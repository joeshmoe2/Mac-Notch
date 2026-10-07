# NotchHub

NotchHub turns the MacBook notch into an expandable widget hub, similar in spirit to NotchNook and Boring Notch. It's a native Swift + SwiftUI app (with AppKit where needed) for **macOS 14 Sonoma or later**.

Move the cursor onto the notch and it springs open into a panel with tabs for:

- **Timer**: run several timers at once. Running and paused timers survive quitting NotchHub.
- **Pomodoro**: focus and break cycles. During focus it can show a full-screen block screen over distracting apps, block websites, and turn on a Focus (Do Not Disturb).
- **Notes**: quick notes with checklists, saved as Markdown files you can see in Finder. They're shared with **NotchNotes**, a full-window companion app (see below).
- **File Shelf**: a temporary drop zone for files.
- **Weather**: current conditions and an hourly forecast.
- **Now Playing**: Music and Spotify controls, volume and output device.
- **Calendar (Next Up)**: today's and upcoming events by calendar color, a countdown beside the notch before the next event, and **Join** buttons for Zoom, Google Meet and Teams links.
- **Reminders**: reminders from the lists you choose; tick them off or quick-add new ones with a due date.
- **Clipboard**: history of copied text, links and images; click to copy again, pin favorites. *Off by default.* Passwords and copies from password managers are never saved.
- **Mirror**: a camera preview to check yourself before a call. *Off by default.* The camera is on only while the tab is open.
- **Quick Actions**: a grid of buttons that run your Apple Shortcuts.

The **File Shelf** also picks up new screenshots automatically (Settings → Shelf). On first launch, a short **welcome window** explains the notch and asks for each permission one at a time (all skippable); reopen it from Settings → General.

There is also a **Home** dashboard that shows several modules at once. While the notch is collapsed, it can show small *live activities* on either side of the camera housing: album art with audio bars, a timer countdown, or a Pomodoro ring.

---

## Building

