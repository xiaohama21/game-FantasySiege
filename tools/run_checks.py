"""Run fresh game checks and reject failed reports, script errors, and leaks."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = Path("F:/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe")
FATAL_LOG = re.compile(r"\bERROR\b|\bLeaked\s+instance\b|\bObjectDB\s+instances?\b", re.IGNORECASE)
ANSI_ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
NVAPI_EXISTING_PROFILE = re.compile(r"^\s*NVAPI: Error creating application: NVAPI_EXECUTABLE_ALREADY_IN_USE\(code -167\)\s*$")
TIMESTAMP_TOLERANCE_NS = 1_000_000  # Filesystem wall-clock metadata may round by a millisecond.


@dataclass(frozen=True)
class CheckCase:
    name: str
    marker: str
    report_file: str
    headless: bool = True
    timeout: int = 120
    final_phase: str | None = None
    report_hashes: tuple[tuple[str, str], ...] = ()
    script_hashes: tuple[str, ...] = ()
    required_report_values: tuple[tuple[str, str | int | bool], ...] = ()


CASES = {
    case.name: case for case in (
        CheckCase("BattleSmoke", "BATTLE_SMOKE", "battle_smoke.json", timeout=300),
        CheckCase("ProfileSmoke", "PROFILE_SMOKE", "profile_smoke.json"),
        CheckCase("ProgressionSmoke", "PROGRESSION_SMOKE", "progression_smoke.json"),
        CheckCase("PreferencesSmoke", "PREFERENCES_SMOKE", "preferences_smoke.json"),
        CheckCase("AudioShutdownSmoke", "AUDIO_SHUTDOWN_SMOKE", "audio_shutdown_smoke.json", timeout=30),
        CheckCase("StudyProfileSmoke", "STUDY_PROFILE_SMOKE", "study_profile_smoke.json",
                  report_hashes=(("studies_sha256", "resources/studies.json"),)),
        CheckCase("StudyCombatSmoke", "STUDY_COMBAT_SMOKE", "study_combat_smoke.json", final_phase="complete",
                  report_hashes=(("unit_stats_sha256", "scripts/core/UnitStats.gd"), ("siege_battle_sha256", "scripts/combat/SiegeBattle.gd"), ("units_sha256", "resources/units.json"), ("studies_sha256", "resources/studies.json")),
                  required_report_values=(("matrix_cases", 108),)),
        CheckCase("StudyUISmoke", "STUDY_UI_SMOKE", "study_ui_smoke.json",
                  report_hashes=(("project_sha256", "project.godot"), ("studies_sha256", "resources/studies.json"), ("units_sha256", "resources/units.json")),
                  script_hashes=("scripts/ui/Main.gd",)),
        CheckCase("MainFlow", "MAIN_FLOW", "main_flow.json", headless=False, timeout=300),
        CheckCase("CampaignJourney", "CAMPAIGN_JOURNEY_COMPLETE", "campaign_journey.json", timeout=900, final_phase="complete"),
    )
}
VISUAL_CASES = ("MainFlow", "CampaignJourney")
CPU_CASES = tuple(name for name, case in CASES.items() if case.headless and name not in VISUAL_CASES)


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def project_context() -> dict:
    source = (ROOT / "project.godot").read_bytes()
    match = re.search(r'^\s*config/version\s*=\s*"([^"\r\n]+)"\s*$', source.decode("utf-8-sig"), re.MULTILINE)
    if match is None:
        raise ValueError("project.godot has no application config/version")
    return {"program_version": match.group(1), "project_sha256": hashlib.sha256(source).hexdigest()}


def case_artifact_context(case: CheckCase, root: Path | None = None) -> dict:
    base = ROOT if root is None else root
    context = {key: hashlib.sha256((base / relative).read_bytes()).hexdigest() for key, relative in case.report_hashes}
    if case.script_hashes:
        context["scripts_sha256"] = {relative: hashlib.sha256((base / relative).read_bytes()).hexdigest() for relative in case.script_hashes}
    return context


def capture_text(value: bytes | str | None) -> str:
    return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else (value or "")


def joined_output(stdout: bytes | str | None, stderr: bytes | str | None) -> str:
    # Keep stream boundaries: an ERROR on stderr must not merge into the last
    # word on stdout and evade the token/line checks.
    return "\n".join(part for part in (capture_text(stdout), capture_text(stderr)) if part)


def fatal_lines(output: str) -> list[str]:
    plain = ANSI_ESCAPE.sub("", output)
    return [line.strip() for line in plain.splitlines() if FATAL_LOG.search(line) and not NVAPI_EXISTING_PROFILE.fullmatch(line)][:12]


def diagnostic_lines(output: str) -> list[str]:
    plain = ANSI_ESCAPE.sub("", output)
    return [line.strip() for line in plain.splitlines() if NVAPI_EXISTING_PROFILE.fullmatch(line)]


def has_completion_marker(stdout: str, case: CheckCase) -> bool:
    return re.search(r"(?m)^\s*" + re.escape(case.marker) + r"(?:\s|$)", ANSI_ESCAPE.sub("", stdout)) is not None


def _write_json(path: Path, data: dict) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _invalid_json_number(value: str) -> None:
    raise ValueError("non-JSON numeric literal: " + value)


def validate_report(case: CheckCase, result: dict, expected: dict) -> None:
    path = ROOT / "reports" / case.report_file
    if not path.is_file():
        result["errors"].append("fresh_report_missing")
        return
    result["report_mtime_ns"] = path.stat().st_mtime_ns
    if result["report_mtime_ns"] + TIMESTAMP_TOLERANCE_NS < result["started_ns"]:
        result["errors"].append("report_timestamp_before_run")
    if result["report_mtime_ns"] > result["finished_ns"] + 1_000_000_000:
        result["errors"].append("report_timestamp_after_run")
    try:
        raw = path.read_bytes()
        report = json.loads(raw.decode("utf-8-sig"), parse_constant=_invalid_json_number)
        result["report_sha256"] = hashlib.sha256(raw).hexdigest()
    except (OSError, ValueError) as error:
        result["errors"].append("invalid_report: " + str(error))
        return
    if not isinstance(report, dict):
        result["errors"].append("report_is_not_an_object")
        return
    if report.get("passed") is not True:
        result["errors"].append("report_passed_is_not_true")
    if report.get("failures"):
        result["errors"].append("report_contains_failures")
    count = report.get("checks")
    if type(count) is not int or count <= 0:
        result["errors"].append("report_has_no_positive_check_count")
    result["checks"] = count
    for key in ("version", "program_version", "project_version"):
        if key in report and report[key] != expected["program_version"]:
            result["errors"].append("report_program_version_mismatch: " + key)
    if case.final_phase is not None and report.get("phase") != case.final_phase:
        result["errors"].append("report_final_phase_missing")
    for key, digest in result.get("artifact_sha256", {}).items():
        if report.get(key) != digest:
            result["errors"].append("report_artifact_hash_mismatch: " + key)
    for key, value in case.required_report_values:
        if type(report.get(key)) is not type(value) or report.get(key) != value:
            result["errors"].append("report_required_value_mismatch: " + key)


def run_case(case: CheckCase, godot: Path, expected: dict, verbose_render_diagnostics: bool = False) -> dict:
    command = [str(godot), "--path", str(ROOT)]
    if case.headless or verbose_render_diagnostics:
        command.append("--verbose")
    if case.headless:
        command.append("--headless")
    command += ["--script", f"res://tests/{case.name}.gd"]
    result = {
        "case": case.name, "passed": False, "errors": [], "exit_code": None,
        "started_at": _utc_now(), "started_ns": time.time_ns(),
        "report": "reports/" + case.report_file, **expected,
        "launch_mode": "headless_verbose" if case.headless else ("rendered_verbose_diagnostics" if verbose_render_diagnostics else "rendered_production"),
        "command_line": command,
        "artifact_sha256": {},
    }
    output = ""
    try:
        # Deletion, not an mtime-only comparison, prevents reuse of an old PASS.
        (ROOT / "reports" / case.report_file).unlink(missing_ok=True)
        if project_context() != expected:
            raise ValueError("project_changed_before_case")
        result["artifact_sha256"] = case_artifact_context(case)
        launch_options = {}
        if os.name == "nt" and not case.headless:
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 1  # SW_SHOWNORMAL: this is the interactive game, not a helper.
            launch_options["startupinfo"] = startup
        run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=case.timeout, **launch_options)
        result["exit_code"] = run.returncode
        output = joined_output(run.stdout, run.stderr)
        if run.returncode != 0:
            result["errors"].append("nonzero_exit")
        if not has_completion_marker(capture_text(run.stdout), case):
            result["errors"].append("completion_marker_missing")
    except subprocess.TimeoutExpired as error:
        output = joined_output(error.stdout, error.stderr)
        result["errors"].append("timeout")
    except (OSError, ValueError) as error:
        output = str(error)
        result["errors"].append("start_or_prepare_failed: " + str(error))
    result["finished_ns"] = time.time_ns()
    result["finished_at"] = _utc_now()
    result["duration_seconds"] = (result["finished_ns"] - result["started_ns"]) / 1_000_000_000
    result["fatal_log_lines"] = fatal_lines(output)
    result["diagnostic_log_lines"] = diagnostic_lines(output)
    if result["fatal_log_lines"]:
        result["errors"].append("fatal_error_or_leak_log")
    try:
        (ROOT / "reports" / f"{case.name}.log").write_text(output, encoding="utf-8")
        if project_context() != expected:
            result["errors"].append("project_changed_during_case")
        if case_artifact_context(case) != result["artifact_sha256"]:
            result["errors"].append("artifact_changed_during_case")
        validate_report(case, result, expected)
    except (OSError, ValueError) as error:
        result["errors"].append("report_or_project_unreadable: " + str(error))
    result["passed"] = not result["errors"]
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    parser.add_argument("--visual", action="store_true", help="Also run MainFlow and the headless complete CampaignJourney")
    parser.add_argument("--only", choices=tuple(CASES), help="Run one case after a focused change")
    parser.add_argument("--verbose-render-diagnostics", action="store_true", help="Enable verbose driver/resource diagnostics for rendered cases; normal error/leak gates still apply")
    args = parser.parse_args(argv)
    selected = (args.only,) if args.only else CPU_CASES + (VISUAL_CASES if args.visual else ())
    report = {
        "passed": False, "state": "running", "suite": "single" if args.only else ("full" if args.visual else "logic"),
        "selected_cases": list(selected), "cases": [], "errors": [], "started_at": _utc_now(),
        "project_root": str(ROOT), "reject_script_errors": True, "reject_object_leaks": True,
        "require_fresh_report": True, "require_current_project_version": True,
        "verbose_render_diagnostics": args.verbose_render_diagnostics,
        "rendered_launch_scope": "verbose driver/resource diagnostics" if args.verbose_render_diagnostics else "production startup logging",
    }
    directory = ROOT / "reports"
    directory.mkdir(parents=True, exist_ok=True)
    summary = directory / "checks.json"
    # A running/aborted suite never leaves a previous all-green summary in place.
    summary.unlink(missing_ok=True)
    try:
        context = project_context()
        report.update(context)
        _write_json(summary, report)
        for name in selected:
            result = run_case(CASES[name], args.godot, context, args.verbose_render_diagnostics)
            report["cases"].append(result)
            _write_json(summary, report)
            print(name, "PASS" if result["passed"] else "FAIL", flush=True)
    except (OSError, ValueError) as error:
        report["errors"].append(str(error))
        print("CHECKS FAIL", str(error), flush=True)
    report["state"] = "complete"
    report["finished_at"] = _utc_now()
    report["passed"] = not report["errors"] and len(report["cases"]) == len(selected) and all(case["passed"] for case in report["cases"])
    _write_json(summary, report)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
