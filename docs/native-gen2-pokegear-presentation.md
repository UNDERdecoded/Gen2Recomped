# Native Pokegear state and window-resolution presentation

Actual unchanged Johto GPU inspection found a mismatch that the native
radio command/input assertions alone did not detect. The native card was
RADIO, but a source renderer asked for `card()` (or its legacy cursor),
fell back to CLOCK and painted the wrong panel. It also received the small
cartridge canvas rather than a window-resolution drawing boundary.

The native Pokegear now exposes `card()`, `cardLabel()`, `stations()` and
`currentStation()` over its existing native selection and tuner. Station
rows carry the real native identity and knob-derived frequency. Its `radio`
view follows native program text advancement and retuning; leaving or closing
the card clears that view. This is presentation of the existing native
program text, not the complete cartridge show or song state machine.

`drawsWidescreen()` / `drawWidescreen(width, height)` are an optional
screen-space drawing boundary. A replacement of the Pokegear's fallback
drawer opts into it; the unmodified native menu retains its original canvas.
The normal world/compositor runs first. Only the selected wide owner's small
UI drawing is omitted; native overlays above it remain on their own existing
canvas and are composited after the high-resolution owner. This works even
when a mod's `render.compose` hook owns the ordinary world composite.
Graphics state is restored around the window drawer and overlay.

Focused synthetic tests cover native card navigation, retuning, text
advancement, borrowed-record isolation, ordinary no-mod behavior, window
owner selection, overlay ordering and graphics-state isolation. Real
unchanged-mod GPU acceptance of this correction is still pending.

The earlier exact `e435f5ff` package passed 36 automatic checks per OpenGL
and Metal backend with actual Crystal and the unchanged Johto package.
All eight fresh OS images were inspected. Wall-radio names were upright,
but the four Pokegear images showed CLOCK instead of RADIO, so that set was
rejected as complete radio visual acceptance and was not published. Metal
deprecation overlays also remain visible at the lower edge.

Full radio shows/audio, source phone/map facade completion, ordinary story
admission and Windows/Intel hardware GPU gameplay remain open. In particular,
the pre-existing native Snorlax special checks only EXPN; a real native VM
probe incorrectly returns true without flute music or adjacency. That story
gate requires a separate audio/ownership correction and is not fixed here.

This standalone upstream composition has not received unchanged-mod GPU acceptance.
Original contributions by Roxas2712 are offered under the specific permission in
[LICENSE-ROXAS2712.md](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md). Existing project and third-party rights remain effective.
