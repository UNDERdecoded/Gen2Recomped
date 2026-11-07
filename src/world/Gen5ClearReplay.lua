-- src/world/Gen5ClearReplay.lua -- BLACK / WHITE: SCRIPT 9601 FOR SAVES THAT
-- CLEARED THE GAME BEFORE THE PORT RAN IT.
--
-- The game clear (0x156, either kind) ends by running shared script 9601
-- (ov10 0x0215F734 step 10 -> 0x02158A20, literal 0x2581; member 866 S02DF).
-- Until gen5-script-link-v20's lowering (Gen4ScriptVM `bwgameclear`) the port
-- never ran it, so every save cleared before then lacks the post-game layout
-- -- flag 0x960 first of all, which the Super lines, the Royal Unova and the
-- cities' post-game talk all wait for. On such a save's next BW map load
-- this applies 9601's writes once, decoded from the script (READ, member 866):
--
--   S02DF  if flag 0x960 is clear: S0444 (below); else if flag 0x97B is
--          clear: S04D7 (below). Then: healparty; 0x0D9 1; 0x0DC
--          (391, 1, 5, 0, 6) the special location; set 0x966, 0x170; for
--          each roaming-legend pair (shown flag, caught flag) -- (0x289,
--          0xA6) (0x28A, 0xA7) (0x28B, 0xA8) (0x2EE, 0x139) (0x2FE, 0x133)
--          (0x321, 0x152) (0x32A, 0x15C) -- clear the first when it is set
--          and the second is not
--   S0444  set 0x960; 0x0DA 1,0,0; clear 0x97C, 0x257; 0x40A2 = 3; clear
--          0xB9; 0x0DA 5,0,1; set 0x29D; 0x0E4 1; clear 0x32F, 0x30C; 0x40D2
--          = 1; 0x4085 = 2; clear 0x2E0, 0x2C4, 0x2C3; set 0x334; clear 0x2CC,
--          0x2C2, 0x2CD; set 0x2E4, 0x2F8; 0x40D0 = 1; clear 0x2CE; set 0x163;
--          0x4077 = 1 unless it is 2
--   S04D7  set 0x97B; clear 0x331; set 0x200; 0x0E4 2
--
-- No warps and no messages anywhere in it. Left out here: the heal (a map
-- load is no place for one). 0x0DA / 0x0D9 / 0x0E4 (src/script/
-- Gen5StorySwaps.lua) are applied: S0444's story swaps 1 off and 5 on, the
-- warp id 1, the clear bits 1 (S0444) and 2 (S04D7). The Champion's clear
-- (kind 1) runs 9601 a second time -- the S04D7 branch. The story's OTHER
-- swaps (castle, bedroom ...) an old cache never ran are not guessed here.
--
-- The marker is save.gen5Clear9601, set by g4_bw_game_clear (Gen4Commands)
-- every time the VM is about to run 9601 itself. A save without it is one
-- the old port cleared, whatever flag 0x960 says (an interim build set that
-- flag alone on map load, which would make 9601 skip S0444).

local M = {}

M.S0444 = {
  set = { 0x960, 0x29D, 0x334, 0x2E4, 0x2F8, 0x163 },
  clear = { 0x97C, 0x257, 0xB9, 0x32F, 0x30C, 0x2E0, 0x2C4, 0x2C3, 0x2CC, 0x2C2, 0x2CD, 0x2CE },
  vars = { { 0x40A2, 3 }, { 0x40D2, 1 }, { 0x4085, 2 }, { 0x40D0, 1 } },
}
M.S04D7 = { set = { 0x97B, 0x200 }, clear = { 0x331 } }
M.TAIL = { set = { 0x966, 0x170 } }
M.LEGENDS = { { 0x289, 0xA6 }, { 0x28A, 0xA7 }, { 0x28B, 0xA8 }, { 0x2EE, 0x139 },
              { 0x2FE, 0x133 }, { 0x321, 0x152 }, { 0x32A, 0x15C } }
M.HOME = { zone = 391, warp = 1, x = 5, y = 0, z = 6 }

local function name(id) return ("FLAG_G4_%04X"):format(id) end

local function apply(save, block)
  local Flags = require("src.script.Flags")
  for _, f in ipairs(block.set or {}) do Flags.set(save, name(f)) end
  for _, f in ipairs(block.clear or {}) do Flags.clear(save, name(f)) end
  local G4 = require("src.script.Gen4Commands")
  for _, v in ipairs(block.vars or {}) do G4.setVar(save, v[1], v[2]) end
end

-- one run of S02DF; `first` = this save has never run S0444
function M.run(save, first)
  local Flags = require("src.script.Flags")
  local G4 = require("src.script.Gen4Commands")
  local Swaps = require("src.script.Gen5StorySwaps")
  local function bits(n)
    local b = tonumber(save.gen5ClearBits) or 0
    if math.floor(b / n) % 2 == 0 then save.gen5ClearBits = b + n end
  end
  if first then
    apply(save, M.S0444)
    Swaps.set(save, 1, false)
    Swaps.set(save, 5, true)
    bits(1)
    if G4.getVar(save, 0x4077) ~= 2 then G4.setVar(save, 0x4077, 1) end
  elseif not Flags.get(save, name(0x97B)) then
    apply(save, M.S04D7)
    bits(2)
  end
  save.gen5WarpId = 1
  save.gen5SpecialLocation = { zone = M.HOME.zone, warp = M.HOME.warp, x = M.HOME.x, y = M.HOME.y, z = M.HOME.z }
  apply(save, M.TAIL)
  for _, p in ipairs(M.LEGENDS) do
    if Flags.get(save, name(p[1])) and not Flags.get(save, name(p[2])) then Flags.clear(save, name(p[1])) end
  end
