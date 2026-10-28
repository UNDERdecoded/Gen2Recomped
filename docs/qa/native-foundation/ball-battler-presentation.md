# Native battler observations during send-out

The source presentation view previously reported a visible, full-size Pokemon
while its actual native ball still owned an empty slot. It also omitted the
native rise offset. A fitted presentation could consequently show a Pokemon
before its throw or opening, then restart its appearance.

Observe the existing native ball's `monHidden`, `monScale` and `monRise` for
that ball's battler only. Compose its scale/rise with existing native move
effects. Before a ball exists, observe the native trainer/send-out hiding
flags as well; the opposite slot remains independent. Additional double-battle
slots use the existing native side-arrival query. Explicit source overrides
retain their established precedence. Native draw overrides still use only
explicit overrides, so these observations cannot feed native scale back into
itself. No native controller, command queue or animation clock is changed.

Validation so far:

- Exact predecessor `4e807b6d`, run `7237c0a31e`: the same fixture reports
  4,075 failures out of 23,160 assertions. No new controller is overlaid.
- Older-public composition `0b63737b6a`: 73 groups pass, including all
  23,160 visibility/scale/rise assertions across five GBA editions and
  player/opponent/capture balls. Existing native bodies remain in place.
- Frozen `2ad0e77282` includes fetched fork main `72c2a946` and the entry
  visibility correction: 197 CPU groups pass, including all 23,160 assertions
  above and the new main's font, alpha-depth, effects, checkpoint and waterfall
  regressions. Native Gen2 regressions remain included.
- Real Metal Ruby `611cb4757b`, unchanged consumer `bddb5181`, imported TIANA
  portrait 2: 595 battler observations, including 553 before the accepted
  player send-out with zero premature visible player rows. All 82 observed
  ball-hidden rows hide their actual actor. Both native send-outs are admitted;
  108 native clock samples, 76 visible fitted ball rows and 11 captured throw
  images are retained. The command menu and cleanup complete without loader
  errors; 378 opening-effect passes contain zero duplicate native ball cells.
  Images at enemy frames 32/62 and player frames 0/20 confirm empty slots
  before release and actual opening emergence. Opening particles still need
  fitting to the source scene; this is not complete scene, all-portrait/view
  or stable frame-rate acceptance. Hosted CI remains separate.

QA uses owned profiles and preserved disposable copies with a 20 GiB free
floor. Private consumer sources, ROM originals and player saves are unchanged.
