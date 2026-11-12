// LogoToggle — menu bar control for the MacBook Pro illuminated Apple logo.
//
// Talks to corebrightnessd via CoreBrightness's private BrightnessSystemClient
// (no password needed). Keys: LEBacklightMode (0 = off, 2 = on) and
// LEPWMFactorFadeDuration (fade seconds, 0 = automatic). If the private API
// is unavailable, on/off falls back to Apple's documented sudo defaults
// command with an admin prompt; strobe needs the private API.
//
// Optional clap control listens on the microphone for a double clap. Audio is
// analysed in memory for loudness only; nothing is recorded or sent anywhere.
import AppKit
import AVFoundation

// MARK: - Logo light access

final class LogoLight {
    private let client: NSObject?
    private let setSel = NSSelectorFromString("setProperty:forKey:")
    private let getSel = NSSelectorFromString("copyPropertyForKey:")
    private typealias SetFn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Bool

    init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        if let cls = NSClassFromString("BrightnessSystemClient") as? NSObject.Type {
            client = cls.init()
        } else {
            client = nil
        }
    }

    var available: Bool { client != nil }

    /// nil when the state can't be read.
    var isOn: Bool? {
        guard let c = client,
              let v = c.perform(getSel, with: "LEBacklightMode")?.takeRetainedValue() as? NSNumber
        else { return nil }
        return v.intValue != 0
    }

    @discardableResult
    func set(_ value: NSNumber, _ key: String) -> Bool {
        guard let c = client, c.responds(to: setSel) else { return false }
        let fn = unsafeBitCast(c.method(for: setSel), to: SetFn.self)
        return fn(c, setSel, value, key as NSString)
    }

    @discardableResult
    func setOn(_ on: Bool) -> Bool { set(NSNumber(value: on ? 2 : 0), "LEBacklightMode") }
    func setFade(_ seconds: Double) { set(NSNumber(value: seconds), "LEPWMFactorFadeDuration") }

    // Smooth fades: the logo follows DisplayLogicalState (1 = Blank, 2 = Unblank),
    // animating over LEPWMFactorFadeDuration. The keyboard backlight follows it too,
    // so after each Blank the keyboards alone are told Unblank to keep them lit.
    // (Research: github.com/Ark0N/LogoLight docs/corebrightnessd.md)
    private typealias KbSetFn = @convention(c) (AnyObject, Selector, AnyObject, NSString, UInt64) -> Bool
    private let kbSel = NSSelectorFromString("setProperty:withKey:keyboardID:")
    private lazy var keyboardIDs: [UInt64] = {
        guard let t = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return [] }
        let ids = t.init().perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?
            .takeRetainedValue() as? [NSNumber]
        return ids?.map(\.uint64Value) ?? []
    }()

    private func setKeyboardsLit() {
        guard let c = client, c.responds(to: kbSel) else { return }
        let fn = unsafeBitCast(c.method(for: kbSel), to: KbSetFn.self)
        for id in keyboardIDs { _ = fn(c, kbSel, NSNumber(value: 2), "DisplayLogicalState", id) }
    }

    /// Fades the logo to dark (false) or fully lit (true) over `seconds`.
    func fade(lit: Bool, over seconds: Double) {
        setFade(seconds)
        set(NSNumber(value: lit ? 2 : 1), "DisplayLogicalState")
        if !lit { setKeyboardsLit() }
    }

    /// Ends a smooth effect: back to fully lit, then automatic fade timing.
    func restoreLit() {
        fade(lit: true, over: 0.3)
        setKeyboardsLit()
        setFade(0)   // safe straight away: a running fade keeps its own duration
    }
}

// MARK: - Clap detection

/// Finds double claps in a stream of microphone samples. Pure logic, no audio APIs.
///
/// Samples are reduced to one peak level per 10 ms window. A clap is a sudden jump
/// well above the background that is over within a few windows; speech and music
/// are quieter and stay loud for far longer, so they don't count. Two claps
/// 0.12-0.5 s apart make a double clap, reported as soon as the second is confirmed.
/// Tuned against real recordings from the built-in microphone, where claps peak at
/// 0.2-3.0 for 10-20 ms and speech at under 0.1 for 100 ms or more.
/// All times below are in windows (1 window = 10 ms).
final class ClapDetector {
    static let minPeak: Float = 0.15    // quietest clap accepted (1.0 = full scale); lower = more sensitive
    static let floorRatio: Float = 4    // and it must be this many times the background level
    static let confirm = 8              // how long a sound is watched to decide if it's a clap
    static let maxLoud = 3              // a clap stays above half its peak for at most this long
    static let gap = 12...50            // spacing between the two claps
    static let cooldown = 35            // after a double clap, ignore claps for this long

