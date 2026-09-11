-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MATCH CALL: who is in your POKéNAV, and who wants a rematch.
--
-- Two tables meet here and they are not the same table.
--
--   gRematchTable is seventy-eight rows of FIVE TRAINER IDS and a map.  The
--   first id is the trainer you fought on the way through; the other four are
--   the same person at higher levels.  Which one you actually fight is not
--   stored anywhere -- GetRematchTrainerIdFromTable walks the five and takes
--   the first you have NOT beaten, so the rematch ladder is derived from the
--   defeat flags rather than from a counter.
--
--   sMatchCallHeaders is twenty-one HAND-WRITTEN entries -- Mom, Dad, Birch,
--   the rival, Steven, Scott, the eight leaders, the Elite Four, Wallace --
--   each with its own tagline, its own phone lines and its own appearance
--   flag.  Eleven of them also name a rematch row, which is how a Gym Leader
--   is both a phone contact and a rematch.
--
-- WHAT ARMS A REMATCH.  Not talking to anyone: a step counter that only runs
-- once you hold five badges, and a roll that happens ON MAP LOAD once it has
-- reached 255.  Every eligible rematch trainer standing on the map you just
-- walked into is rolled INDEPENDENTLY at thirty-one percent, and the counter
-- resets if any of them came out armed -- or was already armed.  The Elite
-- Four and the Champion are never rolled; WALLY is rolled only after his own
-- flag is set.
--
-- WHAT REGISTERS ONE.  Beating a trainer whose id is the FIRST of some
-- rematch row sets flag 348 + that row, and that flag is what the POKéNAV
-- lists.  It is set on the defeat, not on a phone call.
local MatchCall = {}

local Gen3Commands  -- required lazily: it requires this file back

local function commands()
  Gen3Commands = Gen3Commands or require("src.script.Gen3Commands")
  return Gen3Commands
end

function MatchCall.record(data)
  local c = (data and data.constants) or {}
  local nav = c.gen3Pokenav
  return nav and nav.matchCall or nil
end

function MatchCall.rematchRows(data)
  local r = MatchCall.record(data)
  return (r and r.rematch) or {}
end

-- The flag that says a rematch row is in your POKéNAV.
function MatchCall.registeredFlag(data, index)
  local r = MatchCall.record(data)
  local base = (r and r.registeredFlagBase) or 348
  return commands().flagKey(base + index)
end

function MatchCall.isRegistered(data, save, index)
  local rows = MatchCall.rematchRows(data)
  if not rows[index + 1] then return false end
  return (save.flags or {})[MatchCall.registeredFlag(data, index)] == true
end

-- GetRematchIdxByTrainerIdx: the row whose FIRST id is this trainer.
function MatchCall.rowForFirst(data, trainerId)
  for i, row in ipairs(MatchCall.rematchRows(data)) do
    if row.trainers[1] == trainerId then return i - 1 end
  end
  return nil
end

-- TrainerIdToRematchTableId: the row that names this trainer ANYWHERE.
function MatchCall.rowForAny(data, trainerId)
  for i, row in ipairs(MatchCall.rematchRows(data)) do
    for _, id in ipairs(row.trainers) do
      if id == trainerId then return i - 1 end
    end
  end
  return nil
end

-- The per-row counter the overworld arms.  Stored on the save under its own
-- name rather than inside the flag array, because it is a LEVEL (1..5) and
-- not a bit -- SetRematchIdForTrainer writes how far up the ladder you are.
function MatchCall.armed(save)
  save.rematches = save.rematches or {}
  return save.rematches
end

function MatchCall.isReady(data, save, index)
  return (MatchCall.armed(save)[index] or 0) ~= 0
end

function MatchCall.clearReady(save, index)
  MatchCall.armed(save)[index] = nil
end

-- HasTrainerBeenFought: FlagGet(id + 0x500).
function MatchCall.beaten(save, trainerId)
  return (save.flags or {})[commands().flagKey(0x500 + trainerId)] == true
end

