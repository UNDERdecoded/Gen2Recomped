# B34 - Unnamed building

![Unnamed building](img/B34_x10.png)

`OVERWORLD` tileset, **4 x 2 cells** (8 x 4 tiles of 8px, 64 x 32 px). Appears **1 time** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..4, y=1..2; tile column c=1..8, tile row r=1..4. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4 
      +-----+-----+-----+-----+
   y1 | A B | C C | C C | D E |
      | F G | H H | H H | I J |
      +-----+-----+-----+-----+
   y2 | K L | M N | M M | O P |
      | Q R | R R | R R | R S |
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
      |  78  26 |  26  26 |  26  26 |  26  79 |
      +---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {   5,   6,   7,   7,   7,   7,   8,   9 },  -- r1
  {  21,  22,  23,  23,  23,  23,  24,  25 },  -- r2
  {  37,  38,  10,  34,  10,  10,  40,  41 },  -- r3
  {  78,  26,  26,  26,  26,  26,  26,  79 },  -- r4
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
- `M` = tile 10, used 3x
- `N` = tile 34, used 1x
- `O` = tile 40, used 1x
- `P` = tile 41, used 1x
- `Q` = tile 78, used 1x
- `R` = tile 26, used 6x
- `S` = tile 79, used 1x

![distinct tiles](img/B34_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID
```

Every cell is solid - this building has no door of its own.

## Silhouette

154 of the 2048 px inside the box are ground outside the black outline, so the 64x32 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:48px, c2:16px, c7:16px, c8:48px
    r3   c1:5px, c8:5px
    r4   c1:8px, c8:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| FUCHSIA_CITY | (14,26) | - | scenery, no entrance |
