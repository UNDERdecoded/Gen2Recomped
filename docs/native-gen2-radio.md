# Native Gen2 radio content and wall-radio lifecycle

The native `MapRadio` special previously only assigned a successful check
result. It now opens a native radio overlay, holds its station announcement
for 100 update frames, and resumes the suspended native script once on A/B.
Closing a covered or already closed overlay cannot pop another state or
resume the script again. The existing `setval` result is preserved.

`mod.content.radio_channels` provides the shared native station records for
Gold, Silver and Crystal. Records accept an optional `channel` integer
0–255 and optional authored display `name`. Positive wall-radio channel
numbers must be unique. Channel zero remains the automatic Pokemon Channel:
Johto morning selects Pokedex, other Johto hours select Oak, and Kanto
selects Places & People. Region detection uses the loaded map definition
and imported Pallet landmark boundary when available.

API 1/2 native mods can inspect detached records, patch,
override, register and remove them. The native Pokegear uses the same
records for its existing program slots; a new numbered station is available
to wall radios without inventing a Pokegear tuning frequency. An explicitly
empty dataset remains empty. Built-in names retain engine translation,
whereas authored names are displayed literally.

Content writes are frozen after load. Failed entries roll back their earlier
writes and subscriptions. Reusing the mounted dataset on reload retires old
mod writes while preserving unrelated external edits and removals. A mod-free
load does not materialize an extra namespace. Other generations receive an unavailable content handle and cannot create
the native target. This standalone patch does not add the fork capability
query or unified API prerequisites.

`radio.channel` is emitted on tuning, not on drawing or advancing text:
`station` is the stable station ID, `name` is its display name, `channel` is
the wall script byte or native Pokegear knob position, and `source` is
`map_radio` or `pokegear`.

Focused synthetic acceptance: 113 content/loader checks and 73 native
VM/UI/input checks. These tests use the actual loader, bytecode lowering,
coroutine runner, native state stack and Pokegear input path. They do not
establish GPU or unchanged-mod gameplay acceptance.

The existing native Pokegear program text is reused. Full cartridge show
state machines, schedule-dependent program data, songs and map-music
restoration are still open parity work. This change is not complete radio
parity and must receive new runtime/package/GPU qualification before release.

Original contributions by Roxas2712 are offered to Cedric / UNDERdecoded
under the specific contribution permission in
[LICENSE-ROXAS2712.md](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md).
Existing project, third-party and previously granted rights remain effective.
