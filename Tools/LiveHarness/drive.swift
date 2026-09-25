// Live harness driver (Tools/LiveHarness/README.md). Synthetic content only.
//
// Safety rails, all enforced here rather than by the caller:
// - keys and typing go out only while Frisket or the pattern tool is frontmost;
// - every pointer point must lie on an active display;
// - a click or drag may start only on a window owned by Frisket or the pattern tool
//   (`FRISKET_DRIVE_ALLOW_OWNERS=Finder,…` widens that for one command).
import AppKit
import ApplicationServices
import ImageIO

let frisketBundleIDs = ProcessInfo.processInfo.environment["FRISKET_BUNDLE_ID"].map { [$0] }
    ?? ["io.github.prateeksingh1092.frisket.debug", "io.github.prateeksingh1092.frisket"]
let patternName = "pattern"
let src = CGEventSource(stateID: .hidSystemState)

func die(_ s: String) -> Never { fputs(s + "\n", stderr); exit(2) }
func ms(_ v: Int) { usleep(useconds_t(v * 1000)) }

func frisketApp() -> NSRunningApplication? {
    frisketBundleIDs.lazy.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }.first
}
func frisketPID() -> pid_t {
    guard let app = frisketApp() else { die("Frisket is not running (bundle IDs \(frisketBundleIDs))") }
    return app.processIdentifier
}
/// A PID argument, or the words `frisket` / `pattern`.
func pidArgument(_ s: String) -> pid_t {
    switch s {
    case "frisket": return frisketPID()
    case patternName:
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == patternName }) else { die("pattern is not running") }
        return app.processIdentifier
    default:
        guard let pid = pid_t(s) else { die("bad pid \(s)") }
        return pid
    }
}

func frontInfo() -> (name: String, pid: pid_t) {
    let app = NSWorkspace.shared.frontmostApplication
    return (app?.localizedName ?? "?", app?.processIdentifier ?? 0)
}
func safeTarget() -> Bool {
    let f = frontInfo()
    // `FRISKET_DRIVE_ALLOW_FRONT="CleanShot X"` allows keys to one named comparator app for one command.
    let allowed = Set((ProcessInfo.processInfo.environment["FRISKET_DRIVE_ALLOW_FRONT"] ?? "").split(separator: ",").map(String.init))
    return f.pid == frisketApp()?.processIdentifier || f.name == patternName || allowed.contains(f.name)
}

func activeDisplays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &n)
    return Array(ids.prefix(Int(n)))
}
/// Refuses any point that isn't on an active display. The arrangement can change mid-run
/// (a lid closing once shifted every coordinate), so this is recomputed each time.
func requireOnDisplay(_ p: CGPoint) {
    // CGDisplayBounds is half-open; include the far edges so a display's last row and column count.
    guard activeDisplays().contains(where: { CGDisplayBounds($0).insetBy(dx: -0.5, dy: -0.5).contains(p) }) else {
        die("REFUSED: point \(p) is on no active display")
    }
}

