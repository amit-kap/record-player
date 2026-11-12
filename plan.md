# record-player: build plan

## Approach
- **Stack:** native Swift and SwiftUI, built with Xcode 26.6 (installed). Target: macOS 15 or later.
- **Playback:** Apple's MusicKit for Swift. `ApplicationMusicPlayer` plays the queue; `MusicAuthorization` handles access.
- **Picker data:** `MusicLibraryRequest` for library albums and playlists; `MusicCatalogSearchRequest` for catalog search.
- **3D:** RealityKit inside SwiftUI (`RealityView`), with a fixed top-down camera. Fallback: SceneKit.
- **Turntable model:** a real 3D model scripted in Blender (`Models/turntable.py`, rebuilt with `scripts/build-model.sh`) and loaded as `Turntable.usdz`. Reference: Audio-Technica AT-LP140XP, no branding. The record is still built in code, because its label and grooves change at runtime.
- **Label artwork:** the album or playlist artwork, loaded as a texture on the label disc.
- **App state:** one observable player model owns the queue, the playback state and the tonearm position. The 3D scene and the buttons both read from it and write to it.
- **Themes:** materials, lighting and colours come from one theme value, so later themes are data, not new code.
- **Stored data:** only the last loaded record. No accounts and no server.
- **Tests:** unit tests for the pure logic (tonearm angle ↔ track and time). Playback and 3D are verified by hand against the acceptance criteria in `prd.md`.

## Risks
1. **Apple Music playback on macOS may not work reliably through MusicKit.** Earliest test: M1, a bare app that signs in and plays one full album. Fallback routes, in order: control the Music app through AppleScript; MusicKit JS in a web view.
2. **Library artwork may not load as a texture** (library items can return non-web artwork URLs). Earliest test: M1, load one library album's artwork into an image. Fallback: look up the matching catalog item's artwork.
3. **Dragging the tonearm may feel wrong in RealityKit on macOS.** Earliest test: M2, a draggable arm that rotates on its pivot with limits. Fallback: SceneKit.
4. **A code-built model may look too plain next to the reference.** Earliest test: M2, Amit reviews a screenshot against `ref/record-player-ref.jpg`. Fallback: Amit models the tonearm, or a sourced model.
5. **The notarized build may not play music on a friend's Mac.** Earliest test: M6 starts with one build sent to one friend before any polish.

## Milestones
1. **Playback test (2 days).** Bare window: sign in, load one album, play, pause, skip, show artwork.
   Verified by: criteria 1 and 2; risks 1 and 2 answered. **Needs the Apple Developer membership.**
2. **Turntable scene (4 days).** Plinth, platter, record, label and tonearm in the dark theme; platter spins; tonearm drags. No music yet.
   Verified by: criteria 13 and 14; Amit approves the look against the reference.
3. **Turntable plays music (4 days).** Scene wired to the player: tonearm play, stop and seek, progress tracking, spin-up, buttons, keys, track info.
   Verified by: criteria 6 to 11.
4. **Record picker (4 days).** Library shelf and catalog search for albums and playlists; picking one loads it.
   Verified by: criteria 3, 4, 5 and 16.
5. **Record change and states (3 days).** Record change animation, last record restored on launch, error states.
   Verified by: criteria 12 and 17.
6. **Friends' build (3 days).** Signing, notarization, a DMG, app name and icon, one friend install, fixes.
   Verified by: criterion 15, and a friend plays an album.

Total: 20 working days, inside the 4-week budget.

## Delivery
- **Setup:** Amit enrolls in the Apple Developer Program ($99/year), then enables the MusicKit service for the app's bundle ID. I walk through this at the start of M1.
- **Access:** each user needs their own Apple Music subscription and allows access on first run.
- **Deployment:** a Developer ID signed and notarized DMG, sent to friends directly. No App Store.
- **Running costs:** the $99/year membership. No server.
- **Repo:** local git on `main`. A GitHub repo is created when Amit asks; its link goes in `repo:` in `concept.md`.

## Status
Current milestone: M2, built, waiting for Amit's review (2026-11-12). M1 is not started and is blocked on the Apple Developer membership.

M2 so far:
- Done: the Blender-modelled deck (S-shaped tonearm, counterweight, strobe dots and lamp, pitch fader, 45 adapter), the dark theme, platter spin, tonearm drag, physical start/stop, previous and next buttons (the real deck's two speed buttons). Keys: space, left, right. Render: `docs/m2-turntable.png`.
- Checked: 16 unit tests pass (`scripts/test.sh`); offscreen renders at rest, playing and at 800 × 500.
- Not checked: dragging with a real pointer, live resizing and 60 fps (criteria 13 and 14). Amit runs `scripts/dev-build.sh`, then opens `build/dev/RecordPlayer.app`.
- Not checked: the Xcode project build. `xcodebuild` fails on this Mac until Amit runs `sudo xcodebuild -runFirstLaunch`. Until then `scripts/dev-build.sh` builds with the Swift compiler alone.
- Previous and next jump between placeholder track bands until music is wired in (M3).

## Review
(Filled when the last milestone is done.)
