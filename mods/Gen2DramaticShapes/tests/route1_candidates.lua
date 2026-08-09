-- Driver: propose and photograph several battle arenas for ONE map.
--
-- data/battle_arenas.lua holds a single authored spot per area, chosen by
-- arena_pick's nearest-to-the-middle search and then looked at. This is the
-- other half of that job: when the shipped spot is up for review, it lays out
-- the ALTERNATIVES -- every arena on the map both mons can be seen in, spread
-- along the map so the shortlist is places rather than neighbours -- and
-- stages a real battle in each so they can be compared by eye.
--
--   SHOT_DIR=.scratchpad/route1_candidates CAND_MAP=ROUTE_1 CAND_N=5 \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/route1_candidates.lua love .
--
-- CAND_MAP is the map id (default ROUTE_1), CAND_N how many to photograph.
-- One `CAND` line per shot, ready to paste into the data file, plus a PNG
-- named for its corner and shape.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or ".scratchpad/route1_candidates"
  local MAP = os.getenv("CAND_MAP") or "ROUTE_1"
  local WANT = tonumber(os.getenv("CAND_N") or "") or 5
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

  U.teleport(game, MAP, 1, 1, "down")
  local map = game.overworld.map
  U.log(("%s is %dx%d cells"):format(MAP, map.widthCells, map.heightCells))

  -- ------- every arena the map can offer
  --
  -- BattleArena.search answers "the nearest one", which is the wrong question
  -- for a shortlist -- it returns one spot and hides the rest. So walk the
  -- same grid ourselves and keep them all, tagged with whether the pair would
  -- actually be SEEN there (Arena.clearance), because an obstructed spot is
  -- not a candidate no matter how good the ground looks.
  --
  -- The map's outermost cells are its CONNECTION BORDER -- the strip the
  -- neighbouring map is drawn into, walkable so the player can step across.
  -- Ground there passes every test and is still the wrong answer: a fight
  -- staged on it happens at the edge of the world with the border ring's tree
  -- wall at the mons' backs, and every spot in the strip looks like every
  -- other one. CAND_MARGIN keeps the shortlist on the route proper.
  local MARGIN = tonumber(os.getenv("CAND_MARGIN") or "") or 2
  local cands = {}
  for _, shape in ipairs(Arena.SHAPES) do
    for y = MARGIN, map.heightCells - shape.h - MARGIN do
      for x = MARGIN, map.widthCells - shape.w - MARGIN do
        local fits = true
        for cy = y, y + shape.h - 1 do
          for cx = x, x + shape.w - 1 do
            if not Arena.openCell(map, cx, cy, false) then fits = false break end
          end
          if not fits then break end
        end
        if fits then
          local a = Arena.at(x, y, shape.id)
          if a and Arena.clearance(map, a) then
            cands[#cands + 1] = { x = x, y = y, shape = shape.id,
                                  mx = x + (shape.w - 1) / 2,
                                  my = y + (shape.h - 1) / 2 }
          end
        end
      end
    end
  end
  U.log(("%d clear arenas on %s"):format(#cands, MAP))
  if #cands == 0 then U.log("done -- nothing to propose") return end

  for _, c in ipairs(cands) do
    U.log(("  fit  %d,%d %s"):format(c.x, c.y, c.shape))
  end

  -- CAND_AT=x,y,shape;x,y,shape;... photographs an explicit shortlist instead
  -- of the spread one. The spread is a first pass over ground the clearance
  -- test approved, and that test measures terrain height along the sightline
  -- only -- it has no opinion on a hedge sitting in the apron row between the
  -- camera and the near mon, which is the failure that keeps turning up. So
  -- the loop is: spread, look, then re-shoot the survivors and the
  -- replacements by hand.
  local explicit = os.getenv("CAND_AT")
  if explicit and explicit ~= "" then
    local list = {}
    for spot in explicit:gmatch("[^;]+") do
      local x, y, s = spot:match("^%s*(%-?%d+)%s*,%s*(%-?%d+)%s*,%s*(%a+)%s*$")
      if x then
        list[#list + 1] = { x = tonumber(x), y = tonumber(y), shape = s }
      else
        U.log("BAD CAND_AT entry: " .. spot)
      end
    end
    cands = list
    WANT = #list
    U.log(("%d spots given explicitly"):format(#list))
  end

  local function shapeOf(id)
    for _, s in ipairs(Arena.SHAPES) do if s.id == id then return s end end
  end
  for _, c in ipairs(cands) do
    local s = shapeOf(c.shape)
    c.mx = c.x + ((s and s.w or 1) - 1) / 2
    c.my = c.y + ((s and s.h or 1) - 1) / 2
  end

  -- ------- thin them down to a shortlist that is actually a CHOICE
  --
  -- Adjacent corners are the same patch of ground shifted a cell, so a naive
  -- top-N is five photographs of one place, and pure farthest-point selection
  -- goes straight to the extremes -- which on a route means the ends, where
  -- the ground is emptiest and the shots are least distinguishable.
  --
  -- So: spread along the route's LONG AXIS, one pick per band, and within a
  -- band take the spot nearest the middle of the road. The road is measured
  -- rather than assumed -- the median cross-axis position of everywhere a
  -- fight fits IS the lane, on a map whose walkable ground is mostly lane.
  local horizontal = map.widthCells > map.heightCells
  local function along(c) return horizontal and c.mx or c.my end
  local function across(c) return horizontal and c.my or c.mx end

  local xs = {}
  for _, c in ipairs(cands) do xs[#xs + 1] = across(c) end
  table.sort(xs)
  local road = xs[math.ceil(#xs / 2)]
  U.log(("road runs %s, centre of the lane is %s = %.1f")
        :format(horizontal and "east-west" or "north-south",
                horizontal and "y" or "x", road))

  local lo, hi = math.huge, -math.huge
  for _, c in ipairs(cands) do
    lo, hi = math.min(lo, along(c)), math.max(hi, along(c))
  end

  -- an explicit shortlist is already the answer; the spread below would only
  -- thin it, and its overlap rule would silently drop two spots deliberately
  -- asked for a cell apart
  local picked, taken = {}, {}
  for band = 1, (explicit and explicit ~= "") and 0 or WANT do
    -- band centres, not band edges: the first and last picks sit inside the
    -- route rather than on its two connection mouths
    local target = lo + (hi - lo) * (band - 0.5) / WANT
    local best, bestScore
    for _, c in ipairs(cands) do
      if not taken[c] then
        local da = along(c) - target
        local dr = across(c) - road
        -- distance from the band centre, plus a heavier penalty for being off
        -- the lane; wide arenas are worth a detour, being the shot this mode
        -- is framed for
        local score = da * da + 4 * dr * dr - (c.shape == "wide" and 100 or 0)
        if not bestScore or score < bestScore then best, bestScore = c, score end
      end
    end
    if best then
      picked[#picked + 1] = best
      -- everything overlapping the pick is off the table, so two bands whose
      -- best spots touch cannot return the same patch of ground twice
      for _, c in ipairs(cands) do
        if math.abs(along(c) - along(best)) < 3
           and math.abs(across(c) - across(best)) < 3 then
          taken[c] = true
        end
      end
    end
  end

  if #picked == 0 then picked = cands end

  -- north to south (or west to east), so the filenames read along the route
  table.sort(picked, function(a, b)
    if along(a) ~= along(b) then return along(a) < along(b) end
    return across(a) < across(b)
  end)

  for i, c in ipairs(picked) do
    U.log(("CAND %d  [%q] = { x = %d, y = %d, shape = %q },")
          :format(i, MAP, c.x, c.y, c.shape))
    -- forced through the authored-entry seam, so what gets staged is exactly
    -- this spot rather than whatever the search would pick from the player's
    -- cell
    Arena.setOverride(MAP, { x = c.x, y = c.y, shape = c.shape })
    local staged = Arena.find(map, 0, 0, false)
    if not staged then
      U.log(("SKIP %d -- override did not stage"):format(i))
    else
      game.overworld.player.cellX = staged.playerCell[1]
      game.overworld.player.cellY = staged.playerCell[2]
      U.wait(90)                              -- let the meshes land
      local battle = BattleState.newWild(game, "NIDORINO", 20)
      battle.onFinish = function() end
      game.overworld:pushBattle(battle)
      U.wait(70)
      for _ = 1, 14 do U.tap(game, "a"); U.wait(8) end
      local got = Battles.arena()
      U.log(("SHOT %d  staged at %s,%s"):format(i, tostring(got and got.x),
                                                tostring(got and got.y)))
      U.shot(game, ("%s/%d_%s_x%d_y%d_%s.png")
                   :format(DIR, i, MAP:lower(), c.x, c.y, c.shape))
      while game.stack:top() and game.stack:top() ~= game.overworld do
        game.stack:pop()
      end
      U.wait(6)
    end
  end
  Arena.setOverride(MAP, nil)

  U.log("done -- " .. DIR)
end