struct WindowRow { let owner: String; let pid: Int; let id: Int; let layer: Int; let bounds: CGRect; let alpha: Double; let name: String }
func onScreenWindows() -> [WindowRow] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.map { w in
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        return WindowRow(owner: w[kCGWindowOwnerName as String] as? String ?? "", pid: w[kCGWindowOwnerPID as String] as? Int ?? 0,
                         id: w[kCGWindowNumber as String] as? Int ?? 0, layer: w[kCGWindowLayer as String] as? Int ?? 0,
                         bounds: CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0),
                         alpha: w[kCGWindowAlpha as String] as? Double ?? 1, name: w[kCGWindowName as String] as? String ?? "")
    }
}
/// The front-most visible window under a point, skipping the cursor and other Window Server surfaces.
func windowAt(_ p: CGPoint) -> WindowRow? {
    onScreenWindows().first { $0.bounds.contains(p) && $0.alpha > 0 && $0.owner != "Window Server" && !isDockBackdrop($0, p) }
}
/// On the main display the Dock owns a full-display window at layer 20 that passes clicks through
/// everywhere except the Dock itself. Skip it above the bottom 100 pt, where the Dock sits.
func isDockBackdrop(_ w: WindowRow, _ p: CGPoint) -> Bool {
    w.owner == "Dock" && w.name == "Dock" && w.bounds.width > 800 && p.y < w.bounds.maxY - 100
}
/// A press may only land on Frisket or the pattern tool, so a misread coordinate can't click another app.
func requireOwnTarget(_ p: CGPoint) {
    requireOnDisplay(p)
    let allowed = Set((ProcessInfo.processInfo.environment["FRISKET_DRIVE_ALLOW_OWNERS"] ?? "").split(separator: ",").map(String.init))
    guard let w = windowAt(p) else { die("REFUSED: no window under \(p)") }
    let own = w.pid == Int(frisketApp()?.processIdentifier ?? -1) || w.owner == patternName || allowed.contains(w.owner)
    guard own else { die("REFUSED: \(p) is on a window owned by \(w.owner.isEmpty ? "?" : w.owner)") }
}

func parseFlags(_ s: String?) -> CGEventFlags {
    var f: CGEventFlags = []
    guard let s else { return f }
    for p in s.split(separator: ",") {
        switch p {
        case "cmd": f.insert(.maskCommand)
        case "shift": f.insert(.maskShift)
        case "opt", "alt": f.insert(.maskAlternate)
        case "ctrl": f.insert(.maskControl)
        default: break
        }
    }
    return f
}

func modifierKeys(_ f: CGEventFlags) -> [CGKeyCode] {
    var k: [CGKeyCode] = []
    if f.contains(.maskCommand) { k.append(55) }
    if f.contains(.maskShift) { k.append(56) }
    if f.contains(.maskAlternate) { k.append(58) }
    if f.contains(.maskControl) { k.append(59) }
    return k
}

/// Posts modifier downs, the key, then modifier ups at the HID tap, so Carbon hot keys fire.
func postKey(_ code: CGKeyCode, _ f: CGEventFlags) {
    var held: CGEventFlags = []
    let mods = modifierKeys(f)
    let order: [(CGKeyCode, CGEventFlags)] = [(55, .maskCommand), (56, .maskShift), (58, .maskAlternate), (59, .maskControl)]
    for (key, flag) in order where mods.contains(key) {
        held.insert(flag)
        let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)!
        e.flags = held
        e.post(tap: .cghidEventTap)
        ms(15)
    }
    let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)!
    d.flags = f
    d.post(tap: .cghidEventTap)
    ms(30)
    let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)!
    u.flags = f
    u.post(tap: .cghidEventTap)
    ms(15)
    for (key, flag) in order.reversed() where mods.contains(key) {
        held.remove(flag)
        let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)!
        e.flags = held
        e.post(tap: .cghidEventTap)
        ms(15)
    }
    ms(40)
}

func typeString(_ s: String) {
    for ch in s {
        let units = Array(String(ch).utf16)
        let d = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)!
        d.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        d.post(tap: .cghidEventTap)
        ms(20)
        let u = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)!
        u.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        u.post(tap: .cghidEventTap)
        ms(30)
    }
}

func mouse(_ t: CGEventType, _ p: CGPoint, _ f: CGEventFlags = [], clicks: Int64 = 1) {
    let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!
    e.flags = f
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.post(tap: .cghidEventTap)
}

