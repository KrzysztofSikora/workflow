# Autonomy policy

Every per-change skill (`/plan`, `/plan-review`, `/implement`, `/mutation`, `/review`,
`/fix-review`, `/pr-body`, `/address-pr`) runs without a person in the loop. Nobody will answer
a question until the pull request is open. The PR is where a person accepts, changes or
rejects what you decided. So your job is to make **good, visible, cheap-to-change** decisions,
not to wait for permission.

## 1. Decide, never ask

Do not ask the user anything, and do not end your turn with a question or "shall I proceed?".
`AskUserQuestion` is disabled during a run. When a choice is open, settle it in this order:

1. `context/lessons.md` (binding rules);
2. `context/prd.md`, `context/tech-stack.md`, `context/test-plan.md`, `CLAUDE.md`;
3. what the existing code already does (follow its conventions);
4. the option that is simplest, most conventional and **cheapest to reverse**.

## 2. Record every decision where the PR can show it

Write each decision into the *Decisions* table of `context/changes/<change-id>/plan.md`:

```markdown
| ID | Question | Chosen | Alternatives (and what they would buy) | Why | Reversal | Decided by |
|----|----------|--------|----------------------------------------|-----|----------|------------|
| D-1 | ... | ... | B: ...; C: ... | ... | cheap | agent |
```

- **ID:** `D-<n>`, never reused. The person refers to it in PR comments ("D-3: take B").
- **Reversal:** `cheap` (local code, easy to swap later) or `costly`. Treat a decision as
  `costly` if it touches any of the following: persisted data shape or migrations, a public
  API or GraphQL contract, auth or security, deleting or rewriting data, a new runtime
  dependency, calls that cost money or hit a third party, or user-facing wording that a PRD
  AC fixes.
- **Decided by:** `agent`, `research`, `lesson`, `prd`, or `user (PR #n)` after the person
  decided in review.

A `costly` decision is still yours to make, but:
- choose the option that keeps the most doors open (additive over destructive, nullable over
  required, internal over public);
- keep it in as few files as possible, so switching to an alternative touches one place;
- it appears at the top of the PR under **Decisions to confirm**.

## 3. Deviations from the plan

If reality differs from the plan, describe it in three lines (plan says, code shows,
consequence), act, and log it under *Deviations* in `plan.md`:

- `- [minor] ...`: small and local. Just do it.
- `- [REVIEW] ...`: it changes the scope, the design, a contract or a later phase. Do the
  most conservative thing that keeps the build green, and say what the alternative was. It is
  listed in the PR.
- `- [FOLLOW-UP] ...`: something worth doing outside this change. Do not do it now.

## 4. Things a run never does

- Commit on, push to, or merge into the default branch. Work only on `change/<change-id>`.
- `git push --force`, `--no-verify`, `git reset --hard`, `git clean`, bulk staging
  (`git add -A`, `git add .`), `gh pr merge`.
- Weaken, skip or delete a test to get to green. Edit secrets or `.env`.
- Set up new tools, services or paid accounts. Call real third-party APIs from tests.
- Expand scope beyond the roadmap item. Record extra ideas as `[FOLLOW-UP]`.

Hooks in `.claude/settings.json` enforce the git rules. Do not try to work around a hook that
denies a command; treat the denial as the answer.

## 5. When you are stuck

You are stuck when you cannot finish without breaking a rule above, or when the same gate
fails after two honest attempts at fixing its cause. Then:

1. leave the tree in a committed or clean state if you can (commit the work in progress as
   `wip(<change-id>): <what>`, never with failing hooks bypassed);
2. add `- [STUCK] <what blocks you, what you tried, what a person must decide>` under
   *Deviations*;
3. write the same one-paragraph reason to `.workflow/stuck` and end your turn.

The runner turns that into a draft PR, so the decision still reaches a person, just at the
PR stage.

## 6. Human checks

Things only a person can judge (a UI look, real third-party behaviour, wording) are never
ticked by you. For each one, collect what makes the person's check fast: the exact command or
URL, sample input, and evidence you can produce yourself (command output, a Playwright
screenshot) saved under `context/changes/<change-id>/evidence/`. Prefer text. Keep each image
under 300 KB. The PR lists every human check as an open checkbox.

## 7. Finish the step

The runner checks the step's artifact when you stop. If it is missing or incomplete, you will
be sent back to finish. End with a short report: what you did, the checks and their results,
and the decisions and deviations you added.
