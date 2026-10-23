# Field-effect render checks

Run from the Gen2 checkout, with a clean pinned Gen1 checkout:

```sh
luajit tests/engine/field_effect_render_data.lua
luajit tests/engine/field_effect_resources.lua
python3 tools/field-effect-render-check/check.py --gen1 /absolute/gen1 --lua luajit
```

The checker drives the same mod entry through both real Loaders, using native
field state and native draw functions as independent geometry/pixel oracles.
It covers FireRed/Emerald, hold boundaries, invisible sparkle linger, grass
movement phases, cropped Gen1 feet covers, flips and fractional cameras. Use
`--api 3` against a Gen2 checkout also containing the separate API-3 PR series.
The Gen1 shim is explicitly a test reference; it imports no Gen2 implementation.

Run native GPU comparisons serially, from the engine selected by the backend:

```sh
FIELD_RENDER_ROOT=/absolute/gen2 FIELD_RENDER_BACKEND=gen2 \
  FIELD_RENDER_VERSION=firered FIELD_RENDER_REPORT=/tmp/field-gpu.json \
  love /absolute/gen2/tools/field-effect-render-check
```

For Gen1, change cwd to the pinned Gen1 checkout and use `FIELD_RENDER_BACKEND=gen1`.
`FIELD_RENDER_API` defaults to 2. `FIELD_RENDER_SHOT` optionally saves the final
comparison surface. Run both `firered` and `emerald`, with LÖVE 11/12 as available.
Gen2 GPU checks use the real production streaming reader. A separate QA identity
stages only the three synthetic fixture PNGs and removes them on success. The
engine's real ROM/import caches and saves are not used. No FPS claim is made.
