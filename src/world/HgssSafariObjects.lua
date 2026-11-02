-- HEARTGOLD / SOULSILVER'S SAFARI ZONE: THE OBJECTS, THE AREA LEVELS AND
-- BAOBA'S CALLS -- the save-side half of the area customizer (the six-area
-- arrangement itself is src/world/HgssSafariZone.lua).
--
-- pokeheartgold, read off:
--
--   * THE OBJECTS (unk_02097268.c sObjects / GetSafariObjectConfig): 24
--     kinds, each a build model, a footprint (width x height tiles) and an
--     object type (1 plains, 2 forest, 3 peak, 4 water, 0 none). An area holds
--     up to 30 { id, x, y, z } (safari_zone.c SafariZone_AddObjectToArea /
--     SafariZone_RemoveObjectFromArea); `save.hgssSafari.sets[n].areas[i].objects`.
--   * THE AREA LEVELS (SafariZone_AddToAllAreaLevels): a count per AREA NUMBER
--     (not per slot), capped at 255, raised by the days passed for each
--     distinct area of set 0; `sets[0].levels[areaNo]`.
--   * THE OBJECT LEVELS (SafariZoneAreaSet_GetObjectsInArea): each placed
--     object of a type adds getObjectLevelBoost(areaLevel / 10, type) -- 1..7
--     by sObjectLevelBoosts -- to its type's level; the bonus encounter slots
--     unlock on those levels (src/world/HgssSafariZone.lua M.slots).
--   * THE DAYS (SaveData_SafariZone_CheckAreasWithUpdatedEncounters, from
--     sub_02055508 on a new RTC day and from SafariZoneAction 1): nothing
--     until Baoba has unlocked objects (objectUnlockLevel > 0); during a
--     Safari game the days are banked in the zone level (unk5F8) and spent
--     when the game ends; otherwise the area levels rise and the areas whose
--     morning tables changed (all five tables, set 0) are written to the
--     phone state with CALL_TRIGGER_BAOBA_NEW_POKEMON (6), or the trigger
--     cleared when none changed.
--   * BAOBA'S TIMED CALLS (unk_02092BE8.c sub_02092E54, on each RTC minute the
--     ring manager counts): none while a trigger 7..11 is set; nothing with
--     VAR 0x4057 under 3 or the unlock level at 4; at 3, three hours of play
--     since the mark (sub_0202F798: IGT minutes - unk5FA >= 180; 2 once the
--     IGT is maxed at 59,999 minutes) rings NEXT_TEST (7); from 6, with the
--     National Dex, MORE / EVEN MORE objects (8 / 9 / 10 by the unlock level)
--     or MEMORY LOSS (11) when the IGT is maxed.
--   * THE PHONE (phone_scripts_baoba.c): 143 / 144 raise the unlock level by
--     1 and re-mark the IGT, 145 / 146 by 4; the trigger-6 call
--     (scriptType 15, GearPhoneCall_Baoba) names the changed areas: 667
--     38 / 39 none, 24 / 25 six, else 14 + 2 (n - 1) / 15 + 2 (n - 1) with the
--     area names (msg_0428) in slots 10.. .
--   * THE FIELD COMMANDS (overlay_03_scrcmds.c, ov02_0224E754): 718 buffers an
--     object's name (msg_0430 14 + id), 719 the object in front of the player
--     (its id, 255 for none, and its index), 720 takes it out of the area.

local M = {}

M.MAX_OBJECTS = 30
M.TRIGGER_NEW_POKEMON = 6
M.VAR_BAOBA = 0x4057
-- sObjects: { width, height, type }
M.OBJECTS = {
  [0] = { 1, 1, 1 }, { 1, 1, 1 }, { 1, 1, 1 },                 -- shrubbery, red / white flower
  { 2, 2, 2 }, { 2, 2, 2 }, { 2, 2, 2 },                       -- tree, stump, branches
  { 1, 1, 3 }, { 2, 2, 3 }, { 2, 2, 3 },                       -- small / big / mossy rock
  { 2, 2, 4 }, { 2, 2, 4 }, { 2, 2, 4 },                       -- puddle, fountain, water hole
  { 2, 1, 0 }, { 1, 1, 0 }, { 1, 1, 0 }, { 2, 1, 0 }, { 1, 2, 0 }, -- bench, fences
  { 1, 1, 0 }, { 1, 1, 0 }, { 1, 1, 0 }, { 1, 1, 0 }, { 1, 1, 0 }, { 1, 1, 0 }, { 1, 1, 0 },
}
-- sObjectLevelBoosts
M.BOOSTS = { { 1, 5, 10, 15, 20 }, { 2, 6, 11, 16, 21 }, { 3, 7, 12, 17, 22 }, { 4, 8, 13, 18, 23 } }

