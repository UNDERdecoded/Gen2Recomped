-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- ALTERNATE FORMS IN BATTLE (Platinum, HGSS, Black / White). Installed onto
-- BattleState from its foot; the out-of-battle half is
-- src/pokemon/Gen45FormData.lua.
--
-- A battle form is shown on the BATTLER (picture, and for a stats form its
-- personal row: types, ability, stats) -- the party Pokemon keeps its own
-- form unless the cartridge writes it back (Shaymin's freeze, Burmy).
--
-- READ pokeplatinum battle_lib.c BattleSystem_TriggerFormChange (HGSS
-- overlay_12 the same), run in speed order whenever the field may have
-- changed:
--   * Castform with Forecast: formNum by the weather (sunny 1, rainy 2,
--     snowy 3, else 0); the type change itself is BattleState:abilityForecast
--   * Cherrim (species only, any ability): Sunshine form 1 in sun, Overcast 0
--     otherwise -- a picture change, its Flower Gift is Gen4Damage's
--   * Arceus with Multitype: formNum = its Plate's type (the type itself is
--     Gen45FormData's definition view)
--   * Giratina Origin, outside the Distortion World and not holding the
--     Griseous Orb: Altered (subscript_giratina_form_change) -- stats and
--     ability with it
--   BattleSystem_SetBurmyForm (battle_system.c): at battle end each party
--   Burmy that was sent out takes the battle terrain's cloak (not after link,
--   frontier, safari or Pal Park battles).
-- READ Black ov093:
--   * 0x021DC738 Zen Mode (Gen45Abilities, already: HP <= max / 2)
--   * 0x021E8190 Meloetta (0x288): the Relic Song handler toggles its form
--     (param 0x13: 0 -> 1, else 0) with message 0xDE -- the hit / Sheer
--     Force conditions of that event are INFERRED (the form changes after a
--     Relic Song that dealt damage)
--   * 0x021C29B8 Shaymin (0x1EC) in form 1 given status 3 (freeze) is set to
--     form 0 for good (0x021D66D8) with message 0xDE
--   * 0x021E324C Techno Blast's Drive types (Gen45FormData.DRIVE)
-- INFERRED for BW: Castform / Cherrim / Arceus picture rules as Platinum's;
-- Burmy's cloak: the table and the loop are READ, the key's source is not
-- (see bwBurmyForm). Genesect's Drive picture as Arceus's Plate.

local M = {}
local Strings = require("src.core.Strings")
local FD = require("src.pokemon.Gen45FormData")

local CASTFORM, CHERRIM, ARCEUS, GIRATINA, SHAYMIN, MELOETTA = 351, 421, 493, 487, 492, 648
local RELIC_SONG = 547
local CASTFORM_FORM = { FIRE = 1, WATER = 2, ICE = 3 }

local function gen(battle) return ((battle and battle.data or {}).constants or {}).gen end
local function sid(b) return b and b.mon and FD.speciesId(b.mon.species) end
local function who(b) return b.isPlayer and b.name or ("Enemy " .. tostring(b.name)) end
local function shown(b)
  if b.g45Form ~= nil then return b.g45Form end
  return tonumber(b.mon and b.mon.form) or 0
end
local function weather(battle)
  local ok, W = pcall(require, "src.battle.Weather")
  return ok and W.current(battle) or nil
end
local function abilityOf(b)
  local ok, A = pcall(require, "src.battle.Abilities")
  return ok and A.of(b) or nil
end

-- show battler `b` as `form`; `full` also takes the form's personal row
function M.show(battle, b, form, full)
  if not (b and b.mon) then return end
  local proxy = {}
  for k, v in pairs(b.mon) do proxy[k] = v end
  proxy.form = form
  if full then
    local def = require("src.pokemon.Gen4Forms").definition(battle.data, proxy)
    if def then
      b.def = def
      b.curTypes = def.types
      b.abilityOverride = nil
      local ok, st = pcall(require("src.pokemon.Stats").calc, def, b.mon.level or 1,
        b.mon.ivs, nil, b.mon.evs, b.mon.nature)
      if ok and type(st) == "table" then
        local cs = {}
        for k, v in pairs(b.curStats or {}) do cs[k] = v end
        for k, v in pairs(st) do if k ~= "hp" then cs[k] = v end end
        b.curStats = cs
      end
    end
  end
  local side = b.isPlayer and "back" or "front"
  local okP, path = pcall(require("src.pokemon.Sprites").path, battle.data, b.mon.species, side,
    { mon = proxy, kind = "battle" })
  local okI, img = pcall(require("src.render.Assets").image, okP and path or nil)
  if okI and img then
    pcall(img.setFilter, img, "nearest", "nearest")
    b.sprite = img
  end
  if b.picAnim then
    local okA, pa = pcall(require("src.pokemon.PicAnim").forMon, battle.data, proxy, side)
    pa = okA and pa or nil
    -- already on screen: run it (as Gen5Transform does)
    if pa and pa.start then pcall(pa.start, pa) end
    b.picAnim = pa
  end
  b.g45Form = form
  battle.g45FormLog = battle.g45FormLog or {}
  table.insert(battle.g45FormLog, { species = sid(b), form = form, full = full and true or false })
