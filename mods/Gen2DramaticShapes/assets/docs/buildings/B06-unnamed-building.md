# B06 - Unnamed building

![Unnamed building](img/B06_x10.png)

`OVERWORLD` tileset, **4 x 4 cells** (8 x 8 tiles of 8px, 64 x 64 px). Appears **8 times** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..4, y=1..4; tile column c=1..8, tile row r=1..8. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4 
      +-----+-----+-----+-----+
   y1 | A B | B B | B B | B C |
      | D E | E E | E E | E D |
      +-----+-----+-----+-----+
   y2 | D E | E E | E E | E D |
      | F G | G G | G G | G H |
      +-----+-----+-----+-----+
   y3 | I J | J J | J J | J K |
      | I L | L L | L L | L K |
      +-----+-----+-----+-----+
   y4 | I L | M N | O P | L K |
      | Q R | * S | T T | R U |
      +-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4   
      +---------+---------+---------+---------+
   y1 |  76  83 |  83  83 |  83  83 |  83  77 |
      |  90  18 |  18  18 |  18  18 |  18  90 |
      +---------+---------+---------+---------+
   y2 |  90  18 |  18  18 |  18  18 |  18  90 |
      |  92  23 |  23  23 |  23  23 |  23  93 |
      +---------+---------+---------+---------+
   y3 |  15  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+
   y4 |  15  75 |  11  12 |  68  69 |  75  31 |
      |  78  26 |  27  28 |  74  74 |  26  79 |
      +---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {  76,  83,  83,  83,  83,  83,  83,  77 },  -- r1
  {  90,  18,  18,  18,  18,  18,  18,  90 },  -- r2
  {  90,  18,  18,  18,  18,  18,  18,  90 },  -- r3
  {  92,  23,  23,  23,  23,  23,  23,  93 },  -- r4
  {  15,  10,  10,  10,  10,  10,  10,  31 },  -- r5
  {  15,  75,  75,  75,  75,  75,  75,  31 },  -- r6
  {  15,  75,  11,  12,  68,  69,  75,  31 },  -- r7
  {  78,  26,  27,  28,  74,  74,  26,  79 },  -- r8
}
```

## Legend

_Legend pending._

- `*` = tile 27, used 1x
- `A` = tile 76, used 1x
- `B` = tile 83, used 6x
- `C` = tile 77, used 1x
- `D` = tile 90, used 4x
- `E` = tile 18, used 12x
- `F` = tile 92, used 1x
- `G` = tile 23, used 6x
- `H` = tile 93, used 1x
- `I` = tile 15, used 3x
- `J` = tile 10, used 6x
- `K` = tile 31, used 3x
- `L` = tile 75, used 8x
- `M` = tile 11, used 1x
- `N` = tile 12, used 1x
- `O` = tile 68, used 1x
- `P` = tile 69, used 1x
- `Q` = tile 78, used 1x
- `R` = tile 26, used 2x
- `S` = tile 28, used 1x
- `T` = tile 74, used 2x
- `U` = tile 79, used 1x

![distinct tiles](img/B06_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID
    y4   SOLID  DOOR   SOLID  SOLID
```

Enterable cell: (2,4).

## Silhouette

258 of the 4096 px inside the box are ground outside the black outline, so the 64x64 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:25px, c8:25px
    r2   c1:24px, c8:24px
    r3   c1:24px, c8:24px
    r4   c1:24px, c8:24px
    r5   c1:8px, c8:8px
    r6   c1:8px, c8:8px
    r7   c1:8px, c8:8px
    r8   c1:8px, c8:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| CERULEAN_CITY | (24,22) | (25,25) | `CERULEAN_MART` |
| CINNABAR_ISLAND | (14,8) | (15,11) | `CINNABAR_MART` |
| FUCHSIA_CITY | (4,10) | (5,13) | `FUCHSIA_MART` |
| LAVENDER_TOWN | (14,10) | (15,13) | `LAVENDER_MART` |
| PEWTER_CITY | (22,14) | (23,17) | `PEWTER_MART` |
| SAFFRON_CITY | (24,8) | (25,11) | `SAFFRON_MART` |
| VERMILION_CITY | (22,10) | (23,13) | `VERMILION_MART` |
| VIRIDIAN_CITY | (28,16) | (29,19) | `VIRIDIAN_MART` |
