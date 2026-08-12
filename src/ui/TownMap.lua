-- TOWN MAP viewer (engine/menus/town_map.asm; location data from
-- data/maps/town_map_entries.asm via the extractor's field.townMap).
--
-- Grid mode (when field.townMap provides coordinates): the 20x18-tile
-- Kanto map with a filled square per known location -- routes lighter,
-- towns darker -- a blinking cursor the d-pad snaps between locations,
-- the selected name in a banner up top, and the player's current
-- location blinking.  List mode (townMap data missing): up/down through
-- an ordered list of fly towns instead.  B closes.
--
-- Fly mode (opts.fly + opts.onFly, LoadTownMap_Fly): the same Kanto map,
-- but the cursor cycles ONLY the visited fly destinations (Up/Down, in fly
-- order), the banner reads "To <NAME>", and A calls onFly(mapId) to depart.
-- This is what the party-menu FLY field move opens (#195).

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")

local TownMap = {}
TownMap.__index = TownMap
TownMap.isOpaque = true

-- SGB: PalPacket_TownMap, whole screen.  Gen2's map is a real GBC picture
-- (RomExtractorGen2:gen2TownMap rips town_map_johto/kanto.png with the six
-- PokegearPals palettes baked in), so it wants no shade-remap at all -- and
-- TOWNMAP is a Gen1 SuperPalette name the Gen2 cache does not carry anyway.
--
-- That covers the Pokedex AREA screen too: pokedex.asm's .Area runs the whole
-- screen through `predef Pokedex_GetArea`, which ends on GetSGBLayout with
-- SCGB_POKEGEAR_PALS.  The SCGB_POKEDEX after it only restores the dex ENTRY
-- screen once you back out, so the area map is NOT in the dex's orange.
function TownMap:sgbPalettes(game)
  if self.mode == "gen2" then return nil end
  return require("src.render.PaletteFX").wholeNamed(game.data, "TOWNMAP")
end

-- Gen2 town map.  field.townMap is a completely different shape from Gen1's:
-- two full-screen pictures (johto/kanto) plus `landmarks`, a flat id -> {name,
-- x, y} table whose coordinates are absolute screen pixels, and every map
-- record carries the landmark id it belongs to.  Landmarks from $2E up are
-- Kanto: `DEF KANTO_LANDMARK EQU const_value` sits immediately BEFORE
-- LANDMARK_PALLET_TOWN in constants/landmark_constants.asm, so Pallet is
-- the first of them, not Route 1.  A landmark short of it and Pallet read
-- as Johto -- flown to off the Johto picture with no cursor drawn on it.
local GEN2_KANTO_FIRST = 0x2E

local function gen2Locations(game)
  local tm = (game.data.field or {}).townMap
  if type(tm) ~= "table" or type(tm.landmarks) ~= "table" or not tm.johto then
    return nil
  end
  local byLandmark, locs = {}, {}
  for id, e in pairs(tm.landmarks) do
    local x, y = tonumber(e and e.x), tonumber(e and e.y)
    if x and y and tonumber(id) and tonumber(id) > 0 then
      local loc = {
        name = tostring(e.name or ""):gsub("\n", " "),
        -- Landmarks stores HARDWARE OAM bytes, not screen pixels:
        -- GetLandmarkCoords hands them straight to wVirtualOAMSprite00,
        -- and the GB adds the sprite origin (-8 x, -16 y).  px/py are the
        -- 8x8 icon's CENTRE on screen, which is what every marker here
        -- draws around -- taken raw, every nest sat 4px right and 12px
        -- below the town it belongs to.
        px = x - 4, py = y - 12, landmark = tonumber(id),
        region = tonumber(id) >= GEN2_KANTO_FIRST and "kanto" or "johto",
      }
      byLandmark[tonumber(id)] = loc
      locs[#locs + 1] = loc
    end
  end
  if #locs == 0 then return nil end
  table.sort(locs, function(a, b) return a.landmark < b.landmark end)
  local byMap = {}
  for mapId, def in pairs(game.data.maps or {}) do
    local loc = def.landmark and byLandmark[def.landmark]
    if loc then byMap[mapId] = loc end
  end
  return locs, byMap
end

local function gen2Images(game)
  local tm = (game.data.field or {}).townMap or {}
  local out = {}
  for _, region in ipairs({ "johto", "kanto" }) do
    local path = tm[region]
    if path then
      local ok, img = pcall(love.graphics.newImage, path)
      if ok then out[region] = img end
    end
  end
  return out
end

-- pull x/y out of a townMap entry regardless of the exact shape the
-- extractor settled on ({x=,y=}, {col=,row=} or {coords={x=,y=}})
local function entryCoords(e)
  if type(e) ~= "table" then return nil end
  local c = e.coords or e
  local x = tonumber(c.x or c.col)
  local y = tonumber(c.y or c.row)
  return x, y
end

local function entryName(e, mapId)
  local name = type(e) == "table" and (e.name or e.label) or nil
  return name or mapId:gsub("_", " ")
end

local function isRoute(loc)
  return loc.name:find("ROUTE", 1, true) ~= nil
end

-- Build the ordered location list.  Grid mode dedupes shared entries
-- (interior maps point at their town's square); list mode falls back to
-- the fly towns so the screen still works without townMap data.
local function buildLocations(game)
  local field = game.data.field or {}
  local townMap = field.townMap
  -- the extractor nests the per-map entries under .locations
  if type(townMap) == "table" and type(townMap.locations) == "table" then
    townMap = townMap.locations
  end
  local locs, byMap = {}, {}
  if type(townMap) == "table" and next(townMap) then
    local seen = {}
    for mapId, e in pairs(townMap) do
      local x, y = entryCoords(e)
      if x and y then
        local name = entryName(e, mapId)
        local key = ("%s:%d:%d"):format(name, x, y)
        local loc = seen[key]
        if not loc then
          loc = { name = name, x = x, y = y }
          seen[key] = loc
          table.insert(locs, loc)
        end
        byMap[mapId] = loc
      end
    end
    if #locs > 0 then
      table.sort(locs, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        return a.name < b.name
      end)
      return locs, byMap, "grid"
    end
  end
  -- fallback: towns from the fly order (deduped, outdoor maps only)
  local Map = require("src.world.Map")
  local seen = {}
  for _, mapId in ipairs(field.flyOrder or {}) do
    local def = game.data.maps and game.data.maps[mapId]
    -- accept the PLATEAU tileset too so Indigo Plateau shows on the
    -- stale-asset list fallback, matching the fly-list filter (#203)
    if not seen[mapId] and def
       and (Map.isOutdoor(def) or def.tileset == "PLATEAU") then
      seen[mapId] = true
      local loc = { name = mapId:gsub("_", " ") }
      table.insert(locs, loc)
      byMap[mapId] = loc
    end
  end
  if #locs == 0 then locs = { { name = "KANTO" } } end
  return locs, byMap, "list"
end

-- load the extracted Kanto background (nil on stale asset builds)
local function loadBackground(game)
  local tm = (game.data.field or {}).townMap or {}
  local bg = tm.background
  if not (bg and bg.map and bg.tiles) then return nil end
  local ok, img = pcall(love.graphics.newImage, bg.tiles.path)
  if not ok then return nil end
  local quads = {}
  local iw, ih = img:getDimensions()
  local per = iw / 8
  for i = 0, per * (ih / 8) - 1 do
    quads[i] = love.graphics.newQuad((i % per) * 8,
                                     math.floor(i / per) * 8, 8, 8, iw, ih)
  end
  local cursor
  if bg.cursor then
    local okc, c = pcall(love.graphics.newImage, bg.cursor.path)
    cursor = okc and c or nil
  end
  return { img = img, quads = quads, map = bg.map, cursor = cursor }
end

-- town-map grid -> screen pixels (TownMapCoordsToOAMCoords: the 16x16
-- nybble grid sits 2 tiles in and 1 tile down on the 20x18 screen)
local function markerXY(loc)
  return loc.x * 8 + 16, loc.y * 8 + 8
end

-- the row-0 name banner; fly mode prefixes "To " like LoadTownMap_Fly
-- (engine/menus/town_map.asm prints the destination as "To <NAME>")
function TownMap:bannerText(loc)
  return (self.fly and "To " or "") .. loc.name
end

-- Fly mode selection set (engine/menus/town_map.asm LoadTownMap_Fly): the
-- cursor cycles ONLY the visited fly destinations, in fly order, each landing
-- on its town square.  Built from field.flyOrder filtered to visited outdoor
-- towns that have a fly-warp spot, deduped, reusing the grid loc so the cursor
-- lands on the town and its name shows in the banner.
local function buildFlyList(game, byMap)
  local field = game.data.field or {}
  local visited = game.save.visited or {}
  local flyWarps = field.flyWarps or {}
  local Map = require("src.world.Map")
  local flyLocs, flyMapIds, seen = {}, {}, {}
  for _, mapId in ipairs(field.flyOrder or {}) do
    local def = game.data.maps and game.data.maps[mapId]
    -- INDIGO_PLATEAU is a normal Fly spot (engine/menus/town_map.asm
    -- LoadTownMap_Fly cycles it like any town), but its map uses tileset
    -- "PLATEAU" not OVERWORLD, so Map.isOutdoor() alone dropped it from the
    -- cursor even though it is visited and has a fly warp.  Allow PLATEAU here
    -- while the CAVERN/FACILITY dungeon escape spots that share flyOrder still
    -- fail the gate and stay out (#203).
    if not seen[mapId] and visited[mapId] and flyWarps[mapId]
       and def and (Map.isOutdoor(def) or def.tileset == "PLATEAU") then
      seen[mapId] = true
      local loc = byMap[mapId] or { name = mapId:gsub("_", " ") }
      table.insert(flyLocs, loc)
      flyMapIds[#flyLocs] = mapId
    end
  end
  return flyLocs, flyMapIds
end

-- opts.nestSpecies: the Pokédex AREA screen (LoadTownMap_Nest) --
-- blink a nest icon on every map whose wild slots hold the species
function TownMap.new(game, opts)
  opts = opts or {}
  pcall(function()
    require("src.script.Gen2Commands").g2_ensure_roam_landmarks({ save = game.save, game = game })
  end)
  local self = setmetatable({}, TownMap)
  self.game = game
  self.bg = loadBackground(game)
  local g2locs, g2byMap = gen2Locations(game)
  if g2locs then
    self.locs, self.byMap, self.mode = g2locs, g2byMap, "gen2"
    self.images = gen2Images(game)
    self.region = "johto"
  else
    self.locs, self.byMap, self.mode = buildLocations(game)
  end
  if opts.nestSpecies then
    self.nestSpecies = opts.nestSpecies
    self.nests = {}
    local seen = {}
    -- Gen2 grass tables carry THREE slot sets: `slots` is the day one and
    -- `byTime.morn` / `byTime.nite` ride alongside (RomExtractorGen2
    -- :extractEncounters).  Pokedex_GetArea searches all of them, so a mon
    -- that only appears at night has to be scanned for here too -- reading
    -- `slots` alone left every nocturnal species AREA UNKNOWN.
    local function holds(group)
      if type(group) ~= "table" then return false end
      for _, slot in ipairs(group.slots or {}) do
        if slot.species == opts.nestSpecies then return true end
      end
      for _, timed in pairs(group.byTime or {}) do
        for _, slot in ipairs(timed.slots or {}) do
          if slot.species == opts.nestSpecies then return true end
        end
      end
      return false
    end
    for mapId, enc in pairs(game.data.encounters or {}) do
      local found = false
      for _, group in pairs(enc) do
        if holds(group) then found = true break end
      end
      local loc = found and self.byMap[mapId]
      if loc and not seen[loc] then
        seen[loc] = true
        table.insert(self.nests, loc)
      end
    end
    -- field.townMap.nest lifts the icon path out of the engine
    local nest = ((game.data.field or {}).townMap or {}).nest
    local ok, img = pcall(love.graphics.newImage,
                          (nest and nest.path)
                          or "assets/generated/townmap/nest.png")
    self.nestIcon = ok and img or nil
    -- Pokedex_GetArea opens on whichever region actually has nests
    if self.mode == "gen2" then
      for _, loc in ipairs(self.nests) do
        if loc.region == "johto" then self.region = "johto" break end
        self.region = loc.region
      end
    end
  end
  if opts.fly and self.mode == "gen2" then
    -- Gen2 grid uses absolute pixels, so the grid coord check below does not
    -- apply; the fly list is still the visited fly towns.
    local flyLocs, flyMapIds = buildFlyList(game, self.byMap)
    if #flyLocs > 0 then
      self.fly, self.onFly = true, opts.onFly
      self.locs, self.flyMapIds = flyLocs, flyMapIds
    end
  elseif opts.fly then
    -- FLY picker (LoadTownMap_Fly): restrict the selectable set to the
    -- visited fly towns so Up/Down cycle only those and A knows the mapId.
    local flyLocs, flyMapIds = buildFlyList(game, self.byMap)
    if #flyLocs > 0 then
      self.fly = true
      self.onFly = opts.onFly
      self.locs = flyLocs
      self.flyMapIds = flyMapIds
      -- grid rendering needs coords on every entry; without them fall back to
      -- the name list so the fly screen still works on stale asset builds
      if self.mode == "grid" then
        for _, loc in ipairs(flyLocs) do
          if not (loc.x and loc.y) then self.mode = "list" break end
        end
      end
    end
    -- with nothing visited yet there is nowhere to fly: leave self.fly unset
    -- so the screen degrades to a plain viewer (B closes)
  end
  -- the player's current location (guard: overworld may not be running)
  local mapId = game.overworld and game.overworld.map and game.overworld.map.id
  self.playerLoc = mapId and self.byMap[mapId] or nil
  self.sel = 1
  for i, loc in ipairs(self.locs) do
    if loc == self.playerLoc then self.sel = i break end
  end
  self.blink = 0
  if self.fly then self:followRegion() end
  return self
end

-- snap the cursor to the nearest location in the pressed direction
function TownMap:moveGrid(dx, dy)
  local cur = self.locs[self.sel]
  local best, bestScore
  for i, loc in ipairs(self.locs) do
    if i ~= self.sel then
      local ddx, ddy = loc.x - cur.x, loc.y - cur.y
      local fwd = ddx * dx + ddy * dy       -- progress along the d-pad axis
      local side = math.abs(ddx * dy) + math.abs(ddy * dx)
      if fwd > 0 then
        local score = fwd + side * 3        -- prefer staying on-axis
        if not best or score < bestScore then best, bestScore = i, score end
      end
    end
  end
  if best then
    self.sel = best
    Sound.play(self.game.data, "Tink")
  end
end

function TownMap:moveList(step)
  local n = #self.locs
  if n < 2 then return end
  self.sel = (self.sel - 1 + step) % n + 1
  Sound.play(self.game.data, "Tink")
end

-- Gen 2 draws Johto and Kanto as two separate pictures, and the FLY list
-- runs straight through both.  Cycling past Silver Cave has to turn the
-- page or the cursor simply stops being drawn -- only markers whose region
-- matches the picture on screen are (drawGen2) -- and every Kanto
-- destination is picked blind.
function TownMap:followRegion()
  local loc = self.locs[self.sel]
  if loc and loc.region then self.region = loc.region end
end

function TownMap:update(dt)
  self.blink = (self.blink + 1) % 32
  local input = self.game.input
  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    self.game.stack:pop()
    return
  end
  if self.fly then
    -- LoadTownMap_Fly: Up/Down cycle the visited destinations, A flies there,
    -- B cancels (handled above).  moveList walks self.locs, now the fly list.
    if input:wasPressed("a") then
      Sound.play(self.game.data, "Press_AB")
      local mapId = self.flyMapIds[self.sel]
      self.game.stack:pop()
      if mapId and self.onFly then self.onFly(mapId) end
      return
    elseif input:wasPressed("up") then
      self:moveList(-1)
      self:followRegion()
    elseif input:wasPressed("down") then
      self:moveList(1)
      self:followRegion()
    end
  elseif self.nestSpecies then
    -- Pokedex_GetArea: LEFT/RIGHT swap JOHTO and KANTO, A/B leave
    if self.mode == "gen2"
       and (input:wasPressed("left") or input:wasPressed("right")) then
      self.region = self.region == "johto" and "kanto" or "johto"
      Sound.play(self.game.data, "Tink")
    elseif input:wasPressed("a") then
      Sound.play(self.game.data, "Press_AB")
      self.game.stack:pop()
    end
  elseif self.mode == "gen2" then
    if input:wasPressed("up") then self:moveList(-1)
    elseif input:wasPressed("down") then self:moveList(1)
    elseif input:wasPressed("left") or input:wasPressed("right") then
      self.region = self.region == "johto" and "kanto" or "johto"
      for i, loc in ipairs(self.locs) do
        if loc.region == self.region then self.sel = i break end
      end
      Sound.play(self.game.data, "Tink")
    end
  elseif self.mode == "grid" then
    if input:wasPressed("up") then self:moveGrid(0, -1)
    elseif input:wasPressed("down") then self:moveGrid(0, 1)
    elseif input:wasPressed("left") then self:moveGrid(-1, 0)
    elseif input:wasPressed("right") then self:moveGrid(1, 0)
    end
  else
    if input:wasPressed("up") then self:moveList(-1)
    elseif input:wasPressed("down") then self:moveList(1)
    end
  end
end

local function drawSquare(loc)
  if isRoute(loc) then
    love.graphics.setColor(0.62, 0.62, 0.62, 1)  -- routes lighter
  else
    love.graphics.setColor(0.25, 0.25, 0.25, 1)  -- towns darker
  end
  love.graphics.rectangle("fill", loc.x * 8 + 1, loc.y * 8 + 1, 6, 6)
end

function TownMap:drawGen2()
  local game = self.game
  local img = self.images and self.images[self.region]
  local town = (game.data.field or {}).townMap or {}
  local gear = (game.data.field or {}).pokegear or {}
  love.graphics.setColor(1, 1, 1, 1)
  if img then
    love.graphics.draw(img, 0, 0)
    require("src.render.PaletteFX").markTrueColor(0, 0, 160, 144)
  else
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end

  if self._playerIcon == nil then
    -- Prefer the pokegear Chris extract over the town-map one
    local path = gear.playerIcon or town.playerIcon
    if path then
      local ok, i = pcall(love.graphics.newImage, path)
      self._playerIcon = ok and i or false
    else
      self._playerIcon = false
    end
  end

  -- Landmark -> pixel helper for roam entries that only store landmark ids
  local function landmarkXY(lm)
    local e = town.landmarks and (town.landmarks[lm] or town.landmarks[tostring(lm)])
    if not e then return nil end
    -- Same OAM origin correction as gen2Locations
    return (e.x or 0) - 4, (e.y or 0) - 12
  end

  if self.nestSpecies then
    if self.blink % 16 < 10 then
      for _, loc in ipairs(self.nests) do
        if loc.region == self.region then
          if self.nestIcon then
            love.graphics.draw(self.nestIcon, loc.px - 4, loc.py - 4)
          else
            love.graphics.setColor(0.15, 0.15, 0.15, 1)
            love.graphics.rectangle("fill", loc.px - 3.5, loc.py - 3.5, 7, 7)
            love.graphics.setColor(1, 1, 1, 1)
          end
        end
      end
    end
    local def = game.data.pokemon[self.nestSpecies]
    local name = def and def.name or self.nestSpecies
    local any = false
    for _, loc in ipairs(self.nests) do
      if loc.region == self.region then any = true break end
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 8)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(any and (name .. "'s NEST") or (name .. " AREA UNKNOWN"), 8, 0)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- Roaming legendaries as mon icons in a green box (Gold/Silver pokegear).
  local roam = game.save.g2RoamReleased and game.save.g2Roam
  if type(roam) == "table" then
    for species, info in pairs(roam) do
      if info and info ~= false then
        local lm = type(info) == "table" and tonumber(info.landmark) or nil
        local px, py = landmarkXY(lm)
        if not px and type(info) == "table" then
          px, py = tonumber(info.px), tonumber(info.py)
        end
        if px and py then
          local region = (lm and lm >= 0x2F) and "kanto" or "johto"
          if region == self.region then
            local speciesId = (type(info) == "table" and (info.speciesId or info.species))
              or ({ RAIKOU = "SPECIES_243", ENTEI = "SPECIES_244", SUICUNE = "SPECIES_245" })[tostring(species):upper()]
              or tostring(species)
            if not tostring(speciesId):match("^SPECIES_") and tonumber(speciesId) then
              speciesId = string.format("SPECIES_%03d", tonumber(speciesId))
            end
            local monPath = "assets/generated/icons/" .. tostring(speciesId):lower() .. ".png"
            local icons = (game.data.icons or {}).bySpecies or {}
            local entry = icons[speciesId] or icons[tostring(speciesId):upper()]
            if type(entry) == "table" and entry.image then monPath = entry.image
            elseif type(entry) == "string" then monPath = entry end
            local poke = game.data.pokemon or {}
            local def = poke[speciesId]
            if type(def) == "table" and def.icon then monPath = def.icon end
            local ok, monImg = pcall(love.graphics.newImage, monPath)
            love.graphics.setColor(0.2, 0.9, 0.3, 1)
            love.graphics.rectangle("line", px - 9, py - 9, 18, 18)
            love.graphics.rectangle("line", px - 8, py - 8, 16, 16)
            if ok and monImg then
              love.graphics.setColor(1, 1, 1, 1)
              local iw, ih = monImg:getDimensions()
              local scale = math.min(16 / iw, 16 / ih)
              love.graphics.draw(monImg, px - 8, py - 8, 0, scale, scale)
            else
              love.graphics.setColor(1, 0.85, 0.1, 1)
              love.graphics.rectangle("fill", px - 6, py - 6, 12, 12)
            end
            love.graphics.setColor(1, 1, 1, 1)
          end
        end
      end
    end
  end

  -- Player icon: solid (does NOT blink). Gold/Silver keeps it steady while
  -- the red selection cursor is the blinking element.
  if self.playerLoc and self.playerLoc.region == self.region then
    if self._playerIcon then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(self._playerIcon, self.playerLoc.px - 8, self.playerLoc.py - 8)
    else
      love.graphics.setColor(0.9, 0.25, 0.2, 1)
      love.graphics.rectangle("fill", self.playerLoc.px - 3, self.playerLoc.py - 3, 6, 6)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- Selection cursor: RED BOX around the selected city (blinks).
  local selected = self.locs[self.sel]
  if selected and selected.region == self.region and self.blink % 16 < 10 then
    love.graphics.setColor(1, 0.15, 0.15, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", selected.px - 6, selected.py - 6, 12, 12)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 8)
  love.graphics.setColor(0, 0, 0, 1)
  if selected then Font.draw(self:bannerText(selected), 8, 0) end
  love.graphics.setColor(1, 1, 1, 1)
end

function TownMap:draw()
  if self.mode == "gen2" then return self:drawGen2() end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  local selected = self.locs[self.sel]
  if self.mode == "grid" and self.bg then
    -- the real Kanto map (LoadTownMap's RLE tilemap)
    for i, t in ipairs(self.bg.map) do
      local col, row = (i - 1) % 20, math.floor((i - 1) / 20)
      love.graphics.draw(self.bg.img, self.bg.quads[t], col * 8, row * 8)
    end
    if self.nestSpecies then
      -- AREA mode: blinking nests, the species name up top
      if self.blink % 16 < 10 then
        for _, loc in ipairs(self.nests) do
          local x, y = markerXY(loc)
          if self.nestIcon then
            love.graphics.draw(self.nestIcon, x, y)
          else
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("fill", x + 2, y + 2, 4, 4)
            love.graphics.setColor(1, 1, 1, 1)
          end
        end
      end
      love.graphics.rectangle("fill", 0, 0, 160, 8)
      love.graphics.setColor(0, 0, 0, 1)
      local def = self.game.data.pokemon[self.nestSpecies]
      local name = def and def.name or self.nestSpecies
      Font.draw(#self.nests > 0 and (name .. "'s NEST")
                or (name .. " AREA UNKNOWN"), 8, 0)
      love.graphics.setColor(1, 1, 1, 1)
      return
    end
    -- the player's current location blinks (slow phase).  Paint it with a
    -- palette-safe DARK shade (red 0), not red: this screen composites through
    -- the TOWNMAP SGB shade-remap shader (PaletteFX.shader), which keys ONLY on
    -- the red channel, and a red-0.75 dot lands in the c1 bucket = TOWNMAP
    -- {165,214,255}, the exact light-blue used for the water and the town-square
    -- fill, so the marker was drawn but recolored invisible (#152).  Red 0 -> c3
    -- {25,16,16} = a solid dark "you are here" dot, visible on land and water.
    if self.playerLoc and self.blink < 20 then
      local x, y = markerXY(self.playerLoc)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", x + 2, y + 2, 4, 4)
      love.graphics.setColor(1, 1, 1, 1)
    end
    -- blinking cursor on the selected location.  markerXY is the 8x8 cell's
    -- top-left; the cursor asset is a 16x16 hollow frame centered on its own
    -- (8,8), so draw it -4,-4 to enclose the cell (engine/menus/town_map.asm
    -- draws the box cursor CENTERED on the selected location).  Drawing it at
    -- the cell top-left put the square in the frame's top-left quadrant (#152).
    if selected and self.blink % 16 < 10 then
      local x, y = markerXY(selected)
      if self.bg.cursor then
        love.graphics.draw(self.bg.cursor, x - 4, y - 4)
      else
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, 7, 7)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
    -- the name strip on row 0 (DisplayTownMap: ClearScreenArea + name)
    love.graphics.rectangle("fill", 0, 0, 160, 8)
    love.graphics.setColor(0, 0, 0, 1)
    if selected then Font.draw(self:bannerText(selected), 8, 0) end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, 0, 20, 18)
  if self.mode == "grid" then
    -- stale assets (no background art): the old abstract squares
    for _, loc in ipairs(self.locs) do
      drawSquare(loc)
    end
    if self.playerLoc and self.blink < 20 then
      -- palette-safe dark, same red-channel shade-remap reason as the primary
      -- grid path above (#152); stale-asset builds hit this fallback square
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", self.playerLoc.x * 8 + 2,
                              self.playerLoc.y * 8 + 2, 4, 4)
    end
    if selected and self.blink % 16 < 10 then
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("line", selected.x * 8 + 0.5,
                              selected.y * 8 + 0.5, 7, 7)
    end
  else
    -- list fallback: show a window of names, cursor on the selection
    love.graphics.setColor(0, 0, 0, 1)
    local rows = 6
    local first = math.max(1, math.min(self.sel - 2, #self.locs - rows + 1))
    for i = 0, rows - 1 do
      local loc = self.locs[first + i]
      if loc then
        local y = 40 + i * 16
        if first + i == self.sel and self.blink % 16 < 10 then
          Font.drawCode(0xED, 8, y)  -- the "▶" cursor glyph
        end
        Font.draw(loc.name, 24, y)
        if loc == self.playerLoc and self.blink < 20 then
          -- blinking marker on the player's current town; force the palette-safe
          -- dark shade explicitly so the red-channel shade-remap keeps it
          -- visible regardless of Font.draw's leftover color (#152)
          love.graphics.setColor(0, 0, 0, 1)
          love.graphics.rectangle("fill", 24 + #loc.name * 8 + 6, y + 2, 4, 4)
        end
      end
    end
  end

  -- name banner across the top
  Font.drawBox(0, 0, 20, 3)
  love.graphics.setColor(0, 0, 0, 1)
  if selected then Font.draw(self:bannerText(selected), 8, 8) end
  love.graphics.setColor(1, 1, 1, 1)
end

return TownMap
