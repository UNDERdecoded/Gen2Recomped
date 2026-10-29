# Native GSC volatile state

The live Gen2 battle model exposes `volatile(mon)` as a view of its existing
native battler, rather than a disconnected metadata table. Canonical source
names `confuseCount`, `flinched`, `endure`, `recharge`, `protectCount`,
`focusEnergy` and `xAccuracy` address the native confusion counter, admission,
damage, action-lock, protection, critical and hit-check owners. Substitute,
protect and mist aliases are also supported. Unknown keys remain transient
consumer metadata, not newly implemented mechanics.

Views are cached on the transient model only. Module-global weak-key caches can
retain retired battlers on LuaJIT when value closures reference the key. The
same active native owner has a stable view; withdrawn entries retire on query
and incoming wrappers get new views. No view or metadata is stored in a party
mon or serialized battler.

GSC consecutive-protection retention follows the actual PROTECT/ENDURE effect,
including renamed moves; an old PROTECT ID with another effect resets it.
Protection RNG, opponent-first and Substitute rules are addressed by the
separate [native protection work](native-gen2-protection.md).
No second battle simulator is introduced.

On this older host, 423 real native state/mechanics/ownership/collection checks,
262 model checks and 83 move-priority checks pass independently. The fixture
loads an actual API2 source consumer and covers Gold/Silver/Crystal, Prism and
Polished Crystal. The fork's additional semantic-checkpoint backend is absent
here, so its checkpoint result is not claimed for this offered branch.
These ROM-free CPU checks do not establish complete source-model, GPU,
unchanged-mod or release acceptance. Depends on the native model boundary and
move-priority contributions offered separately.

Source-field names were inspected against Gen1Recomp Gen2 revision
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Native integration and tests are
contributions by Roxas2712, offered to Cedric / UNDERdecoded under the fork's
specific PR contribution permission, with existing third-party rights intact.
