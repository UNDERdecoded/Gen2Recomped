# Native GSC picture-command ownership

The shared native controller resolves a move before its queued animation runs.
Changing the sprite at that earlier point exposed Transform's copied Pokemon
and Substitute's doll before the ROM command. The existing renderer also read
`substituteHP` despite an explicit `dropsub` override, and ignored Beat Up's
temporary species image.

`Gen2PicturePresentation` holds only presentation identity. A pin belongs to the
actual battler, saved Pokemon and queued row, then to the actual GSC runner.
Native stats, moves, HP, PP and turn resolution retain their existing owners.
The native queue retires each pin at the real image opcode or completion; no
additional update clock, combat model or authored ROM program is introduced.
Missing, disabled and cancelled animations reconcile immediately. Repeated
transforms commit in queue order; a replaced slot cannot inherit an old pin.
Transformed front animations get their own native entrance runner.

Both the native picture layer and the existing source-facing captures use the
selected native image. Placement and image-specific scale metadata are measured
from that same selected image. An explicit false override hides the doll while
preserving its combat HP. A newly created substitute appears at `raisesub`.
The imported Beat Up parameter selects a species index, rather than a party
slot; the existing VM's public `slot` field is retained. Its catalog lookup is
cached for a stable override and catalog.

The picture tests exercise Gold, Silver, Crystal, Prism and Polished Crystal;
the emitted-image comparison covers both sides in the three retail editions.
They run the real native effects, queue and GSC interpreter. Only device draw
calls are recorded. The pixel suite is also runnable against the previous
engine without adding the new helper, so its failures are wrong emitted
images rather than missing modules. CI runs these tests alongside the existing
object and background owner tests.

The upstream controller has no source-facing `pic`/`drawPic` boundary yet.
Its tests therefore exercise the native picture layer; optional public-capture
assertions run on the fork where that boundary already exists. The upstream
adaptation uses its existing inline queue admission, not a copied fork queue.

The follow-up [native picture-art implementation](native-gen2-picture-art.md)
adds Minimize/Substitute ROM art, GSC placement/palette/resize composition and
Crystal's staged actor copy. Full per-hit Beat Up combat sequencing, battler-row
OAM drawing, send-out events, natural-move GPU comparisons, Windows and packaged
release validation remain separate work. No supplied mod, protected instance,
ROM or player save is changed. No new release is implied by these CPU tests.
