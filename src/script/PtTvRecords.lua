-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- PLATINUM'S RECORDED TV EPISODES, from the player's own play
-- (pokeplatinum src/tv_segment.c, src/unk_0202E2CC.c,
-- src/scrcmd_tv_broadcast.c; pt_cmd audit round 4).
--
-- THE STORE (TVBroadcast_SaveSegmentData, READ): per program type (1
-- interviews, 2 trainer sightings, 3 records) four own slots, each
-- { seg = segment id, played = times played (0..3), data = the segment's
-- fields }. Saving a segment id that already has a slot overwrites it only
-- once that slot has been played 3 times; otherwise the first empty slot;
-- otherwise the first slot played 3 times; otherwise nothing.
-- `save.gen4PtTvEpisodes[type][1..4]`.
--
-- AN EPISODE ID is the own slot number (1..4) -- sub_0202E578 hands back
-- `slot + 1`. Episodes from other players (Wi-Fi / record mixing) do not
-- exist offline, so the "others" passes of GetNextTVSegmentID find nothing.
--
-- RECORDED HERE (READ, each from its FieldSystem_SaveTVSegment_*):
--   type 2 seg 1 / 2  Catch That Pokemon Show (success / failure): saved at
--                     the end of a wild battle in which balls were thrown --
--                     CAPTURED_MON always, WIN / fled only after more than 2
--                     balls (BattleState counts throws, calls battleEnded)
--   type 2 seg 6      Hidden Item Breaking News (ScrCmd_SaveTVSegmentHiddenItem)
--   type 1 seg 4 / 10 / 15..18  the reporter interviews whose answer is the
--                     player's own (Your Pokemon Corner, Street Corner
--                     Personality Checkup, In-Your-Face Interview 1..4)
-- (Later rounds add the others below; the photo corner, interview 9, reads
-- the dress-up photo store, src/pokemon/Gen4Photos.lua.)
-- The other interviews (Battle Tower corner, Poketch watch, contest hall,
-- photo corner, poffin corner, Amity watch, Frontier news) read TV-side
-- state this port does not keep, so their eligibility stays FALSE, and the
-- records type (3) has no hook yet.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

M.SLOTS, M.MAX_PLAYS = 4, 3
M.TYPE_INTERVIEWS, M.TYPE_SIGHTINGS, M.TYPE_RECORDS = 1, 2, 3
M.BANK = { [1] = 415, [2] = 416, [3] = 417 }   -- TEXT_BANK_TV_PROGRAMS_INTERVIEWS / _TRAINER_SIGHTINGS / _RECORDS
M.BANK_REPORTER = 621                          -- TEXT_BANK_TV_REPORTER_INTERVIEWS
M.BANK_SPECIES, M.BANK_ITEMS = 412, 392

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return math.floor(tonumber(G4().valueOf(ctx, n)) or 0) end
local function setVar(ctx, id, v) if id then G4().setVar(ctx.save, id, v) end end

function M.slots(save, ptype)
  if not save then return {} end
  save.gen4PtTvEpisodes = save.gen4PtTvEpisodes or {}
  local all = save.gen4PtTvEpisodes
  all[ptype] = all[ptype] or {}
  return all[ptype]
end

-- TVBroadcast_SaveSegmentData
function M.save(save, ptype, seg, data)
  local s = M.slots(save, ptype)
  local function write(i) s[i] = { seg = seg, played = 0, data = data } return true end
  for i = 1, M.SLOTS do
    if s[i] and s[i].seg == seg then
      if (s[i].played or 0) >= M.MAX_PLAYS then return write(i) end
      return false
    end
  end
  for i = 1, M.SLOTS do if not (s[i] and s[i].seg) then return write(i) end end
  for i = 1, M.SLOTS do if (s[i].played or 0) >= M.MAX_PLAYS then return write(i) end end
  return false
end

-- sub_0202E578 over the own slots: the episode ids of `seg` played before
-- (wantPlayed) or never
function M.episodes(save, ptype, seg, wantPlayed)
  local out = {}
  for i, e in ipairs(M.slots(save, ptype)) do
    if e.seg == seg and (((e.played or 0) > 0) == (wantPlayed and true or false)) then out[#out + 1] = i end
  end
  return out
end

local function speciesOf(mon)
  local id = mon and mon.species
  return tonumber(id) or tonumber(tostring(id or ""):match("(%d+)%s*$")) or 0
end
local function text(ctx, bank, line)
  local data = ctx.game and ctx.game.data
  return data and data.text and data.text[require("src.import.Gen4Text").label(bank, line)] or ""
end
local function buffer(ctx, slot, value)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[slot + 1] = tostring(value or "")
end
local function trainer(ctx, slot) pcall(Commands.g4_buffer, ctx, slot, "player") end
local function word(ctx, w)
  local ok, s = pcall(function() return require("src.pokemon.Gen4EasyChat").toString(ctx.game.data, w) end)
  return ok and s or ""
end
local function seen(ctx, species)
  local dex = ctx.save and ctx.save.pokedex
  for key, flag in pairs((dex and dex.seen) or {}) do
    if (flag == true or (type(flag) == "number" and flag > 0))
       and (tonumber(key) or tonumber(tostring(key):match("(%d+)%s*$"))) == species then return true end
  end
  return false
end
local function firstHatched(save)
  for _, mon in ipairs((save and save.party) or {}) do if not mon.isEgg then return mon end end
end
-- sub_0206CED0's hasNickname: a name other than the species' own
local function nicknamed(mon, data)
  local nick = mon and mon.nickname
  if type(nick) ~= "string" or nick == "" then return nil end
  local own = data and data.text and data.text[require("src.import.Gen4Text").label(M.BANK_SPECIES, speciesOf(mon))]
  if own and own:upper() == nick:upper() then return nil end
  if mon.speciesName and tostring(mon.speciesName):upper() == nick:upper() then return nil end
  return nick
end

-- ---------------------------------------------------------------------------
-- the segments: { eligible(ctx, data), load(ctx, data) -> line }
-- ---------------------------------------------------------------------------
M.SEGMENTS = { [1] = {}, [2] = {}, [3] = {} }

-- Catch That Pokemon Show (TVSegment_LoadMessage_CatchThatPokemonShow_*)
M.SEGMENTS[2][1] = {
  eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 2, text(ctx, M.BANK_ITEMS, d.ball or 4))
    buffer(ctx, 3, d.balls)
    if d.nickname then buffer(ctx, 4, d.nickname) return 0 end    -- _Nicknamed
    return 1                                                        -- _NotNicknamed
  end }
