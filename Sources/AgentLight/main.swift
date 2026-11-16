import AppKit

// MARK: - Model

enum St: Int {
    case pinned = 0, done, working, error, needsInput   // pinned: a to-do that stays until you mark it done

    init?(_ s: String) {
        switch s {
        case "pinned": self = .pinned
        case "needs_input": self = .needsInput
        case "error": self = .error
        case "working": self = .working
        case "done": self = .done
        default: return nil
        }
    }
    var color: NSColor {
        switch self {
        case .needsInput, .pinned: return NSColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1)
        case .error: return NSColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
        case .working: return NSColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1)
        case .done: return NSColor(red: 0.20, green: 0.80, blue: 0.40, alpha: 1)
        }
    }
    var word: String {
        switch self {
        case .needsInput: return "waiting"
        case .error: return "error"
        case .working: return "working"
        case .done: return "done"
        case .pinned: return "to do"
        }
    }
}

struct Session {
    let agent: String, state: St, ts: Date, cwd: String, message: String, termApp: String, path: String, title: String, url: String
    var project: String { !title.isEmpty ? title : cwd.isEmpty ? "session" : (cwd as NSString).lastPathComponent }
}

let stateDir = NSString(string: "~/.agentlight/state").expandingTildeInPath
let iconDir = NSString(string: "~/agent-light/icons").expandingTildeInPath

func loadSessions() -> [Session] {
    let fm = FileManager.default
    var out: [Session] = []
    for f in (try? fm.contentsOfDirectory(atPath: stateDir)) ?? [] where f.hasSuffix(".json") {
        let path = stateDir + "/" + f
        guard let data = fm.contents(atPath: path),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agent = d["agent"] as? String, let st = St(d["state"] as? String ?? ""),
              let ts = d["ts"] as? Double else { continue }
        let age = Date().timeIntervalSince1970 - ts
        if (age > 30 * 60 && st != .pinned) || (st == .done && age > 60) { try? fm.removeItem(atPath: path); continue }
        out.append(Session(agent: agent, state: st, ts: Date(timeIntervalSince1970: ts),
                           cwd: d["cwd"] as? String ?? "", message: d["message"] as? String ?? "",
                           termApp: d["term_app"] as? String ?? "", path: path, title: d["title"] as? String ?? "", url: d["url"] as? String ?? ""))
    }
    // needs_input first, then most urgent, then newest
    return out.sorted { $0.state.rawValue != $1.state.rawValue ? $0.state.rawValue > $1.state.rawValue : $0.ts > $1.ts }
}

func ageText(_ s: Session) -> String {
    let t = Int(Date().timeIntervalSince(s.ts))
    let span = t < 60 ? "\(t)s" : t < 3600 ? "\(t / 60)m" : "\(t / 3600)h"
    return s.state == .done ? "\(span) ago" : "\(s.state.word) \(span)"
}

// MARK: - Logos

let appPaths: [String: [String]] = [
    "claude": ["Claude.app"], "codex": ["Codex.app", "ChatGPT.app"],
    "gemini": ["Gemini.app"], "muse": ["Muse.app"],
]
let monoColors: [String: NSColor] = [
    "claude": NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1), "codex": NSColor(white: 0.25, alpha: 1),
    "gemini": NSColor(red: 0.30, green: 0.45, blue: 0.95, alpha: 1), "muse": NSColor(red: 0.70, green: 0.30, blue: 0.80, alpha: 1),
]

func logo(for agent: String) -> NSImage {
    if let img = NSImage(contentsOfFile: "\(iconDir)/\(agent).png") { return img }
    for dir in ["/Applications", NSString(string: "~/Applications").expandingTildeInPath] {
        for name in appPaths[agent] ?? [] where FileManager.default.fileExists(atPath: "\(dir)/\(name)") {
            return NSWorkspace.shared.icon(forFile: "\(dir)/\(name)")
        }
    }
    let size = NSSize(width: 40, height: 40)
    return NSImage(size: size, flipped: false) { r in
        (monoColors[agent] ?? NSColor.gray).setFill()
        NSBezierPath(ovalIn: r).fill()
        let s = NSAttributedString(string: String(agent.prefix(1)).uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: NSColor.white])
        let sz = s.size()
        s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2))
        return true
    }
}

let gap: CGFloat = 6, perEar = 3

final class LogoView: NSView {
    var onClick: ((LogoView) -> Void)?
    var onMenu: ((NSEvent, NSView) -> Void)?
    let agent: String

