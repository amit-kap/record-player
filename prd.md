# record-player: product brief

## User and problem
AMIT SAYS: a desktop music player connected to your Apple Music sub. The entire app is a top-view 3D record player the user controls: load a new record, play, stop and more.

Users: Amit and a few friends, each on their own Mac with their own Apple Music subscription.

## First-version outcome
A Mac app where you pick an album or playlist from Apple Music, it drops onto a 3D turntable, and you play it by dragging the tonearm or pressing buttons.

## Main flow
1. Open the app. On first run, allow access to Apple Music.
2. See the turntable from above, with an empty platter.
3. Open the record picker: your library shelf, or search the Apple Music catalog.
4. Pick an album or playlist. The record drops onto the platter with its artwork on the label.
5. Drag the tonearm onto the record, or press play. The platter spins up and music starts.
6. The tonearm moves inward as the record plays. Drag it to another track band to jump there.
7. Use prev, play/pause and next, or lift the tonearm to stop.
8. Pick another record. The old one lifts off and the new one drops on.

## Included
- macOS only, native Swift, one resizable window that also goes full screen.
- Apple Music sign-in and playback of full tracks.
- A record is an album or a playlist.
- Record picker: library albums and playlists, plus catalog search.
- Real-time 3D turntable that mimics a real record player, top view, built in code: plinth, platter with strobe dots, record, label, tonearm, buttons, status light.
- Artwork on the record label.
- Tonearm: drag to play, drag to seek between tracks, lift to stop. It tracks playback progress.
- Buttons: start/stop, previous and next, as physical buttons on the plinth like a real record player. Keyboard: space, left and right arrows, and the Mac media keys.
- Track title, album, artist and elapsed time.
- Platter spin-up and slow-down on play and stop.
- Record change animation.
- Dark theme, like the reference image.
- A signed and notarized build friends can open.

## Excluded
- Windows, browser and iOS versions.
- Mini player and menu bar item.
- Songs and radio stations as records.
- Editing playlists or the library.
- Mac App Store release.

## Later
- More themes (warm hi-fi, light minimal) with a theme switch.
- Needle-drop and crackle sounds.
- Dragging the record to scrub.
- A more detailed turntable model.

## Acceptance criteria
1. **Sign-in:** on first run the app asks for Apple Music access; after allowing it, the picker shows library content.
2. **Playback:** a full track from an Apple Music subscription plays to the end, not a 30-second preview.
3. **Library:** the picker lists library albums and playlists with artwork.
4. **Search:** typing a query returns catalog albums and playlists within 2 seconds on a normal connection.
5. **Load:** picking a record puts it on the platter with its artwork on the label.
6. **Tonearm play:** dropping the tonearm on the record starts playback; lifting it off stops playback.
7. **Tonearm seek:** dropping the tonearm on track band N starts track N.
8. **Progress:** the tonearm position matches the elapsed share of the record to within one track band.
9. **Buttons and keys:** prev, play/pause and next work from the buttons, the keyboard and the media keys.
10. **Track info:** title, album, artist and elapsed time update within 1 second of a track change.
11. **Spin:** the platter spins only while music plays, and eases in and out.
12. **Record change:** loading a new record animates the old one off and the new one on, and stops the old audio.
13. **Window:** the turntable stays fully visible and centred at any window size down to 800 × 500.
14. **Frame rate:** the scene holds 60 fps on Amit's Mac while playing.
15. **Friends' build:** the app opens on another Mac with no Gatekeeper warning.
16. **Empty states:** an empty platter invites picking a record; an empty library points to search; a search with no results says so.
17. **Error states:** no subscription, access denied and offline each show one plain message and a way to retry.

## Budget and success test
Budget: 4 weeks (default; Amit has not stated one).

Success test: after two weeks of use, Amit still opens record-player instead of the Music app to play an album, and at least one friend has installed it.

## Open
- OPEN: minimum macOS version. The plan assumes macOS 15. Friends on older versions could not run it.
- OPEN: app name and icon for the build friends receive.
