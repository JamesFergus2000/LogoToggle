// LogoToggle — menu bar control for the MacBook Pro illuminated Apple logo.
//
// Talks to corebrightnessd via CoreBrightness's private BrightnessSystemClient
// (no password needed). Keys: LEBacklightMode (0 = off, 2 = on) and
// LEPWMFactorFadeDuration (fade seconds, 0 = automatic). If the private API
// is unavailable, on/off falls back to Apple's documented sudo defaults
// command with an admin prompt; strobe needs the private API.
import AppKit

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

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let light = LogoLight()

    private var effectTimer: Timer?
    private var effect: Effect?
    private var phaseOn = true
    private var wasOnBeforeEffect = true

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
        rebuild()
        // Stop effects when the display sleeps.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(stopEffectNotification),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
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
    @objc private func stopEffectNotification() { stopEffect(displaySleeping: true); rebuild() }

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
