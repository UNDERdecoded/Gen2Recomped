# Reuse validated static atlas palette projections

Repeated native atlas observations rebuilt the same 256 RGBA entries, BGR
tables and concatenated palette rows. Reuse the projection after comparing
all consumed RGB inputs by value, the original palette-word strings and the
palette-bank boundaries. Keep caller-visible BGR tables detached from the
cache. Same-clock nested RGB writes, changed provenance, modified row metadata,
palette programs, explicit overrides and foreign table observers retain the
full projection path. No terrain clock or upload owner changes.

Qualification on main cbb552a8 plus the existing shader corrections:

- 13 focused CPU groups pass: cache 1360, independent pixel goldens 1748,
  palette words/programs 602, atlas resource lifetime 526, static palette
  reuse 2448, samples 1018, frame cache 622, renderer 3639, indexed drawing
  7771, Gen2 queries 19, drawing 247, byte register 15433 and clock 46.
- An alternating five-trial CPU comparison of 3000 updates per edition
  measures median old/new milliseconds: FireRed 118.527/71.382,
  LeafGreen 121.363/71.934, Emerald 127.920/71.836,
  Ruby 126.816/72.111, Sapphire 132.229/74.963. Final lower/upper RGBA
  bytes equal the earlier projection in each edition. These are isolated
  CPU costs; they establish no whole-scene FPS improvement.
- The benchmark is reproducible with
  `luajit tools/native-atlas/palette-reuse-benchmark.lua /path/to/earlier/AtlasPixels.lua`.
  The comparison baseline is 9f8cc0fb, before this projection cache.
- The actual native atlas GPU fixture passes 526 checks with 215 texture
  readbacks under each of Metal and OpenGL on the integrated fork source.
- The actually offered atlas component, composed only with its published
  palette decoding prerequisite c08f8011 (#259), independently passes the
  cache 1360, pixel 1748 and palette-word 602 checks. Its resource/clock
  prerequisites remain those listed in the atlas offer (#260).

Receipts: focused CPU 6413d6b825, benchmark b436937911, GPU a980111c01,
offered component e49fd412c0.
Contributions by Roxas2712 under LICENSE-ROXAS2712.md; existing rights remain.
