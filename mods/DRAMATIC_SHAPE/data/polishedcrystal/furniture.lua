-- Complete drawings in Polished Crystal's House1 atlas. These are authored
-- as groups: matching only unchanged individual tiles splits the monitors
-- from their cases and lets the cell collision raise tables into walls.
return {
  TilesetHouse1 = {
    console = {102,103,118,119,134,135},
    billboard = {96,97,112,113,128,129},
    prop = {100,101,116,117},
    stool = {108,109,124,125},
    bookcase = {4,5,36,37,52,53},
    table = {32,33,48,49,51,64,65,80,81,82,84,185,186,187},
    ground = {1,16,34,35,66,144,145,160,161},
    heights = {table=6,stool=5},
    when_below = {
      [4]={{below={20},class='table'}},
      [5]={{below={21},class='table'}},
    },
    when_above = {
      [20]={{above={4},class='table'}},
      [21]={{above={5},class='table'}},
    },
  },
  TilesetHouse2 = {
    console = {102,103,118,119,134,135},
    billboard = {96,97,112,113,128,129},
    prop = {100,101,116,117},
    table = {32,33,48,49,51,64,65,80,81,82,84,110,126},
    stool = {108,109,124,125},
    bookcase = {4,5,36,37,52,53},
    ground = {1,16},
    heights = {table=6,stool=5},
    when_below = {[4]={{below={20},class='table'}},[5]={{below={21},class='table'}}},
    when_above = {[20]={{above={4},class='table'}},[21]={{above={5},class='table'}}},
  },
  TilesetHouse3 = {
    -- Traditional homes: patterned carpets reuse graphics which an
    -- unrelated HOUSE donor calls walls. They are floors in this family.
    ground = {1,2,3,4,16,17,18,19,53,54,68,69,70,84,85,86},
    console = {6,7,22,23,38,39},
    billboard = {8,9,24,25,40,41},
    prop = {10,11,26,27},
    table = {34,50,51,52},
    heights = {table=6},
  },
  TilesetPokeCenter = {
    -- The PC is a complete two-by-two drawing in Polished, not the
    -- unchanged lower half of Crystal's taller cabinet.
    console = {128,129,130,131},
    ground = {1,2,4,7,8,17,18,19,53,54,64,65,66,67,80,84,85,96,97,98,99},
    table = {74,75,90,91},
    stool = {12,13,14,15,28,29,30,31,44,45,46,47,60,61,62,63},
    heights = {table=6,stool=5},
  },
}
