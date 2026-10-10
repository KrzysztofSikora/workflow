---
name: fix-review
description: Triage the findings of /review autonomously - fix, defer, reject or turn into a proposed lesson - then commit the fixes. Every choice is recorded on the finding so the PR reviewer can overrule it.
argument-hint: "<change-id>"
disable-model-invocation: true
---

# Act on review findings

This step runs without a person (`.claude/workflow/autonomy.md`). In the interactive workflow
the user triaged each finding; here you do it, and the PR shows what you chose.

## Input

- `context/changes/$ARGUMENTS/review.md`: every finding with `- Decision: open`.
- `context/changes/$ARGUMENTS/plan.md`, `CLAUDE.md` (*Gates*), `context/lessons.md`.

## Triage

Re-verify each open finding in the code first. Then decide:

| Finding | Decision |
|---------|----------|
| `blocker` | **fix**. If you cannot fix it within the change's scope, follow `autonomy.md` section 5. |
| `major`, effort small or medium, inside the change's files | **fix** |
| `major`, effort large or outside the change's scope | **defer**: add a `[FOLLOW-UP]` deviation to `plan.md` |
| `minor`, small and local | **fix** |
| `minor`, otherwise | **defer** |
| Re-verification shows the finding is wrong | **reject**, with the evidence in one line |

A fix that would change a `costly` decision (`D-<n>` with reversal `costly`) is not yours to
make silently: implement the reviewer's suggestion only if it keeps the decision's contract,
otherwise defer it and add a `[REVIEW]` deviation naming the D-ID.

## Fix

- Fix findings one at a time, smallest diff that resolves the problem, with a test where the
  finding is about behaviour.
- After all fixes run the gates from the `CLAUDE.md` *Gates* table. Never weaken a test.
- Commit by explicit path. One commit per finding, or one per group of related findings:
  `fix(<change-id>): <what> (R<n>)`, plus `Refs #<issue>` when the item has an issue.

## Lessons

For each finding with a lesson candidate that you judge recurring (it would apply to other
changes, not just this diff), append it to `context/lessons.md` in the format below, marked as
proposed. Commit lesson proposals separately (`docs(<change-id>): propose lessons`), so the
PR reviewer can drop that single commit to reject them.

```markdown
## <rule, as an imperative sentence>
- Why: <the failure it prevents>
- Seen in: <change-id>, R<n>
- Scope: <paths or layers it applies to>
- Status: proposed in the PR for <change-id>
```

## Record

Update each finding's `Decision:` line in `review.md`:

- `- Decision: fixed (<short hash>)`
- `- Decision: deferred (<why>; FOLLOW-UP in plan.md)`
- `- Decision: rejected (<evidence>)`
- add `+ lesson proposed` to any of the above when you appended a lesson.

Commit `review.md` and `plan.md` (`docs(<change-id>): triage review round <n>`). The tree must
be clean when you finish, and no finding may still say `Decision: open`.
