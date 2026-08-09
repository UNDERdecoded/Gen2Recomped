-- Driver: choose and photograph one battle arena per map.
--
-- data/battle_arenas.lua holds one authored spot per area. This is what
-- authors it: for every map a battle can happen on, it asks BattleArena for
-- the arena nearest the map's middle that its clearance test says both mons
-- can be SEEN in, stages a real battle there, and takes one screenshot.
--
-- Two outputs. A `PICK` line per map, ready to paste into the data file, and
-- a PNG per map to look at -- because the clearance test answers a geometry
-- question ("nothing tall on the sightline") and the actual question is
-- whether the picture reads. Grass and flowers around a mon's feet are fine
-- and wanted; a body cut in half by a wall is not, and only an eye catches
-- the difference.
--
--   SHOT_DIR=.scratchpad/arenas ARENA_FROM=1 ARENA_COUNT=20 \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/arena_pick.lua love .
--
-- ARENA_FROM / ARENA_COUNT slice the map list so several runs can share the
-- work; ARENA_MAPS=ID,ID,... does an explicit set instead. ARENA_COUNT=0
-- lists the maps and stops. ARENA_SURF=1 stages the fight out on the water,
-- centred in the map's biggest body of it, which is what the surf routes
-- want. SHOT_DIR must already exist -- the capture writes with io.open,
-- which does not create directories.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or ".scratchpad/arenas"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 45) }
  game.save.player.name = "RED"

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    U.log("DRAMATIC_SHAPE is not loaded -- enable it and run again")
    return
  end
  local Arena = lib.require("BattleArena")
  local Battles = lib.require("OverworldBattle")

  -- ------- staging out on the water
  --
  -- A surf route's land is a rim of beach round the edge of the map, so the
  -- ordinary search always picks the rim and the fight happens on sand at
  -- the corner of a sea. ARENA_SURF=1 says stage this map afloat: water
  -- counts as ground, and the search starts from the middle of the map's
  -- BIGGEST body of water rather than the middle of the map, so the arena
  -- lands out in the open sea instead of against the first shoreline it
  -- finds.
  --
  -- Biggest body, not all water at once: a map with a lake and an ocean has
  -- a centroid between them that is on neither, and the arena would be
  -- pinned to whichever shore that landed nearest.
  local function waterCentre(map)
    local w, h = map.widthCells, map.heightCells
    local seen, best = {}, nil
    for y0 = 0, h - 1 do
      for x0 = 0, w - 1 do
        if not seen[y0 * w + x0] and map:isWaterCell(x0, y0) then
          -- one connected body, flooded from this cell
          local stack, n, sx, sy = { { x0, y0 } }, 0, 0, 0
          seen[y0 * w + x0] = true
          while #stack > 0 do
            local cell = table.remove(stack)
            local cx, cy = cell[1], cell[2]
            n, sx, sy = n + 1, sx + cx, sy + cy
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
              local nx, ny = cx + d[1], cy + d[2]
              local key = ny * w + nx
              if nx >= 0 and ny >= 0 and nx < w and ny < h and not seen[key]
                 and map:isWaterCell(nx, ny) then
                seen[key] = true
                stack[#stack + 1] = { nx, ny }
              end
            end
          end
          if not best or n > best.n then
            best = { n = n, x = sx / n, y = sy / n }
          end
        end
      end
    end
    return best
  end

  -- Which maps a battle can actually happen on: anything with a wild
  -- encounter table or an object that fights. Everything else -- a shop
  -- floor, a stairwell, a bedroom -- would be authoring a spot for a fight
  -- that never happens there.
  --
  -- The encounter tables are their OWN registry keyed by map id, not a field
  -- on the map record. An earlier cut of this read `def.encounters`, which is
  -- always nil -- so the list silently narrowed to trainer maps only and
  -- every route, cave and Safari zone fell out of it. Nothing failed; the
  -- tool just quietly stopped offering to author the places wild battles
  -- actually happen.
  local function fights(id, def)
    local enc = game.data.encounters and game.data.encounters[id]
    if enc then
      for _, kind in ipairs({ "grass", "water" }) do
        local t = enc[kind]
        if t and (t.rate or 0) > 0 and t.slots and t.slots[1] then
          return true
        end
      end
    end
    for _, obj in ipairs(def.objects or {}) do
      if obj.trainer or obj.trainerClass or obj.species then return true end
    end
    return false
  end

  local ids = {}
  local explicit = os.getenv("ARENA_MAPS")
  if explicit and explicit ~= "" then
    for id in explicit:gmatch("[^,%s]+") do ids[#ids + 1] = id end
  else
    for id, def in pairs(game.data.maps) do
      if type(id) == "string" and type(def) == "table" and fights(id, def) then
        ids[#ids + 1] = id
      end
    end
    table.sort(ids)
  end

  local from = tonumber(os.getenv("ARENA_FROM") or "") or 1
  local count = tonumber(os.getenv("ARENA_COUNT") or "") or #ids
  U.log(("%d battle maps; doing %d..%d"):format(#ids, from,
                                                math.min(#ids, from + count - 1)))
  -- ARENA_COUNT=0 lists what WOULD be done and stops. The set this filter
  -- picks is the authoritative answer to "which areas need an arena", so it
  -- has to be readable without sitting through a capture -- that is how the
  -- bug above went unnoticed.
  if count <= 0 then
    for i = 1, #ids, 8 do
      U.log("LIST  " .. table.concat(ids, ",", i, math.min(#ids, i + 7)))
    end
    U.log("done -- listing only")
    return
  end

  for i = from, math.min(#ids, from + count - 1) do
    local id = ids[i]
    local def = game.data.maps[id]
    local cx = math.floor(def.width)          -- the middle, in cells
    local cy = math.floor(def.height)

    -- the pick is made against the MAP, before anything is staged, so a map
    -- with no clear arena at all is reported rather than quietly given a bad
    -- one
    local ok, err = pcall(function()
      U.teleport(game, id, 1, 1, "down")
    end)
    if not ok then
      U.log(("SKIP %s -- could not enter (%s)"):format(id, tostring(err)))
    else
      local map = game.overworld.map
      local clear, any
      -- ARENA_AT=x,y[,shape] photographs one specific spot instead of the
      -- picked one, which is how a map the automatic choice got wrong is
      -- re-aimed by hand and checked in the same loop.
      -- ARENA_MAP=OTHER_ID stages on another floor of the same cave or
      -- building, for a map that has nowhere of its own to put a fight
      local at = os.getenv("ARENA_AT")
      local onMap = os.getenv("ARENA_MAP")
      if at and at ~= "" and (explicit and explicit ~= "") then
        local ax, ay, ashape = at:match("^(%-?%d+)%s*,%s*(%-?%d+)%s*,?%s*(%a*)$")
        if ax then
          -- forced through the authored-entry seam, so what gets staged is
          -- exactly what was asked for rather than whatever the search
          -- would have picked from the player's cell
          local onCam = os.getenv("ARENA_CAM")
          Arena.setOverride(id, {
            x = tonumber(ax), y = tonumber(ay),
            shape = (ashape ~= "" and ashape) or "wide",
            map = (onMap ~= "" and onMap) or nil,
            cam = (onCam and onCam ~= "" and onCam) or nil,
          })
          any = Arena.find(map, 0, 0, false)
          clear = any and Arena.clearance(any.map or map, any) or false
        end
      end
      local surf = os.getenv("ARENA_SURF")
      surf = surf ~= nil and surf ~= "" and surf ~= "0"
      if not any then
        local ox, oy = cx, cy
        if surf then
          local sea = waterCentre(map)
          if sea then
            ox, oy = sea.x, sea.y
            U.log(("SEA    %s: biggest body is %d cells, centre %.1f,%.1f")
                  :format(id, sea.n, sea.x, sea.y))
          else
            U.log("SEA    " .. id .. ": no water on this map")
          end
        end
        clear = Arena.search(map, ox, oy, surf, true)
        any = clear or Arena.search(map, ox, oy, surf)
      end
      if not any then
        U.log(("NONE %s -- no arena of either shape"):format(id))
      else
        local onOther = any.map and any.map.id ~= id and any.map.id or nil
        U.log(("PICK   [%q] = { %sx = %d, y = %d, shape = %q%s },%s")
              :format(id, onOther and ("map = %q, "):format(onOther) or "",
                      any.x, any.y, any.shape,
                      any.cam and (", cam = %q"):format(any.cam) or "",
                      clear and "" or "   -- OBSTRUCTED: no clear spot"))
        -- stand the player on the arena so the staged battle uses it, then
        -- fight something there and photograph the result
        game.overworld.player.cellX = any.playerCell[1]
        game.overworld.player.cellY = any.playerCell[2]
        U.wait(90)                            -- let the meshes land
        local battle = BattleState.newWild(game, "NIDORINO", 20)
        battle.onFinish = function() end
        game.overworld:pushBattle(battle)
        U.wait(70)
        for _ = 1, 14 do U.tap(game, "a"); U.wait(8) end
        local got = Battles.arena()
        U.log(("SHOT   %s at %s,%s"):format(id,
              tostring(got and got.x), tostring(got and got.y)))
        U.shot(game, ("%s/%s.png"):format(DIR, id:lower()))
        while game.stack:top() and game.stack:top() ~= game.overworld do
          game.stack:pop()
        end
        U.wait(6)
      end
    end
  end

  U.log("done -- " .. DIR)
end
