# Fit native opening effects to a source send-out

A source renderer can fit a send-out ball through its existing
`Ui.presentation.ballPosition` callback. Its cell then follows the scene,
while the borrowed native opening ring previously remained in cartridge
screen coordinates, producing oversized particles away from the opening.

For a standalone send-out opening pass, borrow that same current callback
and map the actual native effect origin/size to its returned position/scale.
Use the existing native ring, shiny and star painters; no private renderer,
new particle timeline or native controller is introduced. Zero scale hides
the opening with its cell; an absent projection retains native geometry.
Reject nonfinite geometry or an admission changed by the callback. The
existing graphics guard restores caller state even after a provider error.

Capture providers already transform their whole opening pass, so capture
does not borrow this projection again. Base calls inside the native whole-ball
boundary retain its complete native painter. Unmodified presentation remains
native, and no projected observation feeds back into native drawing.

Validation:

- Focused `8191e50543`: 16 groups pass, including 460 native effect/projection
  checks across five GBA editions and player/opponent/capture balls.
- Frozen `5fe451e231` on fork main `72c2a946`: 198 CPU groups pass. The later
  fixture-only diagnostic correction adds error descriptions; production
  hashes and positive assertions are unchanged.
- Exact predecessor `85b7ae61`, `ed19cde0c3`: 240 failures out of 450 checks.
  The ten callback-local checks are absent because the predecessor never
  invokes the provider. The earlier negative run hit a missing fixture error
  description after detecting wrong geometry; its receipt is retained.
- Older-public composition `4402bdd757`: 74 groups pass, including all 460
  projection assertions, with its existing native controllers retained.
- Real Metal Ruby `3fec7460ac`, unchanged consumer `bddb5181`, imported TIANA
  portrait 2: all 189 observed opening-particle draws have the current fitted
  ball centre (maximum framebuffer error `0.00000763` pixels). The frame at
  opponent presentation tick 62 now shows the ring at the actual ball rather
  than outside the scene. Both native send-outs, 11 captured throw images,
  the command menu and cleanup pass without loader errors. The 553 pre-player-
  throw observations and 82 ball-hidden observations retain zero visibility
  violations. There are zero duplicate cells in 378 opening passes.
  All views/portraits, capture image acceptance and stable frame rates remain
  separate. Hosted CI is separate too.

Owned QA profiles/copies only, with a 20 GiB free floor. Private sources,
original ROMs and player saves/profiles are unchanged.
