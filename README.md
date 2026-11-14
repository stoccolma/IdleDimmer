# IdleDimmer

A small macOS menu bar app that dims a MacBook's built-in display when you step away, keeps the Mac awake on request, and can put up a decoy lock screen that hides your desktop from passers-by while automation agents (Claude, ChatGPT and similar) keep working underneath.

The menu is in English or Swedish, following the system language.

## What it does

**Idle dimming.** After 5 minutes without keyboard or mouse activity the built-in display drops to 5% brightness. Any activity restores the brightness it had before. *Dim now* and *Restore brightness* do the same by hand.

**Keep awake.** A menu switch runs the system `caffeinate -di` so the Mac and display do not sleep. It is off at launch and stops when you quit.

**Decoy lock.** *Lock screen (decoy)* covers every display with a lock-screen look (clock, date, password field). It is not the real macOS lock:

- Physical key presses, clicks, scrolling and gestures are swallowed. The pointer still moves.
- Input sent by other programs passes through, and the cover is excluded from screen capture, so an agent sees and controls the real desktop.
- Type your unlock code blind and press Return to unlock. You choose the code the first time you lock.
- Keep awake is switched on while locked, and dimming counts only physical inactivity.

**Wrong-code clip.** A wrong code starts a 20-second camera recording with sound, saved to `~/Movies/IdleDimmer`. When you unlock, a warning lists the attempts and links to the folder.

Menu bar icon: orange when keep awake is running, green when automatic dimming is on, white when both are off.

## Install

Requires macOS 13 or later and the Xcode command line tools (`xcode-select --install`).

    git clone https://github.com/stoccolma/IdleDimmer.git
    cd IdleDimmer
    ./build.sh
    open IdleDimmer.app

`build.sh` signs with a Developer ID certificate if one is in your keychain, otherwise ad hoc. With an ad hoc signature macOS forgets the permissions below after every rebuild.

## Permissions

| Permission | Needed for | Asked |
| --- | --- | --- |
| Accessibility | Blocking physical input while the decoy lock is on | First time you lock |
| Camera | Wrong-code clip | First time you lock |
| Microphone | Sound in the clip (optional; without it the clip is silent) | First time you lock |

Dimming and keep awake need no permissions.

## Limits you should know about

- **The decoy lock is a privacy screen, not security.** The session stays unlocked. A restart, a remote login or a crash of the app removes it. Touch ID is not used.
- **Forgotten code:** restart the Mac, or run `killall IdleDimmer` over ssh.
- **The camera's green light is on while recording** and cannot be hidden. Recording people may be regulated where you live; that is your responsibility.
- **Private API.** Brightness is set through Apple's private DisplayServices framework, which can change in any macOS update. It only works on the built-in display.
- **Secure input.** While another app has a password field focused, macOS can keep key presses away from the lock's filter.
- **Not everything is tested.** Verified with the lock on: screenshots, browser automation through the Claude in Chrome extension, and typing into a native app with Claude's background computer use. Not verified: agents that take over the whole screen, and ChatGPT.
- If the app crashes while the display is dimmed, restore brightness with the keyboard keys.

## Development

Everything is in `main.swift`; there are no dependencies.

    ./build.sh                                            # build and sign
    IdleDimmer.app/Contents/MacOS/IdleDimmer --probe      # read-only brightness check
    IdleDimmer.app/Contents/MacOS/IdleDimmer --camera-test 3   # record a 3-second clip
    tools/make-icon.sh                                    # regenerate the app icon

*Debug logging* in the menu writes state samples to `~/Library/Logs/IdleDimmer/debug.log` (no key contents, no screenshots). `restore-regression.swift` and `keep-awake-regression.swift` are standalone checks run with `swift <file>`. Design notes and test history are in [docs/DEVLOG.md](docs/DEVLOG.md).

## License

MIT, see [LICENSE](LICENSE).
