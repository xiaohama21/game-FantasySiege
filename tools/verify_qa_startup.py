"""Prove first-autoload isolation with preseeded saves in fresh Godot processes."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

import qa_launch
import run_checks

ROOT = Path(__file__).resolve().parents[1]
INITIAL = ["guanyu", "zhaoyun", "zhugeliang", "diaochan", "lubu", "iron_guard", "ember_archer", "rune_medic"]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def existing_snapshot(directory: Path) -> dict:
    """Read existing user bytes only. Never create a player-file sentinel."""
    files = {}
    if directory.exists():
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                files[path.relative_to(directory).as_posix()] = {"bytes": path.stat().st_size, "sha256": sha(path)}
    return {"directory": str(directory), "exists": directory.exists(), "files": files}


def seed(root: Path, future: bool = False) -> dict:
    prefs = {"schema": 99 if future else 1, "master_volume": 0.23, "music_volume": 0.45,
             "sfx_volume": 0.7, "fullscreen": True, "damage_numbers": True,
             "edge_scroll": True, "tutorial_seen": True}
    profile = {"schema": 99 if future else 3, "credits": 731,
               "levels": {name: 7 if name == "guanyu" else 1 for name in INITIAL},
               "roster": INITIAL, "owned": INITIAL, "cleared": [], "transactions": [], "study_routes": {}}
    result = {}
    for name, data in (("preferences", prefs), ("profile", profile)):
        path = root / (name + ".json")
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        result[name] = {"path": str(path), "sha256": sha(path)}
    return result


def replace_option(command: list[str], flag: str, value: str | None, duplicate: bool = False) -> list[str]:
    result = command.copy()
    if duplicate:
        return result + [flag, str(value)]
    index = result.index(flag)
    if value is None:
        del result[index:index + 2]
    else:
        result[index + 1] = value
    return result


def run_probe(project: Path, godot: Path, mode: str, real_user: Path) -> dict:
    label = "first_read_" + mode
    evidence = qa_launch.prepare_launch(
        [str(godot), "--headless", "--path", str(project), "--script", "res://tests/QAStartupSmoke.gd"],
        project, label, background=True)
    fixture = evidence.engine_log.parent / "fixture.json"
    expected = "future" if mode == "future" else ("invalid" if mode.startswith("invalid_") else "normal")
    seeded = seed(evidence.save_root, mode == "future")
    command = evidence.command + ["--qa-expect", expected, "--qa-fixture-report", str(fixture)]
    if mode == "invalid_outside":
        command = replace_option(command, "--qa-save-root", str(real_user))
    elif mode == "invalid_duplicate":
        command = replace_option(command, "--qa-save-root", str(evidence.save_root), duplicate=True)
    elif mode == "invalid_missing_root":
        command = replace_option(command, "--qa-save-root", None)
    elif mode == "invalid_relative":
        command = replace_option(command, "--qa-save-root", "tests/.user/relative")
    elif mode == "invalid_missing_report":
        # There is intentionally no valid report destination, so the fixture
        # supplies the in-memory snapshot for rejection evidence instead.
        command = replace_option(command, "--qa-startup-report", None)
    elif mode == "invalid_outside_report":
        command = replace_option(command, "--qa-startup-report", str(real_user / "qa_forbidden_report.json"))
    item = {"case": mode, "passed": False, "started_ns": time.time_ns(), "command_line": command,
            "seeded": seeded, "errors": [], "fixture_report": str(fixture)}
    output = ""
    try:
        run = subprocess.run(command, cwd=project, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=45)
        output = run_checks.joined_output(run.stdout, run.stderr)
        item["exit_code"] = run.returncode
        if run.returncode != 0:
            item["errors"].append("fixture_exit_nonzero")
        if "QA_STARTUP_SMOKE" not in run.stdout:
            item["errors"].append("fixture_marker_missing")
        item["fatal_log_lines"] = run_checks.fatal_lines(output)
        if item["fatal_log_lines"]:
            item["errors"].append("fatal_fixture_log")
        detail = json.loads(fixture.read_text(encoding="utf-8"))
        item["fixture_report_sha256"] = sha(fixture)
        item["checks"] = detail.get("checks", 0)
        item["qa_startup"] = detail.get("qa_startup", {})
        if detail.get("passed") is not True or detail.get("failures") or detail.get("expected") != expected:
            item["errors"].append("fixture_structured_failure")
        if type(item["checks"]) is not int or item["checks"] <= 0:
            item["errors"].append("fixture_positive_integer_checks_required")
        if detail.get("fixture_sha256") != sha(project / "tests/QAStartupSmoke.gd"):
            item["errors"].append("fixture_script_fingerprint_mismatch")
        if mode in ("invalid_missing_report", "invalid_outside_report"):
            # No unsafe startup report is created. Audit the trusted fixture
            # snapshot and the explicitly redirected engine log independently.
            snapshot = item["qa_startup"]
            if snapshot.get("qa_enabled") is not True or snapshot.get("valid") is not False or snapshot.get("operations"):
                item["errors"].append("invalid_unreported_context_touched_save")
            if not snapshot.get("refused_operations"):
                item["errors"].append("invalid_context_refusal_missing")
            if evidence.startup_report.exists():
                item["errors"].append("invalid_report_destination_fallback")
            if not evidence.engine_log.is_file() or run_checks.fatal_lines(evidence.engine_log.read_text(encoding="utf-8", errors="replace")):
                item["errors"].append("invalid_engine_log_missing_or_fatal")
            item["launch_evidence"] = {"passed": not item["errors"], "engine_log": str(evidence.engine_log),
                                       "engine_log_sha256": sha(evidence.engine_log), "expected_rejection": True,
                                       "startup_report_written": False}
        else:
            audit = qa_launch.validate_evidence(evidence, run_checks.fatal_lines, expect_valid=expected != "invalid")
            item["launch_evidence"] = audit
            item["errors"].extend(audit["errors"])
        for saved in seeded.values():
            if sha(Path(saved["path"])) != saved["sha256"]:
                item["errors"].append("seeded_save_bytes_changed")
        for name in ("preferences.json", "profile.json"):
            if any((evidence.save_root / (name + suffix)).exists() for suffix in (".tmp", ".bak")):
                item["errors"].append("unexpected_seed_write_artifact:" + name)
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as failure:
        item["errors"].append(type(failure).__name__ + ": " + str(failure))
        if isinstance(failure, subprocess.TimeoutExpired):
            output = run_checks.joined_output(failure.stdout, failure.stderr)
    stdout_path = evidence.engine_log.parent / "stdout_stderr.log"
    stdout_path.write_text(output, encoding="utf-8")
    item.update(stdout_stderr=str(stdout_path), stdout_stderr_sha256=sha(stdout_path), finished_ns=time.time_ns())
    item["passed"] = not item["errors"]
    return item


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--godot", type=Path, default=run_checks.DEFAULT_GODOT)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(argv)
    project = args.project.resolve(strict=True)
    godot = args.godot.resolve(strict=True)
    report_path = args.report or project / "reports/qa_startup_verification_local.json"
    qa_launch.preflight_project(project)
    qa_launch.ensure_confined(report_path, project / "reports")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    actual_user = Path(os.environ["APPDATA"]) / "FantasySiege"
    before = existing_snapshot(actual_user)
    version = re.search(r'^\s*config/version="([^"]+)"', (project / "project.godot").read_text(encoding="utf-8-sig"), re.MULTILINE)
    if version is None:
        raise ValueError("project program version missing")
    report = {"passed": False, "scope": "Fresh-process first-autoload isolated reads and rejection; no foreground or performance validation",
              "program_version": version.group(1),
              "started_utc": datetime.now(timezone.utc).isoformat(), "real_user_before": before,
              "cases": [], "failures": [], "real_player_sentinels_created": False}

    def save() -> None:
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    save()
    for mode in ("normal", "future", "invalid_outside", "invalid_duplicate", "invalid_missing_root",
                 "invalid_relative", "invalid_missing_report", "invalid_outside_report"):
        item = run_probe(project, godot, mode, actual_user)
        report["cases"].append(item)
        print("QA_STARTUP", mode, "PASS" if item["passed"] else "FAIL", flush=True)
        save()
    after = existing_snapshot(actual_user)
    report["real_user_after"] = after
    report["real_user_unchanged"] = before == after
    if before != after:
        report["failures"].append("real_user_directory_changed")
    report["failures"].extend(item["case"] for item in report["cases"] if not item["passed"])
    report["checks"] = sum(item.get("checks", 0) for item in report["cases"])
    report["passed"] = not report["failures"]
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    save()
    print("QA_STARTUP_VERIFICATION_COMPLETE", json.dumps({"passed": report["passed"], "cases": len(report["cases"]),
                                                        "checks": report["checks"], "report": str(report_path)}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
