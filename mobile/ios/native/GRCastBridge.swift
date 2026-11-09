// gen1recomp iOS native bridge: TV / CAST host (AirPlay, HDMI adapters).
//
// The iOS end of the second-display file protocol that
// mobile/second-display/SecondDisplayHost.java speaks on Android.  The Lua end
// (src/render/SecondScreen.lua, src/ui/CastDisplay.lua, src/render/CastTop.lua)
// is shared, so this file follows the Java host's protocol exactly:
//
//   <saveDir>/second_display/host.txt   written HERE, once a second:
//       "1 <displays> <width> <height> <kind> <mode>"
//       kind = none | external (an iPhone has no built-in second panel)
//       mode = mirror | bottom | top, or auto when nothing is attached.
//       displays is 2 only while our window is up on the TV and taking frames.
//   <saveDir>/second_display/mode.txt   written by LUA, read HERE every
//       heartbeat: mirror | bottom | top; missing or anything else = auto,
//       which for an external display is mirror.
//   <saveDir>/second_display/frame.bin  written by LUA: "G2SD", then version,
//       width, height, sequence as little-endian u16 (twelve bytes), then
//       width*height*4 bytes of RGBA.  Read here only when the sequence moves.
//   touch.txt is never written: a TV is not a touch panel, so BOTTOM routes
//   no taps (the phone keeps the top screen and its own controls).
//
// MIRROR creates nothing.  The TV's scene stays empty, and iOS mirrors the
// phone onto it (GRSceneGuard.m keeps SDL from claiming that scene).
// BOTTOM / TOP put one UIWindow on the external display's UIWindowScene that
// shows frame.bin, letterboxed on black.
//
// Started from Lua through love.system.castHostStart() (wrap_System.cpp,
// patched by mobile/ios/patch_love_src.py), which passes LOVE's real save
// directory.  An IPA without this file has no castHostStart, so Lua never
// offers the option there.  Everything below runs on the main thread.

import UIKit
import QuartzCore

@objc(GRCastBridge)
public final class GRCastBridge: NSObject {

    static let protocolVersion = 1
    static let dirName = "second_display"
    static let hostFile = "host.txt"
    static let frameFile = "frame.bin"
    static let modeFile = "mode.txt"
    static let kindNone = "none"
    static let kindExternal = "external"
    static let modeMirror = "mirror"
    static let modeBottom = "bottom"
    static let modeTop = "top"
    static let modeAuto = "auto"
    // The size reported to Lua is capped: the launcher renders its lower
    // panel at the host's size and writes it through a file every frame, and
    // a 4K TV's full size would be 33 MB a frame.  The window scales it up.
    static let maxLong: CGFloat = 640
    static let maxShort: CGFloat = 360

    private static var dir: URL?
    private static var started = false
    private static var heartbeat: Timer?
    private static var observers: [NSObjectProtocol] = []
    private static var panel: GRCastPanel?

    // MARK: - Entry point called from liblove (C strings on purpose)

