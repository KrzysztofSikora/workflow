---
name: implement
description: Implement exactly one phase of a change plan, verify it with the gates, prepare its human checks for the PR, and commit the phase autonomously on the change branch. Stops at the phase boundary.
argument-hint: "<change-id> [phase-number]"
disable-model-invocation: true
---

# Implement one phase

This step runs without a person (`.claude/workflow/autonomy.md`). It ends with exactly one new
phase committed and ticked, or with a `[STUCK]` entry.

## Input

- `$ARGUMENTS`: the change-id and optionally a phase number. With no phase given, take the
  first unticked phase in *Progress*.
- `context/changes/<change-id>/plan.md`, and `plan-review.md` if present: treat its open
  `minor` findings and its *Decisions the PR reviewer should look at* as things to be careful
  with.
- `CLAUDE.md` (the *Gates* table lists the commands you run) and `context/lessons.md`
  (binding rules).

## Process

1. **Start.** Restate the phase goal and its checks in two lines. Set the roadmap status to
   `in-progress`. Run `git status` and `git branch --show-current`: you must be on
   `change/<change-id>` with a clean tree. If not, follow `autonomy.md` section 5.
2. **Test first where it pays.** For domain logic, validation and adapters, write the failing
   test from the AC, run it, and watch it fail for the right reason.
3. **Build** the smallest change that makes the tests pass and matches the plan's design.
   Keep a running list of every file you create or edit.
4. **Run the agent checks**, then every gate in the `CLAUDE.md` *Gates* table that does not
   need services you cannot start. Fix every failure at its cause. Never weaken, skip or delete
   a test to get green. Two honest failed attempts at the same gate means you are stuck.
5. **Handle drift.** If reality differs from the plan, describe it in three lines (plan says,
   code shows, consequence), act, and log it under *Deviations* as `[minor]`, `[REVIEW]` or
   `[FOLLOW-UP]` (`autonomy.md` section 3). A choice that the plan did not foresee gets a new
   `D-<n>` row in *Decisions*.
6. **Prepare the human checks.** Do not wait for them and never tick them. For each human check
   of the phase, add an open checkbox under `## Human checks` in `plan.md`:
   `- [ ] (Phase n) <what to look at> — run: <command or URL, sample input> — evidence: <path or "none">`.
   Produce the evidence you can yourself (command output, an API response, a Playwright
   screenshot) under `context/changes/<change-id>/evidence/`.
7. **Commit the phase.**
   - Tick the phase in *Progress* (`- [x] Phase n: <name>`) before committing, so the tick is
     part of the phase commit.
   - Stage, by explicit path, only the files on your list from step 3, the evidence files,
     `plan.md` and `context/roadmap.md`. Bulk staging is off-limits.
   - Message: `<type>(<change-id>): <what the phase delivers>` (Conventional Commits), a body
     line `Phase <n> of <total>`, and `Refs #<issue>` when the roadmap item has an issue.
     The PR, not a commit, closes the issue.
   - Never use `--no-verify`. If a hook fails, fix the cause and commit again.
   - The tree must be clean afterwards.

## Report

- What changed, file by file, one line each.
- Each check and its result.
- New decisions and deviations, if any.

## Rules

- One phase per run. Do not start the next phase; the runner starts a fresh session for it.
- No drive-by refactors outside the phase's files. Log them as `[FOLLOW-UP]`.
- No secrets in code, tests, logs, evidence or commits.
