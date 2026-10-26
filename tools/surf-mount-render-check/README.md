# Cross-engine surf-mount contract checks

From Gen2, with a clean pinned Gen1 reference checkout:

```sh
luajit tests/engine/surf_mount_render_data.lua
luajit tests/engine/surf_mount_clock.lua
luajit tests/engine/surf_mount_resources.lua
python3 tools/surf-mount-render-check/check.py --gen1 /absolute/gen1 --lua luajit
```

`--api 3` additionally requires the existing API-3 proposal in Gen2. The same
public-only example entry is loaded by both real Loaders. Gen1's documented shim
is a test-only host extension, with no Gen2 implementation imports. Each host's
resolved image pixels and geometry are compared with its native drawing rather
than requiring different native art/animations to become identical.

Native GPU checks run from the selected engine checkout:

```sh
SURF_RENDER_ROOT=/absolute/gen2 SURF_RENDER_BACKEND=gen2 \
  SURF_RENDER_VERSION=firered SURF_RENDER_REPORT=/tmp/surf-gpu.json \
  love /absolute/gen2/tools/surf-mount-render-check
```

Use `gen1` from the pinned Gen1 cwd for that backend; test `firered` and `emerald`.
`SURF_RENDER_API` defaults to 2; LÖVE 11 and 12 are supported. If the actor contract
and its example exist on the integrated Gen2 checkout, the driver additionally
compares public rider-plus-mount composition with native Player drawing. The
mount-only checks exercise fractional cameras separately from the actor v1
floor-before-camera convention.

The driver stages only three synthetic PNGs in its dedicated QA identity and
removes them on success. Gen2 uses the production source streamer. Optional
`SURF_RENDER_SHOT` saves a visible sample. Real ROM/import caches and saves are
not used. The deterministic time fixture affects only this QA process.
