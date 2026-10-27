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

## Observation and retirement boundaries

Field damage queries initialize the native type chart and evaluate supported
move-effect handlers against detached combatants. Queries cannot spend resident
PP, change HP, advance scripts or consume the native RNG. Source sound commands
use separate owned voices; stopping or unloading one mod cannot stop a native
script's voice or another mod's voice. Read-only warp resolution observes the
admitted native warp record without firing the gameplay destination hook.

Map previews inspect the actual native stack state and refuse to dismiss a
covered screen. Weather queries use the native active weather byte or imported
map header. Terrain animation metadata comes from admitted imported banks and
source behavior identifiers. A detached decoder samples their original pixels;
reading metadata never rewinds or advances a live atlas or the native clock.
Missing native door artwork or a missing door animation producer is reported
explicitly rather than replaced with a synthetic animation timer.

## Qualification

ROM-free fixtures cover FireRed, LeafGreen, Emerald, Ruby and Sapphire. Run:

```sh
luajit tests/run_engine.lua
luajit tests/run_modkit.lua
luajit tests/mod_examples_tests.lua
```

The native companion suites include resident/PP validation, effect-specific
damage, field locks, owned encounter admission, native menus, evolution and
move-reminder continuations, sound isolation, warp reads, animation metadata
and teardown. Callback coverage uses the public SDK and actual native battle
and follower producers, including callback failures and owner rollback.

The GPU host checks battler orientation, native presentation phases, text ink
and shadows, nested shader state, image decoding, explicit palette-index
artwork and blend pixels with independent synthetic artwork:

```sh
python3 tools/check_companion_runtime.py --love /absolute/path/to/love --backend opengl
```

LÖVE 12 on macOS additionally supports `--backend metal`. Request only backends
supported by the supplied build. An optional `--companion-mod /absolute/package`
checks unchanged external package initialization for all five editions in
separate processes. The package must export `active` and `rendererInstalled`;
no selected package, an entry error, or an inactive renderer fails the probe.
The external package and its artwork are never included in this repository.
Initialization and synthetic pixel tests do not establish a complete playthrough.

Managed starters pin their sources, freeze committed candidates, retain a
20 GiB free-space reserve and use disposable profiles. Player profiles and
player saves are not read or modified.

## Public composition and presentation scope

The public companion branch composes the existing native session, map, player,
modal, terrain, palette, atlas, script, sprite, field-view, asset-pack, worker
permission and bounded transport offers. The branch carries these prerequisites
so its tests run against the checked-out public candidate. Native battle chrome
and field presentation are included from their existing offers as well.

The supported battle path remains the native battle controller and renderer.
An external package may request a separate presentation API with additional
command-taking, task, intro, switch or catch-sequence contracts. Those contracts
are not advertised here. Its optional alternate battle card can use the native
fallback while the package's field renderer and native companion services stay
active. This qualification must not be presented as full alternate battle-card
support or a complete playthrough of every edition.

Existing source copyright and licence notices remain in place. Original
contributions offered by Roxas2712 use the specific upstream permission in
[LICENSE-ROXAS2712.md](../LICENSE-ROXAS2712.md).

## Completion evidence

Public runtime `79c37058` passes **194/194 engine suites**, **3/3 SDK suites**,
the gallery, all **200 API-3 comparisons / 400 isolated loader runs** and
**14/14 unchanged external fixture entrypoints**. Each supported GPU host
passes **575 assertions, 30 pixel comparisons and 100 readbacks**: LÖVE 11.5
OpenGL and LÖVE 12 Metal/OpenGL. The unchanged external 1.0.9 package
initializes on all five editions on each of those three hosts.

Disposable FireRed and Emerald ROM imports additionally exercise a staged
native field, resident party edits, dialogue, field damage, wild battle, a
native move, battle return and mod unload. The external field renderer stays
active after the battle. FireRed is bound to `79c37058`; Emerald is bound to
`df85f6d0`. These are admission/action flows, not complete playthroughs or
performance benchmarks. The optional alternate battle card uses the native
fallback described above.

[Machine-readable revision-bound evidence](qa/native-companion-completion.json)
records the individual scopes and outcomes.
