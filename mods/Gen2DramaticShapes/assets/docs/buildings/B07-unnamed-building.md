# B07 - Unnamed building

![Unnamed building](img/B07_x10.png)

`OVERWORLD` tileset, **4 x 3 cells** (8 x 6 tiles of 8px, 64 x 48 px). Appears **7 times** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..4, y=1..3; tile column c=1..8, tile row r=1..6. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4 
      +-----+-----+-----+-----+
   y1 | A B | C C | C C | D E |
      | F G | H H | H H | I J |
      +-----+-----+-----+-----+
   y2 | K L | M N | M M | O P |
      | Q H | H H | H H | H R |
      +-----+-----+-----+-----+
   y3 | S N | T U | M M | N V |
      | W X | * Y | X X | X Z |
      +-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4   
      +---------+---------+---------+---------+
   y1 |   5   6 |   7   7 |   7   7 |   8   9 |
      |  21  22 |  23  23 |  23  23 |  24  25 |
      +---------+---------+---------+---------+
   y2 |  37  38 |  10  34 |  10  10 |  40  41 |
      |  92  23 |  23  23 |  23  23 |  23  93 |
      +---------+---------+---------+---------+
   y3 |  15  34 |  11  12 |  10  10 |  34  31 |
      |  78  26 |  27  28 |  26  26 |  26  79 |
      +---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {   5,   6,   7,   7,   7,   7,   8,   9 },  -- r1
  {  21,  22,  23,  23,  23,  23,  24,  25 },  -- r2
  {  37,  38,  10,  34,  10,  10,  40,  41 },  -- r3
  {  92,  23,  23,  23,  23,  23,  23,  93 },  -- r4
  {  15,  34,  11,  12,  10,  10,  34,  31 },  -- r5
  {  78,  26,  27,  28,  26,  26,  26,  79 },  -- r6
}
```

## Legend

_Legend pending._

- `*` = tile 27, used 1x
- `A` = tile 5, used 1x
- `B` = tile 6, used 1x
- `C` = tile 7, used 4x
- `D` = tile 8, used 1x
- `E` = tile 9, used 1x
- `F` = tile 21, used 1x
- `G` = tile 22, used 1x
- `H` = tile 23, used 10x
- `I` = tile 24, used 1x
- `J` = tile 25, used 1x
- `K` = tile 37, used 1x
- `L` = tile 38, used 1x
- `M` = tile 10, used 5x
- `N` = tile 34, used 3x
- `O` = tile 40, used 1x
- `P` = tile 41, used 1x
- `Q` = tile 92, used 1x
- `R` = tile 93, used 1x
- `S` = tile 15, used 1x
- `T` = tile 11, used 1x
- `U` = tile 12, used 1x
- `V` = tile 31, used 1x
- `W` = tile 78, used 1x
- `X` = tile 26, used 4x
- `Y` = tile 28, used 1x
- `Z` = tile 79, used 1x

![distinct tiles](img/B07_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID
    y3   SOLID  DOOR   SOLID  SOLID
```

Enterable cell: (2,3).

## Silhouette

218 of the 3072 px inside the box are ground outside the black outline, so the 64x48 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:48px, c2:16px, c7:16px, c8:48px
    r3   c1:5px, c8:5px
    r4   c1:24px, c8:24px
    r5   c1:8px, c8:8px
    r6   c1:8px, c8:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| FUCHSIA_CITY | (26,25) | (27,27) | `WARDENS_HOUSE` |
| FUCHSIA_CITY | (30,25) | (31,27) | `FUCHSIA_GOOD_ROD_HOUSE` |
| PALLET_TOWN | (4,3) | (5,5) | `REDS_HOUSE_1F` |
| PALLET_TOWN | (12,3) | (13,5) | `BLUES_HOUSE` |
| ROUTE_25 | (44,1) | (45,3) | `BILLS_HOUSE` |
| SAFFRON_CITY | (6,3) | (7,5) | `COPYCATS_HOUSE_1F` |
| SAFFRON_CITY | (12,9) | (13,11) | `SAFFRON_PIDGEY_HOUSE` |
