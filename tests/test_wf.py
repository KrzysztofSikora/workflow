"""Tests for .claude/workflow/wf.py: artifact parsing, step checks and the hooks.

Run: python3 -m unittest discover -s tests
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

WF = Path(__file__).resolve().parents[1] / ".claude" / "workflow" / "wf.py"

ROADMAP = """# Roadmap

## Overview

| ID | Issue | change-id | Type | Covers | Depends on | Size | Status |
|----|-------|-----------|------|--------|------------|------|--------|
| F-01 | #1 | repo-skeleton | foundation | - | - | S | done |
| S-01 | #7 | list-items | slice | FR-01 | F-01 | M | todo |

## Items
"""

PLAN = """# Plan: list-items (S-01)

## Decisions
| ID | Question | Chosen | Alternatives | Why | Reversal | Decided by |

## Progress
- [x] Phase 1: schema
- [ ] Phase 2: resolver

## Deviations
- [ ] Phase 9: not a progress line, other section
"""


class WfTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        (self.root / ".gitignore").write_text(".workflow/\n")
        (self.root / "context" / "changes" / "list-items").mkdir(parents=True)
        (self.root / "context" / "roadmap.md").write_text(ROADMAP)
        self.write("plan.md", PLAN)
        self.git("add", ".")
        self.git("commit", "-qm", "init")
        self.git("switch", "-qc", "change/list-items")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def write(self, name, text):
        (self.root / "context" / "changes" / "list-items" / name).write_text(text)

    def wf(self, *args, stdin="", env=None):
        full_env = {k: v for k, v in os.environ.items() if k != "WORKFLOW_RUN"}
        full_env.update({"CLAUDE_PROJECT_DIR": str(self.root), **(env or {})})
        return subprocess.run([sys.executable, str(WF), *args], cwd=self.root, input=stdin,
                              capture_output=True, text=True, env=full_env)

    def start_run(self, step, **extra):
        # A run owned by this test process, so the pid liveness check passes.
        run = {"change_id": "list-items", "branch": "change/list-items", "pid": os.getpid(),
               "step": step, "step_started": time.time() - 1, "stop_blocks": 0, **extra}
        (self.root / ".workflow").mkdir(exist_ok=True)
        (self.root / ".workflow" / "run.json").write_text(json.dumps(run))

    def hook(self, name, event, in_run=True):
        env = {"WORKFLOW_RUN": "list-items"} if in_run else {}
        out = self.wf("hook", name, stdin=json.dumps(event), env=env).stdout
        return json.loads(out) if out.strip() else None


class ArtifactTests(WfTestCase):
    def test_resolve_by_roadmap_id_change_id_and_issue(self):
        for arg in ("S-01", "list-items", "#7", "7"):
            self.assertEqual(self.wf("resolve", arg).stdout.strip(), "list-items\tS-01\t7", arg)

    def test_resolve_unknown_item_fails(self):
        result = self.wf("resolve", "S-99")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("S-99", result.stderr)

    def test_progress_counts_only_the_progress_section(self):
        self.assertEqual(self.wf("progress", "list-items").stdout.split(), ["1", "2"])

    def test_verdict_accepts_only_known_values(self):
        self.write("review.md", "# Review\n\nVerdict: APPROVE WITH FOLLOW-UPS\n")
        self.assertEqual(self.wf("verdict", "list-items", "review").stdout.strip(), "APPROVE WITH FOLLOW-UPS")
        self.write("review.md", "Verdict: LOOKS FINE\n")
        self.assertEqual(self.wf("verdict", "list-items", "review").stdout.strip(), "")

    def test_open_findings(self):
        self.write("review.md", "### R1\n- Decision: open\n### R2\n- Decision: fixed (abc)\n### R3\n- Decision: open\n")
        self.assertEqual(self.wf("open-findings", "list-items").stdout.strip(), "2")

    def test_new_comments_skips_everything_up_to_the_last_agent_reply(self):
        items = [
            {"kind": "comment", "body": "old", "created_at": "2026-01-01T00:00:00Z"},
            {"kind": "comment", "body": "<!-- workflow:address-pr -->\nreplies", "created_at": "2026-01-02T00:00:00Z"},
            {"kind": "review", "body": "", "created_at": "2026-01-03T00:00:00Z"},
            {"kind": "inline", "body": "D-1: take B", "created_at": "2026-01-04T00:00:00Z"},
        ]
        src = self.root / "all.jsonl"
        src.write_text("\n".join(json.dumps(i) for i in items))
        out = self.root / "new.json"
        self.assertEqual(self.wf("new-comments", str(src), str(out)).stdout.strip(), "1")
        self.assertEqual([c["body"] for c in json.loads(out.read_text())], ["D-1: take B"])


class CheckTests(WfTestCase):
    def check(self, step):
        return self.wf("check", step, "list-items")

    def test_implement_needs_a_new_tick_and_a_clean_tree(self):
        self.start_run("implement", ticked_before=1)
        self.assertEqual(self.check("implement").returncode, 1)
        self.write("plan.md", PLAN.replace("- [ ] Phase 2", "- [x] Phase 2"))
        self.assertIn("not clean", self.check("implement").stdout)
        self.git("commit", "-qam", "phase 2")
        self.assertEqual(self.check("implement").returncode, 0)

    def test_review_must_be_written_during_the_step(self):
        self.write("review.md", "Verdict: APPROVE\n")
        old = time.time() - 3600
        os.utime(self.root / "context/changes/list-items/review.md", (old, old))
        self.start_run("review")
        self.assertIn("not written", self.check("review").stdout)
        self.write("review.md", "Verdict: APPROVE\n")
        self.assertEqual(self.check("review").returncode, 0)

    def test_fix_review_needs_every_finding_decided(self):
        self.start_run("fix-review")
        self.write("review.md", "### R1\n- Decision: open\n")
        self.assertIn("1 finding", self.check("fix-review").stdout)

    def test_stuck_file_ends_any_step(self):
        self.start_run("implement", ticked_before=1)
        (self.root / ".workflow" / "stuck").write_text("needs a database")
        self.assertEqual(self.check("implement").returncode, 0)


class HookTests(WfTestCase):
    def bash(self, command, in_run=True):
        return self.hook("pre-tool", {"tool_name": "Bash", "tool_input": {"command": command}}, in_run)

    def test_ask_user_question_is_denied_in_a_run(self):
        self.start_run("plan")
        out = self.hook("pre-tool", {"tool_name": "AskUserQuestion", "tool_input": {}})
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIn("Decisions", out["hookSpecificOutput"]["permissionDecisionReason"])

    def test_hooks_ignore_sessions_not_started_by_the_runner(self):
        self.start_run("plan")
        self.assertIsNone(self.hook("pre-tool", {"tool_name": "AskUserQuestion"}, in_run=False))
        self.assertIsNone(self.bash("git push origin main", in_run=False))
        self.assertIsNone(self.hook("stop", {}, in_run=False))

    def test_hooks_ignore_a_dead_run(self):
        self.start_run("plan", pid=2**22 + 12345)
        self.assertIsNone(self.hook("pre-tool", {"tool_name": "AskUserQuestion"}))

    def test_git_guard_denies_risky_commands(self):
        self.start_run("implement")
        for command in ("git push", "git -C . push origin change/list-items", "gh pr merge 3",
                        "git commit --no-verify -m x", "git reset --hard HEAD~1", "git clean -fd",
                        "git add -A", "git add .", "cd src && git add --all", "git switch main",
                        "git checkout -b other", "git rebase main"):
            out = self.bash(command)
            self.assertIsNotNone(out, command)
            self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny", command)

    def test_git_guard_allows_normal_work(self):
        self.start_run("implement")
        for command in ('git commit -m "feat(x): merge filters and push results"',
                        "git add src/a.ts plan.md", "git status", "git diff main...HEAD",
                        "git checkout -- src/a.ts", "git log --oneline", "pnpm test"):
            self.assertIsNone(self.bash(command), command)

    def test_commit_is_denied_off_the_change_branch(self):
        self.start_run("implement")
        self.git("switch", "-q", "main")
        out = self.bash("git commit -m x")
        self.assertIn("change/list-items", out["hookSpecificOutput"]["permissionDecisionReason"])

    def test_stop_is_blocked_until_the_step_is_done_then_released(self):
        self.start_run("implement", ticked_before=1)
        for _ in range(3):
            out = self.hook("stop", {"stop_hook_active": True})
            self.assertEqual(out["decision"], "block")
            self.assertIn("No new phase is ticked", out["reason"])
        self.assertIsNone(self.hook("stop", {}), "gives up after 3 blocks; the runner retries")

    def test_stop_is_allowed_when_the_step_is_done(self):
        self.start_run("plan")
        self.assertIsNone(self.hook("stop", {}))


if __name__ == "__main__":
    unittest.main()
