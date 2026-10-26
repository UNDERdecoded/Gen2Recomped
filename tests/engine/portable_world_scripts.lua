package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Manifest = require("src.mods.Manifest")
local Program = require("src.mods.ScriptProgram")
local Runtime = require("src.mods.Runtime")
local Runner = require("src.script.ScriptRunner")
local WorldAPI = require("src.world.WorldAPI")
local GameVersion = require("src.core.GameVersion")
local Font = require("src.render.Font")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local Json = require("src.link.Json")
local originalVersion = GameVersion.get()
local function boot(version)
  GameVersion.set(version)
  local data, files = T.fixtures.fresh(), {}
  for _, id in ipairs({ "probe", "other", "legacy" }) do
    files["mods/" .. id .. "/manifest.json"] = Json.encode({
      id = id,
      name = id,
      version = "1.0.0",
      api = 2,
      entry = "main.lua",
      script_format = id ~= "legacy" and "unified" or nil,
      content_format = os.getenv("PORTABLE_SCRIPT_ALL_FORMATS") == "1" and id ~= "legacy" and "unified"
        or nil,
      callback_format = os.getenv("PORTABLE_SCRIPT_ALL_FORMATS") == "1" and id ~= "legacy" and "unified"
        or nil,
      description = os.getenv("PORTABLE_SCRIPT_ALL_FORMATS") == "1" and "all-formats" or "",
    })
    files["mods/" .. id .. "/main.lua"] = [[return function(mod)
      if mod.id ~= "legacy" then
        assert(mod.scriptFormat == "unified")
        if mod.manifest.description == "all-formats" then
          assert(mod.contentFormat == "unified")
          assert(mod.callbackFormat == "unified")
        end
        local ok, why = mod.world:queueScript({ { "wait", 1 } })
        assert(ok == nil and type(why) == "string")
      else assert(mod.scriptFormat == "native") end
    end]]
  end
  local fs = {
    read = function(p)
      return files[p]
    end,
    load = function(p)
      return loadstring(files[p], p)
    end,
    getDirectoryItems = function(p)
      return p == "mods" and { "probe", "other", "legacy" } or {}
    end,
    getInfo = function(p)
      if p == "mods" or p == "mods/probe" or p == "mods/other" or p == "mods/legacy" then
        return { type = "directory" }
      end
      if files[p] then
        return { type = "file" }
      end
    end,
  }
  local loader = Loader.new({ fs = fs, dev = false })
  T.check(loader:load(data), "fixture mods load")
  T.eq(package.loaded["src.core.Game"], nil, "early portable request does not bootstrap Game")
  Font.load(data)
  local game = {
    data = data,
    save = SaveData.newGame(),
    stack = setmetatable({ states = {} }, { __index = StateStack }),
  }
  local ow = {
    isOverworld = true,
    map = { id = "FIX_TOWN", def = data.maps.FIX_TOWN },
    player = { cellX = 4, cellY = 5, facing = "up" },
    scriptMoves = {},
    pendingScripts = {},
    parallelRunners = {},
  }
  game.overworld, ow.game = ow, game
  ow.runner = Runner.new(game, ow)
  function ow:update()
    self.runner:update()
  end
  game.stack.states = { ow }
  game.input = {
    wasPressed = function()
      return false
    end,
    isDown = function()
      return false
    end,
  }
  loader.game = game
  return loader.apis.probe.world, game, ow, loader, files
end
local function tick(game, key)
  game.input.wasPressed = function(_, k)
    return k == key
  end
  Runtime.call("input.step", function() end, game, 1 / 60)
  game.stack:update(1 / 60)
  game.input.wasPressed = function()
    return false
  end
end
local function untilState(game, predicate)
  for _ = 1, 2000 do
    if predicate() then
      return
    end
    tick(game)
  end
  error("native UI did not reach requested state")
end
local function finishText(game)
  local box = game.stack:top()
  untilState(game, function()
    return box.done or box.waiting and (box.preWait or 0) <= 0
  end)
  tick(game, "a")
