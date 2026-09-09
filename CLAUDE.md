# Project instructions for Claude Code

Repo-level guidance for any Claude Code session working on this project.
See `README.md` for application setup; this file covers how to work with
this repo's git/worktree layout safely.

## Background: the incident this file exists to prevent

PR #5 was developed in a linked worktree at `.claude/worktrees/online-store`.
Two things went wrong before it was caught:

1. `.claude/worktrees/online-store` got committed into root's history as a
   submodule-style gitlink (`160000` mode), most likely from a `git add -A`
   run from repo root while the worktree existed underneath it. Every
   commit on the worktree branch after that then showed up in root as a
   "modified submodule," which is confusing noise unrelated to the actual
   change.
2. After PR #5 was merged on GitHub, root's local `main` had not pulled the
   merge — so root's working tree looked like the feature was "missing,"
   when it had actually already landed upstream and root was just behind.

Both were root-caused and fixed (see commits `9e073cb` and the fast-forward
that preceded it). The safeguards below exist so neither recurs.

## 1. `.claude/worktrees/` is gitignored

`.gitignore` contains:

```
# Ignore Claude Code worktrees (linked working trees, not part of history).
/.claude/worktrees/
```

This is committed. To re-verify it's actually in effect: from repo root,
create a fresh worktree (e.g. `git worktree add .claude/worktrees/tmp-check
-b tmp-check`), then run `git status` from repo root — nothing under
`.claude/worktrees/` should appear as untracked or trackable. Clean up
with `git worktree remove .claude/worktrees/tmp-check` and
`git branch -D tmp-check` afterward.

## 2. Pre-merge checklist for any PR out of a `.claude/worktrees/*` session

Before merging a PR that was developed in a linked worktree, verify:

- The PR's file list contains only expected project paths (`app/`,
  `spec/`, `config/`, `db/`, etc.) — no path containing
  `.claude/worktrees/`.
- `git log --stat <branch> | grep '.claude/worktrees'` returns nothing.
- The worktree branch was committed to from inside the worktree
  directory, not from repo root. A stray `git add -A` run from root
  while a worktree exists underneath it is the likely cause of
  gitlink/nested-path pollution — see the incident above.

## 3. Keep root `main` in sync

Before starting any new worktree-based session, and before concluding
"the code isn't in root yet, something's wrong":

- Run `git fetch origin` and `git status` from repo root first.
- Check whether root `main` is simply behind `origin/main` (as happened
  with PR #5 — it was already merged upstream, root just hadn't pulled)
  before concluding files are misplaced or missing.
- If root is behind and the branch is a clean ancestor, fast-forward
  (`git pull` or `git merge --ff-only origin/main`) rather than
  investigating a "bug" that's actually just a stale local branch.

## 4. After merging and cleaning up a worktree

Once a worktree's branch is fully merged into `main`:

- Remove the worktree: `git worktree remove <path>`.
- Delete the now-merged local branch: `git branch -d <branch>` (safe —
  `-d` refuses if it isn't actually merged).
- Confirm `bundle check` and the full test suite pass from repo root,
  not just from inside the worktree, before considering the feature
  done — the two can drift (different `Gemfile.lock` resolution,
  different `config/database.yml` state, etc.).
