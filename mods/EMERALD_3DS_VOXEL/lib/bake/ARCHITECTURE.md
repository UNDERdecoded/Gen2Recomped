# lib/bake: Emerald 3DS's voxel bake, in Lua

The mod draws four ROM-derived files (`buildings.bin`, `relief.bin`,
`regions.bin`, `signposts.bin`) plus `layouts.lua`. `bake/bake.py` makes them
with Python by running Emerald 3DS's generators (`3ds_port/scripts/*.py` of
the dev checkout) on a tree the v0.4.0 release builder rebuilds from the ROM.
This folder is that pipeline ported to Lua, so release builds (no Python,
`generated/` pruned) can bake in-game on desktop and phones.

It ships with the mod: do not move it under `generated/` or `tools/`, which
`scripts/pack_love.sh` prunes.

## Pipeline (`Bake.lua`, mirrors bake.py `bake_from_checkout`)

1. `vtree.build_tree(rom, recipe, tree)`: the generators' input tree, in
   memory (`Tree.lua`). 2724 files, about 0.1 s.
2. `Bake.install_assets(tree, fetch)`: the generator assets (below) into
   `tree/3ds_port/...`.
3. The steps of `emerald3ds_builder/voxel.py` STEPS, in order:
   `gen_voxel_regions`, `gen_voxel_sign_masks`, `gen_voxel_relief`,
   `gen_voxel_buildings`. `gen_intro_margins` is skipped (not voxel data).
   Each step runs in a fresh `Session` (one Python process; see below) and
   writes `tree/3ds_port/romfs/voxel/<name>.bin`.
4. `Bake.layouts_lua(tree)`: `layouts.lua` from `data/layouts/layouts.json`
   (bake.py `write_layouts`; LF line ends).

`Bake.run{rom, recipe_blob, inflate, fetch, steps, progress, open}` does it
all and returns `{["regions.bin"] = bytes, ...}`. Nothing here touches the
disk or `love.graphics`: the caller passes `inflate` (zlib), `fetch`
(assets) and gets bytes back, so the whole bake can run inside a
`love.thread`.

**Streaming (`opts.open`).** With `open(name) -> writer` (`:write(chunk)`,
`:close()`, both raising on failure) every output is written through a
writer as it is made instead of returned, and Bake.run returns
`{[name] = size}`. `Bake.run_step` passes the step's
`output(path) -> writer` into the Session; a generator asks
`S:output(path)` and, given a writer, writes its parts in order and leaves
the file out of the tree (gen_voxel_buildings export: buildings.bin is
never joined into one 35 MB string). The small outputs are still built in
the tree and written in one chunk. Without `open` nothing changes (the
harness steps and compare tools). Bake.run also clears `opts.rom` and
`opts.recipe_blob` so the caller's ROM copy can go. `lib/BakeThread.lua`
streams to `e3ds_voxel/<name>.part` (love File, buffered), and only once the
whole bake succeeded removes the stamp, writes `incomplete.txt`, renames
every `.part` over its output (os.rename on the real save path, else a
chunked copy), writes the stamp and removes `incomplete.txt`; a failed bake
deletes its `.part` files. `BakeJob.dataState` calls a folder with
`incomplete.txt` stale.

**Progress.** `Session:part(lo, hi, label)` / `S:tick(f)` report through a
part of the step's 0..1. The relief (`gen_voxel_relief.PARTS`): ledges
(main) 0-2%, drawn maps (world_levels, a tick per drawn group) 2-30%, map
heights (export, a tick per layout) 30-66%, terraces (apply_file, a tick
per chosen layout) 66-93%, sea ramps / cut feet / fixes 93-100%. Buildings
(`gen_voxel_buildings.PARTS`): spec expansion, building models (a tick
every 4 specs built), then export's placements/textures/pages. BakeThread
weights the steps by their JIT-on or JIT-off cost; BakeJob shows what the
thread reports (no estimate in between).

## Files

