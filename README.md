# git agent

Run multiple AI agents on the same repo at the same time, each on its own branch, without them stepping on each other.

## The problem

A Git repo has one working folder, so only one branch can be checked out at a time. Two agents (or you and an agent) working on different branches in the same folder overwrite each other's files.

Git worktrees solve this by giving each branch its own folder, but creating and cleaning them up by hand is tedious and easy to forget.

## The solution

`git agent` works exactly like `git`, but `checkout` and `switch` give every branch its own worktree automatically, and merged worktrees are cleaned up for you.

## Install

```bash
bash install-git-agent.sh
```

Requires Git 2.31+. Make sure `~/.local/bin` is on your `PATH`.

## Usage

```bash
git agent checkout -b user/me/fix-abc   # create a new branch in its own worktree
git agent checkout user/me/fix-abc      # open its worktree (created if missing)
git agent pull                          # pull, and delete worktrees of merged branches
```

Every other command (`status`, `commit`, `push`, ...) is plain Git.

Each checkout opens your agent (`claude` by default) inside the worktree. Exit the agent and you are back where you started.

Worktrees are created next to your repo:

```
~/code/repo                        # your main checkout
~/code/repo-wt-user-me-fix-abc     # worktree for user/me/fix-abc
```

## Cleanup rules

- A worktree is removed once its branch is merged into the default branch on the remote.
- Cleanup runs on `git agent pull`, `git agent checkout`, and any `git fetch` / `git pull`.
- Worktrees with uncommitted changes are never removed.
- Squash merges are detected if the `gh` (GitHub) or `glab` (GitLab) CLI is installed and logged in.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `GIT_AGENT_CMD` | `claude` | Command to open in the worktree (e.g. `codex`, `$SHELL`) |

## Limitations

- A script can't change your terminal's current folder, so checkout opens the agent in the worktree rather than moving your shell there.
- If the repo already has a `reference-transaction` hook, auto-cleanup is not installed and a warning is shown.
