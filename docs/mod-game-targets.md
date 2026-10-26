# Edition-scoped mod loading

Mods may declare `games` as an array of edition ids (`"blue"`, `"emerald"`),
generation tokens (`"gen2"`, also `"Gen 2"`), cartridge families (`"frlg"`,
`"rse"`) or `"all"`. Tokens normalize to unique edition ids in launcher order.
The game catalogue supplies every edition; the loader has no separate list.
Unknown tokens are warnings for API 1 and validation errors for API 2/3.
Malformed arrays fail validation. The legacy `gen2compat` flag adds the second
generation to an explicit claim; on its own it declares the first two.

The loader checks exact edition membership before running an entry chunk.
A skipped mod receives no API, registrations, callbacks or exports. Its hard
dependents are also skipped with the source reason, without adding boot errors.
Unrelated mods continue to load. The normal enabled preference remains intact.
The launcher shows edition claims and derives generation chips from them;
the in-game manager shows the same claim and a distinct skip explanation.

Existing `generations` claims further restrict edition claims. Manifests with
neither `games` nor `gen2compat` retain the host's previous generation policy;
installing this change does not silently turn off established native mods.

The manager's `TRY HERE ANYWAY` stores an override for the current edition only
in `options.modsGames`. A generation override does not widen an explicit
edition claim. An edition override does not turn on a disabled mod. Changes
take effect after restart and can be discarded with the other manager edits.
Previously stored per-edition compatibility preferences remain readable;
legacy boolean compatibility preferences retain second-generation scope.

ROM-free validation: `luajit tests/engine/mod_targets.lua`. It drives actual
entry chunks and dependency skips across every edition in the catalogue, checks
overrides and disabled preferences, and exercises launcher/manager decisions.
