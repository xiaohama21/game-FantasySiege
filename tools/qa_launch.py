"""Prepare isolated Godot launches and verify their first-autoload evidence."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import time
import uuid

SCRIPT_PATHS = (
    "scripts/core/QAStartupContext.gd",
    "scripts/core/UserPrefs.gd",
    "scripts/core/ProfileStore.gd",
)
REPARSE_POINT = 0x400
QA_FLAGS = ("--qa-save-root", "--qa-startup-report", "--qa-background")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _bad_number(value):
    raise ValueError("non-finite JSON number: " + value)


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"), parse_constant=_bad_number)


def ensure_confined(path: Path, base: Path) -> Path:
    path, base = Path(path), Path(base)
    if not path.is_absolute() or not base.is_absolute():
        raise ValueError("QA paths must be absolute")
    try:
        relative = path.absolute().relative_to(base.absolute())
        path.resolve().relative_to(base.resolve())
    except ValueError as failure:
        raise ValueError("QA path leaves its allowed directory: " + str(path)) from failure
    if ".." in relative.parts:
        raise ValueError("QA path contains parent traversal")
    current = base
    for part in (None, *relative.parts):
        if part is not None:
            current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & REPARSE_POINT:
            raise ValueError("QA path contains a link/reparse point: " + str(current))
        if stat.S_ISREG(info.st_mode) and info.st_nlink > 1:
            raise ValueError("QA path contains a hardlinked file: " + str(current))
    return path.absolute()


def assert_safe_path(path: Path, project: Path, subtree: str) -> Path:
    """Reject existing links/reparse points/hardlinks before creating any QA files.

    This is a preflight check, not a claim of protection against another process
    replacing directories between validation and an engine I/O operation.
    """
    path, project = Path(path), Path(project)
    if not path.is_absolute() or not project.is_absolute():
        raise ValueError("QA paths must be absolute")
    project = project.absolute()
    base = project / subtree
    try:
        relative = path.absolute().relative_to(project)
        path.absolute().relative_to(base)
        path.resolve().relative_to(base.resolve())
    except ValueError as failure:
        raise ValueError("QA path leaves project " + subtree + ": " + str(path)) from failure
    if ".." in relative.parts:
        raise ValueError("QA path contains parent traversal")
    current = project
    for part in (None, *relative.parts):
        if part is not None:
            current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & REPARSE_POINT:
            raise ValueError("QA path contains a link/reparse point: " + str(current))
        if stat.S_ISREG(info.st_mode) and info.st_nlink > 1:
            raise ValueError("QA path contains a hardlinked file: " + str(current))
    return path.absolute()


def inspect_existing_save_tree(project: Path) -> None:
    """Cover paths which fixtures may select after the initial autoload."""
    base = assert_safe_path(project / "tests/.user", project, "tests/.user")
    inspect_existing_tree(base)


def inspect_existing_tree(base: Path) -> None:
    """Walk without following links; inspect each entry once before any writes."""
    if not base.exists():
        return
    for directory, directories, files in os.walk(base, followlinks=False):
        for name in (*directories, *files):
            path = Path(directory) / name
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & REPARSE_POINT:
                raise ValueError("QA tree contains a link/reparse point: " + str(path))
            if stat.S_ISREG(info.st_mode) and info.st_nlink > 1:
                raise ValueError("QA tree contains a hardlinked file: " + str(path))


def preflight_project(project: Path, *, gameplay: bool = True) -> None:
    """Call before launcher report preparation, not only before subprocess.run."""
    project = Path(project).absolute()
    reports = assert_safe_path(project / "reports", project, "reports")
    inspect_existing_tree(reports)
    if gameplay:
        inspect_existing_save_tree(project)


@dataclass(frozen=True)
class LaunchEvidence:
    command: list[str]
    project: Path
    save_root: Path | None
    startup_report: Path | None
    engine_log: Path
    started_ns: int
    script_sha256: dict[str, str]
    gameplay: bool


def prepare_launch(command: list[str], project: Path, label: str, *,
                   gameplay: bool = True, background: bool = False) -> LaunchEvidence:
    project = Path(project).absolute()
    command = list(map(str, command))
    if not command:
        raise ValueError("empty Godot launch command")
    if any(token == "--log-file" or token.startswith("--log-file=") or
           any(token == flag or token.startswith(flag + "=") for flag in QA_FLAGS)
           for token in command):
        raise ValueError("launch already contains reserved log/QA arguments")
    engine_args = command[:command.index("--")] if "--" in command else command
    if engine_args.count("--path") != 1 or engine_args.index("--path") + 1 >= len(engine_args):
        raise ValueError("Godot QA launch requires explicit project --path")
    requested = Path(engine_args[engine_args.index("--path") + 1])
    if not requested.is_absolute() or requested.resolve() != project.resolve():
        raise ValueError("Godot --path differs from QA project")
    safe_label = re.sub(r"[^a-zA-Z0-9_-]", "_", label)[:64] or "launch"
    unique = safe_label + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f") + "-" + uuid.uuid4().hex[:12]
    report_root = assert_safe_path(project / "reports/qa_startup" / unique, project, "reports")
    engine_log = assert_safe_path(report_root / "engine.log", project, "reports")
    startup_report = assert_safe_path(report_root / "startup.json", project, "reports") if gameplay else None
    save_root = assert_safe_path(project / "tests/.user/qa" / unique, project, "tests/.user") if gameplay else None
    # Check all inputs/targets before the first write. Missing runtime scripts is
    # an error for gameplay; an editor-only texture import need not have them.
    scripts = {relative: sha(project / relative) for relative in SCRIPT_PATHS} if gameplay else {}
    preflight_project(project, gameplay=gameplay)
    report_root.mkdir(parents=True, exist_ok=False)
    if save_root is not None:
        save_root.mkdir(parents=True, exist_ok=False)
        ignore = assert_safe_path(project / "tests/.user/.gdignore", project, "tests/.user")
        if not ignore.exists():
            ignore.write_text("", encoding="utf-8")
    split = command.index("--") if "--" in command else len(command)
    command[split:split] = ["--log-file", str(engine_log)]
    if gameplay:
        if "--" not in command:
            command.append("--")
        command.extend(["--qa-save-root", str(save_root), "--qa-startup-report", str(startup_report)])
        if background:
            command.append("--qa-background")
    return LaunchEvidence(command, project, save_root, startup_report, engine_log,
                          time.time_ns(), scripts, gameplay)


def _same_path(left, right) -> bool:
    return isinstance(left, str) and Path(left).is_absolute() and Path(left).resolve() == Path(right).resolve()


def _validate_startup(report: dict, record: dict, project: Path, expect_valid: bool) -> list[str]:
    errors = []
    if report.get("qa_enabled") is not True or report.get("valid") is not expect_valid:
        errors.append("QA startup context validity differs")
    if not _same_path(report.get("report_path"), record["startup_report"]):
        errors.append("QA startup report path differs")
    if expect_valid and not _same_path(report.get("save_root"), record["save_root"]):
        errors.append("QA startup save root differs")
    if report.get("script_sha256") != record["script_sha256"]:
        errors.append("QA startup script fingerprints differ")
    refused = report.get("refused_operations")
    if not isinstance(refused, list) or (expect_valid and refused):
        errors.append("QA startup refused-operation evidence invalid")
    if not expect_valid and not refused:
        errors.append("Invalid QA startup did not record refusal")
    operations = report.get("operations")
    if not isinstance(operations, list):
        errors.append("QA startup operation trace missing")
    else:
        for operation in operations:
            if not isinstance(operation, dict) or not isinstance(operation.get("path"), str):
                errors.append("QA startup operation record malformed")
                continue
            if operation.get("allowed") is not True or type(operation.get("ticks_usec")) is not int or not isinstance(operation.get("action"), str):
                errors.append("QA startup operation authorization/time missing")
            try:
                assert_safe_path(Path(operation["path"]), project, "tests/.user")
            except (OSError, ValueError) as failure:
                errors.append("QA startup operation outside isolation: " + str(failure))
        if not expect_valid and operations:
            errors.append("Invalid QA startup performed save I/O")
    first = report.get("first_loads")
    if expect_valid:
        if not isinstance(first, dict) or set(first) != {"preferences", "profile"}:
            errors.append("Both first-autoload records required")
        else:
            for owner, filename in (("preferences", "preferences.json"), ("profile", "profile.json")):
                entry = first.get(owner)
                if not isinstance(entry, dict) or not _same_path(entry.get("path"), Path(record["save_root"]) / filename):
                    errors.append("First autoload path differs: " + owner)
                if not isinstance(entry, dict) or not isinstance(entry.get("summary"), dict) or type(entry.get("ticks_usec")) is not int:
                    errors.append("First autoload summary/time missing: " + owner)
                if isinstance(entry, dict) and isinstance(operations, list):
                    reads = [operation for operation in operations if isinstance(operation, dict) and
                             operation.get("owner") == owner and str(operation.get("action", "")).startswith("read")]
                    if not reads or not _same_path(reads[0].get("path"), Path(record["save_root"]) / filename):
                        errors.append("First autoload read trace missing/differs: " + owner)
                    elif type(reads[0].get("ticks_usec")) is not int or reads[0]["ticks_usec"] > entry.get("ticks_usec", -1):
                        errors.append("First autoload trace is later than load: " + owner)
    return errors


def audit_record(record: dict, project: Path, fatal_validator=None, *, expect_valid: bool = True) -> list[str]:
    """Re-read evidence and actual payload files; no saved passed flag is trusted."""
    errors = []
    try:
        project = Path(project).absolute()
        if not isinstance(record, dict) or not _same_path(record.get("project_root"), project):
            raise ValueError("QA evidence project root differs")
        engine = assert_safe_path(Path(record["engine_log"]), project, "reports")
        if not engine.is_file() or engine.stat().st_size == 0:
            errors.append("QA engine log missing or empty")
        else:
            if sha(engine) != record.get("engine_log_sha256"):
                errors.append("QA engine log SHA differs")
            if engine.stat().st_mtime_ns + 1_000_000 < record["started_ns"]:
                errors.append("QA engine log predates process")
            if fatal_validator and fatal_validator(engine.read_text(encoding="utf-8", errors="replace")):
                errors.append("QA engine log contains errors/leaks")
        if record.get("gameplay") is True:
            assert_safe_path(Path(record["save_root"]), project, "tests/.user")
            startup = assert_safe_path(Path(record["startup_report"]), project, "reports")
            if not startup.is_file():
                errors.append("QA first-autoload report missing")
            else:
                if sha(startup) != record.get("startup_report_sha256"):
                    errors.append("QA startup report SHA differs")
                if startup.stat().st_mtime_ns + 1_000_000 < record["started_ns"]:
                    errors.append("QA startup report predates process")
                data = read_json(startup)
                if not isinstance(data, dict):
                    errors.append("QA startup report is not an object")
                else:
                    errors.extend(_validate_startup(data, record, project, expect_valid))
            actual = {relative: sha(project / relative) for relative in SCRIPT_PATHS}
            if record.get("script_sha256") != actual:
                errors.append("QA runtime scripts changed")
        elif record.get("gameplay") is not False:
            errors.append("QA gameplay scope missing")
    except (OSError, ValueError, KeyError, TypeError) as failure:
        errors.append("QA evidence unreadable: " + str(failure))
    return errors


def validate_evidence(evidence: LaunchEvidence, fatal_validator=None, *, expect_valid: bool = True) -> dict:
    record = {"gameplay": evidence.gameplay, "project_root": str(evidence.project),
              "save_root": str(evidence.save_root) if evidence.save_root else None,
              "startup_report": str(evidence.startup_report) if evidence.startup_report else None,
              "engine_log": str(evidence.engine_log), "started_ns": evidence.started_ns,
              "script_sha256": evidence.script_sha256, "startup_report_sha256": None,
              "engine_log_sha256": None, "engine_fatal_log_lines": []}
    if evidence.engine_log.is_file():
        record["engine_log_sha256"] = sha(evidence.engine_log)
        if fatal_validator:
            record["engine_fatal_log_lines"] = fatal_validator(evidence.engine_log.read_text(encoding="utf-8", errors="replace"))
    if evidence.startup_report and evidence.startup_report.is_file():
        record["startup_report_sha256"] = sha(evidence.startup_report)
    record["errors"] = audit_record(record, evidence.project, fatal_validator, expect_valid=expect_valid)
    record["passed"] = not record["errors"]
    return record
