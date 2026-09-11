# B25 - Unnamed building

![Unnamed building](img/B25_x5.png)

`OVERWORLD` tileset, **8 x 6 cells** (16 x 12 tiles of 8px, 128 x 96 px). Appears **1 time** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..8, y=1..6; tile column c=1..16, tile row r=1..12. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4   x5   x6   x7   x8 
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y1 | A B | B B | B B | B B | B B | B B | B B | B C |
      | D E | E E | E E | E E | E E | E E | E E | E D |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y2 | D E | E E | E E | E E | E E | E E | E E | E D |
      | F G | G G | G G | G G | G G | G G | G G | G H |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y3 | I J | J J | J J | J J | J J | J J | J J | J K |
      | I L | L L | L L | L L | L L | L L | L L | L K |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y4 | I J | J J | J J | J J | J J | J J | J J | J K |
      | I L | L L | L L | L L | L L | L L | L L | L K |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y5 | I J | J J | J J | J J | J L | L J | J J | J K |
      | I L | L L | L L | L L | L L | L L | L L | L K |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y6 | I L | L L | L L | L L | M N | J J | L L | L K |
      | O P | P P | P P | P P | * Q | P P | P P | P R |
      +-----+-----+-----+-----+-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4       x5       x6       x7       x8   
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y1 |  76  83 |  83  83 |  83  83 |  83  83 |  83  83 |  83  83 |  83  83 |  83  77 |
      |  90  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  90 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y2 |  90  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  90 |
      |  92  23 |  23  23 |  23  23 |  23  23 |  23  23 |  23  23 |  23  23 |  23  93 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y3 |  15  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y4 |  15  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y5 |  15  10 |  10  10 |  10  10 |  10  10 |  10  75 |  75  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y6 |  15  75 |  75  75 |  75  75 |  75  75 |  11  12 |  10  10 |  75  75 |  75  31 |
      |  78  26 |  26  26 |  26  26 |  26  26 |  27  28 |  26  26 |  26  26 |  26  79 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {  76,  83,  83,  83,  83,  83,  83,  83,  83,  83,  83,  83,  83,  83,  83,  77 },  -- r1
  {  90,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  90 },  -- r2
  {  90,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  90 },  -- r3
  {  92,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  93 },  -- r4
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  31 },  -- r5
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r6
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  31 },  -- r7
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r8
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  75,  75,  10,  10,  10,  10,  31 },  -- r9
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r10
  {  15,  75,  75,  75,  75,  75,  75,  75,  11,  12,  10,  10,  75,  75,  75,  31 },  -- r11
  {  78,  26,  26,  26,  26,  26,  26,  26,  27,  28,  26,  26,  26,  26,  26,  79 },  -- r12
}
```

## Legend

_Legend pending._

- `*` = tile 27, used 1x
- `A` = tile 76, used 1x
- `B` = tile 83, used 14x
- `C` = tile 77, used 1x
- `D` = tile 90, used 4x
- `E` = tile 18, used 28x
- `F` = tile 92, used 1x
- `G` = tile 23, used 14x
- `H` = tile 93, used 1x
- `I` = tile 15, used 7x
- `J` = tile 10, used 42x
- `K` = tile 31, used 7x
- `L` = tile 75, used 54x
- `M` = tile 11, used 1x
- `N` = tile 12, used 1x
- `O` = tile 78, used 1x
- `P` = tile 26, used 12x
- `Q` = tile 28, used 1x
- `R` = tile 79, used 1x

![distinct tiles](img/B25_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y4   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y5   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y6   SOLID  SOLID  SOLID  SOLID  DOOR   SOLID  SOLID  SOLID
```

Enterable cell: (5,6).

## Silhouette

322 of the 12288 px inside the box are ground outside the black outline, so the 128x96 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:25px, c16:25px
    r2   c1:24px, c16:24px
    r3   c1:24px, c16:24px
    r4   c1:24px, c16:24px
    r5   c1:8px, c16:8px
    r6   c1:8px, c16:8px
    r7   c1:8px, c16:8px
    r8   c1:8px, c16:8px
    r9   c1:8px, c16:8px
    r10  c1:8px, c16:8px
    r11  c1:8px, c16:8px
    r12  c1:8px, c16:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| ROUTE_10 | (2,34) | (6,39) | `POWER_PLANT` |
