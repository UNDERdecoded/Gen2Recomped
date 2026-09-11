# B18 - Unnamed building

![Unnamed building](img/B18_x6.png)

`OVERWORLD` tileset, **6 x 4 cells** (12 x 8 tiles of 8px, 96 x 64 px). Appears **2 times** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

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
   y3 | I J | J J | J J | J J | J J | J K |
      | I L | L L | L L | L L | L L | L K |
      +-----+-----+-----+-----+-----+-----+
   y4 | I L | M N | L L | L L | L L | L K |
      | O P | * Q | P P | P P | P P | P R |
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
   y3 |  15  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+
   y4 |  15  75 |  11  12 |  75  75 |  75  75 |  75  75 |  75  31 |
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
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  31 },  -- r5
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r6
  {  15,  75,  11,  12,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r7
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
- `K` = tile 31, used 3x
- `L` = tile 75, used 18x
- `M` = tile 11, used 1x
- `N` = tile 12, used 1x
- `O` = tile 78, used 1x
- `P` = tile 26, used 8x
- `Q` = tile 28, used 1x
- `R` = tile 79, used 1x

![distinct tiles](img/B18_atlas.png)

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
| PEWTER_CITY | (18,2) | (19,5) | `MUSEUM_1F` |
| ROUTE_2 | (14,36) | (15,39) | `ROUTE_2_GATE` |
