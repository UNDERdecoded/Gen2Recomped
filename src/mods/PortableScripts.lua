-- Per-mod portable dialogue programs. An isolated native runner owns the
-- foreground until completion, then returns the idle runner it borrowed.
local Program = require("src.mods.ScriptProgram")
local Runtime = require("src.mods.Runtime")
local Flags = require("src.mods.Api3Flags")
local State = require("src.mods.ScriptState")
local GameVersion = require("src.core.GameVersion")
local Scripts = {}
local runs = setmetatable({}, { __mode = "k" })
local observers = setmetatable({}, { __mode = "k" })
local contexts = setmetatable({}, { __mode = "k" })
local draining = false
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
local function engine(fn, ...)
  local owner = Runtime.currentMod
  Runtime.currentMod = nil
  local result = pack(pcall(fn, ...))
  Runtime.currentMod = owner
  return unpack(result, 1, result.n)
end
local function current(loader)
  if loader.game then
    return loader.game
  end
  local game = package.loaded["src.core.Game"]
  return type(game) == "table" and game or nil
end
local function message(err)
  local ok, text = pcall(tostring, err)
  return ok and text or "unprintable error"
end
local function contains(stack, state)
  if type(stack.states) ~= "table" then
    return false
  end
  for _, value in ipairs(stack.states) do
    if value == state then
      return true
    end
  end
  return false
end
local function remove(stack, state)
  if type(stack.states) ~= "table" then
    return
  end
  for i = #stack.states, 1, -1 do
    if stack.states[i] == state then
      table.remove(stack.states, i)
      if Runtime.wants("screen.popped") then
        Runtime.emit("screen.popped", { state = state })
      end
      return
    end
  end
end
local LOCKS = {
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
}
local function ready(game)
  if not (game and game.save) then
    return nil, "no save"
  end
  local stack = game.stack
  if not (stack and type(stack.states) == "table" and type(stack.top) == "function") then
    return nil, "no overworld"
  end
  local ow = stack:top()
  if not (ow and ow.isOverworld and ow.map and ow.player and ow.runner) then
    return nil, "world is busy"
  end
  if
    runs[game]
    or game.overworld and game.overworld ~= ow
    or game.linkSession
    or game.linkNet and not game.linkNet.closed
  then
    return nil, "world is busy"
  end
  for _, key in ipairs(LOCKS) do
    if ow[key] then
      return nil, "world is busy"
    end
  end
  for _, key in ipairs({ "moving", "inputLocked", "stairExit", "spinning", "fieldMove" }) do
    if ow.player[key] then
      return nil, "world is busy"
    end
  end
  if
    ow.runner:isRunning()
    or #(ow.scriptMoves or {}) > 0
    or #(ow.pendingScripts or {}) > 0
    or #(ow.parallelRunners or {}) > 0
    or #(ow.parallelQueue or {}) > 0
  then
    return nil, "world is busy"
  end
  return ow
