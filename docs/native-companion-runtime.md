# Native companion runtime

Source consumers on FireRed, LeafGreen, Emerald, Ruby and Sapphire can use
native party residents, encounter admission, field phases and modal screens.
The adapters do not load another game engine or copy an application save.

## Native ownership

- Session party members are typed views with cartridge-numbered identifiers.
  HP, status, friendship, nickname and held items write to their admitted
  resident. Move IDs and maximum PP are read-only; PP edits are validated
  together before committing. Retired views reject writes.
- Bag handles use native pocket/capacity rules. Capacity queries run against
  detached inventory containers; negative quantities cannot remove items.
  Dex and Safari queries inspect the admitted native session.
- Authored wild encounters validate species, level, personality, six IVs,
  moves/PP, item, HP and status before construction. Native encounter
  admission retains its healthy-party, busy-world and single-pending-request
  guards. Native cleanup runs even after the requester is unloaded; its
  continuation runs at most once. Roaming identity and wounds remain native.
- Field locks belong to a mod and tag. Interactions, follower updates and
  party-menu wrappers consume their native phase once. Short player gestures
  advance on the player's fixed step and respect the native pose owner.
- Draw-only actors join native sorting temporarily. They do not become NPCs,
  collision objects or independently updated entities. Rendering errors restore
  the original entity collection. Follower artwork can use an owned renderer.
- Dialogue uses the native TextBox printer. Choice, evolution and move-reminder
  screens use the native StateStack. A UI flow owns its child screens across
  pop/push continuations; retirement removes those screens and discards its
  callback without removing an explicitly foreign overlay.
- EXP awards share native growth, stats and level-up events. Damage queries
  use the native formula/ruleset. Imported moves, item effects, fonts, sounds
  and cries remain native resources. Nested two-tone text restores both the
  shader binding and the outer ink/shadow uniforms.

Optional conveniences attach through an owned option provider. Timed outdoor
encounters reorder existing land entries while preserving native position
weights and rates. Ball shortcuts use idle command admission and the ordinary
bag/catch transaction. Repel reuse asks before consuming another item.
Summary details cycle native stats, IVs and EVs without changing the Pokemon.
Disabling the owner disables these options.

## Qualification and remaining work

ROM-free fixtures exercise all five editions, including encounter identity,
PP validation, lock isolation, native menu navigation, evolution cancellation
and completion, free-slot learning, and unloading a full-moveset reminder.
Run `luajit tests/engine/native_companion_runtime.lua`, the engine tier and
SDK tier. The companion GPU host additionally checks real text pixels and
nested native shader uniforms on Metal and OpenGL; it extends the native
battle orientation/effect oracle.

The local unchanged 1.0.9 package now passes its companion-member probe.
Initialization subsequently requires additional battle/UI presentation
modules, beginning with `src.ui.game3.battle_chrome`. This change does not
advertise the complete battle presentation protocol or claim that the whole
package is playable. Effect-specific field combat, additional UI contracts,
full package graphics and end-to-end gameplay require further qualification.

Local test starters use managed frozen candidates and disposable profiles,
retain an 8 GiB free-space reserve, and do not read or modify player profiles.
No private runtime source or game assets are included in this contribution.

## Public-host composition

This draft composes the existing terrain (#318), battle-animation (#317) and
field-move (#304) offers. The local API-2 qualification retains the previously
qualified map, player, session, modal-stack and rendering prerequisites in its
frozen reference; these dependencies must be composed before treating this as
a standalone runnable change. Internal admission/read helpers do not advertise
another public API version.

The composed public candidate passes 916 companion checks, 1,466 terrain
checks, 486 collision checks, nine API-2 lifecycle checks and three SDK suites.
Its engine result is 94/105 suites versus 93/104 in the frozen reference, with
the identical eleven inherited failures. The initial source-member probe is
not a full package initialization or gameplay acceptance.
