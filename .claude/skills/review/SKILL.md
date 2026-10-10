---
name: review
description: Independent code review of a finished change against its plan and the PRD. Maps planned files to the actual diff, checks quality, safety and the agent's own decisions, reports at most 10 verified findings, and saves context/changes/<change-id>/review.md. Runs in a fresh context.
argument-hint: "<change-id> [base-ref]"
disable-model-invocation: true
context: fork
---

# Review a change

You are reviewing someone else's diff. Report only problems you have confirmed in the code.
Do not modify code. Nobody will answer questions during this run
(`.claude/workflow/autonomy.md`): `/fix-review` acts on your findings, and the person sees
your review in the pull request.

## Input

- `$ARGUMENTS`: the change-id and optionally a base ref. The default is
  `git merge-base HEAD <default branch>` (`origin/HEAD`, else `main`, else `master`).
- The diff: `git diff <base>...HEAD` plus uncommitted changes.
- `context/changes/<change-id>/plan.md` (including *Decisions*, *Deviations* and
  *Human checks*), `context/prd.md`, `CLAUDE.md`, `context/lessons.md`, and
  `context/changes/<change-id>/mutation.md` if present.
- A previous `review.md`, if present: this is a re-review after `/fix-review`. Check each
  earlier finding marked `fixed` really is fixed, and keep the numbering going (R11, R12...).

## Process

1. **Compare the plan with the diff.** Build a table of every file named in the plan and every
   file in the diff, with one status each:
   - `done`: in both, and the change matches the stated intent;
   - `diverged`: in both, but it does something different from the plan (and is not logged
     under *Deviations*);
   - `absent`: planned but not changed;
   - `unplanned`: changed but not in the plan.
   Confirm `diverged` by reading the code, not just the file name.
2. **Read for quality.** For every changed function, open the surrounding code and look at:
   - **Correctness:** ACs met, edge cases, error paths, data integrity.
   - **Design:** layering, dependency direction, cohesion, justified patterns, no premature
     abstraction, consistency with neighbouring modules.
   - **Safety:** input validation at the boundary, no secrets, no injection, external failures
     mapped to clear errors, nothing swallowed.
   - **Tests:** they assert behaviour (not mocks), cover failure paths and are deterministic.
     If `mutation.md` exists, check that every `accept` or `equivalent` decision is plausible.
     A survivor on a mutation target from the test plan with no decision is at least `major`.
     A mutation `bug` that is still in the code is a `blocker`.
   - **Simplicity:** naming, function size, duplication, dead code.
   - **Agent decisions:** each `costly` decision is implemented in one place and could be
     swapped for its alternative as the plan claims. A `[REVIEW]` deviation that changed a
     contract without a *Decisions* row is `major`.
   - **Lessons:** any breach of `context/lessons.md` is at least `major`.
   For a diff larger than about 15 files, you may split the reading between two Explore
   subagents (backend and frontend) and merge their notes yourself.
3. **Verify every candidate.** Re-read the path, or run a test or quick script. Drop anything
   you cannot demonstrate.
4. **Run the gates** from the `CLAUDE.md` *Gates* table. Record the results.
5. **Rank and trim.** Order findings by severity. Merge related ones. Keep at most 10.

## Output: `context/changes/<change-id>/review.md`

```markdown
# Review: <change-id>

Verdict: APPROVE | APPROVE WITH FOLLOW-UPS | CHANGES REQUESTED
Gates: <gate> <ok/fail>, ... · Round: <n>

## Plan vs diff
| File | Status | Note |

## Areas
| Area | Result (ok / concern / fail) | One-line reason |
<!-- Correctness, Design, Safety, Tests, Simplicity, Plan fidelity, Agent decisions -->

## Findings
### R1: <short title>
- Severity: blocker | major | minor
- Where: `file:line`
- Problem: <what is wrong, with evidence>
- Fix: <the change you suggest; add a second option only if there is a real trade-off>
- Effort: small | medium | large
- Lesson candidate: <an imperative rule if this looks like a recurring problem, or "no">
- Decision: open
```

Severity: **blocker** means wrong behaviour, a security issue or failing gates; **major** is a
real maintainability or correctness risk; **minor** is worth fixing but safe to defer.
Style-only remarks are not findings.

The verdict is CHANGES REQUESTED if any blocker exists, APPROVE WITH FOLLOW-UPS if there are
majors, and APPROVE otherwise. Set the roadmap status to `review`.

## Rules

- Keep the `Verdict:` and `- Decision: open` lines exactly in the format above; the runner
  reads them.
- Return a short summary to the caller: the verdict, the gates, and a one-line list of the
  findings.
