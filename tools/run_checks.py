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
import struct
import subprocess
import time
import zlib
import qa_launch

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
    require_gdd_version: bool = False


BRIEFING_REPORT_HASHES = (("project_sha256", "project.godot"), ("gdd_sha256", "docs/GAME_DESIGN.md"),
                         ("briefings_sha256", "resources/briefings.json"), ("studies_sha256", "resources/studies.json"),
                         ("units_sha256", "resources/units.json"), ("stages_sha256", "resources/stages.json"))
BRIEFING_SCRIPT_HASHES = ("scripts/core/BattleBriefing.gd", "scripts/core/UnitStats.gd", "scripts/combat/SiegeBattle.gd")

CASES = {
    case.name: case for case in (
        CheckCase("BattleSmoke", "BATTLE_SMOKE", "battle_smoke.json", timeout=300),
        CheckCase("ProfileSmoke", "PROFILE_SMOKE", "profile_smoke.json"),
        CheckCase("ProgressionSmoke", "PROGRESSION_SMOKE", "progression_smoke.json"),
        CheckCase("PreferencesSmoke", "PREFERENCES_SMOKE", "preferences_smoke.json",
                  report_hashes=(("settings_panel_sha256", "scripts/ui/SettingsPanel.gd"), ("user_prefs_sha256", "scripts/core/UserPrefs.gd")),
                  required_report_values=(("temporary_return_verified", True), ("cold_reloaded_previous_settings", True), ("retry_saved_after_failure", True))),
        CheckCase("AudioShutdownSmoke", "AUDIO_SHUTDOWN_SMOKE", "audio_shutdown_smoke.json", timeout=30),
        CheckCase("StudyProfileSmoke", "STUDY_PROFILE_SMOKE", "study_profile_smoke.json",
                  report_hashes=(("studies_sha256", "resources/studies.json"),)),
        CheckCase("StudyCombatSmoke", "STUDY_COMBAT_SMOKE", "study_combat_smoke.json", final_phase="complete",
                  report_hashes=(("unit_stats_sha256", "scripts/core/UnitStats.gd"), ("siege_battle_sha256", "scripts/combat/SiegeBattle.gd"), ("units_sha256", "resources/units.json"), ("studies_sha256", "resources/studies.json")),
                  required_report_values=(("matrix_cases", 108),)),
        CheckCase("StudyUISmoke", "STUDY_UI_SMOKE", "study_ui_smoke.json",
                  report_hashes=(("project_sha256", "project.godot"), ("studies_sha256", "resources/studies.json"), ("units_sha256", "resources/units.json")),
                  script_hashes=("scripts/ui/Main.gd", "scripts/ui/StatBadge.gd"),
                  required_report_values=(("navigation_toast_valid", True),)),
        CheckCase("BriefingSmoke", "BRIEFING_SMOKE", "briefing_smoke.json", final_phase="complete",
                  report_hashes=BRIEFING_REPORT_HASHES, script_hashes=BRIEFING_SCRIPT_HASHES,
                  required_report_values=(("stage_count", 8), ("matrix_cases", 108)), require_gdd_version=True),
        CheckCase("BriefingUISmoke", "BRIEFING_UI_SMOKE", "briefing_ui_smoke.json",
                  report_hashes=BRIEFING_REPORT_HASHES, script_hashes=BRIEFING_SCRIPT_HASHES + ("scripts/ui/Main.gd", "scripts/ui/StatBadge.gd"),
                  required_report_values=(("stage_count", 8),), require_gdd_version=True),
        CheckCase("BattleReportSmoke", "BATTLE_REPORT_SMOKE", "battle_report_smoke.json", final_phase="complete",
                  report_hashes=BRIEFING_REPORT_HASHES, script_hashes=("scripts/combat/SiegeBattle.gd", "scripts/core/UnitStats.gd"),
                  require_gdd_version=True),
        CheckCase("ResultUISmoke", "RESULT_UI_SMOKE", "result_ui_smoke.json", final_phase="complete", timeout=300,
                  report_hashes=BRIEFING_REPORT_HASHES, script_hashes=("scripts/combat/SiegeBattle.gd", "scripts/core/UnitStats.gd", "scripts/ui/Main.gd", "scripts/ui/StatBadge.gd"),
                  require_gdd_version=True),
        CheckCase("MainFlow", "MAIN_FLOW", "main_flow.json", headless=False, timeout=300),
        CheckCase("CampaignJourney", "CAMPAIGN_JOURNEY_COMPLETE", "campaign_journey.json", timeout=900, final_phase="complete"),
    )
}
VISUAL_CASES = ("MainFlow", "CampaignJourney")
CPU_CASES = tuple(name for name, case in CASES.items() if case.headless and name not in VISUAL_CASES)
MAIN_FLOW_CAPTURES = ("01_campaign", "06_chapter_two", "02_attributes", "03_squad", "09_enemy_book", "14_boss_book", "04_gallery", "11_guide_summon", "12_guide_camera", "13_guide_pulse", "07_battle_right", "10_settings", "15_unsaved_settings", "05_battle", "08_unlock_result")


