-- Driver: voxel-accuracy survey of one map.
--
-- Teleports to a map, walks a list of stand points, and screenshots each
-- one flat (2D ground truth) and at every voxel camera pitch, tilt-shift
-- forced off.  The shots are the evidence an agent (or a human) reads to
-- find sprites whose 3D shape does not match what the object is -- a bed
-- extruded into a wall, a flat stool, stairs drawn as a box.
--
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/voxel_survey.lua love .
--
-- knobs (env):
--   SURVEY_MAP     map id                          (default REDS_HOUSE_2F)
--   SURVEY_SPOTS   "x,y[,facing][@label]; ..."     (default centre of map)
--                  cell coordinates, facing up/down/left/right
--   SURVEY_LEVELS  comma list of voxel levels 1..3 (default "1,2,3";
--                  15/35/50 degrees)
--   SURVEY_TIME    day/night/dusk/dawn pin         (default day)
--   SHOT_DIR       output directory, must exist    (default "shots")
--
-- Levels are set through Pipelines.setLevel, not the player hotkey, so the
-- run never writes the player's options.lua and cannot leave tilt-shift on.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  -- Under POKEPORT_SPEED=N the driver is resumed N times per RENDERED
  -- frame, so anything that must span a draw (a capture flush, a camera
  -- tween) needs its yield count scaled by N or the screenshot lands on a
  -- later state than the one it names.
  local SPEED = math.max(1, math.floor(tonumber(os.getenv("POKEPORT_SPEED")) or 1))
  local function wait(frames) U.wait(frames * SPEED) end

  local DIR = os.getenv("SHOT_DIR") or "shots"
  local mapId = os.getenv("SURVEY_MAP") or "REDS_HOUSE_2F"

  local mapDef = game.data.maps and game.data.maps[mapId]
  assert(mapDef, "unknown map: " .. tostring(mapId))

  local spots = {}
  local spec = os.getenv("SURVEY_SPOTS")
  if spec and spec ~= "" then
    for entry in spec:gmatch("[^;]+") do
      local body, label = entry:match("^%s*(.-)%s*@%s*(%S+)%s*$")
      body = body or entry
      local x, y, facing = body:match("^%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%a*)")
      assert(x, "bad SURVEY_SPOTS entry: " .. entry)
      spots[#spots + 1] = {
        x = tonumber(x), y = tonumber(y),
        facing = (facing ~= "" and facing) or "up",
        label = label or (x .. "x" .. y),
      }
    end
  else
    spots[1] = { x = math.floor(mapDef.width * 2 / 2),
                 y = math.floor(mapDef.height * 2 / 2),
                 facing = "up", label = "centre" }
  end

  local levels = {}
  for n in (os.getenv("SURVEY_LEVELS") or "1,2,3"):gmatch("%d") do
    levels[#levels + 1] = tonumber(n)
  end

  local function shot(name)
    local path = ("%s/%s_%s.png"):format(DIR, mapId, name)
    game.capturePath = path
    wait(3) -- let the capture flush through a real draw
    print("[survey] shot " .. path)
  end

  -- the survey's whole point is reading the voxel geometry: the miniature
  -- blur would soften exactly the edges under inspection
  Pipelines.setLevel("tiltshift", 0)

  -- and reading it under a night palette is reading it through a blue filter
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if lib then
    local DayNight = lib.require("DayNight")
    DayNight.setting:sync(os.getenv("SURVEY_TIME") or "day")
    DayNight.update(0)
  end

  for i, s in ipairs(spots) do
    U.teleport(game, mapId, s.x, s.y, s.facing)
    wait(20)

    Pipelines.setLevel("voxel", 0)
    wait(25)
    if i == 1 then shot(s.label .. "_flat") end

    for _, level in ipairs(levels) do
      Pipelines.setLevel("voxel", level)
      wait(25) -- outlast the 0.25s camera tween
      shot(("%s_v%s"):format(s.label,
        Pipelines.levelLabel("voxel", level) or level))
    end
  end

  Pipelines.setLevel("voxel", 0)
  wait(5)
  print("[survey] done: " .. #spots .. " spots")
end
