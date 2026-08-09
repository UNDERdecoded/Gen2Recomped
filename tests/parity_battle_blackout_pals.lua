-- Parity: SET_PAL_BATTLE_BLACK darkens the whole battle screen while the
-- blackout text is up (#292).  HandlePlayerBlackOut (engine/battle/core.asm:
-- 1147-1159) runs the palette command before PrintText, and returns early in
-- OAKS_LAB.  SetPal_BattleBlack (engine/gfx/palettes.asm:22-25) sends
-- PAL_BLACK into all four BlkPacket_Battle zones (sgb_packets.asm:220): both
-- HP bars and both mon regions.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity battle blackout pals")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local BattleState = require("src.battle.BattleState")
local PaletteFX = require("src.render.PaletteFX")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")

Sound.playCry = function() end
Sound.play = function() end
Sound.playMove = function() end
Sound.playMoveCry = function() end
Sound.stopLoop = function() end
Music.playBattle = function() end
Music.play = function() end

local press = {}
local function makeGame(party)
  local save = SaveData.newGame()
  save.party = party
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return { data = Data, save = save, stack = stack,
           input = { wasPressed = function(_, b) return press[b] == true end } }
end

local function step(battle)
  press.a = true
  battle:update(1 / 60)
  press.a = false
end

-- Lose for real: 0 HP everywhere, then run the faint through onFaint.  Drain
-- to the onFinish callback, NOT to battle.result: playerMonFainted sets
-- result = "lose" in the same act that queues the blackout lines, so stopping
-- on result would miss every page under test.
local function wipeOut(battle)
  local done = false
  local prev = battle.onFinish
  battle.onFinish = function(r) done = true if prev then prev(r) end end
  battle.player.mon.hp = 0
  for _, mon in ipairs(battle.game.save.party) do mon.hp = 0 end
  battle.phase = "messages"
  battle.nextInsert = 0
  battle:onFaint(battle.player)
  local pages, blackAt = {}, {}
  for _ = 1, 1200 do
    step(battle)
    local cur = battle.current
    local text = cur and cur.text
    if text and pages[#pages] ~= text then
      pages[#pages + 1] = text
      blackAt[text] = battle.blackedOut and true or false
    end
    if done then break end
  end
  return pages, blackAt
end

local function indexOf(pages, fragment)
  for i, p in ipairs(pages) do
    if p:find(fragment, 1, true) then return i end
  end
  return nil
end

-- ------------------------------------------------------------- the palette
local pack = PaletteFX.pack(Data)
check(pack ~= nil and pack.palettes ~= nil, "the active COLORS pack has palettes")
local BLACK = pack and pack.palettes and pack.palettes.BLACK
check(BLACK ~= nil,
      "PAL_BLACK exists in the active pack (data/generated/palettes.lua:86, "
      .. "data/palettes_gbc.lua:329)")
if BLACK then
  -- sgb_palettes.asm:46 -- color 0 near-white, colors 1..3 near-black
  check(BLACK[1][1] > 200 and BLACK[1][2] > 200,
        "PAL_BLACK color 0 is the near-white paper")
  for i = 2, 4 do
    check(BLACK[i][1] < 90 and BLACK[i][2] < 90 and BLACK[i][3] < 90,
          "PAL_BLACK color " .. (i - 1) .. " is near-black ink")
  end
end

-- ------------------------------------------------------- a live wild wipe
local game = makeGame({ Pokemon.new(Data, "BULBASAUR", 5) })
local wild = BattleState.newWild(game, "RATTATA", 40)
wild.onFinish = function() end
wild:enter()
for _ = 1, 400 do
  step(wild)
  if wild.phase == "menu" then break end
end
eq(wild.phase, "menu", "the wild battle reaches its menu")
eq(wild.blackedOut, nil, "nothing is blacked out while the battle is live")
local before = wild:sgbBattlePals()
check(before ~= nil, "sgbBattlePals builds the four BlkPacket_Battle zones")
if before and BLACK then
  check(before[0] ~= BLACK and before[1] ~= BLACK
        and before[2] ~= BLACK and before[3] ~= BLACK,
        "no zone is PAL_BLACK during normal play")
end

local pages, blackAt = wipeOut(wild)
eq(wild.result, "lose", "losing the last mon resolves the battle as a loss")
local outOf = indexOf(pages, "out of")
local blacked = indexOf(pages, "blacked")
check(outOf ~= nil, "\"<PLAYER> is out of useable POKeMON!\" prints")
check(blacked ~= nil, "\"<PLAYER> blacked out!\" prints")
if outOf then
  eq(blackAt[pages[outOf]], true,
     "the screen is ALREADY dark under the first blackout line "
     .. "(RunPaletteCommand runs before PrintText, core.asm:1151-1156)")
end
if blacked then
  eq(blackAt[pages[blacked]], true, "and stays dark under the second line")
end

local after = wild:sgbBattlePals()
check(after ~= nil, "sgbBattlePals still builds four zones once blacked out")
if after and BLACK then
  eq(after[0], BLACK, "zone 0 (player HP bar) is PAL_BLACK")
  eq(after[1], BLACK, "zone 1 (enemy HP bar) is PAL_BLACK")
  eq(after[2], BLACK, "zone 2 (player mon region) is PAL_BLACK")
  eq(after[3], BLACK, "zone 3 (enemy mon region) is PAL_BLACK")
end
-- zoneColorsAt reads the same table, so the shade shader cannot disagree with
-- the packet; sample the enemy HP bar corner and the enemy pic
if BLACK then
  local barColors = wild:zoneColorsAt(24, 24)
  local picColors = wild:zoneColorsAt(120, 24)
  check(barColors == nil or barColors == BLACK,
        "the enemy HP bar's zone reads PAL_BLACK")
  check(picColors == nil or picColors == BLACK,
        "the enemy pic's zone reads PAL_BLACK")
end
-- picImage is the funnel every battler pic is drawn through, so it still has
-- to resolve something for the darkened frame
check(wild:picImage(wild.playerBackPic) ~= nil or wild.playerBackPic == nil,
      "picImage still resolves a pic while blacked out")

-- ---------------------------------------------- the Oak's Lab exception
-- core.asm:1147-1149 returns above the palette command when the starter rival
-- wins in OAKS_LAB, so that screen never darkens.
local game2 = makeGame({ Pokemon.new(Data, "BULBASAUR", 5) })
game2.save.player.map = "OAKS_LAB"
local lab = BattleState.newTrainer(game2, "OPP_RIVAL1", 1)
lab.onFinish = function() end
lab:enter()
for _ = 1, 500 do
  step(lab)
  if lab.phase == "menu" then break end
end
eq(BattleState.currentMapId(lab), "OAKS_LAB", "the battle knows it is in Oak's lab")
check(BattleState.isOaksLabStarterRival(lab), "and that this is the starter rival")
local labPages = wipeOut(lab)
eq(lab.result, "lose", "the lab rival still wins the battle")
eq(lab.blackedOut, nil,
   "the Oak's Lab starter rival never darkens the screen (core.asm:1147-1149)")
check(indexOf(labPages, "blacked") == nil,
      "and prints no blackout line either")
if BLACK then
  local labPals = lab:sgbBattlePals()
  check(labPals == nil or labPals[3] ~= BLACK,
        "the lab screen keeps its live palettes")
end

-- ------------------------------------- Route 22 RIVAL1 still blacks out
-- Same OPP_RIVAL1 class, a different map: only the lab is excepted.
local game3 = makeGame({ Pokemon.new(Data, "BULBASAUR", 5) })
game3.save.player.map = "ROUTE_22"
local r22 = BattleState.newTrainer(game3, "OPP_RIVAL1", 1)
r22.onFinish = function() end
r22:enter()
for _ = 1, 500 do
  step(r22)
  if r22.phase == "menu" then break end
end
check(not BattleState.isOaksLabStarterRival(r22), "Route 22 is not the lab")
wipeOut(r22)
eq(r22.blackedOut, true, "a Route 22 RIVAL1 wipe darkens like any other")

S.finish()
