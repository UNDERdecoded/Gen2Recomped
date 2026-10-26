# Owned field-effect artwork

`src.core.game3.field_effects` now supplies the resource part of the compatible
field-effect interface: `install`, `manifest`, `manifestObject`, `loadSheet`
(`getSpriteSheet`), `invalidate`, `release` and owner cancellation. It does not
implement effect tasks, timers, start/wait commands, actor lists, reflections
or draw phases. No empty task observations or additional simulation are used
to imply that those contracts have been completed.

The native catalogue uses identified imported tall-grass, surf-blob, ripple,
sparkle, FRLG bird and independent emote-strip records when present. It does
not claim that every edition imports each record. Each record's own geometry
and frame order remain authoritative. Independent native emote strips are
not renamed into a presumed combined fifteen-frame strip. Additional artwork
and the native effect phase/state bridge remain required.

A loaded sheet owns its ImageData, Image, full-frame quads and eight-pixel
front crops. Neither Assets' image cache nor an actor SpriteRenderer is lent.
Repeated requests share these owned resources with per-mod leases. Retirement
uses a private allocation list: replacing public sheet fields cannot cause a
borrowed image to be released. Actual generated-asset overrides are resolved
at each request; changed paths/geometry retire the preceding owned sheet.

An explicitly installed cache may provide the original `field_effects/objects.lua`
and raw RGBA payloads through its own `read` method. No conversion file is
written. Manifests run with an empty environment and bounded instructions,
then validate scalar/table metadata, finite geometry, names, paths and duplicate
identities. Payload length must exactly match the declared geometry. An authored
manifest remains authoritative; a missing/malformed declared asset is not
silently substituted with unrelated native artwork. Public manifest results
are detached copies; ordinary cached sheet requests avoid copying the manifest.

Providers bind to the current game/dataset/save/mod-set/edition cohort.
Replacement, failed-entry rollback, late validation rejection, asset flushes
and teardown retire owned allocations. Reentrant cache reads revalidate the
cohort before publication. Preparation failures release partial allocations
and allow a later retry. There is a bounded texture-memory budget; exhausting
it reports an unavailable resource instead of returning a partial sheet.

Validation uses synthetic, asymmetric pixel fixtures for all five GBA editions,
actual SDK owner rollback/teardown and real Metal/OpenGL image/frame/crop
readbacks. These are resource tests, not original effect-task parity, cartridge
artwork extraction parity, unchanged package initialization, gameplay, full
renderer or complete mod-coexistence acceptance.