| file | what | status |
|---|---|---|
| `Bake.lua` | orchestrator, asset list and fetcher, layouts.lua | done |
| `Session.lua` | per-step module loader ("one Python process") | done |
| `Tree.lua` | in-memory filesystem: path -> bytes | done |
| `recipe.lua` | recipe.py: ops C/F/L/Z/R, patches, GBA LZ77, CRC-32 | done |
| `vtree.lua` | vtree.py: inputs, layouts.json, map.json, the three headers | done, tree identical |
| `recipes/<code>.vtree` | the recipe's voxel part, zlib JSON (BPEE/BPES/BPEF/BPEI) | done |
| `json.lua` | CPython-compatible json (decode keeps key order; encode = `json.dumps(indent=2)`) | done |
| `py.lua` | Python semantics: round, hypot, sorted, max, struct, dict, class, key | done, tested |
| `Image.lua` | the Pillow subset (+ ImageChops, ImageFilter, PNG decode) | done, tested vs Pillow |
| `voxel_art.lua` | voxel_art.py | done |
| `voxel_cells.lua` | voxel_cells.py | done |
| `voxel_sign_mask.lua` | voxel_sign_mask.py | done |
| `dump_region_art.lua` | dump_region_art.py | done |
| `voxel_props.lua` | voxel_props.py | done; find/cells_in/connections identical for all layouts |
| `voxel_relief_fixes.lua` | voxel_relief_fixes.py | done; parse/pack/apply/cut_clear/cut_fringe identical (seam_eases needs gen_voxel_relief.map_links) |
| `voxel_building.lua` (+ `voxel_building_2.lua`) | voxel_building.py (lines 1-1806, 1807-3740; the second is an installer the first calls) | done; replayed against a recorded real Python build_models() run |
| `gen_voxel_regions.lua` | gen_voxel_regions.py | done, regions.bin byte-identical |
| `gen_voxel_sign_masks.lua` | gen_voxel_sign_masks.py | done, signposts.bin byte-identical |
| `gen_voxel_relief_pyx.lua` | CPython 3.12 set (hash-table iteration order, incl. dummies, resizes, set operators) and dict-with-deletions emulation; positions as `pyx.xy(x, y)` numbers | done, tested (unit_pyx: 13k random histories, commonest_rgb) |
| `gen_voxel_relief.lua` (+ `_a`, `_b`) | gen_voxel_relief.py: foundation (1-830 but solve, map_links, ledge_cells, open_roles) + installers `_a` (831-2598: world_levels, sea ramps, cut feet, drawn_canvas ... solve_drawn) and `_b` (solve, 2627-4331: ledges, layout_heights, cut/rim cells, cell_shapes, export, main) | done, relief.bin byte-identical |
| `voxel_terraces.lua` (+ `_a`, `_b`, `_c`) | voxel_terraces.py: installer + `_a` (60-1293: Cells ... settle), `_b` (1532-3058: blocks ... rough fields), `_c` (3059-4950: ledges, solve, marks, records, merge, apply_file); unreached code not ported | done (apply_file identical to the Python stage) |
| `gen_voxel_buildings.lua` (+ `_2`, `_3` installers: py 1-1746, 1747-2551, 2552-4417) | gen_voxel_buildings.py (no preview/verify/lint) | done, buildings.bin byte-identical (JIT on and off) |
| `voxel_building_specs.lua` (+ `_2`, `_3` installers: py 1-2393, 2394-5129, 5130-7515) | voxel_building_specs.py | done |
| `voxel_bridge.lua`, `voxel_night.lua` | voxel_bridge.py (no main), voxel_night.py | done; `voxel_bridge.PySet` emulates CPython 3.12 set order |

One Lua module per Python module, same name, same function and class names.

## Loading

Two kinds of modules:

* **Infrastructure** (`py`, `json`, `Image`, `Tree`, `recipe`, `vtree`,
  `Bake`, `Session`): stateless, loaded once with `V.require("bake/<name>")`
  exactly like the mod's `lib/` modules (`chunk(V)`).
