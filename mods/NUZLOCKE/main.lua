-- NUZLOCKE: the Nuzlocke and Soul Link rules for every Pokemon game the
-- engine runs (Red/Blue/Yellow, Gold/Silver/Crystal, Emerald/FireRed/
-- LeafGreen, Platinum, HeartGold/SoulSilver, Black/White).
--
-- A save opts in at NEW GAME (the engine's RUN MODES screen,
-- src/ui/RunSetup.lua); every other save is untouched -- this mod does
-- nothing unless save.runModes says nuzlocke.  The engine fires the
-- `runmodes.*` seams from its shared battle / overworld code
-- (src/runmodes/RunHooks.lua); the rules are lib/Rules.lua, the partner
-- link lib/SoulLink.lua.  Nothing here ever deletes a save or a POKéMON:
-- the fallen go to the run's GRAVEYARD, and a finished run can be played on
-- with the rules off, every one of them back.
--
-- It judges only this save's own run and never the shared simulation, so
-- it declares run_rules: online play stays open with it on
-- (Handshake.onlineBlockers checks the claim).

local mod = ...

local L = {}
local loaded = {}
local function lib(name)
  if loaded[name] then return loaded[name] end
  local rel = "lib/" .. name .. ".lua"
  local source = mod:read(rel)
  if not source then
    mod.log:error("%s is missing -- reinstall the NUZLOCKE mod", rel)
    return nil
  end
  local chunk, err = load(source, "@" .. tostring(mod.path) .. "/" .. rel)
  if not chunk then
    mod.log:error("%s did not compile (%s) -- reinstall the NUZLOCKE mod", rel, tostring(err))
    return nil
  end
  loaded[name] = chunk(L)
  return loaded[name]
end

local Rules = lib("Rules")
local SoulLink = lib("SoulLink")
local Screens = lib("Screens")
if not (Rules and SoulLink and Screens) then return end

local RunModes = require("src.runmodes.RunModes")

local G = nil               -- the live Game, from the seams
local function save() return G and G.save end
local function rm() local s = save(); return s and s.runModes end

local function now() return os.time and os.time() or 0 end