def png_dimensions(path: Path) -> tuple[int, int]:
    """Read real RGB/RGBA dimensions and reject truncated/corrupt PNG chunks."""
    raw = path.read_bytes()
    if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("PNG signature missing")
    cursor, dimensions, has_data = 8, None, False
    while cursor + 12 <= len(raw):
        length = struct.unpack_from(">I", raw, cursor)[0]
        kind = raw[cursor + 4:cursor + 8]
        end = cursor + 12 + length
        if end > len(raw):
            raise ValueError("PNG chunk is truncated")
        data = raw[cursor + 8:cursor + 8 + length]
        checksum = struct.unpack_from(">I", raw, cursor + 8 + length)[0]
        if zlib.crc32(kind + data) != checksum:
            raise ValueError("PNG chunk checksum differs")
        if cursor == 8:
            if kind != b"IHDR" or length != 13:
                raise ValueError("PNG IHDR missing")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", data)
            if not width or not height or depth not in (8, 16) or color not in (2, 6) or compression != 0 or filtering != 0 or interlace not in (0, 1):
                raise ValueError("PNG RGB/RGBA header invalid")
            dimensions = (width, height)
        elif kind == b"IHDR":
            raise ValueError("PNG IHDR repeated")
        if kind == b"IDAT" and data:
            has_data = True
        if kind == b"IEND":
            if length or not has_data or end != len(raw) or dimensions is None:
                raise ValueError("PNG ending invalid")
            return dimensions
        cursor = end
    raise ValueError("PNG ending missing or truncated")


def main_flow_check(report: dict, root: Path | None = None) -> list[str]:
    base = ROOT if root is None else root
    errors = []
    if not isinstance(report, dict):
        return ["MainFlow report is not an object"]
    if report.get("passed") is not True or report.get("failures") or type(report.get("checks")) is not int or report.get("checks", 0) <= 0:
        errors.append("MainFlow structured report failed")
    try:
        source = (base / "project.godot").read_text(encoding="utf-8-sig")
        version = re.search(r'^\s*config/version\s*=\s*"([^"\r\n]+)"\s*$', source, re.MULTILINE)
        if version is None or report.get("program_version") != version.group(1):
            errors.append("MainFlow program version differs")
        for key, relative in (("units_sha256", "resources/units.json"), ("stages_sha256", "resources/stages.json")):
            if report.get(key) != hashlib.sha256((base / relative).read_bytes()).hexdigest():
                errors.append("MainFlow input SHA differs: " + key)
    except (OSError, ValueError) as error:
        errors.append("MainFlow context unreadable: " + str(error))
    for key in ("real_spine", "audio_shutdown_clean", "normal_window_close", "engine_input_dispatch_verified"):
        if report.get(key) is not True:
            errors.append("MainFlow required state missing: " + key)
    if report.get("os_input_verified") is not False:
        errors.append("MainFlow must exclude OS/manual input verification")
    observed = report.get("host_observed_frames")
    if type(observed) is not int or observed <= 0:
        errors.append("MainFlow requires positive integer host observation frames")
    for key in ("host_normal_window_frames", "host_focused_frames"):
        if type(report.get(key)) is not int or report.get(key) != observed:
            errors.append("MainFlow host observation incomplete: " + key)
    captures = report.get("capture_states")
    if not isinstance(captures, list):
        return errors + ["MainFlow capture states missing"]
    if type(report.get("screenshots")) is not int or report.get("screenshots") != len(MAIN_FLOW_CAPTURES) or len(captures) != len(MAIN_FLOW_CAPTURES):
        errors.append("MainFlow requires all fifteen capture states")
    names = [capture.get("name") for capture in captures if isinstance(capture, dict) and type(capture.get("name")) is str]
    if len(names) != len(captures) or len(set(names)) != len(MAIN_FLOW_CAPTURES) or set(names) != set(MAIN_FLOW_CAPTURES):
        errors.append("MainFlow capture identities incomplete or duplicated")
    for capture in captures:
        if not isinstance(capture, dict):
            errors.append("MainFlow capture is not an object")
            continue
        name = capture.get("name")
        if type(name) is not str or name not in MAIN_FLOW_CAPTURES:
            errors.append("MainFlow capture identity invalid")
            continue
        for key in ("window_mode", "display_window_mode"):
            if type(capture.get(key)) is not int or capture.get(key) != 0:
                errors.append("MainFlow capture requires normal window: " + name + "/" + key)
        if capture.get("window_visible") is not True or capture.get("focused") is not True or capture.get("actual_rendering_driver") != "vulkan":
            errors.append("MainFlow capture host/driver invalid: " + name)
        size = capture.get("size")
        if size != [1280, 720] or any(type(value) is not int for value in size):
            errors.append("MainFlow capture declared size invalid: " + name)
        relative = "reports/runtime/" + name + ".png"
        if capture.get("path") != "res://" + relative:
            errors.append("MainFlow capture path does not match identity: " + name)
        path = base / relative
        try:
            if png_dimensions(path) != (1280, 720):
                errors.append("MainFlow capture actual PNG size invalid: " + name)
            if hashlib.sha256(path.read_bytes()).hexdigest() != capture.get("sha256"):
                errors.append("MainFlow capture PNG SHA differs: " + name)
        except (OSError, ValueError) as error:
            errors.append("MainFlow capture PNG invalid: " + name + "/" + str(error))
    return errors


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def project_context(root: Path | None = None) -> dict:
    source = ((ROOT if root is None else root) / "project.godot").read_bytes()
    match = re.search(r'^\s*config/version\s*=\s*"([^"\r\n]+)"\s*$', source.decode("utf-8-sig"), re.MULTILINE)
    if match is None:
        raise ValueError("project.godot has no application config/version")
    return {"program_version": match.group(1), "project_sha256": hashlib.sha256(source).hexdigest()}


