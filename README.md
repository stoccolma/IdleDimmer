# IdleDimmer

Open IdleDimmer.app. Its ◐ menu enables/disables automatic dimming, offers Dim now / Restore brightness, and quits.

After 5 minutes without keyboard/mouse activity, the built-in display drops to 5% brightness (unless it is already dimmer). Activity restores the previous brightness. Normal quit also restores it. Each dim cycle restores the fixed brightness captured two seconds before dimming, even if brightness changes while dimmed. An optional independent keep-awake menu switch runs caffeinate -di. Lock settings are not modified. No login item is installed.

Use “Håll datorn vaken (caffeinate -di)” when needed; no Terminal command is required. Brightness dimming does not prevent the normal lock policy from applying.

Build:

    swiftc main.swift -o IdleDimmer.app/Contents/MacOS/IdleDimmer -framework AppKit -framework CoreGraphics

Read-only diagnostic:

    IdleDimmer.app/Contents/MacOS/IdleDimmer --probe

Uses Apple's private DisplayServices brightness functions on the built-in display. These may change in macOS updates. No downloads or third-party dependencies. If the process crashes while dimmed, restore brightness with the hardware keys.

Validation: compiled successfully on arm64 macOS 27.0.1. The read-only diagnostic found built-in display 1 and read brightness and the all-input idle counter. GUI launch/interaction verification was blocked by computer-use timeouts; actual dim/restore and the full five-minute cycle are not yet verified. A later read-only probe could not access brightness, so availability must be checked in the user's active desktop session.

Fix 2026-10-19: polling now runs in common run-loop modes so menu tracking does not pause it. Failed restore attempts remain pending and retry every 0.5 seconds. Wake and screen-wake request restoration. Restore/disable cancels delayed manual dim requests. Build and git diff --check passed. The read-only probe reported brightness unavailable in this execution session; physical dim/restore still requires checking in the active desktop session.

## Debug logging (2026-10-20)

Restart the app, then enable **Debug logging** in the ◐ menu. The setting persists across launches. **Capture debug snapshot** records the current state; **Open debug log** enables logging if necessary and opens the file. Logs are local at `~/Library/Logs/IdleDimmer/debug.log`, rotate at roughly 2 MB with one previous file, and contain no key contents or screenshots. Disable logging when finished.

Records include five-second state samples (idle seconds, brightness, saved brightness, restore pending, enable/wait flags), display-service write return codes and immediate readback, failed reads, activity-triggered restores, manual-change decisions, wake notifications and timer gaps. Immediate readback may precede a brightness animation settling; compare later samples. When stuck, capture a snapshot BEFORE choosing Restore brightness, then capture another afterwards and provide debug.log and debug.log.previous if present.

Validation: Swift compilation and git diff --check passed. Hardware dim/restore and menu interaction have not been verified in the active desktop session. This change adds diagnostics; it does not claim the remaining intermittent bug is fixed.

2026-10-22: Fixed restore target captured two seconds before dim. Activity cancels preparation. Restore always writes saved target; only a successful write plus readback within one percentage point clears it. Failed/unconfirmed restores retry. Build and diff check pass. restore-regression.swift executes the restore method with a fake brightness device: drift, failed write, unconfirmed readback and successful retry pass. Hardware interaction still requires desktop verification.

Menu icon: green when automatic dimming is enabled, white when disabled. Updated at launch and when toggled. Compiled successfully; visual desktop check remains.

## Keep awake (2026-10-25)

The independent “Håll datorn vaken (caffeinate -di)” toggle starts the system caffeinate tool with display/idle-sleep assertions. It starts off on each app launch. Orange icon = keep awake running (regardless of dimming), green = dimming enabled without keep awake, white = both off. The tooltip and checkmarks show both independent states. Dimming to 5% still works while keep awake runs. Stop/quit releases the app-owned process; Existing external caffeinate processes are untouched. Unexpected child exit resets the checkmark and icon; launch errors are shown and logged. Normal lock settings remain unchanged.

Validation: build, restore regression and keep-awake process regression passed (real caffeinate start, duplicate prevention, stop, unexpected exit cleanup). Menu colors and physical sleep prevention remain to verify in the active desktop session.

