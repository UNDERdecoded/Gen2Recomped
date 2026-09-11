# B33 - Unnamed building

![Unnamed building](img/B33_x10.png)

`OVERWORLD` tileset, **4 x 4 cells** (8 x 8 tiles of 8px, 64 x 64 px). Appears **1 time** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..4, y=1..4; tile column c=1..8, tile row r=1..8. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4 
      +-----+-----+-----+-----+
   y1 | A B | C C | C C | D E |
      | F G | H H | H H | G I |
      +-----+-----+-----+-----+
   y2 | F G | H H | H H | G I |
      | F J | K K | K K | L I |
      +-----+-----+-----+-----+
   y3 | M N | O O | O O | P Q |
      | R S | S S | S S | S T |
      +-----+-----+-----+-----+
   y4 | R O | O O | U V | O T |
      | W X | X X | * Y | X Z |
      +-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4   
      +---------+---------+---------+---------+
   y1 |   5   6 |  83  83 |  83  83 |   8   9 |
      |  21  56 |  18  18 |  18  18 |  56  25 |
      +---------+---------+---------+---------+
   y2 |  21  56 |  18  18 |  18  18 |  56  25 |
      |  21  22 |  23  23 |  23  23 |  24  25 |
      +---------+---------+---------+---------+
   y3 |  37  38 |  10  10 |  10  10 |  40  41 |
      |  15  34 |  34  34 |  34  34 |  34  31 |
      +---------+---------+---------+---------+
   y4 |  15  10 |  10  10 |  11  12 |  10  31 |
      |  78  26 |  26  26 |  27  28 |  26  79 |
      +---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {   5,   6,  83,  83,  83,  83,   8,   9 },  -- r1
  {  21,  56,  18,  18,  18,  18,  56,  25 },  -- r2
  {  21,  56,  18,  18,  18,  18,  56,  25 },  -- r3
  {  21,  22,  23,  23,  23,  23,  24,  25 },  -- r4
  {  37,  38,  10,  10,  10,  10,  40,  41 },  -- r5
  {  15,  34,  34,  34,  34,  34,  34,  31 },  -- r6
  {  15,  10,  10,  10,  11,  12,  10,  31 },  -- r7
  {  78,  26,  26,  26,  27,  28,  26,  79 },  -- r8
}
```

## Legend

_Legend pending._

- `*` = tile 27, used 1x
- `A` = tile 5, used 1x
- `B` = tile 6, used 1x
- `C` = tile 83, used 4x
- `D` = tile 8, used 1x
- `E` = tile 9, used 1x
- `F` = tile 21, used 3x
- `G` = tile 56, used 4x
- `H` = tile 18, used 8x
- `I` = tile 25, used 3x
- `J` = tile 22, used 1x
- `K` = tile 23, used 4x
- `L` = tile 24, used 1x
- `M` = tile 37, used 1x
- `N` = tile 38, used 1x
- `O` = tile 10, used 8x
- `P` = tile 40, used 1x
- `Q` = tile 41, used 1x
- `R` = tile 15, used 2x
- `S` = tile 34, used 6x
- `T` = tile 31, used 2x
- `U` = tile 11, used 1x
- `V` = tile 12, used 1x
- `W` = tile 78, used 1x
- `X` = tile 26, used 4x
- `Y` = tile 28, used 1x
- `Z` = tile 79, used 1x

![distinct tiles](img/B33_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID
    y4   SOLID  SOLID  DOOR   SOLID
```

Enterable cell: (3,4).

## Silhouette

186 of the 4096 px inside the box are ground outside the black outline, so the 64x64 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:48px, c2:16px, c7:16px, c8:48px
    r5   c1:5px, c8:5px
    r6   c1:8px, c8:8px
    r7   c1:8px, c8:8px
    r8   c1:8px, c8:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| ROUTE_5 | (8,18) | (10,21) | `DAYCARE` |