M.SEGMENTS[2][2] = {
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, d.balls)
    return d.result == "win" and 2 or 3                             -- _Fainted / _RanAway
  end }
-- Hidden Item Breaking News
M.SEGMENTS[2][6] = {
  load = function(ctx, d)
    buffer(ctx, 0, require("src.script.PtTvBroadcast").headerLabel(ctx, d.header))
    trainer(ctx, 1)
    buffer(ctx, 2, text(ctx, M.BANK_ITEMS, d.item))
    return 10
  end }
-- Your Pokemon Corner (interview 4)
M.SEGMENTS[1][4] = {
  eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 3, word(ctx, d.word))
    if d.nickname then buffer(ctx, 2, d.nickname) return 10 end
    return 11
  end }
-- Street Corner Personality Checkup (interview 10): line 21 + type - 1
M.SEGMENTS[1][10] = { load = function(ctx, d) trainer(ctx, 0) return 21 + (d.pokemonType or 1) - 1 end }
-- In-Your-Face Interview, questions 1..4 (interviews 15..18): lines 48..51
for q = 1, 4 do
  M.SEGMENTS[1][14 + q] = { load = function(ctx, d) trainer(ctx, 0) buffer(ctx, 1, word(ctx, d.word)) return 47 + q end }
end

-- ---------------------------------------------------------------------------
-- the hooks
-- ---------------------------------------------------------------------------

-- FieldSystem_SaveTVSegment_CatchThatPokemonShow, from BattleState:finish
-- (wild battles; `ptBallsThrown` counted in BattleState:throwBall)
function M.battleEnded(battle, result)
  local game = battle and battle.game
  local save = game and game.save
  if not (save and battle.kind == "wild") then return end
  if require("src.import.Gen4ScriptBands").family ~= "platinum" then return end
  local balls = math.min(999, tonumber(battle.ptBallsThrown) or 0)
  if balls == 0 then return end
  local mon = battle.enemy and battle.enemy.mon
  if battle.safari and result == "caught" then M.safariCaught(save, mon) end
  local d = { balls = balls, species = speciesOf(mon), result = result,
              ball = tonumber(battle.ptLastBallItem) or nil }
  if result == "caught" then
    d.nickname = nicknamed(mon, game.data)
    M.save(save, M.TYPE_SIGHTINGS, 1, d)
  elseif (result == "win" or result == "run") and balls > 2 then
    M.save(save, M.TYPE_SIGHTINGS, 2, d)
  end
end

-- ScrCmd_SaveTVSegmentHiddenItem <item>
function Commands.pt_tv_hidden_item(ctx, item)
  local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
  M.save(ctx.save, M.TYPE_SIGHTINGS, 6, { item = valueOf(ctx, item), header = def and tonumber(def.header) or 0 })
end

-- ---------------------------------------------------------------------------
-- interviews (scrcmd_tv_broadcast.c)
-- ---------------------------------------------------------------------------
-- sInterviews: the reporter's line in bank 621 and the eligibility; nil
-- `eligible` is TRUE, `false` is a check on TV state this port does not keep
M.INTERVIEWS = {
  [1] = { line = 3 }, [3] = { line = 5 }, [5] = { line = 7 }, [8] = { line = 10 }, [12] = { line = 14 },
  [2] = { line = nil, eligible = false },                          -- Battle Tower corner
  [4] = { line = 6, fill = function(ctx)                            -- sub_02049268: first hatched species
    local mon = firstHatched(ctx.save)
    buffer(ctx, 0, text(ctx, M.BANK_SPECIES, speciesOf(mon)))
  end, save = function(ctx, w)
    local mon = firstHatched(ctx.save)
    M.save(ctx.save, M.TYPE_INTERVIEWS, 4, { species = speciesOf(mon), nickname = nicknamed(mon, ctx.game and ctx.game.data), word = w })
  end },
  [6] = { eligible = false }, [7] = { eligible = false }, [9] = { eligible = false },
  [10] = { line = 12, save = function(ctx, t) M.save(ctx.save, M.TYPE_INTERVIEWS, 10, { pokemonType = t }) end },
  [11] = { eligible = false }, [13] = { eligible = false }, [14] = { eligible = false }, [19] = { eligible = false },
}
for q = 1, 4 do
  M.INTERVIEWS[14 + q] = { line = 16 + q, save = function(ctx, w)
    M.save(ctx.save, M.TYPE_INTERVIEWS, 14 + q, { word = w })
  end }
end

-- sub_0202E6B0: may this interview be recorded now? Not while an unplayed
-- one of it is waiting; yes when a played one has had its 3 plays; else yes
-- when a slot is free or spent
function M.slotOpen(save, seg)
  if #M.episodes(save, M.TYPE_INTERVIEWS, seg, false) > 0 then return false end
  local played = M.episodes(save, M.TYPE_INTERVIEWS, seg, true)
  if #played > 0 then
    local s = M.slots(save, M.TYPE_INTERVIEWS)
    for _, i in ipairs(played) do if (s[i].played or 0) >= M.MAX_PLAYS then return true end end
    return false
  end
  local s = M.slots(save, M.TYPE_INTERVIEWS)
  for i = 1, M.SLOTS do
    if not (s[i] and s[i].seg) or (s[i].played or 0) >= M.MAX_PLAYS then return true end
  end
  return false
end

-- TVInterview_IsEligible
function M.interviewEligible(ctx, seg)
  if not M.slotOpen(ctx.save, seg) then return false end
  local iv = M.INTERVIEWS[seg]
  if not iv then return false end
  if iv.eligibleFn then return iv.eligibleFn(ctx) and true or false end
  if iv.eligible == false then return false end
  return true