end

local function terrain(battle)
  if battle.g45Terrain == nil then
    local ok, t = false, nil
    if gen(battle) == 4 then ok, t = pcall(require("src.battle.Gen4Battle").terrainFor, battle.game) end
    battle.g45Terrain = ok and t or false
  end
  return battle.g45Terrain or nil
end

-- BattleSystem_TriggerFormChange, for one battler
function M.sync(battle, b)
  if not (b and b.mon and (b.mon.hp or 0) > 0) then return end
  local g = gen(battle)
  if g ~= 4 and g ~= 5 then return end
  local id = sid(b)
  -- a Transformed battler wears someone else's picture (not modelled: the
  -- Transformed Origin Giratina's revert)
  if b.species and FD.speciesId(b.species) ~= id then return end
  if id == CASTFORM and abilityOf(b) == "FORECAST" then
    local t = type(b.curTypes) == "table" and b.curTypes[1] or nil
    local want = CASTFORM_FORM[t or ""] or 0
    if shown(b) ~= want then M.show(battle, b, want, false) end
  elseif id == CHERRIM then
    local want = weather(battle) == "SUN" and 1 or 0
    if shown(b) ~= want then M.show(battle, b, want, false) end
  elseif id == ARCEUS then
    local def = b.def
    if FD.hasMultitype(def, b.mon) then
      local want = FD.arceusForm(battle.data, b.mon)
      if shown(b) ~= want then M.show(battle, b, want, false) end
    end
  elseif id == FD.GENESECT and g == 5 then
    -- the Drive's palette form (READ ov093 0x021E324C; the pictures are the
    -- /a/0/0/4 form slots 708-711, imported by Gen5BattleSprites)
    local d = FD.DRIVE[FD.itemOf(b.mon) or -1]
    local want = d and d[2] or 0
    if shown(b) ~= want then M.show(battle, b, want, false) end
  elseif id == GIRATINA and g == 4 and shown(b) == 1 then
    local t = terrain(battle)
    local dw = t == "distortion_world" or t == "giratina"
    if not dw and FD.itemOf(b.mon) ~= FD.GRISEOUS_ORB then
      M.show(battle, b, 0, true)
    end
  end
end

local function each(battle, fn)
  -- BattleState:activeBattlers is an iterator (i, battler)
  if battle.activeBattlers then
    for _, b in battle:activeBattlers() do if b then fn(b) end end
    return
  end
  for _, b in ipairs({ battle.player, battle.enemy }) do if b then fn(b) end end
end

-- the BW freeze rule (ov093 0x021C29B8)
local function shayminFrozen(battle, b)
  if gen(battle) ~= 5 or sid(b) ~= SHAYMIN then return end
  if (tonumber(b.mon.form) or 0) ~= 1 then return end
  if not (b.mon.status == "FRZ" or b.mon.status == "freeze") then return end
  require("src.pokemon.Gen4Forms").setForm(battle.data, b.mon, 0)
  M.show(battle, b, 0, true)
  battle:sayNext(Strings("%s transformed!", who(b)))
end

function M.afterMove(battle, user, target, moveInst, before)
  if gen(battle) == 5 and user and user.mon and (user.mon.hp or 0) > 0
     and sid(user) == MELOETTA and moveInst and tonumber(moveInst.id) == RELIC_SONG then
    local hit = false
    for b, hp in pairs(before or {}) do
      if b ~= user and b.mon and (b.mon.hp or 0) < hp then hit = true end
    end
    if hit and abilityOf(user) ~= "SHEER_FORCE" then
      M.show(battle, user, shown(user) == 0 and 1 or 0, true)
      battle:sayNext(Strings("%s transformed!", who(user)))
    end
  end
  each(battle, function(b) shayminFrozen(battle, b) end)
