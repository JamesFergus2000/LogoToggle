# LogoToggle

**Website:** https://jamesfergus2000.github.io/LogoToggle/

A tiny menu bar app for the illuminated Apple logo on the MacBook Pro with PROLED XDR Display.

- **On / off**: no password needed
- **Breathe**: smooth hardware fades in and out (slow, medium, fast)
- **Strobe**: rapid flashing (slow, medium, fast)

It's a single Swift file with no dependencies, and it lives only in the menu bar (no Dock icon).

> ⚠️ **Photosensitivity warning:** strobe mode flashes up to about 4 times a second. Don't use it around people who may be affected by flashing lights.

## Requirements

- A MacBook Pro with the illuminated logo (PROLED XDR Display)
- macOS 27 or later, Apple silicon

## Install

### One-line install (easiest)

Paste this into Terminal. It downloads the latest release, installs it into Applications and opens it, with no Gatekeeper prompt:

```sh
curl -fsSL https://jamesfergus2000.github.io/LogoToggle/install.sh | sh
```

### Download

1. Download `LogoToggle.zip` from [Releases](../../releases) and unzip it.
2. Move `LogoToggle.app` to Applications.
3. The app isn't notarized by Apple, so the first time you open it macOS will block it. Go to
   **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to
   LogoToggle. Alternatively, run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/LogoToggle.app
   ```

### Build from source

You'll need the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/JamesFergus2000/LogoToggle.git
cd LogoToggle
./build.sh --install     # builds and copies to ~/Applications
open ~/Applications/LogoToggle.app
```

Apps you build yourself aren't quarantined, so there's no Gatekeeper prompt.

To start it automatically, add it under **System Settings → General → Login Items**.

## How it works

LogoToggle talks to `corebrightnessd`, the system service that drives the logo LED, through
`BrightnessSystemClient` in the private `CoreBrightness` framework. That works without root.

| Key | Used for |
| --- | --- |
| `LEBacklightMode` | `0` off, `2` on: the on/off switch and strobe |
| `DisplayLogicalState` | `1` Blank / `2` Unblank fades the logo: used for breathe |
| `LEPWMFactorFadeDuration` | how long the next fade takes |

The keyboard backlight also follows `DisplayLogicalState`, so after each fade-out LogoToggle tells
the keyboards on their own to stay lit.

If the private API is missing, on/off falls back to the command from Apple's support article
"About the illuminated Apple logo on MacBook Pro with PROLED XDR Display", which needs an admin
password:

```sh
sudo defaults write com.apple.CoreBrightness LEBacklightMode -int 0   # off
sudo defaults delete com.apple.CoreBrightness LEBacklightMode         # on
```

**This relies on undocumented Apple behaviour and may break with any macOS update.** It can't be
distributed through the Mac App Store.

## Credits

The `DisplayLogicalState` fade technique and the keyboard workaround come from the excellent
research in [**LogoLight**](https://github.com/Ark0N/LogoLight) by Ark0N
([docs/corebrightnessd.md](https://github.com/Ark0N/LogoLight/blob/main/docs/corebrightnessd.md)),
which is MIT-licensed. If you want brightness control, more effects, sound-reactive mode, Morse code
or Control Center integration, use LogoLight. LogoToggle is the minimal version.

## Licence

MIT. See [LICENSE](LICENSE).