end
for _, version in ipairs(GameVersion.ORDER) do
  local world, game, ow, loader = boot(version)
  local before, calls, result = ow.runner, 0, nil
  T.check(
    world:queueScript({ { "wait", 2 }, { "text", "First" }, { "end" }, { "text", "Unreachable" } }, {
      onDone = function(ok, why)
        calls = calls + 1
        result = { ok, why }
      end,
    }),
    version .. " program admitted"
  )
  T.neq(ow.runner, before, "isolated native runner installed")
  T.eq(ow.runner:isRunning(), true, "runner locks foreground input")
  tick(game)
  T.eq(game.stack:top(), ow, "wait does not end early")
  tick(game)
  T.neq(game.stack:top(), ow, "native text appears after wait")
  T.eq(calls, 0, "completion awaits text")
  finishText(game)
  T.same(result, { true }, "success completion")
  T.eq(calls, 1, "completion once")
  T.eq(ow.runner, before, "idle native runner restored")
  T.eq(game.stack:top(), ow, "script text closed")

  local Choice = require("src.ui.ChoiceBox")
  for _, yes in ipairs({ true, false }) do
    local lines = {}
    T.check(
      world:queueScript({
        { "ask", "Question?" },
        { "jump_if_false", "no" },
        { "text", "YES" },
        { "jump", "end" },
        { "label", "no" },
        { "text", "NO" },
      }, {
        onDone = function(ok)
          lines[#lines + 1] = ok
        end,
      }),
      "question script admitted"
    )
    untilState(game, function()
      return getmetatable(game.stack:top()) == Choice
    end)
    local choice = game.stack:top()
    tick(game, yes and "a" or "b")
    T.eq(choice.pending, yes, "native answer pending")
    T.eq(#lines, 0, "answer hold preserved")
    untilState(game, function()
      return game.stack:top() ~= choice
    end)
    T.same(
      game.stack:top().pages,
      require("src.render.TextBox").paginate(
        yes and "YES" or "NO",
        game.stack:top().maxCols,
        game.stack:top().letterSpacing,
        game.stack:top().maxPixels,
        true
      ),
      "correct branch text"
    )
    finishText(game)
    T.same(lines, { true }, "question branch completes")
  end
  local trace = {}
  T.check(
    world:queueScript({
      { "choice", { "ONE", "TWO", "THREE" }, { default = 2, cancel = 3 } },
      { "jump_if_false", 5 },
      { "text", "WRONG" },
      { "end" },
      { "text", "RIGHT" },
    }, {
      onDone = function(ok)
        trace[#trace + 1] = ok
      end,
    }),
    "multiple choice admitted"
  )
  T.eq(game.stack:top().index, 2, "native default selection")
  tick(game, "b")
  finishText(game)
  T.same(trace, { true }, "native B choice follows false branch")
  T.eq(loader.apis.legacy.world.queueScript, WorldAPI.queueScript, "legacy method unchanged")
end

local function freeze(root)
  local graph = {}
  local function visit(t)
    if type(t) ~= "table" or graph[t] then
      return
    end
    local entry = { mt = getmetatable(t), values = {} }
    graph[t] = entry
    for k, v in pairs(t) do
      entry.values[k] = v
      visit(k)
      visit(v)
    end
  end
  visit(root)
  return function(label)
    local same = true
    for t, entry in pairs(graph) do
      same = same and getmetatable(t) == entry.mt
      for k, v in pairs(entry.values) do
        same = same and rawget(t, k) == v
      end
      for k, v in pairs(t) do
        same = same and entry.values[k] == v
      end
    end
    T.check(same, label)
  end
end
local function refusal(world, game, rows, options, label)
  local unchanged = freeze(game)
  local ok, why = world:queueScript(rows, options)
  T.eq(ok, nil, label)
  T.eq(type(why), "string", label .. " has reason")
  unchanged(label .. " is observational")
end
local badPrograms = {
  false,
  1,
  "text",
  function() end,
  { [1] = { "wait", 1 }, [3] = { "end" } },
  { [1] = { "wait", 1 }, extra = true },
  setmetatable({ { "end" } }, {}),
  { false },
  { {} },
  { { "wait" } },
  { { "wait", 1, 2 } },
  { { "wait", -1 } },
  { { "wait", 1.5 } },
  { { "wait", 0 / 0 } },
  { { "wait", math.huge } },
  { { "wait", 36001 } },
  { { "end", false } },
  { { "native_mutate", {} } },
  { { "show_text", {} } },
  { { "show_text", string.rep("x", 4097) } },
  { { "text", "Valid" }, { "give_item", "POTION" } },
  { { "text", "Valid" }, { "jump", "missing" } },
  { { "label", "same" }, { "label", "same" } },
  { { "label", "end" } },
  { { "label", "bad\nname" } },
  { { "jump", 0 } },
  { { "jump", 99 } },
  { { "jump", false } },
  { { "choice", {} } },
  { { "choice", { "A", "B" }, { cancel = 3 } } },
  { { "choice", { "A" }, { default = 0 } } },
  { { "choice", { "A" }, { custom = true } } },
  { { "choice", { "A", function() end } } },
  { { "choice", { "" } } },
  { { "choice", { "A" }, setmetatable({}, {}) } },
  { setmetatable({ "wait", 1 }, {}) },
}
for _, version in ipairs(GameVersion.ORDER) do
  local world, game, ow, loader = boot(version)
  local callbacks = 0
  for _, rows in ipairs(badPrograms) do
    refusal(world, game, rows, {
      onDone = function()
        callbacks = callbacks + 1
      end,
    }, "invalid whole program")
  end
  for _, options in ipairs({
    false,
    1,
    "options",
    { onDone = true },
    { onDone = function() end, runner = {} },
    setmetatable({}, {}),
  }) do
    refusal(world, game, { { "wait", 1 } }, options, "invalid options")
  end
  T.eq(callbacks, 0, "rejected lists never complete or execute a prefix")
  for _, key in ipairs({
    "transitioning",
    "flyAnim",
    "teleportOut",
    "engaging",
    "emote",
    "pikaHop",
    "healAnim",
    "whirlSpin",
    "gen4Waterfall",
    "gen5SeamPending",
    "gen3Decorate",
    "gen3Locked",
    "frameScriptThisTick",
    "_modScriptLock",
  }) do
    ow[key] = true
    refusal(world, game, { { "wait", 1 } }, nil, key .. " owns world")
    ow[key] = nil
  end
  for _, key in ipairs({ "moving", "inputLocked", "stairExit", "spinning", "fieldMove" }) do
    ow.player[key] = true
    refusal(world, game, { { "wait", 1 } }, nil, key .. " owns player")
    ow.player[key] = nil
  end
  for _, key in ipairs({ "pendingScripts", "scriptMoves", "parallelRunners", "parallelQueue" }) do
    ow[key] = { {} }
    refusal(world, game, { { "wait", 1 } }, nil, key .. " owns script scheduling")
    ow[key] = {}
  end
  game.linkSession = {}
  refusal(world, game, { { "wait", 1 } }, nil, "link session busy")
  game.linkSession = nil
  game.linkNet = { closed = false }
  refusal(world, game, { { "wait", 1 } }, nil, "link transport busy")
  game.linkNet = nil
  game.stack:push({})
  refusal(world, game, { { "wait", 1 } }, nil, "covered world busy")
  game.stack:pop()
  ow.runner:run({ { "wait", 9 } })
  refusal(world, game, { { "wait", 1 } }, nil, "native script busy")
  for _ = 1, 9 do
    tick(game)
  end
  T.check(world:queueScript({ { "wait", 1 } }), "new script after native completion")
  tick(game)
  T.eq(loader.apis.other.world:cancelScript(), false, "another mod cannot cancel a program")
end
-- Limits, data copying and compiler immutability, including a cyclic payload.
do
  local world, game, ow = boot("crystal")
  local over = {}
  for i = 1, 1025 do
    over[i] = { "end" }
  end
  refusal(world, game, over, nil, "row bound")
  over = {}
  for i = 1, 33 do
    over[i] = { "text", string.rep("x", 4096) }
  end
  refusal(world, game, over, nil, "total text bound")
  local cycle = {}
  cycle[1] = cycle
  refusal(world, game, cycle, nil, "cyclic command denied")
  local rows = { { "wait", 2 }, { "choice", { "ONE", "TWO" }, { default = 2 } } }
  local unchanged = freeze(rows)
  local compiled = Program.compile(rows)
  unchanged("compiler leaves caller rows intact")
  T.neq(compiled[2][2], rows[2][2], "compiler copies nested labels")
  T.check(world:queueScript(rows), "copied program accepted")
  rows[2][1], rows[2][2][2], rows[2][3].default = "invalid", "MUTATED", 1
  tick(game)
  tick(game)
  T.eq(game.stack:top().index, 2, "choice options captured before caller edit")
  T.eq(game.stack:top().items[2].label, "TWO", "choice labels copied before execution")
  world:cancelScript()
end
-- Session changes cancel even while an old Game is no longer being stepped.
for _, version in ipairs({ "red", "crystal", "emerald", "platinum", "heartgold", "black" }) do
  for _, change in ipairs({
    "save",
    "data",
    "stack",
    "states",
    "map",
    "mapId",
    "player",
    "position",
    "runner",
    "game",
    "version",
    "removed",
    "transition",
  }) do
    local world, game, ow, loader = boot(version)
    local originalRunner, calls, result = ow.runner, 0
    T.check(
      world:queueScript({ { "wait", 30 }, { "text", "Must not run" } }, {
        onDone = function(ok, why)
          calls = calls + 1
          result = { ok, why }
        end,
      }),
      "session test admitted"
    )
    local stale = ow.runner
    local replacement
    if change == "save" then
      game.save = SaveData.newGame()
    elseif change == "data" then
      game.data = T.fixtures.fresh()
    elseif change == "stack" then
      game.stack = setmetatable({ states = { ow } }, { __index = StateStack })
    elseif change == "states" then
      game.stack.states = { ow }
    elseif change == "map" then
      ow.map = { id = "FIX_ROUTE", def = game.data.maps.FIX_ROUTE }
    elseif change == "mapId" then
      ow.map.id = "FIX_ROUTE"
    elseif change == "player" then
      ow.player = { cellX = 4, cellY = 5 }
    elseif change == "position" then
      ow.player.cellX = 7
    elseif change == "runner" then
      replacement = Runner.new(game, ow)
      ow.runner = replacement
    elseif change == "game" then
      replacement = { stack = setmetatable({ states = {} }, { __index = StateStack }), input = game.input }
      loader.game = replacement
    elseif change == "version" then
      GameVersion.set(version == "red" and "crystal" or "red")
    elseif change == "removed" then
      game.stack.states = {}
    elseif change == "transition" then
      ow.transitioning = true
    end
    Runtime.call("input.step", function() end, change == "game" and replacement or game, 1 / 60)
    T.eq(calls, 1, change .. " cancellation delivered")
    T.eq(result[1], false, "session cancellation is not success")
    T.eq(type(result[2]), "string", "cancellation gives reason")
    T.eq(ow.runner, change == "runner" and replacement or originalRunner, "restore only owned runner")
    stale:resume()
    stale:update()
    T.eq(calls, 1, "old runner callbacks cannot replay cancellation")
    T.eq(stale:isRunning(), false, "abandoned coroutine released")
    GameVersion.set(version)
  end
end
-- Cancel removes only owned windows, including the choice above its text.
for _, version in ipairs(GameVersion.ORDER) do
  local world, game, ow, loader = boot(version)
  local originalRunner, calls = ow.runner, 0
  T.check(
    world:queueScript({ { "ask", "Question?" }, { "text", "Later" } }, {
      onDone = function(ok)
        T.eq(ok, false, "explicit cancel completion")
        calls = calls + 1
      end,
    }),
    "cancellable question"
  )
  local box = game.stack:top()
  untilState(game, function()
    return game.stack:top() ~= box
  end)
  local choice = game.stack:top()
  local foreign = { update = function() end }
  game.stack:push(foreign)
  T.eq(loader.apis.other.world:cancelScript(), false, "foreign mod has no cancellation authority")
  T.check(world:cancelScript(), "owner cancels")
  T.same(game.stack.states, { ow, foreign }, "foreign overlay survives cancellation")
  T.eq(ow.runner, originalRunner, "cancel restores idle runner")
  T.eq(calls, 1, "cancel callback once")
  choice.onChoose(true)
  box.onDone()
  choice:update(1 / 60)
  box:update(1 / 60)
  T.same(game.stack.states, { ow, foreign }, "stale native UI cannot pop foreign screen")
  T.eq(calls, 1, "stale native callbacks do not complete twice")
end
-- Replaying an old callback during a later row must not skip that row's wait.
do
  local world, game, ow = boot("red")
  T.check(
    world:queueScript({ { "text", "First" }, { "wait", 10 }, { "text", "Last" } }),
    "callback replay test admitted"
  )
  local old = game.stack:top()
  finishText(game)
  T.eq(ow.runner.waitingFrames, 10, "later wait begins")
  old.onDone()
  old:update(1 / 60)
  T.eq(ow.runner.waitingFrames, 10, "old text callback cannot skip current wait")
  for _ = 1, 10 do
    tick(game)
  end
  T.neq(game.stack:top(), ow, "new text after full wait")
  world:cancelScript()
end

-- Native error cleanup, completion exceptions and event reentry are bounded.
for _, version in ipairs({ "red", "crystal", "emerald", "platinum", "black" }) do
  local world, game, ow, loader = boot(version)
  local TextBox = require("src.render.TextBox")
  local original, make = ow.runner, TextBox.new
  local completions, result = 0
  TextBox.new = function()
    error("injected native constructor failure")
  end
  Runtime.currentMod = "probe"
  T.check(
    world:queueScript({ { "text", "Fail" } }, {
      onDone = function(ok, why)
        completions = completions + 1
        result = { ok, why }
      end,
    }),
    "entered native failure is admitted"
  )
  T.eq(Runtime.currentMod, "probe", "engine ownership restored on failure")
  Runtime.currentMod = nil
  TextBox.new = make
  T.eq(result[1], false, "native error completes as failure")
  T.check(result[2]:find("constructor failure", 1, true) ~= nil, "native error reason retained")
  T.eq(completions, 1, "native error completion once")
  T.eq(ow.runner, original, "native error releases runner")
  T.check(
    world:queueScript({}, {
      onDone = function()
        error("completion failure")
      end,
    }),
    "callback error isolated"
  )
  T.eq(ow.runner, original, "callback error cannot strand runner")
  local events = {}
  local stop1 = loader.events:on("script.started", function(ev)
    if ev.ctx.source and ev.ctx.source.modId == "probe" then
      events[#events + 1] = "started"
      refusal(
        loader.apis.other.world,
        game,
        { { "wait", 1 } },
        nil,
        "event callback cannot reenter owned run"
      )
    end
  end)
  local stop2 = loader.events:on("script.ended", function(ev)
    if ev.ctx.source and ev.ctx.source.modId == "probe" then
      events[#events + 1] = ev.completed and "success" or "failure"
    end
  end)
  T.check(world:queueScript({ { "wait", 1 } }), "eventful wait admitted")
  tick(game)
  T.same(events, { "started", "success" }, "one lifecycle event pair")
  T.check(world:queueScript({ { "wait", 10 } }), "eventful cancel admitted")
  world:cancelScript()
  T.same(events, { "started", "success", "started", "failure" }, "cancel emits failure once")
  stop1()
  stop2()
end
-- An infinite authored jump yields slices to the engine and eventually
-- reports failure rather than blocking a frame or permanently owning input.
do
  local world, game, ow = boot("red")
  local original, result, ticks = ow.runner, nil, 0
  T.check(
    world:queueScript({ { "label", "loop" }, { "jump", "loop" } }, {
      onDone = function(ok, why)
        result = { ok, why }
      end,
    }),
    "loop admitted"
  )
  T.eq(result, nil, "loop yields back from initial call")
  untilState(game, function()
    ticks = ticks + 1
    return result ~= nil
  end)
  T.check(ticks > 1, "loop spans engine updates")
  T.eq(result[1], false, "instruction limit fails explicitly")
  T.check(result[2]:find("budget", 1, true) ~= nil, "budget reason")
  T.eq(ow.runner, original, "budget exhaustion releases world")
end
-- Teardown/reload and failed entry chunks retire captured facades. Neither
-- completion nor a script-ended listener may start fresh work during teardown.
for _, mode in ipairs({ "teardown", "reload", "rollback" }) do
  local world, game, ow, loader, files = boot("emerald")
  local original, calls, retry = ow.runner, 0
  T.check(
    world:queueScript({ { "text", "Pending" } }, {
      onDone = function(ok)
        T.eq(ok, false, "lifecycle cancellation")
        calls = calls + 1
        retry = world:queueScript({ { "wait", 1 } })
      end,
    }),
    "lifecycle program accepted"
  )
  if mode == "teardown" then
    Loader.teardown()
  elseif mode == "reload" then
    boot("emerald")
  else
    loader:_rollback("probe")
  end
  T.eq(calls, 1, "lifecycle completion once")
  T.eq(retry, nil, "no restart while retiring")
  T.eq(ow.runner, original, "lifecycle restores runner")
  T.same(game.stack.states, { ow }, "lifecycle removes owned text")
  refusal(world, game, { { "wait", 1 } }, nil, "retained API retired")
end
do
  local _, game, ow, loader, files = boot("crystal")
  local original = ow.runner
  files["mods/probe/main.lua"] = [[return function(mod)
    assert(mod.world:queueScript({ { "wait", 30 } }))
    error("entry failure after queue")
  end]]
  files["mods/other/main.lua"] = "return function() end"
  local failed = Loader.new({ fs = loader.fs, dev = false })
  failed.game = game
  failed:load(T.fixtures.fresh())
  T.eq(ow.runner, original, "failed entry cancels its accepted run")
  T.eq(original:isRunning(), false, "failed entry cannot strand foreground")
end
-- Omitted/native formats preserve the old API 1/2 contract. Explicit malformed
-- or API-1 unified declarations must fail instead of silently changing mode.
do
  local function manifest(format, level)
    return {
      id = "probe",
      name = "Probe",
      version = "1.0.0",
      entry = "main.lua",
      api = level or 2,
      script_format = format,
    }
  end
  for _, bad in ipairs({ false, true, 1, {}, "portable", "" }) do
    T.raises(function()
      Manifest.validate(manifest(bad), "mods/probe")
    end, "script_format", "invalid format")
  end
  T.raises(function()
    Manifest.validate(manifest("unified", 1), "mods/probe")
  end, "API 2", "unified requires API 2")
  T.eq(
    Manifest.validate(manifest(nil, 1), "mods/probe").script_format,
    "native",
    "API 1 default remains native"
  )
  T.eq(
    Manifest.validate(manifest("native", 1), "mods/probe").script_format,
    "native",
    "explicit API 1 native accepted"
  )
end
-- Per-frame traces against the real native runner/commands, rather than
-- against another implementation of the portable adapter.
local function stateRecord(game, ow)
  local top = game.stack:top()
  local record =
    { depth = #game.stack.states, running = ow.runner:isRunning(), wait = ow.runner.waitingFrames }
  if top ~= ow then
    record.index, record.pending, record.hold = top.index, top.pending, top.holdFrames
    record.page, record.line, record.char = top.pageIndex, top.lineIndex, top.charIndex
    record.done, record.waiting, record.preWait = top.done, top.waiting, top.preWait
    if top.shown then
      record.shown = Json.decode(Json.encode(top.shown))
    end
    if top.items then
      record.labels = {}
      for _, item in ipairs(top.items) do
        record.labels[#record.labels + 1] = item.label
      end
    end
  end
  return record
end
for _, version in ipairs(GameVersion.ORDER) do
  for _, yes in ipairs({ true, false }) do
    local traces = {}
    for _, native in ipairs({ true, false }) do
      local world, game, ow = boot(version)
      local rows = {
        { "wait", 2 },
        { "show_text", "First\fSecond" },
        { "ask", "Question?" },
        { "jump_if_false", "no" },
        { "choice", { "ONE", "TWO" }, { default = 2, cancel = 2 } },
        { "jump", "end" },
        { "label", "no" },
        { "show_text", "NO" },
      }
      local completed, trace = false, {}
      local saveUnchanged = freeze(game.save)
      if native then
        ow.runner:run(rows, {
          onDone = function()
            completed = true
          end,
        })
      else
        T.check(
          world:queueScript(rows, {
            onDone = function(ok)
              T.eq(ok, true, "parity program succeeds")
              completed = true
            end,
          }),
          "parity program admitted"
        )
      end
      for frame = 1, 2000 do
        trace[#trace + 1] = stateRecord(game, ow)
        if completed then
          break
        end
        local top = game.stack:top()
        local key
        if top.pending == nil and getmetatable(top) == require("src.ui.ChoiceBox") then
          key = yes and "a" or "b"
        elseif top.items then
          key = "b"
        elseif top.done or top.waiting and (top.preWait or 0) <= 0 then
          key = "a"
        end
        tick(game, key)
      end
      T.eq(completed, true, "native parity trace completed")
      saveUnchanged("dialogue program leaves save unchanged")
      traces[#traces + 1] = trace
    end
    T.same(traces[1], traces[2], version .. " frame-by-frame native dialogue/wait/branch parity")
  end
end

do
  local world, game, ow, loader = boot("black")
  for _, invalid in ipairs({
    "bad\0text",
    "\128",
    "\192\128",
    "\224\128\128",
    "\237\160\128",
    "\244\144\128\128",
    "\240\159",
  }) do
    refusal(
      world,
      game,
      { { "text", "Valid first" }, { "ask", invalid } },
      nil,
      "invalid UTF-8 refused before prefix"
    )
  end
  T.check(world:queueScript({ { "text", "Grüße Pokémon ♀" } }), "valid UTF-8 accepted")
  world:cancelScript()
  local calls = 0
  local stop = loader.hooks:wrap("input.step", function(nextFn, ...)
    calls = calls + 1
    return nextFn(...)
  end, -1, "other")
  for _ = 1, 3 do
    T.check(world:queueScript({ { "wait", 2 } }), "reused observer admission")
    world:cancelScript()
  end
  local before = calls
  tick(game)
  T.eq(calls, before + 1, "observer does not skip or duplicate downstream hooks")
  stop()
  local random = math.random
  local rolls = 0
  math.random = function()
    rolls = rolls + 1
    error("portable scripts must not roll RNG")
  end
  T.check(world:queueScript({ { "text", "FIRST" } }), "no-RNG dialogue")
  finishText(game)
  math.random = random
  T.eq(rolls, 0, "no RNG consumed")
  local events = {}
  local done = loader.events:on("script.ended", function(ev)
    events[#events + 1] = ev.completed
  end)
  T.check(world:queueScript({ { "text", "Native failure" } }), "native update failure admission")
  local box = game.stack:top()
  -- The guarded method captures the native update when the box is created.
  -- Fail native work reached on a later frame instead of changing the guard.
  box.beginLine = function()
    error("native text update failure")
  end
  box.done, box.waiting, box.preWait, box.contAdvance = false, true, 0, true
  tick(game, "a")
  T.same(events, { false }, "native UI update error completes once")
  T.eq(game.stack:top(), ow, "native update error releases owned UI")
  done()
end
for _, version in ipairs(GameVersion.ORDER) do
  local world, game, ow, loader = boot(version)
  local api = loader.apis.probe
  if api.supports then
    T.eq(api:supports("world", "queueScript"), true, "portable queue capability")
    T.eq(api:supports("world", "cancelScript"), true, "portable cancel capability")
    for _, verb in ipairs({
      "text",
      "show_text",
      "ask",
      "choice",
      "wait",
      "label",
      "jump",
      "jump_if_true",
      "jump_if_false",
      "end",
    }) do
      T.eq(api:supports("scripts", verb), true, "bounded verb capability")
    end
    T.eq(api:supports("scripts", "warp"), false, "unsupported verb declined")
    T.eq(loader.apis.legacy:supports("world", "cancelScript"), false, "legacy has no portable cancellation")
    T.eq(loader.apis.legacy:supports("scripts", "wait"), false, "native format does not claim portable verbs")
  end
  T.eq(world:current().mapId, "FIX_TOWN", "unrelated world methods still delegate")
  T.eq(world.game, game, "existing native fields still delegate")
end

-- First admission from an input.step callback must not sort a new observer
-- into the chain while it is being traversed (which would replay the caller).
do
  local world, game = boot("crystal")
  local wrappers, vanilla = 0, 0
  local stop = Runtime.hooks:wrap("input.step", function(nextFn, ...)
    wrappers = wrappers + 1
    if wrappers == 1 then
      T.check(world:queueScript({ { "wait", 2 } }), "first queue inside input hook")
    end
    return nextFn(...)
  end, 0, "probe")
  Runtime.call("input.step", function()
    vanilla = vanilla + 1
  end, game, 1 / 60)
  T.eq(wrappers, 1, "first queue does not replay input callback")
  T.eq(vanilla, 1, "native input boundary called once")
  world:cancelScript()
  stop()
end
do
  local world, game, ow=boot("crystal")
  game.stack.states={};game.stack.worldState=ow
  function game.stack:active()return self:top()or self.worldState end
  local calls,result=0,nil
  T.check(world:queueScript({{"wait",2}}, {onDone=function(ok)calls=calls+1;result=ok end}),"persistent Gen2 world admits script")
  Runtime.call("input.step",function()end,game,1/60)
  for _=1,4 do ow:update()end
  T.eq(result,true,"persistent native runner completes script")
  T.eq(calls,1,"persistent script completes once")
  T.eq(game.stack:top(),nil,"completion preserves empty overlay stack")
end
GameVersion.set(originalVersion)
T.finish("portable world scripts")