local notices = {}
local function say(text) notices[#notices + 1] = text end

local function gameId()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.get and GV.get() or nil
end

-- ---------------------------------------------------------------- balls --
local function hasBall(game)
  local s = game and game.save
  local inv = s and s.inventory
  if type(inv) ~= "table" then return true end
  local okE, ItemEffects = pcall(require, "src.inventory.ItemEffects")
  if not okE then return true end
  local items = game.data and game.data.items or {}
  for id, count in pairs(inv) do
    local n = type(count) == "table" and (count.count or count.qty or count[2]) or count
    if (tonumber(n) or 0) > 0 then
      local itemId = type(count) == "table" and (count.id or count[1]) or id
      local ok, isBall = pcall(ItemEffects.isBall, itemId, items[itemId])
      if ok and isBall then return true end
    end
  end
  -- a bag the scan does not understand must not lock areas the player could
  -- never have caught in: when unsure, count nothing until a ball is seen
  return false
end
L.hasBall = hasBall

-- ------------------------------------------------------------ soul link --
local link = SoulLink.new({
  save = save,
  now = now,
  name = function() local s = save(); return s and s.player and s.player.name or "?" end,
  game = gameId,
  say = say,
  kill = function(match, cause)
    local s = save()
    if not s then return nil end
    return Rules.killWhere(s, match, cause, now())
  end,
})
L.link = link

local nextOpen = 0
local function pumpLink()
  local r = rm()
  if not (r and r.soulLink) or r.rulesOff then return end
  Rules.ensure(r)
  if not link.ch then
    local t = love and love.timer and love.timer.getTime() or now()
    if t < nextOpen then return end
    nextOpen = t + 5
    local okW, OnlineWorld = pcall(require, "src.online.world.OnlineWorld")
    if not okW then return end
    local c = OnlineWorld.client and OnlineWorld.client()
    if not (c and c.state == "in") then return end
    if c.hasService and not c:hasService("soullink") then return end
    OnlineWorld.serviceChannel("soullink", function(ch) if ch then link:attach(ch) end end)
    return
  end
  link:pump()
end

-- ------------------------------------------------------------ screens --
local function monName(game, mon)
  if mon.nickname and mon.nickname ~= "" then return tostring(mon.nickname) end
  local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
  return tostring(def and def.name or mon.species)
end

local function areaName(game, area)
  local sec = tostring(area or ""):match("^sec:(.*)$")
  if sec then
    local names = game.data and game.data.regionMapSections
    local n = type(names) == "table" and names[tonumber(sec) or sec]
    if type(n) == "table" then n = n.name end
    if type(n) == "string" then return n end
    return "AREA " .. sec
  end
  return tostring(area or "?"):gsub("^map:", "")
end

local openRecord

local function revive(game)
  local okP, Pokemon = pcall(require, "src.pokemon.Pokemon")
  local okB, Boxes = pcall(require, "src.pokemon.Boxes")
  local n = Rules.revive(game.save, okP and Pokemon.heal or nil, okB and Boxes.deposit or nil)
  return n
end

local function openRunOver(game)
  local r = game.save.runModes
  r.runOver = true
  r.runOverAt = now()
  Screens.list(game, {
    title = "RUN OVER", modal = true,
    lines = function()
      local s = Rules.summary(r)
      return {
        "Your whole party is gone.",
        ("Areas %d, caught %d, fallen %d."):format(s.areas, s.caught, s.dead),
        "The save is kept. Nothing was deleted.",
      }
    end,
    rows = {
      { label = "PLAY ON, NO RULES", run = function(screen)
          local n = revive(game)
          screen:close()
          say(("The run's %d POKéMON are back.\nRules are off for this save."):format(n))
        end },
      { label = "END RUN", run = function(screen)
          screen:close()
          pcall(game.writeSave, game)
          if game.returnToTitle then game:returnToTitle() end
        end },
      { label = "RECORD", run = function() openRecord(game) end },
    },
  })
end

openRecord = function(game)
  local r = game.save and game.save.runModes
  if not r then return end
  Rules.ensure(r)
  local rows = {}
  if r.soulLink and not r.rulesOff then
    rows[#rows + 1] = { label = "GO ONLINE", run = function(screen)
      screen:close()
      local okW, OnlineWorld = pcall(require, "src.online.world.OnlineWorld")
      if okW and OnlineWorld.openMenu then OnlineWorld.openMenu(game) end
    end }
  end
  if r.runOver and not r.rulesOff then
    rows[#rows + 1] = { label = "PLAY ON, NO RULES", run = function(screen)
      local n = revive(game)
      screen:close()
      say(("The run's %d POKéMON are back.\nRules are off for this save."):format(n))
    end }
  end
  rows[#rows + 1] = { label = "BACK", run = function(screen) screen:close() end }
  Screens.list(game, {
    title = r.soulLink and "SOUL LINK RECORD" or "NUZLOCKE RECORD",
    rows = rows,
    lines = function()
      local s = Rules.summary(r)
      local out = { RunModes.describe(game) .. "   SEED " .. tostring(r.seed),
        ("Areas %d: caught %d, missed %d. Fallen %d."):format(s.areas, s.caught, s.missed, s.dead) }
      if r.soulLink then out[#out + 1] = "Partner: " .. link:status() end
      if r.runOver then out[#out + 1] = r.rulesOff and "Run over; playing on with rules off." or "RUN OVER." end
      if #r.graveyard > 0 then out[#out + 1] = "-- THE FALLEN --" end
      for _, e in ipairs(r.graveyard) do
        local m = e.mon or {}
        out[#out + 1] = ("%s Lv%s %s%s"):format(monName(game, m), tostring(m.level or "?"),
          areaName(game, e.area or m.nuzArea), e.cause == "partner" and " (soul)" or "")
      end
      local list = {}
      for area, rec in pairs(r.areas) do list[#list + 1] = { area = area, rec = rec } end
      table.sort(list, function(a, b) return tostring(a.area) < tostring(b.area) end)
      if #list > 0 then out[#out + 1] = "-- AREAS --" end
      for _, it in ipairs(list) do
        out[#out + 1] = ("%s: %s"):format(areaName(game, it.area), it.rec.state)
      end
      return out
    end,
  })
end

RunModes.registerProvider({
  openRecord = function(game) G = game; openRecord(game) end,
  rules = Rules,
  link = link,
})

-- ------------------------------------------------------------ the seams --
mod.hooks:wrap("runmodes.wild_start", function(next, ctx)
  local verdict = next(ctx)
  G = ctx.game
  local r = rm()
  if not r then return verdict end
  local v = Rules.wildStart(r, { area = ctx.area, species = ctx.species,
                                 static = ctx.static, hasBall = hasBall(ctx.game) })
  if v.counted and ctx.battle then ctx.battle.nuzArea = v.area end
  if v.catchable == false then return { catchable = false, reason = v.reason } end
  return verdict
end)

mod.events:on("runmodes.caught", function(p)
  G = p.game
  local r = rm()
  if not r then return end
  local area = (p.battle and p.battle.nuzArea) or p.area
  Rules.caught(r, area, p.mon)
  if r.soulLink and p.mon and p.mon.soulPair then link:areaResult(tostring(area), "caught", p.mon) end
end)

mod.events:on("runmodes.battle_end", function(p)
  G = p.game
  local r = rm()
  if not r then return end
  local area = p.battle and p.battle.nuzArea
  local rec = area and Rules.battleEnd(r, area, p.result)
  if rec and r.soulLink then
    link:areaResult(tostring(area), "missed", nil, rec.idx)
  end
end)

mod.events:on("runmodes.tick", function(p)
  G = p.game
  local s = save()
  local r = s and s.runModes
  if not r then return end
  pumpLink()
  local res = Rules.sweep(s, now())
  for _, entry in ipairs(res.buried) do
    if r.soulLink then link:died(entry.mon, entry.cause) end
  end
  if #res.buried > 0 then
    local names = {}
    for _, e in ipairs(res.buried) do names[#names + 1] = monName(G, e.mon) end
    say(table.concat(names, ", ") .. (#names > 1 and " are" or " is") .. " gone for good.")
  end
  if res.partyGone then
    notices = {}
    openRunOver(G)
    return
  end
  if notices[1] and G.stack then
    local text = table.remove(notices, 1)
    Screens.list(G, { title = r.soulLink and "SOUL LINK" or "NUZLOCKE", lines = { text },
                      rows = { { label = "OK", run = function(screen) screen:close() end } } })
  end
end)

mod.exports.rules = Rules
mod.exports.link = link
mod.exports.openRecord = function(game) G = game; openRecord(game) end
mod.exports._lib = L