end

function Commands.pt_tv_interview_eligible(ctx, seg, destVar)
  setVar(ctx, destVar, M.interviewEligible(ctx, valueOf(ctx, seg)) and 1 or 0)
end

function M.loadInterviewMessage(ctx, seg)
  local iv = M.INTERVIEWS[seg]
  if iv and iv.fill then iv.fill(ctx) end
  return iv and iv.line or 0
end

function M.saveInterviewResponse(ctx, seg, w)
  local iv = M.INTERVIEWS[seg]
  if iv and iv.save then iv.save(ctx, w) end
end


-- ---------------------------------------------------------------------------
-- ROUND 5: records (type 3), more sightings, and the TV-side pending state
-- some interviews wait on (tv_segment.c, READ unless marked)
-- ---------------------------------------------------------------------------
local function platinum() return require("src.import.Gen4ScriptBands").family == "platinum" end
local function itemId(def)
  if type(def) == "table" then return tonumber(def.id) or tonumber(def.index) end
  return tonumber(def) or tonumber(tostring(def or ""):match("(%d+)%s*$"))
end
local function arrivedSave(save, zone)
  local flags = (save and save.flags) or {}
  return flags[require("src.world.Gen4Fly").flagKey(zone)] == true
end
M.FIRST_ARRIVAL_RESORT_AREA, M.FIRST_ARRIVAL_FIGHT_AREA = 6, 17
M.BANK_FURNITURE, M.BANK_NATURES, M.BANK_ACCESSORIES = 371, 202, 386

-- records 1: sub_0206DBB0 from BattleTower_UpdateGameRecords (Gen4BattleTower.endStreak)
function M.towerRecord(save, streak, mon, single)
  if not platinum() then return end
  M.save(save, M.TYPE_RECORDS, 1, { streak = streak, species = speciesOf(mon), single = single and true or false })
end
M.SEGMENTS[3][1] = {
  eligible = function(ctx, d) return seen(ctx, d.species) and arrivedSave(ctx.save, M.FIRST_ARRIVAL_FIGHT_AREA) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 2, d.streak)
    return d.single and 0 or 1
  end }
-- records 3: sub_0206DC6C, a new Route 222 size record (g4_size_contest_result);
-- kept in tenths of an inch, which is what sub_0206DC9C prints
function M.sizeRecord(ctx, mon, tenths)
  if not platinum() then return end
  M.save(ctx.save, M.TYPE_RECORDS, 3, { species = speciesOf(mon), tenths = tenths })
end
M.SEGMENTS[3][3] = {
  eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 2, math.floor((d.tenths or 0) / 10))
    buffer(ctx, 3, (d.tenths or 0) % 10)
    return 2
  end }

-- records 4: sub_0206DD38, the slot machine session (sub_0203E35C, after the
-- slot app closes): kept only when the player left with at least 1000 coins
-- more than they sat down with; the start count, the end count and the
-- minutes played.  Called by the session wrapper (PtSlotMachine).
function M.slotsRecord(save, startCoins, endCoins, minutes)
  if not platinum() then return false end
  startCoins, endCoins = tonumber(startCoins) or 0, tonumber(endCoins) or 0
  if endCoins < 1000 + startCoins then return false end
  M.save(save, M.TYPE_RECORDS, 4, { start = startCoins, finish = endCoins, minutes = math.floor(tonumber(minutes) or 0) })
  return true
end
M.SEGMENTS[3][4] = {
  -- sRecordsSegments[3] = { sub_0206DD5C, NULL }: no eligibility test
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, d.minutes or 0)
    buffer(ctx, 2, d.start or 0)
    buffer(ctx, 3, d.finish or 0)
    return 3
  end }

-- sightings 3: What's Fishing (fishing.c) -- a hooked fish or one that got away
M.ROD_ITEM = { old = 445, good = 446, super = 447 }
function M.fishing(save, rod, enc)
  if not platinum() then return end
  local rodItem = M.ROD_ITEM[tostring(rod):lower():match("(%a+)") or ""] or tonumber(rod) or 445
  local d = { rod = rodItem, caught = enc ~= nil }
  if enc then d.species = speciesOf(enc) end
  M.save(save, M.TYPE_SIGHTINGS, 3, d)
end
M.SEGMENTS[2][3] = {
  eligible = function(ctx, d) return not d.caught or seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    if d.caught then
      buffer(ctx, 1, text(ctx, M.BANK_ITEMS, d.rod))
      buffer(ctx, 2, text(ctx, M.BANK_SPECIES, d.species))
      return 4
    end
    return 5
  end }
-- sightings 7: Sinnoh Shopping Champ Corner (shop_menu.c, normal marts, 10+)
function M.shopping(save, def, amount)
  if not platinum() then return end
  amount = tonumber(amount) or 0
  if amount < 10 then return end
  M.save(save, M.TYPE_SIGHTINGS, 7, { item = itemId(def) or 0, amount = math.min(999, amount) })
end
M.SEGMENTS[2][7] = {
  load = function(ctx, d)
    buffer(ctx, 0, text(ctx, M.BANK_ITEMS, d.item))
    buffer(ctx, 1, d.amount)
    trainer(ctx, 2)
    buffer(ctx, 3, text(ctx, 394, d.item))            -- the plural (StringTemplate_SetItemNamePlural)
    return 11
  end }
-- sightings 8: Happy Happy Egg Club (the hatch, unk_0203D1B8.c)
function M.hatched(save, mon, def)
  if not platinum() then return end
  M.save(save, M.TYPE_SIGHTINGS, 8, { species = speciesOf(mon), header = def and tonumber(def.header) or 0 })
end
M.SEGMENTS[2][8] = {
  eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, require("src.script.PtTvBroadcast").headerLabel(ctx, d.header))
    buffer(ctx, 2, text(ctx, M.BANK_SPECIES, d.species))
    return 12
  end }
