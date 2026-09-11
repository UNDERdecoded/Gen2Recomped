# B24 - Unnamed building

![Unnamed building](img/B24_x5.png)

`OVERWORLD` tileset, **8 x 6 cells** (16 x 12 tiles of 8px, 128 x 96 px). Appears **1 time** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..8, y=1..6; tile column c=1..16, tile row r=1..12. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4   x5   x6   x7   x8 
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y1 | A B | C C | C C | C C | C C | C C | C C | D E |
      | F G | H H | H H | H H | H H | H H | H H | G I |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y2 | F G | H H | H H | H H | H H | H H | H H | G I |
      | F J | K K | K K | K K | K K | K K | K K | L I |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y3 | F G | H H | H H | H H | H H | H H | H H | G I |
      | F G | H H | H H | H H | H H | H H | H H | G I |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y4 | F J | K K | K K | K K | K K | K K | K K | L I |
      | M N | O O | O O | O O | O O | O O | O O | P Q |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y5 | R S | S S | S S | S S | S T | T S | S S | S U |
      | R T | T T | T T | T T | T T | T T | T T | T U |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y6 | R T | T T | T T | T T | V W | S S | T T | T U |
      | X Y | Y Y | Y Y | Y Y | * Z | Y Y | Y Y | Y a |
      +-----+-----+-----+-----+-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4       x5       x6       x7       x8   
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y1 |   5   6 |  83  83 |  83  83 |  83  83 |  83  83 |  83  83 |  83  83 |   8   9 |
      |  21  56 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  56  25 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y2 |  21  56 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  56  25 |
      |  21  22 |  23  23 |  23  23 |  23  23 |  23  23 |  23  23 |  23  23 |  24  25 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y3 |  21  56 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  56  25 |
      |  21  56 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  18  18 |  56  25 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y4 |  21  22 |  23  23 |  23  23 |  23  23 |  23  23 |  23  23 |  23  23 |  24  25 |
      |  37  38 |  34  34 |  34  34 |  34  34 |  34  34 |  34  34 |  34  34 |  40  41 |
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
  {   5,   6,  83,  83,  83,  83,  83,  83,  83,  83,  83,  83,  83,  83,   8,   9 },  -- r1
  {  21,  56,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  56,  25 },  -- r2
  {  21,  56,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  56,  25 },  -- r3
  {  21,  22,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  24,  25 },  -- r4
  {  21,  56,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  56,  25 },  -- r5
  {  21,  56,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  56,  25 },  -- r6
  {  21,  22,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  24,  25 },  -- r7
  {  37,  38,  34,  34,  34,  34,  34,  34,  34,  34,  34,  34,  34,  34,  40,  41 },  -- r8
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  75,  75,  10,  10,  10,  10,  31 },  -- r9
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r10
  {  15,  75,  75,  75,  75,  75,  75,  75,  11,  12,  10,  10,  75,  75,  75,  31 },  -- r11
  {  78,  26,  26,  26,  26,  26,  26,  26,  27,  28,  26,  26,  26,  26,  26,  79 },  -- r12
}
```

## Legend

_Legend pending._

- `*` = tile 27, used 1x
- `A` = tile 5, used 1x
- `B` = tile 6, used 1x
- `C` = tile 83, used 12x
- `D` = tile 8, used 1x
- `E` = tile 9, used 1x
- `F` = tile 21, used 6x
- `G` = tile 56, used 8x
- `H` = tile 18, used 48x
- `I` = tile 25, used 6x
- `J` = tile 22, used 2x
- `K` = tile 23, used 24x
- `L` = tile 24, used 2x
- `M` = tile 37, used 1x
- `N` = tile 38, used 1x
- `O` = tile 34, used 12x
- `P` = tile 40, used 1x
- `Q` = tile 41, used 1x
- `R` = tile 15, used 3x
- `S` = tile 10, used 14x
- `T` = tile 75, used 26x
- `U` = tile 31, used 3x
- `V` = tile 11, used 1x
- `W` = tile 12, used 1x
- `X` = tile 78, used 1x
- `Y` = tile 26, used 12x
- `Z` = tile 28, used 1x
- `a` = tile 79, used 1x

![distinct tiles](img/B24_atlas.png)

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

202 of the 12288 px inside the box are ground outside the black outline, so the 128x96 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:48px, c2:16px, c15:16px, c16:48px
    r8   c1:5px, c16:5px
    r9   c1:8px, c16:8px
    r10  c1:8px, c16:8px
    r11  c1:8px, c16:8px
    r12  c1:8px, c16:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| PEWTER_CITY | (10,2) | (14,7) | `MUSEUM_1F` |
