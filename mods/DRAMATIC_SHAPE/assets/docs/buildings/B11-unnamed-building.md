# B11 - Unnamed building

![Unnamed building](img/B11_x6.png)

`OVERWORLD` tileset, **6 x 2 cells** (12 x 4 tiles of 8px, 96 x 32 px). Appears **5 times** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..6, y=1..2; tile column c=1..12, tile row r=1..4. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4   x5   x6 
      +-----+-----+-----+-----+-----+-----+
   y1 | A B | C C | C C | C C | C C | D E |
      | F G | H H | H H | H H | H H | I J |
      +-----+-----+-----+-----+-----+-----+
   y2 | K L | M N | O M | M O | M M | P Q |
      | R S | S S | S S | S S | S S | S T |
      +-----+-----+-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4       x5       x6   
      +---------+---------+---------+---------+---------+---------+
   y1 |   5   6 |   7   7 |   7   7 |   7   7 |   7   7 |   8   9 |
      |  21  22 |  23  23 |  23  23 |  23  23 |  23  23 |  24  25 |
      +---------+---------+---------+---------+---------+---------+
   y2 |  37  38 |  10  34 |  35  10 |  10  35 |  10  10 |  40  41 |
      |  78  26 |  26  26 |  26  26 |  26  26 |  26  26 |  26  79 |
      +---------+---------+---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {   5,   6,   7,   7,   7,   7,   7,   7,   7,   7,   8,   9 },  -- r1
  {  21,  22,  23,  23,  23,  23,  23,  23,  23,  23,  24,  25 },  -- r2
  {  37,  38,  10,  34,  35,  10,  10,  35,  10,  10,  40,  41 },  -- r3
  {  78,  26,  26,  26,  26,  26,  26,  26,  26,  26,  26,  79 },  -- r4
}
```

## Legend

_Legend pending._

- `A` = tile 5, used 1x
- `B` = tile 6, used 1x
- `C` = tile 7, used 8x
- `D` = tile 8, used 1x
- `E` = tile 9, used 1x
- `F` = tile 21, used 1x
- `G` = tile 22, used 1x
- `H` = tile 23, used 8x
- `I` = tile 24, used 1x
- `J` = tile 25, used 1x
- `K` = tile 37, used 1x
- `L` = tile 38, used 1x
- `M` = tile 10, used 5x
- `N` = tile 34, used 1x
- `O` = tile 35, used 2x
- `P` = tile 40, used 1x
- `Q` = tile 41, used 1x
- `R` = tile 78, used 1x
- `S` = tile 26, used 10x
- `T` = tile 79, used 1x

![distinct tiles](img/B11_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
```

Every cell is solid - this building has no door of its own.

## Silhouette

154 of the 3072 px inside the box are ground outside the black outline, so the 96x32 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:48px, c2:16px, c11:16px, c12:48px
    r3   c1:5px, c12:5px
    r4   c1:8px, c12:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| CELADON_CITY | (20,14) | - | scenery, no entrance |
| CERULEAN_CITY | (14,10) | - | scenery, no entrance |
| CERULEAN_CITY | (34,10) | - | scenery, no entrance |
| CERULEAN_CITY | (18,24) | - | scenery, no entrance |
| CERULEAN_CITY | (28,24) | - | scenery, no entrance |