local function Zone() return require("src.world.HgssSafariZone") end
local function flag(save, id) return ((save or {}).flags or {})[("FLAG_G4_%04X"):format(id)] == true end
local function getVar(save, id)
  local ok, C = pcall(require, "src.script.Gen4Commands")
  if ok and C.getVar then return math.floor(tonumber(C.getVar(save, id)) or 0) end
  return 0
end

function M.config(id)
  local c = M.OBJECTS[tonumber(id) or 0] or M.OBJECTS[0]
  return { width = c[1], height = c[2], type = c[3] }
end

-- getObjectLevelBoost
function M.boost(days, objectType)
  if objectType == 0 then return 0 end
  local row = M.BOOSTS[objectType]
  for i = 1, 5 do
    if days < row[i] then return i end
  end
  return days < 25 and 6 or 7
end

-- SafariZoneAreaSet_GetObjectsInArea: the four type levels of slot idx (0..5)
function M.levelsInArea(set, idx)
  local out = { 0, 0, 0, 0 }
  local area = set and set.areas and set.areas[idx + 1]
  if not area then return out end
  local areaLevel = math.floor((tonumber((set.levels or {})[area.area]) or 0) / 10)
  for _, obj in ipairs(area.objects or {}) do
    local t = M.config(obj.id).type
    if t ~= 0 then out[t] = math.min(255, out[t] + M.boost(areaLevel, t)) end
  end
  return out
end

-- SafariZone_AddToAllAreaLevels on set 0
function M.addToAreaLevels(st, n)
  if n <= 0 then return end
  local set = st.sets[0]
  set.levels = set.levels or {}
  local seen = {}
  for i = 1, 6 do
    local no = set.areas[i] and set.areas[i].area
    if no and not seen[no] then
      seen[no] = true
      set.levels[no] = math.min(255, (tonumber(set.levels[no]) or 0) + n)
    end
  end
end

function M.unlockLevel(st) return math.floor(tonumber(st and st.unlockLevel) or 0) end
-- SafariZone_IncObjectUnlockLevel (SafariZone_SetObjectUnlockLevel caps at 4;
-- the field is 6 bits wide, so the u8 sum wraps first)
function M.incUnlockLevel(save, n)
  local st = Zone().state(save)
  if not st then return 0 end
  st.unlockLevel = math.min(4, (M.unlockLevel(st) + n) % 64)
  return st.unlockLevel
end

-- the IGT in minutes (hours * 60 + minutes, as a u16), from the play clock
function M.igtMinutes(save)
  local secs = tonumber(save and save.playTime) or 0
  -- the IGT stops at 999:59
  return math.min(59999, math.floor(secs / 60))
end
-- sub_0202F784
function M.markIgt(save)
  local st = Zone().state(save)
  if st then st.igtMark = M.igtMinutes(save) end
end
-- sub_0202F798
function M.igtElapsed(save, hours)
  local st = Zone().state(save)
  local now = M.igtMinutes(save)
  if now - (tonumber(st and st.igtMark) or 0) >= hours * 60 then return 1 end
  if now >= 59999 then return 2 end
  return 0
end

