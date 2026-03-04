# Boring Notch Implementation Map

Use this map to translate the notch-app workflow into this repository's concrete implementation.

## App Entry and Lifecycle
- SwiftUI app entry, menu bar item, Sparkle updater setup:
  - `boringNotch/boringNotchApp.swift`
- Launch-time orchestration, window creation, display observers, onboarding:
  - `boringNotch/boringNotchApp.swift` (`AppDelegate`)

## Window Layer
- Custom top-level notch window (SkyLight-aware):
  - `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`
- Base notch panel:
  - `boringNotch/components/Notch/BoringNotchWindow.swift`
- Display space coordination:
  - `boringNotch/managers/NotchSpaceManager.swift`

## Notch State and Coordination
- Core notch state model (`open`, `close`, size, hover/drop signals):
  - `boringNotch/models/BoringViewModel.swift`
- Global cross-feature coordinator (HUD/sneak-peek, selected display, tabs):
  - `boringNotch/BoringViewCoordinator.swift`
- Shared defaults and feature flags:
  - `boringNotch/models/Constants.swift`

## Notch UI and Interaction
- Main notch layout, hover behavior, gesture handling, drop behavior:
  - `boringNotch/ContentView.swift`
- Notch home/media UI composition:
  - `boringNotch/components/Notch/NotchHomeView.swift`
- Gesture helpers:
  - `boringNotch/extensions/PanGesture.swift`
- Drag-enter detection for opening shelf:
  - `boringNotch/observers/DragDetector.swift`

## Media Architecture
- Media orchestration and normalized state:
  - `boringNotch/managers/MusicManager.swift`
- Protocol for provider-specific controllers:
  - `boringNotch/MediaControllers/MediaControllerProtocol.swift`
- Implementations:
  - `boringNotch/MediaControllers/NowPlayingController.swift`
  - `boringNotch/MediaControllers/AppleMusicController.swift`
  - `boringNotch/MediaControllers/SpotifyController.swift`
  - `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicController.swift`

## HUD Replacement and Hardware Control
- Media key interception and HUD routing:
  - `boringNotch/observers/MediaKeyInterceptor.swift`
- Volume handling:
  - `boringNotch/managers/VolumeManager.swift`
- Screen + keyboard brightness managers:
  - `boringNotch/managers/BrightnessManager.swift`

## XPC Helper Boundary
- Main app helper client:
  - `boringNotch/XPCHelperClient/XPCHelperClient.swift`
- Shared helper protocol:
  - `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
  - `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
- Helper service implementation and listener entrypoint:
  - `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
  - `BoringNotchXPCHelper/main.swift`

## Shelf (Drop + Persistence)
- Shelf state and mutation logic:
  - `boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift`
- Dropped item conversion:
  - `boringNotch/components/Shelf/Services/ShelfDropService.swift`
- Persistence:
  - `boringNotch/components/Shelf/Services/ShelfPersistenceService.swift`
- Shelf UI:
  - `boringNotch/components/Shelf/Views/ShelfView.swift`
  - `boringNotch/components/Shelf/Views/ShelfItemView.swift`

## Settings and Onboarding
- Settings window host:
  - `boringNotch/components/Settings/SettingsWindowController.swift`
- Settings tabs and toggles:
  - `boringNotch/components/Settings/SettingsView.swift`
- Software update controls:
  - `boringNotch/components/Settings/SoftwareUpdater.swift`
- Onboarding and permissions flow:
  - `boringNotch/components/Onboarding/OnboardingView.swift`

## Build and Release
- Xcode project target configuration:
  - `boringNotch.xcodeproj/project.pbxproj`
- CI build workflow:
  - `.github/workflows/cicd.yml`
- Reusable signed build and packaging:
  - `.github/workflows/build_reusable.yml`
- Release + appcast update flow:
  - `.github/workflows/release.yml`
- DMG packaging scripts:
  - `Configuration/dmg/create_dmg.sh`
  - `Configuration/dmg/dmgbuild_settings.py`

## Practical Build Order for New Features
1. Add state and defaults in `BoringViewModel`/`Constants`.
2. Extend coordinator notifications only if cross-feature behavior is required.
3. Add UI in `ContentView` or feature subviews.
4. Add manager/controller code for side effects or external app integration.
5. Add settings toggles and persistence wiring.
6. Validate multi-display, lock-screen, and fullscreen behavior.
