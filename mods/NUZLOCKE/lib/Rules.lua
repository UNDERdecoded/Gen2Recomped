-- The Nuzlocke rules over a save's run record (save.runModes).  Pure: no
-- love, no Game -- the mod's main.lua feeds it what the engine's
-- runmodes.* seams report, and the tests drive it with plain tables.
--
--   * one encounter per AREA (region-map section, else map id): the first
--     wild POKéMON met there is the only one that may be caught.  It counts
--     from the moment the player carries a POKé BALL (before that nothing
--     could be caught anyway).  Scripted single battles (legendaries,
--     Snorlax) are statics: they never use up an area and may be caught.
--   * a POKéMON that faints is dead: flagged at once (RunHooks.fainted),
--     moved out of the party into the run's GRAVEYARD on the next overworld
--     frame -- kept, never deleted.
--   * the run is over when the whole party is gone.
--
-- Soul Link (lib/SoulLink.lua) pairs areas with a partner: every counted
-- encounter gets its number (the n-th of the run, caught or missed), and a
-- catch from one is tagged mon.soulPair = area, mon.soulIdx = n.  Statics and
-- catches made before the first ball are free: no pair.

local Rules = {}

Rules.DEAD = "nuzDead"

function Rules.ensure(rm)
  rm.areas = rm.areas or {}
  rm.graveyard = rm.graveyard or {}
  rm.catches = rm.catches or 0
  rm.encounters = rm.encounters or 0
  if rm.soulLink then
    rm.soul = rm.soul or {}
    local s = rm.soul
    s.pairs = s.pairs or {}
    s.outbox = s.outbox or {}
    s.seen = s.seen or {}
    s.nextId = s.nextId or 1
    s.runId = s.runId or ("%d-%d"):format(tonumber(rm.seed) or 0, math.random(1, 0x7ffffff))
  end
  return rm
end

local function isEgg(mon) return type(mon) == "table" and (mon.isEgg or mon.egg == true) end

-- ctx: { area, species, static, hasBall }
-- returns { catchable = bool, reason = string|nil, counted = bool }
function Rules.wildStart(rm, ctx)
  Rules.ensure(rm)
  if ctx.static then return { catchable = true, counted = false } end
  local area = tostring(ctx.area or "?")
  local rec = rm.areas[area]
  if rec then
    return { catchable = false, counted = false,
             reason = "NUZLOCKE: this area's\nencounter is used!" }
  end
  if not ctx.hasBall then return { catchable = true, counted = false } end
  rm.encounters = rm.encounters + 1
  rm.areas[area] = { state = "open", species = ctx.species, idx = rm.encounters }
  return { catchable = true, counted = true, area = area, idx = rm.encounters }
end

-- a catch.  Statics and pre-ball catches still tag the mon.
function Rules.caught(rm, area, mon)
  Rules.ensure(rm)
  area = tostring(area or "?")
  rm.catches = rm.catches + 1
  local rec = rm.areas[area]
  local paired = rec ~= nil and rec.state == "open"
  if not rec then
    rm.areas[area] = { state = "caught", species = mon and mon.species }
    rec = rm.areas[area]
  elseif rec.state == "open" then
    rec.state = "caught"
  end
  if type(mon) == "table" then
    mon.nuzArea = area
    -- only the area's own encounter is paired; a static or a pre-ball catch
    -- (no open record) is free
    if rm.soulLink and paired then
      mon.soulPair = area
      mon.soulIdx = rec.idx
    end
  end
  return rec
end

-- the battle that opened an area ended without a catch: the chance is spent
function Rules.battleEnd(rm, area, result)
  Rules.ensure(rm)
  local rec = area and rm.areas[tostring(area)]
  if rec and rec.state == "open" and result ~= "caught" then
    rec.state = "missed"
    return rec
  end
  return nil
end

local function bury(rm, mon, where, cause, now)
  mon[Rules.DEAD] = true
  local g = rm.graveyard
  g[#g + 1] = { mon = mon, from = where, cause = cause or "fainted",
                area = mon.nuzArea, at = now }
  return g[#g]
end

-- move every dead (flagged, or at 0 HP outside an egg) party mon to the
-- graveyard.  Returns { buried = {...}, partyGone = bool }.
function Rules.sweep(save, now)
  local rm = save.runModes
  Rules.ensure(rm)
  local party = save.party or {}
  local keep, buried = {}, {}
  for _, mon in ipairs(party) do
    local dead = type(mon) == "table" and not isEgg(mon)
      and (mon[Rules.DEAD] == true or (tonumber(mon.hp) or 1) <= 0)
    if dead then
      buried[#buried + 1] = bury(rm, mon, "party", mon.nuzCause or "fainted", now)
    else
      keep[#keep + 1] = mon
    end
  end
  if #buried > 0 then
    for i = #party, 1, -1 do party[i] = nil end
    for i, mon in ipairs(keep) do party[i] = mon end
  end
  local living = 0
  for _, mon in ipairs(party) do if not isEgg(mon) then living = living + 1 end end
  return { buried = buried, partyGone = #buried > 0 and living == 0 }
end

-- kill the mon paired with `key` (Soul Link): party first, then the boxes.
-- match(mon) decides; returns the graveyard entry or nil
function Rules.killWhere(save, match, cause, now)
  local rm = save.runModes
  Rules.ensure(rm)
  for i, mon in ipairs(save.party or {}) do
    if type(mon) == "table" and not mon[Rules.DEAD] and match(mon) then
      mon[Rules.DEAD] = true
      mon.nuzCause = cause
      return { mon = mon, where = "party", index = i, pending = true }
    end
  end
  for b, box in pairs(save.boxes or {}) do
    if type(box) == "table" then
      for slot, mon in pairs(box) do
        if type(mon) == "table" and not mon[Rules.DEAD] and match(mon) then
          box[slot] = nil
          return bury(rm, mon, "box " .. tostring(b), cause, now)
        end
      end
    end
  end
  return nil
end

-- RUN OVER -> keep playing with the rules off: every graveyard mon comes
-- back, healed, to the party (then the boxes).  Nothing was ever deleted.
function Rules.revive(save, heal, deposit)
  local rm = save.runModes
  Rules.ensure(rm)
  save.party = save.party or {}
  local back = 0
  for _, entry in ipairs(rm.graveyard) do
    local mon = entry.mon
    if type(mon) == "table" then
      mon[Rules.DEAD] = nil
      mon.nuzCause = nil
      if heal then pcall(heal, mon) end
      if #save.party < 6 then save.party[#save.party + 1] = mon
      elseif deposit then deposit(save, mon) end
      back = back + 1
    end
  end
  rm.graveyardRevived = (rm.graveyardRevived or 0) + back
  rm.graveyard = {}
  rm.rulesOff = true
  return back
end

-- the record screen's lines
function Rules.summary(rm)
  Rules.ensure(rm)
  local caught, missed = 0, 0
  for _, rec in pairs(rm.areas) do
    if rec.state == "caught" then caught = caught + 1
    elseif rec.state == "missed" then missed = missed + 1 end
  end
  return { areas = caught + missed, caught = caught, missed = missed, dead = #rm.graveyard }
end

return Rules
