# Scoped mod dependencies

Existing `"library"` and `"library@^1.0.0"` requirements retain their behavior.
An optional `#owner/repository` suffix supplies a GitHub source hint. Object
entries can declare a version range, source, edition scope and engine scope:

```json
{
  "dependencies": [
    "shared_library@^1.0.0#author/shared-library",
    {
      "id": "field_library",
      "range": ">=2.0.0 <3.0.0",
      "github": "author/field-library",
      "games": ["firered", "leafgreen"],
      "game_version": ">=0.8.0"
    }
  ],
  "optional_dependencies": [{"id": "extra_effects", "games": "gen3"}],
  "conflicts": [{"id": "alternative_field", "game": "frlg"}],
  "dependency_sources": {"other_library": "author/other-library"}
}
```

`version` aliases `range`, `repo` aliases `github`, and `game` aliases `games`.
Edition tokens use the same normalization as top-level edition declarations.
An explicit edition stays exact even when another edition shares its generation.
`game_version` constrains the engine version for which that edge applies; it is
separate from the dependency's own version range.

Inactive edges do not block loading, form hard cycles, cause conflicts, change
optional ordering or cascade manager toggles. An optional edge orders a present
library only when its version satisfies the range. A context-free catalogue or
launcher can inspect potential edition edges; in-game toggles use the selected
edition. Engine scopes always use the actual engine version.

Source hints are validated GitHub repository identifiers. They do not install
or execute anything. `LauncherMods.checkDependencies` and launcher row metadata
expose their review URLs and distinguish missing, disabled and incompatible
dependencies. An invalid source hint is discarded; malformed identities, ranges
and edition scopes reject the manifest rather than silently widening it.

The ROM-free scoped dependency suite exercises the real loader across all host
editions, hard-cycle and conflict detection, optional ordering, manager closure
and catalogue warnings. These checks establish manifest/runtime behavior rather
than acceptance of every dependent mod or platform.
