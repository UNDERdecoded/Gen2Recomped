# Prism gifts, text, character art and Game Corner

The supported Prism ROM is compared with its matching 0.95.0254 source
snapshot and symbol file. Changes affect Prism's extraction and the Gen2
commands its scripts use.

* Adoption commands built from arrays now decode ordinary `givepoke`
  without the absent nickname/OT pointers. The runtime dispatches the gift,
  resolves variable species, preserves its held item, and returns the ROM's
  party/box/failure values (0/1/2). A full active Gen2 box rejects a gift
  instead of silently placing it in another box.
* Orphanage checks and deductions use the halfword variable for the `FFFF`
  operand. The four offers charge 100/250/500/1000 points, and their
  dynamic event flags remain separate. Full parties send gifts to storage.
* Game Corner prize scripts resolve `givepoke 0` from the script variable,
  allowing the original confirmation and success flag to reach the coin
  deduction. Freshly decoded Eevee exchange scripts give one level-20 Eevee
  and take 3000 coins.
* Name-rater text is extracted from the ROM's local labels. The selected
  nickname fills buffer 1, and the new nickname updates it. Literal dialogue
  substitutes buffer values before wrapping, preventing a token from being
  split into visible `RAM:wStringBuffer` fragments. Traded ownership checks
  include both OT name and ID. The happiness rater resolves `hScriptVar`.
* Patroller/model 7 backs display 6x6 tiles, as `GetPlayerBackpicCoords`
  specifies. The ROM loads 49 tiles but its back artwork contains 36; reading
  it as a 7x7 picture scrambled the rows. Front/back, speech/shrink and walking
  presentation now use the saved skin and outfit choices. The battle's
  palette-zone path uses the same saved choices, including a missing default
  MEWMON palette.
* Card Flip's local tilemap, cursor and palette labels are preserved in the
  manifest, producing its previously missing art. The memory game now has
  an opaque screen using ROM tiles/glove, a 45-card board, ROM distributions,
  five attempts and the 25-coin entry fee. Matches feed the script's item
  reward loop, which terminates after the collected rewards.
* The berry table covers all 29 trees, including its 11 berry rows beyond
  the apricorn separator. The existing correct extraction was absent from
  old imported caches.

Prism's cache revision is advanced so the launcher requests a reimport. Saves
are retained. Other versions' cache revisions remain unchanged.

The pictured forest entrance is Haunted Forest's Haunted Mansion warp at
(6,5), landing at (6,41) inside. Both stepping onto it and holding Up through
the normal movement/transition path entered the mansion and allowed movement
into its vestibule. No pushback was reproduced locally, and no speculative
doorway change was made. The user's affected save/device still needs checking
after the updated build and reimport.

## Validation

* `tools/prism_feature_parity_check.lua`: 95 checks, including freshly decoded
  and compiled ROM adoption/prize scripts, all four offers, PC delivery,
  nickname workflow, happiness text, berry harvesting and memory rewards.
* `tools/prism_mansion_entry_check.lua`: 6 live movement/transition checks.
* Existing script-tail, event-variable, save-layout, battle and palette-
  publication suites: 237 checks passed.
* Native LOVE extraction/rendering verified model 7 front/back in red and
  blue, 48x48 back geometry, actual battle-entry saved colors, the memory
  board/glove and the Card Flip board.
  Reproduce with `lovec.exe tools/prism_visual_check` from the repository
  root. Set `PRISM_CACHE` to the Prism `data/generated` directory when needed;
  previews and extracted test assets go under `tmp/prism-visual-preview`.

Three older source-string audits in `gen2_prism_text_test.lua`,
`gen2_prism_sprites_test.lua` and `gen2_prism_conditionals_test.lua` still fail
against their expected source snippets. Those snippets were already absent
or reordered in HEAD before these changes; the behavioral checks above pass.
Generic Red-based text/trade suites could not start because this workspace
does not have their `data/generated/constants.lua` cache.
