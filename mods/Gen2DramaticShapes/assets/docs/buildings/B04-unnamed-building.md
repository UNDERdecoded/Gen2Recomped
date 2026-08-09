# B04 - Unnamed building

![Unnamed building](img/B04_x10.png)

`OVERWORLD` tileset, **4 x 2 cells** (8 x 4 tiles of 8px, 64 x 32 px). Appears **12 times** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..4, y=1..2; tile column c=1..8, tile row r=1..4. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4 
      +-----+-----+-----+-----+
   y1 | A B | C C | C C | D E |
      | F G | H H | H H | I J |
      +-----+-----+-----+-----+
   y2 | K L | M N | O O | P Q |
      | R S | * T | S S | S U |
      +-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4   
      +---------+---------+---------+---------+
   y1 |   5   6 |   7   7 |   7   7 |   8   9 |
      |  21  22 |  23  23 |  23  23 |  24  25 |
      +---------+---------+---------+---------+
   y2 |  37  38 |  11  12 |  10  10 |  40  41 |
      |  78  26 |  27  28 |  26  26 |  26  79 |
      +---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {   5,   6,   7,   7,   7,   7,   8,   9 },  -- r1
  {  21,  22,  23,  23,  23,  23,  24,  25 },  -- r2
  {  37,  38,  11,  12,  10,  10,  40,  41 },  -- r3
  {  78,  26,  27,  28,  26,  26,  26,  79 },  -- r4
}
```

## Legend

_Legend pending._

- `*` = tile 27, used 1x
- `A` = tile 5, used 1x
- `B` = tile 6, used 1x
- `C` = tile 7, used 4x
- `D` = tile 8, used 1x
- `E` = tile 9, used 1x
- `F` = tile 21, used 1x
- `G` = tile 22, used 1x
- `H` = tile 23, used 4x
- `I` = tile 24, used 1x
- `J` = tile 25, used 1x
- `K` = tile 37, used 1x
- `L` = tile 38, used 1x
- `M` = tile 11, used 1x
- `N` = tile 12, used 1x
- `O` = tile 10, used 2x
- `P` = tile 40, used 1x
- `Q` = tile 41, used 1x
- `R` = tile 78, used 1x
- `S` = tile 26, used 4x
- `T` = tile 28, used 1x
- `U` = tile 79, used 1x

![distinct tiles](img/B04_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID
    y2   SOLID  DOOR   SOLID  SOLID
```

Enterable cell: (2,2).

## Silhouette

154 of the 2048 px inside the box are ground outside the black outline, so the 64x32 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:48px, c2:16px, c7:16px, c8:48px
    r3   c1:5px, c8:5px
    r4   c1:8px, c8:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| FUCHSIA_CITY | (10,26) | (11,27) | `FUCHSIA_BILLS_GRANDPAS_HOUSE` |
| LAVENDER_TOWN | (6,8) | (7,9) | `MR_FUJIS_HOUSE` |
| LAVENDER_TOWN | (2,12) | (3,13) | `LAVENDER_CUBONE_HOUSE` |
| LAVENDER_TOWN | (6,12) | (7,13) | `NAME_RATERS_HOUSE` |
| PEWTER_CITY | (28,12) | (29,13) | `PEWTER_NIDORAN_HOUSE` |
| PEWTER_CITY | (6,28) | (7,29) | `PEWTER_SPEECH_HOUSE` |
| ROUTE_12 | (10,76) | (11,77) | `ROUTE_12_SUPER_ROD_HOUSE` |
| ROUTE_16 | (6,4) | (7,5) | `ROUTE_16_FLY_HOUSE` |
| ROUTE_2 | (14,18) | (15,19) | `ROUTE_2_TRADE_HOUSE` |
| ROUTE_8 | (12,2) | (13,3) | `UNDERGROUND_PATH_ROUTE_8` |
| VIRIDIAN_CITY | (20,8) | (21,9) | `VIRIDIAN_NICKNAME_HOUSE` |
| VIRIDIAN_CITY | (20,14) | (21,15) | `VIRIDIAN_SCHOOL_HOUSE` |