-- SetRematchIdForTrainer: how far up this row's ladder the player has come.
-- One when nothing past the first has been beaten, five at the top.
function MatchCall.level(data, save, index)
  local row = MatchCall.rematchRows(data)[index + 1]
  if not row then return 0 end
  if not MatchCall.beaten(save, row.trainers[1]) then return 0 end
  local n = 1
  for i = 2, #row.trainers do
    if MatchCall.beaten(save, row.trainers[i]) then n = n + 1 else break end
  end
  return n
end

-- GetRematchTrainerIdFromTable: WHICH of the five you fight.  The first that
-- has not been beaten; if they all have, the last one again.
function MatchCall.rematchTrainer(data, save, trainerId)
  local index = MatchCall.rowForFirst(data, trainerId)
  if not index then return trainerId end
  local row = MatchCall.rematchRows(data)[index + 1]
  for i = 2, #row.trainers do
    if not MatchCall.beaten(save, row.trainers[i]) then return row.trainers[i] end
  end
  return row.trainers[#row.trainers] or trainerId
end

-- ---------------------------------------------------------------------------
-- ARMING
-- ---------------------------------------------------------------------------

-- IsRematchForbidden.
function MatchCall.forbidden(data, save, index)
  local r = MatchCall.record(data) or {}
  if index > ((r.forbiddenAbove) or 72) then return true end
  if index == (r.wally or 64) then
    local key = commands().flagKey(r.wallyFlag or 0x7E)
    return (save.flags or {})[key] ~= true
  end
  return false
end

-- HasAtLeastFiveBadges: the counter does not even run before this.
function MatchCall.counterRuns(data, save)
  local r = MatchCall.record(data) or {}
  local want = r.badges or 5
  -- ASKED THE WAY THE BADGE SCREEN ASKS IT.  A Hoenn badge is a FLAG whose
  -- name lives in the record's `item` field -- `flag` beside it is the raw
  -- number, and looking a number up in the flag table finds nothing, which
  -- would have left the step counter permanently switched off.
  local Badges = require("src.inventory.Badges")
  return Badges.count(data, save) >= want
end

-- IncrementRematchStepCounter, once per step.
function MatchCall.step(data, save)
  if not MatchCall.counterRuns(data, save) then return end
  local r = MatchCall.record(data) or {}
  local cap = r.steps or 255
  save.rematchSteps = math.min(cap, (save.rematchSteps or 0) + 1)
end

-- TryUpdateRandomTrainerRematches, on map load.  Returns how many armed.
function MatchCall.tryArm(data, save, mapId, rng)
  local r = MatchCall.record(data) or {}
  if not MatchCall.counterRuns(data, save) then return 0 end
  if (save.rematchSteps or 0) < (r.steps or 255) then return 0 end
  rng = rng or love.math.random
  local rows = MatchCall.rematchRows(data)
  local any, armed = false, 0
  for i = 0, math.min(#rows - 1, r.randomMax or 64) do
    local row = rows[i + 1]
    if row.map == mapId and not MatchCall.forbidden(data, save, i) then
      if MatchCall.isReady(data, save, i) then
        -- ALREADY ARMED STILL COUNTS.  The counter resets whether this visit
        -- armed anyone or merely found someone waiting, which is why walking
        -- back into a route with a ready trainer does not immediately roll
        -- the rest of it again.
        any = true
      elseif MatchCall.isRegistered(data, save, i)
             and rng(0, 99) <= ((r.chance or 31) - 1) then
        MatchCall.armed(save)[i] = math.max(1, MatchCall.level(data, save, i))
        any = true
        armed = armed + 1
      end
    end
  end
  if any then save.rematchSteps = 0 end
  return armed
end

-- ---------------------------------------------------------------------------
-- THE LIST THE POKeNAV SHOWS
-- ---------------------------------------------------------------------------

-- A REMATCH ROW NAMES A NUMBER, AND THE TRAINER TABLE IS KEYED BY NAME.
-- gRematchTable stores trainer INDICES -- Roxanne is 265 -- and this project's
-- trainers module is keyed by the slug ("ROXANNE"), with the index kept on the
-- record.  Indexing the table with the raw number therefore always missed, and
-- the miss is not visible as an error: it just returns nil.  `trainerOrder` is
-- the same bridge start_battle already uses for `trainerbattle 0, 418`.
function MatchCall.trainer(data, index)
  index = tonumber(index)
  if not index then return nil end
  local order = data and data.constants and data.constants.trainerOrder
  local key = order and order[index]
  if type(key) ~= "string" then return nil end
  return (data.trainers or {})[key]
end

-- MatchCallGetNameAndDesc, the type 1/2/5 half: a header with a NULL name
-- pointer is not nameless -- fourteen of the twenty-one are, every Gym Leader
-- and every member of the Elite Four among them -- it takes the name of the
-- FIRST trainer on the rematch row it owns.  Without this the POKeNAV listed
-- eight leaders as their taglines alone: "ROCKIN' WHIZ" with no ROXANNE.
function MatchCall.headerName(data, header)
  if not header then return nil end
  if header.name then return header.name end
  local row = header.rematch and MatchCall.rematchRows(data)[header.rematch + 1]
  local trainer = row and MatchCall.trainer(data, row.trainers[1])
  return trainer and trainer.name or nil
end


-- Every rematch row some header already owns, so a Gym Leader is listed once
-- rather than twice.
local function ownedRows(data)
  local r = MatchCall.record(data)
  local owned = {}
  for _, header in ipairs((r and r.headers) or {}) do
    if header.rematch then owned[header.rematch] = true end
  end
  return owned
end

-- The MATCH CALL list, in the cartridge's own two passes: the twenty-one
-- headers whose flag is set, then every registered rematch row no header
-- already owns.
function MatchCall.list(data, save)
  local r = MatchCall.record(data)
  local out = {}
  if not r then return out end
  for i, header in ipairs(r.headers or {}) do
    local shown = true
    if header.flag then
      shown = (save.flags or {})[commands().flagKey(header.flag)] == true
    end
    if shown then
      out[#out + 1] = {
        kind = "header", header = i - 1, row = header,
        rematch = header.rematch,
        mapSec = header.mapSec,
        name = MatchCall.headerName(data, header),
        description = header.description,
      }
    end
  end
  local owned = ownedRows(data)
  for i = 0, #MatchCall.rematchRows(data) - 1 do
    if not owned[i] and MatchCall.isRegistered(data, save, i) then
      local row = MatchCall.rematchRows(data)[i + 1]
      local trainer = MatchCall.trainer(data, row.trainers[1])
      out[#out + 1] = {
        kind = "rematch", rematch = i,
        name = trainer and trainer.name or nil,
        className = trainer and (trainer.class or trainer.trainerClass) or nil,
        map = row.map,
      }
    end
  end
  return out
end

-- Whether a row's marker shows "wants a rematch".
function MatchCall.entryReady(data, save, entry)
  if not (entry and entry.rematch) then return false end
  return MatchCall.isReady(data, save, entry.rematch)
end

-- ---------------------------------------------------------------------------
-- WHAT AN ORDINARY REGISTERED TRAINER SAYS
--
-- The twenty-one headers are only half the POKeNAV.  The other sixty-four
-- contacts -- every route trainer you register by beating them -- have no
-- line table at all, and this port had nothing to say for them: every one of
-- them answered the phone with "is not answering".
--
-- BuildMatchCallString (01967AC) assembles it instead, and the order it tries
-- things in is the whole behaviour:
--
--   1. If you are standing on the trainer's own route, the SAME-ROUTE battle
--      request -- "hey, are you near me?"
--   2. Otherwise, if their rematch is armed, the OTHER-ROUTE request.
--   3. Otherwise Random() % 3: two times in three one of their three battle
--      topics -- a wild Pokemon they saw, a battle they lost, a battle they
--      won -- and one time in three their own PERSONALISED line, the one
--      written for that trainer alone.
--
-- Each line carries three fill bytes saying what goes in {VAR1}, {VAR2} and
-- {VAR3}: the trainer's name, the name of where they are, a wild species off
-- their route, or one of their own party.
-- ---------------------------------------------------------------------------

function MatchCall.topics(data)
  local r = MatchCall.record(data)
  local t = r and r.topics
  if type(t) ~= "table" or type(t.trainers) ~= "table" then return nil end
  return t
end

-- MatchCallGetIndexByTrainerId: a linear walk of the sixty-four, the way the
-- cartridge does it, because the ids are not in order.
function MatchCall.topicRow(data, trainerId)
  local t = MatchCall.topics(data)
  if not t then return nil end
  trainerId = tonumber(trainerId)
  for _, row in ipairs(t.trainers) do
    if row.trainer == trainerId then return row end
  end
  return nil
end

local function speciesName(data, id)
  local def = id and (data.pokemon or {})[id]
  return (def and def.name) or (id and tostring(id)) or nil
end

-- sMatchCallFillFuncs (060EFAC), the four an ordinary call can reach.
local function fillValue(data, kind, ctx, rng)
  if kind == 0 then
    -- ...AND SIX OF THEM ARE NAMED WRONG BY gTrainers.  A pair trainer is one
    -- record called "KIRA & DAN"; the phone says "KIRA", and the cartridge
    -- keeps a six-row override table for exactly that.
    local t = MatchCall.topics(data)
    local override = t and t.names and t.names[ctx.trainerId]
    if override then return override end
    local trainer = MatchCall.trainer(data, ctx.trainerId)
    return trainer and trainer.name or nil
  elseif kind == 1 then
    local sections = (data.constants or {}).gen3MapSections
    local def = ctx.map and (data.maps or {})[ctx.map]
    local id = def and tonumber(def.regionMapSection)
    return (id and sections and sections[id]) or nil
  elseif kind == 2 then
    -- a wild species off the trainer's OWN route, which is what makes
    -- "I saw this {VAR2}" true where they are standing
    local enc = ctx.map and (data.encounters or {})[ctx.map]
    local slots = enc and enc.grass and enc.grass.slots
    if type(slots) ~= "table" or #slots == 0 then
      slots = enc and enc.water and enc.water.slots
    end
    if type(slots) ~= "table" or #slots == 0 then return nil end
    local slot = slots[rng(1, #slots)]
    return speciesName(data, slot and slot.species)
  elseif kind == 3 then
    local trainer = MatchCall.trainer(data, ctx.trainerId)
    local party = trainer and (trainer.party or (trainer.parties or {})[1])
    if type(party) ~= "table" or #party == 0 then return nil end
    local mon = party[rng(1, #party)]
    return speciesName(data, mon and mon.species)
  end
  return nil    -- 4 and 5 are Battle Frontier and nothing here picks them
end

-- One line, with its three slots filled.  Returns nil when a slot cannot be
-- filled, so the caller can try a different line rather than print a token.
function MatchCall.topicLine(data, line, ctx, rng)
  if not (line and line.text) then return nil end
  local text = line.text
  for slot = 1, 3 do
    local kind = line.fill and line.fill[slot]
    if kind then
      local value = fillValue(data, kind, ctx, rng)
      if not value then return nil end
      text = text:gsub("{VAR" .. slot .. "}", (value:gsub("%%", "%%%%")))
    end
  end
  return text
end

-- The call itself.  `here` is the map the player is standing on, which is the
-- one thing this cannot work out for itself.
function MatchCall.trainerMessage(data, save, entry, opts)
  local t = MatchCall.topics(data)
  if not (t and entry and entry.rematch) then return nil end
  local row = MatchCall.rematchRows(data)[entry.rematch + 1]
  local trainerId = row and row.trainers[1]
  local topic = trainerId and MatchCall.topicRow(data, trainerId)
  if not topic then return nil end
  opts = opts or {}
  local rng = opts.rng or function(lo, hi) return love.math.random(lo, hi) end
  local ctx = { trainerId = trainerId, map = row.map }

  local order = {}
  if opts.here and opts.here == row.map then
    order[#order + 1] = topic.sameRoute
  elseif MatchCall.isReady(data, save, entry.rematch) then
    order[#order + 1] = topic.otherRoute
  elseif rng(0, 2) ~= 0 then
    order[#order + 1] = topic["battle" .. rng(1, 3)]
  else
    order[#order + 1] = topic.personal
  end
  -- ...AND A FALLBACK ORDER BEHIND IT.  A line whose {VAR2} cannot be filled
  -- -- a route with no encounter table, a trainer whose party this dataset
  -- did not read -- would otherwise print the token, so the personalised
  -- line, which almost never needs one, is what it falls back to.
  order[#order + 1] = topic.personal
  order[#order + 1] = topic.battle2
  for _, ref in ipairs(order) do
    local block = ref and t.blocks[ref.block]
    local text = block and MatchCall.topicLine(data, block[ref.row], ctx, rng)
    if text then return text end
  end
  return nil
end

-- BuildProfBirchMatchCallText.  PROF. BIRCH is match call type 3, the one
-- header shape the cartridge gives no line table at all, because his call is
-- ASSEMBLED at the moment you place it: two fixed halves, then the rating line
-- his dex count earns, then a national postscript once the national dex is on.
-- Without this he was the one contact in the POKeNAV who never answered.
function MatchCall.birch(data, save)
  local r = MatchCall.record(data)
  local b = r and r.birch
  if not (b and b.ratings and #b.ratings > 0) then return nil end
  local Gen3 = commands()
  local seen, caught = Gen3.dexCounts({ save = save, game = { data = data } }, false)
  -- min(20, floor(caught / 10)): ten species per step, the top line reserved
  -- for two hundred and the two mythicals discounted before that last compare.
  local step = b.step or 10
  local index = math.floor(caught / step)
  if index > (b.max or 20) then index = b.max or 20 end
  if index >= (b.max or 20) then
    local dex = (save and save.pokedex) or {}
    local numbers = ((data.constants or {}).gen3HoennDex or {}).numbers or {}
    local discount = 0
    for _, national in ipairs(b.mythicals or {}) do
      for id, n in pairs(numbers) do
        if n == national and (dex.owned or {})[id] then discount = discount + 1 end
      end
    end
    index = math.floor((caught - discount) / step)
    if index > (b.max or 20) then index = b.max or 20 end
  end
  local join = b.join or "\f"
  local body = table.concat({
    b.intro and b.intro[1] or "",
    b.intro and b.intro[2] or "",
    b.ratings[index + 1] or b.ratings[#b.ratings],
  }, join)
  if save and save.nationalDex and b.national then
    local nSeen, nCaught = Gen3.dexCounts({ save = save, game = { data = data } }, true)
    body = body .. join .. b.national:gsub("{VAR1}", tostring(nSeen))
                                     :gsub("{VAR2}", tostring(nCaught))
  end
  return (body:gsub("{VAR1}", tostring(seen)):gsub("{VAR2}", tostring(caught)))
end

-- SelectMatchCallMessage: the HIGHEST-numbered line whose gate flag is set,
-- else the first; then set whatever it says to set.
function MatchCall.message(data, save, entry, opts)
  local lines = entry and entry.row and entry.row.lines
  if type(lines) ~= "table" or #lines == 0 then
    if entry and entry.row and entry.row.kind == 3 then
      return MatchCall.birch(data, save)
    end
    -- a REGISTERED TRAINER, who has no lines of their own because the
    -- cartridge builds theirs out of topics
    return MatchCall.trainerMessage(data, save, entry, opts)
  end
  local flags = save.flags or {}
  local pick = 1
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line.text then
      if not line.gate then pick = i break end
      if flags[commands().flagKey(line.gate)] == true then pick = i break end
    end
  end
  local line = lines[pick]
  if line and line.sets then
    save.flags = save.flags or {}
    save.flags[commands().flagKey(line.sets)] = true
  end
  return line and line.text or nil
end

return MatchCall
