"""Read-only source project verification; writes evidence only in this new project."""
import argparse, hashlib, json, subprocess
from pathlib import Path

SOURCE = Path(r"F:\godotProject\TowerDefense")
ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "docs/reviews/source_snapshot.json"

def snapshot():
    files = {}
    for directory in ("scripts", "scenes", "tests", "tools"):
        for p in (SOURCE / directory).rglob("*"):
            if p.is_file() and p.suffix in (".gd", ".tscn", ".py", ".ps1", ".json") and "__pycache__" not in p.parts:
                files[p.relative_to(SOURCE).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    for name in ("project.godot", "AGENTS.md", "README.md", ".gitignore"):
        files[name] = hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
    for p in (SOURCE / "docs").rglob("*.md"):
        files[p.relative_to(SOURCE).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    run = lambda *args: subprocess.check_output(["git", "-C", str(SOURCE), *args]).decode("utf-8", "replace")
    return {"source": str(SOURCE), "head": run("rev-parse", "HEAD").strip(), "branch": run("branch", "--show-current").strip(), "status": run("status", "--porcelain=v1"), "files": files}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("snapshot", "verify"))
    args = parser.parse_args()
    current = snapshot()
    if args.action == "snapshot":
        if REPORT.exists(): raise SystemExit("Baseline already exists; refusing replacement")
        REPORT.write_text(json.dumps(current, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Recorded {len(current['files'])} read-only source hashes")
    else:
        baseline = json.loads(REPORT.read_text(encoding="utf-8"))
        changed = [k for k in set(baseline['files']) | set(current['files']) if baseline['files'].get(k) != current['files'].get(k)]
        result = {"passed": not changed and all(baseline[k] == current[k] for k in ("head", "branch", "status")), "hashed_files": len(current['files']), "changed_files": sorted(changed), "git_head_unchanged": baseline['head'] == current['head'], "git_branch_unchanged": baseline['branch'] == current['branch'], "git_status_unchanged": baseline['status'] == current['status']}
        (ROOT / "docs/reviews/source_verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(result, ensure_ascii=False))
        raise SystemExit(0 if result['passed'] else 1)