-- the morning tables of set 0's six slots, five kinds each, as a key
local function tablesKey(data, save)
  local set0 = Zone().state(save).sets[0]
  local keys = {}
  for i = 0, 5 do
    keys[i] = {}
    for kind = 0, 4 do
      local parts = {}
      for _, s in ipairs(Zone().slots(data, save, i, kind, 0, set0)) do
        parts[#parts + 1] = ("%d:%d"):format(tonumber(s.species) or 0, tonumber(s.level) or 0)
      end
      keys[i][kind] = table.concat(parts, ",")
    end
  end
  return keys
end

-- SaveData_SafariZone_CheckAreasWithUpdatedEncounters
function M.checkAreas(data, save, days)
  local st = Zone().state(save)
  if not st or M.unlockLevel(st) == 0 or (tonumber(days) or 0) <= 0 then return end
  if save.safari and save.safari.hgss then
    st.level = (tonumber(st.level) or 0) + days
    return
  end
  local before = tablesKey(data, save)
  M.addToAreaLevels(st, days)
  local after = tablesKey(data, save)
  local set0 = st.sets[0]
  local areas, has = {}, {}
  for i = 0, 5 do
    local no = set0.areas[i + 1].area
    if not has[no] then
      for kind = 0, 4 do
        if before[i][kind] ~= after[i][kind] then
          has[no] = true
          areas[#areas + 1] = no
          break
        end
      end
    end
  end
  save.hgssPhoneCallTriggers = save.hgssPhoneCallTriggers or {}
  if #areas == 0 then
    save.hgssPhoneCallTriggers[M.TRIGGER_NEW_POKEMON] = nil
    st.newAreas = {}
  else
    save.hgssPhoneCallTriggers[M.TRIGGER_NEW_POKEMON] = true
    while #areas > 6 do table.remove(areas) end
    st.newAreas = areas
  end
end

-- sub_02055508's call (the field's new day)
function M.onDays(save, days)
  local G = package.loaded["src.core.Game"]
  M.checkAreas(G and G.data, save, tonumber(days) or 0)
end

-- SafariZoneAction 1: the days banked during the game
function M.gameEnded(save)
  local st = Zone().state(save)
  local lvl = tonumber(st and st.level) or 0
  if lvl ~= 0 then
    local G = package.loaded["src.core.Game"]
    M.checkAreas(G and G.data, save, lvl)
    st.level = 0
  end
end

-- sub_02092E54: Baoba's timed triggers, on a counted RTC minute
function M.minuteCheck(game)
  local save = game and game.save
  local st = save and Zone().state(save)
  if not st then return end
  local trig = save.hgssPhoneCallTriggers or {}
  for i = 7, 11 do if trig[i] then return end end
  local v = getVar(save, M.VAR_BAOBA) % 256
  local unlock = M.unlockLevel(st)
  if v < 3 or unlock >= 4 then return end
  local Ring = require("src.world.HgssPhoneRing")
  if v == 3 then
    if M.igtElapsed(save, 3) == 0 then return end
    Ring.setTrigger(game, 7, true)
    return
  end
  if v < 6 then return end
  if not ((save.pokedex or {}).national) then return end
  local r = M.igtElapsed(save, 3)
  if r == 0 then return end
  if r > 1 then
    Ring.setTrigger(game, unlock < 3 and 11 or 10, true)
  elseif unlock == 0 then
    Ring.setTrigger(game, 8, true)
  elseif unlock == 3 then
    Ring.setTrigger(game, 10, true)
  else
    Ring.setTrigger(game, 9, true)
  end
end

-- GearPhoneCall_Baoba (scriptType 15): queue the report on an HgssPhoneCall
function M.reportBuild(call)
  local save, bank = call.game.save, call.bank
  local st = Zone().state(save) or {}
  local areas = st.newAreas or {}
  local n = #areas
  local e, l
  if n == 0 then e, l = 38, 39
  elseif n >= 6 then e, l = 24, 25
  else
    call.extraBuffers = call.extraBuffers or {}
    local T = require("src.import.Gen4Text")
    for i, no in ipairs(areas) do
      call.extraBuffers[10 + i] = T.resolve(call.game.data, 428, no, call.game)
        or Zone().AREA_NAMES[no] or ""
    end
    e, l = 14 + 2 * (n - 1), 15 + 2 * (n - 1)
  end
  call.queue[#call.queue + 1] = { say = call:message(bank, call.girl and l or e) }
end

-- ScrCmd_718 <slot> <idVar>: msg_0430 14 + id
function M.objectName(data, game, id)
  id = math.floor(tonumber(id) or 0)
  if id >= 24 then id = 0 end
  local T = require("src.import.Gen4Text")
  return T.resolve(data, 430, 14 + id, game) or ""
end

-- ov02_0224E31C + ov02_0224E754: the object of set 0 at the matrix tile (x, z)
function M.objectAt(save, gx, gz)
  local st = Zone().state(save)
  if not st then return 255, 0 end
  local function div(a) return a >= 0 and math.floor(a / 32) or -math.floor(-a / 32) end
  local idx = div(gz - 32) * 3 + div(gx - 32)
  if idx < 0 or idx >= 6 then idx = 0 end
  -- the C `% 32` of the matrix coordinate (signed, truncating)
  local function mod(a) return a >= 0 and a % 32 or -((-a) % 32) end
  local lx, lz = mod(gx), mod(gz)
  local area = st.sets[0].areas[idx + 1]
  for i, obj in ipairs(area and area.objects or {}) do
    local c = M.config(obj.id)
    local ox, oz = tonumber(obj.x) or 0, tonumber(obj.z) or 0
    if lx >= ox and lz <= oz and lx < ox + c.width and lz > oz - c.height then
      return math.floor(tonumber(obj.id) or 0), i - 1, idx
    end
  end
  return 255, 0, idx
end

-- ScrCmd_720's save half (SafariZone_RemoveObjectFromArea): slot idx, object n
function M.removeObject(save, idx, n)
  local st = Zone().state(save)
  local area = st and st.sets[0].areas[(tonumber(idx) or 0) + 1]
  local list = area and area.objects
  n = math.floor(tonumber(n) or 0)
  if not list or n < 0 or n >= #list then return false end
  table.remove(list, n + 1)
  return true
end

-- SafariZone_AddObjectToArea (what the decoration app writes)
function M.addObject(save, setNo, idx, obj)
  local st = Zone().state(save)
  local area = st and st.sets[setNo or 0] and st.sets[setNo or 0].areas[(tonumber(idx) or 0) + 1]
  if not area then return false end
  area.objects = area.objects or {}
  if #area.objects >= M.MAX_OBJECTS then return false end
  area.objects[#area.objects + 1] = { id = obj.id, x = obj.x or 0, y = obj.y or 0, z = obj.z or 0 }
  return true
end

return M
