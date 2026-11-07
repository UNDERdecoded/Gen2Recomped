-- HEARTGOLD / SOULSILVER: THE POKEGEAR RING MANAGER -- the calls the field
-- puts through by itself (pokeheartgold src/unk_02092BE8.c,
-- src/field/overlay_2_gear_phone.c, src/save_misc.c 0x280, scrcmd_c.c 148).
--
--   THE CLOCK. Every RTC minute that passes adds to a counter
--     (sub_02092E34 from sub_020555B4; the first advance after boot is not
--     counted when it is 10 minutes or more). A trigger that "bumps" sets the
--     counter to at least 9 (sub_02092E14).
--   THE CHECK (ov02_02251F20), each frame the player stands still in the
--     field (FieldInput unk0_8), on a map whose header lets calls in, once the
--     counter reaches 10 and nothing is ringing:
--     1. a set CALL TRIGGER (ov02_02252218: one at random among those set
--        whose caller is not at home -- the Day-Care man only once registered)
--        rings; one marked forcePickUp (Bike Shop, Bill, Baoba's news) is put
--        straight through (scr_seq_0003 047: PHONE0 twice, fade, RunPhoneCall)
--     2. else MTRandom() % 100 > 50 ends it (counter back to 0)
--     3. else ov02_02251FDC: a call group 0 / 1 / 2 (50 / 30 / 20 %), the
--        registered contacts of that group (book unkF) of the types that call
--        (route trainer, Kurt, gym leader, Kenji, Irwin), not at home, not
--        among the group's recent callers (save_misc unk_0280: 4 / 2 / 2 --
--        all of them recent clears the list), not National Park during the
--        contest; one at random rings. None -> counter back to 0.
--   RINGING. SEQ_SE_GS_PHONE1 every 30 frames. The ring is answered by
--     opening the Pokegear (FieldSystem_InitPokegearArgs: the caller goes in
--     the group's recent list / a trigger's flag is cleared, the manager is
--     reset, the phone opens on the call). Any other field event (a script,
--     a warp) or more than 30 seconds of RTC drops it.
--   TRIGGERS set elsewhere on the cartridge, checked here: Bill's PC full
--     (3; after encounters, registered Bill, FLAG 0x985 clear, no free box
--     space), Oak's dex progress (4; owned / 50 with its 0x988 + n flag clear),
--     Elm's Togepi hatched (0; FLAG 0x983), the Day-Care egg (5; the man
--     registered, not FLAG 0x992 without 0x99E). ScrCmd_148 sets one from a
--     script (Elm's Pokerus, 1).
--   KENJI'S DAY (sub_0202F294) rolls over with the RTC day.
--   Set from other modules: Mom's shopping (12, src/world/HgssMomSavings.lua),
--   the Bike Shop's 1024 steps (2, src/world/HgssBikeShopCall.lua), Baoba's
--   timed calls (7..11, from `minutes`) and new-Pokemon report (6, a new day;
--   src/world/HgssSafariObjects.lua).
--
-- The calls themselves: src/ui/HgssPhoneCall.lua (`call.ring`), whose plan
-- comes from the incoming branch of each handler (HgssPhoneScripts /
-- HgssPhoneOutgoing.generic rows 8..15).
--
-- Tick from OverworldController:update; answer from HgssPokegear.new.

local R = {}

R.THRESHOLD, R.CHANCE, R.MAX_ACTIVE = 10, 50, 30
R.SE_RING, R.SE_CONNECT = "SEQ_SE_GS_PHONE1", "SEQ_SE_GS_PHONE0"
-- ov02_02253C84: callerId, callScriptID, forcePickUp
R.TRIGGERS = {
  [0] = { 1, 13, false }, { 1, 7, false }, { 15, 85, true }, { 9, 93, true }, { 2, 0, false },
  { 6, 0, false }, { 24, 0, false }, { 24, 142, true }, { 24, 143, true }, { 24, 144, true },
  { 24, 145, true }, { 24, 146, true }, { 0, 27, false },
}
R.CALLING_TYPES = { [0] = true, [10] = true, [11] = true, [12] = true, [14] = true }
R.RECENT = { [0] = 4, 2, 2 }   -- _020F677C lengths
R.NATIONAL_PARK = 96

local function flag(save, id) return ((save or {}).flags or {})[("FLAG_G4_%04X"):format(id)] == true end
local function setFlag(save, id)
  save.flags = save.flags or {}
  save.flags[("FLAG_G4_%04X"):format(id)] = true
end
local function rand(n) return math.random(0, n - 1) end
R.rand = rand

local function Game() return package.loaded["src.core.Game"] end

function R.isHgss(game)
  local d = game and game.data
  if not (d and type(d.gen4_hgss_phone_call) == "table" and d.gen4_hgss_phone_call.book) then return false end
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.family and GV.family() == "hgss"
end

-- the transient manager (GearPhoneRingManager), one per game
function R.mgr(game)
  game.hgssRing = game.hgssRing or { counter = 0, active = false, ringing = false }
  return game.hgssRing
end
local function triggers(save)
  save.hgssPhoneCallTriggers = save.hgssPhoneCallTriggers or {}
  return save.hgssPhoneCallTriggers
end
local function state(save) return require("src.ui.HgssPhoneOutgoing").state(save) end

function R.registered(save, id)
  local pg = save and save.hgssPokegear
  return pg and pg.numbers and (pg.numbers[id] or pg.numbers[tostring(id)]) and true or false
end
-- the phonebook in registration order (SavePokegear_AllocAndCopyPhonebook)
function R.contacts(save)
  local pg = save and save.hgssPokegear or {}
  local out, seen = {}, {}
  for _, id in ipairs(pg.order or {}) do
    id = tonumber(id)
    if id and R.registered(save, id) and not seen[id] then out[#out + 1] = id; seen[id] = true end
  end
  local extra = {}
  for id, yes in pairs(pg.numbers or {}) do
    id = tonumber(id)
    if yes and id and not seen[id] then extra[#extra + 1] = id end
  end
  table.sort(extra)
  for _, id in ipairs(extra) do out[#out + 1] = id end
  return out
end

-- the map header the player is on (MapHeader ids, as the book's mapId)
function R.headerId(game, ow)
  ow = ow or (Game() and Game().overworld)
  local data = game.data or {}
  local mapId = (ow and ow.map and ow.map.id) or ((game.save or {}).player or {}).map
  local def = mapId and (data.maps or {})[mapId]
  return def and tonumber(def.header), mapId
end
local function header(game, id)
  local okG, Gear = pcall(require, "src.ui.HgssPokegear")
  local hs = okG and Gear.headers(game.data) or nil
  return hs and id and hs[id]
end

-- sub_02092E14: set a trigger, optionally bumping the clock to one minute short
function R.setTrigger(game, id, bump)
  triggers(game.save)[id] = true
  local m = R.mgr(game)
  if bump and m.counter < R.THRESHOLD - 1 then m.counter = R.THRESHOLD - 1 end
end

-- gearRingingManagerReset
function R.reset(game)
  local m = R.mgr(game)
  m.counter, m.active, m.ringing, m.activeSince, m.ringT = 0, false, false, nil, 0
  m.caller, m.kind, m.script, m.trigger, m.group, m.index, m.mapId = nil, nil, nil, nil, nil, nil, nil
end

-- sub_02092E34: minutes passed on the RTC
function R.minutes(game, n)
  local m = R.mgr(game)
  if not m.counted then
    m.counted = true
    if n >= 10 then return end
  end
  m.counter = m.counter + n
  -- sub_02092E54: Baoba's timed calls (src/world/HgssSafariObjects.lua)
  pcall(function() require("src.world.HgssSafariObjects").minuteCheck(game) end)
end

-- --------------------------------------------------------------- triggers
local function ownedNational(game)
  local ok, S = pcall(require, "src.ui.HgssPhoneScripts")
  return ok and S.dexCount(game, "national", "owned") or 0
end
-- sub_02093070 / sub_020930C4 (after an encounter), sub_02093134 (a hatch),
-- sub_0209316C (the Day-Care's egg): checked on the field instead
function R.checkTriggers(game)
  local save = game.save
  -- Bill: the boxes full
  if R.registered(save, 9) and not flag(save, 0x985) and not triggers(save)[3] then
    local ok, S = pcall(require, "src.ui.HgssPhoneScripts")
    if ok and S.emptySpots(save) == 0 then R.setTrigger(game, 3, true) end
  end
  -- Oak: every 50 owned, until acknowledged
  if R.registered(save, 2) and not triggers(save)[4] then
    local band = math.min(9, math.floor(ownedNational(game) / 50))
    if band > 0 and not flag(save, 0x988 + band) then R.setTrigger(game, 4, false) end
  end
  -- Elm: the Togepi from his egg hatched (MonIsFromTogepiEgg: a Togepi the
  -- player hatched after Elm's assistant gave the egg)
  if not flag(save, 0x983) and flag(save, 0x70) then
    for _, mon in ipairs(save.party or {}) do
      local sp = tonumber(mon.species) or tonumber(tostring(mon.species):match("(%d+)$"))
      if sp == 175 and not mon.isEgg and not mon.egg and (mon.hatched or mon.eggMet or mon.metAsEgg) then
        R.setTrigger(game, 0, true); setFlag(save, 0x983)
        break
      end
    end
  end
  -- the Day-Care man: a new egg waiting
  local okD, D = pcall(require, "src.pokemon.Gen4DayCare")
  if okD and D.hasEgg(save) then
    local st = state(save)
    local dc = D.store(save, false)
    local key = tostring(dc and dc.personality)
    if st.eggCalled ~= key then
      st.eggCalled = key
      if R.registered(save, 6) and not (flag(save, 0x992) and not flag(save, 0x99E)) then
        R.setTrigger(game, 5, true)
      end
    end
  end
end

-- ov02_02252218: one of the set triggers whose caller is not at home
function R.pickTrigger(game, headerId)
  local pc = game.data.gen4_hgss_phone_call
  local list = {}
  local set = triggers(game.save)
  for i = 0, #R.TRIGGERS do
    if set[i] then
      local e = pc.book[R.TRIGGERS[i][1]]
      if e and e.id == 6 then
        if R.registered(game.save, 6) then list[#list + 1] = i end
      elseif not (e and e.mapId == headerId) then
        list[#list + 1] = i
      end
    end
  end
  if #list == 0 then return nil end
  return list[rand(#list) + 1]
end

-- THE CALL GROUP OF EACH CONTACT (PhoneBookEntry unkF), for a cache imported
-- before the importer kept it: `tel/pmtel_book.dat` byte 15 of each 20-byte
-- row, the same in HeartGold and SoulSilver (pokeheartgold files/tel/
-- pmtel_book.json `unkF`, checked against both ROMs' books -- scratch
-- enc_parity/phone_groups.lua). Without it every contact read as group 0, so
-- the 30% / 20% rolls for groups 1 and 2 never rang anyone.
R.CALL_GROUPS = { [0] = 0, 0, 1, 0, 0, 1, 0, 0, 1, 2, 1, 0, 0, 2, 0, 1, 0, 2, 2, 0, 0, 0, 0, 0, 1, 0, 2, 2,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 0, 2, 2, 1, 1, 2, 2,
  2, 2, 2, 2, 1, 0, 0, 2, 2, 2, 1 }
function R.callGroup(e, id)
  if e and e.callGroup ~= nil then return tonumber(e.callGroup) or 0 end
  return R.CALL_GROUPS[tonumber(id) or -1] or 0
end

-- ov02_02251FDC: a random caller
function R.pickRandom(game, headerId)
  local pc = game.data.gen4_hgss_phone_call
  local save = game.save
  local r = rand(1000)
  local group = (r < 500 and 0) or (r < 800 and 1) or 2
  local pool = {}
  for _, id in ipairs(R.contacts(save)) do
    local e = pc.book[id]
    if e and R.callGroup(e, id) == group and R.CALLING_TYPES[e.type] then pool[#pool + 1] = id end
  end
  if #pool == 0 then return 0 end
  local st = state(save)
  st.recent = st.recent or {}
  local recent = st.recent[group] or {}
  st.recent[group] = recent
  if #recent == #pool then for k in pairs(recent) do recent[k] = nil end end
  local isRecent = {}
  for _, id in ipairs(recent) do isRecent[id] = true end
  local h = tonumber(os.date("*t").hour) or 12
  local contest = flag(save, 0x996)
  local takeover = (function() local ok, S = pcall(require, "src.ui.HgssPhoneScripts"); return ok and S.rocketTakeover(save) end)()
  local out = {}
  for _, id in ipairs(pool) do
    local e = pc.book[id]
    local skip = e.mapId == headerId or isRecent[id]
    if id == 8 and (h % 3 == 2 or takeover) then skip = true end
    if e.mapId == R.NATIONAL_PARK and contest then skip = true end
    if not skip then out[#out + 1] = id end
  end
  if #out == 0 then return 0 end
  local pick = out[math.floor(rand(#out * 100) / 100) + 1]
  local m = R.mgr(game)
  m.caller, m.kind, m.script, m.group, m.index = pick, 0, 0, group, #pool
  m.active, m.ringing, m.activeSince, m.ringT = true, true, os.time(), 0
  return #out
end

-- sub_0202AB18: the answered caller joins its group's recent callers
function R.remember(save, group, index, caller)
  local st = state(save)
  st.recent = st.recent or {}
  local list = st.recent[group] or {}
  st.recent[group] = list
  local len = R.RECENT[group] or 2
  if #list < len then list[#list + 1] = caller return end
  if index == len + 1 then
    for k in pairs(list) do list[k] = nil end
    list[1] = caller
    return
  end
  table.remove(list, 1)
  list[#list + 1] = caller
end

-- ------------------------------------------------------------------ check
local function push(game, call, onDone)
  local okC, Call = pcall(require, "src.ui.HgssPhoneCall")
  if not (okC and Call.available(game)) then return false end
  game.stack:push(Call.new(game, call, onDone))
  return true
end

-- ov02_02251F20; answers true when a call was put straight through
function R.check(game, ow)
  local m = R.mgr(game)
  local headerId = R.headerId(game, ow)
  local h = header(game, headerId)
  if h and h.incomingCalls == false then return false end
  if m.active or m.counter < R.THRESHOLD then return false end
  local t = R.pickTrigger(game, headerId)
  if t then
    local row = R.TRIGGERS[t]
    m.caller, m.kind, m.script, m.trigger = row[1], 3, row[2], t
    m.active, m.activeSince, m.ringT = true, os.time(), 0
    if row[3] then
      -- scr_seq_0003 047: the call is put through without the Pokegear
      local call = R.answer(game, true)
      pcall(function() require("src.core.Sound").playSe(game.data, R.SE_CONNECT) end)
      if call and push(game, call, nil) then return true end
      return false
    end
    m.ringing = true
    return false
  end
  if rand(100) > R.CHANCE then m.counter = 0 return false end
  if R.pickRandom(game, headerId) == 0 then m.counter = 0 end
  return false
end

-- FieldSystem_InitPokegearArgs: the Pokegear opened (or a forced call
-- connected) while the manager is active -- the call to run, and the
-- bookkeeping the cartridge does at launch
function R.answer(game, forced)
  if not R.isHgss(game) then return nil end
  local m = R.mgr(game)
  if not m.active or not m.caller then return nil end
  local call = { caller = m.caller, kind = m.kind or 0, id = m.script or 0, ring = true, forced = forced }
  if m.kind == 3 and m.trigger then
    triggers(game.save)[m.trigger] = nil
  elseif m.kind == 0 then
    R.remember(game.save, m.group or 0, m.index or 0, m.caller)
  end
  R.reset(game)
  return call
end

-- ------------------------------------------------------------------- tick
function R.tick(ow)
  local G = Game()
  if not (G and G.save and R.isHgss(G)) then return end
  local game, m = G, R.mgr(G)
  local now = os.time()
  -- the RTC's minutes (sub_02055478 -> sub_020555B4) and day (sub_0202F294)
  local minute = math.floor(now / 60)
  if not m.lastMinute or minute < m.lastMinute then m.lastMinute = minute
  elseif minute > m.lastMinute then
    R.minutes(game, minute - m.lastMinute)
    m.lastMinute = minute
  end
  local okD, Daily = pcall(require, "src.script.Gen4Daily")
  if okD and Daily.civilDay then
    local st = state(game.save)
    local today = Daily.civilDay()
    local last = tonumber(st.kenjiDay)
    if last ~= today then
      st.kenjiDay = today
      if last then require("src.ui.HgssPhoneScripts").kenjiNewDay(game.save, today - last) end
    end
  end
  -- GearPhoneRingManager_HandleTimeAdvance: a ring older than 30 s drops
  if m.active and m.activeSince and now - m.activeSince > R.MAX_ACTIVE then R.reset(game) end
  -- any field event but the menu drops a ring (FieldSystem_Control)
  local mapId = ow and ow.map and ow.map.id
  local running = ow and ow.runner and ow.runner.isRunning and ow.runner:isRunning()
  if m.active and (running or (m.mapId and m.mapId ~= mapId)) then R.reset(game) end
  if m.active then m.mapId = mapId end
  -- the ring
  if m.ringing then
    m.ringT = (m.ringT or 0) + 1
    if m.ringT % 30 == 1 then
      pcall(function() require("src.core.Sound").playSe(game.data, R.SE_RING) end)
    end
  end
  -- standing still in the field (FieldInput unk0_8)
  if running or not ow or (ow.player and ow.player.moving) or #(ow.scriptMoves or {}) > 0 then return end
  if game.stack and game.stack.top and game.stack:top() ~= ow then return end
  R.checkTriggers(game)
  R.check(game, ow)
  if m.active then m.mapId = mapId end
end

return R
