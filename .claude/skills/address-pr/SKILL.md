---
name: address-pr
description: Apply the person's review comments on a change PR - switch decisions they overruled, fix what they flagged, answer their questions - and write one reply per comment. Run by .claude/workflow/address-pr.
argument-hint: "<PR number>"
disable-model-invocation: true
---

# Address PR review comments

This is where the decisions deferred to the PR come back. The person has read the PR and
left comments; nobody is watching this session (`.claude/workflow/autonomy.md`). Their
comments are instructions from the owner of the project, and they outrank the agent's earlier
decisions, but not `CLAUDE.md` rules such as "no secrets".

## Input

- `.workflow/pr-$ARGUMENTS/comments.json`: new comments, reviews and inline comments, oldest
  first (`kind`, `author`, `body`, `path`/`line` for inline ones, `url`).
- The change folder `context/changes/<change-id>/` (the branch is `change/<change-id>`):
  `plan.md`, `review.md`, `pr-body.md`; `CLAUDE.md`, `context/lessons.md`.

## Process

1. **Classify each comment:**
   - **decision**: picks an option for a `D-<n>` ("D-3: take B", "use cursor pagination");
   - **finding**: says what to do with an `R<n>` or a deviation ("R4: fix it", "defer R2");
   - **change request**: an inline or general request to change code, tests or docs;
   - **human check result**: a check from the PR's checklist failed or passed;
   - **lessons**: accepts or rejects proposed lessons ("drop the lessons commit");
   - **question**: asks something; answer from the artifacts and the code;
   - **no action**: approval, thanks, or a comment already handled.
2. **Apply, smallest diff first.**
   - *decision:* update the `D-<n>` row (Chosen, Alternatives, `Decided by: user (PR #<n>)`),
     then switch the code. If the switch is larger than one phase's worth of work, add new
     unticked phases to *Progress* with full phase descriptions under *Phases*; the runner
     implements them in fresh sessions. Otherwise do it now.
   - *finding:* fix it, or move it to *Deviations* as `[FOLLOW-UP]`, and update its
     `Decision:` line in `review.md` (`fixed (<hash>) per PR #<n>`, ...).
   - *human check result:* a passed check gets ticked under `## Human checks` in `plan.md`
     with `(confirmed in PR #<n>)`; a failed one is fixed like a change request.
   - *lessons:* accepted → change `Status: proposed ...` to `Status: accepted (PR #<n>)`;
     rejected → `git revert` the `propose lessons` commit.
   - A comment you cannot apply without breaking a rule, or that is ambiguous between options
     with very different costs: do not guess big. Apply the conservative reading if one exists,
     otherwise change nothing, and say so in the reply.
3. **Verify** with the gates from the `CLAUDE.md` *Gates* table. Never weaken a test.
4. **Commit** by explicit path, one commit per comment or group of related comments:
   `<type>(<change-id>): <what> (PR #<n> review)`, plus `Refs #<issue>` when the item has one.
   Commit the updated `plan.md` and `review.md` too. The tree must be clean when you finish.

## Output: `.workflow/pr-<n>/replies.md`

One entry per comment, in order. The runner posts the file as a single PR comment.

```markdown
### Re: <author>, [<kind>](<url>)
> <first line of the comment>

<what you did and why, in one or two sentences> · <commit short hash(es), or "no change">
```

Finish with a line listing the phases you added, if any, so the person knows more commits will
follow in this run.
