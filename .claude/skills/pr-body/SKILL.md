---
name: pr-body
description: Write the pull request description for a change from its artifacts, putting every decision the agent made alone, every open human check and every deviation in front of the reviewer. Writes context/changes/<change-id>/pr-body.md.
argument-hint: "<change-id>"
disable-model-invocation: true
---

# Write the PR description

The run did not stop for a person, so the PR is where the person decides. Write the
description so they can do that in minutes: the things that need their judgement first,
the evidence next, the narrative last. Every statement must come from an artifact or the git
log; invent nothing.

## Input

- `context/changes/$ARGUMENTS/`: `plan.md` (*Decisions*, *Deviations*, *Human checks*,
  *Progress*), `plan-review.md`, `mutation.md`, `review.md`, `evidence/`.
- `.workflow/run-summary.md`: what the runner saw (failed step, stuck reason, draft reason,
  costs).
- `context/roadmap.md` (title, issue number), `git log --oneline <merge-base>..HEAD`.

## Output: `context/changes/<change-id>/pr-body.md`

The first line is the PR title, the rest is the body. Keep the headings; drop a section's
content to "None." when it is empty, never the heading.

```markdown
# <type>(<change-id>): <what the change delivers>

<one paragraph: the roadmap item, what is now possible, and the PRD ACs covered>
Closes #<issue>   <!-- omit the line when the item has no issue -->

> **Status:** <Ready for review | Draft: <failed step / stuck reason / plan review verdict>>

## ⚠ Needs your decision
<!-- Things the agent could not or should not settle alone. Most important first. -->
- **[STUCK]** ... (from Deviations / run summary)
- **D-<n> (costly):** <question> → chose **<option>**. Alternatives: <B: ...>. Switching costs: <files / migration>.
- **[REVIEW]** <deviation>
- **Plan review / review leftovers:** <blocker or major not fixed, with R-id and why>

Reply in a review comment, e.g. `D-3: take B`, `R4: fix it`, `drop the lessons commit`,
then run `.claude/workflow/address-pr <PR number>`.

## Human checks
<!-- Every line from plan.md "## Human checks", unchecked, with how to run it and the evidence link. -->
- [ ] ...

## Other decisions made by the agent (cheap to change)
| ID | Question | Chosen | Alternatives |

## Quality
- Gates: <from review.md>
- Review: <verdict>, round <n>: <fixed n, deferred n, rejected n> (rejected ones listed with reason)
- Mutation: <score before → after, or "skipped: reason">; `bug` mutants: <list or none>
- Proposed lessons: <titles, and the commit to drop to reject them, or none>

## Follow-ups
<[FOLLOW-UP] deviations and deferred findings>

## Commits
<git log --oneline, one line each>

<details><summary>Run</summary>

<run summary: steps, attempts, cost>
</details>
```

## Rules

- Link files with relative paths (`context/changes/<id>/plan.md#decisions`) so they open on
  the PR's branch.
- Quote decisions and findings faithfully; shorten, but do not soften them.
- Do not commit; the runner does.
