# Native GSC trainer friendship and source class predicates

The shared native trainer constructor now applies the original Gold/Silver/
Crystal `GYMBATTLE` friendship event before the first turn. Previously the
award was coupled to `BattleState:enter()` and the narrower badge-leader
marker: the Elite Four, Champion and Red received no award, and construction
alone did not expose the updated values to source consumers.

`src.battle.gen2.Battle` exposes the source `GYM_LEADER_CLASSES`,
`KANTO_GYM_LEADER_CLASSES`, `isGymLeader(class)` and
`isKantoGymLeader(class)` contracts. The first predicate covers all 22 classes
in the cartridge's combined leader list; the second covers its eight Kanto
classes. The actual native constructor calls the public predicate, so an
API2 class decoration affects the real battle rather than a second model.

Imported native records retain their numeric group index. The engine maps
that identity to the canonical class identifier rather than comparing the
localized display name, which is often just `LEADER`. It does not mutate the
imported trainer record or claim that every source trainer-view field is
implemented.

The award uses the existing native friendship owner and the battle's ordered
party view. Living, non-egg members receive +3 below 100, +2 below 200, or +1
otherwise, clamped to 255. Excluded party members are untouched. API2
`happiness.changed` callbacks carry the original native mon and the source
symbolic event (`GYMBATTLE`); the numeric cartridge index remains available
as `eventId` (4). Applied events at saturation (and other zero-delta happiness
events) remain observable, as on the reference engine; unchanged walking
steps remain silent.

The award is not replayed by screen entry. Native badge/music and Yellow companion markers keep
their separate meaning. Other editions and Gen2 hacks keep their existing
friendship rules. No mod, Gen1 installation, player profile, save or ROM is
modified by this change.

## Older-host party prerequisite

This offered host did not have the fork's battle-local party selection or
`playerPartyView()`. Supply the original native selection integration here:
validate and retain ordered original mon references in the trainer constructor,
then use the same roster for the lead, doubles, native party menus, benches,
party-wide effects, EXP/EXP.ALL and defeat decisions. Never replace or reorder
`save.party`. Invalid selections fall back to the complete original party.

The standalone `native_trainer_party_scope` regression drives actual older-host
constructors, generation-appropriate menus, AI, Heal Bell/Beat Up, EXP and defeat
across its supported editions. Qualification requires execution on this offered
host; the corresponding fork result is not inherited. Execution status is
recorded in the draft PR.

## Validation

The committed ROM-free regressions exercise real `BattleState.newTrainer`,
the production API2 loader and event bus, all vanilla classes and seven
friendship boundaries, native egg representations, fainted/selected party
members, decorator reachability and other-edition guards. This older offered
host lacks the fork's semantic checkpoint backend, so the fork-only checkpoint
test/result is not inherited. Execution results and independent frozen-reference
comparison are recorded in the PR after running those checks.

This closes the class-predicate/constructor-award gap. It does not establish
complete source-model constructors, turn/event parity, graphical parity,
unchanged VASC acceptance or release readiness.

Native integration/tests by Roxas2712, offered to Cedric / UNDERdecoded under
the specific PR permission in LICENSE-ROXAS2712.md; existing rights remain intact.