* **Ported generator modules** (everything named after a Python file): loaded
  per run with `S.import("<name>")`. The chunk is called as `chunk(V, S, M)`:

  ```lua
  local V, S, M = ...          -- M: this module's table (pre-made, for cycles)
  M = M or {}
  local py = V.require("bake/py")
  local tree = S.tree          -- the Tree this run reads and writes
  local voxel_art = S.import("voxel_art")
  ...
  return M
  ```

  Module-level code (Python's top level: `MB = behaviours()`, memo dicts)
  runs once per Session, i.e. once per generator run, as each Python script
  ran in a fresh process. An import inside a Python function stays an
  `S.import` inside the Lua function (same laziness; it is how cycles such as
  voxel_bridge <-> voxel_building_specs stay legal). `S.import` of a module
  being loaded returns its partly filled M, as Python does.

`Session.lua` finds sources through `V.read(rel)` (harness, thread), else
`V.mod:read(rel)` (main.lua's V), else `love.filesystem.read(V.path/rel)`.

A generator exposes `M.main()`; `Bake.run_step(tree, "gen_voxel_regions")`
runs it in a new Session.

## Tree (`Tree.lua`)

Paths are the strings Python joins onto ROOT, relative, `/`-separated:
`os.path.join(ROOT, entry["blockdata_filepath"])` is
`entry.blockdata_filepath`; `os.path.join(PORT, "romfs", "voxel", "x.bin")`
is `"3ds_port/romfs/voxel/x.bin"`.

`tree:read(p)` (nil if missing), `tree:must(p)` (raises like `open`),
`tree:write(p, bytes)`, `isfile`, `isdir`, `exists`, `listdir(dir)` (sorted),
`files()`, `remove`, and `tree:cached(key, fn)` for parsed files
(`"json:" .. path`, `"u16:" .. path`; cleared when any file is rewritten).
Text is stored with `\n` (CPython's text mode reads CRLF as LF).

## Python -> Lua conventions (follow them; the gens rely on them)

**Indexing.** Python lists and tuples become 1-based Lua arrays: `a[i]` is
`a[i + 1]`, `a[-1]` is `a[#a]`, `a[k - 1]` with `k == 0` is `a[#a]`
(triangulate does this). Slices become loops or helper calls. Pixel buffers
and `Image` coordinates stay 0-based (Pillow's). Exceptions, documented where
they are: `voxel_art` pixel dicts (`p = y*16 + x`), `Tilesets:subtile`
arrays (0-based 64), palettes (0-based 16).

**None** is `nil`; inside arrays, where a hole would break `#`, use `false`
and say so in a comment.

**Tuples as dict keys / set members** become strings: `py.key(a, b, ...)`
(numbers canonical: `1 == 1.0`, `-0.0 == 0.0`, as Python hashes them) or
`py.tkey(array)`. For small int pairs a numeric key is faster:
`voxel_cells.pk(x, y)` / `unpk(k)`.

**dict order.** Python dicts are ordered. A plain Lua table is fine when
order cannot show; when it can (`max(d, key=...)`, `for k in d:` that
appends to output, `next(iter(d))`), use `py.dict()` (`:set`, `:get`,
`:setdefault`, `:has`, `.keys`, `:iter()`). `max(seq, key=f)` /
`min` = `py.max_by` / `py.min_by` (first extreme wins, like CPython).
`sorted(seq, key=f, reverse=r)` = `py.sorted` (stable; keys may be numbers,
strings, booleans or arrays compared like tuples via `py.cmp`).

**set order.** Python sets of ints/tuples iterate in hash order. If a set's
iteration order reaches the output (a first match, an appended list, float
sums), find out what CPython does and reproduce it; usually the code sorts
or only tests membership. Flag any you could not settle.

**Numbers.** Both are IEEE doubles; the differences are in the operators:

| Python | Lua |
|---|---|
| `a // b` | `math.floor(a / b)` (`py.floordiv`) |
| `a % b` | `a % b` (same sign rule in Lua 5.1/LuaJIT) |
| `int(x)` | `py.int(x)` (truncates) |
| `round(x)` / `round(x, n)` | `py.round(x)` / `py.round(x, n)` (exact, half-even; tested on 20k values) |
| `math.hypot` | `py.hypot` (correctly rounded like CPython 3.12; `math.sqrt(x*x+y*y)` is NOT) |
| `math.radians` / `degrees` | `py.radians` / `py.degrees` |
| `x ** y` (floats), `math.sin/cos/tan/atan2/asin/acos/atan/exp/log` | `py.pow`, `py.sin`, ... (ucrtbase through the FFI on Windows, as CPython; LuaJIT's `^`/`math.*` differ in the last bit) |
| `sum(floats)` | `py.sum(array)` / `py.sumv(a, b, ...)` (CPython 3.12's sum is Neumaier-compensated, not a plain loop) |
| `math.copysign` | `py.copysign` |
| `x ** 0.5` | `math.sqrt(x)` |
| `x ** 2` | `x * x` |
| `True + 1`, `sum(bools)` | convert explicitly |
| `bin(v).count("1")` | `py.popcount(v)` |
| `struct.pack("<...")` | `py.pack(fmt, ...)` / `py.pack_list(fmt, list)` (B b H h I i f x; f is binary32 round-half-even; range errors raise like struct.error) |
| `struct.unpack_from` | `py.unpack_from(fmt, data, offset)` -> array |
| `zlib.crc32` | `recipe.crc32` |

Floats print/compare the same. Off Windows there is no ucrtbase: py.pow
falls back to correctly rounded small integer powers / sqrt, the others to
the platform libm, which may differ from a Windows golden in the last bit;
the outputs are float32, which hides nearly all of that. Python ints never
make -0.0 and Lua cannot tell 16 from 16.0: where Python negates an int,
write `0 - x`, and normalise floor/ceil/int results to +0 when they feed a
sign test. Keep the LuaJIT ARM64 JIT off (FMA fusion changes rounding).

**Colours.** Packed integers: rgb `r*65536 + g*256 + b`, rgba
`r*2^24 + g*2^16 + b*2^8 + a` (`Image.rgb`, `Image.rgba`, `Image.unpack_*`).
A Python `rgb + (255,)` is `Image.rgba(r, g, b, 255)` or the 4 values to
`img:put`.

**Classes.** `local C = py.class("Name", Base)`, `function C:__init(...)`,
instances via `C(...)`, `py.isinstance(obj, C)`. Export classes as `M.Name`
(the same table: `M.Proj(...)` constructs).

**Exceptions.** `raise X(...)` -> `error(...)`, `try/except` -> `pcall`.

## Image (`Image.lua`), Pillow 12.3 semantics

| Pillow | Lua |
|---|---|
| `Image.new(mode, (w, h), color)` | `Image.new(mode, w, h, color)` (also `Image.new(mode, {w, h}, color)`); color: number for L, `{r,g,b[,a]}`; default 0 |
| `Image.frombytes(mode, (w, h), b)` | `Image.frombytes(mode, w, h, b)` |
| `im.tobytes()` | `im:tobytes()` |
| `im.copy()` | `im:copy()` |
| `im.size`, `.width`, `.height`, `.mode` | `im.size` (`{w, h}`), `im.width`, `im.height`, `im.mode` |
| `im.crop((x0, y0, x1, y1))` | `im:crop({x0, y0, x1, y1})` (outside reads 0) |
| `im.paste(src, (x, y)[, mask])` | `im:paste(src, {x, y}[, mask])`; mask L or RGBA (alpha); 4-tuple box; colour source |
| `px = im.load(); px[x, y]` | `im:get(x, y)` -> r, g, b, a (multiple values) |
| `px[x, y] = (r, g, b, a)` | `im:put(x, y, r, g, b, a)` |
| `im.getpixel((x, y))` | `im:getpixel(x, y)` -> `{r, g, b, a}` / L value |
| `im.putpixel((x, y), v)` | `im:putpixel(x, y, v)` |
| `px[x, y][:3]` | `im:getrgb(x, y)` (packed rgb); alpha `im:getalpha(x, y)` |
| `im.getdata()` | `im:getdata()` -> 1-based array of PACKED pixels |
| `im.putdata(seq)` | `im:putdata(seq)` (packed values or tables) |
| `im.convert("RGB"/"RGBA"/"L")` | `im:convert(...)` |
| `im.getchannel("A")` | `im:getchannel("A")` |
| `im.split()` | `im:split()` -> `{r, g, b}` |
| `im.point(fn)` | `im:point(fn)` |
| `im.getbbox()` | `im:getbbox()` -> `{x0, y0, x1, y1}` or nil (RGBA: alpha only) |
| `im.histogram()` | `im:histogram()` -> 1-based: `h[255]` is `h[256]` |
| `im.filter(ImageFilter.MinFilter(3))` | `im:filter(Image.ImageFilter.MinFilter(3))` |
| `im.resize((w, h), Image.NEAREST)` | `im:resize(w, h, Image.NEAREST)` |
| `ImageChops.lighter/darker/difference/multiply/subtract/add/invert` | `Image.ImageChops.*` |
| `Image.open(png)` | `Image.open(bytes, inflate)` (8-bit and palette PNGs, no interlace) |
| `im.save`, `ImageDraw` | not ported: preview/debug paths only; `save` raises |

Buffers are FFI `uint8_t[]` whenever the FFI exists (JIT on or off), plain
0-based tables otherwise; `Image.NO_FFI = true` forces tables (the same for
`gen_voxel_relief_pyx` grids, `pyx.NO_FFI`). Interpreted cdata indexing is
about 2x slower than a table's, but a table costs 8 bytes a channel and the
GC time on table pixels outweighs it: with the JIT off, FFI buffers made
buildings faster (342 -> 255 s) and halved the bake's memory. See "Memory". 40 cases (paste with masks and clipping,
crop out of bounds, all conversions, bbox, chops, MinFilter, point,
histogram, resize, split, putpixel) match Pillow byte for byte on both
backends (`lua_test unit:unit_image.lua`).

## Recipe and what ships

The release's `emerald3ds.recipe` is LZMA. Rather than a Lua LZMA decoder,
`recipes/<code>.vtree` ships the part the voxel tree needs, converted once
(`scratch_claude/e3ds_port/tools/convert_recipe.py`): the 2202 `inputs`
entries (only `C` and `Z` ops: ROM offsets, sizes, CRCs) and `vtree` (decomp
symbol names, file paths, the ROM offsets of the layout and map tables, the
behaviour enum). The converter checks that no input references the literal
pool: the files hold no game bytes of any kind. About 51 KB each, four
languages (picked by the ROM's game code at 0xAC). `recipe.load(blob,
inflate)` reads one; `build_entry` checks every file's size and CRC-32, so a
wrong or modified ROM fails loudly.

## Assets (fetched, never shipped)

The generators read two files of Emerald 3DS's own (MIT, its author's), not
the cartridge's. `Bake.ASSETS`, at `Bake.ASSET_COMMIT` (the dev checkout's
HEAD, 3a1afea3409e44715d5b3a36dde6d4410b587341), from
`https://raw.githubusercontent.com/ZallaxDev/emerald-3ds/<commit>/<path>`:

* `3ds_port/assets/voxel/relief_fixes.json` (about 880 KB): hand fixes the
  relief and building generators apply;
* `3ds_port/src/voxel/voxel_regions.h` (2 KB): the `VOXEL_ROLE_*` numbers.

(`interior_lint_allow.toml` is only read by the building generator's lint,
which `--output` does not run.) The six tree PNGs the mod draws are listed in
`Bake.TREES` at `Bake.TREE_COMMIT` (bake.py's pin).

`Bake.fetcher{http = fn(url) -> bytes, cache_read = fn(key), cache_write =
fn(key, bytes)}` builds the fetch function: cache first (key
`<commit>/<path>`, e.g. save dir `e3ds_voxel/cache/`), then HTTP. Phase 3
plugs the game's HTTP in; tests pass a function reading the local checkout.

## Test harness

`G:/Gen2Recomped/scratch_claude/e3ds_port/lua_test` (a LÖVE project):

```
export TMP=G:/Gen2Recomped/scratch_claude/tmp TEMP=G:/Gen2Recomped/scratch_claude/tmp
cd G:/Gen2Recomped/scratch_claude/e3ds_port/lua_test
"C:/Program Files/LOVE/lovec.exe" . tree regions signposts layouts [--nojit]
"C:/Program Files/LOVE/lovec.exe" . unit:unit_image.lua
"C:/Program Files/LOVE/lovec.exe" . relief            # once ported
```

`tree` diffs the Lua tree against the golden Python work tree
(`golden/e3ds-voxel-*/tree`), each step diffs its `.bin` with `golden/out`
(a differing output is written to `e3ds_port/lua_test_<name>.bin`),
`unit:<file>` runs a Lua file as `chunk(V, tree, say)`. `RESULT_FILE=path`
also writes the log there.

For intermediates, run the Python modules on the golden tree itself: the
golden work tree holds the scripts in `tree/3ds_port/scripts`, so
`sys.path.insert(0, ".../tree/3ds_port/scripts"); import voxel_building`
reads that tree as ROOT. Copy any script you instrument into your own
scratch folder first; never edit the checkouts or the golden tree.

## Timings (this machine)

| | Python | Lua, JIT on | Lua, JIT off |
|---|---|---|---|
| input tree | (part of 5 s) | 0.12 s | 0.2 s |
| regions | 32.8 s | 1.3 s | 2.6 s |
| signposts | 10.2 s | 1.0 s | 1.7 s |
| relief | 565 s | 69 s (84 s, 3a) | 119 s (237 s, 3a) |
| buildings | 556 s | 151 s (165 s, 3a) | 285 s (328 s, 3a) |

(3a: after the memory work, two bakes running side by side; JIT off now
uses FFI buffers and GC pause 100.)

Unit tests (`unit:<file>`): `unit_image.lua` (Pillow), `unit_num.lua`
(round/hypot/radians/f32 on 20k CPython values), `unit_libm.lua` (pow, sin,
cos, tan, atan2, asin, sum on 20k values), `unit_props_fixes.lua`,
`unit_vb_a.lua` and `unit_vb_b.lua` (voxel_building halves, replaying
recordings made by `e3ds_port/vb_a/record.py` and `vb_b/record.py`: a real
`gen_voxel_buildings.build_models()` run with the classes monkeypatched in
memory). All pass with the JIT on and off, except 21 synthetic
`_plan_normal` cases in vb_a that differ only in the sign of a zero
(int-vs-float -0.0; never reached by the real run).

## Memory (phase 3a: phones run the bake with the JIT off)

Peak memory of the whole `Bake.run`, this machine, JIT off (private bytes;
Lua heap sampled every 1M VM instructions):

| | before | after |
|---|---|---|
| relief step | 2.75 GB (heap 2.53 GB) | 465 MB (heap 425 MB) |
| buildings step | 2.6 GB (heap 2.42 GB) | ~520 MB, ~600 at the end (heap 480 MB) |
| whole bake, harness `all` | 2.68 GB (heap 2.53 GB), 507 s | 604 MB (heap 482 MB), 572 s |
| whole bake, `Bake.run` | -- | 655 MB (heap 498 MB), 567 s |
| whole bake, `Bake.run` streaming (`opts.open`) | 655 MB | 508 MB (heap 481 MB), 536 s |

JIT on: 1.75 GB -> 821 MB, 248 -> 254 s.

What does it (every output still byte-identical, JIT on and off):

* **FFI pixel/grid buffers with the JIT off** (Image.lua, pyx grids): the
  biggest single win (about -1 GB per step).
* **`Bake.release()` between steps** (Bake.run calls it): `jit.flush()` +
  full collect. JIT traces keep their constants -- the modules' tables, so
  every memo of a finished step -- alive: 600-700 MB stayed reachable after
  relief with the JIT on. A no-op flush with the JIT off.
* **GC**: relief and buildings `main` run at `setpause(M.GC_PAUSE)`
  (restored after): 100 with the JIT off; with the JIT on 200 / 110 as
  before (pause 100 cost the JIT-on bake ~30% time). Stepmul 400 cut the peak only ~6% for +15% time: left
  at 200 (`M.GC_STEPMUL`).
* **Relief**: `drawn_prepare` keeps only the cell-centre values of
  `prep.region` (the only later reader, `voxel_terraces.region_ties`;
  `M.KEEP_PREP_REGION = true` keeps the grid for unit_relief_ra);
  `solve_drawn` drops its group's `_PREP` once `world_levels` is done;
  `M.release_export_state()` after export drops `_PREP`, `_DRAWN`,
  `_SHIFT`, `_ROCK`, `_CELLS`, `_DRAWN_SIDE` (checked: nothing reads them
  after export; `_ART` is reread and stays); `voxel_terraces.pixel_classes`
  grids share equal rows (`T.ROWS`).
* **Buildings**: `build_models` drops each model's `prisms` (nothing after
  `Model()` reads them; ~400 MB); `M.release_build_state(models)` before
  export drops `_PIECES`, `_CELL_KEYS`, `_expanded`, `spec.art`, the
  LayoutArt and voxel_props subtile memos; export computes the bridge
  deck table first and drops `voxel_bridge._READ`, drops `m.layout` after a
  model's placements and `_LAYOUT_ART` + LayoutArt memos after all of
  them, and releases the models before assembling the file;
  `register_piece` stores a cell's wanted pixels flat (`{o1, rgb1, ...}`).
* **Bounded pure caches**: `voxel_building.SUBTILES_KEPT` (4096
  `LayoutArt:subtiles` entries) and `voxel_props.SUBS_KEPT` (16 layouts):
  past the cap the memo starts over (only time changes).

Knobs (module fields, defaults shown): `voxel_building.SUBTILES_KEPT`,
`voxel_props.SUBS_KEPT`, `gen_voxel_relief.GC_PAUSE/GC_STEPMUL`,
`gen_voxel_buildings.GC_PAUSE/GC_STEPMUL`. Bake.run's signature and
outputs are unchanged; `Bake.release()` is new and public.

Streaming the outputs (`opts.open`, see Pipeline) removed the last
~130 MB: assembling buildings.bin as one 35 MB string (plus table.concat's
growing buffer; LuaJIT allocates big strings outside the freed heap). The
peak is now the building specs' expansion (interior_specs, heap ~480 MB).
During the build `_PIECES` (pixel sets, ~70 MB) and the bridges
(~60 MB) are the largest live state. Measuring: the harness copy in
`scratch_claude/e3ds_port/memory/harness` (`bakerun` step = Bake.run end to
end with a memory timeline; `--sink` streams the outputs to
`memory/sink_out/*.part` and compares those; `--tables` forces table
buffers), `memprof.lua`
and the `hook_*.lua` STEP_HOOK scripts there.

## Notes for phase 2 (relief, buildings)

**Shared modules you build on** (all `S.import`): `voxel_art`,
`voxel_cells`, `dump_region_art`, `voxel_props`, `voxel_relief_fixes`,
`voxel_sign_mask`, `voxel_building`. Read the header comment of each for its
Lua shapes; the important ones:

* `voxel_building`: a vertex is `{x, y, z, u, v}` (shared between
  triangles: never mutate); `Mesh.tris` is an array of `{{a, b, c}, shade,
  tag}`; `triangulate` returns Python's 0-based indices; `Prism.edges` is
  keyed by 0-based edge index; `Strip`'s `repeat` field is `s["repeat"]`;
  keyword arguments are positional in Python's order (nil = default), and
  part B's classes also take one plain table of keywords in place of the
  first optional argument; static methods are dot calls
  (`M.Mound.with_ring(...)`, `M.PlanPrism._tri(...)`); `LayoutArt` is a
  `py.class` (relief's `AliasArt` can subclass it); `cell_image` returns a
  copy; `subtiles(m, layer)` is up to 4 blocks `{rgb = 0-based 64, idx =
  0-based 64}`; `Raster.color/depth/owner` are 1-based, owner `false` for
  None; read and assign `M.HEIGHTSOLID_LOD` through the module.
  `VoxelLathe.cards` emulates CPython's set iteration order (xxHash tuple
  hash) to break ties; nothing else in voxel_building depends on set order.
* `voxel_cells`: positions keyed `pk(x, y)`; `Layout:metatile` is nil off
  the map; `ROCK_ALL` (packed rgb) is gen_voxel_relief's set: export the
  same table from gen_voxel_relief.lua (`M.ROCK_ALL = voxel_cells.ROCK_ALL`).
* `voxel_relief_fixes`: cells keyed `ck(x, y) = y*256 + x`, cuts keyed
  `cutkey(lay, x, y)`; both sort numerically as Python sorts the tuples.
  `seam_eases` (called by `pack`) does `S.import("gen_voxel_relief")
  .map_links()`: return an array of `{a, b, direction, offset}`.
  `apply_file(path)` rewrites the file in the tree.
* `voxel_props`: `find` returns `{name, sx, sy, present}` with `present`
  keyed `py.key(i, j)`; `cells_in` returns `{[py.key(x, y)] = {x, y,
  names}}`; `connections()` emulates Windows' `os.listdir` order of
  data/maps (case-insensitive) since `beyond` takes the first match.
  Use `voxel_props._listdir_ntfs` wherever a generator iterates
  `os.listdir` unsorted and the order can reach the output.

**Relief: done.** Shapes and conventions are in the headers of
`gen_voxel_relief*.lua` / `voxel_terraces*.lua` and in
`scratch_claude/e3ds_port/relief/PLAN.md` (positions are `pyx.xy` numbers,
dicts `pyx.odict`, sets `pyx.xyset`/`pyx.set` wherever CPython's order can
show). The golden relief ran before buildings.bin existed, so
`voxel_terraces.modelled` finds no buildings.bin and returns {}; keep the
step order (relief before buildings) or the output changes. Unit tests:
`unit_pyx.lua`, `unit_relief_found.lua`, `unit_relief_ra/rb/ta/tb/tc.lua`
(replaying recordings under `e3ds_port/relief/`). No shared core file was
changed for phase 2 (relief). The original notes:

**Relief** (`gen_voxel_relief.py` 4331 lines) imports `voxel_building`,
`voxel_cells`, `voxel_props`, `voxel_relief_fixes`, `voxel_sign_mask`, and
on its main path `voxel_terraces.py` (5014 lines; it imports
gen_voxel_relief back: import it lazily, inside functions, as Python does).
`main --output` = `export`, then `voxel_terraces.apply_file`,
`apply_sea_ramps`, `apply_cut_feet`, `voxel_relief_fixes.apply_file`, each
rereading the tree file. The `VOXEL_RELIEF_CACHE` pickle path and the
previews/proofs (`ImageDraw`) are developer-only: skip them. Module-level
`DRAWN = find_drawn()` runs at import (once per Session).

**Buildings** (`gen_voxel_buildings.py` 4417 lines) needs `voxel_bridge`
(2368), `voxel_building_specs` (7515, with lazy cycles into voxel_bridge),
`voxel_night` (100). With `--output` the checks/lint (`voxel_defect_scan`,
`tomllib`, `interior_lint_allow.toml`) do not run. `gen_voxel_buildings`
uses `ImageChops` (multiply, invert, lighter, difference, subtract),
`ImageFilter.MinFilter`, `getchannel/point/getbbox/histogram/split/
frombytes/putdata`: all in Image.lua and tested against Pillow.

**Buildings, as ported.** `lovec . buildings` is byte-identical (35,509,860
bytes). Shapes between the slices (specs, pieces, bridge block specs, model
fields) are in the file headers and in
`scratch_claude/e3ds_port/buildings/CONVENTIONS.md` (decisions log); each
slice's recorders/replays are there too (`specsA_`, `specsB_`, `specsC_`,
`bridge_`, `gen1_`, `gen2_`, `gen3_`). `gen_voxel_buildings_3.main` runs at
GC pause 100 (restored after). Memory: see "Memory" above (phase 3a).

**Verify** end to end with `lovec . relief` / `lovec . buildings` (the
harness writes a differing output to `e3ds_port/lua_test_<name>.bin`), and
narrow mismatches with recorded intermediates as vb_a/vb_b did.
