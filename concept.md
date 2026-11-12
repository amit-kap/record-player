---
name: record-player
status: develop
track: personal
platform: macOS
interest:
next: "Amit: enroll in the Apple Developer Program, answer the two OPEN items in prd.md, then say start M1"
repo:
updated: 2026-11-11
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
