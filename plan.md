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
5. **The notarized build may not play music on a friend's Mac.** Earliest test: M8 starts with one build sent to one friend before any polish.

## Milestones
1. **Playback test (2 days).** Bare window: sign in, load one album, play, pause, skip, show artwork.
   Verified by: criteria 1 and 2; risks 1 and 2 answered. **Needs the Apple Developer membership.**
2. **Turntable scene (4 days).** Plinth, platter, record, label and tonearm in the dark theme; platter spins; tonearm drags. No music yet.
   Verified by: criteria 13 and 14; Amit approves the look against the reference.
3. **Turntable plays music (4 days).** Scene wired to the player: tonearm play, stop and seek, progress tracking, spin-up, buttons, keys, track info.
   Verified by: criteria 6 to 11.
4. **Camera views and a model-ready deck (4 days).** Three views (top, 45-degree side, tonearm close-up) with a smooth switch; tonearm and buttons work in every view; everything specific to the deck moves into one description.
   Verified by: criteria 18 and 19.
5. **HUD and song artwork (3 days).** A HUD the user shows or hides, with the current song and playback controls; the label shows each song's album cover.
   Verified by: criteria 10, 20 and 21.
6. **Record picker (4 days).** Library shelf and catalog search for albums and playlists; picking one loads it.
   Verified by: criteria 3, 4, 5 and 16.
7. **Record change and states (3 days).** Record change animation, last record restored on launch, error states.
   Verified by: criteria 12 and 17.
8. **Friends' build (3 days).** Signing, notarization, a DMG, app name and icon, one friend install, fixes.
   Verified by: criterion 15, and a friend plays an album.

Total: 27 working days. Milestones 4 and 5 were added on 2026-11-13, when Amit made views, the HUD and song artwork mandatory for the first version.

## Delivery
- **Setup:** Amit enrolls in the Apple Developer Program ($99/year), then enables the MusicKit service for the app's bundle ID. I walk through this at the start of M1.
- **Access:** each user needs their own Apple Music subscription and allows access on first run.
- **Deployment:** a Developer ID signed and notarized DMG, sent to friends directly. No App Store.
- **Running costs:** the $99/year membership. No server.
- **Repo:** local git on `main`. A GitHub repo is created when Amit asks; its link goes in `repo:` in `concept.md`.

## Status
Current milestone: M5, built, waiting for Amit's hands-on check (2026-11-15). M4 is built and also waits for his hands-on check (2026-11-13). M3 was tried by Amit and adjusted (stop returns the arm home, calmer strobe dots). M1 is not started and is blocked on the Apple Developer membership.

M5 so far (built by Sonnet and Opus agents, each task reviewed and re-run by the supervising session; not committed):
- Done: every track carries its album and its cover (`Artwork`: an id and an image that loads when asked, so Apple Music covers fit later). The model gives the current song's cover.
- Test record: the three MP3s have no album tag and no embedded cover, so each gets a generated cover in its own colour with the title on it.
- Done: the label shows the current song's cover, cropped to the disc, with a 0.3-second crossfade. Covers for the current, next and previous tracks are built ahead of time. Renders: `docs/m5-label-top.png`, `docs/m5-label-side.png`, `docs/m5-label-tonearm.png`.
- Label glow: the old glow added a flat grey that washed covers out. It is now an unlit copy of the label over the lit one, so colours stay true. The placeholder label is slightly darker than before.
- Done: the HUD, one floating panel at the bottom: cover, title, artist and album, elapsed and length, previous, play/pause, next, and a Top / Side / Tonearm switch. It replaces the old track line. Screenshots: `docs/m5-hud.png`, `docs/m5-hud-800x500.png`, `docs/m5-hud-hidden.png`.
- Show and hide: key H, the panel's chevron, or a small round button in the bottom-right corner while hidden (it fades when the pointer rests). The choice is remembered.
- While the HUD shows, the deck zooms out a little and moves up, so the panel never covers the plinth, even at 800 × 500. The deck and the panel move together in 0.3 seconds.
- Debug flags: `--hud` and `--no-hud` for one launch; `--snapshot` takes `--track N`.
- Checked: 39 unit tests pass; the playback check passes and now exits non-zero on failure. Label swap after a track change: 0.32 to 0.38 seconds over 13 runs (limit 1 second). A cover never seen before: 0.43 to 0.74 seconds.
- Checked: HUD at 1280 × 800 and 800 × 500, shown and hidden; show/hide and a view change measured from screen recordings.
- Sent back during review: two test covers had the same colour; the first cover of a record was too close to the 1-second limit; the panel was not animating and the debug flags overwrote the saved choice.
- Not checked: clicking the HUD buttons and dragging the tonearm with a real pointer while the HUD shows; the corner button's fade; VoiceOver and Reduce Motion; 60 fps during a label swap; the Xcode project build.
- Open risk for M1: an Apple Music cover comes over the network. The next track's cover is fetched ahead, but the first cover of a newly picked record may take longer than 1 second on a slow connection.

