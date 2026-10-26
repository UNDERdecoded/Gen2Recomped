# World anchored sun shadows (P7)

`V.shadowWorldAnchor` defaults to `true` in `mods/DRAMATIC_SHAPE/main.lua`.
Set it to `false` to restore the combined, camera-fitted shadow pass independently
of the other performance flags. A failed secondary target also selects that
complete legacy pass, with a sticky failure until shadow resources are invalidated.

`WorldShadows` is a separate internal card. It rounds the existing visible-ground
bounds outward to a 256-world-pixel grid. The static light projection stays fixed
while that set of cells remains visible. Actual terrain, water and flower meshes,
map/neighbor offsets, atlas identities and alpha-animation steps, sun direction
and the existing resolution cap participate in invalidation. There is one cached
static projection, not an unbounded collection of tile textures.

Moving sprites, authored figures and battle cards use a second 256-square target
with the same projection. Their poses, resolved images, chosen frames, first-person
view and battle token determine invalidation. The existing BALANCED cadence still
limits moving updates. Static changes update both maps immediately. The lit shader
samples both maps and combines coverage without doubling shadow darkness. Water
continues to sample static casters only, as its previous actor exclusion requires.

The anchored path corrects render-target lookup Y under the tested LÖVE 12 Metal
backend. Its pixel test compares the same lit scene with only dynamic sampling
enabled/disabled. The original four-argument shadow pass retains its conversion.
`Tier.lua`, the manifest and engine-internals permissions are unchanged. No loader,
public mod interface, hook or engine record changes are needed.

## Reproduction and measurement

Run `python3 tools/check_world_shadow_profile.py --love /absolute/path/to/love
--report .local/qa/world-shadows/profile.json` on one shell line. The guarded runner
uses a separate QA identity, owned geometry and texture, actual native shadow/scene
shaders, matrices and targets. It stores source hashes and the lit-image negative
control. It does not use a cartridge, player profile or game save.

The 13,824-vertex flat grid and one moving alpha-tested card are an isolated pass
fixture. Each mode has 120 warmup and 120 measured frames. FrameProfile separates
`voxel.sun submit (owned geometry)` from `voxel.sun GPU fence (owned geometry)`.
A one-pixel readback completes GPU work in both modes. Presentation is excluded;
these are offscreen pass times, not full-game FPS or an end-to-end speedup claim.

| Desktop macOS ARM64 host | Combined pass | Anchored layers |
| --- | ---: | ---: |
| LÖVE 11.5 OpenGL, CPU submission | 0.090 ms | 0.045 ms |
| LÖVE 11.5 OpenGL, including GPU fence | 0.794 ms | 0.298 ms |
| LÖVE 12 Metal, CPU submission | 0.096 ms | 0.074 ms |
| LÖVE 12 Metal, including GPU fence | 0.767 ms | 0.563 ms |
| Static passes per 120 measured frames | 120 | 4 |

The trajectory crosses a grid boundary and wraps, so four static updates are
expected; the moving layer updates all 120 frames at HIGH. GPU fence costs vary
between runs: an earlier Metal fixture run measured 0.547 → 0.732 ms, while the
final source-bound run above improved. The reduction in static work is repeatable;
this small fixture does not establish a universal GPU speedup. A real populated
map and mobile/handheld performance remain unmeasured.

Both native hosts pass 22 scoped checks: plain/instanced shader compilation,
negative-coordinate snapping, unchanged static pixels/matrix during walking,
moving pixels and their actual lit contribution, cell/geometry/sun/neighbor
invalidation, idle reuse, balanced cap/cadence, live rollback, and sticky allocation
failure with complete legacy shadows. The source-bound record is
[world-shadows-p7.json](qa/world-shadows-p7.json).

Integrated fork acceptance: 477/477 engine suites, 3/3 SDK suites, 253 gallery
checks, 200 API-3 comparisons / 400 workers, and all 17 unchanged external fixture
entrypoints in complete mode pass. The public stack retains exactly its previous
29 FAIL lines across 11 inherited suites: 156/167, with no new failure. Its SDK,
gallery, 48 API-3 comparisons / 96 workers and 17 fixture entrypoints all pass.
