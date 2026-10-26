# Native GBA battle source boundary

This is an incremental presentation and observation bridge over the existing
`BattleState`. It does not establish complete unchanged-package boot or play.

## Implemented boundaries

- The admitted native stack owns battle identity, input, combat, RNG and exit.
- Stable source observations translate cartridge species/move/item/ability/type
  identifiers and flattened Pokemon fields. Trainer class and trainer id remain
  different fields. HP/status changes and PP transactions reach native Pokemon;
  unsupported move replacements fail before an update.
- Native start notifications, update, UI pump, whole-screen drawing and the
  background pass have independent scopes. Repeated base calls consume each
  native body once. Calls outside an update scope cannot tick combat.
- Every queued native update/draw rechecks the original admission after source
  hooks, including the inner UI/background hooks. Save, dataset, loader, stack,
  edition and imported catalogue replacement retire the old binding; restoring
  an earlier pointer cannot revive that binding. Native method bodies execute
  outside a source callback owner.
- Explicit battle/UI captures suppress the repeated native screen draw within
  the same renderer frame and render target. A separate preview target cannot
  suppress the main screen. Capturing never advances combat.
- LuaJIT `pairs`/`next` expose typed battle fields, preserving nested typed
  identity. Iterator registry values are weak, so an unused observation cannot
  retain its own weak key through a closure.
- Covered battles remain observable, but cannot update or pop their cover.
  Mod retirement invalidates its source views without cancelling native combat.
  Completed views keep detached observations and reject further native writes.
- Basic source wild/trainer requests reuse the native encounter admission and
  cleanup provider when present. Authored source parties, extended options,
  headless simulation and source-controlled link termination remain unsupported.
  Constructor-request acceptance is not yet independently qualified here.
- Pokemon observations use native imported records. Height and weight convert
  metres/kilograms to cartridge decimetres/hectograms. Static pictures are owned
  by the source service; native animation frames remain borrowed.
- Separate presentation players reuse native `MonAnim`/`PicAnim` timing. Their
  timing is the existing native implementation, not a proof of exact source
  sprite callbacks. They cannot consume combat commands.

Older native controllers without HUD visibility or move-grid query methods
return an explicit unavailable reason for those observations. This does not
advertise the complete presentation protocol on that host.

## Qualification

The focused engine suites cover all five registered GBA editions using
synthetic imported data and actual native constructors, stack admissions and
exit. They exercise repeated base calls, covered states, UI input/draw scopes,
owner/data/edition retirement, numeric identity, PP and detached final views.
View-only collection checks isolate this bridge from the host's global facade
cache; they do not certify the entire host's Game/save collection policy.

`tools/battle-source-runtime/host` draws the actual native `Gen3Battle` on a
GPU. It compares default and wrapped pixels, replaces only the field pass,
checks that the native command-area pixels remain identical, and checks
graphics restoration after a failing callback. Artwork and battle records are
synthetic; these are not original-package or cartridge gameplay checks.

## Remaining presentation work

The UI module deliberately does not advertise the complete sprite/particle
presentation protocol. Native animation VM, effect, healthbox, trainer, ball,
text, catch, switch and intro presentation interfaces still need their own
bindings. So do complete party/save collection schemas and authored source
Pokemon operations. Original-package initialization, real play sequences,
source effect timing/art parity and physical target acceptance remain open.

The last unchanged-package loader probe advances beyond battle, Pokemon,
motion and UI imports to the missing `src.core.game3.battle.anim` interface.

Older native hosts also retire already-loaded battle, Pokemon-picture and
motion services at loader unwind, even when their stream service is not yet
driven by loader retirement. This releases observations and owned pictures;
it does not pop or finish the actual native battle.