end
local function observe(loader)
  local installed = observers[loader]
  if installed and installed[1] == loader.hooks then
    return
  end
  -- Weak values too: the hook closure captures its loader, so retaining the
  -- hooks here would otherwise keep every unloaded loader alive on LuaJIT.
  observers[loader] = setmetatable({ loader.hooks }, { __mode = "v" })
  -- Keep one observer per loader: retiring a hook while its chain dispatches
  -- would shift the following mod's index. Per-run cleanup never edits it.
  loader.hooks:wrap("input.step", function(nextFn, game, dt)
    if next(runs) == nil then
      return nextFn(game, dt)
    end
    local pending = {}
    for _, token in pairs(runs) do
      if token.loader == loader then
        pending[#pending + 1] = token
      end
    end
    for _, token in ipairs(pending) do
      local ok, live, why = engine(token.valid)
      if not ok or not live then
        token.finish(false, ok and why or "script context failed")
      elseif token.waitingUI and not contains(token.stack, token.waitingUI) then
        token.finish(false, "script UI was removed")
      end
    end
    return nextFn(game, dt)
  end, math.huge, "engine:portable_scripts")
end
function Scripts.cancelAll(loader, modId, reason)
  if loader and modId then
    if contexts[loader] then
      contexts[loader].owners[modId] = nil
    end
  elseif loader then
    contexts[loader] = nil
  else
    for owner in pairs(contexts) do
      contexts[owner] = nil
    end
  end
  local wasDraining = draining
  draining = true
  local pending = {}
  for _, token in pairs(runs) do
    if (not loader or token.loader == loader) and (not modId or token.modId == modId) then
      pending[#pending + 1] = token
    end
  end
  for _, token in ipairs(pending) do
    token.finish(false, reason or "script session ended")
  end
  draining = wasDraining
end
local function facade(loader, modId, native)
  local context = contexts[loader]
  if not context then
    context = { owners = {} }
    contexts[loader] = context
  end
  local lease = {}
  context.owners[modId] = lease
  local function licensed()
    return not draining and contexts[loader] == context and context.owners[modId] == lease
  end
  -- Install before entry code can subscribe/queue from input.step. Sorting
  -- a new observer into a live hook chain could replay its current wrapper.
  observe(loader)
  local world, active = {}, nil
  local function queue(rows, options)
    if not licensed() then
      return nil, "script facade is retired"
    end
    local program, why = Program.compile(
      rows,
      { owner = modId, generation = GameVersion.generation(), version = GameVersion.get() }
    )
    if not program then
      return nil, why
    end
    if options ~= nil then
      if type(options) ~= "table" or getmetatable(options) ~= nil then
        return nil, "options must be a plain table"
      end
      for key, value in pairs(options) do
        if key ~= "onDone" or type(value) ~= "function" then
          return nil, "only onDone callback is supported"
        end
      end
    end
    local onDone = options and options.onDone
    local game = current(loader)
    local ow
    ow, why = ready(game)
    if not ow then
      return nil, why
    end
    local function flag(name, value, write)
      return Flags.call(game, modId, GameVersion.generation(), name, value, write, licensed, function()
        return ow
      end)
    end
    -- Check stores for every row, including unreachable branches, before a prefix runs.
    for i, row in ipairs(program) do
      if
        row[1] == "set_flag"
        or row[1] == "clear_flag"
        or row[1] == "check_flag"
        or row[1] == "wait_flag"
      then
        local value, reason = flag(row[2])
        if value == nil then
          return nil, "row " .. i .. ": " .. reason
        end
      end
    end
    local state, reason = State.prepare(loader, game, ow, program)
    if not state then
      return nil, reason
    end
    local Runner = require("src.script.ScriptRunner")
    local runner = Runner.new(game, ow)
    local token = {
      loader = loader,
      modId = modId,
      game = game,
      world = ow,
      runner = runner,
      original = ow.runner,
      stack = game.stack,
      states = game.stack.states,
      mapId = ow.map.id,
      x = ow.player.cellX,
      y = ow.player.cellY,
      save = game.save,
      data = game.data,
      map = ow.map,
      player = ow.player,
      version = GameVersion.get(),
      ui = {},
      steps = 0,
    }
    function token.valid()
      if token.done then
        return nil, "script is finished"
      end
      if
        not licensed()
        or current(loader) ~= game
        or game.save ~= token.save
        or game.data ~= token.data
        or game.stack ~= token.stack
        or game.stack.states ~= token.states
        or not contains(token.stack, ow)
        or game.overworld and game.overworld ~= ow
        or ow.map ~= token.map
        or ow.map.id ~= token.mapId
        or ow.player ~= token.player
        or ow.player.cellX ~= token.x
        or ow.player.cellY ~= token.y
        or ow.runner ~= runner
        or GameVersion.get() ~= token.version
        or Runtime.hooks ~= loader.hooks
        or Runtime.events ~= loader.events
        or game.linkSession
        or game.linkNet and not game.linkNet.closed
        or ow.transitioning
      then
        return nil, "script session changed"
      end
      return true
    end
    function token.finish(ok, reason)
      if token.done then
        return
      end
      token.done = true
      runner.co, runner.waitingFrames, runner.waitingCheck = nil, nil, nil
      -- Remove only this run's exact native screens, preserving foreign
      -- overlays and a replacement world's runner/locks.
      for i = #token.ui, 1, -1 do
        remove(token.stack, token.ui[i])
      end
      if ow.runner == runner then
        ow.runner = token.original
      end
      if runs[game] == token then
        runs[game] = nil
      end
      if active == token then
        active = nil
      end
      if Runtime.wants("script.ended") then
        Runtime.emit("script.ended", { ctx = runner.ctx, completed = ok })
      end
      if onDone then
        local called, err = pcall(onDone, ok, reason)
        if not called then
          Runtime.reportError(modId, "portable script completion failed: " .. message(err))
        end
      end
    end
    local function check()
      local valid, reason = token.valid()
      if not valid then
        token.finish(false, reason)
      end
      return valid
    end
    local function owned(state, step)
      token.ui[#token.ui + 1] = state
      local update = state.update
      function state:update(...)
        if not check() or token.step ~= step or game.stack:top() ~= self then
          return
        end
        local ok, err = engine(update, self, ...)
        if not ok then
          token.finish(false, "native UI failed: " .. message(err))
        end
      end
      return state
    end
    local function dialog(ctx, text, asking, step)
      local TextBox = require("src.render.TextBox")
      local box, answered
      local function answer(value)
        if answered or token.step ~= step or not check() then
          return
        end
        answered = true
        token.waitingUI = nil
        ctx.lastCheck = value
        runner:resume()
      end
      box = TextBox.new(game, TextBox.fromProse(text), function()
        if not asking and not contains(token.stack, box) then
          answer(nil)
        end
      end)
      if asking then
        local update, pushed, selected = box.update, false, nil
        box.choice = function(yes)
          if token.step ~= step or not check() or not selected or contains(token.stack, selected) then
            return
          end
          remove(token.stack, box)
          answer(yes)
        end
        function box:update(dt)
          if self.done and (self.holdFrames or 0) <= 0 and not pushed then
            pushed, self.choicePushed = true, true
            local Choice = require("src.ui.ChoiceBox")
            local geometry = self.choiceBox or {}
            selected = owned(
              Choice.new(
                game,
                self.choice,
                { anchor = "bottom", tx = geometry.tx, ty = geometry.ty, tw = geometry.tw, th = geometry.th }
              ),
              step
            )
            token.waitingUI = selected
            game.stack:push(selected)
          else
            update(self, dt)
          end
        end
      end
      owned(box, step)
      token.waitingUI = box
      game.stack:push(box)
      runner:yield()
    end
    local function choice(ctx, labels, opts, step)
      local Menu = require("src.ui.Menu")
      local items, menu, answered = {}, nil, false
      local function pick(index)
        if answered or token.step ~= step or not check() or contains(token.stack, menu) then
          return
        end
        answered = true
        token.waitingUI = nil
        ctx.lastCheck, ctx.lastChoice = index == 1, { index = index, label = labels[index] }
        runner:resume()
      end
      for i, label in ipairs(labels) do
        items[i] = {
          label = label,
          onSelect = function()
            pick(i)
          end,
        }
      end
      menu = owned(
        Menu.new(game, items, {
          onCancel = function()
            pick(opts.cancel)
          end,
        }),
        step
      )
      menu.index = opts.default
      token.waitingUI = menu
      game.stack:push(menu)
      runner:yield()
    end
    function runner:exec(compiled, ctx)
      local pc, slice = 1, 0
      while pc <= #compiled do
        if not check() then
          return
        end
        if slice >= Program.SLICE then
          self.waitingFrames = 1
          self:yield()
          slice = 0
          if not check() then
            return
          end
        end
        token.steps, slice = token.steps + 1, slice + 1
        if token.steps > Program.MAX_STEPS then
          error("portable script instruction budget exceeded", 0)
        end
        local row = compiled[pc]
        local verb = row[1]
        token.step = {}
        self.lastRow = verb .. " (portable row " .. pc .. ")"
        ctx.script, ctx.pc = compiled, pc
        if State.ARITY[verb] then
          state(ctx, row)
        elseif verb == "set_flag" or verb == "clear_flag" then
          local ok, reason = flag(row[2], verb == "set_flag", true)
          if not ok then
            error(reason, 0)
          end
        elseif verb == "check_flag" then
          local value, reason = flag(row[2])
          if value == nil then
            error(reason, 0)
          end
          ctx.lastCheck = value
        elseif verb == "wait_flag" then
          local left = row[3]
          self.waitingCheck = function()
            if not check() then
              return false
            end
            local value, reason = flag(row[2])
            if value == nil then
              error(reason, 0)
            end
            if value then
              return true, true
            end
            if left then
              left = left - 1
              if left <= 0 then
                return true, false
              end
            end
            return false
          end
          ctx.lastCheck = self:yield()
        elseif verb == "wait" then
          self.waitingFrames = row[2]
          self:yield()
        elseif verb == "show_text" or verb == "ask" then
          dialog(ctx, row[2], verb == "ask", token.step)
        elseif verb == "choice" then
          choice(ctx, row[2], row[3], token.step)
        elseif verb == "end" then
          return
        elseif
          verb == "jump"
          or verb == "jump_if_true" and ctx.lastCheck
          or verb == "jump_if_false" and not ctx.lastCheck
        then
          pc = row[2] - 1
        end
        pc = pc + 1
      end
    end
    local update = Runner.update
    function runner:resume(...)
      if not check() or not self.co or coroutine.status(self.co) == "running" then
        return
      end
      local ok, err = coroutine.resume(self.co, ...)
      if not ok then
        Runtime.reportError(modId, "portable script failed: " .. message(err))
        token.finish(false, "script failed: " .. message(err))
      elseif not token.done and coroutine.status(self.co) == "dead" then
        token.finish(true)
      end
    end
    function runner:update(...)
      if not check() or game.stack:top() ~= ow then
        return
      end
      local ok, err = engine(update, self, ...)
      if not ok then
        token.finish(false, "script update failed: " .. message(err))
      end
    end
    function runner:run()
      error("portable script owns this runner", 0)
    end
    -- Session/argument checks above do not mutate gameplay. Admission starts
    -- here; subsequent native failures complete through onDone(false, reason).
    active, runs[game], ow.runner = token, token, runner
    runner.ctx = runner:makeContext({
      source = { modId = modId, mapId = ow.map.id, hook = "queueScript", strict = true },
    })
    runner.co = coroutine.create(function()
      runner:exec(program, runner.ctx)
    end)
    if Runtime.wants("script.started") then
      Runtime.emit("script.started", { ctx = runner.ctx })
    end
    local ok, err = engine(runner.resume, runner)
    if not ok then
      token.finish(false, "script start failed: " .. message(err))
    end
    return true
  end
  function world:queueScript(rows, options)
    local ok, result, reason = engine(queue, rows, options)
    if not ok then
      return nil, "portable script validation failed"
    end
    return result, reason
  end
  function world:cancelScript()
    if not active or active.done then
      return false, "no portable script"
    end
    active.finish(false, "script cancelled")
    return true
  end
  return setmetatable(world, {
    __index = function(_, key)
      local value = native()
      local member = value and value[key]
      if type(member) == "function" then
        return function(_, ...)
          return member(value, ...)
        end
      end
      return member
    end,
  })
end
function Scripts.wrap(mt, api, loader, manifest)
  local format = manifest.script_format or "native"
  api.scriptFormat = format
  if format ~= "unified" then
    return mt
  end
  local index = mt.__index
  local world = facade(loader, manifest.id, function()
    return index(api, "world")
  end)
  mt.__index = function(self, key)
    if key == "world" then
      return world
    end
    return index(self, key)
  end
  if api.supports then
    local supports = api.supports
    function api:supports(surface, name)
      if surface == "scripts" then
        if Program.supports(name) then
          return true
        end
        return false, "unsupported portable script command"
      end
      if surface == "world" and (name == "queueScript" or name == "cancelScript") then
        return true
      end
      return supports(self, surface, name)
    end
  end
  return mt
end
return Scripts
