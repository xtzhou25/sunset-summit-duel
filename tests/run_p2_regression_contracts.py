#!/usr/bin/env python3
"""Run legacy P2 scene contracts with isolated writable user data per suite."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
SUITES = [
    ("feedback_test", ["--require-strong"]),
    ("punch_feedback_test", ["--require-new"]),
    ("roundhouse_feedback_test", ["--require-new"]),
    ("signature_scene_test", ["--require-new"]),
    ("spacing_scene_test", []),
    ("spacing_bounds_test", []),
    ("signature_bounds_test", []),
    ("presentation_v3_test", []),
    ("integration_test", []),
    ("camera_test", []),
    ("projectile_view_test", []),
]


def source_hashes():
    paths = [ROOT / "project.godot", ROOT / "main.tscn"]
    paths += sorted((ROOT / "scripts").glob("*.gd"))
    paths += sorted((ROOT / "assets").glob("*.glb"))
    paths += [ROOT / "assets/signature_markers.json"]
    paths += [ROOT / "tests" / f"{name}.gd" for name, _ in SUITES]
    paths += [ROOT / "tests/p2_audio_assertions.gd"]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--log-dir", type=Path, default=ROOT / "exports/qa-p2/final")
    parser.add_argument("--timeout", type=float, default=180)
    args = parser.parse_args()
    godot = shutil.which(args.godot)
    if godot is None:
        parser.error(f"Godot executable unavailable: {args.godot}")
    args.log_dir.mkdir(parents=True, exist_ok=True)
    before = source_hashes()
    results = []
    godot_version = ""
    for name, flags in SUITES:
        command = [godot, "--headless", "--path", str(ROOT), "--script", f"tests/{name}.gd"]
        if flags:
            command += ["--", *flags]
        started = time.monotonic()
        with tempfile.TemporaryDirectory(prefix=f"p2-{name}-", dir="/tmp") as user_dir:
            env = os.environ.copy()
            for key, folder in [("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache")]:
                path = Path(user_dir) / folder
                path.mkdir()
                env[key] = str(path)
            try:
                proc = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, text=True, timeout=args.timeout)
                output, returncode = proc.stdout, proc.returncode
            except subprocess.TimeoutExpired as error:
                output = error.stdout or b""
                if isinstance(output, bytes):
                    output = output.decode("utf-8", errors="replace")
                output += f"\nRUNNER TIMEOUT after {args.timeout}s\n"
                returncode = 124
        (args.log_dir / f"{name}.log").write_text(output)
        if not godot_version:
            godot_version = next((line for line in output.splitlines() if line.startswith("Godot Engine v")), "")
        count_match = re.search(r"checks: (\d+); failures: (\d+)", output)
        check_count = int(count_match.group(1)) if count_match else len(re.findall(r"^(?:PASS[: ]|CAMERA .*pass true)", output, re.M))
        failures = int(count_match.group(2)) if count_match else len(re.findall(r"^FAIL[: ]", output, re.M))
        errors = [line for line in output.splitlines() if re.match(r"(?:SCRIPT ERROR:|ERROR:|WARNING:)", line)]
        shutdown_only = all("ObjectDB instances leaked at exit" in line or "resources still in use at exit" in line for line in errors)
        passed = returncode == 0 and failures == 0 and shutdown_only
        status = "pass_with_audio_shutdown_warnings" if passed and errors else ("pass" if passed else "fail")
        result = {"suite": name, "status": status, "checks": check_count, "failures": failures,
                  "returncode": returncode, "seconds": round(time.monotonic() - started, 3),
                  "command": command, "diagnostics": errors, "log": f"{name}.log"}
        results.append(result)
        print(f"{name}: {status}; checks={check_count}; failures={failures}; exit={returncode}", flush=True)
    after = source_hashes()
    changed = sorted(key for key in before if before[key] != after.get(key))
    report = {"completed_utc": datetime.now(timezone.utc).isoformat(),
              "scope": "Headless legacy scene/pose/input/audio-dispatch regressions; not auditory or GPU/browser certification.",
              "godot": godot_version,
              "suite_count": len(results), "checks": sum(item["checks"] for item in results),
              "failed_suites": [item["suite"] for item in results if item["status"] == "fail"],
              "source_changed_during_run": changed, "source_sha256": after, "suites": results}
    (args.log_dir / "legacy-regressions.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Total checks: {report['checks']}; failed suites: {len(report['failed_suites'])}; changed sources: {changed}")
    return int(bool(report["failed_suites"] or changed))


if __name__ == "__main__":
    raise SystemExit(main())
