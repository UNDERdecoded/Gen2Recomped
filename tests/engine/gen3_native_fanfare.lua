package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, Music = require("src.core.GameVersion"), require("src.core.Music")
local before = V.get()
local expected = {
  ordinary = 4,
  fast = 4,
  ["four-times"] = 4,
  variable = 4,
  fallback = 4,
  ["no-table"] = 160,
  ["song-timer"] = 6,
  ["empty-table"] = 160,
  ["no-fanfare"] = 0,
  ["bgm-dispatch"] = 4,
  ["audio-paused"] = 361,
  long = 361,
  ["long-fast"] = 37,
  replacement = 8,
  ["new-bgm"] = 2,
  ["same-bgm"] = 4,
  ["stop-bgm"] = 4,
  ["deferred-default"] = 4,
  ["latched-completion"] = 4,
}
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/native_fanfare_commands.lua").run(".", "gen2", version)
  T.eq(#rows, 20, "all native timer, variable, metadata and latched-wait cases execute")
  for _, row in ipairs(rows) do
    T.eq(row.completed, expected[row.case], row.case .. " retains native completion timing")
    T.eq(row.frames[1].startedValue, 1, "playing a fanfare does not block the following script command")
    for _, frame in ipairs(row.frames) do
      T.eq(type(frame.finished), "boolean", "native fanfare completion stays boolean")
      T.eq(type(frame.running), "boolean", "native script running state stays boolean")
    end
  end
  for _, speed in ipairs({ 1, 4, 10 }) do
    local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
    local h = dofile("tests/native_bgm/fanfares.lua").install(".", "gen2", version, f)
    h.clear()
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
    local script = assert(require("src.script.Gen3ScriptVM").compile({
      map_scripts = {
        source = "RomExtractorGen3",
        scripts = {
          OWNED_GAME_FANFARE = {
            { "lockall" },
            { "setvar", 0x8004, h.ids[1] },
            { "playfanfare", 0x8004 },
            { "waitfanfare" },
            { "setvar", 0x4001, 1 },
            { "releaseall" },
            { "end" },
          },
        },
      },
    }, "OWNED_GAME_FANFARE"))
    local steps, frame, completed, frozen = 0, 0, nil, true
    local hooks, ended = {}, {}
    f.e.api.hooks:wrap("script.command", function(next, ctx, name, args)
      hooks[#hooks + 1] = { edge = "before", name = name }
      local value = next(ctx, name, args)
      hooks[#hooks + 1] = { edge = "after", name = name }
      return value
    end)
    f.e.api.events:on("script.ended", function(event)
      ended[#ended + 1] = event.completed
    end)
    stack:push({
      update = function()
        h.tick(frame)
        if steps == 0 then
          runner:run(script, { source = { modId = "portable_held_item", strict = true } })
        else
          runner:update()
        end
        if runner:isRunning() and (not ow.gen3Locked or not ow.npcs[1].gen3ScriptFrozen) then
          frozen = false
        end
        if require("src.script.Gen3Commands").getVar(game.save, 0x4001) == 1 then
          completed = completed or frame
        end
        steps = steps + 1
      end,
    })
    Fixed:init(function(dt)
      game:step(dt)
    end)
    for tick = 0, 12 do
      frame = tick
      game:update(1 / 60)
    end
    T.eq(completed, 4, "actual Game audio ticks release the four-frame fanfare independently of logic speed")
    T.eq(runner:isRunning(), false, "actual game runner completes the fanfare script")
    T.eq(frozen, true, "field ownership persists throughout the yielding fanfare wait")
    T.eq(ow.gen3Locked, nil, "completed fanfare releases field input ownership")
    T.same(ended, { true }, "one completed event follows the native wait")
    T.eq(Music.nativeSnapshot().song, h.bgmIds[1], "actual Game audio restores its own dataset's map music")
    T.eq(
      Music.current(),
      "MUS_TITLE",
      "actual Game restoration replays the physical music from its own dataset"
    )
    local entered, exited = 0, 0
    for _, event in ipairs(hooks) do
      if event.name == "g3_wait_fanfare" then
        if event.edge == "before" then
          entered = entered + 1
        else
          exited = exited + 1
        end
      end
    end
    T.eq(entered, 1, "public wait hook enters once")
    T.eq(exited, 1, "public wait hook returns once after yielding")
    h.close()
    f.close()
  end
  local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
  local h = dofile("tests/native_bgm/streams.lua").install(".", "gen2", version, f)
  local ff = h.fanfares()
  local worker = dofile("tests/native_bgm/worker.lua")
  worker.actual(f.data, f.data.audio.songs[("SONG_%03X"):format(h.ids[1])], T)
  worker.transport(h, f, ff, T)
  h.close()
  f.close()
end
V.set(before)
T.finish("native fanfare commands, game clocks, field ownership and latched waits")
