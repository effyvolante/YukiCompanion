# Companion theme assets

These transparent RGBA frames are derived from the supplied animation master
sheets. Each theme uses the same eight-frame rows and the existing companion
canvas/scale conventions. Filenames are prefixed by the theme id so SwiftPM
can embed the resource bundle without flattening collisions.

- `Idle` — idle loop and blink fallback
- `Click` — click/boop
- `Thinking` — thinking
- `Replying` — replying
- `AnswerStart` — answer start
- `AnswerComplete` — answer complete
- `Error` — error
- `Look` — hover/notice and look/capture
- `RareIdle` — rare idle A; the runtime plays this row in reverse for rare idle B

Review-sheet labels, borders, row lines, and backgrounds are not runtime
content.
