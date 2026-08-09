-- Parity: Dig / Fly semi-invulnerable pic hide (#100).
-- Dig charge SLIDE_DOWN hides the user; a cancelled Dig release (miss /
-- type immunity) must restore the pic; a successful Dig release keeps the
-- user hidden through the dirt subanim then emerges via SE_SLIDE_MON_UP
-- (not a cyclic bounce). Self-contained: `luajit tests/parity_dig_pic.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)
local S = require("tests.harness").suite("parity dig pic")
local check, eq = S.check, S.eq

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local function makeGame(species, level, moves)
  local save = SaveData.newGame()
  local mon = Pokemon.new(Data, species, level)
  mon.moves = moves
  save.party = { mon }
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return { data = Data, save = save, stack = stack,
           input = { wasPressed = function() return true end } }
end

local function pumpToMenu(battle)
  local kinds, anims = {}, {}
  local guard = 0
  while guard < 20000 do
    guard = guard + 1
    battle.frame = (battle.frame or 0) + 1
    battle:updateFx()
    local pf = battle.picFx and battle.picFx[battle.player]
    if pf and pf.kind and not kinds[pf.kind] then
      kinds[pf.kind] = true
    end
    if battle.animPlaying and battle.animName
       and anims[#anims] ~= battle.animName then
      anims[#anims + 1] = battle.animName
    end
    if not battle:updateQueue() then
      if battle.phase == "messages" and battle.afterQueue == "menu"
         and not battle.animPlaying and not battle.current
         and #battle.queue == 0 then
        battle.phase = "menu"
        break
      end
      if battle.phase == "menu" then break end
      if not battle.animPlaying and not battle.current
         and #battle.queue == 0 then
        if battle.afterQueue == "menu" then battle.phase = "menu" end
        break
      end
    end
  end
  for _ = 1, 200 do
    battle.frame = battle.frame + 1
    battle:updateFx()
  end
  return kinds, anims
end

local function picHidden(battle)
  local pf = battle.picFx and battle.picFx[battle.player]
  return pf and pf.hidden or false
end

-- Dig charge hides; Dig miss on release restores the pic (#100 vanish).
do
  local game = makeGame("SANDSHREW", 40, { { id = "DIG", pp = 10 } })
  local battle = BattleState.newWild(game, "RATTATA", 5)
  battle.player.curMoves = game.save.party[1].moves
  local dig = battle.player.curMoves[1]
  battle.enemyAction = function() return { id = "TACKLE", pp = 35 } end
  battle.rng = function(a) return a or 0 end
  battle:resolveTurn(dig)
  pumpToMenu(battle)
  check(battle.player.invulnerable == true, "Dig charge sets invulnerable")
  check(picHidden(battle), "Dig charge leaves the user pic hidden")

  battle.rng = function(a, b)
    if a == 0 and b == 255 then return 255 end -- force Dig accuracy miss
    return a or 0
  end
  battle:resolveTurn(dig)
  local kinds, anims = pumpToMenu(battle)
  check(not picHidden(battle),
        "Dig miss on release restores the user pic (#100)")
  check(not kinds.bounce, "Dig release miss never starts a bounce pic fx")
  local sawDig = false
  for _, name in ipairs(anims) do
    if name == "DIG" then sawDig = true end
  end
  check(not sawDig, "Dig miss cancels the DIG release anim")
end

-- Dig hit: stay hidden through DIG start, emerge via slideUp (not bounce).
do
  local game = makeGame("SANDSHREW", 40, { { id = "DIG", pp = 10 } })
  local battle = BattleState.newWild(game, "SNORLAX", 40)
  battle.player.curMoves = game.save.party[1].moves
  local dig = battle.player.curMoves[1]
  battle.enemyAction = function() return { id = "TACKLE", pp = 35 } end
  battle.rng = function(a) return a or 0 end
  battle:resolveTurn(dig)
  pumpToMenu(battle)

  battle:resolveTurn(dig)
  local hiddenAtDigStart = nil
  local kinds = {}
  local guard = 0
  while guard < 20000 do
    guard = guard + 1
    battle.frame = (battle.frame or 0) + 1
    battle:updateFx()
    if battle.animPlaying and battle.animName == "DIG"
       and hiddenAtDigStart == nil then
      -- right after DIG row starts (resetPicFx already ran)
      hiddenAtDigStart = picHidden(battle)
    end
    local pf = battle.picFx and battle.picFx[battle.player]
    if pf and pf.kind then kinds[pf.kind] = true end
    if not battle:updateQueue() then
      if battle.phase == "messages" and battle.afterQueue == "menu"
         and not battle.animPlaying and not battle.current
         and #battle.queue == 0 then
        battle.phase = "menu"
        break
      end
      if battle.phase == "menu" then break end
      if not battle.animPlaying and not battle.current
         and #battle.queue == 0 then
        if battle.afterQueue == "menu" then battle.phase = "menu" end
        break
      end
    end
  end
  for _ = 1, 200 do
    battle.frame = battle.frame + 1
    battle:updateFx()
  end
  check(hiddenAtDigStart == true,
        "DIG release keeps the digger hidden until SE_SLIDE_MON_UP")
  check(kinds.slideUp == true, "Dig release uses slideUp emerge")
  check(not kinds.bounce, "Dig release must not bounce (#100)")
  check(not picHidden(battle), "Dig hit leaves the user pic shown")
end

S.finish()
