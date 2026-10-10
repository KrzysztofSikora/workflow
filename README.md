# Autonomous change workflow for Claude Code

A spec-driven workflow in which **each roadmap item runs from plan to pull request without
stopping for a person**. Every decision the agent would otherwise ask about is made, recorded
with its alternatives and its reversal cost, and put in front of the person **in the PR**.
The person decides there, and one command applies those decisions.

It grew out of an interactive version of the same workflow
(`/plan → /plan-review → /implement → /mutation → /review`), where each step waited for the
user. The project-level steps stay interactive; the per-change loop no longer stops.

```
once per project (interactive, the user decides)
  /shape ─▶ /prd ─▶ /tech-stack ─▶ /roadmap ─▶ /test-plan
                                      │   (costly questions per item are settled here:
                                      │    "Decided up front")
per roadmap item (autonomous)         ▼
  .claude/workflow/ship S-01
    /plan ─▶ /plan-review ⟲ /plan revise      (max 2 rounds, then a draft PR with the plan)
          ─▶ /implement × phases              (fresh session per phase, one commit each)
          ─▶ /mutation
          ─▶ /review ⟲ /fix-review            (max 2 rounds)
          ─▶ /pr-body ─▶ git push ─▶ gh pr create
                                      │
the person, in the PR                 ▼
  reads "Needs your decision", ticks human checks, comments "D-3: take B", "R4: fix it"
                                      │
  .claude/workflow/address-pr 42  ────┘  applies the comments, re-reviews, replies, updates the PR
```

## Where the human gates went

| Interactive workflow | Autonomous workflow |
|----------------------|---------------------|
| `/plan` asks up to 6 questions | The agent decides; each choice is a `D-n` row with alternatives and `cheap`/`costly` reversal. Costly questions can be settled earlier, in `/roadmap` (*Decided up front*). |
| `/plan` waits for agreement on the phases | No wait. The plan and the plan review are in the PR. |
| `/plan-review` says NEEDS CHANGES → the user triages | `/plan revise` addresses the findings and the review runs again. If blockers remain after 2 rounds, a draft PR with the plan only is opened. |
| `/implement` asks about drift | `[minor]` is done, `[REVIEW]` is done conservatively and listed in the PR, `[FOLLOW-UP]` is noted. |
| `/implement` waits for human checks | Each check becomes an open checkbox in the PR, with how to run it and the evidence the agent collected (`evidence/`). |
| `/implement` asks to approve the commit | The phase is committed on `change/<id>`; the git guard hook forbids pushing, merging, bulk staging and `--no-verify`. |
| `/mutation` asks to set up Stryker; stops on a `bug` mutant | The tool must be set up in `/test-plan`. A `bug` mutant becomes a `[REVIEW]` deviation and reaches the review and the PR. |
| `/review` findings → the user decides fix / defer / reject / rule | `/fix-review` triages them with a fixed policy (blockers always fixed); proposed lessons go into one separate commit you can drop. |
| — | Stuck agent (`.workflow/stuck`): the run still ends with a draft PR that says what is blocked. |

The rules every autonomous step follows are in `.claude/workflow/autonomy.md`.

## How it keeps going

- **Runner, not one long chat.** `.claude/workflow/ship` (bash) runs every step as a fresh
  `claude -p "/<skill> <id>"` session, with `--permission-prompts none` (nothing can prompt)
  and `--disallowedTools AskUserQuestion`. Context never runs out, and a crash resumes from
  the artifacts: re-run the same command.
- **Artifacts are the state.** The runner reads progress from `plan.md` (`- [x] Phase`),
  verdicts from `plan-review.md` / `review.md`, and open findings (`Decision: open`).
  `wf.py check <step>` decides whether a step is done.
- **Stop hook.** If a session tries to end before its step is done (or ends with a question),
  the hook sends it back with what is missing, up to 3 times. Then the runner retries the
  step once in a fresh session, and finally gives up with a draft PR.
