# Native Gen2 scene/window owner

Expose `drawWidescreen` and explicit Gen2-only compositor admission on the actual
shared battle class. This upstream adaptation also splits the existing Gen2
classic/wide BG, objects and final-overlay composition into `drawPanel`,
`drawSceneBody` and `drawScene`; the older branch did not provide them. The
same native scene, chrome, layout and fixed/fill setting remain authoritative.
The graphics guard restores caller canvas/state even after leaked pushes.
Other editions retain the original classic/wide route. No mod or game data
is changed or included.

The public contract was checked against Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`,
`src/ui/gen2/BattleState.lua`. The extracted native composition retains the
existing BattleState/WideBattle provenance and applicable project rights.
The additional graphics guard is an independently owned Roxas2712 contribution
offered under the permission described in this PR.

Source tests cover native window admission, multiple viewport/DPI sizes,
classic/wide scene ownership, fixed/fill options, caller-state restoration
and native menu/model/summary regressions. The separate fork's earlier
54 functional Metal checks and12 inspected captures diagnose a missing native
drawer and a white fallback on an older source; they do not qualify this
upstream composition, current visual parity, packages or a release.
