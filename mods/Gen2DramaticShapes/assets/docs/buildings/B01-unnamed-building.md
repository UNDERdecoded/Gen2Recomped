# B01 - Unnamed building

![Unnamed building](img/B01_x10.png)

`OVERWORLD` tileset, **4 x 3 cells** (8 x 6 tiles of 8px, 64 x 48 px). Appears **19 times** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..4, y=1..3; tile column c=1..8, tile row r=1..6. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4 
      +-----+-----+-----+-----+
   y1 | A B | C C | C C | D E |
      | F G | H H | H H | I J |
      +-----+-----+-----+-----+
   y2 | K L | M M | M M | N O |
      | P Q | Q Q | R R | R S |
      +-----+-----+-----+-----+
   y3 | P M | M M | M M | M S |
      | T U | U U | U U | U V |
      +-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4   
      +---------+---------+---------+---------+
   y1 |   5   6 |   7   7 |   7   7 |   8   9 |
      |  21  22 |  23  23 |  23  23 |  24  25 |
      +---------+---------+---------+---------+
   y2 |  37  38 |  10  10 |  10  10 |  40  41 |
      |  15  34 |  34  34 |  75  75 |  75  31 |
      +---------+---------+---------+---------+
   y3 |  15  10 |  10  10 |  10  10 |  10  31 |
      |  78  26 |  26  26 |  26  26 |  26  79 |
      +---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {   5,   6,   7,   7,   7,   7,   8,   9 },  -- r1
  {  21,  22,  23,  23,  23,  23,  24,  25 },  -- r2
  {  37,  38,  10,  10,  10,  10,  40,  41 },  -- r3
  {  15,  34,  34,  34,  75,  75,  75,  31 },  -- r4
  {  15,  10,  10,  10,  10,  10,  10,  31 },  -- r5
  {  78,  26,  26,  26,  26,  26,  26,  79 },  -- r6
}
```

## Legend

_Legend pending._

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
- `M` = tile 10, used 10x
- `N` = tile 40, used 1x
- `O` = tile 41, used 1x
- `P` = tile 15, used 2x
- `Q` = tile 34, used 3x
- `R` = tile 75, used 3x
- `S` = tile 31, used 2x
- `T` = tile 78, used 1x
- `U` = tile 26, used 6x
- `V` = tile 79, used 1x

![distinct tiles](img/B01_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID
```

Every cell is solid - this building has no door of its own.

## Silhouette

186 of the 3072 px inside the box are ground outside the black outline, so the 64x48 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:48px, c2:16px, c7:16px, c8:48px
    r3   c1:5px, c8:5px
    r4   c1:8px, c8:8px
    r5   c1:8px, c8:8px
    r6   c1:8px, c8:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| SAFFRON_CITY | (36,1) | - | scenery, no entrance |
| SAFFRON_CITY | (2,3) | - | scenery, no entrance |
| SAFFRON_CITY | (10,3) | - | scenery, no entrance |
| SAFFRON_CITY | (4,9) | - | scenery, no entrance |
| SAFFRON_CITY | (8,9) | - | scenery, no entrance |
| SAFFRON_CITY | (28,9) | - | scenery, no entrance |
| SAFFRON_CITY | (32,9) | - | scenery, no entrance |
| SAFFRON_CITY | (4,27) | - | scenery, no entrance |
| SAFFRON_CITY | (12,27) | - | scenery, no entrance |
| SAFFRON_CITY | (16,27) | - | scenery, no entrance |
| SAFFRON_CITY | (20,27) | - | scenery, no entrance |
| SAFFRON_CITY | (32,27) | - | scenery, no entrance |
| SAFFRON_CITY | (4,33) | - | scenery, no entrance |
| SAFFRON_CITY | (8,33) | - | scenery, no entrance |
| SAFFRON_CITY | (12,33) | - | scenery, no entrance |
| SAFFRON_CITY | (16,33) | - | scenery, no entrance |
| SAFFRON_CITY | (24,33) | - | scenery, no entrance |
| SAFFRON_CITY | (28,33) | - | scenery, no entrance |
| SAFFRON_CITY | (32,33) | - | scenery, no entrance |