    @objc(startWithCommand:saveDir:)
    public static func start(command: UnsafePointer<CChar>?,
                             saveDir: UnsafePointer<CChar>?) -> Bool {
        let save = saveDir.map { String(cString: $0) } ?? ""
        let run = { () -> Bool in
            guard !save.isEmpty else { return false }
            let d = URL(fileURLWithPath: save, isDirectory: true)
                .appendingPathComponent(dirName, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: d,
                                                        withIntermediateDirectories: true)
            } catch {
                NSLog("GRCastBridge: cannot create \(d.path): \(error)")
                return false
            }
            dir = d
            if !started {
                started = true
                watch()
            }
            // Synchronously, so the first host.txt exists before Lua probes.
            reconcile()
            return true
        }
        if Thread.isMainThread { return run() }
        var ok = false
        DispatchQueue.main.sync { ok = run() }
        return ok
    }

    // MARK: - Watching for displays

    private static func watch() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIScene.willConnectNotification,
                                            object: nil, queue: .main) { _ in
            // the scene is not in connectedScenes until willConnect returns
            DispatchQueue.main.async { reconcile() }
        })
        observers.append(center.addObserver(forName: UIScene.didDisconnectNotification,
                                            object: nil, queue: .main) { note in
            if let scene = note.object as? UIWindowScene, let p = panel, p.scene === scene {
                NSLog("GRCastBridge: external display disconnected")
                closePanel()
            }
            DispatchQueue.main.async { reconcile() }
        })
        observers.append(center.addObserver(forName: UIScene.didActivateNotification,
                                            object: nil, queue: .main) { _ in
            reconcile()
        })
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in reconcile() }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    static func isExternalDisplay(_ scene: UIScene) -> Bool {
        let role = scene.session.role
        if #available(iOS 16.0, *) {
            if role == .windowExternalDisplayNonInteractive { return true }
        }
        return role == .windowExternalDisplay
    }

    private static func externalScene() -> UIWindowScene? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene, isExternalDisplay(ws) else { continue }
            if ws.activationState == .unattached { continue }
            return ws
        }
        return nil
    }

    // MARK: - The heartbeat: match the TV to the player's mode, report it

    private static func reconcile() {
        guard let d = dir else { return }
        let requested = readRequestedMode(d)
        guard let scene = externalScene() else {
            closePanel()
            writeHost(d, displays: 1, width: 0, height: 0,
                      kind: kindNone, mode: requested ?? modeAuto)
            return
        }
        // effectiveMode: never-set on an external display is MIRROR
        let mode = requested ?? modeMirror
        if mode == modeMirror {
            if panel != nil {
                NSLog("GRCastBridge: mirror mode; window removed from the TV")
            }
            closePanel()
            writeHost(d, displays: 1, width: 0, height: 0,
                      kind: kindExternal, mode: modeMirror)
            return
        }
        if let p = panel, p.scene !== scene { closePanel() }
        if panel == nil {
            panel = GRCastPanel(scene: scene,
                                frameURL: d.appendingPathComponent(frameFile))
            NSLog("GRCastBridge: window on external display, mode \(mode)")
        }
        panel?.apply(mode: mode)
        let size = reportedSize(scene)
        writeHost(d, displays: 2, width: size.0, height: size.1,
                  kind: kindExternal, mode: mode)
    }

    private static func closePanel() {
        panel?.close()
        panel = nil
    }

    private static func reportedSize(_ scene: UIWindowScene) -> (Int, Int) {
        let bounds = scene.coordinateSpace.bounds.size
        let scale = max(scene.screen.scale, 1)
        var w = bounds.width * scale
        var h = bounds.height * scale
        if w <= 0 || h <= 0 { return (maxLong.toInt, maxShort.toInt) }
        let capW = w >= h ? maxLong : maxShort
        let capH = w >= h ? maxShort : maxLong
        let s = min(1, min(capW / w, capH / h))
        w = (w * s).rounded()
        h = (h * s).rounded()
        return (max(1, Int(w)), max(1, Int(h)))
    }

    // MARK: - The files

    static func hostLine(displays: Int, width: Int, height: Int,
                         kind: String, mode: String) -> String {
        return "\(protocolVersion) \(displays) \(width) \(height) \(kind) \(mode)\n"
    }

    private static func writeHost(_ d: URL, displays: Int, width: Int, height: Int,
                                  kind: String, mode: String) {
        let line = hostLine(displays: displays, width: width, height: height,
                            kind: kind, mode: mode)
        guard let data = line.data(using: .utf8) else { return }
        do {
            try data.write(to: d.appendingPathComponent(hostFile), options: .atomic)
        } catch {
            NSLog("GRCastBridge: host.txt write failed: \(error)")
        }
    }

    static func parseMode(_ text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if word == modeMirror || word == modeBottom || word == modeTop { return word }
        return nil
    }

    private static func readRequestedMode(_ d: URL) -> String? {
        guard let data = try? Data(contentsOf: d.appendingPathComponent(modeFile)),
              let text = String(data: data.prefix(32), encoding: .utf8) else { return nil }
        return parseMode(text)
    }
}

