-- src/script/Gen5StorySwaps.lua -- BLACK / WHITE ops 0x0D9, 0x0DA, 0x0E4.
--
-- READ FROM CODE (Black, ov10 handlers via the table at file 0x1B4CC):
--
--   0x0DA <id, on, apply>  (0x0215AE34) THE STORY SWAPS. 0x02159F28 finds row
--        `id` of ov10's table 0x02170FB0 (ten rows of 6 bytes: u8, u8 id, u16
--        event var, u16 value -- ids 0..9 are vars 0x4031..0x403A) and sets
--        that var to the row's value when `on` is not 0, to 0 otherwise. With
--        `apply` set the field's map replacements are rebuilt at once
--        (0x02159B94 / 0x02159CC4, the same work every map load does). Those
--        vars are exactly the conditions 3..12 of the map replacements
--        (src/world/Gen5MapVariants.lua): the bedroom after the first battle
--        (Z391, id 6), N's castle rising at the League (Z144, id 1; off again
--        after the clear, 9601), Nacrene's museum ...
--   0x0D9 <id>  (0x0215AD50) when 1 <= id <= 17 (0x02159F84): the save's
--        warp id (system block +0x15C, field +0x70; arm9 0x02012900). Read back
--        (0x02012914) by ov10 0x0215F630 and ov20 0x02184F40, which turns it
--        into a location through the 20-byte rows of ov10 0x02170FF4 (row
--        id - 1: zone, x, z ... and a fly flag 0x9B1 +). Set to 1 by the new
--        game and the game clear, 12 on entering the League (Z137), 3 by the
--        new game's other branch. It is THE WHITEOUT POINT (ov20 0x0218562C;
--        M.WARP_ROWS below): kept as save.gen5WarpId and written into
--        save.lastHeal, which the port's blackout reads.
--   0x0E4 <n>  (0x0215B084) when n is 1 or 2: OR n into a byte of another
--        save block (system +0x19C -> arm9 0x02007A68, +0x3DC). 9601 sets 1 on
--        the first clear, 2 on the second. Kept as save.gen5ClearBits; its
--        reader is not read.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
Commands.meta = Commands.meta or {}

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function v(ctx, a) return math.floor(tonumber(G4().valueOf(ctx, a)) or 0) end

-- the row's var and value (Gen4Commands.BW_CONDITIONS is the same table)
function M.row(id) G4() return Commands.BW_CONDITIONS and Commands.BW_CONDITIONS[id] end

-- set swap `id` on or off in a save; true when the var changed
function M.set(save, id, on)
  local row = M.row(id)
  if not (row and save) then return false end
  local value = on and row[2] or 0
  if G4().getVar(save, row[1]) == value then return false end
  G4().setVar(save, row[1], value)
  return true
end

-- rebuild the current map's replacements when they changed (ov10 0x02159CC4)
function M.refresh(ctx, before)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  if not (def and def.gen5 and ow.reloadMap) then return end
  local MV = require("src.world.Gen5MapVariants")
  local after = MV.key(ctx.game and ctx.game.data, ctx.save, def.layout)
  if after ~= before then pcall(ow.reloadMap, ow, ow.map.id, "bw story swap") end
end

function Commands.g5_story_swap(ctx, id, on, apply)
  local n = v(ctx, id)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  local before = def and def.gen5 and require("src.world.Gen5MapVariants").key(ctx.game and ctx.game.data, ctx.save, def.layout)
  local changed = M.set(ctx.save, n, v(ctx, on) ~= 0)
  require("src.core.Logger").info("bw story swap %d %s%s", n, v(ctx, on) ~= 0 and "on" or "off", changed and "" or " (unchanged)")
  if changed and v(ctx, apply) ~= 0 then M.refresh(ctx, before) end
end

-- THE WARP ROWS (READ, ov10 0x02170FEC, 20 bytes each, row id - 1): u16 fly
-- flag, u16 mode, u16 the whiteout zone, u8 x / u8 y of the arrival there
-- (0x02159FA8: low byte x, high byte y), then the fly zone and its point
-- twice. The whiteout (ov20 0x0218562C, step 0 of task 0x02185694) warps to
-- row[warp id]; a map load into one of the whiteout zones sets the id itself
-- (ov20 0x02185862 -> 0x02159FE0) -- the port's src/world/Gen4Blackout.lua
-- noteEntry, which finds the same spot (two below the nurse). Rows 14 and 17
-- are not Centers ({zone, x, y} as read, unused by any 0x0D9 site).
M.WARP_ROWS = {
  { 390, 6, 8 }, { 398, 7, 12 }, { 8, 7, 12 }, { 20, 7, 12 }, { 41, 7, 12 }, { 65, 7, 12 },
  { 99, 7, 12 }, { 109, 7, 12 }, { 115, 7, 12 }, { 122, 7, 12 }, { 407, 7, 12 }, { 146, 7, 12 },
  { 413, 7, 12 }, { 147, 0x8B, 0xEC }, { 1, 7, 12 }, { 425, 7, 12 }, { 214, 0, 0 },
}

-- the whiteout point a warp id stands for, as save.lastHeal takes it
function M.healFor(id)
  local row = M.WARP_ROWS[tonumber(id) or 0]
  if not row then return nil end
  return { map = ("Z%03d"):format(row[1]), x = row[2], y = row[3], facing = "up", home = (id == 1) or nil }
end

function Commands.g5_warp_id(ctx, id)
  local n = v(ctx, id)
  if not (n >= 1 and n <= 17 and ctx.save) then return end
  ctx.save.gen5WarpId = n
  -- the whiteout goes where the id says until the next Center is entered
  -- (the game clear and the new game: home; the League's map load: its Center)
  local heal = M.healFor(n)
  local data = ctx.game and ctx.game.data
  if heal and n ~= 14 and n ~= 17 and (not data or not data.maps or data.maps[heal.map]) then
    ctx.save.lastHeal = heal
  end
end

function Commands.g5_clear_bits(ctx, n)
  local k = v(ctx, n)
  if (k == 1 or k == 2) and ctx.save then
    local b = tonumber(ctx.save.gen5ClearBits) or 0
    if math.floor(b / k) % 2 == 0 then ctx.save.gen5ClearBits = b + k end
  end
end

return M