// MARK: AX helpers
func ax(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}
func axString(_ e: AXUIElement, _ a: String) -> String? {
    guard let v = ax(e, a) else { return nil }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    if CFGetTypeID(v) == AXValueGetTypeID() {
        let av = v as! AXValue
        switch AXValueGetType(av) {
        case .cgPoint: var p = CGPoint.zero; AXValueGetValue(av, .cgPoint, &p); return "\(p)"
        case .cgSize: var s = CGSize.zero; AXValueGetValue(av, .cgSize, &s); return "\(s)"
        case .cgRect: var r = CGRect.zero; AXValueGetValue(av, .cgRect, &r); return "\(r)"
        default: return "<axvalue>"
        }
    }
    return nil
}
func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = ax(e, kAXPositionAttribute), let sv = ax(e, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
    AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
func children(_ e: AXUIElement) -> [AXUIElement] { (ax(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func actions(_ e: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(e, &names) == .success, let n = names as? [String] else { return [] }
    return n
}
func describe(_ e: AXUIElement) -> String {
    var parts: [String] = []
    for (key, attr) in [("role", kAXRoleAttribute), ("sub", kAXSubroleAttribute), ("title", kAXTitleAttribute),
                        ("desc", kAXDescriptionAttribute), ("help", kAXHelpAttribute), ("id", kAXIdentifierAttribute),
                        ("value", kAXValueAttribute), ("enabled", kAXEnabledAttribute), ("focused", kAXFocusedAttribute),
                        ("roledesc", kAXRoleDescriptionAttribute)] {
        if let s = axString(e, attr), !s.isEmpty {
            let clipped = s.count > 240 ? String(s.prefix(240)) + "…" : s
            parts.append("\(key)=\(clipped.debugDescription)")
        }
    }
    if let f = frame(e) { parts.append("frame=\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))") }
    let a = actions(e).map { $0.hasPrefix("Name:") ? String($0.split(separator: "\n").first ?? "") : $0 }
    if !a.isEmpty { parts.append("actions=\(a)") }
    return parts.joined(separator: " ")
}
func windows(_ pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    return (ax(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
}
func dump(_ e: AXUIElement, depth: Int, max: Int) {
    print(String(repeating: "  ", count: depth) + describe(e))
    guard depth < max else { return }
    for c in children(e) { dump(c, depth: depth + 1, max: max) }
}
func roots(_ pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    var r = windows(pid)
    if let extras = ax(app, "AXExtrasMenuBar") { r.append(extras as! AXUIElement) }
    return r
}
func find(_ pid: pid_t, _ label: String, exact: Bool) -> AXUIElement? {
    func matches(_ e: AXUIElement) -> Bool {
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXHelpAttribute] {
            guard let s = axString(e, attr) else { continue }
            if exact ? s == label : s.localizedCaseInsensitiveContains(label) { return true }
        }
        return false
    }
    func walk(_ e: AXUIElement, _ d: Int) -> AXUIElement? {
        if matches(e) { return e }
        guard d < 14 else { return nil }
        for c in children(e) { if let f = walk(c, d + 1) { return f } }
        return nil
    }
    // An open History window has hundreds of rows; walking it made one search take 12 s (2026-09-25).
    // Search it only when the label is about History ("History captures…", "…selected History capture").
    let wantsHistory = label.localizedCaseInsensitiveContains("History")
    for r in roots(pid) {
        if !wantsHistory, axString(r, kAXTitleAttribute) == "Frisket History" { continue }
        if let f = walk(r, 0) { return f }
    }
    return nil
}


// MARK: Pasteboard
func clipSave(_ path: String) {
    let pb = NSPasteboard.general
    var items: [[String: Data]] = []
    for item in pb.pasteboardItems ?? [] {
        var d: [String: Data] = [:]
        for t in item.types { if let data = item.data(forType: t) { d[t.rawValue] = data } }
        items.append(d)
    }
    let data = try! PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0)
    // The saved clipboard is the user's own content: owner-only, and deleted by the caller after restore.
    FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
    print("saved \(items.count) item(s), changeCount=\(pb.changeCount), types=\(items.map { $0.keys.sorted() })")
}
func clipRestore(_ path: String) {
    let data = try! Data(contentsOf: URL(fileURLWithPath: path))
    let items = try! PropertyListSerialization.propertyList(from: data, format: nil) as! [[String: Data]]
    let pb = NSPasteboard.general
    pb.clearContents()
    let objs: [NSPasteboardItem] = items.map { dict in
        let it = NSPasteboardItem()
        for (t, d) in dict { it.setData(d, forType: NSPasteboard.PasteboardType(t)) }
        return it
    }
    if !objs.isEmpty { pb.writeObjects(objs) }
    print("restored \(objs.count) item(s)")
}
func clipInfo() {
    let pb = NSPasteboard.general
    print("changeCount=\(pb.changeCount)")
    for (i, item) in (pb.pasteboardItems ?? []).enumerated() {
        let desc = item.types.map { t -> String in "\(t.rawValue)(\(item.data(forType: t)?.count ?? -1)B)" }
        print("item \(i): \(desc.joined(separator: ", "))")
    }
    if let png = pb.data(forType: .png), let rep = NSBitmapImageRep(data: png) { print("png dims \(rep.pixelsWide)x\(rep.pixelsHigh)") }
    else if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) { print("tiff dims \(rep.pixelsWide)x\(rep.pixelsHigh)") }
    if let s = pb.string(forType: .string) { print("string length \(s.count)") }
}
func clipPNG(_ out: String) {
    let pb = NSPasteboard.general
    if let png = pb.data(forType: .png) { try! png.write(to: URL(fileURLWithPath: out)); print("wrote png \(png.count)B"); return }
    if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try! png.write(to: URL(fileURLWithPath: out)); print("wrote png from tiff \(png.count)B"); return
    }
    die("no image on pasteboard")
}
func clipText(_ out: String) {
    guard let s = NSPasteboard.general.string(forType: .string) else { die("no text") }
    try! s.write(toFile: out, atomically: true, encoding: .utf8)
    print("wrote text \(s.count) chars")
}

// MARK: Pixels (raw decoded bytes, no colour conversion)
struct Raw { let w: Int; let h: Int; let bpr: Int; let bpp: Int; let bytes: [UInt8]; let alphaFirst: Bool; let hasAlpha: Bool; let space: String }
func loadRaw(_ path: String) -> Raw {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(s, 0, nil),
          let data = img.dataProvider?.data else { die("cannot read \(path)") }
    let info = img.alphaInfo
    let first = [.first, .premultipliedFirst, .noneSkipFirst].contains(info)
    let has = ![.none, .noneSkipFirst, .noneSkipLast].contains(info)
    guard img.bitsPerComponent == 8 else { die("bpc \(img.bitsPerComponent) unsupported") }
    return Raw(w: img.width, h: img.height, bpr: img.bytesPerRow, bpp: img.bitsPerPixel / 8,
               bytes: Array(data as Data), alphaFirst: first, hasAlpha: has, space: (img.colorSpace?.name as String?) ?? "untagged")
}
func rgba(_ r: Raw, _ x: Int, _ y: Int) -> [Int] {
    let o = y * r.bpr + x * r.bpp
    if r.bpp == 3 { return [Int(r.bytes[o]), Int(r.bytes[o + 1]), Int(r.bytes[o + 2]), 255] }
    if r.alphaFirst { return [Int(r.bytes[o + 1]), Int(r.bytes[o + 2]), Int(r.bytes[o + 3]), Int(r.bytes[o])] }
    return [Int(r.bytes[o]), Int(r.bytes[o + 1]), Int(r.bytes[o + 2]), r.hasAlpha ? Int(r.bytes[o + 3]) : 255]
}

func displayScale(_ id: CGDirectDisplayID) -> Int {
    guard let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 else { return 1 }
    return max(1, mode.pixelWidth / mode.width)
}

@main enum Drive {
    @MainActor static func main() {
        var a = Array(CommandLine.arguments.dropFirst())
        guard !a.isEmpty else { die("usage: drive <command> … (see Tools/LiveHarness/README.md)") }
        let cmd = a.removeFirst()
        func d(_ i: Int) -> Double { guard i < a.count, let v = Double(a[i]) else { die("bad arg \(i)") }; return v }
        func point(_ i: Int) -> CGPoint { CGPoint(x: d(i), y: d(i + 1)) }
        switch cmd {
        case "sleep": ms(Int(d(0)))
        case "displays":  // one line per display: id builtin|external x y w h scale (CG global points, top-left origin)
            for id in activeDisplays() {
                let b = CGDisplayBounds(id)
                print("\(id)\t\(CGDisplayIsBuiltin(id) != 0 ? "builtin" : "external")\t\(Int(b.minX))\t\(Int(b.minY))\t\(Int(b.width))\t\(Int(b.height))\t\(displayScale(id))")
            }
        case "frisket":
            print(frisketPID())
        case "key":  // key CODE [cmd,shift,…]: also used for global ⌘⇧ hot keys, still only with Frisket or pattern frontmost
            guard safeTarget() else { die("REFUSED key: frontmost is \(frontInfo())") }
            postKey(CGKeyCode(d(0)), parseFlags(a.count > 1 ? a[1] : nil))
            print("key \(a[0]) \(a.count > 1 ? a[1] : "") -> front \(frontInfo())")
        case "type":
            guard safeTarget() else { die("REFUSED type: frontmost is \(frontInfo())") }
            typeString(a[0]); print("typed \(a[0].count) chars")
        case "move":
            let p = point(0); requireOnDisplay(p); mouse(.mouseMoved, p); ms(60)
        case "click":
            let p = point(0); requireOwnTarget(p)
            let f = parseFlags(a.count > 2 ? a[2] : nil)
            mouse(.mouseMoved, p); ms(60); mouse(.leftMouseDown, p, f); ms(60); mouse(.leftMouseUp, p, f); ms(80)
        case "dclick":
            let p = point(0); requireOwnTarget(p)
            mouse(.mouseMoved, p); ms(60)
            mouse(.leftMouseDown, p, clicks: 1); ms(40); mouse(.leftMouseUp, p, clicks: 1); ms(60)
            mouse(.leftMouseDown, p, clicks: 2); ms(40); mouse(.leftMouseUp, p, clicks: 2); ms(80)
        case "drag":  // drag X0 Y0 X1 Y1 [STEPS] [mods]
            let p0 = point(0), p1 = point(2)
            requireOwnTarget(p0); requireOnDisplay(p1)
            let steps = a.count > 4 ? Int(d(4)) : 24
            let f = parseFlags(a.count > 5 ? a[5] : nil)
            mouse(.mouseMoved, p0); ms(80); mouse(.leftMouseDown, p0, f); ms(80)
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                mouse(.leftMouseDragged, CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t), f); ms(16)
            }
            ms(80); mouse(.leftMouseUp, p1, f); ms(120)
        case "seq":  // each arg is one step, run in this process so button state persists
            for step in a {
                let t = step.split(separator: " ").map(String.init)
                func v(_ i: Int) -> Double { guard i < t.count, let x = Double(t[i]) else { die("bad step \(step)") }; return x }
                let mods = parseFlags(t.count > 3 && ["down", "drag", "up"].contains(t[0]) ? t[3] : (t.count > 2 && ["key", "kdown", "kup"].contains(t[0]) ? t[2] : nil))
                switch t[0] {
                case "down": let p = CGPoint(x: v(1), y: v(2)); requireOwnTarget(p); mouse(.mouseMoved, p); ms(60); mouse(.leftMouseDown, p, mods); ms(60)
                case "drag": let p = CGPoint(x: v(1), y: v(2)); requireOnDisplay(p); mouse(.leftMouseDragged, p, mods); ms(30)
                case "up": let p = CGPoint(x: v(1), y: v(2)); requireOnDisplay(p); mouse(.leftMouseUp, p, mods); ms(80)
                case "move": let p = CGPoint(x: v(1), y: v(2)); requireOnDisplay(p); mouse(.mouseMoved, p); ms(40)
                case "wait": ms(Int(v(1)))
                case "key", "kdown", "kup":
                    guard safeTarget() else { die("REFUSED \(step): frontmost is \(frontInfo())") }
                    if t[0] == "key" { postKey(CGKeyCode(v(1)), mods); continue }
                    let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(v(1)), keyDown: t[0] == "kdown")!
                    e.flags = mods
                    if [55, 56, 58, 59].contains(Int(v(1))) { e.type = .flagsChanged }
                    e.post(tap: .cghidEventTap); ms(40)
                case "shot":  // shot X Y W H FILE: evidence cropped to a test window, never the whole desktop
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    p.arguments = ["-x", "-R\(t[1]),\(t[2]),\(t[3]),\(t[4])", t[5]]
                    try? p.run(); p.waitUntilExit()
                default: die("unknown step \(step)")
                }
            }
        case "pos":
            print(CGEvent(source: nil)?.location ?? .zero)
        case "front":
            let f = frontInfo()
            print("frontmost: \(f.name) pid=\(f.pid)")
            let sys = AXUIElementCreateSystemWide()
            if let el = ax(sys, kAXFocusedUIElementAttribute) {
                var pid: pid_t = 0; AXUIElementGetPid(el as! AXUIElement, &pid)
                print("AX focused element (pid \(pid)): " + describe(el as! AXUIElement))
            }
            if let app = frisketApp(), let fw = ax(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) {
                print("Frisket focused window: " + describe(fw as! AXUIElement))
            }
        case "activate":  // activate frisket|pattern: bring that app forward (only these two)
            let pid = pidArgument(a[0])
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier == frisketApp()?.bundleIdentifier || app.localizedName == patternName
            else { die("REFUSED: activate only Frisket or the pattern") }
            print("activate \(app.localizedName ?? "?") ->", app.activate())
            usleep(400_000)
        case "frontmost":  // prints the frontmost app's name only
            print(frontInfo().name)
        case "axdump":
            let pid = pidArgument(a[0]); let depth = a.count > 1 ? Int(d(1)) : 8
            for w in roots(pid) { dump(w, depth: 0, max: depth) }
        case "axwin":
            for w in windows(pidArgument(a[0])) { print(describe(w)) }
        case "axfind":  // axfind PID LABEL: exit 0 and describe it if an element carries LABEL
            let pid = pidArgument(a[0])
            guard let e = find(pid, a[1], exact: true) ?? find(pid, a[1], exact: false) else { print("not found: \(a[1])"); exit(1) }
            print(describe(e))
        case "menu":  // menu PID TITLE: the items of the main menu's TITLE menu (ticket 94: Edit › Undo's title)
            // Opening the menu makes AppKit validate its items, which sets titles such as "Undo Arrow".
            // Frisket is an accessory app with no visible menu bar, so opening may fail; the items are listed anyway.
            let app = AXUIElementCreateApplication(pidArgument(a[0]))
            guard let bar = ax(app, kAXMenuBarAttribute) else { die("no menu bar") }
            guard let item = children(bar as! AXUIElement).first(where: { axString($0, kAXTitleAttribute) == a[1] }) else { die("no menu \(a[1])") }
            let opened = AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            ms(400)
            for menu in children(item) { for entry in children(menu) { print(describe(entry)) } }
            if opened { for menu in children(item) { AXUIElementPerformAction(menu, kAXCancelAction as CFString) } }
            print("opened=\(opened)")
        case "axframe":  // axframe PID LABEL: x y w h in CG global points
            let pid = pidArgument(a[0])
            guard let e = find(pid, a[1], exact: true) ?? find(pid, a[1], exact: false), let f = frame(e) else { die("not found: \(a[1])") }
            print("\(Int(f.minX)) \(Int(f.minY)) \(Int(f.width)) \(Int(f.height))")
        case "axclick":  // axclick PID LABEL: a real click at the element's centre (AX press doesn't activate the app)
            let pid = pidArgument(a[0])
            guard let e = find(pid, a[1], exact: true) ?? find(pid, a[1], exact: false), let f = frame(e) else { die("not found: \(a[1])") }
            let p = CGPoint(x: f.midX, y: f.midY); requireOwnTarget(p)
            mouse(.mouseMoved, p); ms(60); mouse(.leftMouseDown, p); ms(60); mouse(.leftMouseUp, p); ms(120)
            print("clicked \(a[1]) at \(p)")
        case "axpress":
            let pid = pidArgument(a[0]); let label = a[1]; let action = a.count > 2 ? a[2] : "AXPress"
            guard let e = find(pid, label, exact: true) ?? find(pid, label, exact: false) else { die("not found: \(label)") }
            var name = action
            let names = actions(e)
            if !names.contains(action), let custom = names.first(where: { $0.contains("Name:\(action)") }) { name = custom }
            let r = AXUIElementPerformAction(e, name as CFString)
            print("axpress \(label) [\(action)] -> \(r.rawValue) on " + describe(e))
            if r != .success { exit(1) }
        case "axfocus":
            let pid = pidArgument(a[0])
            guard let e = find(pid, a[1], exact: true) ?? find(pid, a[1], exact: false) else { die("not found") }
            let r = AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            print("focus -> \(r.rawValue) " + describe(e))
        case "axmove":
            let pid = pidArgument(a[0]); let sub = a[1]; let p = point(2); requireOnDisplay(p)
            let parts = sub.split(separator: "#").map(String.init)
            let matching = windows(pid).filter { parts[0] == "*" || (axString($0, kAXTitleAttribute) ?? "").contains(parts[0]) }
            let index = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            guard index < matching.count else { die("no window \(sub)") }
            let w = matching[index]
            var pt = p
            let v = AXValueCreate(.cgPoint, &pt)!
            let r = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v)
            print("move -> \(r.rawValue) now " + describe(w))
        case "cardact":  // cardact Y ACTION: a custom AX action on the Frisket Thumbnail whose top edge is at Y
            let wantY = d(0); let sub = a[1]
            for w in windows(frisketPID()) {
                guard let f = frame(w), abs(f.minY - wantY) < 1 else { continue }
                for n in actions(w) where n.contains(sub) {
                    print("perform \(n) at y=\(f.minY) ->", AXUIElementPerformAction(w, n as CFString).rawValue); exit(0)
                }
            }
            die("no Thumbnail at y=\(wantY) with action \(sub)")
        case "cgwin":  // cgwin [OWNER]: Frisket's and the pattern's on-screen windows (plus OWNER's)
            let fp = Int(frisketApp()?.processIdentifier ?? -1)
            for w in onScreenWindows() where w.pid == fp || w.owner == patternName || (a.first.map { w.owner.contains($0) } ?? false) {
                print("\(w.owner)\tid=\(w.id)\tlayer=\(w.layer)\t\(Int(w.bounds.minX)) \(Int(w.bounds.minY)) \(Int(w.bounds.width)) \(Int(w.bounds.height))\talpha=\(w.alpha)\tname=\(w.name.debugDescription)")
            }
        case "whatat":  // whatat X Y: every on-screen window under a point, front to back
            let p = point(0)
            for w in onScreenWindows() where w.bounds.contains(p) {
                print("layer=\(w.layer) owner=\(w.owner) alpha=\(w.alpha) bounds=\(w.bounds)")
            }
        case "clip-save": clipSave(a[0])
        case "clip-restore": clipRestore(a[0])
        case "clip-info": clipInfo()
        case "clip-count": print(NSPasteboard.general.changeCount)
        case "clip-png": clipPNG(a[0])
        case "clip-text": clipText(a[0])
        case "px":
            let r = loadRaw(a[0]); let x = Int(d(1)), y = Int(d(2))
            print("\(r.w)x\(r.h) bpp=\(r.bpp) space=\(r.space) px(\(x),\(y))=\(rgba(r, x, y))")
        case "info":
            let r = loadRaw(a[0]); print("\(r.w)x\(r.h) bpp=\(r.bpp) alpha=\(r.hasAlpha) space=\(r.space)")
        case "size":
            let r = loadRaw(a[0]); print("\(r.w) \(r.h)")
        default: die("unknown command \(cmd)")
        }
    }
}