-- sightings 10: Rate That Name Change (ScrCmd_2B8 <slot>, the Name Rater)
function Commands.pt_tv_name_change(ctx, slot)
  local mon = ctx.save and ctx.save.party and ctx.save.party[valueOf(ctx, slot) + 1]
  if not mon then return end
  M.save(ctx.save, M.TYPE_SIGHTINGS, 10, { species = speciesOf(mon), nickname = mon.nickname })
end
M.SEGMENTS[2][10] = {
  eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 2, d.nickname or "")
    local r = (love and love.math and love.math.random) and love.math.random(0, 4) or math.random(0, 4)
    return 17 + r
  end }
-- sightings 16: Pokemon Storage Special News Bulletin (ScrCmd_SaveTVSegmentPokemonStorageBulletin):
-- a party all one gender (no genderless), the first hatched mon
function Commands.pt_tv_storage_bulletin(ctx)
  local party = (ctx.save and ctx.save.party) or {}
  local male, female, none = false, false, false
  for _, mon in ipairs(party) do
    if not mon.isEgg then
      local g = require("src.pokemon.Pokemon").genderOf(ctx.game and ctx.game.data, mon)
      if g == "male" then male = true
      elseif g == "female" then female = true
      else none = true end
    end
  end
  if none or male == female then return end
  local lead = firstHatched(ctx.save)
  M.save(ctx.save, M.TYPE_SIGHTINGS, 16, { species = speciesOf(lead), male = male })
end
M.SEGMENTS[2][16] = {
  eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species))
    return d.male and 27 or 28
  end }
-- sightings 18 / 19: Planting and Watering Show (BerryPatches_HarvestBerry): a
-- yield rating of 4 is the show, 0 the no-berries show, 5 nothing
function M.harvested(save, item, rating, amount)
  if not platinum() then return end
  rating = tonumber(rating) or 5
  local d = { item = itemId(item) or 0, amount = tonumber(amount) or 0 }
  if rating == 4 then M.save(save, M.TYPE_SIGHTINGS, 18, d)
  elseif rating == 0 then M.save(save, M.TYPE_SIGHTINGS, 19, d) end
end
M.SEGMENTS[2][18] = { load = function(ctx, d)
  trainer(ctx, 0); buffer(ctx, 1, text(ctx, M.BANK_ITEMS, d.item)); buffer(ctx, 2, d.amount); return 30 end }
M.SEGMENTS[2][19] = { load = function(ctx, d)
  trainer(ctx, 0); buffer(ctx, 1, text(ctx, M.BANK_ITEMS, d.item)); return 31 end }
-- sightings 21: Seal Club Show (FieldSystem_SaveTVSegment_SealClubShow),
-- recorded by the capsule app when a decorated capsule is attached to a
-- party Pokemon (capsule_menu/main.c CAPSULE_MENU_ATTACH_CAPSULE_STATE_ID):
-- the first seal's name index (CapsuleMenu_GetSealNameIndex) and the mon.
-- The capsule app is not ported; this is where it records.
function M.sealClub(save, mon, sealNameIndex)
  if not platinum() then return end
  M.save(save, M.TYPE_SIGHTINGS, 21, { species = speciesOf(mon), seal = tonumber(sealNameIndex) or 0 })
end
M.BANK_BALL_SEAL_NAMES = 12
M.SEGMENTS[2][21] = { eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_BALL_SEAL_NAMES, d.seal or 0))
    buffer(ctx, 2, text(ctx, M.BANK_SPECIES, d.species))
    -- TVProgramTrainerSightings_Text_SealClubShow_CleverlyCalculated + LCRNG_RandMod(3)
    local r = (love and love.math and love.math.random) and love.math.random(0, 2) or math.random(0, 2)
    return 33 + r
  end }

-- sightings 25 / 26: Home and Manor (ScrCmd_30C / ScrCmd_30D <furniture>)
function Commands.pt_tv_villa(ctx, furniture)
  if furniture == nil then M.save(ctx.save, M.TYPE_SIGHTINGS, 25, { dummy = 1 })
  else M.save(ctx.save, M.TYPE_SIGHTINGS, 26, { furniture = valueOf(ctx, furniture) }) end
end
local function resort(ctx) return arrivedSave(ctx.save, M.FIRST_ARRIVAL_RESORT_AREA) end
M.SEGMENTS[2][25] = { eligible = resort, load = function(ctx) trainer(ctx, 0) return 38 end }
M.SEGMENTS[2][26] = { eligible = resort, load = function(ctx, d)
  trainer(ctx, 0); buffer(ctx, 1, text(ctx, M.BANK_FURNITURE, d.furniture or 0)); return 39 end }

