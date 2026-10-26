# Imported field-move presentation on the native state

This extends the native `Gen3FieldMove` admission with a cartridge presentation program. The normal native style remains the default when there is no active compatible observer. Existing native sprite hooks and asset overrides still resolve the front picture. No second world, player or task clock is created.

The compatible field-move namespace exposes `start`, `isActive`, `step`, `draw`, `reset` and `invalidate`. Entry configures an actual stack state. Only that state's native update advances the presentation. Wrapped base calls share a once-only phase; an arbitrary `step()` cannot drive another frame. Read-only `_fx` observations are detached from the actual state. Rendering an effect through the source world pass suppresses the same admission's native UI draw within the renderer's frame serial.

The optional program uses separate indoor and outdoor 256×80 strips, a 24-tick optional pose, cartridge-style window reveal/hide, picture motion/hold and one cry. `noDuck` and per-call cry volume feed the existing audio engine; the next ordinary cry restores its normal volume. An unrelated active cry retains ownership of its music attenuation.

## Imported data and ownership

The existing field-effects import stage authenticates the actual complete ROM SHA-1 before extracting strips. Bounds and declared tile counts are checked. The compact cache contains indices and palette words; RGBA is expanded only on admission. An older manifest can use the audited exact-digest profile, while discovery writes explicit optional `fieldMoveStreaks` metadata. Unknown revisions decline this artifact. The GBA-only cache revision forces an import refresh without migrating player data.

Profiles cover FireRed, LeafGreen, Emerald, Ruby and Sapphire. Source locations and presentation facts were checked against the corresponding primary cartridge projects: [FireRed](https://github.com/pret/pokefirered/blob/master/src/field_effect.c), [Emerald](https://github.com/pret/pokeemerald/blob/master/src/field_effect.c), [Ruby/Sapphire](https://github.com/pret/pokeruby/blob/master/src/field_effect.c). No cartridge payloads are bundled.

A mounted field-art provider can supply the same raw strips directly. Missing or malformed declared provider data fails admission; it cannot silently select another provider. Front images, strips, image data and quads are privately tracked per admission, including failed preparation and reload. Changing a public sprite field never transfers ownership of a borrowed native image. Pose ownership uses an admission token, so an old admission cannot restore over a newer pose.

Callbacks and states belong to the current game/data/save/mod-set/edition/stack/world. A covered state cannot complete another screen. Source-owner cancellation removes only its own admission, including behind another screen, and discards captured continuations. Observer teardown preserves native continuations. Duplicate, early, reentrant and failed continuations retain their guards.

## Validation and remaining scope

ROM-free checks exercise admission, wrappers, cohort changes, resource ownership, actual SDK entry/late-validation/teardown, and the existing music/cry engines. Independent private oracles use immutable original blobs for per-tick state comparison and separately decode both strips from all five ROMs. The GPU host compares the original drawing routine against the native program on Metal/OpenGL, including repeated and externally composed draws. Front artwork in that host is an asymmetric synthetic fixture; it does **not** prove every cartridge portrait, form or personality variant.

Full special-form/personality picture handling, native field-effect tasks and actor/overlay scheduling, party-slot selection, the unchanged complete renderer and real full-package gameplay are still separate acceptance work. A loadable module or matching cut-in is not full mod compatibility.
