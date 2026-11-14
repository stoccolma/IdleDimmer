# IdleDimmer

Open IdleDimmer.app. Its ◐ menu enables/disables automatic dimming, offers Dim now / Restore brightness, and quits.

After 5 minutes without keyboard/mouse activity, the built-in display drops to 5% brightness (unless it is already dimmer). Activity restores the previous brightness. Normal quit also restores it. A manual brightness change takes precedence. Sleep, locking and caffeinate are not modified. No login item is installed.

Keep caffeinate -di running if required for computer-use sessions. Brightness dimming does not prevent the normal lock policy from applying.

Build:

    swiftc main.swift -o IdleDimmer.app/Contents/MacOS/IdleDimmer -framework AppKit -framework CoreGraphics

Read-only diagnostic:

    IdleDimmer.app/Contents/MacOS/IdleDimmer --probe

Uses Apple's private DisplayServices brightness functions on the built-in display. These may change in macOS updates. No downloads or third-party dependencies. If the process crashes while dimmed, restore brightness with the hardware keys.

Validation: compiled successfully on arm64 macOS 27.0.1. The read-only diagnostic found built-in display 1 and read brightness and the all-input idle counter. GUI launch/interaction verification was blocked by computer-use timeouts; actual dim/restore and the full five-minute cycle are not yet verified. A later read-only probe could not access brightness, so availability must be checked in the user's active desktop session.