-- THE TV-SIDE PENDING STATE (TVBroadcast's small structs), kept in
-- save.gen4PtTvPending:
--   amity  sub_0206CF48 / _CF9C / _CFB4 from ScrCmd_27C: the walked mon (case
--          0), then the accessory (2) or item (1) it picked up
--   tower  sub_0206CFE4 from BattleTower_UpdateGameRecords(AndJournal):
--          singles / doubles, a streak of 7 or more, won or lost
function M.pending(save)
  if not save then return {} end
  save.gen4PtTvPending = save.gen4PtTvPending or {}
  return save.gen4PtTvPending
end
function Commands.pt_tv_amity(ctx, which, value)
  local p = M.pending(ctx.save)
  local w = math.floor(tonumber(which) or -1)
  if w == 0 then
    local mon = ctx.save and ctx.save.party and ctx.save.party[valueOf(ctx, value) + 1]
    if not mon then return end
    p.amity = { species = speciesOf(mon), nature = (tonumber(mon.personality) or 0) % 25, found = 0 }
  elseif p.amity then
    if w == 2 then p.amity.found, p.amity.accessory = 2, valueOf(ctx, value)
    elseif w == 1 then p.amity.found, p.amity.item = 1, valueOf(ctx, value) end
  end
end
function M.towerOutcome(save, win, streak, mode)
  if not platinum() or (mode ~= 0 and mode ~= 1) or (tonumber(streak) or 0) < 7 then return end
  M.pending(save).tower = { win = win and true or false, streak = math.min(9999, tonumber(streak) or 0) }
end

-- Battle Tower Corner (interview 2) and Amity Square Watch (interview 13):
-- eligible while their pending state is set; the answer takes it
M.INTERVIEWS[2] = { line = 4, eligibleFn = function(ctx) return M.pending(ctx.save).tower ~= nil end,
  save = function(ctx, w)
    local p = M.pending(ctx.save)
    if not p.tower then return end
    M.save(ctx.save, M.TYPE_INTERVIEWS, 2, { win = p.tower.win, streak = p.tower.streak, word = w })
    p.tower = nil
  end }
M.INTERVIEWS[13] = { line = 15, eligibleFn = function(ctx) return M.pending(ctx.save).amity ~= nil end,
  save = function(ctx, w)
    local p = M.pending(ctx.save)
    if not p.amity then return end
    local d = {}
    for k, v in pairs(p.amity) do d[k] = v end
    d.word = w
    M.save(ctx.save, M.TYPE_INTERVIEWS, 13, d)
    p.amity = nil
  end }
M.SEGMENTS[1][2] = {
  eligible = function(ctx) return arrivedSave(ctx.save, M.FIRST_ARRIVAL_FIGHT_AREA) end,
  load = function(ctx, d)
    buffer(ctx, 0, d.streak); trainer(ctx, 1); buffer(ctx, 2, word(ctx, d.word))
    return d.win and 8 or 9
  end }
M.SEGMENTS[1][13] = {
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 2, text(ctx, M.BANK_NATURES, d.nature or 0))
    buffer(ctx, 5, word(ctx, d.word))
    if d.found == 2 then buffer(ctx, 3, text(ctx, M.BANK_ACCESSORIES, d.accessory or 0)) return 44 end
    if d.found == 1 then buffer(ctx, 3, text(ctx, M.BANK_ITEMS, d.item or 0)) return 46 end
    return 45
  end }


-- sightings 17: Safari Game Special News Bulletin. ScrCmd_StartEndSafariGame
-- resets the TV's safari tally on start (TVBroadcast_ResetSafariGameData) and
-- records it on end if anything was caught; each capture in the marsh counts,
-- the first one naming the species (encounter.c TVBroadcast_UpdateSafariGameData)
function Commands.pt_tv_safari(ctx, state)
  if not platinum() then return end
  local p = M.pending(ctx.save)
  local st = valueOf(ctx, state)
  if st == 0 then p.safari = { caught = 0 }
  elseif st == 1 and p.safari and (p.safari.caught or 0) > 0 then
    M.save(ctx.save, M.TYPE_SIGHTINGS, 17, { species = p.safari.species, caught = p.safari.caught })
  end
end
function M.safariCaught(save, mon)
  local p = M.pending(save)
  p.safari = p.safari or { caught = 0 }
  if (p.safari.caught or 0) == 0 then p.safari.species = speciesOf(mon) end
  p.safari.caught = (p.safari.caught or 0) + 1
end
M.SEGMENTS[2][17] = {
  eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0); buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species)); buffer(ctx, 2, d.caught)
    return 26
  end }


-- CONTEST HALL (interview 7) and THREE CHEERS FOR POFFIN CORNER (interview
-- 11), round 6: their pending state, from the contest's end
-- (TVBroadcast_SetContestHallShowInfo in contest.c, every non-practice
-- contest: the player's mon, type, rank, placement + 1) and from a Poffin
-- cooked alone (ov83 sub_0206CFCC: the Poffin's type)
function M.contestShown(save, mon, contestType, rank, placement)
  if not platinum() then return end
  M.pending(save).contest = { species = speciesOf(mon), contestType = tonumber(contestType) or 0,
    rank = tonumber(rank) or 0, placement = tonumber(placement) or 1 }
end
function M.poffinCooked(save, poffinType)
  if not platinum() then return end
  M.pending(save).poffin = { poffinType = tonumber(poffinType) or 0 }
end
local function takePending(key, seg)
  return function(ctx, w)
    local p = M.pending(ctx.save)
    if not p[key] then return end
    local d = {}
    for k, v in pairs(p[key]) do d[k] = v end
    d.word = w
    M.save(ctx.save, M.TYPE_INTERVIEWS, seg, d)
    p[key] = nil
  end
end
M.INTERVIEWS[7] = { line = 9, eligibleFn = function(ctx) return M.pending(ctx.save).contest ~= nil end,
  save = takePending("contest", 7) }
M.INTERVIEWS[11] = { line = 13, eligibleFn = function(ctx) return M.pending(ctx.save).poffin ~= nil end,
  save = takePending("poffin", 11) }
M.BANK_CONTEST, M.BANK_POFFIN_TYPES = 204, 465
M.SEGMENTS[1][7] = {
  eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    buffer(ctx, 0, text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 1, text(ctx, M.BANK_CONTEST, 41 + (d.contestType or 0)))   -- Contest_GetContestTypeMessageID
    local rank = d.rank or 0
    buffer(ctx, 2, text(ctx, M.BANK_CONTEST, rank <= 3 and 46 + rank or 51))  -- Contest_GetRankMessageID
    buffer(ctx, 3, d.placement)
    trainer(ctx, 4)
    buffer(ctx, 5, word(ctx, d.word))
    return d.placement == 1 and 18 or 17
  end }
-- POFFIN_TYPE_RICH 25, OVERRIPE 26, FOUL 27, MILD 28
M.POFFIN_LINE = { [25] = 39, [26] = 40, [27] = 41, [28] = 42 }
M.SEGMENTS[1][11] = {
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_POFFIN_TYPES, d.poffinType or 0))
    buffer(ctx, 2, word(ctx, d.word))
    return M.POFFIN_LINE[d.poffinType] or 38
  end }