M4 so far:
- Done: three camera views with a 0.9-second glide between them; keys 1, 2 and 3 switch. Renders: `docs/m4-side.png`, `docs/m4-tonearm.png`.
- Side view matches `ref/AT-LP140XP/side-view.png`: 45 degrees up, 25 degrees to the right (Amit's reference, 2026-11-13).
- Tonearm view is a close-up after `ref/AT-LP140XP/tonearm.png` that rides with the headshell, so the needle stays centre frame while it plays. It has a depth-of-field blur: the headshell is sharp, the label and the near edge are soft.
- The blur uses RealityKit's custom post-processing, which needs macOS 26. On macOS 15 the view works without the blur. It is not in the command-line renders, only in the running app.
- Done: the tonearm and buttons are read through whichever camera is showing, so they work in every view.
- Done: everything specific to the deck (model file, layout, button positions, part names, heights, camera views) is one value, `TurntableSpec`. To add a deck: script it in `Models/`, export a `.usdz`, add one spec to `TurntableSpec.all`.
- Camera adjust panel: press A for sliders on the view being shown (side, height, roll, zoom, shift, blur). Save keeps the pose on this Mac; Reset returns to the deck's own. Saved poses are read back with `defaults read com.amitka.recordplayer.dev`. Screenshot: `docs/m4-adjust-panel.png`.
- Feet: four large round feet under the plinth corners, as in the reference, and the floor sits under them. The model already had small feet, hidden because the floor cut through the plinth.
- Lighting: one key lamp, a spot from the front left that throws the shadows and lights a pool on the floor, with a weak overhead fill and a dimmer room reflection. The streak on the record lies along the line to the lamp. Render: `docs/m4-top.png`.
- Fixed: the blur was rebuilding its shader every frame, which stalled the app; it is now built once.
- Checked: 34 unit tests pass, including camera math against the old top-down maths; renders of all three views; a live view change in the running app; the muted playback check still passes.
- Not checked: dragging the tonearm with a real pointer in the side and tonearm views, how the glide and the following camera feel in motion, and 60 fps with the blur on.
- Not done: a visible control to switch views (it comes with the HUD in M5) and a control to switch decks (Later).

M3 so far:
- Done: a player interface (`RecordPlayback`) with a local-file player behind it; tonearm play, stop and seek; the arm follows the music inward; start/stop, previous and next; space, arrows and media keys; one line of track info under the deck; the arm returns to rest when the record ends. Screenshot: `docs/m3-playing.png`.
- Test record: debug builds bundle the three MP3s in `ref/royality-free-music/` (`scripts/dev-build.sh`). They are not in the Xcode build or the friends' build.
- The start/stop button lifts the needle and sends the arm home (Amit's call, 2026-11-12). Space and the media play/pause key pause in place and resume. With the arm at rest, both play from the first groove.
- The needle plays from exactly where it lands, so dropping it mid-band starts mid-track.
- The strobe dots turn with the platter while it spins up and settle to a standstill at 33⅓ rpm, as under a real strobe lamp. The platter speed itself is the real 33.3 rpm (measured in the running app).
- Previous restarts the track after 3 seconds, otherwise goes to the one before.
- Checked: 26 unit tests pass (`scripts/test.sh`); a muted headless run (`RecordPlayer --playback-check`) covers play, next, previous, stop/start, tonearm seek and the end of the record; the arm stays within 0.001 of the music's position.
- Not checked: how it sounds, dragging with a real pointer, the media keys, and 60 fps while playing. Amit runs `scripts/dev-build.sh`, then opens `build/dev/RecordPlayer.app`.
- Not checked: the Xcode project build (`sudo xcodebuild -runFirstLaunch` is still needed).
- Left for M1: an Apple Music player behind the same interface. Left for M5: artwork on the label.

## Review
(Filled when the last milestone is done.)
