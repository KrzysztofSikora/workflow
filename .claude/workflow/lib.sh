# Shared by .claude/workflow/ship and .claude/workflow/address-pr. Source it from the repo root.
# shellcheck shell=bash

HERE=.claude/workflow
WF="python3 $HERE/wf.py"
# shellcheck source=config.sh
source "$HERE/config.sh"

die() { echo "$(basename "$0"): $*" >&2; exit 1; }
note() { echo "[$(basename "$0") $(date +%H:%M:%S)] $*" | tee -a "$SUMMARY" >&2; }

# begin_run <change-id> <title line>: branch must already be checked out.
begin_run() {
  CHANGE=$1
  BRANCH=$(git branch --show-current)
  LOGS=.workflow/logs/$CHANGE
  SUMMARY=.workflow/run-summary.md
  mkdir -p "$LOGS" "context/changes/$CHANGE"
  rm -f .workflow/stuck
  printf '# %s\n\nBranch: %s · Started: %s\n\n' "$2" "$BRANCH" "$(date -Iseconds)" > "$SUMMARY"
  N=$(find "$LOGS" -name '*.jsonl' | wc -l)
  FAILED=""
  $WF run start "$CHANGE" "$BRANCH"
  export WORKFLOW_RUN=$CHANGE   # hooks act only in sessions that inherit this
  trap '$WF run end' EXIT

  CLAUDE_ARGS=(--permission-mode "$WORKFLOW_PERMISSION_MODE" --permission-prompts none
    --disallowedTools AskUserQuestion --output-format stream-json --verbose
    --append-system-prompt "Autonomous run of change '$CHANGE' on branch '$BRANCH'. Nobody will answer questions until the pull request. Follow .claude/workflow/autonomy.md.")
  [ -z "$WORKFLOW_MODEL" ] || CLAUDE_ARGS+=(--model "$WORKFLOW_MODEL")
  [ -z "$WORKFLOW_STEP_BUDGET_USD" ] || CLAUDE_ARGS+=(--max-budget-usd "$WORKFLOW_STEP_BUDGET_USD")
}

# Commit the step's documents (only context/ files) so the next step starts from a clean tree.
commit_docs() {
  local p existing=() msg=(-m "docs($CHANGE): $1")
  for p in "context/changes/$CHANGE" context/roadmap.md context/lessons.md; do
    [ -e "$p" ] && existing+=("$p")
  done
  [ -n "$(git status --porcelain -- "${existing[@]}")" ] || return 0
  [ -z "${ISSUE:-}" ] || msg+=(-m "Refs #$ISSUE")
  git add -- "${existing[@]}"
  git commit --quiet "${msg[@]}" || note "commit of $1 artifacts failed (see the hook output above)"
}

# run_step <name> <prompt> [key=value ...]
# One fresh headless session per attempt; retried while the step's artifact is incomplete.
run_step() {
  local name=$1 prompt=$2 attempt missing="" log
  shift 2
  for attempt in $(seq 0 "$WORKFLOW_STEP_RETRIES"); do
    N=$((N + 1))
    log=$(printf '%s/%02d-%s.jsonl' "$LOGS" "$N" "$name")
    note "step $name (attempt $((attempt + 1))): $prompt"
    $WF run step "$name" "$@"
    claude -p "$prompt" "${CLAUDE_ARGS[@]}" > "$log" 2>&1 || note "  claude exited non-zero, see $log"
    note "  $($WF cost "$log")"
    if [ -f .workflow/stuck ]; then
      FAILED="$name: agent stuck: $(cat .workflow/stuck)"
      return 1
    fi
    if missing=$($WF check "$name" "$CHANGE"); then
      case "$name" in plan|plan-review|review|mutation|pr-body) commit_docs "$name" ;; esac
      return 0
    fi
    note "  incomplete: $missing"
  done
  FAILED="$name: incomplete after $((WORKFLOW_STEP_RETRIES + 1)) attempts: $missing"
  return 1
}

# One implement session per unticked phase.
implement_loop() {
  local ticked total guard=0
  read -r ticked total < <($WF progress "$CHANGE")
  while [ "$ticked" -lt "$total" ]; do
    guard=$((guard + 1))
    if [ "$guard" -gt "$WORKFLOW_MAX_PHASES" ]; then
      FAILED="implement: more than $WORKFLOW_MAX_PHASES phase sessions"
      return 1
    fi
    run_step implement "/implement $CHANGE" "ticked_before=$ticked" || return 1
    read -r ticked total < <($WF progress "$CHANGE")
  done
}