Requirements: **Xcode 16 or later** (the project uses Xcode 16's folder-synchronized groups) and macOS 14 or later.

1. Open `NotchHub.xcodeproj`.
2. Select the **NotchHub** scheme and *My Mac*, then press **Run**.

The project is set to *Sign to Run Locally*, so it builds without a developer team. To distribute it, choose your team under *Signing & Capabilities*.

From the command line:

```bash
xcodebuild -project NotchHub.xcodeproj -scheme NotchHub -configuration Release build
```

New `.swift` files you add anywhere under `NotchHub/` are picked up automatically. You don't need to edit `project.pbxproj`.

The CI workflow `.github/workflows/build.yml` builds the project on a macOS runner for every push.

NotchHub is an agent app (`LSUIElement`), so it has **no Dock icon**. Use the menu bar icon (▭) to toggle the notch, open Settings, or quit. The default global shortcut is **⌥⌘N**.

---

## NotchNotes (companion app)

NotchNotes is a regular windowed note-taking app built from the same project (scheme **NotchNotes**). It reads and writes the same notes as the notch's Notes module.

- **Storage**: every note is a Markdown file (`.md`) in `~/Documents/NotchHub Notes/` by default. You can change the folder in either app's settings (Settings → Notes in NotchHub, ⌘, in NotchNotes) and both apps follow. Put it in iCloud Drive to sync between Macs, or open the files in any editor.
- **File names follow the note's first line.** Deleting a note moves its file to the Trash.
- **Live sync**: both apps watch the folder, so edits in one show up in the other within a moment. Changes made in other editors appear too.
- **Getting there**: the notes button next to Settings in the notch's top bar, the **Open in NotchNotes** button in the Notes tab, or **Open NotchNotes** in the menu bar menu.
- **Deleting is deliberate**: there's no ⌘⌫ shortcut (that key keeps deleting text in the editor). Deleting asks for confirmation (in the notch, click the trash icon twice), and the file goes to the Trash.
- **Formats as you type**: the editor styles Markdown live (headings, bold, italic, strikethrough, code, highlight, links, quotes, lists); the symbols stay in the file but are dimmed. Click a `[ ]` to tick it, and Return continues a list (Return on an empty item ends it). Turn it off in Settings if you prefer plain text.
- **Markdown**: Edit, Split and Preview modes (⌘1 / ⌘2 / ⌘3). Preview renders headings, bold/italic, strikethrough, quotes, lists, clickable task lists, code blocks, tables, links, images, horizontal rules, footnotes, definition lists, ==highlight==, sub~script~/super^script^ and :emoji: shortcodes. The Format menu and toolbar add Markdown for you (⌘B, ⌘I, ⌘K, ⌥⌘1–3, …). A **Markdown Cheat Sheet** note is created on first launch (restore it from Settings). In the notch, the eye button previews the formatted note.
- **Accent color**: NotchNotes and the live editor use the accent color chosen in NotchHub (Settings → Appearance), and update immediately when you change it. Until NotchHub has run once, NotchNotes uses its own orange accent.
- **Features**: sidebar with search, a large editor, insert checkbox (⇧⌘L), word count, share and Show in Finder.
- The first time NotchHub starts after this update, notes from the old `notes.json` are converted to files automatically (the old file is kept as `notes.json.migrated`).

**NotchNotes is built into NotchHub.** Building or archiving NotchHub also builds NotchNotes and embeds it at `NotchHub.app/Contents/Helpers/NotchNotes.app`. Open it from the menu bar icon (**Open NotchNotes**), from Settings → Notes, or from the window button on a note. **Settings → Notes → Add to Applications** copies it to `/Applications` so it appears in Launchpad and Spotlight. You can still run it on its own with the **NotchNotes** scheme while developing.

## Permissions, entitlements and Info.plist keys

| Purpose | Info.plist key / entitlement | Notes |
|---|---|---|
| Agent app (no Dock icon) | `LSUIElement = YES` | Set in `Info.plist` and as `INFOPLIST_KEY_LSUIElement`. |
| Weather location | `NSLocationWhenInUseUsageDescription`, `NSLocationUsageDescription` | Asked the first time Weather refreshes. If you deny it, set a city in **Settings → Weather**. |
| Location under the Hardened Runtime or sandbox | `com.apple.security.personal-information.location` | In `NotchHub.entitlements`. |
| Controlling Music and Spotify | `NSAppleEventsUsageDescription` | macOS asks once per player ("NotchHub wants to control Spotify"). |
| Apple Events under the Hardened Runtime | `com.apple.security.automation.apple-events` | In `NotchHub.entitlements`. |
| Notifications | none | Requested during onboarding or the first time a timer or Pomodoro starts. |
| Calendar | `NSCalendarsUsageDescription`, `NSCalendarsFullAccessUsageDescription`, entitlement `com.apple.security.personal-information.calendars` | Asked from the Calendar tab ("Allow Calendar Access"). If denied, the tab links to Privacy settings. |
| Reminders | `NSRemindersUsageDescription`, `NSRemindersFullAccessUsageDescription` (same calendars entitlement) | Asked from the Reminders tab. |
| Camera (Mirror) | `NSCameraUsageDescription`, entitlement `com.apple.security.device.camera` | Asked the first time the Mirror tab opens. |
| Clipboard history | none | Reads the general pasteboard only while the module is enabled. |
| Screenshot shelf | none | Reads the screenshot location from `com.apple.screencapture` and watches that folder. |
| Quick Actions | none | Runs `/usr/bin/shortcuts run "<name>"`. |
| Launch at login | none | Uses `SMAppService.mainApp`. If macOS asks, approve NotchHub in *System Settings → General → Login Items*. |
| Pomodoro app blocking | none | Shows a full-screen block screen (or hides/quits the app) when a chosen app opens during a focus phase (NSWorkspace launch/activate notifications). |
| Pomodoro website blocking | Administrator password, once | "Install Website Blocker" installs `/usr/local/libexec/notchhub-hosts` (root-owned) and `/etc/sudoers.d/notchhub`, which let NotchHub add/remove only its own marked `0.0.0.0 <domain>` block in `/etc/hosts`. Uninstall from the same settings page. |
| Pomodoro Focus / Do Not Disturb | none | macOS has no public API for this, so NotchHub runs two Shortcuts you create (`shortcuts run "NotchHub Focus On"` / `"NotchHub Focus Off"`) using the **Set Focus** action. |
| Global shortcut | none | Uses Carbon `RegisterEventHotKey`, which doesn't need Accessibility permission. |
| Hover detection | none | Global `mouseMoved` / `leftMouseDragged` monitors don't need Accessibility permission. Only key monitors do. |

When a permission is denied, the module shows an explanation and a button that opens the right pane in System Settings. Each module keeps working as far as it can without the permission: Weather falls back to a manual city, timers still ring in-app, and Now Playing explains what is missing.

The app is **not sandboxed** by default, which makes AppleScript and CoreAudio simpler to use. To sandbox it, add the App Sandbox capability plus these entitlements:

- `com.apple.security.network.client` (for Open-Meteo)
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.files.bookmarks.app-scope`
- `com.apple.security.temporary-exception.apple-events` listing `com.apple.Music` and `com.spotify.client`

The File Shelf detects the sandbox automatically and switches to security-scoped bookmarks.

---

## Architecture

```
NotchHub/
├── App/                 NotchHubApp (@main, MenuBarExtra, Settings scene), AppDelegate, AppState
├── NotchWindow/         AppKit panel + SwiftUI shell
│   ├── NotchPanel.swift              non-activating NSPanel + tracking container view
│   ├── NotchWindowController.swift   hover/click/drag state machine, event monitors
│   ├── NotchWindowManager.swift      one controller per screen, display change handling
│   ├── NotchGeometry.swift           notch detection (safeAreaInsets + auxiliaryTop*Area)
│   ├── NotchViewModel.swift          @Observable per-screen UI state
│   ├── NotchRootView.swift           shape, background, collapsed live activity, drop target
│   ├── ExpandedView.swift            header tab bar, Home dashboard
│   ├── NotchShape.swift              animatable notch silhouette, blur background
│   └── SharedComponents.swift        buttons, progress ring, permission row
├── Modules/
│   ├── NotchModule.swift             the module protocol + LiveActivity
│   ├── ModuleRegistry.swift          enable/order/home/live-activity priorities
│   ├── Timer/  Pomodoro/  Notes/  FileShelf/  Weather/  Audio/
│   ├── Calendar/  Reminders/  Clipboard/  Camera/  QuickActions/
├── Services/            Location, Weather (Open-Meteo), Media (AppleScript), MediaRemote (optional),
│                        AudioDevice (CoreAudio), Notifications, HotKey, AppleScriptRunner,
│                        EventKit, PasteboardWatcher, Camera, ScreenshotWatcher, Shortcuts
├── Models/              CountdownTimer, Note, ShelfItem, WeatherModels, JSONStore
├── Settings/            Preferences (typed UserDefaults keys), SettingsView, SettingsTransfer
└── Resources/           Assets
Shared/                  Code compiled into both apps: Note, NotesStore (Markdown files + folder watching),
                         MarkdownParser/MarkdownInline/MarkdownView (rendering), MarkdownCheatSheet,
                         NotesFolderSettings
NotchNotes/              The companion app: NotchNotesApp, ContentView, Assets
```

### Key design decisions

- **The window code is AppKit-only.** `NotchPanel` is a borderless `.nonactivatingPanel` at `mainMenu + 3` level, with `canJoinAllSpaces` and `fullScreenAuxiliary`. That keeps it above the menu bar, on every Space and over full-screen apps, and it never takes focus. It can become key only when you click into a text field.
- **Mouse handling.**
  - **Collapsed:** the panel sets `ignoresMouseEvents = true`, so clicks pass through to the menu bar. Hover is detected with a global `mouseMoved` monitor, which costs nothing while the mouse is elsewhere.
  - **Expanded:** an `NSTrackingArea` (`.activeAlways`) plus the global monitor detect when the mouse leaves.
  - **File drags:** detected by watching the drag pasteboard's `changeCount` during `leftMouseDragged`, so the notch can open *before* the drop lands.
- **Collapse is suppressed** while:
  - a file drag is over the notch,
  - a text view is first responder,
  - a mouse button is held (for example, while dragging a shelf item out),
  - or a share sheet, menu or child window is open.

  Esc or a click elsewhere always closes it.
- **Settings window.** Settings is a dedicated `NSWindow` (`SettingsWindowController`), not the SwiftUI `Settings` scene, which can't be opened reliably from an agent app's panel. While Settings or onboarding is open the app temporarily becomes a regular app (Dock icon, ⌘-Tab) so the window comes to the front, then goes back to menu-bar-only.
- **Low idle CPU.** Nothing polls.
  - Timers and Pomodoro schedule one `Task.sleep` until their end date. Their views redraw with `TimelineView(.periodic)` only while visible.
  - Now Playing listens to Music and Spotify distributed notifications.
  - Volume and output devices use CoreAudio property listeners.
  - Weather wakes once per refresh interval.
- **Display changes.** `didChangeScreenParametersNotification` and wake events trigger a debounced rebuild of the per-screen panels. That covers plugging in monitors, closing the lid (the notch moves to the main screen) and resolution changes.
- **Animations.** The notch frame and shape animate with springs scaled by the *Animation speed* setting. Tab selection uses `matchedGeometryEffect`, and the album art morphs between the collapsed live activity and the expanded player.
- **Settings.**
  - Every setting is a typed `PrefKey` (namespaced `nh.*`) used through `@AppStorage(Prefs.someKey)` in views, or `Prefs.someKey.value` in non-view code.
  - Export, import and reset work generically on the `nh.` prefix.
  - Module choices (order, enabled, Home, live-activity priority) are persisted by `ModuleRegistry`.
- **Data.** Notes are Markdown files in a user-chosen folder (default `~/Documents/NotchHub Notes/`). The notes folder location is kept in the shared preferences domain `com.notchhub.shared`, so both apps agree on it. Shelf items and the weather cache are JSON files in `~/Library/Application Support/NotchHub/`.

---

## Adding a new module

1. Create `NotchHub/Modules/MyThing/MyThingModule.swift`:

```swift
import SwiftUI

extension Prefs {
    // Per-module settings: keys are namespaced automatically ("nh.mything.greeting").
    static let myThingGreeting = PrefKey("mything.greeting", "Hello")
}

@Observable
@MainActor
final class MyThingModule: NotchModule {
    let id = "mything"            // stable, used for persistence
    let name = "My Thing"
    let icon = "star.fill"        // SF Symbol

    var count = 0

    func compactView() -> AnyView {          // tile on the Home dashboard
        AnyView(Text("Count: \(count)"))
    }

    func expandedView() -> AnyView {         // full tab content
        AnyView(Button("Tap") { self.count += 1 }.buttonStyle(PillButtonStyle()))
    }

    func settingsView() -> AnyView {         // rows inside Settings → My Thing
        AnyView(MyThingSettings())
    }

    // Optional:
    var supportsLiveActivity: Bool { true }
    var liveActivity: LiveActivity? {        // nil = nothing to show
        guard count > 0 else { return nil }
        return LiveActivity(moduleID: id) {
            Image(systemName: icon)
        } trailing: {
            Text("\(count)").monospacedDigit()
        }
    }
    var enabledByDefault: Bool { true }      // false = starts switched off (privacy-sensitive)
    func setActive(_ active: Bool) { /* start/stop observers */ }
    func willExpand() { /* refresh stale data */ }
}

struct MyThingSettings: View {
    @AppStorage(Prefs.myThingGreeting) private var greeting
    var body: some View { TextField("Greeting", text: $greeting) }
}
```

2. Register it in `AppState.makeModules()`. Its position in that list is the default tab order.

That's all. The module automatically appears:

- in the tab bar,
- in **Settings → Modules** (enable, reorder, Home, live-activity priority),
- and in the Settings sidebar with its own page.

Because modules are `@Observable` classes, SwiftUI updates the tab, the Home tile and the live activity automatically whenever the module's state changes.

---

## Known limitations

- **Now Playing only supports Music and Spotify by default.** The private MediaRemote framework, which would cover every player, is restricted to Apple-entitled processes on macOS 15.4 and later. It's available as an opt-in experimental fallback (*Settings → Now Playing*), and the tradeoffs are documented in `MediaRemoteBridge.swift`.
- **AppleScript needs the player to be running.** NotchHub never launches Music or Spotify itself. The first contact with each player triggers a macOS Automation prompt.
- **Music artwork** comes back as raw data over AppleScript. Some streamed tracks have no artwork data, and a placeholder is shown.
- **The notch geometry comes from public NSScreen APIs.** On a few scaled resolutions the overlay can be off by a point or two; it includes 2 pt of overdraw to hide this.
- **Clicking inside the expanded notch while another app is in full screen** may briefly show the menu bar, which is macOS behavior for windows at menu-bar level.
- **Timers and Pomodoro are saved with end dates**, so they keep counting while NotchHub is quit; anything that ran out meanwhile is shown as finished on launch (no notification is sent for it).
- **Clipboard history polls `changeCount` every 0.5 s** while enabled — macOS has no pasteboard-change notification. Reading the counter is essentially free, and the timer has tolerance so the system can coalesce wake-ups.
- **Calendar links** are detected for Zoom, Google Meet and Microsoft Teams URLs in the event's URL, location or notes; other services don't get a Join button.
- **The shelf auto-clear check** runs when the notch opens and at launch, not on a background timer.
- **Website blocking uses `/etc/hosts`**, so it works in every browser but can be bypassed by a VPN or a browser's "secure DNS" (DNS-over-HTTPS) setting, and tabs already open may keep working until reloaded. It's a focus aid, not parental controls. True Screen Time–style blocking (like Opal) requires Apple's Family Controls entitlement, which Apple grants per developer.
- **App blocking is "soft"**: a blocked app is hidden (or quit) as soon as it opens or comes to the front, but it isn't prevented from running in the background. Notification silencing depends on the two Shortcuts existing in the Shortcuts app.
- **Live activities show one module at a time**, the highest-priority active one.
- **Launch at login** needs the app in `/Applications` (or another stable location) to behave reliably.
