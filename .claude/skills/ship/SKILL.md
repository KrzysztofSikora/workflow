---
name: ship
description: Start the autonomous runner for one roadmap item (plan -> plan review -> implement every phase -> mutation -> review and fix -> pull request) in the background, or address the comments on its PR. No questions are asked until the PR.
argument-hint: "<S-01 | change-id | #issue> [--no-mutation] [--no-pr] | pr <number>"
disable-model-invocation: true
---

# Ship one roadmap item

The work itself is done by `.claude/workflow/ship` (or `.claude/workflow/address-pr`), which
runs every step in a fresh headless session. This skill only starts it and reports back, so the
current conversation stays small.

1. Check the preconditions and report any failure to the user instead of starting:
   `git status --porcelain` is empty, `context/roadmap.md` has the item, `CLAUDE.md` has a
   *Gates* table.
2. Start the runner with the Bash tool **in the background** (`run_in_background: true`),
   from the repo root:
   - `$ARGUMENTS` starting with `pr`: `.claude/workflow/address-pr <number>`;
   - otherwise: `.claude/workflow/ship $ARGUMENTS`.
3. Tell the user, in three lines: what is running, that it will not ask anything, and that
   progress is in `.workflow/run-summary.md` (session logs in `.workflow/logs/<change-id>/`).
   Do not poll; you are notified when the command exits.
4. When it exits, read `.workflow/run-summary.md` and report: the PR URL (or why there is
   none), whether it is a draft and why, and the first items of the PR's
   *Needs your decision* section from `context/changes/<change-id>/pr-body.md`.
