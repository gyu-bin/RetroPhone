# RetroPhone 아키텍처 / Architecture

SwiftUI (iOS 26+, Xcode 27, Swift 5 mode with **default MainActor isolation**). No third-party
packages. Xcode project uses *file-system synchronized groups*: any `.swift` file placed under
`RetroPhone/` is compiled automatically — no project edits needed.

## Modules (folders)

| Folder | Role |
|---|---|
| `App/` | `@main` entry, `RootView` (status bar, home button, lock overlay), `SpringboardView` (home ↔ app ↔ multitasking layering), `ClassicAppHost` (BuiltinApp → view) |
| `Core/` | `AppRouter` (navigation state), `HomeLayout` (pure layout model + packing/edit operations), `AppCatalog` (built-in + external apps), `Settings`, `Localization` |
| `Persistence/` | `FileStore` (JSON + images in Application Support), `LayoutStore` (debounced layout persistence, backup/restore) |
| `RetroUI/` | Design system: `RetroIconView`/`IconArt` (code-drawn icons), bars, buttons, grouped tables, toggle, segmented, search bar, alert, status bar, wallpapers |
| `Themes/` | `RetroTheme` tokens (iOS 4 today; iOS 5/6 later) |
| `LockScreen/` | Virtual lock screen + slide to unlock |
| `HomeScreen/` | Pager, dock, edit mode, drag & drop, folders, add/edit sheets, multitasking tray |
| `Widgets/` | Weather, battery, calendar, clocks, photo, notes, music |
| `ClassicApps/` | Internal apps (one folder per group) |
| `AppLauncher/` | External app launching (URL scheme → universal link → App Store) |
| `Services/` | System integrations: battery/network/clock, location, weather, EventKit, PhotoKit, MediaPlayer, notes store, sounds/haptics, screenshot OCR import |
| `Setup/` | First-run flow |
| `Resources/` | Asset catalog (app icon only — all other art is code-drawn) |

## Writing an internal app

Entry point is a `View` named `<Name>AppView` with no parameters (see `ClassicAppHost`). Apps lay out
**inside the safe area**: the root draws the classic status bar in the top inset and the virtual home
button in the bottom inset. Use `NavigationStack` + `ClassicPage` for each screen (the system navigation
bar is hidden; `ClassicPage` draws the iOS 4 bar).

```swift
struct FooAppView: View {
    var body: some View {
        NavigationStack {
            ClassicPage(title: L("푸"), leading: { EmptyView() }, trailing: {
                ClassicBarButton(title: L("편집")) { ... }
            }) {
                ScrollView { GroupedSection(header: L("섹션")) { TableRow(title: L("행"), chevron: true) } }
            }
            .navigationDestination(for: Item.self) { item in
                ClassicPage(title: item.name, leading: { ClassicBackButton() }, trailing: { EmptyView() }) { ... }
            }
        }
    }
}
```

### RetroUI API (all in `RetroUI/`)
- `ClassicPage(title:barStyle:background:leading:trailing:content:)` — nav bar + content, pinstripe background by default (`background: AnyView(Color.white)` for plain lists). `BarStyle`: `.blue`, `.black`, `.blackTranslucent`.
- `ClassicNavBar(title:style:leading:trailing:)`, `ClassicBarButton(title:kind:systemImage:barStyle:action:)` (`kind`: `.plain .done .back .destructive`), `ClassicBackButton()`.
- `ClassicToolbar(style:) { ... }`, `ToolbarIconButton(systemImage:label:enabled:action:)`.
- `GroupedSection(header:footer:) { rows }` — each direct child view becomes a row with separators. `TableRow(title:detail:icon:systemIcon:chevron:destructive:accessory:)`.
- `PlainRow { }`, `PlainSectionHeader(title:)` for plain (white) lists.
- `RetroToggle(isOn:label:)`, `RetroSegmented(options:[(T,String)], selection:style:)`, `RetroSearchBar(text:placeholder:)`.
- `GlossyButton(title:systemImage:tint:height:action:)` (`.green .red .blue .gray .black`).
- `PermissionPlaceholder(systemImage:title:message:requestTitle:request:denied:)` — use for every not-determined/denied permission state.
- `.retroAlert(title, isPresented:, message:, buttons: [RetroAlertButton])` — classic blue alert.
- `RetroIconView(art:size:)`, `IconArt` enum. `PinstripeBackground()`, `LinedPaper(lineSpacing:)`.
- Fonts: `.font(.retro(size, .bold))` (Helvetica, honours text-size setting); `.retroFixed` for chrome. `Color(hex: 0xRRGGBB)`. `.embossed()` for engraved text.
- Status bar style: `.retroStatusBar(.black)` / `.retroStatusBarHidden()` on the app root.

### Services (singletons, `@Observable`)
- `SoundService.shared.play(.tock | .keyClick | .shutter | .recordStart | .recordStop | .alarm | .timerDone | …)`, `playDTMF(Character)`; `Haptics.tap()/success()/warning()/selection()`.
- `LocationService.shared` — `currentLocation() async -> CLLocation?`, `isDenied`, `requestPermission()`.
- `WeatherService.shared` — `snapshot: WeatherSnapshot?`, `status`, `refresh()`, `refreshIfNeeded()`, `static searchCity(_:)`; `Double.temperatureString`; `WeatherGlyph(condition:isDay:size:)` view.
- `CalendarService.shared` — `store: EKEventStore`, `requestAccess()`, `hasFullAccess`, `isDenied`, `events(on:)`, `events(from:to:)`, `daysWithEvents(inMonthOf:)`, `delete(_:)`, `revision` (observe to reload). `MonthGrid.days(for:)`, `MonthGrid.weekdaySymbols()`.
- `PhotoLibraryService.shared` — `requestAccess()`, `canRead`, `isDenied`, `recentAssets(limit:)`, `albums()`, `image(for:size:contentMode:) async`, `save(_ data:) async throws`.
- `MusicService.shared` — `requestAccess()`, `isAuthorized`, `isDenied`, `songs()/albums()/artists()/playlists()`, `play(_:startAt:)`, `togglePlayPause()`, `next()`, `previous()`, `nowPlaying`, `isPlaying`, `player` (system music player).
- `NotesStore.shared` — `notes`, `create(_:)`, `update(_:text:)`, `delete(_:)`, `pruneEmpty()`.
- `BatteryMonitor.shared`, `NetworkMonitor.shared` (`isOnline`), `ClockTicker.shared.now` (minute-aligned).
- `RetroFormat.time(_:)`, `.date(_:template:)`, `.lockDate(_:)`.
- `AppRouter` via `@Environment(AppRouter.self)`; `router.pendingDeepLink` (`.calendar(Date)`, `.weather`).

### Localization
Korean is the source language. Wrap every user-visible string in `L("한국어")` (or `LF("%d개", n)` for formats).
Add English translations to the module's table, e.g. `ClassicApps/Media/MediaStrings.swift`
(`extension EnglishTable { static let appsMedia: [String: String] = ["사진": "Photos", …] }`).

### Concurrency rules
Types are MainActor by default. Delegate callbacks from AVFoundation/CoreLocation arrive on other
queues: mark such delegate methods (or a dedicated delegate class) `nonisolated` and hop back with
`Task { @MainActor in … }`. Closures passed to background-queue APIs should be `@Sendable`.

### Rules
- Public Apple frameworks only. No private API, no fake data (never show values iOS doesn't provide).
- Request each permission on first use of the feature; handle not-determined / denied / restricted.
- No user data leaves the device; don't log personal data.
