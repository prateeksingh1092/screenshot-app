"""Pixel-free performance measurement and report interface; Python standard library only."""
import json
import math
import re


def parse_gpu(contents):
    devices = json.loads(contents).get("SPDisplaysDataType", [])
    descriptions = []
    for device in devices:
        model = device.get("sppci_model", "unknown")
        if not isinstance(model, str) or not re.fullmatch(r"[A-Za-z0-9 ()+.,_-]{1,100}", model):
            model = "unknown"
        descriptions.append(f"{model} ({len(device.get('spdisplays_ndrvs', []))} attached displays)")
    return ("; ".join(descriptions) if descriptions else "GPU inventory unavailable") + "; render GPU unconfirmed"


def condition_issues(power, thermal, state, cooldown_seconds):
    issues = []
    if not re.search(r"^Now drawing from 'AC Power'", power, re.MULTILINE):
        issues.append("AC power not confirmed")
    if type(state) is not int or state != 0:
        issues.append("thermal state is not nominal")
    for key in ("CPU_Speed_Limit", "CPU_Scheduler_Limit"):
        if key in thermal and not re.search(r"\b" + key + r"\s*=\s*100\b", thermal):
            issues.append("CPU throttling reported or unreadable")
    if cooldown_seconds < 300:
        issues.append("five-minute continuous cool-down not completed")
    return issues


def statistics(values):
    if len(values) != 20 or any(type(v) not in (int, float) or
                               not math.isfinite(v) or v < 0 for v in values):
        raise ValueError("exactly 20 finite nonnegative runs required")
    ordered = sorted(values)
    return {"count": 20, "median": (ordered[9] + ordered[10]) / 2,
            "p95": ordered[18]}  # nearest rank: ceil(0.95 * 20)


def latency_metrics(interval):
    if set(interval) != {"start_low_ns", "start_high_ns", "end_low_ns", "end_high_ns"}:
        raise ValueError("unexpected latency fields")
    if any(type(v) is not int or v < 0 for v in interval.values()):
        raise ValueError("latency clocks must be nonnegative integer nanoseconds")
    a, b, c, d = (interval[k] for k in
                  ("start_low_ns", "start_high_ns", "end_low_ns", "end_high_ns"))
    if a > b or c > d or d < b or c < a:
        raise ValueError("invalid latency clock ordering")
    low, high = max(0, c - b) / 1e6, (d - a) / 1e6
    return {"low_ms": low, "high_ms": high, "mid_ms": (low + high) / 2,
            "error_ms": (high - low) / 2}


def parse_app_row(line, expected_run):
    row = json.loads(line)
    if not isinstance(row, dict) or set(row) != {"run", "start_ns", "end_ns"}:
        raise ValueError("app log schema is run/start_ns/end_ns only")
    if type(row["run"]) is not int or row["run"] != expected_run:
        raise ValueError("app log run numbers must be 1 through 20 in order")
    interval = {"start_low_ns": row["start_ns"], "start_high_ns": row["start_ns"],
                "end_low_ns": row["end_ns"], "end_high_ns": row["end_ns"]}
    latency_metrics(interval)
    return interval


def parse_app_log(contents):
    rows = [line for line in contents.splitlines() if line.strip()]
    if len(rows) != 20:
        raise ValueError("app log must contain exactly 20 rows")
    return [parse_app_row(line, i) for i, line in enumerate(rows, 1)]