    init(agent: String, state: St, count: Int, size cell: CGFloat) {
        self.agent = agent
        super.init(frame: NSRect(x: 0, y: 0, width: cell, height: cell))
        wantsLayer = true

        let iv = NSImageView(frame: bounds.insetBy(dx: cell * 0.15, dy: cell * 0.15))
        iv.image = logo(for: agent)
        iv.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iv)

        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = state.color.cgColor
        ring.lineWidth = 2
        ring.shadowColor = state.color.cgColor
        ring.shadowOpacity = 0.9
        ring.shadowRadius = 3
        ring.shadowOffset = .zero
        layer?.addSublayer(ring)

        let pulse: (Float, Float, Double)? = {
            switch state {
            case .needsInput: return (0.25, 1, 0.4)
            case .error: return (0.6, 1, 0.9)
            case .working: return (0.5, 1, 1.6)
            case .done, .pinned: return nil
            }
        }()
        if let (from, to, dur) = pulse {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = from; a.toValue = to; a.duration = dur
            a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ring.add(a, forKey: "pulse")
        }

        if count > 1 {
            let b = NSTextField(labelWithString: "\(count)")
            b.font = .systemFont(ofSize: 9, weight: .bold)
            b.textColor = .white
            b.alignment = .center
            b.wantsLayer = true
            b.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
            b.layer?.cornerRadius = 6
            b.frame = NSRect(x: cell - 12, y: 0, width: 12, height: 12)
            addSubview(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(self) }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event, self) }
}

// MARK: - Popover rows

final class ActionButton: NSButton {
    var handler: (() -> Void)?
    convenience init(_ title: String, _ handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(fire)
        bezelStyle = .rounded
        controlSize = .small
    }
    @objc func fire() { handler?() }
}