-- ---------------------------------------------------------------------------
-- ROUND 7
-- ---------------------------------------------------------------------------
-- RECORDS 5: the ribbon count (sub_0206DDB8). Whenever a ribbon is set
-- (ScrCmd_SetPartyMonRibbon, a contest win, the Battle Tower's), the mon's
-- count of the 39 Sinnoh-era ribbons (Unk_020EFDDC, by MON_DATA param) is
-- taken; 15, 20, 25, 30, 35 or 40 is a TV record with the ribbon's name.
-- The port keys mon.ribbons by the cartridge's own ribbon ids
-- (sRibbonDataTable index: 32 Sinnoh Champ, 33 + type * 4 + rank the contest
-- ribbons), so these tables (generated by pt_cmds/gen_ribbons.py from
-- ribbon.c / pokemon_data_params / ribbon_names) apply to it directly.
M.RIBBON_PARAM = {  -- ribbon id (sRibbonDataTable index) -> MON_DATA_* value
  [0] = 98,  -- RIBBON_HOENN_CHAMPION MON_DATA_CHAMPION_RIBBON
  [1] = 78,  -- RIBBON_HOENN_COOL MON_DATA_COOL_RIBBON
  [2] = 79,  -- RIBBON_HOENN_COOL_SUPER MON_DATA_COOL_RIBBON_SUPER
  [3] = 80,  -- RIBBON_HOENN_COOL_HYPER MON_DATA_COOL_RIBBON_HYPER
  [4] = 81,  -- RIBBON_HOENN_COOL_MASTER MON_DATA_COOL_RIBBON_MASTER
  [5] = 82,  -- RIBBON_HOENN_BEAUTY MON_DATA_BEAUTY_RIBBON
  [6] = 83,  -- RIBBON_HOENN_BEAUTY_SUPER MON_DATA_BEAUTY_RIBBON_SUPER
  [7] = 84,  -- RIBBON_HOENN_BEAUTY_HYPER MON_DATA_BEAUTY_RIBBON_HYPER
  [8] = 85,  -- RIBBON_HOENN_BEAUTY_MASTER MON_DATA_BEAUTY_RIBBON_MASTER
  [9] = 86,  -- RIBBON_HOENN_CUTE MON_DATA_CUTE_RIBBON
  [10] = 87,  -- RIBBON_HOENN_CUTE_SUPER MON_DATA_CUTE_RIBBON_SUPER
  [11] = 88,  -- RIBBON_HOENN_CUTE_HYPER MON_DATA_CUTE_RIBBON_HYPER
  [12] = 89,  -- RIBBON_HOENN_CUTE_MASTER MON_DATA_CUTE_RIBBON_MASTER
  [13] = 90,  -- RIBBON_HOENN_SMART MON_DATA_SMART_RIBBON
  [14] = 91,  -- RIBBON_HOENN_SMART_SUPER MON_DATA_SMART_RIBBON_SUPER
  [15] = 92,  -- RIBBON_HOENN_SMART_HYPER MON_DATA_SMART_RIBBON_HYPER
  [16] = 93,  -- RIBBON_HOENN_SMART_MASTER MON_DATA_SMART_RIBBON_MASTER
  [17] = 94,  -- RIBBON_HOENN_TOUGH MON_DATA_TOUGH_RIBBON
  [18] = 95,  -- RIBBON_HOENN_TOUGH_SUPER MON_DATA_TOUGH_RIBBON_SUPER
  [19] = 96,  -- RIBBON_HOENN_TOUGH_HYPER MON_DATA_TOUGH_RIBBON_HYPER
  [20] = 97,  -- RIBBON_HOENN_TOUGH_MASTER MON_DATA_TOUGH_RIBBON_MASTER
  [21] = 99,  -- RIBBON_HOENN_WINNING MON_DATA_WINNING_RIBBON
  [22] = 100,  -- RIBBON_HOENN_VICTORY MON_DATA_VICTORY_RIBBON
  [23] = 101,  -- RIBBON_HOENN_ARTIST MON_DATA_ARTIST_RIBBON
  [24] = 102,  -- RIBBON_HOENN_EFFORT MON_DATA_EFFORT_RIBBON
  [25] = 103,  -- RIBBON_HOENN_MARINE MON_DATA_MARINE_RIBBON
  [26] = 104,  -- RIBBON_HOENN_LAND MON_DATA_LAND_RIBBON
  [27] = 105,  -- RIBBON_HOENN_SKY MON_DATA_SKY_RIBBON
  [28] = 106,  -- RIBBON_HOENN_COUNTRY MON_DATA_COUNTRY_RIBBON
  [29] = 107,  -- RIBBON_HOENN_NATIONAL MON_DATA_NATIONAL_RIBBON
  [30] = 108,  -- RIBBON_HOENN_EARTH MON_DATA_EARTH_RIBBON
  [31] = 109,  -- RIBBON_HOENN_WORLD MON_DATA_WORLD_RIBBON
  [32] = 25,  -- RIBBON_SINNOH_CHAMP MON_DATA_SINNOH_CHAMP_RIBBON
  [33] = 123,  -- RIBBON_COOL MON_DATA_SUPER_COOL_RIBBON
  [34] = 124,  -- RIBBON_COOL_GREAT MON_DATA_SUPER_COOL_RIBBON_GREAT
  [35] = 125,  -- RIBBON_COOL_ULTRA MON_DATA_SUPER_COOL_RIBBON_ULTRA
  [36] = 126,  -- RIBBON_COOL_MASTER MON_DATA_SUPER_COOL_RIBBON_MASTER
  [37] = 127,  -- RIBBON_BEAUTY MON_DATA_SUPER_BEAUTY_RIBBON
  [38] = 128,  -- RIBBON_BEAUTY_GREAT MON_DATA_SUPER_BEAUTY_RIBBON_GREAT
  [39] = 129,  -- RIBBON_BEAUTY_ULTRA MON_DATA_SUPER_BEAUTY_RIBBON_ULTRA
  [40] = 130,  -- RIBBON_BEAUTY_MASTER MON_DATA_SUPER_BEAUTY_RIBBON_MASTER
  [41] = 131,  -- RIBBON_CUTE MON_DATA_SUPER_CUTE_RIBBON
  [42] = 132,  -- RIBBON_CUTE_GREAT MON_DATA_SUPER_CUTE_RIBBON_GREAT
  [43] = 133,  -- RIBBON_CUTE_ULTRA MON_DATA_SUPER_CUTE_RIBBON_ULTRA
  [44] = 134,  -- RIBBON_CUTE_MASTER MON_DATA_SUPER_CUTE_RIBBON_MASTER
  [45] = 135,  -- RIBBON_SMART MON_DATA_SUPER_SMART_RIBBON
  [46] = 136,  -- RIBBON_SMART_GREAT MON_DATA_SUPER_SMART_RIBBON_GREAT
  [47] = 137,  -- RIBBON_SMART_ULTRA MON_DATA_SUPER_SMART_RIBBON_ULTRA
  [48] = 138,  -- RIBBON_SMART_MASTER MON_DATA_SUPER_SMART_RIBBON_MASTER
  [49] = 139,  -- RIBBON_TOUGH MON_DATA_SUPER_TOUGH_RIBBON
  [50] = 140,  -- RIBBON_TOUGH_GREAT MON_DATA_SUPER_TOUGH_RIBBON_GREAT
  [51] = 141,  -- RIBBON_TOUGH_ULTRA MON_DATA_SUPER_TOUGH_RIBBON_ULTRA
  [52] = 142,  -- RIBBON_TOUGH_MASTER MON_DATA_SUPER_TOUGH_RIBBON_MASTER
  [53] = 26,  -- RIBBON_ABILITY MON_DATA_ABILITY_RIBBON
  [54] = 27,  -- RIBBON_GREAT_ABILITY MON_DATA_GREAT_ABILITY_RIBBON
  [55] = 28,  -- RIBBON_DOUBLE_ABILITY MON_DATA_DOUBLE_ABILITY_RIBBON
  [56] = 29,  -- RIBBON_MULTI_ABILITY MON_DATA_MULTI_ABILITY_RIBBON
  [57] = 30,  -- RIBBON_PAIR_ABILITY MON_DATA_PAIR_ABILITY_RIBBON
  [58] = 31,  -- RIBBON_WORLD_ABILITY MON_DATA_WORLD_ABILITY_RIBBON
  [59] = 32,  -- RIBBON_ALERT MON_DATA_ALERT_RIBBON
  [60] = 33,  -- RIBBON_SHOCK MON_DATA_SHOCK_RIBBON
  [61] = 34,  -- RIBBON_DOWNCAST MON_DATA_DOWNCAST_RIBBON
  [62] = 35,  -- RIBBON_CARELESS MON_DATA_CARELESS_RIBBON
  [63] = 36,  -- RIBBON_RELAX MON_DATA_RELAX_RIBBON
  [64] = 37,  -- RIBBON_SNOOZE MON_DATA_SNOOZE_RIBBON
  [65] = 38,  -- RIBBON_SMILE MON_DATA_SMILE_RIBBON
  [66] = 39,  -- RIBBON_GORGEOUS MON_DATA_GORGEOUS_RIBBON
  [67] = 40,  -- RIBBON_ROYAL MON_DATA_ROYAL_RIBBON
  [68] = 41,  -- RIBBON_GORGEOUS_ROYAL MON_DATA_GORGEOUS_ROYAL_RIBBON
  [69] = 42,  -- RIBBON_FOOTPRINT MON_DATA_FOOTPRINT_RIBBON
  [70] = 43,  -- RIBBON_RECORD MON_DATA_RECORD_RIBBON
  [71] = 44,  -- RIBBON_HISTORY MON_DATA_HISTORY_RIBBON
  [72] = 45,  -- RIBBON_LEGEND MON_DATA_LEGEND_RIBBON
  [73] = 46,  -- RIBBON_RED MON_DATA_RED_RIBBON
  [74] = 47,  -- RIBBON_GREEN MON_DATA_GREEN_RIBBON
  [75] = 48,  -- RIBBON_BLUE MON_DATA_BLUE_RIBBON
  [76] = 49,  -- RIBBON_FESTIVAL MON_DATA_FESTIVAL_RIBBON
  [77] = 50,  -- RIBBON_CARNIVAL MON_DATA_CARNIVAL_RIBBON
  [78] = 51,  -- RIBBON_CLASSIC MON_DATA_CLASSIC_RIBBON
  [79] = 52,  -- RIBBON_PREMIER MON_DATA_PREMIER_RIBBON
}
M.RIBBON_NAME = {  -- ribbon id -> RibbonName line (TEXT_BANK_RIBBON_NAMES 535)
  [0] = 0,
  [1] = 1,
  [2] = 2,
  [3] = 3,
  [4] = 4,
  [5] = 5,
  [6] = 6,
  [7] = 7,
  [8] = 8,
  [9] = 9,
  [10] = 10,
  [11] = 11,
  [12] = 12,
  [13] = 13,
  [14] = 14,
  [15] = 15,
  [16] = 16,
  [17] = 17,
  [18] = 18,
  [19] = 19,
  [20] = 20,
  [21] = 21,
  [22] = 22,
  [23] = 23,
  [24] = 24,
  [25] = 25,
  [26] = 26,
  [27] = 27,
  [28] = 28,
  [29] = 29,
  [30] = 30,
  [31] = 31,
  [32] = 32,
  [33] = 33,
  [34] = 34,
  [35] = 35,
  [36] = 36,
  [37] = 37,
  [38] = 38,
  [39] = 39,
  [40] = 40,
  [41] = 41,
  [42] = 42,
  [43] = 43,
  [44] = 44,
  [45] = 45,
  [46] = 46,
  [47] = 47,
  [48] = 48,
  [49] = 49,
  [50] = 50,
  [51] = 51,
  [52] = 52,
  [53] = 53,
  [54] = 54,
  [55] = 55,
  [56] = 56,
  [57] = 57,
  [58] = 58,
  [59] = 59,
  [60] = 60,
  [61] = 61,
  [62] = 62,
  [63] = 63,
  [64] = 64,
  [65] = 65,
  [66] = 66,
  [67] = 67,
  [68] = 68,
  [69] = 69,
  [70] = 70,
  [71] = 71,
  [72] = 72,
  [73] = 73,
  [74] = 74,
  [75] = 75,
  [76] = 76,
  [77] = 77,
  [78] = 78,
  [79] = 79,
}
M.RIBBON_COUNTED = { -- the MON_DATA params sub_0206DE4C counts (Unk_020EFDDC)
  [102] = true, [25] = true, [123] = true, [124] = true, [125] = true, [126] = true, [127] = true, [128] = true, [129] = true, [130] = true, [131] = true, [132] = true, [133] = true, [134] = true, [135] = true, [136] = true, [137] = true, [138] = true, [139] = true, [140] = true, [141] = true, [142] = true, [26] = true, [27] = true, [28] = true, [29] = true, [30] = true, [31] = true, [32] = true, [33] = true, [34] = true, [35] = true, [36] = true, [37] = true, [38] = true, [39] = true, [40] = true, [41] = true, [42] = true
}

M.BANK_RIBBON_NAMES = 535
M.RIBBON_MILESTONES = { [15] = true, [20] = true, [25] = true, [30] = true, [35] = true, [40] = true }
function M.ribbonCount(mon)
  local n = 0
  for id, has in pairs((mon and mon.ribbons) or {}) do
    local param = M.RIBBON_PARAM[tonumber(id) or -1]
    if has and param and M.RIBBON_COUNTED[param] then n = n + 1 end
  end
  return n
end
function M.ribbonGiven(save, mon, ribbonId, data)
  if not platinum() or not mon then return end
  local n = M.ribbonCount(mon)
  if not M.RIBBON_MILESTONES[n] then return end
  local nameLine = M.RIBBON_NAME[tonumber(ribbonId) or -1]
  if not nameLine then return end
  M.save(save, M.TYPE_RECORDS, 5, { species = speciesOf(mon), nickname = nicknamed(mon, data),
    ribbonName = nameLine, count = n })
end
M.SEGMENTS[3][5] = {
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, d.nickname or text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 2, text(ctx, M.BANK_RIBBON_NAMES, d.ribbonName))
    buffer(ctx, 3, d.count)
    return 4
  end }

