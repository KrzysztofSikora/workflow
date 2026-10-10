#!/usr/bin/env bash
# Install the autonomous change workflow into a git repository.
#
#   ./install.sh <target-repo> [--force] [--github]
#
# Copies .claude/skills, .claude/workflow and the hooks; merges the hooks into an existing
# .claude/settings.json; adds .workflow/ to .gitignore; adds CLAUDE.md and docs/workflow.md
# only where they do not exist yet. Existing skills are kept unless --force is given.
# --github also adds .github/workflows/agent.yml (runs ship / address-pr in GitHub Actions).
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
TARGET="" FORCE=0 GITHUB=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --github) GITHUB=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) TARGET=$arg ;;
  esac
done
[ -n "$TARGET" ] || { sed -n '2,10p' "$0"; exit 1; }
TARGET=$(cd "$TARGET" && git rev-parse --show-toplevel) || { echo "install: $TARGET is not a git repository" >&2; exit 1; }

copy() {  # copy <relative path>: skip existing files unless --force
  local src=$SRC/$1 dst=$TARGET/$1
  if [ -e "$dst" ] && [ "$FORCE" -eq 0 ]; then
    if ! cmp -s "$src" "$dst"; then echo "  kept   $1 (differs; --force to overwrite)"; fi
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "  wrote  $1"
}

echo "Installing into $TARGET"
(cd "$SRC" && find .claude/skills .claude/workflow -type f -not -path "*/__pycache__/*") | sort | while read -r f; do copy "$f"; done
chmod +x "$TARGET/.claude/workflow/ship" "$TARGET/.claude/workflow/address-pr" "$TARGET/.claude/workflow/wf.py"

# Merge our hooks into settings.json without dropping the project's own settings.
python3 - "$SRC/.claude/settings.json" "$TARGET/.claude/settings.json" <<'EOF'
import json, sys
from pathlib import Path
ours = json.loads(Path(sys.argv[1]).read_text())
path = Path(sys.argv[2])
theirs = json.loads(path.read_text()) if path.exists() else {}
hooks = theirs.setdefault("hooks", {})
added = 0
for event, groups in ours["hooks"].items():
    existing = hooks.setdefault(event, [])
    commands = {h.get("command") for g in existing for h in g.get("hooks", [])}
    for group in groups:
        if all(h["command"] not in commands for h in group["hooks"]):
            existing.append(group)
            added += 1
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(theirs, indent=2) + "\n")
print(f"  merged .claude/settings.json ({added} hook group(s) added)")
EOF

if ! grep -qxF '.workflow/' "$TARGET/.gitignore" 2>/dev/null; then
  printf '\n# Autonomous workflow runtime state and session logs\n.workflow/\n' >> "$TARGET/.gitignore"
  echo "  added  .workflow/ to .gitignore"
fi

[ -e "$TARGET/CLAUDE.md" ] && echo "  kept   CLAUDE.md (add a 'Gates' table; see $SRC/templates/CLAUDE.md)" \
  || { cp "$SRC/templates/CLAUDE.md" "$TARGET/CLAUDE.md"; echo "  wrote  CLAUDE.md (fill in the placeholders)"; }
mkdir -p "$TARGET/docs" "$TARGET/context"
[ -e "$TARGET/docs/workflow.md" ] || { cp "$SRC/README.md" "$TARGET/docs/workflow.md"; echo "  wrote  docs/workflow.md"; }
if [ "$GITHUB" -eq 1 ]; then
  mkdir -p "$TARGET/.github/workflows"
  SRC_GH=templates/github/agent.yml
  [ -e "$TARGET/.github/workflows/agent.yml" ] && [ "$FORCE" -eq 0 ] && echo "  kept   .github/workflows/agent.yml" \
    || { cp "$SRC/$SRC_GH" "$TARGET/.github/workflows/agent.yml"; echo "  wrote  .github/workflows/agent.yml"; }
fi

echo
echo "Next: fill in the Gates table in CLAUDE.md, run /shape ... /test-plan once,"
echo "then: .claude/workflow/ship S-01   (or /ship S-01 inside Claude Code)"
