"""Render and verify twelve native, transparent Spine idle portraits locally."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import time
import zlib

try:
    from .run_checks import fatal_lines, diagnostic_lines
except ImportError:
    from run_checks import fatal_lines, diagnostic_lines

import qa_launch

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = Path("F:/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe")
MARKER = "SPINE_PORTRAITS_COMPLETE "


def project_version(root: Path) -> str:
    match = re.search(r'^\s*config/version\s*=\s*"([^"\r\n]+)"\s*$',
                      (root / "project.godot").read_text(encoding="utf-8-sig"), re.MULTILINE)
    if match is None:
        raise ValueError("project.godot has no program version")
    return match.group(1)


def _paeth(a: int, b: int, c: int) -> int:
    value = a + b - c
    pa, pb, pc = abs(value-a), abs(value-b), abs(value-c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)


def png_alpha(path: Path) -> dict:
    """Read RGBA8 PNG alpha without Pillow; RGB channels need not be unfiltered."""
    source = path.read_bytes()
    if source[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    cursor, compressed, header = 8, bytearray(), None
    while cursor < len(source):
        length = struct.unpack_from(">I", source, cursor)[0]
        kind = source[cursor+4:cursor+8]
        chunk = source[cursor+8:cursor+8+length]
        if cursor + length + 12 > len(source):
            raise ValueError("truncated PNG chunk")
        crc = struct.unpack_from(">I", source, cursor+8+length)[0]
        if zlib.crc32(kind + chunk) & 0xffffffff != crc:
            raise ValueError("PNG CRC mismatch")
        if kind == b"IHDR": header = struct.unpack(">IIBBBBB", chunk)
        if kind == b"IDAT": compressed.extend(chunk)
        cursor += length + 12
        if kind == b"IEND": break
    if header is None:
        raise ValueError("PNG has no IHDR")
    width, height, bits, color, compression, filtering, interlace = header
    if not width or not height or (bits, color, compression, filtering, interlace) != (8, 6, 0, 0, 0):
        raise ValueError("expected non-interlaced RGBA8 PNG")
    if width > 4096 or height > 4096:
        raise ValueError("portrait exceeds maximum raster size")
    data = memoryview(zlib.decompress(compressed))
    stride = width * 4
    if len(data) != height * (stride + 1):
        raise ValueError("PNG scanline length mismatch")
    previous = bytearray(width)
    nonzero = 0
    xmin, ymin, xmax, ymax = width, height, -1, -1
    for y in range(height):
        offset = y * (stride + 1)
        filter_type = data[offset]
        alpha = bytearray(data[offset+4:offset+stride+1:4])
        if filter_type > 4:
            raise ValueError("invalid PNG row filter")
        for x in range(width):
            left = alpha[x-1] if x else 0
            above = previous[x]
            upper_left = previous[x-1] if x else 0
            if filter_type == 1: alpha[x] = (alpha[x]+left) & 255
            elif filter_type == 2: alpha[x] = (alpha[x]+above) & 255
            elif filter_type == 3: alpha[x] = (alpha[x]+(left+above)//2) & 255
            elif filter_type == 4: alpha[x] = (alpha[x]+_paeth(left,above,upper_left)) & 255
            if alpha[x]:
                nonzero += 1
                xmin, xmax = min(xmin,x), max(xmax,x)
                ymin, ymax = min(ymin,y), max(ymax,y)
        previous = alpha
    return {"width":width,"height":height,"nonzero_alpha_pixels":nonzero,
            "transparent_pixels":width*height-nonzero,"alpha_bounds":[xmin,ymin,xmax,ymax]}


def validate_portraits(root: Path = ROOT, fresh_after_ns: int | None = None) -> dict:
    directory = root / "assets" / "portraits"
    manifest_path = directory / "manifest.json"
    failures, checked = [], []
    result = {"program_version":project_version(root),"passed":False,"failures":failures,
              "entries":checked,"manifest":str(manifest_path)}
    try:
        if fresh_after_ns is not None and manifest_path.stat().st_mtime_ns < fresh_after_ns - 1_000_000:
            raise ValueError("portrait manifest is stale")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if not isinstance(manifest,dict): raise ValueError("portrait manifest must be an object")
        units = json.loads((root / "resources" / "units.json").read_text(encoding="utf-8"))
        expected = {key:str(value["visual_id"]) for key,value in units.items() if value.get("playable",False)}
        source_hash = hashlib.sha256((root / "resources" / "visuals.json").read_bytes()).hexdigest()
        if manifest.get("passed") is not True: failures.append("native generation did not pass")
        if manifest.get("program_version") != result["program_version"]: failures.append("program version mismatch")
        if manifest.get("visuals_sha256") != source_hash: failures.append("visual recipe source hash mismatch")
        if not manifest.get("rendering_adapter"): failures.append("native renderer was not recorded")
        entries = manifest.get("entries",[])
        if not isinstance(entries,list) or len(entries) != 12 or len(expected) != 12:
            raise ValueError("expected exactly twelve playable portrait entries")
        seen = set()
        for entry in entries:
            if not isinstance(entry,dict):
                failures.append("portrait entry must be an object")
                continue
            unit_id = entry.get("unit_id","")
            try:
                if unit_id not in expected or unit_id in seen: raise ValueError("unknown/duplicate unit_id")
                seen.add(unit_id)
                if entry.get("visual_id") != expected[unit_id]: raise ValueError("unit visual_id mismatch")
                if entry.get("png") != unit_id+".png" or not re.fullmatch(r"[a-z][a-z0-9_]*",unit_id):
                    raise ValueError("portrait filename must match the unit_id")
                if entry.get("native") is not True or entry.get("nonempty") is not True:
                    raise ValueError("placeholder/empty portrait is not accepted")
                path = directory / entry["png"]
                if hashlib.sha256(path.read_bytes()).hexdigest() != entry.get("sha256"):
                    raise ValueError("portrait SHA256 mismatch")
                alpha = png_alpha(path)
                if (alpha["width"],alpha["height"]) != (entry.get("width"),entry.get("height")):
                    raise ValueError("portrait dimension mismatch")
                if not alpha["nonzero_alpha_pixels"] or not alpha["transparent_pixels"]:
                    raise ValueError("portrait must have both native body and transparent area")
                x0,y0,x1,y1 = alpha["alpha_bounds"]
                if x0 <= 0 or y0 <= 0 or x1 >= alpha["width"]-1 or y1 >= alpha["height"]-1:
                    raise ValueError("portrait silhouette touches image edge")
                checked.append({**entry,"alpha_validation":alpha})
            except (ValueError,OSError,KeyError,TypeError,struct.error,zlib.error) as exc:
                failures.append(f"{unit_id}: {exc}")
        if seen != set(expected): failures.append("portrait set does not cover all playable units")
        result["visuals_sha256"] = source_hash
    except (ValueError,OSError,KeyError,TypeError,struct.error,zlib.error) as exc:
        failures.append(str(exc))
    result["passed"] = not failures and len(checked) == 12
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",type=Path)
    parser.add_argument("--rendering-method",choices=["gl_compatibility","mobile"])
    parser.add_argument("--timeout",type=int,default=300)
    parser.add_argument("--check",action="store_true",help="validate existing PNGs without starting Godot")
    args = parser.parse_args(argv)
    qa_launch.preflight_project(ROOT, gameplay=not args.check)
    manifest_path = qa_launch.assert_safe_path(ROOT / "assets" / "portraits" / "manifest.json", ROOT, "assets/portraits")
    qa_launch.inspect_existing_tree(manifest_path.parent)
    report_path = qa_launch.assert_safe_path(ROOT / "reports" / "portraits_local.json", ROOT, "reports")
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.unlink(missing_ok=True)
    if args.check:
        report = validate_portraits()
    else:
        godot = args.godot or (ROOT / "FantasySiege.exe" if (ROOT / "FantasySiege.exe").exists() else DEFAULT_GODOT)
        if godot.name.endswith("_console.exe") and godot.with_name(godot.name.replace("_console.exe",".exe")).exists():
            godot = godot.with_name(godot.name.replace("_console.exe",".exe"))
        manifest_path.unlink(missing_ok=True)
        command = [str(godot),"--path",str(ROOT),"--script","res://tests/SpinePortraits.gd","--render-thread","safe"]
        if args.rendering_method: command.extend(["--rendering-method",args.rendering_method])
        startupinfo, flags = None, 0
        if os.name == "nt":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startupinfo.wShowWindow = subprocess.SW_HIDE
            flags = subprocess.CREATE_NO_WINDOW
        started = time.time_ns()
        evidence = None
        try:
            evidence = qa_launch.prepare_launch(command, ROOT, "portrait_render", background=True)
            command = evidence.command
            completed = subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                                       timeout=args.timeout,startupinfo=startupinfo,creationflags=flags)
            stdout = completed.stdout.decode("utf-8",errors="replace")
            stderr = completed.stderr.decode("utf-8",errors="replace")
            (ROOT / "reports" / "portrait_render.log").write_text(stdout,encoding="utf-8")
            (ROOT / "reports" / "portrait_render.err").write_text(stderr,encoding="utf-8")
            report = validate_portraits(fresh_after_ns=started)
            report.update({"command":command,"exit_code":completed.returncode,"diagnostics":diagnostic_lines(stdout+"\n"+stderr),"offscreen_only":True})
            if completed.returncode != 0: report["failures"].append(f"Godot exit {completed.returncode}")
            if not any(line.startswith(MARKER) for line in stdout.splitlines()): report["failures"].append("native completion marker missing")
            report["qa_startup"] = qa_launch.validate_evidence(evidence, fatal_lines)
            report["failures"].extend(report["qa_startup"]["errors"])
            report["failures"].extend(fatal_lines(stdout+"\n"+stderr))
            report["passed"] = report["passed"] and not report["failures"]
        except (OSError,ValueError,subprocess.TimeoutExpired) as exc:
            report = {"program_version":project_version(ROOT),"passed":False,"failures":[str(exc)],"entries":[],"offscreen_only":True}
            if evidence is not None:
                report["qa_startup"] = qa_launch.validate_evidence(evidence, fatal_lines)
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("PORTRAITS_CHECK_COMPLETE "+json.dumps({"passed":report["passed"],"portraits":len(report["entries"]),"failures":report["failures"],"report":str(report_path)},ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