def case_artifact_context(case: CheckCase, root: Path | None = None) -> dict:
    base = ROOT if root is None else root
    context = {key: hashlib.sha256((base / relative).read_bytes()).hexdigest() for key, relative in case.report_hashes}
    if case.script_hashes:
        context["scripts_sha256"] = {relative: hashlib.sha256((base / relative).read_bytes()).hexdigest() for relative in case.script_hashes}
    if case.require_gdd_version:
        document = (base / "docs/GAME_DESIGN.md").read_text(encoding="utf-8-sig")
        header = re.search(r'^> 文档 v([^\s]+)\s+·', document, re.MULTILINE)
        if header is None:
            raise ValueError("same-project GDD version header missing")
        context["gdd_version"] = header.group(1)
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
    qa_launch.assert_safe_path(path, ROOT, "reports")
    temporary = path.with_name(path.name + ".tmp")
    qa_launch.assert_safe_path(temporary, ROOT, "reports")
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
    if case.name == "MainFlow":
        result["errors"].extend(main_flow_check(report))
    if case.name == "CampaignJourney":
        restart = report.get("restart", {})
        result["errors"].extend(qa_launch.audit_record(restart.get("qa_startup", {}), ROOT, fatal_lines))


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
    evidence = None
    try:
        # Deletion, not an mtime-only comparison, prevents reuse of an old PASS.
        qa_launch.preflight_project(ROOT)
        qa_launch.assert_safe_path(ROOT / "reports" / case.report_file, ROOT, "reports").unlink(missing_ok=True)
        if project_context() != expected:
            raise ValueError("project_changed_before_case")
        result["artifact_sha256"] = case_artifact_context(case)
        evidence = qa_launch.prepare_launch(command, ROOT, case.name, background=case.headless)
        command = evidence.command
        result["command_line"] = command
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
    if evidence is not None:
        result["qa_startup"] = qa_launch.validate_evidence(evidence, fatal_lines)
        result["errors"].extend(result["qa_startup"]["errors"])
    result["fatal_log_lines"] = fatal_lines(output)
    result["diagnostic_log_lines"] = diagnostic_lines(output)
    if result["fatal_log_lines"]:
        result["errors"].append("fatal_error_or_leak_log")
    try:
        qa_launch.assert_safe_path(ROOT / "reports" / f"{case.name}.log", ROOT, "reports").write_text(output, encoding="utf-8")
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
    qa_launch.preflight_project(ROOT)
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
