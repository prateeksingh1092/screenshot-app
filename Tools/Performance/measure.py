#!/usr/bin/env python3
"""Offline performance harness. Real measurement requires a present operator; never launches apps."""
import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

from baseline import (condition_issues, format_report, idle_metrics, latency_metrics,
                      parse_app_log, parse_gpu, parse_sample)

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / ".build/performance/probe"


def command(args):
    return subprocess.check_output([str(a) for a in args], text=True, stderr=subprocess.DEVNULL,
                                   timeout=30)


def conditions(cooldown=300):
    power = command(["/usr/bin/pmset", "-g", "batt"])
    thermal = command(["/usr/bin/pmset", "-g", "therm"])
    state = json.loads(command([PROBE, "thermal"]))["thermal_state"]
    issues = condition_issues(power, thermal, state, cooldown)
    # Persist only closed/numeric results, never raw command output.
    return {"ac": "AC power not confirmed" not in issues, "thermal_state": state,
            "checked_at": utc(), "issues": issues}


def require_good():
    result = conditions()
    if result["issues"]:
        raise ValueError("conditions refused: " + "; ".join(result["issues"]))
    return result


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def metadata(tool):
    try:
        gpu = parse_gpu(command(["/usr/sbin/system_profiler", "SPDisplaysDataType", "-json"]))
    except (subprocess.SubprocessError, ValueError):
        gpu = "GPU inventory unavailable; render GPU unconfirmed"
    return {"date": utc(), "os_build": command(["/usr/bin/sw_vers", "-buildVersion"]).strip(),
            "architecture": platform.machine(), "tool": tool, "gpu": gpu,
            "low_power_confirmed": False}


