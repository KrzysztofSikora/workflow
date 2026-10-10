---
name: mutation
description: Measure whether the tests of a change actually defend its logic, using mutation testing on a narrow set of risk-critical modules. Triages every surviving mutant and strengthens assertions only where a real bug would slip through. Writes context/changes/<change-id>/mutation.md.
argument-hint: "<change-id> | <path[:start-end]>"
disable-model-invocation: true
---

# Mutation check

This step runs without a person (`.claude/workflow/autonomy.md`).

Coverage tells you that code ran during tests. Mutation testing tells you whether the tests
would notice if that code were wrong. The tool (e.g. StrykerJS, mutmut, PIT) makes many small
deliberate faults (flips `>` to `>=`, negates a condition, empties a block, swaps `&&` for
`||`) and reruns the relevant tests against each one:

- **killed:** a test failed, so the fault was caught.
- **survived:** every test still passed, so no assertion guards that spot.
- **no coverage:** no test even executed the code.
- **timeout:** the fault hung the tests. It counts as caught.
- **compile error / ignored:** excluded from the score.

`score = (killed + timeout) / (killed + timeout + survived + no coverage)`

The score is only a pointer. The useful output is the list of surviving mutants and a
decision on each.

## Input

- `$ARGUMENTS`: a change-id (its changed logic files are the targets), or a file path with an
  optional line range.
- The `mutation` row of the *Gates* table in `CLAUDE.md`: the command and how to scope it to
  one file.
- `context/test-plan.md`, section *Mutation targets*, if present.
- `context/changes/<change-id>/plan.md` for the behaviours the change must guarantee.
- `context/lessons.md` (binding rules for mutation runs and test changes).

## 1. Choose targets

Mutate only code where a silent bug hurts: domain rules, input validation, mapping of
third-party responses, error mapping, and query building (filters, sorting). Skip wiring,
generated code, configuration, pure presentation components and constants.
For a change-id, intersect `git diff --name-only <base>...HEAD` (base: the merge base with the
default branch) with that list, and list the targets with one line of reason each.

If there are no targets, write `mutation.md` with `Skipped: <reason>` and stop.

## 2. The tool must already be set up

Setting up a mutation tool is a project decision, made in `/test-plan` with the user. If
`CLAUDE.md` has no `mutation` gate or the tool is not installed, do not install or configure
anything: write `mutation.md` with `Skipped: no mutation tool configured` and add a
`[FOLLOW-UP]` deviation to `plan.md`.

## 3. Run

Run the `mutation` command scoped to the targets. If the tool reports that no tests ran for a
file, that file has no fast tests: record it as a test-plan gap. Do not widen the scope to make
the error go away. Keep runs narrow; never run on the whole repo.

## 4. Triage every surviving and uncovered mutant

Read the report. For each mutant, ask: **would a real bug of this shape hurt a user or break a
requirement?** Then give it one decision:

| Decision | When | Action |
|----------|------|--------|
| `strengthen` | The fault changes observable behaviour that a requirement or AC covers | Add or sharpen an assertion on that behaviour |
| `equivalent` | The fault cannot change any observable outcome | No test. Explain in one line |
| `accept` | The behaviour changes, but pinning it would only mirror the implementation (log text, exact wording, incidental object shape) | No test. Explain in one line |
| `bug` | The mutant shows the production code is already wrong | Do not fix it here. Record it, and add a `[REVIEW]` deviation to `plan.md` so it reaches `/review` and the PR |

Also flag **dead-weight tests**: tests that kill nothing beyond what other tests already
kill, usually copies with one changed input. Suggest folding them into one parametrised test.

## 5. Strengthen and re-run

- Write assertions about behaviour as seen at the boundary: return values, the API response,
  the stored row, the error code. Never assert on private details just to kill a mutant.
- Prefer extending an existing test or a parametrised table over a new copy of the setup.
- Never edit production code in this skill.
- Re-run on the same targets. Record the score before and after.
- Run the test gates, then commit the test changes by explicit path:
  `test(<change-id>): strengthen assertions from mutation check`. The runner commits
  `mutation.md` itself.

## Output: `context/changes/<change-id>/mutation.md`

```markdown
# Mutation check: <change-id>

Targets: <files and line ranges> · Tests: <config used>
Score: <before>% -> <after>% (killed / survived / no coverage / timeout)

## Mutants
| File:line | Mutator | Change | Decision | Note / test added |
|-----------|---------|--------|----------|-------------------|

## Dead-weight tests
## Gaps for the test plan
## Proposed lessons
<a recurring weakness worth a rule in context/lessons.md, or "none">
```

## Rules

- Do not chase 100%. A survivor you decided to accept, with a reason, is a valid result.
- Do not change the CI threshold.