def format_report(metadata, idle_runs, latency_runs, method, dry_run=False):
    if method not in ("external-window", "app-monotonic"):
        raise ValueError("unknown latency method")
    if len(idle_runs) != 20 or len(latency_runs) != 20:
        raise ValueError("report requires 20 idle and 20 latency runs")
    latency = [latency_metrics(row) for row in latency_runs]
    lines = ["# Performance baseline", "",
             "DRY RUN — synthetic counters, not a baseline" if dry_run else "Measured session",
             ""]
    for key in ("date", "os_build", "architecture", "tool", "gpu"):
        lines.append(f"{key}: {metadata[key]}")
    if not metadata["low_power_confirmed"]:
        lines.append("FLAG: low-power GPU unconfirmed; cannot ratify ticket 38 targets.")
    lines += ["", "arm64 not executed" if metadata["architecture"] == "x86_64" else
              "Architecture execution is recorded above.", "",
              "20 runs; p95 is nearest rank (19th sorted value). CPU: percent of one core.",
              "Idle: 600 seconds minimum per run, 300 seconds continuous cool-down.",
              ("Conditions above describe the real-run protocol; dry run did not wait or measure targets." if dry_run else
               "AC and nominal thermal state checked during cool-down and each run."), "",
              "| Metric | Median | p95 |", "| --- | ---: | ---: |"]
    for key in ("seconds", "cpu_percent_one_core", "package_wakeups_per_second",
                "interrupt_wakeups_per_second", "footprint_end_bytes",
                "footprint_peak_sampled_bytes"):
        summary = statistics([r[key] for r in idle_runs])
        lines.append(f"| {key} | {summary['median']:.6g} | {summary['p95']:.6g} |")
    for key in ("mid_ms", "low_ms", "high_ms"):
        summary = statistics([r[key] for r in latency])
        lines.append(f"| latency_{key} | {summary['median']:.6g} | {summary['p95']:.6g} |")
    error = max(row["error_ms"] for row in latency)
    lines += ["", f"Latency method: {method}. Maximum interval half-width: ±{error:.3f} ms."]
    if method == "external-window":
        lines += ["Window-availability proxy: mouse release to matching on-screen window.",
                  "Polling bounds exclude HID delivery and window-to-visible-pixels bias; those are uncalibrated.",
                  "This is not a validated visible-thumbnail latency or comparable directly to app timestamps."]
    else:
        lines += ["App timestamps share one monotonic clock. Zero polling interval does not imply zero clock/instrumentation error."]
    lines += ["", "Per-run latency brackets (ms):", "",
              "| Run | Lower | Upper | Half-width |", "| --- | ---: | ---: | ---: |"]
    for index, row in enumerate(latency, 1):
        lines.append(f"| {index} | {row['low_ms']:.3f} | {row['high_ms']:.3f} | {row['error_ms']:.3f} |")
    return "\n".join(lines) + "\n"


def parse_sample(line):
    sample = json.loads(line)
    fields = {"pid", "identity", "monotonic_ns", "cpu_ns", "package_wakeups",
              "interrupt_wakeups", "phys_footprint"}
    if not isinstance(sample, dict) or set(sample) != fields:
        raise ValueError("sample must contain only the documented numeric fields")
    if any(type(v) is not int or v < 0 for v in sample.values()):
        raise ValueError("sample counters must be nonnegative integers")
    if not sample["pid"] or not sample["identity"]:
        raise ValueError("sample must identify a live process")
    return sample


def idle_metrics(samples):
    if len(samples) < 2:
        raise ValueError("idle measurement needs at least two samples")
    for sample in samples:
        parse_sample(json.dumps(sample))
    for before, after in zip(samples, samples[1:]):
        if any(before[k] != after[k] for k in ("pid", "identity")):
            raise ValueError("process exited or PID was reused")
        if after["monotonic_ns"] <= before["monotonic_ns"]:
            raise ValueError("sample clock did not advance")
        if any(after[k] < before[k] for k in
               ("cpu_ns", "package_wakeups", "interrupt_wakeups")):
            raise ValueError("kernel counter reset")
    first, last = samples[0], samples[-1]
    elapsed = (last["monotonic_ns"] - first["monotonic_ns"]) / 1e9
    if elapsed < 600:
        raise ValueError("idle interval must cover at least ten minutes")
    return {
        "seconds": elapsed,
        "cpu_percent_one_core": (last["cpu_ns"] - first["cpu_ns"]) / 1e9 / elapsed * 100,
        "package_wakeups_per_second": (last["package_wakeups"] - first["package_wakeups"]) / elapsed,
        "interrupt_wakeups_per_second": (last["interrupt_wakeups"] - first["interrupt_wakeups"]) / elapsed,
        "footprint_end_bytes": last["phys_footprint"],
        "footprint_peak_sampled_bytes": max(s["phys_footprint"] for s in samples),
    }
