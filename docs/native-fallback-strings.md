# Translation-mod access to native fallback text

The October upstream update added native hatch and Pokeathlon consumers whose
English fallback text bypassed the shared `strings` catalog. A translation
mod could override the imported message bank, but could not replace these
fallbacks when that bank entry was absent. Several templates also inserted
the Pokemon or item name before a catalog could look up a stable source key.

Hatch prompts, athlete-shop messages and the team-panel medal caption now
translate their source template before substituting the name or balance.
Imported bank messages retain their existing precedence and buffering. The
shop's prices, points and award rules stay on their original native paths.

Poke Transfer refusal messages already performed their lookup at use time.
Their module-level source table now uses `Strings.source()` markers so the
catalog harvester can find the keys. These markers do not translate at
module-load time: loading a translation later, or changing its catalog,
continues to affect the displayed refusal.

Validation uses a ROM-free mod loaded through `T.sdk.loadMod()` and the public
`mod.content.strings:override()` registry. The unchanged production consumers
are loaded before two successive catalogs. Native hatch paths cover Platinum,
HeartGold and Black; actual athlete-shop transactions, transfer text boxes
and the team-panel draw path use synthetic data and hardware doubles.

- **85/85** consumer checks pass, including ROM-message precedence, name
  substitution, late catalog changes and unchanged card/point transactions.
- The exact same suite with the four unchanged upstream modules fails
  **30/85** checks. Existing runtime-translated transfer refusals continue
  to pass that negative control; their repair is catalog discoverability.
- The coverage gate passes **16/16**, existing string-registry tests pass
  **20/20**, and the existing SDK tier passes **3/3** suites.
- The actual source harvester finds all **13 required templates** in copies
  of the four changed modules; the parent copies expose none of those keys.
  This is a scoped harvester check, not full translation-CLI acceptance.

Run from the repository root with LuaJIT:

```sh
POKEPORT_DATA_DIR=tests/fixture_data luajit tests/engine/native_fallback_strings.lua
POKEPORT_DATA_DIR=tests/fixture_data luajit tests/engine/gate_strings_coverage.lua
POKEPORT_DATA_DIR=tests/fixture_data luajit tests/mod_strings_tests.lua
POKEPORT_DATA_DIR=tests/fixture_data luajit tests/run_modkit.lua
```

See the [source-bound receipt](qa/native-fallback-strings.json). No ROM,
normal save or graphics/audio device is required. These checks do not
establish a complete game or whole-mod playthrough.
