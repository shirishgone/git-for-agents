#!/usr/bin/env bash
# Installs `git agent`: works exactly like git, except checkout/switch give each branch
# its own worktree (created on demand, reused if it exists, removed once merged).
set -euo pipefail
BIN="$HOME/.local/bin"
mkdir -p "$BIN"

cat > "$BIN/git-agent" <<'EOF'
#!/usr/bin/env bash
# git agent <any git command>   e.g. git agent checkout -b user/me/fix-abc
set -e
orig=("$@")

# Anything other than checkout/switch is plain git.
case "${1:-}" in checkout|switch) ;; *) exec git "$@" ;; esac

main=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
hook=$(cd "$main" && git rev-parse --path-format=absolute --git-path hooks/reference-transaction)
if [ ! -e "$hook" ]; then
  mkdir -p "$(dirname "$hook")"
  cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
# git-agent: remove worktrees whose branch is merged into the default branch
[ "$1" = committed ] || exit 0
def=$(git symbolic-ref -q --short refs/remotes/origin/HEAD || echo origin/main)
grep -q " refs/remotes/$def\$" || exit 0
main=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
(
  git worktree list --porcelain |
  awk '/^worktree /{sub(/^worktree /,""); p=$0} /^branch /{sub(/^branch refs\/heads\//,""); print p "\t" $0}' |
  while IFS=$'\t' read -r path br; do
    [ "$path" = "$main" ] && continue
    if git merge-base --is-ancestor "$br" "$def" 2>/dev/null; then
      git worktree remove "$path" && git branch -D "$br"   # fully contained in main: safe
    elif { command -v gh >/dev/null && [ "$(gh pr view "$br" --json state -q .state 2>/dev/null)" = MERGED ]; } ||
         { command -v glab >/dev/null && glab mr view "$br" -F json 2>/dev/null | grep -Eq '"state": ?"merged"'; }; then
      git worktree remove "$path" && git branch -d "$br"   # squash-merged: keep branch if it has extra commits
    fi
  done
) >/dev/null 2>&1 &
HOOK

  chmod +x "$hook"
elif ! grep -q "git-agent" "$hook"; then
  echo "git-agent: $hook already exists; auto-cleanup not installed" >&2
fi

# Parse: checkout|switch [-b|-B|-c|-C] <branch> [start-point]; anything else -> plain git
shift; new=""; branch=""; start=""
while [ $# -gt 0 ]; do
  case "$1" in
    -b|-c) new=-b; shift; branch=${1:-} ;;
    -B|-C) new=-B; shift; branch=${1:-} ;;
    -*)    exec git "${orig[@]}" ;;
    *)     if [ -z "$branch" ]; then branch=$1; elif [ -z "$start" ]; then start=$1; else exec git "${orig[@]}"; fi ;;
  esac
  shift || true
done
[ -z "$branch" ] && exec git "${orig[@]}"

open_in() { cd "$1"; echo "git-agent: working in $1" >&2; exec ${GIT_AGENT_CMD:-claude}; }

git -C "$main" fetch -q origin 2>/dev/null || true   # sweeps merged worktrees via hook
sleep 1

if [ -z "$new" ]; then
  [ -n "$start" ] && exec git "${orig[@]}"
  existing=$(git worktree list --porcelain | awk -v b="branch refs/heads/$branch" '/^worktree /{sub(/^worktree /,""); p=$0} $0==b{print p}')
  [ -n "$existing" ] && open_in "$existing"
  git show-ref -q --verify "refs/heads/$branch" || git show-ref -q --verify "refs/remotes/origin/$branch" ||
    exec git "${orig[@]}"                      # not a branch (e.g. a file path): plain git
fi

dir="$(dirname "$main")/$(basename "$main")-wt-${branch//\//-}"
if [ -n "$new" ]; then
  git -C "$main" worktree add "$new" "$branch" "$dir" ${start:+"$start"}
else
  git -C "$main" worktree add "$dir" "$branch"
fi
open_in "$dir"
EOF
chmod +x "$BIN/git-agent"

echo "Installed: $BIN/git-agent"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Add to your shell profile: export PATH=\"$BIN:\$PATH\"" ;; esac
