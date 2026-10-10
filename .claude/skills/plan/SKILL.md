---
name: plan
description: Research the codebase and docs for one roadmap item, decide the open design choices autonomously (recorded with alternatives for review in the PR), and write a phased, verifiable implementation plan in context/changes/<change-id>/plan.md. Writes no production code.
argument-hint: "<change-id | roadmap ID> [revise]"
disable-model-invocation: true
---

# Plan one change

This step runs without a person. Read `.claude/workflow/autonomy.md` first; it overrides any
habit of asking for confirmation.

## Input

- `$ARGUMENTS`: a change-id or roadmap ID (e.g. `S-01`), optionally followed by `revise`.
  Resolve it in `context/roadmap.md`. If the item does not exist, write `.workflow/stuck`
  with that reason and stop.
- `context/prd.md`, `context/tech-stack.md`, `CLAUDE.md`, and if present
  `context/test-plan.md` and `context/lessons.md`. Treat every lesson as a constraint on the
  design. The roadmap item's *Decided up front* answers are the user's and are final.
- **`revise` mode:** `plan.md` and `plan-review.md` exist. Address every `blocker` and `major`
  finding of the review: change the plan, or add a row to *Decisions* that explains why the
  finding does not apply. Keep ticked progress. Add a line per finding under
  *Review response*. Then stop; do not rewrite parts the review did not touch.
- An existing `plan.md` without `revise`: keep the ticked progress and complete only what is
  missing.

## Process

### 1. Research

- **Inside the repo:** find the files, patterns and conventions this change touches. For broad
  searches, delegate to an Explore subagent if you can, and ask for conclusions with
  `file:line` references, not file dumps.
- **Outside the repo:** check library APIs and third-party behaviour with context7 or the
  official docs. Record anything surprising under *Findings*.

### 2. Decide

List the choices that research could not settle and that change the outcome: behaviour on
failure, data shape, API contract, UX. Leave out anything the PRD, tech stack, lessons, the
roadmap's *Decided up front* or existing code already decide. For each remaining choice:

- weigh 2-3 options; name the strongest argument against the one you prefer;
- pick using the order in `autonomy.md` section 1, favouring the option that is cheapest to
  reverse;
- add a `D-<n>` row to *Decisions* with the alternatives, what each would buy, the reason and
  the reversal cost (`cheap` / `costly`).

Never record a question as open. If a choice truly cannot be made without the user (the PRD
contradicts itself, or every option breaks a lesson), follow `autonomy.md` section 5.

### 3. Shape the phases

Choose phases that each:
- leave the repo building, with the gates in `CLAUDE.md` green;
- are small enough to review as one diff (aim for under ~400 changed lines);
- put every `costly` decision in as few files as possible, so the PR reviewer can swap it.

### 4. Write the plan

Each phase must name the files it touches, with the intent of each change and the contract it
affects (a signature, schema field, route or invariant), and split its exit criteria into
**agent checks** (commands the agent runs) and **human checks** (things only a person can
judge: UI, real third-party behaviour, wording). Human checks do not block the run: they
become checkboxes in the PR, so make each one concrete enough to do in two minutes.

Set the roadmap status to `planned`. Do not commit; the runner commits the plan.

## Output: `context/changes/<change-id>/plan.md`

```markdown
# Plan: <change-id> (<roadmap ID>)

## Goal and end state
<what is observably true when done; refer to PRD AC IDs>

## Scope
- In:
- Out:

## Findings
<current state with file:line refs; library and API facts with sources>

## Decisions
| ID | Question | Chosen | Alternatives (and what they would buy) | Why | Reversal | Decided by |
|----|----------|--------|----------------------------------------|-----|----------|------------|

## Design
<interfaces, schema, data flow, error model>

## Phases
### Phase 1: <name>
- Files:
  - `path/file.ts`: <intent>. Contract: <signature, field or invariant>
- Proves: <AC IDs and the test level used>
- Agent checks: <commands from the CLAUDE.md Gates table, scoped where possible>
- Human checks: <or "none">

## Risks and unknowns

## Progress
<!-- One line per phase. /implement ticks it in the phase's own commit. -->
- [ ] Phase 1: <name>
- [ ] Phase 2: <name>

## Human checks
<!-- Filled by /implement: one open checkbox per human check, with how to run it and evidence. -->

## Deviations
<!-- [minor] / [REVIEW] / [FOLLOW-UP] / [STUCK] entries, see autonomy.md section 3 -->

## Review response
<!-- revise mode only: one line per plan-review finding and what changed -->
```

## Rules

- Only short snippets, and only where prose would be ambiguous (a regex, an unusual API call).
- Every PRD AC this item covers must be proved by a test in some phase.
- Prefer the simplest design that meets the ACs. Name any pattern you introduce and say why.
- Keep the `## Progress` line format exactly: the runner counts `- [ ] Phase` lines.
