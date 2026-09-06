# Effy production atlas v1

This atlas preserves the approved character identity and has a transparent checkerboard-rendered background. It is a visual motion/reference atlas, not yet wired into Swift.

Rows, top to bottom:

1. Idle
2. Blink
3. Click / boop
4. Thinking
5. Replying
6. Answer started
7. Answer complete
8. Error

Important review note: the generated atlas has a consistent visual character but does not yet provide deterministic equal-size frame cells and machine-readable frame metadata. Do not ship it directly as runtime sprites until each frame is manually/algorithmically cropped into fixed 512×512 transparent canvases with a shared bottom-center anchor.
