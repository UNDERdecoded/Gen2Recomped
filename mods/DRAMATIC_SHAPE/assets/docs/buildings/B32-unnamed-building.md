# B32 - Unnamed building

![Unnamed building](img/B32_x5.png)

`SHIP_PORT` tileset, **8 x 3 cells** (16 x 6 tiles of 8px, 128 x 48 px). Appears **1 time** in the game. Tile ids index `assets/generated/tilesets/ship_port.png`, 16 per row.

Coordinates are 1-based and local to the building: cell x=1..8, y=1..3; tile column c=1..16, tile row r=1..6. No terrain padding is included - edge rows and columns that were pure ground have been trimmed.

## Symbol grid

```
          x1   x2   x3   x4   x5   x6   x7   x8 
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y1 | A A | B C | D E | F G | H H | I I | J K | L M |
      | N O | P Q | R S | T U | V W | V W | X Y | Z a |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y2 | b c | d e | f g | h i | j k | j k | l m | n o |
      | p c | d q | r s | t u | v w | v w | x y | x o |
      +-----+-----+-----+-----+-----+-----+-----+-----+
   y3 | z 0 | 1 2 | 3 4 | 4 4 | 4 4 | 4 4 | 4 5 | 6 7 |
      | A 8 | 9 ! | # # | # # | # # | # # | # $ | % & |
      +-----+-----+-----+-----+-----+-----+-----+-----+
```

## Same grid, raw tile ids

```
            x1       x2       x3       x4       x5       x6       x7       x8   
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y1 |  20  20 |   2   3 |   4   5 |   6   7 |   9   9 |  11  11 |  12  13 |  14  15 |
      |  16  17 |  18  19 |   0  21 |  22  23 |  24  25 |  24  25 |  28  29 |  30  31 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y2 |  32  33 |  34  35 |  36  37 |  38  39 |  40  41 |  40  41 |  44  45 |  46  47 |
      |  48  33 |  34  51 |  52  53 |  54  55 |  56  57 |  56  57 |  62  61 |  62  47 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
   y3 |  64  65 |  66  67 |  68  69 |  69  69 |  69  69 |  69  69 |  69  77 |  78  79 |
      |  20  81 |  82  83 |  85  85 |  85  85 |  85  85 |  85  85 |  85  93 |  90  91 |
      +---------+---------+---------+---------+---------+---------+---------+---------+
```

As a 1-based Lua array, `rows[r][c]`:

```lua
local rows = {
  {  20,  20,   2,   3,   4,   5,   6,   7,   9,   9,  11,  11,  12,  13,  14,  15 },  -- r1
  {  16,  17,  18,  19,   0,  21,  22,  23,  24,  25,  24,  25,  28,  29,  30,  31 },  -- r2
  {  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  40,  41,  44,  45,  46,  47 },  -- r3
  {  48,  33,  34,  51,  52,  53,  54,  55,  56,  57,  56,  57,  62,  61,  62,  47 },  -- r4
  {  64,  65,  66,  67,  68,  69,  69,  69,  69,  69,  69,  69,  69,  77,  78,  79 },  -- r5
  {  20,  81,  82,  83,  85,  85,  85,  85,  85,  85,  85,  85,  85,  93,  90,  91 },  -- r6
}
```

## Legend

_Legend pending._

- `!` = tile 83, used 1x
- `#` = tile 85, used 9x
- `$` = tile 93, used 1x
- `%` = tile 90, used 1x
- `&` = tile 91, used 1x
- `0` = tile 65, used 1x
- `1` = tile 66, used 1x
- `2` = tile 67, used 1x
- `3` = tile 68, used 1x
- `4` = tile 69, used 8x
- `5` = tile 77, used 1x
- `6` = tile 78, used 1x
- `7` = tile 79, used 1x
- `8` = tile 81, used 1x
- `9` = tile 82, used 1x
- `A` = tile 20, used 3x
- `B` = tile 2, used 1x
- `C` = tile 3, used 1x
- `D` = tile 4, used 1x
- `E` = tile 5, used 1x
- `F` = tile 6, used 1x
- `G` = tile 7, used 1x
- `H` = tile 9, used 2x
- `I` = tile 11, used 2x
- `J` = tile 12, used 1x
- `K` = tile 13, used 1x
- `L` = tile 14, used 1x
- `M` = tile 15, used 1x
- `N` = tile 16, used 1x
- `O` = tile 17, used 1x
- `P` = tile 18, used 1x
- `Q` = tile 19, used 1x
- `R` = tile 0, used 1x
- `S` = tile 21, used 1x
- `T` = tile 22, used 1x
- `U` = tile 23, used 1x
- `V` = tile 24, used 2x
- `W` = tile 25, used 2x
- `X` = tile 28, used 1x
- `Y` = tile 29, used 1x
- `Z` = tile 30, used 1x
- `a` = tile 31, used 1x
- `b` = tile 32, used 1x
- `c` = tile 33, used 2x
- `d` = tile 34, used 2x
- `e` = tile 35, used 1x
- `f` = tile 36, used 1x
- `g` = tile 37, used 1x
- `h` = tile 38, used 1x
- `i` = tile 39, used 1x
- `j` = tile 40, used 2x
- `k` = tile 41, used 2x
- `l` = tile 44, used 1x
- `m` = tile 45, used 1x
- `n` = tile 46, used 1x
- `o` = tile 47, used 2x
- `p` = tile 48, used 1x
- `q` = tile 51, used 1x
- `r` = tile 52, used 1x
- `s` = tile 53, used 1x
- `t` = tile 54, used 1x
- `u` = tile 55, used 1x
- `v` = tile 56, used 2x
- `w` = tile 57, used 2x
- `x` = tile 62, used 2x
- `y` = tile 61, used 1x
- `z` = tile 64, used 1x

![distinct tiles](img/B32_atlas.png)

## Collision

Cell walkability reads the **bottom-left 8px tile** of each cell (`src/world/Map.lua:6`):

```
    y1   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y2   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
    y3   SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID  SOLID
```

Every cell is solid - this building has no door of its own.

## Silhouette

315 of the 6144 px inside the box are ground outside the black outline, so the 128x48 box is **not** a solid rectangle - a pixel-perfect cutout has to follow the outline. Terrain pixels by tile row:

```
    r1   c1:22px, c2:20px, c3:20px, c4:19px, c5:13px, c6:3px, c8:4px, c11:9px, c12:9px, c13:11px, c14:18px, c15:18px, c16:22px
    r2   c1:20px, c2:8px, c16:4px
    r3   c1:5px
    r5   c1:16px, c16:2px
    r6   c1:25px, c2:23px, c3:6px, c4:1px, c16:17px
```

## Where it stands

| map | cell (x,y) | door | leads to |
| --- | --- | --- | --- |
| VERMILION_DOCK | (10,3) | - | scenery, no entrance |
