# Native Gen2 phone identities and Buena import

The importer used a Gold-sized four-name list for all cartridges. Actual
Crystal contact37 uses non-trainer identity5, so Buena and both of her phone
script pointers were discarded. Read the name range referenced by the actual
native contact rows instead. Native outgoing/incoming pointers and masks stay
in their original directions. Empty and reserved rows remain uncallable.

Each non-trainer row now preserves `contactNumber` independently of `number`,
which remains the native **map number**. `map_scripts.phoneInfo` carries the
full reserved table size, actual rows read and imported non-trainer names.
Even a completely empty book retains its reserved bound.

Native constants also retain explicit phone-contact and trainer class/member
orders. These are constant identifiers from reference535a5ec0, not localized
display-name guesses or ROM dialogue. Existing authored identity metadata is
authoritative; explicit manifest metadata supports alternative cartridges.
A partial authored identity set does not silently inherit unrelated retail
roster rows. Retail fallback is limited to Gold/Silver/Crystal. Legacy
`PHONE_OAK` is retained as a compatibility spelling for slot2; the actual
imported display name remains authoritative.

The `gen2-phone-identities-v1` marker rebuilds only stock G/S/C imports once.
Existing saves are not modified by this change. Other edition cache markers
are unchanged.

Validation:138 synthetic checks exercise both native directions through
Gen2ScriptVM/ScriptRunner, Buena's actual name consumer, reserved/empty rows,
separate map/contact numbers, copied metadata, authored precedence, generation
isolation and the real cache-readiness gate. A read-only actual Crystal table
probe changes32 to33 callable rows (28 trainer /5 non-trainer),38 reserved
rows and62 to64 queued phone scripts; all trainer members resolve through
explicit metadata. The original ROM is unchanged. This is table extraction,
not full-import, GPU, story-call or complete phone-facade acceptance.

The semantic `phone_contacts` registry writer, stable added-contact allocation,
rollback/reload and the remaining legacy Phone facade still need implementation.
These fields are prerequisites for connecting those APIs to native consumers;
the native numeric saved phone book remains authoritative.

Original implementation by Roxas2712. Existing upstream and third-party
licenses/credits remain applicable; see the specific contribution permission and credits:
<https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md>.
