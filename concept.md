---
name: record-player
status: develop
track: personal
platform: macOS
interest:
next: "Amit: set view 3 with the adjust panel (key A) and save; then M5: HUD and song artwork"
repo:
updated: 2026-11-15
---

# record-player

> a desktop music player connected to your apple music sub.

## About
a desktop music player connected to your apple music sub. The entire app is a top view 3d record player that user can control it load a new record, play, stop and other stuff

## Vision
AMIT SAYS (answers on 2026-11-11):
- macOS only, for me and a few friends.
- A record is an album or a playlist, picked from my library or by search.
- Real-time 3D turntable, built in code.
- Physical controls plus buttons: the tonearm is draggable, with prev, play/pause and next.
- One resizable window.
- Switchable themes; dark, like the reference, comes first.

## Decisions
- 2026-11-11: Amit asked for a build plan directly, so the idea starts at develop with no research. Budget: 20 working days (the 4-week default; Amit has not stated one).
- 2026-11-11: Stack is native Swift with MusicKit. Amit will get an Apple Developer membership.
- 2026-11-11: Amit had no preference on vinyl touches. First version includes tonearm progress, spin-up and the record change animation; sounds and scrubbing are Later.
- 2026-11-12: AMIT SAYS: "must have controls" and "i want to mimic a real record player". Controls are physical buttons on the plinth, not flat on-screen buttons. Real-turntable details (strobe dots, status light) are in.
- 2026-11-12: AMIT SAYS: "i expictly asked for 3d model". The code-built primitives are replaced by a real 3D model scripted in Blender, after his reference: https://www.audio-technica.com/en-us/turntables/best-for/dj/at-lp140xp. No branding on the model.
- 2026-11-12: Model reworked against all images in ref/AT-LP140XP: controls moved in from the edges, pitch slider, tonearm and round strobe dots matched to the reference. Drift: none
- 2026-11-12: Amit approved the M2 look after a tighter zoom and a lower key light. M3 started before M1: Amit supplied three royalty-free MP3s as a local test record, so the turntable plays music without the Apple Developer membership. Apple Music plugs in behind the same player interface in M1.
- 2026-11-12: AMIT SAYS: "why on stop the tonearm dont return to home?" The start/stop button now returns the arm home; space and the media key pause in place.
- 2026-11-13: AMIT SAYS (FYI): the user can switch between 3 to 4 camera views (top, side 45 degrees, tonearm close-up); switch between 3 to 4 record player models (Amit provides the list); toggle a HUD with the playing music and playback controls; and the label shows each song's album cover. Added to `prd.md`. Rough extra work: views 3 days, HUD 2 days, song artwork 1 day, each extra model 3 to 4 days (ASSUMPTION, from the time the first model took). That is over the 20-day budget; milestones are not re-planned until Amit decides.
- 2026-11-13: AMIT SAYS: "i'll provide the models list later - for now carry on with this single one but prepare the code for this feature - all other request are mandatory for R1". Views, the HUD and song artwork join the first version; model switching moves to Later with the code prepared for it. Budget grows from 20 to 27 working days. The tonearm will be draggable in every view. Drift: the app is no longer top-view only.
- 2026-11-13: AMIT SAYS: the side view is `ref/AT-LP140XP/side-view.png`; the third view is a close-up on the tonearm tip that keeps it centre frame while playing, with a depth-of-field blur if possible. Both done; the blur needs macOS 26.
- 2026-11-13: AMIT SAYS: view 3 still needs adjusting; add the base stands from `side-view.png`; the lighting "feels unclear - i would like to see a more primary prominant source that affects the scence". Added a camera adjust panel (key A) so Amit sets the views himself, larger feet, and one key lamp from the front left with shadows.
- 2026-11-15: Amit approved the key-lamp lighting ("Yes, keep it").