# review -> fix-review, up to <rounds> reviews. Open findings are triaged even when the verdict
# is APPROVE (minors); a re-review happens only after fixing blockers or majors.
review_loop() {
  local rounds=$1 round=0 verdict
  while :; do
    round=$((round + 1))
    run_step review "/review $CHANGE" || return 1
    verdict=$($WF verdict "$CHANGE" review)
    note "review round $round: $verdict, $($WF open-findings "$CHANGE") open finding(s)"
    [ "$($WF open-findings "$CHANGE")" -gt 0 ] || return 0
    run_step fix-review "/fix-review $CHANGE" || return 1
    [ "$verdict" != "APPROVE" ] && [ "$round" -lt "$rounds" ] || return 0
  done
}

# Keep unfinished work for the person. Tracked changes are always committed. Untracked files
# are committed only when a step failed (they may be the agent's unfinished new files); after a
# successful run they are build output or junk, so they are listed and left alone. Hooks still
# run (e.g. a secret scan); if they refuse the commit, the work is stashed locally instead.
save_leftovers() {
  local untracked
  untracked=$(git ls-files --others --exclude-standard)
  if [ -n "$untracked" ] && [ -z "$FAILED" ]; then
    note "untracked files left in the tree (not committed; consider .gitignore): $(echo "$untracked" | tr '\n' ' ')"
  fi
  if [ -n "$FAILED" ]; then git add -A; else git add -u; fi
  git diff --cached --quiet && return 0
  local subject="wip($CHANGE): changes left after the run"
  [ -z "$FAILED" ] || subject="wip($CHANGE): unfinished work from step ${FAILED%%:*}"
  if git commit --quiet -m "$subject"; then
    note "committed leftover changes as WIP"
  else
    git reset --quiet
    git stash push --quiet --include-untracked -m "$CHANGE: leftover work"
    note "leftover changes failed the commit hooks and were stashed locally (git stash list)"
  fi
}

# write_pr_body: regenerate pr-body.md from the artifacts (fallback: the run summary).
write_pr_body() {
  local failed=$FAILED
  {
    echo
    echo "## Outcome"
    echo "- Failed step: ${failed:-none}"
    echo "- Draft reason: ${DRAFT_REASON:-none}"
    echo "- Plan review: $($WF verdict "$CHANGE" plan-review)"
    echo "- Review: $($WF verdict "$CHANGE" review) ($($WF open-findings "$CHANGE") open findings)"
    echo "- Phases ticked: $($WF progress "$CHANGE" | tr ' ' '/')"
  } >> "$SUMMARY"
  rm -f .workflow/stuck
  run_step pr-body "/pr-body $CHANGE" || {
    note "pr-body failed; falling back to the run summary"
    { echo "# wip($CHANGE): ${ROADMAP_ID:-$CHANGE}"; echo; cat "$SUMMARY"; } > "context/changes/$CHANGE/pr-body.md"
    commit_docs pr-body
  }
  FAILED=$failed
}

# publish_pr <base>: push the branch, then create the PR or update its title and body.
# Prints the PR URL. A draft PR means the agent did not reach a reviewable end state.
publish_pr() {
  local base=$1 title body draft=()
  title=$($WF pr-title "$CHANGE")
  body=.workflow/pr-body-$CHANGE.md
  sed '1{/^# /d}' "context/changes/$CHANGE/pr-body.md" > "$body"
  if [ -n "$FAILED${DRAFT_REASON:-}" ] || [ "$($WF open-findings "$CHANGE")" -gt 0 ]; then
    draft=(--draft)
  fi
  if ! git remote get-url origin >/dev/null 2>&1 || ! command -v gh >/dev/null; then
    note "PR not opened (no origin remote or no gh). Description: context/changes/$CHANGE/pr-body.md"
    return 0
  fi
  git push --quiet -u origin "$BRANCH"
  if gh pr view "$BRANCH" --json url >/dev/null 2>&1; then
    gh pr edit "$BRANCH" --title "$title" --body-file "$body" >/dev/null
    [ ${#draft[@]} -gt 0 ] || gh pr ready "$BRANCH" >/dev/null 2>&1 || true
    PR_URL=$(gh pr view "$BRANCH" --json url --jq .url)
  else
    PR_URL=$(gh pr create --base "$base" --head "$BRANCH" --title "$title" --body-file "$body" "${draft[@]}")
  fi
  note "PR: $PR_URL ${draft[*]}"
}
