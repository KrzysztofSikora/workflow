# Defaults for .claude/workflow/ship and address-pr. Override any of them in the environment.

# Permission mode for the headless sessions. `auto` lets a classifier approve tool calls;
# anything it would ask about is denied (--permission-prompts none), never prompted.
# Use `acceptEdits` together with a `permissions.allow` list in .claude/settings.json if auto
# mode is not available on your plan. `bypassPermissions` only inside a disposable container.
: "${WORKFLOW_PERMISSION_MODE:=auto}"

# Optional: model alias or id, and a dollar cap per step (API-key auth only).
: "${WORKFLOW_MODEL:=}"
: "${WORKFLOW_STEP_BUDGET_USD:=}"

# Loop limits. When a limit is hit the run does not stop for a person: it opens a draft PR.
: "${WORKFLOW_PLAN_REVIEW_ROUNDS:=2}"   # plan-review / plan-revise rounds
: "${WORKFLOW_REVIEW_ROUNDS:=2}"        # review / fix-review rounds
: "${WORKFLOW_MAX_PHASES:=12}"          # implement sessions per change
: "${WORKFLOW_STEP_RETRIES:=1}"         # extra sessions when a step leaves its artifact incomplete
