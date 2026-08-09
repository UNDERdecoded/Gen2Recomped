# B17 - Unnamed building

![Unnamed building](img/B17_x6.png)

`OVERWORLD` tileset, **6 x 2 cells** (12 x 4 tiles of 8px, 96 x 32 px). Appears **3 times** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..6, y=1..2; tile column c=1..12, tile row r=1..4. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4   x5   x6 
      +-----+-----+-----+-----+-----+-----+
   y1 | A B | C C | C C | C C | C C | D E |
      | F G | H H | H H | H H | H H | I J |
      +-----+-----+-----+-----+-----+-----+
   y2 | K L | M N | O P | P O | P P | Q R |
      | S T | * U | T T | T T | T T | T V |
      +-----+-----+-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4       x5       x6   
      +---------+---------+---------+---------+---------+---------+
   y1 |   5   6 |   7   7 |   7   7 |   7   7 |   7   7 |   8   9 |
      |  21  22 |  23  23 |  23  23 |  23  23 |  23  23 |  24  25 |
      +---------+---------+---------+---------+---------+---------+
   y2 |  37  38 |  11  12 |  35  10 |  10  35 |  10  10 |  40  41 |
      |  78  26 |  27  28 |  26  26 |  26  26 |  26  26 |  26  79 |
      +---------+---------+---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {   5,   6,   7,   7,   7,   7,   7,   7,   7,   7,   8,   9 },  -- r1
  {  21,  22,  23,  23,  23,  23,  23,  23,  23,  23,  24,  25 },  -- r2
  {  37,  38,  11,  12,  35,  10,  10,  35,  10,  10,  40,  41 },  -- r3
  {  78,  26,  27,  28,  26,  26,  26,  26,  26,  26,  26,  79 },  -- r4
}
```

## Legend

_Legend pending._

- `*` = tile 27, used 1x
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
- `M` = tile 11, used 1x
- `N` = tile 12, used 1x
- `O` = tile 35, used 2x
- `P` = tile 10, used 4x
- `Q` = tile 40, used 1x
- `R` = tile 41, used 1x
- `S` = tile 78, used 1x
- `T` = tile 26, used 8x
- `U` = tile 28, used 1x
- `V` = tile 79, used 1x

![distinct tiles](img/B17_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y2   SOLID  DOOR   SOLID  SOLID  SOLID  SOLID
```

Enterable cell: (2,2).

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
| CERULEAN_CITY | (8,10) | (9,11) | `CERULEAN_BADGE_HOUSE` |
| CERULEAN_CITY | (26,10) | (27,11) | `CERULEAN_TRASHED_HOUSE` |
| CERULEAN_CITY | (12,14) | (13,15) | `CERULEAN_TRADE_HOUSE` |
