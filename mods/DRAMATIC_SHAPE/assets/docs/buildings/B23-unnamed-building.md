# B23 - Unnamed building

![Unnamed building](img/B23_x4.png)

`PLATEAU` tileset, **18 x 3 cells** (36 x 6 tiles of 8px, 288 x 48 px). Appears **1 time** in the game. Tile ids index `assets/generated/tilesets/plateau.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..18, y=1..3; tile column c=1..36, tile row r=1..6. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4   x5   x6   x7   x8   x9  x10  x11  x12  x13  x14  x15  x16  x17  x18 
      +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
   y1 | A B | C C | C C | C C | C C | C C | C C | C C | C C | C C | C C | C C | C C | C C | C C | C C | C C | A B |
      | D E | F F | F F | F F | F F | F F | F F | F F | F F | F F | F F | F F | F F | F F | F F | F F | F F | D E |
      +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
   y2 | G H | I I | I I | I I | I I | I I | I I | I I | J K | C C | C C | C C | C C | J K | I I | I I | I I | G H |
      | L M | I I | I I | I I | I I | I I | I I | I I | J K | C C | C C | C C | C C | J K | I I | I I | I I | L M |
      +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
   y3 | L M | I I | I I | I I | N O | I I | I I | I I | J K | C C | C C | C C | C C | J K | N O | I I | I I | L M |
      | G H | P P | P P | P P | * Q | P P | P P | P P | J K | C C | C C | C C | C C | J K | * Q | P P | P P | G H |
      +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4       x5       x6       x7       x8       x9      x10      x11      x12      x13      x14      x15      x16      x17      x18   
      +---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+
   y1 |  37  38 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |   3   3 |  37  38 |
      |  40  41 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  13  13 |  40  41 |
      +---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+
   y2 |  21  22 |  15  15 |  15  15 |  15  15 |  15  15 |  15  15 |  15  15 |  15  15 |  46  47 |   3   3 |   3   3 |   3   3 |   3   3 |  46  47 |  15  15 |  15  15 |  15  15 |  21  22 |
      |   5   6 |  15  15 |  15  15 |  15  15 |  15  15 |  15  15 |  15  15 |  15  15 |  46  47 |   3   3 |   3   3 |   3   3 |   3   3 |  46  47 |  15  15 |  15  15 |  15  15 |   5   6 |
      +---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+
   y3 |   5   6 |  15  15 |  15  15 |  15  15 |  11  12 |  15  15 |  15  15 |  15  15 |  46  47 |   3   3 |   3   3 |   3   3 |   3   3 |  46  47 |  11  12 |  15  15 |  15  15 |   5   6 |
      |  21  22 |  14  14 |  14  14 |  14  14 |  27  28 |  14  14 |  14  14 |  14  14 |  46  47 |   3   3 |   3   3 |   3   3 |   3   3 |  46  47 |  27  28 |  14  14 |  14  14 |  21  22 |
      +---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {  37,  38,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,  37,  38 },  -- r1
  {  40,  41,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,  40,  41 },  -- r2
  {  21,  22,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  46,  47,   3,   3,   3,   3,   3,   3,   3,   3,  46,  47,  15,  15,  15,  15,  15,  15,  21,  22 },  -- r3
  {   5,   6,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  46,  47,   3,   3,   3,   3,   3,   3,   3,   3,  46,  47,  15,  15,  15,  15,  15,  15,   5,   6 },  -- r4
  {   5,   6,  15,  15,  15,  15,  15,  15,  11,  12,  15,  15,  15,  15,  15,  15,  46,  47,   3,   3,   3,   3,   3,   3,   3,   3,  46,  47,  11,  12,  15,  15,  15,  15,   5,   6 },  -- r5
  {  21,  22,  14,  14,  14,  14,  14,  14,  27,  28,  14,  14,  14,  14,  14,  14,  46,  47,   3,   3,   3,   3,   3,   3,   3,   3,  46,  47,  27,  28,  14,  14,  14,  14,  21,  22 },  -- r6
}
```

## Legend

_Legend pending._

- `*` = tile 27, used 2x
- `A` = tile 37, used 2x
- `B` = tile 38, used 2x
- `C` = tile 3, used 64x
- `D` = tile 40, used 2x
- `E` = tile 41, used 2x
- `F` = tile 13, used 32x
- `G` = tile 21, used 4x
- `H` = tile 22, used 4x
- `I` = tile 15, used 56x
- `J` = tile 46, used 8x
- `K` = tile 47, used 8x
- `L` = tile 5, used 4x
- `M` = tile 6, used 4x
- `N` = tile 11, used 2x
- `O` = tile 12, used 2x
- `P` = tile 14, used 16x
- `Q` = tile 28, used 2x

![distinct tiles](img/B23_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID  DOOR   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  DOOR   SOLID  SOLID  SOLID
```

Enterable cells: (5,3), (15,3).

## Silhouette

1297 of the 13824 px inside the box are ground outside the black outline, so the 288x48 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:14px, c2:14px, c3:4px, c4:4px, c5:4px, c6:4px, c7:4px, c8:4px, c9:4px, c10:4px, c11:4px, c12:4px, c13:4px, c14:4px, c15:4px, c16:4px, c17:4px, c18:4px, c19:4px, c20:4px, c21:4px, c22:4px, c23:4px, c24:4px, c25:4px, c26:4px, c27:4px, c28:4px, c29:4px, c30:4px, c31:4px, c32:4px, c33:4px, c34:4px, c35:14px, c36:14px
    r2   c1:10px, c2:10px, c3:16px, c4:16px, c5:16px, c6:16px, c7:16px, c8:16px, c9:16px, c10:16px, c11:16px, c12:16px, c13:16px, c14:16px, c15:16px, c16:16px, c17:16px, c18:16px, c19:16px, c20:16px, c21:16px, c22:16px, c23:16px, c24:16px, c25:16px, c26:16px, c27:16px, c28:16px, c29:16px, c30:16px, c31:16px, c32:16px, c33:16px, c34:16px, c35:10px, c36:10px
    r3   c1:10px, c2:10px, c17:8px, c18:8px, c19:4px, c20:4px, c21:4px, c22:4px, c23:4px, c24:4px, c25:4px, c26:4px, c27:8px, c28:8px, c35:10px, c36:10px
    r4   c1:8px, c2:8px, c17:8px, c18:8px, c19:1px, c27:8px, c28:8px, c35:8px, c36:8px
    r5   c1:8px, c2:8px, c17:8px, c18:8px, c19:1px, c27:8px, c28:8px, c29:34px, c30:34px, c35:8px, c36:8px
    r6   c1:15px, c2:15px, c3:9px, c4:8px, c5:8px, c6:8px, c7:8px, c8:8px, c11:8px, c12:8px, c13:8px, c14:8px, c15:8px, c16:8px, c17:8px, c18:8px, c19:1px, c27:8px, c28:8px, c29:18px, c30:18px, c31:9px, c32:8px, c33:8px, c34:8px, c35:15px, c36:15px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| ROUTE_23 | (0,29) | (4,31) | `VICTORY_ROAD_1F` |
| ROUTE_23 | (0,29) | (14,31) | `VICTORY_ROAD_2F` |
