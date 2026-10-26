package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Sound, V = require("src.core.Sound"), require("src.core.GameVersion")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/native_sound_script_waits.lua").run(".", "gen2", version)
  T.eq(#rows, 18, "every native script wait/control/clock case executes")
  local expected = {
    silent = 0,
    ["file-override"] = 0,
    ["special-player-three"] = version == "emerald" and 0 or 3,
    ["logic-only-cap"] = 181,
    ["normal-audio-cap"] = 180,
    ["double-audio-cap"] = 90,
    ["half-audio-cap"] = 181,
    ["latched-silence"] = 2,
    ["unlatched-silence"] = 4,
    ["replacement-keeps-waiting"] = 4,
    ["independent-player-keeps-waiting"] = 4,
    ["special-player-after-regular"] = version == "emerald" and 2 or 4,
    ["stop-native-keeps-file"] = 2,
    ["consecutive-logic-waits"] = 362,
    ["consecutive-audio-waits"] = 360,
  }
  for _, row in ipairs(rows) do
    local completed
    for _, frame in ipairs(row.frames) do
      if frame.advanced and completed == nil then
        completed = frame.tick
      end
      T.eq(type(frame.running), "boolean", "script-running state remains boolean")
      T.eq(type(frame.advanced), "boolean", "post-wait variable observation remains boolean")
    end
    T.eq(completed, expected[row.case] or 3, row.case .. " follows the measured native completion tick")
    T.eq(row.frames[#row.frames].running, false, row.case .. " returns from the actual runner")
    if row.case:match("consecutive") then
      local first
      for _, frame in ipairs(row.frames) do
        if frame.firstAdvanced then
          first = frame.tick
          break
        end
      end
      T.eq(
        first,
        row.case == "consecutive-logic-waits" and 181 or 180,
        "each consecutive wait starts its own native clocks"
      )
    elseif row.case == "latched-silence" then
      T.eq(row.frames[3].queries["164"], true, "latched completion survives an active replacement")
    end
  end
  for _, speed in ipairs({ 1, 2, 10 }) do
    local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
    local hardware = dofile("tests/native_sound/fixture.lua").install(".", false, f)
    hardware.clear()
    Sound.update()
    hardware.stereo(true)
    hardware.tick(0)
    assert(Sound.playId(f.data, 141, { pan = -64 }))
    local Game, Fixed = require("src.core.Game"), require("src.core.FixedStep")
    local stack = require("src.core.StateStack")
    stack:init()
    local game = setmetatable({
      data = f.data,
      save = f.game.save,
      stack = stack,
      input = require("src.core.Input"),
      speedOverride = speed,
    }, { __index = Game })
    game.input:init()
    local ow = setmetatable(
      { npcs = { {}, {} }, player = { facing = "up" } },
      { __index = require("src.world.OverworldController") }
    )
    local runner = require("src.script.ScriptRunner").new(game, ow)
    local hookEvents, ended = {}, {}
    f.e.api.hooks:wrap("script.command", function(next, ctx, name, args)
      hookEvents[#hookEvents + 1] = { edge = "before", name = name }
      local result = next(ctx, name, args)
      hookEvents[#hookEvents + 1] = { edge = "after", name = name }
      return result
    end)
    f.e.api.events:on("script.ended", function(event)
      ended[#ended + 1] =
        { completed = event.completed, value = require("src.script.Gen3Commands").getVar(game.save, 0x4001) }
    end)
    local script = assert(require("src.script.Gen3ScriptVM").compile({
      map_scripts = {
        source = "RomExtractorGen3",
        scripts = {
          OWNED_GAME_WAIT = {
            { "lockall" },
            { "waitse" },
            { "setvar", 0x4001, 1 },
            { "releaseall" },
            { "end" },
          },
        },
      },
    }, "OWNED_GAME_WAIT"))
    local steps, firstCompleted, resumed, freezeBroken = 0, nil, 0, false
    stack:push({
      update = function()
        hardware.tick(steps)
        if steps == 0 then
          runner:run(script, {
            source = {
              modId = "portable_held_item",
              mapId = "OWNED_WAIT_MAP",
              hook = "native_wait",
              strict = true,
            },
          })
        else
          runner:update()
        end
        if
          runner:isRunning()
          and (not ow.gen3Locked or not ow.npcs[1].gen3ScriptFrozen or not ow.npcs[2].gen3ScriptFrozen)
        then
          freezeBroken = true
        end
        if require("src.script.Gen3Commands").getVar(game.save, 0x4001) == 1 then
          firstCompleted = firstCompleted or steps
          resumed = resumed + 1
        end
        steps = steps + 1
      end,
    })
    Fixed:init(function(dt)
      game:step(dt)
    end)
    for _ = 1, 190 do
      game:update(1 / 60)
    end
    T.eq(
      firstCompleted,
      speed == 1 and 180 or 181,
      "actual Game:update services audio after logic independently of fast-forward"
    )
    T.eq(runner:isRunning(), false, "native script returns through the actual game/state clock")
    T.check(resumed > 1, "the owning state keeps updating after the native wait returns")
    T.check(game.save.playTime > 0, "the actual game logic advances its ordinary play clock")
    T.eq(freezeBroken, false, "native field objects stay frozen while the sound wait yields")
    T.eq(ow.gen3Locked, nil, "releaseall restores the field after the wait")
    T.eq(ow.npcs[1].gen3ScriptFrozen, nil, "releaseall unfreezes the first native field object")
    T.eq(ow.npcs[2].gen3ScriptFrozen, nil, "releaseall unfreezes every native field object")
    T.eq(runner.ctx.g3Locked, nil, "the completed script does not retain its input lock")
    T.eq(runner.ctx.source.strict, true, "native wait retains strict script ownership")
    T.eq(runner.ctx.source.mapId, "OWNED_WAIT_MAP", "native wait retains source map metadata")
    local waitBefore, waitAfter
    for index, event in ipairs(hookEvents) do
      if event.name == "g3_wait_se" then
        if event.edge == "before" then
          T.eq(waitBefore, nil, "waiting command enters its public hook exactly once")
          waitBefore = index
        else
          T.eq(waitAfter, nil, "waiting command exits its public hook exactly once")
          waitAfter = index
        end
      end
    end
    T.check(
      waitBefore and waitAfter and waitBefore < waitAfter,
      "the actual command hook resumes around the yielding native wait"
    )
    T.same(
      ended,
      { { completed = true, value = 1 } },
      "script-ended event follows the native wait and variable write once"
    )
    hardware.clear()
    Sound.update()
    hardware.close()
    f.close()
  end
end
T.finish("native world-script sound waits, audio clocks and actual Game:update")