2026-10-26: User reports no visible dimming despite successful API readback. Readback alone is not proof of physical screen behavior. Caffeinate now uses exactly -di, without -w, matching the reported working Terminal command; this is a diagnostic compatibility change, not a confirmed cause. Normal stop/quit terminates the child, but a crash can now leave it running. Manual Dim now preparation is no longer cancelled by incidental mouse movement during its two-second sample interval; Restore/disable still cancels it. Automatic preparation remains activity-cancellable. Build identifier added to debug launch entry.

## Skenlås (2026-11-14)

**Lås skärmen (skenlås)** i ◐-menyn täcker alla skärmar med en låsskärmsliknande bild (klocka, datum, lösenordsfält) utan att låsa macOS-sessionen. Fysiska tangenttryck, klick, scroll och gester sväljs; syntetisk inmatning (händelser postade av andra processer, t.ex. Claude och ChatGPT) släpps igenom till apparna under, och täckfönstret är undantaget från skärmdumpar/skärminspelning så agenterna ser det riktiga skrivbordet. Muspekaren går fortfarande att flytta.

Lås upp: skriv koden blint och tryck Retur (Esc tömmer, backsteg raderar). Koden väljs första gången, eller via **Ställ in upplåsningskod…**, och sparas som saltad SHA-256 i appens inställningar. Kräver behörigheten Hjälpmedel (Systeminställningar → Integritet och säkerhet → Hjälpmedel); eftersom binären är osignerad kan behörigheten behöva ges om efter varje ombyggnad. Medan skenlåset är på startas "håll vaken" automatiskt (och stängs av vid upplåsning om låset startade den), och dimningen räknar bara fysisk inaktivitet så att agenternas arbete inte tänder skärmen igen.

Detta är ett insynsskydd, inte ett säkerhetslås: sessionen är upplåst, Touch ID används inte, och fjärrinloggning, omstart eller en krasch tar bort det. Glömd kod: stäng locket/starta om, eller `killall IdleDimmer` via ssh. När ett annat program har säker inmatning aktiv (lösenordsfält i fokus) kan macOS hålla tangenttryck borta från filtret.

Validering: kompilerar. En separat probe på denna Mac bekräftade att ett fönster med sharingType none syns på skärmen men saknas i `screencapture`, och att en postad händelse bär avsändarens pid i en event tap. Själva låsläget (täckning, blockering av fysisk inmatning, upplåsning med kod, agentarbete under låset) är inte kört på skrivbordet ännu.

### Film vid fel kod (2026-11-14)

När fel kod anges på skenlåset spelar kameran in 20 sekunder video med ljud till `~/Movies/IdleDimmer/fel-kod-<datum>_<tid>.mov`. En inspelning i taget: fler felförsök under pågående film startar ingen ny. **Visa filmer från fel kod** i ◐-menyn öppnar mappen. Kamera- och mikrofonbehörighet efterfrågas första gången skärmen låses; utan kamera hoppas filmen över, utan mikrofon blir den stum (loggas i debugloggen). När rätt kod sedan anges visas en varning med antal felförsök, tidpunkter och knappen **Visa filmer** som öppnar mappen; felförsöken räknas per låsning och sparas inte efter att varningen stängts. Kamerans gröna lampa lyser under inspelningen och går inte att stänga av. Filmerna rensas inte automatiskt.

Test utan att låsa: `IdleDimmer.app/Contents/MacOS/IdleDimmer --camera-test 3` spelar in tre sekunder och skriver ut sökvägen.

Validering: kompilerar, Info.plist giltig. `--camera-test` från agentens skal hoppade över inspelningen eftersom kamerabehörighet inte var given där; ingen film har spelats in ännu.

Ljud och varning vid upplåsning: kompilerar, Info.plist giltig; inte körda på skrivbordet.

2026-11-14, kört på skrivbordet: användaren bekräftade att låset täcker skärmen, att Cmd-Tab och övrig fysisk inmatning stoppas, att upplåsning med kod fungerar, att filmen spelas in och att varningen visas. Med låset på tog Claude skärmdumpar av Chrome och TextEdit (låsbilden syntes inte), navigerade och läste text via Chrome-tillägget och skrev text i TextEdit i bakgrundsläge, inklusive ett tabbtryck som rå tangentinmatning; se skenlas-test.txt. Inte testat: styrning av hela skärmen (händelser postade på sessionsnivå, den väg filtrets pid-kontroll gäller) och ChatGPT.