- **PreToolUse hook.** Denies `AskUserQuestion` ("decide and record it") and risky git
  commands. Both hooks act only in sessions started by the runner (`WORKFLOW_RUN`), so your
  own interactive sessions are unaffected.
- **Draft vs ready.** The PR is a draft when a step failed, the agent got stuck, the plan
  review never reached READY, or review findings are still open. Otherwise it is ready for
  review.

## Install

```bash
./install.sh /path/to/repo            # skills, runner, hooks, .gitignore, CLAUDE.md template
./install.sh /path/to/repo --github   # also .github/workflows/agent.yml
```

Then, in the target repo:

1. Fill in the **Gates** table in `CLAUDE.md`. The autonomous skills run exactly those commands.
2. Run the project steps once, interactively: `/shape <brief>`, `/prd`, `/tech-stack`,
   `/roadmap`, `/test-plan`.
3. Ship an item: `.claude/workflow/ship S-01` in a terminal, or `/ship S-01` inside Claude Code
   (it starts the runner in the background and reports when the PR is open).
4. Review the PR, then `.claude/workflow/address-pr <n>` (or `/ship pr <n>`).

Requirements: `claude`, `git`, `python3`; `gh` (authenticated) and an `origin` remote to open
PRs. Without them the description is left in `context/changes/<id>/pr-body.md`.

## Configuration (`.claude/workflow/config.sh`, overridable by env)

| Variable | Default | Meaning |
|----------|---------|---------|
| `WORKFLOW_PERMISSION_MODE` | `auto` | Permission mode of the headless sessions. Use `acceptEdits` plus a `permissions.allow` list if auto mode is not available; `bypassPermissions` only in a disposable container. |
| `WORKFLOW_MODEL` | – | Model for every step. |
| `WORKFLOW_STEP_BUDGET_USD` | – | Spend cap per session (API key auth). |
| `WORKFLOW_PLAN_REVIEW_ROUNDS` | 2 | Plan review rounds before a plan-only draft PR. |
| `WORKFLOW_REVIEW_ROUNDS` | 2 | Review / fix rounds. |
| `WORKFLOW_MAX_PHASES` | 12 | Implement sessions per change. |
| `WORKFLOW_STEP_RETRIES` | 1 | Fresh sessions when a step's artifact is incomplete. |

## Files

```
.claude/
  settings.json            hooks (PreToolUse: no questions, git guard; Stop: step guard)
  workflow/
    autonomy.md            decision policy for every autonomous step
    ship, address-pr       runners
    lib.sh, config.sh      shared runner code, defaults
    wf.py                  state from artifacts, step checks, hook entry points
  skills/
    shape prd tech-stack roadmap test-plan     interactive, once per project
    plan plan-review implement mutation review autonomous, per change
    fix-review pr-body address-pr              autonomous, new
    ship                                       starts a runner from inside Claude Code
templates/
  CLAUDE.md                project memory with the Gates table
  github/agent.yml         GitHub Actions: label an issue `agent:ship`, comment `/address` on the PR
install.sh
```

Runtime state (gitignored): `.workflow/run.json` (active run), `.workflow/run-summary.md`,
`.workflow/logs/<change-id>/NN-<step>.jsonl` (full session transcripts, stream-json),
`.workflow/pr-<n>/` (comments and replies).

## Things to know

- **The run uses the working tree.** It switches to `change/<id>` and commits there. Keep
  working in another clone or `git worktree` while it runs.
- **Cost.** One item takes roughly 8–15 sessions (plan, 1–2 plan reviews, one per phase,
  mutation, 1–2 reviews and fixes, PR body). The run summary lists the cost of each.
- **Wrong early decisions are the main risk**: everything after the plan builds on them.
  Settle the expensive ones in `/roadmap` (*Decided up front*), keep phases small, and read
  the PR's *Needs your decision* section before the code.
- **The hooks are guard rails, not a sandbox.** The git rules match command text; the
  permission mode and, ideally, a container are the real boundary.
