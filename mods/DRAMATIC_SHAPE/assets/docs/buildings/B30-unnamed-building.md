# B30 - Unnamed building

![Unnamed building](img/B30_x6.png)

`OVERWORLD` tileset, **6 x 4 cells** (12 x 8 tiles of 8px, 96 x 64 px). Appears **1 time** in the game. Tile ids index `assets/generated/tilesets/overworld.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..6, y=1..4; tile column c=1..12, tile row r=1..8. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4   x5   x6 
      +-----+-----+-----+-----+-----+-----+
   y1 | A B | B B | B B | B B | B B | B C |
      | A D | D D | D D | D D | D D | D C |
      +-----+-----+-----+-----+-----+-----+
   y2 | A B | B B | B B | B B | B B | B C |
      | A D | D D | D D | D D | D D | D C |
      +-----+-----+-----+-----+-----+-----+
   y3 | A B | B B | B B | B B | B B | B C |
      | A D | D D | D D | D D | D D | D C |
      +-----+-----+-----+-----+-----+-----+
   y4 | A D | D D | D D | D D | D D | D C |
      | E F | F F | F F | F F | F F | F G |
      +-----+-----+-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4       x5       x6   
      +---------+---------+---------+---------+---------+---------+
   y1 |  15  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+
   y2 |  15  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+
   y3 |  15  10 |  10  10 |  10  10 |  10  10 |  10  10 |  10  31 |
      |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      +---------+---------+---------+---------+---------+---------+
   y4 |  15  75 |  75  75 |  75  75 |  75  75 |  75  75 |  75  31 |
      |  78  26 |  26  26 |  26  26 |  26  26 |  26  26 |  26  79 |
      +---------+---------+---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  31 },  -- r1
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r2
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  31 },  -- r3
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r4
  {  15,  10,  10,  10,  10,  10,  10,  10,  10,  10,  10,  31 },  -- r5
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r6
  {  15,  75,  75,  75,  75,  75,  75,  75,  75,  75,  75,  31 },  -- r7
  {  78,  26,  26,  26,  26,  26,  26,  26,  26,  26,  26,  79 },  -- r8
}
```

## Legend

_Legend pending._

- `A` = tile 15, used 7x
- `B` = tile 10, used 30x
- `C` = tile 31, used 7x
- `D` = tile 75, used 40x
- `E` = tile 78, used 1x
- `F` = tile 26, used 10x
- `G` = tile 79, used 1x

![distinct tiles](img/B30_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y4   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
```

Every cell is solid - this building has no door of its own.

## Silhouette

1552 of the 6144 px inside the box are ground outside the black outline, so the 96x64 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:24px, c12:24px
    r2   c1:24px, c2:30px, c3:30px, c4:30px, c5:30px, c6:30px, c7:30px, c8:30px, c9:30px, c10:30px, c11:30px, c12:24px
    r3   c1:24px, c12:24px
    r4   c1:24px, c2:30px, c3:30px, c4:30px, c5:30px, c6:30px, c7:30px, c8:30px, c9:30px, c10:30px, c11:30px, c12:24px
    r5   c1:24px, c12:24px
    r6   c1:24px, c2:30px, c3:30px, c4:30px, c5:30px, c6:30px, c7:30px, c8:30px, c9:30px, c10:30px, c11:30px, c12:24px
    r7   c1:24px, c2:30px, c3:30px, c4:30px, c5:30px, c6:30px, c7:30px, c8:30px, c9:30px, c10:30px, c11:30px, c12:24px
    r8   c1:8px, c12:8px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| LAVENDER_TOWN | (12,0) | - | scenery, no entrance |
