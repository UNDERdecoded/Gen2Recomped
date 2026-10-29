# Live native GSC Pokemon fields

Source GSC consumers read `mon.maxHp`, `mon.name`, `mon.types`, and
`stats.specialAttack`/`stats.specialDefense`. Native Pokemon store their
maximum in `stats.hp`, look up species display/types from the data registry,
and use `spatk`/`spdef`. A real native birth on preceding source `a6eb0c05`
fails all five source-field checks; the implementation module is absent too.
Unchanged menu, healing and capture consumers can consequently read missing
maximums or special statistics despite the native combat values existing.

`Gen2MonFields` supplies those spellings on the actual native tables.
Reads follow native stat-block replacement and live registry changes;
source stat/maximum writes reach their native canonical fields. Construction,
save validation, the native battler data factory and identity refresh bind
the original Pokemon. Native GSC stat calculation/rehydration publish split-stat aliases. This
older host republishes species base-stat aliases after its real generic
registry fold, without adding the newer fork's species-name writer. Data seeding and actual
mod loading also expose the base-stat spellings used by source consumers.
There is no parallel Pokemon, duplicated HP counter or per-frame polling.

Aliases live on metatables, without adding helper keys to serialized records.
Explicit authored stored fields retain their existing precedence. Existing
custom metamethods are preserved; protected custom metatables are not
replaced and may therefore decline the additional fields. Live Pokemon retain
their data owner; abandoned Pokemon/data cycles remain collectible on LuaJIT.
The helper does not allocate graphics or install a fake LÖVE runtime.

Newer fork selected qualification on corrected source `2a000267` (not an
independent qualification of this older offered host):

- 156 pure-data checks with no LÖVE, including live owners, canonical writes,
  replaced registries/stat blocks, custom/protected tables and cycle collection.
- 162 actual native checks across the registered editions: birth, real save
  encoding/decoding/validation, native battlers and source model, box stats,
  actual SDK loading and native registry writes. Non-GSC Pokemon are excluded.
- Existing data construction 691, native construction/art hydration 972,
  identity ownership 142, species identity 145 and save-summary 50 checks pass.

The first implementation lost custom metamethods on a cache miss; four pure
checks caught it. The corrected cache selection passes all checks. The same
native probe on the preceding committed engine fails six checks, including
the five observed field gaps. Complete current-tree, unchanged-mod GPU/menu
and final release qualification remain open. This does not implement the
still-missing standalone source battle constructor or turn/event executor.

No mod, protected Gen1 installation, ROM original or player profile is edited.
Existing engine authors' rights remain effective; native field integration
and tests by Roxas2712 are subject to `LICENSE-ROXAS2712.md`.

This older adaptation uses its actual `BattleState.makeBattler`, controller
and original RNG constructor signature. It does not fabricate the newer
fork's extracted Battler, live source model, identity refresh or source
options-record constructor, which are separate offered work. Its own native
probe follows the actual older SDK loader/registry fold. Corrected source
`6985a377` independently passes184 pure-data and170 native checks across
its15 registered editions, plus4454 frame-query,116 chrome and1031
screen-position regressions. The managed host is cleaned after exit.
Its initial independent run on `c0ea73de` passed the pure-data/frame/chrome/
position checks but rejected the actual SDK `spatk` patch as an unknown
nested schema field. The schema now accepts native `spatk`/`spdef` with the
same1..255 integer bounds; invalid inputs remain rejected. The native
registry-fold test still patches both real columns and now passes.
The older host has no semantic-checkpoint subsystem: no newer checkpoint
facade or unqualified checkpoint integration is added to this offer.
The pure helper authenticates its own unchanged raw-record wrappers and
provides native-slot rebinding, with custom-owner refusal and no mod-storage
traversal. It is stacked on upstream PR398 and its existing prerequisites.

Independently owned integration/tests by Roxas2712 are offered under
<https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md>,
including the specific Cedric / UNDERdecoded permission with visible credit.
Existing engine authors' rights, notices and earlier grants remain effective.