end

-- BattleSystem_SetBurmyForm, at the end of the battle
-- BLACK / WHITE'S BURMY. READ: ov092 0x021B9C34 (battle end; skipped for
-- battle modes 2 and 3) calls ov010 0x0216E62C for every party slot whose
-- participation byte (+0xC2 + slot) is set; for a Burmy it looks its key up
-- in the 25-entry table ov010 0x02172554 (FD.BW_BURMY_KEY) and sets that
-- form. The key is /a/1/5/2 member 0's record [setup+8] (36 bytes), byte
-- 0x13 + [setup+0xC] (ov092 0x021B9C80). NOT LOCATED: which zone / tile
-- values fill setup+8 and +0xC, and the port draws every BW battle on the
-- default field -- so the key is INFERRED from the port's own tile class
-- (Gen5WildTables gen5Terrain): grass -> key 5, sand -> 0, cave -> 4 (the
-- cave records' terrain slot); other battles leave the cloak alone.
M.BW_TERRAIN_KEY = { grass = 5, sand = 0, cave = 4 }
local function bwBurmyForm(battle)
  local key = M.BW_TERRAIN_KEY[battle.gen5Terrain or ""]
  return key and FD.BW_BURMY_KEY[key] or nil
end

function M.finished(battle)
  local g = gen(battle)
  if g ~= 4 and g ~= 5 then return end
  if battle.kind == "link" or battle.demo or battle.pokedudeDemo or battle.safari
     or battle.palPark or battle.battleTower then return end
  local form
  if g == 5 then
    form = bwBurmyForm(battle)
    if form == nil then return end
  else
    form = FD.burmyForm(terrain(battle))
  end
  for mon in pairs(battle.g45Sent or {}) do
    if FD.speciesId(mon.species) == FD.BURMY and not (mon.isEgg or mon.egg) then
      mon.form = form
    end
  end
end

function M.install(BattleState)
  if BattleState.g45FormsInstalled then return end
  BattleState.g45FormsInstalled = true
  local switchIn = BattleState.abilitySwitchIn
  function BattleState:abilitySwitchIn(battler)
    if battler and battler.isPlayer and battler.mon then
      self.g45Sent = self.g45Sent or {}
      self.g45Sent[battler.mon] = true
    end
    pcall(M.sync, self, battler)
    local r = switchIn(self, battler)
    pcall(M.sync, self, battler)
    return r
  end
  local forecast = BattleState.abilityForecast
  function BattleState:abilityForecast(battler)
    local r = forecast(self, battler)
    pcall(M.sync, self, battler)
    return r
  end
  local perform = BattleState.performMove
  function BattleState:performMove(user, target, moveInst, ...)
    local before = {}
    pcall(each, self, function(b) if b.mon then before[b] = b.mon.hp or 0 end end)
    local r = perform(self, user, target, moveInst, ...)
    local ok, err = pcall(M.afterMove, self, user, target, moveInst, before)
    if not ok then print("Gen45FormBattle.afterMove: " .. tostring(err)) end
    return r
  end
  local eot = BattleState.endOfTurn
  function BattleState:endOfTurn(...)
    local r = eot(self, ...)
    pcall(each, self, function(b) shayminFrozen(self, b); M.sync(self, b) end)
    return r
  end
  local finish = BattleState.finish
  function BattleState:finish(...)
    if not self.g45FormsFinished then
      self.g45FormsFinished = true
      local ok, err = pcall(M.finished, self)
      if not ok then print("Gen45FormBattle.finished: " .. tostring(err)) end
    end
    return finish(self, ...)
  end
end

-- Judgment / Techno Blast in Black / White (effect 268, absent from the BW
-- table so both were Normal): the held Plate's / Drive's type. Embargo and
-- Klutz turn it off (INFERRED, as Gen 4's Judgment).
function M.installG5(G5)
  if not (G5 and G5.DEF and G5.NAMES) or G5.DEF.BW_JUDGMENT then return end
  G5.DEF.BW_JUDGMENT = {
    kind = "full",
    moveType = function(ctx)
      local u = ctx.user
      local item = FD.itemOf(u and u.mon)
      if not item or (u and u.bwEmbargo) or abilityOf(u) == "KLUTZ" then return ctx.move.type end
      return FD.heldType(item) or ctx.move.type
    end,
  }
  G5.NAMES[268] = "BW_JUDGMENT"
end

return M