-- THE POKETCH WATCH (interview 6): eligible once the Poketch is the player's
-- (sub_02049358 Poketch_IsEnabled); the question names the app on the watch
-- (sub_02049288, TEXT_BANK_POKETCH_APP_NAMES 457), the answer keeps it. The
-- port's watch keeps its app as a 1-based index into its app list
-- (save.poketch.app), the cartridge's app id being that index - 1 (INFERRED
-- from the list's order).
M.BANK_POKETCH_APPS = 457
local function poketchApp(save)
  local p = save and save.poketch
  return math.max(0, (tonumber(p and p.app) or 1) - 1)
end
M.INTERVIEWS[6] = { line = 8,
  eligibleFn = function(ctx) return require("src.pokemon.Gen4PoketchState").owned(ctx.save) end,
  fill = function(ctx) buffer(ctx, 0, text(ctx, M.BANK_POKETCH_APPS, poketchApp(ctx.save))) end,
  save = function(ctx, w) M.save(ctx.save, M.TYPE_INTERVIEWS, 6, { app = poketchApp(ctx.save), word = w }) end }
M.SEGMENTS[1][6] = {
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_POKETCH_APPS, d.app or 0))
    buffer(ctx, 2, word(ctx, d.word))
    return 16
  end }

-- BATTLE FRONTIER FRONTLINE NEWS, SINGLE (interview 14): FrontierScrCmd_C7
-- in the Battle Hall's script, single challenge only, records the lead mon
-- (sub_0206D048) -- the pending state; eligible while it is set
function Commands.fr_hall_tv(ctx)
  if not platinum() then return end
  local hall = ctx.game and ctx.game.gen4BattleHall
  if not hall or (tonumber(hall.challenge) or 0) ~= 0 then return end
  local mon = ctx.save and ctx.save.party and ctx.save.party[((hall.slots and hall.slots[0]) or 0) + 1]
  if not mon then return end
  M.pending(ctx.save).frontier = { species = speciesOf(mon), nickname = nicknamed(mon, ctx.game.data) }
