-- Driver: Rocket Hideout elevator gates (#199).
--
-- Gen1 stamps a closed barred gate over the elevator doorway on every map
-- load, opening it only once the guarding Rockets are beaten:
--   scripts/RocketHideoutB1F.asm  RocketHideoutB1FDoorCallbackScript
--     closed block $54 at (12,8), open block $0e; opens once
--     EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4 is set (the guard by the lift;
--     EVENT_ENTERED_ROCKET_HIDEOUT is never SetEvent -- the SFX bug noted
--     in the source -- so it is not part of the effective open condition).
--   scripts/RocketHideoutB4F.asm  RocketHideoutB4FDoorCallbackScript
--     closed block $2d at (12,5), open block $0e; opens once BOTH
--     EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0 and _1 are set.
-- B2F/B3F call no door callback (spinner-tile floors), so they get no gate.
--
-- The recomp shipped no stamping, so the .blk's open floor block ($0e/14)
-- showed through -- the reporter's "gate is open" screenshots. Pre-fix the
-- closed-gate asserts read 14 and fail; post-fix they read the barred block.
--
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/rocket_hideout_gate_bug199_test.lua \
--   POKEPORT_IDENTITY=bug199 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local OW = require("src.world.OverworldController")

  local failures = {}
  local function check(cond, msg)
    if cond then U.log("ok:", msg) else
      table.insert(failures, msg); U.log("FAIL:", msg)
    end
    return cond
  end

  -- swap map, wiping event flags to a known slate, then settle until the
  -- map has loaded and the player is idle so the door callback has stamped
  local function load(mapId, x, y, flags)
    while game.stack:top() do game.stack:pop() end
    game.save.flags = {}
    for k, v in pairs(flags or {}) do game.save.flags[k] = v end
    game.stack:push(OW, mapId, x, y, "down")
    for _ = 1, 240 do
      local ow = game.overworld
      if ow and ow.map and ow.map.id == mapId and not ow.transitioning
         and not (ow.player and ow.player.moving) then
        break
      end
      U.wait(1)
    end
    U.wait(3)
    return game.overworld
  end

  local OPEN = 14          -- $0e floor block (doorway when unlocked)
  local CLOSED_B1F = 84    -- $54 barred gate (bars in the north cell-row)
  local CLOSED_B4F = 45    -- $2d barred gate (bars in the south cell-row)

  -- B1F: barred until the lift guard (trainer 4) is beaten
  local ow = load("ROCKET_HIDEOUT_B1F", 24, 14)
  U.shot(game, DIR .. "/b1f_gate_closed.png")
  check(ow.map:blockAt(12, 8) == CLOSED_B1F,
        "B1F doorway (12,8) barred, got " .. tostring(ow.map:blockAt(12, 8)))
  check(ow.map:blockAt(12, 9) == 44,
        "B1F warp carpet (12,9) untouched, got " .. tostring(ow.map:blockAt(12, 9)))

  -- B1F: opens once the guard is beaten
  ow = load("ROCKET_HIDEOUT_B1F", 24, 14,
            { EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4 = true })
  U.shot(game, DIR .. "/b1f_gate_open.png")
  check(ow.map:blockAt(12, 8) == OPEN,
        "B1F doorway opens after guard, got " .. tostring(ow.map:blockAt(12, 8)))

  -- B4F: barred until BOTH guards are beaten
  ow = load("ROCKET_HIDEOUT_B4F", 24, 8)
  U.shot(game, DIR .. "/b4f_gate_closed.png")
  check(ow.map:blockAt(12, 5) == CLOSED_B4F,
        "B4F doorway (12,5) barred, got " .. tostring(ow.map:blockAt(12, 5)))

  -- B4F: one guard is not enough
  ow = load("ROCKET_HIDEOUT_B4F", 24, 8,
            { EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0 = true })
  check(ow.map:blockAt(12, 5) == CLOSED_B4F,
        "B4F stays barred with only one guard, got " .. tostring(ow.map:blockAt(12, 5)))

  -- B4F: opens once both guards are beaten
  ow = load("ROCKET_HIDEOUT_B4F", 24, 8,
            { EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0 = true,
              EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_1 = true })
  U.shot(game, DIR .. "/b4f_gate_open.png")
  check(ow.map:blockAt(12, 5) == OPEN,
        "B4F doorway opens after both guards, got " .. tostring(ow.map:blockAt(12, 5)))

  -- B2F has no dynamic gate in pokered (spinner floor); it must still load
  ow = load("ROCKET_HIDEOUT_B2F", 24, 14)
  check(ow and ow.map and ow.map.id == "ROCKET_HIDEOUT_B2F",
        "B2F loads with no gate callback")

  -- regression: the shared Silph Co card-key path must still stamp
  ow = load("SILPH_CO_2F", 4, 4)
  check(ow.map:blockAt(2, 2) == 84,
        "SILPH_CO_2F door1 (2,2) still barred, got " .. tostring(ow.map:blockAt(2, 2)))
  ow = load("SILPH_CO_2F", 4, 4, { EVENT_SILPH_CO_2_UNLOCKED_DOOR1 = true })
  check(ow.map:blockAt(2, 2) == 14,
        "SILPH_CO_2F door1 opens with its event, got " .. tostring(ow.map:blockAt(2, 2)))

  if #failures > 0 then
    error(#failures .. " check(s) failed: " .. table.concat(failures, " | "))
  end
  U.log("all Rocket Hideout gate checks passed")
end