func label(_ s: String, _ font: NSFont, _ color: NSColor = .labelColor) -> NSTextField {
    let t = NSTextField(labelWithString: s)
    t.font = font; t.textColor = color
    return t
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var strip: NSView!
    var popover: NSPopover?
    var popAgent: String?
    var sessions: [Session] = []
    var stripSig = "", popSig = ""
    var watch: DispatchSourceFileSystemObject?

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        strip = NSView()
        strip.wantsLayer = true
        panel.contentView = strip

        let fd = Darwin.open(stateDir, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in self?.refresh() }
            src.resume()
            watch = src
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sampleApps() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.stripSig = ""; self?.refresh() }
        refresh()
    }

    // MARK: App activity (Muse and Gemini are desktop apps with no hooks, so watch their CPU)
    // Measured: idle ~0-2%; Muse generating 6-18%; Gemini generating 17-700%.
    struct Watch { let agent: String, match: String, threshold: Double, bundle: String }
    let watches = [Watch(agent: "muse", match: "/Muse.app/", threshold: 5, bundle: "com.meta.endo"),
                   Watch(agent: "gemini", match: "/Gemini.app/", threshold: 10, bundle: "com.google.GeminiMacOS"),
                   // ChatGPT.app is OpenAI's Codex desktop app (Electron). Threshold NOT yet measured.
                   Watch(agent: "codex", match: "/ChatGPT.app/", threshold: 10, bundle: "com.openai.codex")]
    var hot: [String: Int] = [:], cold: [String: Int] = [:], busy: Set<String> = [], lastWrite: [String: Date] = [:]
    var sampling = false

    func sampleApps() {
        guard !sampling else { return }
        sampling = true
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-axo", "pcpu=,command="]
            let pipe = Pipe()
            p.standardOutput = pipe
            var out = ""
            if (try? p.run()) != nil {
                out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
            }
            var cpu: [String: Double] = [:]
            for line in out.split(separator: "\n") {
                let t = line.drop { $0 == " " }
                guard let sp = t.firstIndex(of: " "), let v = Double(t[..<sp]) else { continue }
                let cmd = t[sp...]
                for w in self.watches where cmd.contains(w.match) { cpu[w.agent, default: 0] += v }
            }
            DispatchQueue.main.async { self.sampling = false; self.applyActivity(cpu) }
        }
    }

    func applyActivity(_ cpu: [String: Double]) {
        for w in watches {
            let isHot = (cpu[w.agent] ?? 0) >= w.threshold
            hot[w.agent] = isHot ? (hot[w.agent] ?? 0) + 1 : 0
            cold[w.agent] = isHot ? 0 : (cold[w.agent] ?? 0) + 1
            if !busy.contains(w.agent), (hot[w.agent] ?? 0) >= 3 {
                busy.insert(w.agent)
                writeApp(w, "working", "Working…")
            } else if busy.contains(w.agent) {
                if (cold[w.agent] ?? 0) >= 6 {
                    busy.remove(w.agent)
                    writeApp(w, "done", "Finished responding")
                } else if Date().timeIntervalSince(lastWrite[w.agent] ?? .distantPast) > 20 {
                    writeApp(w, "working", "Working…")   // keep the session fresh
                }
            }
        }
    }

    func writeApp(_ w: Watch, _ state: String, _ message: String) {
        lastWrite[w.agent] = Date()
        let d: [String: Any] = ["agent": w.agent, "state": state, "ts": Date().timeIntervalSince1970, "cwd": "",
                                "message": message, "term_app": w.bundle, "session": "app"]
        guard let data = try? JSONSerialization.data(withJSONObject: d) else { return }
        let path = "\(stateDir)/\(w.agent)__app.json"
        try? data.write(to: URL(fileURLWithPath: path + ".tmp"))
        rename(path + ".tmp", path)
    }

    /// Agents ordered most urgent first, each with its best session and session count.
    func agents() -> [(String, Session, Int)] {
        var seen: [String: (Session, Int)] = [:]
        for s in sessions { seen[s.agent] = seen[s.agent].map { ($0.0, $0.1 + 1) } ?? (s, 1) }  // sessions already sorted
        return seen.map { ($0.key, $0.value.0, $0.value.1) }.sorted {
            $0.1.state.rawValue != $1.1.state.rawValue ? $0.1.state.rawValue > $1.1.state.rawValue : $0.1.ts > $1.1.ts
        }
    }

    func refresh() {
        sessions = loadSessions()
        let list = agents()
        let sig = list.map { "\($0.0):\($0.1.state):\($0.2)" }.joined(separator: ",")
        if sig != stripSig { stripSig = sig; rebuildStrip(list) }

        guard let pop = popover, pop.isShown, let a = popAgent else { return }
        let mine = sessions.filter { $0.agent == a }
        if mine.isEmpty { pop.close(); return }
        let psig = mine.map { "\($0.path)\($0.state)\($0.message)\(ageText($0))" }.joined()
        if psig != popSig { popSig = psig; pop.contentViewController = popoverVC(mine); pop.contentSize = pop.contentViewController!.view.frame.size }
    }

    func rebuildStrip(_ list: [(String, Session, Int)]) {
        strip.subviews.forEach { $0.removeFromSuperview() }
        strip.layer?.sublayers = nil
        guard !list.isEmpty else { panel.orderOut(nil); return }

        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let h = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let size = h - 8
        let step = size + gap

        // Each logo: (agent info, x offset from the panel's left edge)
        var frame: NSRect
        var xs: [CGFloat]
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            // Dynamic-Island style: black "ears" on both sides of the notch; left ear fills first.
            let leftN = min(list.count, perEar), rightN = min(list.count - leftN, perEar)
            let leftW = CGFloat(leftN) * step + gap, rightW = rightN > 0 ? CGFloat(rightN) * step + gap : 0
            let notch = r.minX - l.maxX
            frame = NSRect(x: l.maxX - leftW, y: screen.frame.maxY - h, width: leftW + notch + rightW, height: h)
            xs = (0..<min(list.count, perEar * 2)).map { i in
                i < leftN ? leftW - gap - CGFloat(i + 1) * step + gap      // most urgent nearest the notch
                          : leftW + notch + gap + CGFloat(i - leftN) * step
            }
            let rad: CGFloat = 8, w = frame.width
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: rad))
            p.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w - rad, y: 0), radius: rad)
            p.addLine(to: CGPoint(x: rad, y: 0))
            p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: 0, y: rad), radius: rad)
            p.closeSubpath()
            let shape = CAShapeLayer()
            shape.path = p
            shape.fillColor = NSColor.black.cgColor
            strip.layer?.addSublayer(shape)
        } else {
            // No notch: loose logos at the top-right of the menu bar, no black shape.
            let n = min(list.count, perEar * 2)
            let w = CGFloat(n) * step + gap
            frame = NSRect(x: screen.frame.maxX - w - 220, y: screen.frame.maxY - h, width: w, height: h)
            xs = (0..<n).map { w - CGFloat($0 + 1) * step }
        }
        panel.setFrame(frame, display: false)
        strip.frame = NSRect(origin: .zero, size: frame.size)

        for (i, x) in xs.enumerated() {
            let (agent, best, count) = list[i]
            let v = LogoView(agent: agent, state: best.state, count: count, size: size)
            v.frame.origin = NSPoint(x: x, y: (h - size) / 2)
            v.onClick = { [weak self] v in self?.togglePopover(v) }
            v.onMenu = { [weak self] e, v in self?.showMenu(e, v) }
            strip.addSubview(v)
        }
        panel.orderFrontRegardless()
    }

    func showMenu(_ e: NSEvent, _ v: NSView) {
        let m = NSMenu()
        m.addItem(withTitle: "Clear all done", action: #selector(clearDone), keyEquivalent: "").target = self
        m.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(m, with: e, for: v)
    }
    @objc func clearDone() {
        sessions.filter { $0.state == .done }.forEach { try? FileManager.default.removeItem(atPath: $0.path) }
        refresh()
    }
    @objc func quit() { NSApp.terminate(nil) }

    func togglePopover(_ v: LogoView) {
        if let p = popover, p.isShown { p.close(); if popAgent == v.agent { return } }
        let mine = sessions.filter { $0.agent == v.agent }
        guard !mine.isEmpty else { return }
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = popoverVC(mine)
        p.contentSize = p.contentViewController!.view.frame.size
        popover = p; popAgent = v.agent
        popSig = mine.map { "\($0.path)\($0.state)\($0.message)\(ageText($0))" }.joined()
        p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
    }

    func popoverVC(_ list: [Session]) -> NSViewController {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        for s in list { stack.addArrangedSubview(row(s)) }
        stack.widthAnchor.constraint(equalToConstant: 340).isActive = true
        stack.layoutSubtreeIfNeeded()
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        let vc = NSViewController()
        vc.view = stack
        return vc
    }

    func row(_ s: Session) -> NSView {
        let pill = label(" \(s.state.word) ", .systemFont(ofSize: 10, weight: .semibold), s.state.color)
        pill.wantsLayer = true
        pill.layer?.backgroundColor = s.state.color.withAlphaComponent(0.18).cgColor
        pill.layer?.cornerRadius = 4
        let top = NSStackView(views: [label(s.project, .systemFont(ofSize: 13, weight: .semibold)), pill,
                                      label(ageText(s), .systemFont(ofSize: 11), .secondaryLabelColor)])
        top.spacing = 6

        let col = NSStackView(views: [top])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 4
        if !s.message.isEmpty {
            let m = NSTextField(wrappingLabelWithString: s.message)
            m.font = .systemFont(ofSize: 12)
            m.textColor = .secondaryLabelColor
            m.maximumNumberOfLines = 2
            m.lineBreakMode = .byTruncatingTail
            m.preferredMaxLayoutWidth = 314
            col.addArrangedSubview(m)
        }
        let open = ActionButton("Open") { [weak self] in self?.open(s) }
        let dismiss = ActionButton(s.state == .pinned ? "Done" : "Dismiss") { [weak self] in
            try? FileManager.default.removeItem(atPath: s.path)
            self?.refresh()
        }
        open.isEnabled = !s.termApp.isEmpty || !s.url.isEmpty
        col.addArrangedSubview(NSStackView(views: [open, dismiss]))
        return col
    }

    func open(_ s: Session) {
        popover?.close()
        let line = "\(Date()) open title=\(s.project) url=\(s.url) app=\(s.termApp)\n"
        if let h = FileHandle(forWritingAtPath: stateDir + "/../open.log") { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { try? line.write(toFile: stateDir + "/../open.log", atomically: true, encoding: .utf8) }
        // A pin with a chat link opens that exact chat in a new Chrome window.
        if s.url.hasPrefix("https://") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            switch s.agent {
            case "claude":   // Claude desktop deep link: same path as the web URL
                p.arguments = [s.url.replacingOccurrences(of: "https://", with: "claude://")]
            case "gemini":   // Gemini.app takes the https link and shows that chat
                p.arguments = ["-b", "com.google.GeminiMacOS", s.url]
            default:         // ChatGPT.app's built-in browser isn't signed in, so use Chrome
                p.arguments = ["-na", "Google Chrome", "--args", "--new-window", s.url]
            }
            try? p.run()
            return
        }
        // Not running: launching it opens a window by itself.
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: s.termApp).first else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: s.termApp) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        // Running but windowless/hidden/other Space: plain "activate" does nothing, so also ask for a new
        // window with Cmd+N. Posting key events needs Accessibility; the first click shows the system prompt.
        app.unhide()
        app.activate(options: [.activateAllWindows])
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let src = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0x2D, keyDown: down)  // 0x2D = N
                e?.flags = .maskCommand
                e?.postToPid(app.processIdentifier)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
