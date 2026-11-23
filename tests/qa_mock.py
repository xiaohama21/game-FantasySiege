"""Write simulated process artifacts for launcher boundary unit tests only."""
import json
from pathlib import Path
import qa_launch


def scripts(project):
    for relative in qa_launch.SCRIPT_PATHS:
        path = project / relative
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("mock source: " + relative + "\n", encoding="utf-8")


def emit(command, project, *, fatal=""):
    """Mocks still exercise strict file/path/hash/startup gates."""
    engine = Path(command[command.index("--log-file") + 1])
    engine.write_text("Godot mock process evidence\n" + fatal, encoding="utf-8")
    if "--qa-startup-report" not in command:
        return
    startup = Path(command[command.index("--qa-startup-report") + 1])
    root = Path(command[command.index("--qa-save-root") + 1])
    report = {"qa_enabled": True, "valid": True, "project_root": str(project),
              "save_root": str(root), "report_path": str(startup), "first_loads": {},
              "operations": [], "refused_operations": [],
              "script_sha256": {relative: qa_launch.sha(project / relative) for relative in qa_launch.SCRIPT_PATHS}}
    for owner, filename in (("preferences", "preferences.json"), ("profile", "profile.json")):
        path = str(root / filename)
        report["operations"].append({"owner": owner, "action": "read", "path": path, "allowed": True, "ticks_usec": 1})
        report["first_loads"][owner] = {"owner": owner, "path": path, "summary": {}, "ticks_usec": 2, "blocked": False}
    startup.write_text(json.dumps(report), encoding="utf-8")


def record(project, label="mock"):
    scripts(project)
    evidence = qa_launch.prepare_launch(["unused", "--path", str(project), "--script", "res://tests/mock.gd"], project, label)
    emit(evidence.command, project)
    return qa_launch.validate_evidence(evidence)
