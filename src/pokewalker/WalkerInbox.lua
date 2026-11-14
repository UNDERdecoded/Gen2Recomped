-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT THE POKEWALKER SENT HOME, unpacked immediately by WalkerDelivery
-- using destination ROM records, or retried by Game:restoreSave:
--   * the walked Pokemon: its steps as EXP, but never more than one level
--     (the original's rule), its friendship, then back into the PC;
--   * each catch: built by Pokemon.new in this generation's shape at its
--     course level, met "on the Pokewalker", into the PC;
--   * each item: into the bag by name (queued when the bag is full); an item
--     this game does not have becomes a Poke Ball / Potion of its kind.
-- Nothing is dropped: whatever cannot be placed (the PC full) stays in the
-- inbox for the next load.

local I = {}

-- "POKé BALL" (Gen 2-3 charmaps) and "Poké Ball" read as POKEBALL: the é was
-- stripped with the punctuation, so no ball ever matched and every ball the
-- walker sent home became a Potion
local function norm(s)
  s = tostring(s or ""):gsub("\195\169", "E"):gsub("\195\137", "E")
  return (s:upper():gsub("[^%w]", ""))
end

local function speciesKey(data, dex)
  for key, def in pairs(data.pokemon or {}) do
    if type(def) == "table" and tonumber(def.dex) == dex then return key, def end
  end
  -- Sinnoh's and Johto-on-DS tables carry no `dex`: they are keyed by it
  -- (data.pokemon[25] is Pikachu). Without this every catch sent home to
  -- HeartGold / SoulSilver / Platinum was dropped from the inbox unmade.
  local def = (data.pokemon or {})[dex]
  if dex > 0 and type(def) == "table" and def.dex == nil and tonumber(def.id or dex) == dex then return dex, def end
  return nil
end

local function bagKey(data,id)
  local alias=type(id)=="number" and ("ITEM_%03d"):format(id)
  return alias and data.items[alias] and alias or id
end

local function itemId(data, name)
  -- a Gen IV cache in another language: the English name's cartridge id
  local refKey = require("src.pokemon.Gen4EnglishRef").itemKey(data, name)
  if refKey then return bagKey(data, refKey) end
  local want = norm(name)
  local fallback
  for id, def in pairs(data.items or {}) do
    if type(def) == "table" then
      local n = norm(def.name)
      if n == want then return bagKey(data,id) end
      if n == "POTION" and not fallback then fallback = bagKey(data,id) end
    end
  end
  -- not in this game: a ball becomes a Poke Ball, anything else a Potion
  if want:find("BALL") then
    for id, def in pairs(data.items or {}) do
      if type(def) == "table" and norm(def.name) == "POKEBALL" then return bagKey(data,id) end
    end
  end
  -- (a Gen IV cache in another language has no English names to find them by)
  local R = require("src.pokemon.Gen4EnglishRef")
  if want:find("BALL") then
    local k = R.itemKey(data, "POKE BALL")
    if k then return bagKey(data, k) end
  end
  if not fallback then
    local k = R.itemKey(data, "POTION")
    if k then fallback = bagKey(data, k) end
  end
  return fallback
end

local function levelUp(data, mon, steps)
  local Growth = require("src.pokemon.Growth")
  local Stats = require("src.pokemon.Stats")
  local okF, Forms = pcall(require, "src.pokemon.Gen4Forms")
  local def = (okF and Forms.definition and Forms.definition(data, mon)) or (data.pokemon or {})[mon.species]
  if not def then return end
  local rates = data.growth_rates
  local level = tonumber(mon.level) or 1
  if level >= 100 then return end
  local exp = tonumber(mon.exp) or Growth.expForLevel(def.growthRate, level, rates)
  local cap = Growth.expForLevel(def.growthRate, level + 1, rates)
  mon.exp = math.min(exp + (tonumber(steps) or 0), cap)
  if mon.exp >= cap then
    mon.level = level + 1
    local old = mon.stats or {}
    if Stats.isGen3 and Stats.isGen3(def) then
      mon.stats = Stats.calcGen3(def, mon.level, mon.ivs, mon.evs, mon.nature)
    else
      mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
    end
    if mon.hp and old.hp then mon.hp = math.min(mon.stats.hp, mon.hp + (mon.stats.hp - old.hp)) end
  end
end

-- returns a short report, or nil when there was nothing
local function applyContents(save, data, opts)
  -- the Watt Shop's Events shelf: its own queue (src/pokewalker/WalkerEvents.lua)
  if not (opts and opts.skipEvents) then pcall(function() require("src.pokewalker.WalkerEvents").apply(save, data) end) end
  local box = save and save.walkerInbox
  if type(box) ~= "table" then return nil end
  data = data or require("src.core.Data")
  local Boxes = require("src.pokemon.Boxes")
  save.inventory=type(save.inventory)=="table" and save.inventory or {}
  local report = { mons = 0, caught = 0, items = 0 }
  -- the walked Pokemon
  for i = #(box.returning or {}), 1, -1 do
    local r = box.returning[i]
    local mon = r.raw
    -- PUT BACK BY THE WALKER ALREADY (WalkerLink.deliver): find it where it
    -- was placed -- or, if the player moved it about since, anywhere in the PC
    -- by species -- and give it its steps and friendship there
    if type(mon) ~= "table" and type(r.placed) == "table" then
      local boxes = save.boxes or {}
      local list = boxes[r.placed.box]
      list = type(list) == "table" and (list.mons or list) or {}
      local found = list[r.placed.index]
      if not (type(found) == "table" and found.species == r.species) then
        found = nil
        for _, b in ipairs(boxes) do
          for _, m in pairs((type(b) == "table" and (b.mons or b)) or {}) do
            if type(m) == "table" and m.species == r.species and not found then found = m end
          end
        end
      end
      if found then
        pcall(levelUp, data, found, (tonumber(r.steps) or 0) + (tonumber(r.bonusExp) or 0))
        if r.friendship then
          if found.happiness ~= nil then found.happiness = r.friendship else found.friendship = r.friendship end
        end
        report.mons = report.mons + 1
      end
      table.remove(box.returning, i)
    elseif type(mon) == "table" then
      pcall(levelUp, data, mon, (tonumber(r.steps) or 0) + (tonumber(r.bonusExp) or 0))
      if r.friendship then
        if mon.happiness ~= nil then mon.happiness = r.friendship
        else mon.friendship = r.friendship end
      end
      if Boxes.deposit(save, mon) then table.remove(box.returning, i); report.mons = report.mons + 1 end
    else
      table.remove(box.returning, i)
    end
  end
  -- the catches
  local Pokemon = require("src.pokemon.Pokemon")
  for i = #(box.mons or {}), 1, -1 do
    local c = box.mons[i]
    local key = speciesKey(data, tonumber(c.species) or 0)
    if key then
      local ok,mon=true,c.raw
      if not (type(mon)=="table" and mon.species==key) then
        ok,mon=pcall(Pokemon.new,data,key,tonumber(c.level) or 5)
      end
      if ok and type(mon) == "table" then
        mon.metLocation = "POKEWALKER"
        mon.ot = mon.ot or (save.player and save.player.name)
        mon.otId = mon.otId or (save.player and save.player.id)
        -- a Poke Radar legendary keeps its mark; a shiny find is made shiny
        -- the game's own way (Gen 2 DVs, Gen 3+ a personality against the OT)
        if c.legendary then mon.walkerLegendary = true end
        if c.shiny and not Pokemon.isShiny(mon) then
          pcall(Pokemon.forceShiny, data, mon, nil, mon.otId)
        end
        if Boxes.deposit(save, mon) then
          table.remove(box.mons,i);report.caught=report.caught+1
          save.pokedex=save.pokedex or {};save.pokedex.seen=save.pokedex.seen or {};save.pokedex.owned=save.pokedex.owned or {}
          save.pokedex.seen[mon.species]=true;save.pokedex.owned[mon.species]=true
        else c.raw=mon end -- preserve the individual while storage is full
      elseif not ok then
        require("src.core.Logger").warn("walker catch %s pending: %s",tostring(c.species),tostring(mon))
      end
    end -- Unknown species stay queued; never erase a reward we cannot resolve.
  end
  -- the items
  local Bag = require("src.inventory.Bag")
  for i = #(box.items or {}), 1, -1 do
    local id = itemId(data, box.items[i].name)
    -- a stack (the Watt Shop, the minigames) keeps its count
    local n = math.max(1, math.floor(tonumber(box.items[i].count) or 1))
    if id then
      local room=math.max(0,Bag.stackLimit(id,data)-(tonumber(save.inventory[id]) or 0))
      local take=math.min(n,room)
      if take>0 and Bag.add(save,id,take,data) then
        report.items=report.items+1
        n=n-take
      end
      if n==0 then table.remove(box.items,i) else box.items[i].count=n end
    end -- A full bag or unknown item stays in the inbox, never a hidden PC stack.

  end
  if #(box.returning or {}) == 0 and #(box.mons or {}) == 0 and #(box.items or {}) == 0 then
    save.walkerInbox = nil
  end
  if report.mons + report.caught + report.items == 0 then return nil end
  pcall(function()
    require("src.core.Logger").info("pokewalker: home -- %d walked, %d caught, %d items",
      report.mons, report.caught, report.items)
  end)
  return report
end

function I.apply(save,data,opts)
  data=data or require("src.core.Data")
  return require("src.pokemon.Boxes").withData(data,function()
    return applyContents(save,data,opts)
  end)
end

return I