end

-- THE STORY SWAPS A SAVE MADE BEFORE 0x0DA WAS LOWERED NEVER GOT
-- (gen5-script-link-v21, src/script/Gen5StorySwaps.lua). Each of the ten
-- 0x0DA sites is keyed on a var or flag the SAME script block writes beside
-- it (READ, Black /a/0/5/7), applied in story order so a later "off" wins:
--   M0782 @1002 id 6 on  -- the bedroom battle's block sets 0x4081 = 2 (@1747)
--   M0638 @1374 id 6 off -- sets 0x407D = 1 (@1368), the Running Shoes
--   M0310 @3384 id 0 off -- sets 0x40AA = 4 (@3348), Lenora's Moon Stone
--   M0228 @331  id 4 on  -- sets 0x4097 = 3 (@313), Brycen's Freeze Badge
--   M0770 @796  id 7 on  -- the block then sets 0x40C9 = 1 (@941); @355 sets
--                           0x40C9 = 0 and id 7 from a temp var -- so id 7 is
--                           on exactly while 0x40C9 == 1
--   M0288 @409  id 1 on  -- sets flag 0x97C (@417), the castle rising
--   M0556 @1199 id 3 on  -- inside the block that sets 0x40B6 = 2 (@835)
-- (M0866's two, after the clear, are the replay's below.) Var keys hold
-- "at least the value written"; flag keys "set".
M.SWAP_SITES = {
  { id = 6, on = true,  var = 0x4081, at = 2 },
  { id = 6, on = false, var = 0x407D, at = 1 },
  { id = 0, on = false, var = 0x40AA, at = 4 },
  { id = 4, on = true,  var = 0x4097, at = 3 },
  { id = 7, on = true,  var = 0x40C9, eq = 1 },
  { id = 1, on = true,  flag = 0x97C },
  { id = 3, on = true,  var = 0x40B6, at = 2 },
}
function M.backfillSwaps(save)
  local Flags = require("src.script.Flags")
  local G4 = require("src.script.Gen4Commands")
  local Swaps = require("src.script.Gen5StorySwaps")
  local done = {}
  for _, site in ipairs(M.SWAP_SITES) do
    local hit
    if site.flag then hit = Flags.get(save, name(site.flag))
    elseif site.eq then hit = G4.getVar(save, site.var) == site.eq
    else hit = G4.getVar(save, site.var) >= site.at end
    if hit then
      Swaps.set(save, site.id, site.on)
      done[#done + 1] = ("%d %s"):format(site.id, site.on and "on" or "off")
    end
  end
  return done
end

-- on a BW map load, once each: the story swaps back-filled, then -- for a
-- save the old port cleared -- 9601 (twice when it also beat the Champion),
-- which turns swap 1 off again after the castle. Returns true when it did
-- something
-- THE AMITY COUNTER'S LEFTOVER. Before it learned to skip BW maps,
-- OverworldState:gen4CountAmityStep counted every step into var 0x403A
-- (capped at 10000) on Black / White too -- the story swap var of 0x0DA id 9,
-- map-variant condition 12 (== 0x1028). It touched no other swap var. No
-- script writes id 9: the ten 0x0DA sites (Black /a/0/5/7, READ) use ids 0,
-- 1, 3, 4, 5, 6 and 7 only, so the value the story leaves there is 0. Once
-- per save, its own marker (saves already back-filled get it too).
function M.cleanAmityVar(save)
  if save.gen5AmityVarClean then return false end
  save.gen5AmityVarClean = true
  local G4 = require("src.script.Gen4Commands")
  local was = G4.getVar(save, 0x403A)
  if was ~= 0 then
    G4.setVar(save, 0x403A, 0)
    require("src.core.Logger").info("gen5: var 0x403A reset from %d (the old Amity step count)", was)
    return true
  end
  return false
end

function M.onMapLoad(save)
  if type(save) ~= "table" then return false end
  local did = M.cleanAmityVar(save)
  if not save.gen5SwapBackfill then
    save.gen5SwapBackfill = true
    local done = M.backfillSwaps(save)
    if #done > 0 then
      did = true
      require("src.core.Logger").info("gen5: story swaps back-filled: %s", table.concat(done, ", "))
    end
  end
  return M.maybeApply(save) or did
end

-- a save the old port cleared gets 9601 once (twice when it also beat the
-- Champion). Returns true when it did something
function M.maybeApply(save)
  if type(save) ~= "table" or not save.gen5GameClear or save.gen5Clear9601 then return false end
  M.run(save, true)
  if save.gen5ChampionClear then M.run(save, false) end
  save.gen5Clear9601 = true
  require("src.core.Logger").info("gen5: script 9601 replayed for a save cleared before it ran (champion %s)",
    tostring(save.gen5ChampionClear == true))
  return true
end

return M