def save(path, document):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(document, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def cool_down():
    # No measurement interval begins until five uninterrupted nominal minutes pass.
    start = time.monotonic()
    while time.monotonic() - start < 300:
        require_good()
        time.sleep(5)
    return require_good()


def idle(args):
    record = {"schema": 1, "kind": "idle", "metadata": metadata(args.tool),
              "status": "partial", "runs": []}
    save(args.output, record)
    for index in range(20):
        print(f"Idle run {index + 1}/20: cool-down, then 600 seconds", flush=True)
        checks = [cool_down()]
        samples = [parse_sample(command([PROBE, "sample", args.pid]))]
        start = time.monotonic()
        last_wall = time.time()
        last_mono = time.monotonic()
        while samples[-1]["monotonic_ns"] - samples[0]["monotonic_ns"] < 600_000_000_000:
            time.sleep(min(5, max(0.01, 600 - (time.monotonic() - start))))
            wall, mono = time.time(), time.monotonic()
            # Sleep or wall-clock discontinuities invalidate the interval; do not hide them.
            if mono - last_mono > 15 or abs((wall - last_wall) - (mono - last_mono)) > 2:
                raise ValueError("sleep, clock discontinuity, or stalled sampler; restart session")
            last_wall, last_mono = wall, mono
            checks.append(require_good())
            samples.append(parse_sample(command([PROBE, "sample", args.pid])))
        record["runs"].append({"metrics": idle_metrics(samples), "samples": samples,
                               "conditions": checks})
        save(args.output, record)
    record["status"] = "complete"
    record["metadata_end"] = metadata(args.tool)
    save(args.output, record)


def latency(args):
    if args.tool == "frisket":
        raise ValueError("Frisket must use app-latency with app-logged monotonic timestamps")
    if args.tool == "snapzy":
        raise ValueError("Snapzy persists captures before its thumbnail. No-image-storage constraint blocks capture runs; see runbook.")
    if not args.no_image_storage_verified:
        raise ValueError("operator must verify a no-image-storage capture route before observing latency")
    record = {"schema": 1, "kind": "latency", "method": "external-window",
              "metadata": metadata(args.tool), "status": "partial", "runs": []}
    save(args.output, record)
    for index in range(20):
        input(f"Run {index + 1}/20: thumbnail absent; press Return before five-minute cool-down. ")
        before = cool_down()
        print("ARMED: operator selects only synthetic pattern content within 60 seconds.", flush=True)
        # Start/end are observed externally. All capture/launch input is human-operated.
        process = subprocess.Popen([str(PROBE), "observe", "--operator-approved", str(args.pid)] +
                                   [str(v) for v in args.thumbnail_rect], stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, text=True)
        checks = [before]
        deadline = time.monotonic() + 65
        try:
            while process.poll() is None:
                checks.append(require_good())
                if time.monotonic() > deadline:
                    raise ValueError("observation timed out")
                time.sleep(1)
            output = process.communicate()[0]
            if process.returncode:
                raise ValueError("observer failed; no sample recorded (check PID, rectangle, or timeout)")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        interval = json.loads(output)
        latency_metrics(interval)
        checks.append(require_good())
        if input("Was the detected window the new thumbnail? Type yes: ").strip() != "yes":
            raise ValueError("unconfirmed window classification; restart session")
        record["runs"].append({"interval": interval, "conditions": checks})
        save(args.output, record)
    record["status"] = "complete"
    record["metadata_end"] = metadata(args.tool)
    save(args.output, record)


def app_latency(args):
    if args.log.exists() and args.log.stat().st_size:
        raise ValueError("app log must be new/empty; do not mix sessions")
    record = {"schema": 1, "kind": "latency", "method": "app-monotonic",
              "metadata": metadata("frisket"), "status": "partial", "runs": []}
    save(args.output, record)
    for index in range(20):
        input(f"Frisket run {index + 1}/20: press Return to begin cool-down. ")
        checks = [cool_down()]
        print("ARMED: human triggers one synthetic capture; waiting for app log.", flush=True)
        deadline = time.monotonic() + 60
        while True:
            checks.append(require_good())
            contents = args.log.read_text() if args.log.exists() else ""
            # A row is committed only by its trailing newline.
            rows = contents.splitlines() if contents.endswith("\n") else contents.splitlines()[:-1]
            if len(rows) > index + 1:
                raise ValueError("extra app captures; restart session")
            if len(rows) == index + 1:
                row = json.loads(rows[-1])
                if set(row) != {"run", "start_ns", "end_ns"} or row["run"] != index + 1:
                    raise ValueError("invalid app log schema or run number")
                interval = dict(start_low_ns=row["start_ns"], start_high_ns=row["start_ns"],
                                end_low_ns=row["end_ns"], end_high_ns=row["end_ns"])
                latency_metrics(interval)
                break
            if time.monotonic() > deadline:
                raise ValueError("app log timed out")
            time.sleep(1)
        record["runs"].append({"interval": interval, "conditions": checks})
        save(args.output, record)
    parse_app_log(args.log.read_text())
    record["status"] = "complete"
    record["metadata_end"] = metadata("frisket")
    save(args.output, record)


def report(args):
    idle_data, latency_data = (json.loads(Path(p).read_text()) for p in (args.idle, args.latency))
    for data, kind in ((idle_data, "idle"), (latency_data, "latency")):
        if data.get("status") != "complete" or data.get("kind") != kind or data.get("schema") != 1:
            raise ValueError("only complete schema-1 sessions can produce a baseline")
        for run in data["runs"]:
            if not run.get("conditions") or any(c["issues"] or not c["ac"] or
                                                c["thermal_state"] != 0 for c in run["conditions"]):
                raise ValueError("missing or bad recorded conditions")
    for key in ("tool", "os_build", "architecture"):
        if idle_data["metadata"][key] != latency_data["metadata"][key]:
            raise ValueError("cannot combine different tools, OS builds, or architectures")
    text = format_report(idle_data["metadata"],
                         [idle_metrics(r["samples"]) for r in idle_data["runs"]],
                         [r["interval"] for r in latency_data["runs"]], latency_data["method"])
    text += f"\nLatency session date: {latency_data['metadata']['date']}\n"
    for data in (idle_data, latency_data):
        text += f"\n{data['kind']} GPU at end: {data['metadata_end']['gpu']}\n"
    Path(args.output).write_text(text)


def dry_run(args):
    # Exercises host metadata and self rusage only. No UI enumeration/capture or operator gate.
    host = metadata(args.tool)
    live_conditions = conditions(cooldown=0)
    own = parse_sample(command([PROBE, "sample", os.getpid()]))
    runs, intervals = [], []
    for i in range(20):
        first = dict(own)
        last = dict(first, monotonic_ns=first["monotonic_ns"] + 600_000_000_000,
                    cpu_ns=first["cpu_ns"] + 3_000_000_000,
                    package_wakeups=first["package_wakeups"] + 60,
                    interrupt_wakeups=first["interrupt_wakeups"] + 120)
        runs.append(idle_metrics([first, last]))
        intervals.append(dict(start_low_ns=0, start_high_ns=5_000_000,
                              end_low_ns=100_000_000 + i * 1_000_000,
                              end_high_ns=105_000_000 + i * 1_000_000))
    text = format_report(host, runs, intervals, "external-window", dry_run=True)
    text += "\nLive preflight (not a completed cool-down): " + json.dumps(live_conditions) + "\n"
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(text)
    print("Dry run complete; all baseline measurements remain pending.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode", required=True)
    for name in ("idle", "latency", "dry-run", "preflight"):
        sub = commands.add_parser(name)
        sub.add_argument("--tool", choices=("macos", "snapzy", "frisket"), required=True)
        if name != "preflight":
            sub.add_argument("--output", type=Path, required=True)
        if name in ("idle", "latency"):
            sub.add_argument("--pid", type=int, required=True)
            sub.add_argument("--operator-approved", action="store_true", required=True)
        if name == "latency":
            sub.add_argument("--thumbnail-rect", type=float, nargs=4, required=True,
                             metavar=("X", "Y", "WIDTH", "HEIGHT"))
            sub.add_argument("--no-image-storage-verified", action="store_true")
    sub = commands.add_parser("report")
    sub.add_argument("--idle", type=Path, required=True)
    sub.add_argument("--latency", type=Path, required=True)
    sub.add_argument("--output", type=Path, required=True)
    sub = commands.add_parser("app-latency")
    sub.add_argument("--log", type=Path, required=True)
    sub.add_argument("--output", type=Path, required=True)
    sub.add_argument("--operator-approved", action="store_true", required=True)
    args = parser.parse_args()
    if args.mode == "preflight":
        print(json.dumps({"metadata": metadata(args.tool), "conditions": conditions(0)}, indent=2))
    elif args.mode == "idle":
        idle(args)
    elif args.mode == "latency":
        latency(args)
    elif args.mode == "report":
        report(args)
    elif args.mode == "app-latency":
        app_latency(args)
    else:
        dry_run(args)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Measurement stopped: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("Interrupted; partial data is not a baseline.", file=sys.stderr)
        sys.exit(130)
