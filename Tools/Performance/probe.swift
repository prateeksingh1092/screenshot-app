// Development-only metadata probe. No pixels, event taps, input synthesis, or app launch.
import Foundation
import CoreGraphics
import Darwin

enum ProbeError: Error { case invalidArguments, unavailable, ambiguousWindow, timeout, thermal }

func emit(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

// CLOCK_MONOTONIC_RAW is monotonic nanoseconds, independent of wall-clock adjustment.
func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

func sample(_ pid: Int32) throws {
    var usage = rusage_info_v0()
    let status = withUnsafeMutablePointer(to: &usage) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V0, $0)
        }
    }
    guard status == 0 else { throw ProbeError.unavailable }
    try emit(["pid": pid, "identity": usage.ri_proc_start_abstime,
              "monotonic_ns": now(), "cpu_ns": usage.ri_user_time + usage.ri_system_time,
              "package_wakeups": usage.ri_pkg_idle_wkups,
              "interrupt_wakeups": usage.ri_interrupt_wkups,
              "phys_footprint": usage.ri_phys_footprint])
}

// Only retain IDs of matching windows. Never serialize titles, paths, other owners, or pixels.
func windows(_ pid: Int32, _ rect: CGRect) throws -> Set<UInt32> {
    guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]] else {
        throw ProbeError.unavailable
    }
    var result: Set<UInt32> = []
    for entry in entries {
        guard (entry[kCGWindowOwnerPID as String] as? Int32) == pid,
              let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              let id = entry[kCGWindowNumber as String] as? UInt32,
              let alpha = entry[kCGWindowAlpha as String] as? Double, alpha > 0 else { continue }
        // Bounds are supplied from operator calibration, in global screen points (not pixels).
        if abs(frame.minX - rect.minX) <= 4 && abs(frame.minY - rect.minY) <= 4 &&
           abs(frame.width - rect.width) <= 4 && abs(frame.height - rect.height) <= 4 {
            result.insert(id)
        }
    }
    return result
}

func observe(_ pid: Int32, _ rect: CGRect) throws {
    guard try windows(pid, rect).isEmpty else { throw ProbeError.ambiguousWindow }
    let deadline = now() + 60_000_000_000
    var held = false
    var lastDown: UInt64 = 0
    var start: (UInt64, UInt64)?
    var lastAbsent = now()
    while now() < deadline {
        guard ProcessInfo.processInfo.thermalState == .nominal else { throw ProbeError.thermal }
        let before = now()
        // Polling reads aggregate button state; it does not intercept or synthesize events.
        let down = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let after = now()
        if start == nil {
            if down { held = true; lastDown = before }
            if held && !down { start = (lastDown, after) }
        }
        let windowBefore = now()
        let matches = try windows(pid, rect)
        let windowAfter = now()
        guard matches.count <= 1 else { throw ProbeError.ambiguousWindow }
        if !matches.isEmpty {
            guard let start else { throw ProbeError.ambiguousWindow }
            try emit(["start_low_ns": start.0, "start_high_ns": start.1,
                      "end_low_ns": lastAbsent, "end_high_ns": windowAfter])
            return
        }
        lastAbsent = windowBefore
        usleep(5_000) // Actual measured brackets include query duration and scheduler delays.
    }
    throw ProbeError.timeout
}

func inventory(_ pid: Int32) throws {
    guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]] else {
        throw ProbeError.unavailable
    }
    for entry in entries {
        guard (entry[kCGWindowOwnerPID as String] as? Int32) == pid,
              let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              let id = entry[kCGWindowNumber as String] as? UInt32 else { continue }
        try emit(["id": id, "x": frame.minX, "y": frame.minY,
                  "width": frame.width, "height": frame.height])
    }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["thermal"] {
        try emit(["thermal_state": ProcessInfo.processInfo.thermalState.rawValue])
    } else if args.count == 2, args[0] == "sample", let pid = Int32(args[1]), pid > 0 {
        try sample(pid)
    } else if args.count == 3, args[0] == "inventory", args[1] == "--operator-approved",
              let pid = Int32(args[2]), pid > 0 {
        try inventory(pid)
    } else if args.count == 7, args[0] == "observe", args[1] == "--operator-approved",
              let pid = Int32(args[2]), pid > 0 {
        let values = args[3...6].compactMap(Double.init)
        guard values.count == 4, values.allSatisfy({ $0.isFinite }),
              values[2] > 0, values[3] > 0 else { throw ProbeError.invalidArguments }
        try observe(pid, CGRect(x: values[0], y: values[1], width: values[2], height: values[3]))
    } else {
        throw ProbeError.invalidArguments
    }
} catch {
    // Closed errors only. No arbitrary OS descriptions that could include private data.
    fputs("probe failed: \(error is ProbeError ? String(describing: error) : "serialization")\n", stderr)
    exit(1)
}
