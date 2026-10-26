# LOW presentation budget and UI quads (P9)

`require("src.core.Performance").lowTierBudget` defaults to `true`. Set it to
`false` to disable P9 independently: the previous AUTO heuristic and presentation
policy return, palette refresh uses full native ticks, and the affected UI paths
use their previous quad behavior. Existing P1–P8 flags remain independent.

## Additive caps and live behavior

| Cap | HIGH / BALANCED | LOW |
| --- | --- | --- |
| shaderPresets | true | false |
| colorCorrection | true | false |
| gen3PaletteCycle | full | quarter |
| reflections | true | false |
| discordPresence | true | false |

`Performance.extraCap(name)` reads these added live caps and returns nil with P9
disabled. Existing CAPS rows, methods and identities remain. Shader preset entries,
parameters and the selected correction mode stay intact while their actual passes
are masked; raising the tier restores them. Ordinary mod-owned pipelines remain
available. Game's Discord section skips work at LOW; applying LOW retires an
already loaded connection. Presence initialization keeps the same subscriptions,
but skips connection, flush and polling under the cap. Raising the tier resumes
through the existing reconnect path. No real IPC/network operation is used in QA.

The ordinary native world pass and owned field capture omit actor reflections
under LOW while retaining terrain, actors, ripples and FX. Other tiers restore the
same draw trace. Existing entity records are not replaced with cache records.

Gen-3 tile sheets sample palette ticks at floor(nativeTick/4)*4 under LOW. The
native tile animation clock keeps advancing at full speed; this reduces visual
refresh frequency without slowing the animation or changing gameplay. A private
weak record table avoids repeated sampling/recoloring during held ticks. Explicit
public palette-reader queries retain their requested ticks.

## Physical pixel policy

AUTO still recognizes ARM handhelds, mobile OS and the desktop core-count floor.
With usable `love.graphics.getPixelDimensions` data it also selects LOW for mobile
frames above 1920×1080 pixels and dual-core frames above 1280×720, and BALANCED for
other desktop frames at or above 3840×2160. These are area comparisons, so portrait
and landscape agree. Missing/invalid dimensions preserve the earlier decision.
Explicit HIGH/BALANCED/LOW selections bypass detection. Apple Silicon retains the
existing desktop exemption, including ordinary Retina-sized windows. Detection is
resolved through the existing applyOptions lifecycle, not a per-frame policy loop.

## Native UI reuse

`src/render/UiQuad.lua` owns weak, private records by menu/textbox instance and draw
site. Immediate native draws reuse a Quad and update its viewport, including source
extent. Bag pocket/item images, box icons/FRLG crops/party panel and the animated
text prompt use this path. Separate owners/sites do not share scratch Quads.
Existing box-cache fields and rollback paths remain. No hook payload, asset record,
option-row signature or require path changes; `ui.options.rows` stays in place.

## Reproduction and measurements

`tests/engine/performance_low_budget.lua` exercises real policy consumers: native
palette-sheet cadence, preset and correction masks with retained selections, the
world producer's draw trace, live restoration, a connection-state double, source
size/viewport changes and owner isolation. It passes 86 checks. Existing tier,
correction and world-hot-path regressions also pass.

Run `python3 tools/check_low_tier.py --love /absolute/path/to/love --report
.local/qa/low-tier/profile.json` on one shell line. The guarded runner uses an
isolated identity and owned asymmetric artwork. Actual bag, box and textbox draw
producers render four exact full-RGBA comparisons across prompt animation phases;
separate native ownership/allocation checks bring each backend to six scoped
checks. The loop draws 64 bag/item/icon/crop groups plus the prompt per frame,
with 120 warmup and 120 measured frames in each flag mode.

| Desktop macOS ARM64 | Previous UI draws | Cached UI draws |
| --- | ---: | ---: |
| LÖVE 11.5 OpenGL, FrameProfile CPU submission | 0.635 ms | 0.521 ms |
| LÖVE 12 Metal, FrameProfile CPU submission | 0.291 ms | 0.173 ms |
| New Quads / 120 measured frames | 15,480 | 0 |

An equal one-pixel GPU completion fence runs outside the CPU section. Presentation,
ROM artwork, ordinary game/menu usage frequency and full-game FPS are outside this
fixture. Mobile/handheld and long-session measurements are unavailable. These UI
numbers do not quantify the savings from disabled presets, correction, reflection
or presence. Source hashes and acceptance are in [low-tier-p9.json](qa/low-tier-p9.json).

The public stack reuses #89 and #100/#101/#125 for the existing color/shader
features, #259 for native palette programs/caches, plus the desktop ARM policy already offered in #243. P9 adds their LOW
policy rather than republishing those features as a separate implementation.

Integrated acceptance: 480/480 engine suites, SDK 3/3, gallery 253/253,
200 API-3 comparisons / 400 isolated workers and all 17 unchanged external
fixture entrypoints in complete mode pass. Public candidate: 167/178 engine
suites versus 166/177 on composed baseline 3bd33cb3, with exactly the same
29 FAIL lines across eleven inherited suites. Public SDK 3/3, gallery 253,
API-3 48/96 and all 17 fixture entrypoints pass; its new 86-check suite passes.

The public Metal branch separately passes the same six native checks. Its UI CPU
measurement is 0.386 → 0.222 ms during concurrent acceptance work; its own source
hashes are retained separately. Its TextBox lacks the fork's unrelated Gen-2 prose
substitution repair, and its world has no owned field-capture API; P9 does not add
that separate API. Existing correction/preset merge order, private native viewport
and window-UI guard, sheet pinning and profiler sections are retained in the stack.
