# B26 - Unnamed building

![Unnamed building](img/B26_x6.png)

`OVERWORLD` tileset, **6 x 6 cells** (12 x 12 tiles of 8px, 96 x 96 px). Appears **1 time** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..6, y=1..6; tile column c=1..12, tile row r=1..12. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4   x5   x6 
      +-----+-----+-----+-----+-----+-----+
   y1 | A B | C C | C C | C C | C C | D E |
      | F G | H H | H H | H H | H H | G I |
      +-----+-----+-----+-----+-----+-----+
   y2 | F G | H H | H H | H H | H H | G I |
      | F J | K K | K K | K K | K K | L I |
      +-----+-----+-----+-----+-----+-----+
   y3 | F G | H H | H H | H H | H H | G I |
      | F G | H H | H H | H H | H H | G I |
      +-----+-----+-----+-----+-----+-----+
   y4 | F J | K K | K K | K K | K K | L I |
      | M N | O O | O O | O O | O O | P Q |
      +-----+-----+-----+-----+-----+-----+
   y5 | R S | S S | S S | S S | S S | S T |
      | R U | U U | U U | U U | U U | U T |
      +-----+-----+-----+-----+-----+-----+
   y6 | R S | S S | S S | S S | S S | S T |
      | R U | U U | U U | U U | U U | U T |
      +-----+-----+-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4       x5       x6   
      +---------+---------+---------+---------+---------+---------+
   y1 |   5   6 |  83  83 |  83  83 |  83  83 |  83  83 |   8   9 |
      |  21  56 |  18  18 |  18  18 |  18  18 |  18  18 |  56  25 |
      +---------+---------+---------+---------+---------+---------+
   y2 |  21  56 |  18  18 |  18  18 |  18  18 |  18  18 |  56  25 |
      |  21  22 |  23  23 |  23  23 |  23  23 |  23  23 |  24  25 |
      +---------+---------+---------+---------+---------+---------+
   y3 |  21  56 |  18  18 |  18  18 |  18  18 |  18  18 |  56  25 |
      |  21  56 |  18  18 |  18  18 |  18  18 |  18  18 |  56  25 |
      +---------+---------+---------+---------+---------+---------+
   y4 |  21  22 |  23  23 |  23  23 |  23  23 |  23  23 |  24  25 |
      |  37  38 |  34  34 |  34  34 |  34  34 |  34  34 |  40  41 |
      +---------+---------+---------+---------+---------+---------+
   y5 |  15  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+
   y6 |  15  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {   5,   6,  83,  83,  83,  83,  83,  83,  83,  83,   8,   9 },  -- r1
  {  21,  56,  18,  18,  18,  18,  18,  18,  18,  18,  56,  25 },  -- r2
  {  21,  56,  18,  18,  18,  18,  18,  18,  18,  18,  56,  25 },  -- r3
  {  21,  22,  23,  23,  23,  23,  23,  23,  23,  23,  24,  25 },  -- r4
  {  21,  56,  18,  18,  18,  18,  18,  18,  18,  18,  56,  25 },  -- r5
  {  21,  56,  18,  18,  18,  18,  18,  18,  18,  18,  56,  25 },  -- r6
  {  21,  22,  23,  23,  23,  23,  23,  23,  23,  23,  24,  25 },  -- r7
  {  37,  38,  34,  34,  34,  34,  34,  34,  34,  34,  40,  41 },  -- r8
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  31 },  -- r9
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r10
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  31 },  -- r11
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r12
}
```

## Legend

_Legend pending._

- `A` = tile 5, used 1x
- `B` = tile 6, used 1x
- `C` = tile 83, used 8x
- `D` = tile 8, used 1x
- `E` = tile 9, used 1x
- `F` = tile 21, used 6x
- `G` = tile 56, used 8x
- `H` = tile 18, used 32x
- `I` = tile 25, used 6x
- `J` = tile 22, used 2x
- `K` = tile 23, used 16x
- `L` = tile 24, used 2x
- `M` = tile 37, used 1x
- `N` = tile 38, used 1x
- `O` = tile 34, used 8x
- `P` = tile 40, used 1x
- `Q` = tile 41, used 1x
- `R` = tile 15, used 4x
- `S` = tile 10, used 20x
- `T` = tile 31, used 4x
- `U` = tile 75, used 20x

![distinct tiles](img/B26_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y4   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y5   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y6   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
```

Every cell is solid - this building has no door of its own.

## Silhouette

1170 of the 9216 px inside the box are ground outside the black outline, so the 96x96 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:48px, c2:16px, c11:16px, c12:48px
    r8   c1:6px, c2:23px, c3:24px, c4:24px, c5:24px, c6:24px, c7:24px, c8:24px, c9:24px, c10:24px, c11:23px, c12:6px
    r9   c1:24px, c12:24px
    r10  c1:24px, c2:30px, c3:30px, c4:30px, c5:30px, c6:30px, c7:30px, c8:30px, c9:30px, c10:30px, c11:30px, c12:24px
    r11  c1:24px, c12:24px
    r12  c1:24px, c2:30px, c3:30px, c4:30px, c5:30px, c6:30px, c7:30px, c8:30px, c9:30px, c10:30px, c11:30px, c12:24px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| ROUTE_10 | (12,66) | - | scenery, no entrance |
