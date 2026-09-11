-- Checking an authoring before it leaves the building.
--
-- THE FAILURES THIS CATCHES ARE ALL SILENT ONES.  A pin naming a class the
-- mod has never heard of does not resolve and falls through -- quietly, by
-- design, because a mod's class list is its own vocabulary and a pin
-- written against another mod's is not an error.  A pin on a tile id the
-- tileset does not have resolves against nothing.  A conditional rule whose
-- `above` key does not match its `when_above` side is dropped by the
-- parser without a word.  None of those raise; all of them look exactly
-- like "I set it and nothing happened".
--
-- So: errors are things that would make the export wrong, warnings are
-- things that would make it inert, and neither is fatal to the editor.

local Cache = require("core.Cache")

local Validate = {}

local function add(list, kind, tsId, msg, tile)
  list[#list + 1] = { kind = kind, tileset = tsId, tile = tile, msg = msg }
end

function Validate.run(doc, cacheSet, bridge)
  local out = { errors = {}, warnings = {}, info = {} }
  local vocab = (bridge and bridge.classInfo) or {}
  local folds = {}
  for _, info in pairs(vocab) do if info.art then folds[info.art] = true end end

  for tsId, e in pairs(doc.tilesets or {}) do
    -- which cache holds this tileset, and how big is its tile-id space
    local ts, geom
    for _, c in ipairs(cacheSet or {}) do
      if c.tilesets[tsId] then
        ts = c.tilesets[tsId]
        geom = Cache.tileGeometry(ts)
        break
      end
    end
    if not ts then
      add(out.warnings, "tileset", tsId,
          "no loaded cache has this tileset -- its pins are exported unchecked")
    end
    local count = geom and geom.count or nil

    local function checkTile(tile, what)
      if type(tile) ~= "number" or math.floor(tile) ~= tile or tile < 0 then
        add(out.errors, "tile", tsId, what .. ": tile id " .. tostring(tile)
            .. " is not a non-negative integer", tile)
        return false
      end
      if count and tile >= count then
        add(out.errors, "tile", tsId, what .. ": tile " .. tile
            .. " is outside this tileset's " .. count .. "-tile id space", tile)
        return false
      end
      return true
    end

    for tile, class in pairs(e.pins or {}) do
      checkTile(tile, "pin")
      if type(class) ~= "string" then
        add(out.errors, "class", tsId, "pin on tile " .. tostring(tile)
            .. " is not a class name", tile)
      elseif next(vocab) and not vocab[class] then
        add(out.warnings, "class", tsId, "tile " .. tostring(tile)
            .. " is pinned to '" .. class
            .. "', which this install's TileShape does not resolve -- it will"
            .. " fall through to the derived default", tile)
      end
    end

    for tile, fold in pairs(e.folds or {}) do
      checkTile(tile, "fold")
      if next(folds) and not folds[fold] then
        add(out.warnings, "fold", tsId, "tile " .. tostring(tile)
            .. " folds as '" .. tostring(fold)
            .. "', which no class in this install uses", tile)
      end
    end

    for class, h in pairs(e.heights or {}) do
      if type(h) ~= "number" then
        add(out.errors, "height", tsId,
            "height for '" .. tostring(class) .. "' is not a number")
      elseif next(vocab) and not vocab[class] then
        add(out.warnings, "height", tsId,
            "height set for '" .. tostring(class)
            .. "', a class this install does not have -- the override is dropped")
      elseif h < -16 or h > 128 then
        add(out.warnings, "height", tsId,
            "'" .. class .. "' at " .. h
            .. " world pixels is outside anything the cartridge draws")
      end
    end

    -- the one invariant the profile states about itself: a can's stated
    -- body height and its class height are the same number, or things
    -- riding it float
    if e.heights and e.heights.can and e.can_height
       and e.heights.can ~= e.can_height then
      add(out.errors, "can", tsId,
          "can_height (" .. tostring(e.can_height) .. ") and heights.can ("
          .. tostring(e.heights.can) .. ") disagree")
    end

    for tile, list in pairs(e.cond or {}) do
      checkTile(tile, "conditional")
      for i, rule in ipairs(list) do
        local where = "conditional " .. i .. " on tile " .. tostring(tile)
        if next(vocab) and not vocab[rule.class] then
          add(out.warnings, "class", tsId,
              where .. " names class '" .. tostring(rule.class)
              .. "', which does not resolve -- the rule is dropped", tile)
        end
        if rule.side == "cell" then
          if type(rule.walkable) ~= "boolean" then
            add(out.errors, "conditional", tsId,
                where .. ": a cell rule needs walkable = true or false", tile)
          end
        else
          if type(rule.ids) ~= "table" or #rule.ids == 0 then
            add(out.errors, "conditional", tsId,
                where .. ": no neighbour tile ids", tile)
          else
            for _, t in ipairs(rule.ids) do checkTile(t, where) end
          end
          if rule.rows and (type(rule.rows) ~= "number" or rule.rows < 1) then
            add(out.errors, "conditional", tsId,
                where .. ": rows must be 1 or more", tile)
          end
        end
      end
    end

    for tile, s in pairs(e.sculpt or {}) do
      checkTile(tile, "sculpt")
      local res = s.res
      if type(res) ~= "number" or res < 1 or res > 8 or math.floor(res) ~= res then
        add(out.errors, "sculpt", tsId,
            "tile " .. tostring(tile) .. ": res must be an integer 1..8", tile)
      elseif type(s.h) ~= "table" or #s.h ~= res * res then
        add(out.errors, "sculpt", tsId,
            "tile " .. tostring(tile) .. ": expected " .. (res * res)
            .. " heights, got " .. tostring(s.h and #s.h), tile)
      else
        for i = 1, res * res do
          if type(s.h[i]) ~= "number" then
            add(out.errors, "sculpt", tsId,
                "tile " .. tostring(tile) .. ": height " .. i .. " is not a number", tile)
            break
          end
        end
      end
      if res == 8 then
        add(out.info, "sculpt", tsId,
            "tile " .. tostring(tile)
            .. " sculpts at 1px: up to 64 boxes for that tile, everywhere it appears", tile)
      end
    end

    -- SIDE-FACE ART.  A band pointing at a tile that does not exist draws
    -- nothing and looks exactly like the void it was painted over, so it is
    -- an error rather than a note.  That it is sidecar-only is a note, once
    -- per tileset, because it is a property of the format and not a mistake.
    local saidSidecar = false
    for tile, b in pairs(e.bands or {}) do
      checkTile(tile, "band art")
      for band, src in pairs(b) do
        local where = "tile " .. tostring(tile) .. " band " .. tostring(band)
        if type(band) ~= "number" or math.floor(band) ~= band or band < -1 then
          add(out.errors, "band art", tsId,
              where .. ": band must be -1 (all) or 0 and up", tile)
        end
        if type(src) ~= "number" then
          add(out.errors, "band art", tsId,
              where .. ": source must be a tile id", tile)
        else
          checkTile(src, "band art source")
        end
      end
      if not saidSidecar then
        saidSidecar = true
        add(out.info, "band art", tsId,
            "side-face art ships in the versioned sidecar only: the shipped"
            .. " mod reads pins, folds, heights and place edits, and does not"
            .. " read this", tile)
      end
    end

    -- GENERIC KEYS.  `extra` replaces a profile key wholesale, which is the
    -- only honest way to edit a key nothing here understands -- and it means
    -- a mistake here is a mistake in the profile rather than in a side table.
    -- So the tile-shaped ones get the same id check everything else gets, and
    -- the rest is reported as a fact rather than judged.
    for key, value in pairs(e.extra or {}) do
      if type(value) == "table" then
        local n = 0
        for k, v in pairs(value) do
          n = n + 1
          if type(k) == "number" and type(v) == "number" then
            -- a tile -> tile map, or an array of tile ids
            checkTile(v, key)
            if k >= 1 and math.floor(k) == k and value[1] ~= nil then
              -- an array: the KEY is an index, not a tile
            else
              checkTile(k, key)
            end
          end
        end
        add(out.info, "profile key", tsId,
            key .. ": replaced wholesale by this document, " .. n
            .. " entries -- it overrides the mod's own value for this tileset")
      else
        add(out.info, "profile key", tsId,
            key .. " = " .. tostring(value) .. " (set by this document)")
      end
    end

    for gi, g in ipairs(e.groups or {}) do
      local n = (g.w or 0) * (g.h or 0)
      if type(g.tiles) ~= "table" or #g.tiles ~= n or n == 0 then
        add(out.errors, "group", tsId,
            "group " .. gi .. " (" .. tostring(g.name) .. "): "
            .. tostring(g.w) .. "x" .. tostring(g.h) .. " needs " .. n
            .. " tile ids, has " .. tostring(g.tiles and #g.tiles))
      else
        for _, t in ipairs(g.tiles) do checkTile(t, "group " .. gi) end
      end
      if next(vocab) and g.class and not vocab[g.class] then
        add(out.warnings, "class", tsId,
            "group " .. gi .. " names class '" .. tostring(g.class) .. "'")
      end
      if g.cap and (type(g.cap) ~= "number" or g.cap < 1) then
        add(out.errors, "group", tsId,
            "group " .. gi .. ": the repetition cap must be 1 or more")
      end
      if not g.cap then
        add(out.warnings, "group", tsId,
            "group " .. gi .. " has no repetition cap -- a repeating canopy"
            .. " will fold into one monolith rather than rows of trees")
      end
    end
  end

  -- ------------------------------------------------------------ map edits
  --
  -- A place edit names a square of a named map.  Both halves can go stale --
  -- a map id that is not in this cartridge, a class the host cannot resolve
  -- -- and both fail silently at runtime: the patch is skipped, or the class
  -- falls through, and the square draws as if nothing was ever said about it.
  local knownMaps = nil
  for _, c in ipairs(cacheSet or {}) do
    -- Only ask a cache that can answer.  Loading maps.lua is nine megabytes
    -- on Emerald and there is no reason to pay it to validate a document
    -- with no place edits in it -- and a stub cache (the self test's) has no
    -- root to load from at all.
    local maps = (c._maps ~= false) and c._maps or nil
    if not maps and c.root and next(doc.maps or {}) then
      maps = Cache.maps(c)
    end
    if maps then
      knownMaps = knownMaps or {}
      for id in pairs(maps) do knownMaps[id] = true end
    end
  end

  for mapId, m in pairs(doc.maps or {}) do
    if knownMaps and not knownMaps[mapId] then
      add(out.warnings, "map", mapId,
          "no map with this id is in the loaded cache -- the pack will patch"
          .. " nothing for it")
    end
    local n = 0
    for k, o in pairs(m.tiles or {}) do
      n = n + 1
      local tx, ty = tostring(k):match("^(-?%d+),(-?%d+)$")
      if not tx then
        add(out.errors, "map", mapId, "'" .. tostring(k)
            .. "' is not a tile coordinate")
      end
      if o.art and next(vocab) and not vocab[o.art] then
        add(out.warnings, "class", mapId, "square " .. tostring(k)
            .. " names class '" .. tostring(o.art)
            .. "', which this install does not resolve")
      end
      if o.h ~= nil and type(o.h) ~= "number" then
        add(out.errors, "map", mapId, "square " .. tostring(k)
            .. ": height is not a number")
      end
      if o.sub then
        local res = o.sub.res
        if type(res) ~= "number" or res < 1 or res > 8 then
          add(out.errors, "map", mapId, "square " .. tostring(k)
              .. ": sub res must be 1..8")
        elseif type(o.sub.h) ~= "table" or #o.sub.h ~= res * res then
          add(out.errors, "map", mapId, "square " .. tostring(k)
              .. ": expected " .. (res * res) .. " heights")
        end
      end
    end
    if n > 2000 then
      add(out.info, "map", mapId, n .. " squares named individually -- that is"
          .. " a lot of coordinate overrides for one map")
    end
  end

  out.ok = #out.errors == 0
  return out
end

function Validate.summary(result)
  return ("%d error%s, %d warning%s"):format(
    #result.errors, #result.errors == 1 and "" or "s",
    #result.warnings, #result.warnings == 1 and "" or "s")
end

return Validate
