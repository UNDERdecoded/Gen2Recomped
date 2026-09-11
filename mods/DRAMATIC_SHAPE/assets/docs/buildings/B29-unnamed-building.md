# B29 - Unnamed building

![Unnamed building](img/B29_x6.png)

`OVERWORLD` tileset, **6 x 4 cells** (12 x 8 tiles of 8px, 96 x 64 px). Appears **1 time** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..6, y=1..4; tile column c=1..12, tile row r=1..8. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4   x5   x6 
      +-----+-----+-----+-----+-----+-----+
   y1 | A B | B B | B B | B B | B B | B C |
      | D E | E E | E E | E E | E E | E D |
      +-----+-----+-----+-----+-----+-----+
   y2 | D E | E E | E E | E E | E E | E D |
      | F G | G G | G G | G G | G G | G H |
      +-----+-----+-----+-----+-----+-----+
   y3 | I J | J J | K L | M K | J J | J N |
      | I O | O O | K K | K K | O O | O N |
      +-----+-----+-----+-----+-----+-----+
   y4 | I O | P Q | J J | J J | O O | O N |
      | R S | * T | S S | S S | S S | S U |
      +-----+-----+-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4       x5       x6   
      +---------+---------+---------+---------+---------+---------+
   y1 |  76  83 |  83  83 |  83  83 |  83  83 |  83  83 |  83  77 |
      |  90  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  90 |
      +---------+---------+---------+---------+---------+---------+
   y2 |  90  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  90 |
      |  92  23 |  23  23 |  23  23 |  23  23 |  23  23 |  23  93 |
      +---------+---------+---------+---------+---------+---------+
   y3 |  15  10 |  10  10 |  34  47 |  63  34 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  34  34 |  34  34 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+
   y4 |  15  75 |  11  12 |  10  10 |  10  10 |  75  75 |  75  31 |
      |  78  26 |  27  28 |  26  26 |  26  26 |  26  26 |  26  79 |
      +---------+---------+---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {  76,  83,  83,  83,  83,  83,  83,  83,  83,  83,  83,  77 },  -- r1
  {  90,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  90 },  -- r2
  {  90,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  90 },  -- r3
  {  92,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  93 },  -- r4
  {  15,  10,  10,  10,  34,  47,  63,  34,  10,  10,  10,  31 },  -- r5
  {  15,  75,  75,  75,  34,  34,  34,  34,  75,  75,  75,  31 },  -- r6
  {  15,  75,  11,  12,  10,  10,  10,  10,  75,  75,  75,  31 },  -- r7
  {  78,  26,  27,  28,  26,  26,  26,  26,  26,  26,  26,  79 },  -- r8
}
```

## Legend

_Legend pending._

- `*` = tile 27, used 1x
- `A` = tile 76, used 1x
- `B` = tile 83, used 10x
- `C` = tile 77, used 1x
- `D` = tile 90, used 4x
- `E` = tile 18, used 20x
- `F` = tile 92, used 1x
- `G` = tile 23, used 10x
- `H` = tile 93, used 1x
- `I` = tile 15, used 3x
- `J` = tile 10, used 10x
- `K` = tile 34, used 6x
- `L` = tile 47, used 1x
- `M` = tile 63, used 1x
- `N` = tile 31, used 3x
- `O` = tile 75, used 10x
- `P` = tile 11, used 1x
- `Q` = tile 12, used 1x
- `R` = tile 78, used 1x
- `S` = tile 26, used 8x
- `T` = tile 28, used 1x
- `U` = tile 79, used 1x

![distinct tiles](img/B29_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y4   SOLID  DOOR   SOLID  SOLID  SOLID  SOLID
```

Enterable cell: (2,4).

## Silhouette

258 of the 6144 px inside the box are ground outside the black outline, so the 96x64 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:25px, c12:25px
    r2   c1:24px, c12:24px
    r3   c1:24px, c12:24px
    r4   c1:24px, c12:24px
    r5   c1:8px, c12:8px
    r6   c1:8px, c12:8px
    r7   c1:8px, c12:8px
    r8   c1:8px, c12:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| FUCHSIA_CITY | (4,24) | (5,27) | `FUCHSIA_GYM` |