end
M.INTERVIEWS[14] = { line = 16, eligibleFn = function(ctx) return M.pending(ctx.save).frontier ~= nil end,
  save = takePending("frontier", 14) }
M.SEGMENTS[1][14] = {
  eligible = function(ctx) return arrivedSave(ctx.save, M.FIRST_ARRIVAL_FIGHT_AREA) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 2, d.nickname or text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 3, word(ctx, d.word))
    return 47
  end }

-- RIGHT-ON PHOTO CORNER (interview 9, pt_photo round; READ, tv_segment.c
-- 1754-1784 and scrcmd_tv_broadcast.c sub_02049378): the Jubilife TV 2F
-- reporter is there while dress-up photo 0 holds a photo; the answer keeps
-- a word and photo 0's species (FieldSystem_SaveTVSegment_RightOnPhotoCorner);
-- the episode needs that species seen and prints the trainer, the species
-- and the word (TVSegment_LoadMessage_RightOnPhotoCorner, bank 415 line 20)
M.INTERVIEWS[9] = { line = 11,
  eligibleFn = function(ctx) return require("src.pokemon.Gen4Photos").hasData(ctx.save, "dressUp", 0) end,
  save = function(ctx, w)
    local p = require("src.pokemon.Gen4Photos").get(ctx.save, "dressUp", 0)
    M.save(ctx.save, M.TYPE_INTERVIEWS, 9, { species = speciesOf(p and p.mon), word = w })
  end }
M.SEGMENTS[1][9] = {
  eligible = function(ctx, d) return seen(ctx, d.species) end,
  load = function(ctx, d)
    trainer(ctx, 0)
    buffer(ctx, 1, text(ctx, M.BANK_SPECIES, d.species))
    buffer(ctx, 2, word(ctx, d.word))
    return 20
  end }

return M
