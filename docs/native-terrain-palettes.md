# Native terrain palette programs

Normal GBA imports now classify terrain palette callbacks and preserve original
BGR555 palette words beside existing RGB data. Exact-ROM profiles cover Emerald
and FireRed Rev 0. Their pinned source references and digests are recorded in
`tools/gen3_palette_program_profiles.json`; unknown revisions or unproved
programs remain explicitly unavailable. No callback code executes. Bounded
read-only initializer analysis only identifies an audited runtime program.

Emerald's Battle Dome program supplies four unfaded palettes on a four-tick
cadence. FireRed's audited terrain callbacks are tile-only. Palette frame records
retain both native RGB and original words; existing RGB values are unchanged.
The stage authenticates the actual cartridge bytes, clears stale success on
failure and writes diagnostics to the existing tileset cache. The other three
GBA editions and arbitrary modified cartridges are not certified by these
profiles. Existing imports need a cache refresh before the new metadata exists;
automatic upgrading remains separate.

The native decoder observes independent palette ticks. The renderer refreshes
both terrain layers, cached batches, borders and reflection covers while keeping
their GPU texture identities. A bounded CPU picture cache avoids rebaking
repeating palettes; decoder samples retain at most four pictures and invalidate
on in-place source edits. Missing or invalid metadata retains base rendering.
No additional simulation, RNG, save field or mod manifest change is introduced.

ROM-free tests cover real synthetic headers and automatic stage serialization,
initializer/recipe failures, mutable source invalidation, cache limits, native
sheet/border/reflection pixels, unchanged legacy rendering and upload failure
cleanup. Run the six `gen3_palette_*` / `gen3_static_palette_reuse` engine suites
and `python3 tests/test_gen3_palette_profiles.py`. These checks do not establish
full-game, GPU, performance, cartridge fading or map-local reset-phase parity.
