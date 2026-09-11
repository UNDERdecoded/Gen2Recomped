# B08 - Unnamed building

![Unnamed building](img/B08_x10.png)

`OVERWORLD` tileset, **4 x 6 cells** (8 x 12 tiles of 8px, 64 x 96 px). Appears **6 times** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..4, y=1..6; tile column c=1..8, tile row r=1..12. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

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
   y4 | I J | J J | J J | J K |
      | I L | L L | L L | L K |
      +-----+-----+-----+-----+
   y5 | I J | J J | J J | J K |
      | I L | L L | L L | L K |
      +-----+-----+-----+-----+
   y6 | I L | L L | L L | L K |
      | M N | N N | N N | N O |
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
   y4 |  15  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+
   y5 |  15  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+
   y6 |  15  75 |  75  75 |  75  75 |  75  31 |
      |  78  26 |  26  26 |  26  26 |  26  79 |
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
  {  15,  10,  10,  10,  10,  10,  10,  31 },  -- r7
  {  15,  75,  75,  75,  75,  75,  75,  31 },  -- r8
  {  15,  10,  10,  10,  10,  10,  10,  31 },  -- r9
  {  15,  75,  75,  75,  75,  75,  75,  31 },  -- r10
  {  15,  75,  75,  75,  75,  75,  75,  31 },  -- r11
  {  78,  26,  26,  26,  26,  26,  26,  79 },  -- r12
}
```

## Legend

_Legend pending._

- `A` = tile 76, used 1x
- `B` = tile 83, used 6x
- `C` = tile 77, used 1x
- `D` = tile 90, used 4x
- `E` = tile 18, used 12x
- `F` = tile 92, used 1x
- `G` = tile 23, used 6x
- `H` = tile 93, used 1x
- `I` = tile 15, used 7x
- `J` = tile 10, used 18x
- `K` = tile 31, used 7x
- `L` = tile 75, used 24x
- `M` = tile 78, used 1x
- `N` = tile 26, used 6x
- `O` = tile 79, used 1x

![distinct tiles](img/B08_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID
    y4   SOLID  SOLID  SOLID  SOLID
    y5   SOLID  SOLID  SOLID  SOLID
    y6   SOLID  SOLID  SOLID  SOLID
```

Every cell is solid - this building has no door of its own.

## Silhouette

322 of the 6144 px inside the box are ground outside the black outline, so the 64x96 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:25px, c8:25px
    r2   c1:24px, c8:24px
    r3   c1:24px, c8:24px
    r4   c1:24px, c8:24px
    r5   c1:8px, c8:8px
    r6   c1:8px, c8:8px
    r7   c1:8px, c8:8px
    r8   c1:8px, c8:8px
    r9   c1:8px, c8:8px
    r10  c1:8px, c8:8px
    r11  c1:8px, c8:8px
    r12  c1:8px, c8:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| CELADON_CITY | (2,4) | - | scenery, no entrance |
| SAFFRON_CITY | (6,16) | - | scenery, no entrance |
| SAFFRON_CITY | (10,16) | - | scenery, no entrance |
| SAFFRON_CITY | (24,16) | - | scenery, no entrance |
| SAFFRON_CITY | (28,16) | - | scenery, no entrance |
| SAFFRON_CITY | (32,16) | - | scenery, no entrance |