private extension CGFloat {
    var toInt: Int { return Int(self) }
}

// One window on the TV's scene, showing frame.bin.
private final class GRCastPanel: NSObject {
    weak var scene: UIWindowScene?
    private let window: UIWindow
    private let picture: UIView
    private let frameURL: URL
    private var link: CADisplayLink?
    private var lastSeq = -1
    private var reading = false
    private let reader = DispatchQueue(label: "gen1recomp.cast.frame")

    init(scene: UIWindowScene, frameURL: URL) {
        // Built in locals: nothing on self may be read before super.init.
        let win = UIWindow(windowScene: scene)
        win.frame = scene.coordinateSpace.bounds
        win.backgroundColor = .black
        let root = UIViewController()
        root.view.backgroundColor = .black
        let view = UIView(frame: root.view.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.layer.contentsGravity = .resizeAspect
        view.layer.minificationFilter = .linear
        root.view.addSubview(view)
        win.rootViewController = root
        self.scene = scene
        self.frameURL = frameURL
        self.window = win
        self.picture = view
        super.init()
        // Visible but never key: the phone's SDL window keeps the keyboard,
        // the pickers and every touch.
        window.isHidden = false
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func apply(mode: String) {
        // BOTTOM is the DS's own 256x192, blown up: keep the pixels square.
        // TOP is already a downscaled picture; smooth it.
        picture.layer.magnificationFilter =
            mode == GRCastBridge.modeBottom ? .nearest : .linear
    }

    func close() {
        link?.invalidate()
        link = nil
        window.isHidden = true
        window.rootViewController = nil
    }

    @objc private func tick() {
        if reading { return }
        reading = true
        let url = frameURL
        let last = lastSeq
        reader.async { [weak self] in
            let frame = GRCastPanel.load(url: url, lastSeq: last)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.reading = false
                guard let frame = frame, self.link != nil else { return }
                self.lastSeq = frame.seq
                self.picture.layer.contents = frame.image
            }
        }
    }

    struct Header: Equatable {
        let width: Int
        let height: Int
        let seq: Int
    }

    struct Frame {
        let seq: Int
        let image: CGImage
    }

    static let headerBytes = 12

    // "G2SD", version, width, height, sequence: little-endian u16s.
    static func parseHeader(_ bytes: [UInt8]) -> Header? {
        guard bytes.count >= headerBytes,
              bytes[0] == 0x47, bytes[1] == 0x32, bytes[2] == 0x53, bytes[3] == 0x44
        else { return nil }
        func u16(_ at: Int) -> Int { return Int(bytes[at]) | (Int(bytes[at + 1]) << 8) }
        guard u16(4) == GRCastBridge.protocolVersion else { return nil }
        let w = u16(6), h = u16(8)
        guard w > 0, h > 0, w <= 4096, h <= 4096 else { return nil }
        return Header(width: w, height: h, seq: u16(10))
    }

    // Off the main thread.  nil = nothing new, or a write in progress (Lua
    // truncates and rewrites frame.bin; a short file is retried next tick).
    static func load(url: URL, lastSeq: Int) -> Frame? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let headData = try? handle.read(upToCount: headerBytes),
              let head = parseHeader([UInt8](headData)),
              head.seq != lastSeq else { return nil }
        let want = headerBytes + head.width * head.height * 4
        guard (try? handle.seek(toOffset: 0)) != nil,
              let all = try? handle.readToEnd(),
              all.count == want,
              let again = parseHeader([UInt8](all.prefix(headerBytes))),
              again == head else { return nil }
        let pixels = all.subdata(in: headerBytes..<want)
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let image = CGImage(width: head.width, height: head.height,
                                  bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: head.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: info, provider: provider,
                                  decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        return Frame(seq: head.seq, image: image)
    }
}