    private let window: Int             // samples per window
    private var filled = 0
    private var level: Float = 0        // peak of the window being filled
    private var now = 0
    private var floor: Float = 0.01     // background level
    private var wasLoud = false
    private var onset: Int?             // start of the sound being watched
    private var onsetLevels: [Float] = []
    private var first: Int?             // first clap of a possible pair
    private var ignoreUntil = 0

    init(sampleRate: Double) { window = max(1, Int(sampleRate / 100)) }

    /// Feeds samples in; returns true when a double clap has just completed.
    func process(_ samples: UnsafeBufferPointer<Float>) -> Bool {
        var fired = false
        for s in samples {
            level = max(level, abs(s))
            filled += 1
            if filled == window {
                if step(level) { fired = true }
                filled = 0
                level = 0
            }
        }
        return fired
    }

    private func step(_ level: Float) -> Bool {
        now += 1
        let loud = level >= max(Self.minPeak, floor * Self.floorRatio)
        defer { wasLoud = loud }

        guard let start = onset else {
            floor = max(0.001, floor + (level - floor) * (level > floor ? 0.02 : 0.2))
            if loud && !wasLoud {
                onset = now
                onsetLevels = [level]
            }
            return false
        }
        onsetLevels.append(level)
        guard onsetLevels.count >= Self.confirm else { return false }
        onset = nil
        let peak = onsetLevels.max() ?? 0
        let isClap = onsetLevels.filter { $0 > peak * 0.5 }.count <= Self.maxLoud
        if !isClap {
            first = nil                         // a loud noise that isn't a clap: start over
        } else if start < ignoreUntil {
            // an extra clap straight after a double clap
        } else if let f = first, Self.gap.contains(start - f) {
            first = nil
            ignoreUntil = start + Self.cooldown
            return true
        } else {
            first = start
        }
        return false
    }
}

/// Runs the microphone through a ClapDetector while started.
final class ClapListener {
    private let engine = AVAudioEngine()
    private var running = false
    var onDoubleClap: (() -> Void)?

