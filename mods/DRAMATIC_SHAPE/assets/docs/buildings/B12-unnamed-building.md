# B12 - Unnamed building

![Unnamed building](img/B12_x10.png)

`FOREST` tileset, **4 x 2 cells** (8 x 4 tiles of 8px, 64 x 32 px). Appears **5 times** in the game. Tile ids index `assets/generated/tilesets/forest.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..4, y=1..2; tile column c=1..8, tile row r=1..4. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4 
      +-----+-----+-----+-----+
   y1 | A B | B B | B B | B C |
      | D E | E E | E E | E F |
      +-----+-----+-----+-----+
   y2 | G H | I J | K K | H L |
      | M H | * N | H H | H O |
      +-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4   
      +---------+---------+---------+---------+
   y1 |   8   9 |   9   9 |   9   9 |   9  12 |
      |  24  25 |  25  25 |  25  25 |  25  28 |
      +---------+---------+---------+---------+
   y2 |  40  41 |  42  43 |   1   1 |  41  44 |
      |  56  41 |  58  59 |  41  41 |  41  60 |
      +---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {   8,   9,   9,   9,   9,   9,   9,  12 },  -- r1
  {  24,  25,  25,  25,  25,  25,  25,  28 },  -- r2
  {  40,  41,  42,  43,   1,   1,  41,  44 },  -- r3
  {  56,  41,  58,  59,  41,  41,  41,  60 },  -- r4
}
```

## Legend

_Legend pending._

- `*` = tile 58, used 1x
- `A` = tile 8, used 1x
- `B` = tile 9, used 6x
- `C` = tile 12, used 1x
- `D` = tile 24, used 1x
- `E` = tile 25, used 6x
- `F` = tile 28, used 1x
- `G` = tile 40, used 1x
- `H` = tile 41, used 6x
- `I` = tile 42, used 1x
- `J` = tile 43, used 1x
- `K` = tile 1, used 2x
- `L` = tile 44, used 1x
- `M` = tile 56, used 1x
- `N` = tile 59, used 1x
- `O` = tile 60, used 1x

![distinct tiles](img/B12_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID
    y2   SOLID  DOOR   SOLID  SOLID
```

Enterable cell: (2,2).

## Silhouette

101 of the 2048 px inside the box are ground outside the black outline, so the 64x32 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:17px, c8:17px
    r2   c1:16px, c8:17px
    r3   c1:10px, c8:8px
    r4   c1:8px, c8:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| SAFARI_ZONE_CENTER | (16,18) | (17,19) | `SAFARI_ZONE_CENTER_REST_HOUSE` |
| SAFARI_ZONE_EAST | (24,8) | (25,9) | `SAFARI_ZONE_EAST_REST_HOUSE` |
| SAFARI_ZONE_NORTH | (34,2) | (35,3) | `SAFARI_ZONE_NORTH_REST_HOUSE` |
| SAFARI_ZONE_WEST | (2,2) | (3,3) | `SAFARI_ZONE_SECRET_HOUSE` |
| SAFARI_ZONE_WEST | (10,10) | (11,11) | `SAFARI_ZONE_WEST_REST_HOUSE` |