    init() {
        // The input device or its format changed (e.g. headphones plugged in): reattach.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.running else { return }
            self.stop()
            self.start()
        }
    }

    @discardableResult
    func start() -> Bool {
        if running { return true }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }   // no microphone
        let detector = ClapDetector(sampleRate: format.sampleRate)
        do {
            // `error: ()` is how Swift imports this macOS 27 method's NSError parameter.
            try input.__installTap(onBus: 0, bufferSize: 4096, format: format, error: ()) { [weak self] buffer, _ in
                guard let data = buffer.floatChannelData else { return }
                let samples = UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
                if detector.process(samples) {
                    DispatchQueue.main.async { self?.onDoubleClap?() }
                }
            }
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        running = true
        return true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let light = LogoLight()

    private var effectTimer: Timer?
    private var effect: Effect?
    private var phaseOn = true
    private var wasOnBeforeEffect = true

    private let claps = ClapListener()
    private var clapEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "clapToggle") }
        set { UserDefaults.standard.set(newValue, forKey: "clapToggle") }
    }

    /// An effect is a dark/lit loop. Strobe snaps by switching the logo off/on;
    /// Breathe glides using hardware fades of the display logical state.
    struct Effect: Equatable {
        let kind: String            // "Strobe" / "Breathe"
        let speed: String           // menu label
        let interval: TimeInterval  // time per dark/lit half-cycle
        var smooth: Bool { kind == "Breathe" }
        var icon: String { smooth ? "wind" : "bolt.fill" }
    }

    static let effects: [String: [Effect]] = [
        "Breathe": [
            Effect(kind: "Breathe", speed: "Slow",   interval: 3.0),
            Effect(kind: "Breathe", speed: "Medium", interval: 2.0),
            Effect(kind: "Breathe", speed: "Fast",   interval: 1.0),
        ],
        "Strobe": [
            Effect(kind: "Strobe", speed: "Slow",   interval: 0.5),
            Effect(kind: "Strobe", speed: "Medium", interval: 0.25),
            Effect(kind: "Strobe", speed: "Fast",   interval: 0.12),
        ],
    ]

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        claps.onDoubleClap = { [weak self] in self?.clapped() }
        if clapEnabled {
            // Permission may have been revoked since last time; don't prompt at launch.
            clapEnabled = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && claps.start()
        }
        rebuild()
        // Stop effects and the microphone when the display sleeps (the logo is dark then anyway).
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(stopEffectNotification),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screensDidWake),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    func applicationWillTerminate(_ note: Notification) { stopEffect() }

    private func rebuild() {
        let on = light.isOn ?? true
        let img = NSImage(systemSymbolName: effect?.icon ?? "apple.logo",
                          accessibilityDescription: "Logo light")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.appearsDisabled = effect == nil && !on

        let menu = NSMenu()
        let statusText: String
        if let e = effect { statusText = "\(e.kind) (\(e.speed.lowercased()))" }
        else if light.isOn == nil { statusText = "Logo light state unknown" }
        else { statusText = on ? "Logo light is on" : "Logo light is off" }
        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if let e = effect {
            menu.addItem(withTitle: "Stop \(e.kind.lowercased())", action: #selector(stopEffectAction), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: on ? "Turn logo off" : "Turn logo on",
                         action: #selector(toggle), keyEquivalent: "").target = self
        }

        for kind in ["Breathe", "Strobe"] {
            let parent = NSMenuItem(title: kind, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for e in Self.effects[kind]! {
                let mi = NSMenuItem(title: e.speed, action: #selector(startEffect(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = "\(e.kind)|\(e.speed)"
                mi.state = effect == e ? .on : .off
                mi.isEnabled = light.available
                sub.addItem(mi)
            }
            parent.submenu = sub
            menu.addItem(parent)
        }

        menu.addItem(.separator())
        let clap = NSMenuItem(title: "Clap twice to toggle", action: #selector(toggleClapControl), keyEquivalent: "")
        clap.target = self
        clap.state = clapEnabled ? .on : .off
        clap.isEnabled = light.available
        menu.addItem(clap)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    // MARK: On / off

    @objc private func toggle() {
        let wantOn = !(light.isOn ?? true)
        if !light.setOn(wantOn) { adminFallback(wantOn) }
        rebuild()
    }

    /// Apple's documented method; prompts for an admin password.
    private func adminFallback(_ wantOn: Bool) {
        let cmd = wantOn
            ? "/usr/bin/defaults delete com.apple.CoreBrightness LEBacklightMode 2>/dev/null; true"
            : "/usr/bin/defaults write com.apple.CoreBrightness LEBacklightMode -int 0"
        let src = "do shell script \"\(cmd)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err = err, (err[NSAppleScript.errorNumber] as? Int) != -128 {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the logo light"
            alert.informativeText = (err[NSAppleScript.errorMessage] as? String) ?? "\(err)"
            alert.runModal()
        }
    }

    // MARK: Clap control

    @objc private func toggleClapControl() {
        if clapEnabled {
            clapEnabled = false
            claps.stop()
            rebuild()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            enableClapControl()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { if granted { self.enableClapControl() } }
            }
        default:
            let alert = NSAlert()
            alert.messageText = "LogoToggle needs the microphone to hear claps"
            alert.informativeText = "Allow LogoToggle under System Settings → Privacy & Security → Microphone, then try again."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func enableClapControl() {
        if claps.start() {
            clapEnabled = true
        } else {
            let alert = NSAlert()
            alert.messageText = "Couldn't start listening for claps"
            alert.informativeText = "No microphone is available."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        rebuild()
    }

    /// A double clap switches the logo, or ends a running effect and leaves it dark.
    /// Never falls back to the admin prompt: a sound shouldn't raise a password dialog.
    private func clapped() {
        guard clapEnabled, light.available else { return }
        if effect != nil {
            stopEffect()
            light.setOn(false)
        } else {
            light.setOn(!(light.isOn ?? true))
        }
        rebuild()
    }

    @objc private func screensDidWake() {
        if clapEnabled { claps.start() }
    }

    // MARK: Effects

    @objc private func startEffect(_ sender: NSMenuItem) {
        guard let tag = (sender.representedObject as? String)?.split(separator: "|"), tag.count == 2,
              let e = Self.effects[String(tag[0])]?.first(where: { $0.speed == tag[1] }) else { return }
        if effect == nil { wasOnBeforeEffect = light.isOn ?? true }
        effectTimer?.invalidate()
        if effect?.smooth == true { light.restoreLit() }   // switching away from breathe
        effect = e
        if e.smooth {
            light.setOn(true)        // fades only show while the logo setting is on
        } else {
            light.setFade(0.02)      // near-instant on/off for strobe
        }
        phaseOn = false
        let t = Timer(timeInterval: e.interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if e.smooth {
                self.light.fade(lit: self.phaseOn, over: e.interval)
            } else {
                self.light.setOn(self.phaseOn)
            }
            self.phaseOn.toggle()
        }
        RunLoop.main.add(t, forMode: .common)   // keep ticking while the menu is open
        effectTimer = t
        t.fire()
        rebuild()
    }

    @objc private func stopEffectAction() { stopEffect(); rebuild() }
    @objc private func stopEffectNotification() {
        stopEffect(displaySleeping: true)
        claps.stop()
        rebuild()
    }

    /// When the display is going to sleep, the daemon owns the logical state, so we
    /// don't force the logo lit — just stop and hand fade timing back.
    private func stopEffect(displaySleeping: Bool = false) {
        guard let e = effect else { return }
        effectTimer?.invalidate()
        effectTimer = nil
        effect = nil
        if e.smooth && !displaySleeping { light.restoreLit() }
        light.setFade(0)                 // back to automatic fades
        light.setOn(wasOnBeforeEffect)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
app.run()
