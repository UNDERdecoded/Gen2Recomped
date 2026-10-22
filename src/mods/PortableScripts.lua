-- Per-mod portable dialogue programs. An isolated native runner owns the
-- foreground until completion, then returns the idle runner it borrowed.
local Program = require("src.mods.ScriptProgram")
local Runtime = require("src.mods.Runtime")
local Flags = require("src.mods.Api3Flags")
local State = require("src.mods.ScriptState")
local Gifts = require("src.mods.ScriptGifts")
local Audio = require("src.mods.ScriptAudio")
local Fields = require("src.mods.ScriptFields")
local DialogueAudio = require("src.mods.ScriptDialogueAudio")
local Shops = require("src.mods.ScriptShops")
local Battles = require("src.mods.ScriptBattles")
local Travel = require("src.mods.ScriptTravel")
local Movement = require("src.mods.ScriptMovement")
local WorldEdits = require("src.mods.ScriptWorldEdits")
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
      elseif token.shop then
        token.shop.refresh()
      elseif token.travel then
        token.travel.tick()
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
  local nativeGame, nativeWorld
  local function battleWorld(game)
    if nativeGame ~= game then
      nativeWorld = require("src.world.WorldAPI").new(game, modId)
      nativeGame = game
    end
    return nativeWorld
  end
  local function ownedBattle(game, ow)
    if
      active
      and runs[game] == active
      and not active.done
      and active.world == ow
      and ow.runner == active.runner
      and game.stack:top() == ow
      and active.valid()
    then
      return true
    end
    return nil, "portable script does not own this world"
  end
  local function provider()
    return current(loader)
  end
  local startWild = require("src.mods.Api3WildBattle").new(
    loader,
    modId,
    provider,
    battleWorld,
    licensed,
    require,
    ownedBattle
  )
  local startTrainer = require("src.mods.Api3WildBattle").new(
    loader,
    modId,
    provider,
    battleWorld,
    licensed,
    require,
    ownedBattle,
    Battles.nativeTrainer
  )
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
    local fields, fieldsReason = Fields.prepare(game, modId, program)
    if not fields then
      return nil, fieldsReason
    end
    local dialogueAudio, dialogueReason = DialogueAudio.prepare(loader, game, program)
    if not dialogueAudio then
      return nil, dialogueReason
    end
    local audio, audioReason = Audio.prepare(game, program)
    if not audio then
      return nil, audioReason
    end
    local state, reason = State.prepare(loader, game, ow, program)
    if not state then
      return nil, reason
    end
    local gift, giftReason = Gifts.prepare(loader, game, ow, program)
    if not gift then
      return nil, giftReason
    end
    local battleOK, battleReason = Battles.prepare(loader, game, ow, program, flag)
    if not battleOK then
      return nil, battleReason
    end
    local travel, travelReason = Travel.prepare(game, ow, modId, program, loader)
    if not travel then
      return nil, travelReason
    end
    local edit, editReason = WorldEdits.prepare(game, ow, modId, program, true)
    if not edit then
      return nil, editReason
    end
    local movement, moveReason = Movement.prepare(ow, program, true)
    if not movement then
      return nil, moveReason
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
      ownedUI = {},
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
        or not token.travel and not token.mutating and ow.map ~= token.map
        or not token.travel and ow.map.id ~= token.mapId
        or ow.player ~= token.player
        or not token.travel and (ow.player.cellX ~= token.x or ow.player.cellY ~= token.y) and not (token.move and token.move.position())
        or not token.travel and not token.mutating and ow.runner ~= runner
        or token.move and not token.move.live()
        or token.shop and not token.shop.valid()
        or GameVersion.get() ~= token.version
        or Runtime.hooks ~= loader.hooks
        or Runtime.events ~= loader.events
        or game.linkSession
        or game.linkNet and not game.linkNet.closed
        or not token.travel and ow.transitioning
        or token.travel and not token.travel.valid()
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
      if token.travel then
        token.travel.retired = true
      end
      if token.move then
        token.move.cancel()
      end
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
    local function mutate(operation)
      if not check() then
        return nil, "script session changed"
      end
      token.mutating = true
      local called, value, reason = engine(operation)
      if
        not token.done
        and current(loader) == game
        and game.save == token.save
        and game.data == token.data
        and game.stack == token.stack
        and ow.player == token.player
      then
        if
          called
          and value
          and ow.map ~= token.map
          and ow.map
          and ow.map.id == token.mapId
          and ow.runner ~= runner
        then
          token.original = ow.runner
          ow.runner = runner
        end
        if called and value and ow.map and ow.map.id == token.mapId then
          token.map = ow.map
        end
      end
      token.mutating = nil
      if not check() then
        return nil, "script session changed"
      end
      if not called then
        return nil, message(value)
      end
      return value, reason
    end
    local discover
    local function snapshot()
      local before = {}
      for _, state in ipairs(game.stack.states) do
        before[state] = true
      end
      return before
    end
    local function owned(state, step)
      if token.ownedUI[state] then
        return state
      end
      token.ownedUI[state] = true
      token.ui[#token.ui + 1] = state
      local update = state.update
      function state:update(...)
        if not check() or token.step ~= step or game.stack:top() ~= self then
          return
        end
        local before = token.nativeStep == step and snapshot()
        local previous, phase, priorBefore = token.executingUI, token.uiPhase, token.uiBefore
        if token.shop and token.shop.step == step then
          token.executingUI, token.uiPhase, token.uiBefore = self, self.asking, before
        end
        local ok, err = engine(update, self, ...)
        if before then
          discover(before, step)
        end
        if token.shop then
          token.shop.refresh()
        end
        token.executingUI, token.uiPhase, token.uiBefore = previous, phase, priorBefore
        if not ok then
          token.finish(false, "native UI failed: " .. message(err))
        end
      end
      if token.shop then
        token.shop.attach(state)
      end
      return state
    end
    discover = function(before, step)
      if token.done or token.step ~= step or token.travel or token.battling then
        return
      end
      for _, state in ipairs(game.stack.states) do
        if not before[state] then
          owned(state, step)
          if token.nativeStep == step and not token.shop then
            token.waitingUI = state
          end
        end
      end
    end
    local function nativeGift(ctx, row)
      local step = token.step
      local bound = setmetatable({
        resume = function(_, ...)
          if token.step == step and check() then
            runner:resume(...)
          end
        end,
      }, { __index = runner, __newindex = runner })
      local revision = 0
      local proxy = setmetatable({
        portableCallback = function(callback)
          local expected, fired = revision, false
          return function(...)
            if fired or expected ~= revision or token.step ~= step or not check() then
              return
            end
            fired = true
            revision = revision + 1
            return callback(...)
          end
        end,
        runner = bound,
        portableAlive = function()
          return token.step == step and check()
        end,
      }, { __index = ctx, __newindex = ctx })
      token.nativeStep = step
      local result = gift(proxy, row)
      token.nativeStep = nil
      token.waitingUI = nil
      return result
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
      local opts = dialogueAudio.options(ctx, asking, function()
        return not answered
          and token.step == step
          and check()
          and box ~= nil
          and contains(token.stack, box)
          and token.stack:top() == box
      end)
      box = TextBox.new(game, TextBox.fromProse(text), function()
        if not asking and not contains(token.stack, box) then
          answer(nil)
        end
      end, opts)
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
          if self.done and (self.holdFrames or 0) <= 0 and not pushed and not self.auto then
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
    local function shop(ctx, row)
      local stock, validate = Shops.plan(loader, game, ow, row)
      if not stock then
        error(validate, 0)
      end
      local step, complete, root = token.step, false, nil
      local service = { step = step }
      function service.valid()
        if not complete and root and not contains(token.stack, root) and token.executingUI ~= root then
          return false
        end
        return validate()
      end
      local invoke
      service.attach = require("src.mods.ScriptShopUI").new({
        alive = function(state)
          return not complete
            and token.shop == service
            and token.step == step
            and check()
            and (
              game.stack:top() == state
              or token.executingUI == state
              or token.executingUI
                and token.ownedUI[token.executingUI]
                and (contains(token.stack, state) or token.uiBefore and token.uiBefore[state])
            )
        end,
        phase = function(state)
          return token.executingUI == state and token.uiPhase or nil
        end,
        invoke = function(state, fn, ...)
          return invoke(state, fn, ...)
        end,
      })
      function service.refresh()
        if token.done then
          return
        end
        if not token.executingUI then
          for i = #token.ui, 1, -1 do
            if not contains(token.stack, token.ui[i]) then
              token.ownedUI[token.ui[i]] = nil
              table.remove(token.ui, i)
            end
          end
        end
        for _, state in ipairs(token.ui) do
          if contains(token.stack, state) then
            service.attach(state)
          end
        end
      end
      invoke = function(state, fn, ...)
        local previous, phase, priorBefore = token.executingUI, token.uiPhase, token.uiBefore
        local before = snapshot()
        token.executingUI, token.uiPhase, token.uiBefore = state, state.asking, before
        local result = pack(engine(fn, ...))
        discover(before, step)
        service.refresh()
        token.executingUI, token.uiPhase, token.uiBefore = previous, phase, priorBefore
        if not result[1] then
          token.finish(false, "native shop callback failed: " .. message(result[2]))
          return
        end
        return unpack(result, 2, result.n)
      end
      token.shop, token.nativeStep = service, step
      local function done()
        if not root or complete or token.step ~= step or not check() or contains(token.stack, root) then
          return
        end
        complete = true
      end
      local called, state = engine(require("src.ui.Screens").push, game, "ShopMenu", stock, done)
      if not called then
        token.shop, token.nativeStep = nil, nil
        error(state, 0)
      end
      root = state
      if token.done then
        remove(token.stack, root)
        return
      end
      owned(root, step)
      if not check() then
        return
      end
      runner.waitingCheck = function()
        return complete
      end
      runner:yield()
      token.shop, token.nativeStep = nil, nil
    end
    local function battle(ctx, row)
      local verb = row[1]
      if verb == "check_battle_result" then
        ctx.lastCheck = false
        for i = 2, #row do
          if row[i] == ctx.lastBattleResult then
            ctx.lastCheck = true
          end
        end
        return
      end
      local species, level = row[2], row[3]
      if verb == "start_battle" then
        species, level = row[3], row[4]
      end
      local step, complete, result = token.step, false, nil
      token.battling = true
      local start = verb == "start_battle" and row[2] == "trainer" and startTrainer or startWild
      local ok, why = start(species, level, function(outcome, failure)
        if complete or token.step ~= step or not check() then
          return
        end
        if not Battles.outcomes[outcome] then
          token.finish(false, failure or "invalid native battle result")
          return
        end
        complete, result = true, outcome
      end)
      if not ok then
        token.battling = nil
        error(why, 0)
      end
      if not check() then
        return
      end
      if not complete then
        runner.waitingCheck = function()
          return complete
        end
        runner:yield()
      end
      token.battling = nil
      if not check() then
        return
      end
      ctx.lastBattleResult, ctx.lastCheck = result, result == "win"
      if verb == "static_battle" and result ~= "lose" then
        if row[4] ~= nil then
          local value, reason = flag(row[4], true, true)
          if not value then
            error(reason, 0)
          end
        end
        if not check() then
          return
        end
        local npc = movement.npc
        local def = npc and npc.def
        local ref = def and (def.name or def.localId or def.index or def.id)
        if ref then
          local value, reason = require("src.mods.ScriptWorldEdits").prepare(
            game,
            ow,
            modId,
            { { "hide_object", ow.map.id, ref } }
          )
          if not value then
            error(reason, 0)
          end
          local accepted, detail = value({ "hide_object", ow.map.id, ref }, mutate)
          if not check() then
            return
          end
          if not accepted then
            error(detail, 0)
          end
        end
      end
    end
    local function warp(ctx, row)
      local plan, reason = travel(row)
      if not plan then
        error(reason, 0)
      end
      if row[1] == "remember_outdoor" then
        token.save.lastOutdoor = { id = plan.mapId, x = plan.x, y = plan.y }
        if GameVersion.generation() == 3 then
          token.save.escapeWarp = { map = plan.mapId, warpId = 255, x = plan.x, y = plan.y }
        elseif ow.rememberOutdoor then
          ow:rememberOutdoor(plan.mapId, plan.x, plan.y)
        else
          ow.lastOutdoor = token.save.lastOutdoor
        end
        return
      end
      local origin, step = ow.map, token.step
      local accepted, pending, fired, complete = nil, false, false, false
      local lease = { ui = {} }
      local remaining = 3600
      function lease.tick()
        local top = token.stack:top()
        if top == ow or lease.ui[top] then
          remaining = remaining - 1
          if remaining <= 0 then
            token.finish(false, "native warp timed out")
          end
        end
      end
      function lease.valid()
        if lease.retired then
          return false
        end
        if
          ow.map == origin
          and ow.player.cellX == token.x
          and ow.player.cellY == token.y
          and ow.runner == runner
        then
          return true
        end
        return ow.map and ow.map.id == plan.mapId and ow.player.cellX == plan.x and ow.player.cellY == plan.y
      end
      local function done()
        if fired or lease.retired then
          return
        end
        if accepted == nil then
          pending = true
          return
        end
        fired = true
        if not accepted or token.step ~= step or not check() then
          return
        end
        if
          not ow.map
          or ow.map.id ~= plan.mapId
          or ow.player.cellX ~= plan.x
          or ow.player.cellY ~= plan.y
          or ow.transitioning
        then
          token.finish(false, "native warp did not arrive")
          return
        end
        if ow.runner ~= runner then
          if not ow.runner or ow.runner:isRunning() then
            token.finish(false, "destination script is busy")
            return
          end
          token.original = ow.runner
          ow.runner = runner
        end
        token.map, token.mapId, token.x, token.y = ow.map, plan.mapId, plan.x, plan.y
        ctx.mapId, ctx.npc = plan.mapId, nil
        movement.forgetNpc()
        movement.npc = nil
        complete = true
      end
      token.travel = lease
      local statesBefore = snapshot()
      local called, value, why =
        engine(ow.startWarpTo, ow, plan.mapId, plan.x, plan.y, plan.facing, done, { via = "warp" })
      for _, state in ipairs(game.stack.states) do
        if not statesBefore[state] then
          lease.ui[state] = true
        end
      end
      accepted = called and value ~= false and not (value == nil and why ~= nil)
      if not accepted then
        lease.retired = true
        token.travel = nil
        error(called and (why or "native warp refused") or message(value), 0)
      end
      if pending then
        done()
      end
      if not check() then
        return
      end
      if not complete then
        runner.waitingCheck = function()
          return complete
        end
        runner:yield()
      end
      lease.retired = true
      if token.travel == lease then
        token.travel = nil
      end
    end
    local function move(ctx, row)
      local actor = movement.target(row)
      if not actor then
        error("native movement target unavailable", 0)
      end
      local verb, dirs = row[1], {}
      if verb == "move_player" or verb == "move_npc" then
        local at = verb == "move_player" and 2 or 3
        for i = 1, row[at + 1] or 1 do
          dirs[i] = row[at]
        end
      elseif verb == "move_npc_to" then
        local reason
        dirs, reason = Movement.path(ow, actor, row[3], row[4])
        if not dirs then
          error(reason, 0)
        end
      elseif verb == "place_npc" then
        if actor.def and actor.def.index then
          require("src.script.Commands").place_npc(ctx, actor.def.index, row[3], row[4], row[5])
          return
        end
        actor.cellX, actor.cellY, actor.px, actor.py = row[3], row[4], row[3] * 16, row[4] * 16
        actor.moving, actor.marching, actor.progress = false, false, 0
        actor.targetX, actor.targetY = nil, nil
        if row[5] then
          actor.facing = row[5]
        end
        return
      else
        local dir = verb == "face_object" and row[3] or row[2]
        if verb == "face_npc" or verb == "face_player" then
          local other = verb == "face_npc" and movement.npc or ow.player
          local dx, dy = other.cellX - actor.cellX, other.cellY - actor.cellY
          dir = math.abs(dx) > math.abs(dy) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
        end
        if actor.scriptFace then
          actor:scriptFace(dir)
        else
          actor.facing = dir
        end
        if verb == "face_object" and row[4] and row[4].hold then
          actor.timer = row[4].hold
        end
        return
      end
      for _, dir in ipairs(dirs) do
        if not check() then
          return
        end
        if actor ~= ow.player and movement.target(row) ~= actor then
          error("movement target changed", 0)
        end
        local step, completed, accepted, fired, pending = token.step, false, nil, false, false
        local sx, sy = actor.cellX, actor.cellY
        local delta = Movement.directions[dir]
        local tx, ty = sx + delta[1], sy + delta[2]
        local entries, before = {}, {}
        for _, entry in ipairs(ow.scriptMoves or {}) do
          before[entry] = true
        end
        local lease = {}
        function lease.live()
          return movement.target(row) == actor
            and (actor.cellX == sx and actor.cellY == sy or actor.cellX == tx and actor.cellY == ty)
        end
        function lease.position()
          if actor ~= ow.player then
            return false
          end
          local x, y = actor.cellX, actor.cellY
          return (x == sx and y == sy or x == tx and y == ty)
        end
        function lease.cancel()
          local removed = false
          for i = #(ow.scriptMoves or {}), 1, -1 do
            if entries[ow.scriptMoves[i]] then
              table.remove(ow.scriptMoves, i)
              removed = true
            end
          end
          local foreign = false
          for _, entry in ipairs(ow.scriptMoves or {}) do
            if entry.entity == actor then
              foreign = true
            end
          end
          if removed and not foreign then
            actor.moving, actor.marching = false, false
            actor.targetX, actor.targetY = nil, nil
            actor.px, actor.py = actor.cellX * 16, actor.cellY * 16
          end
          if token.move == lease then
            token.move = nil
          end
        end
        local function done()
          if fired then
            return
          end
          if accepted == nil then
            pending = true
            return
          end
          fired = true
          if not accepted or token.step ~= step or not check() then
            return
          end
          if actor.cellX ~= tx or actor.cellY ~= ty then
            token.finish(false, "native movement did not arrive")
            return
          end
          completed = true
          if actor == ow.player then
            token.x, token.y = tx, ty
          end
          lease.cancel()
          -- Poll completion on the next foreground logic frame. A callback
          -- beneath a foreign overlay cannot resume later script effects.
        end
        token.move = lease
        local called, value, reason = engine(ow.scriptMove, ow, actor, dir, 1, done)
        for _, entry in ipairs(ow.scriptMoves or {}) do
          if not before[entry] and entry.entity == actor then
            entries[entry] = true
          end
        end
        if token.done then
          lease.cancel()
          return
        end
        accepted = called and value ~= false and not (value == nil and reason ~= nil)
        if not accepted then
          lease.cancel()
          error(called and (reason or "native movement refused") or message(value), 0)
        end
        if pending then
          done()
        end
        if not check() then
          return
        end
        if not completed then
          local remaining = 3600
          runner.waitingCheck = function()
            remaining = remaining - 1
            if remaining <= 0 then
              token.finish(false, "native movement timed out")
            end
            return completed
          end
          runner:yield()
        end
      end
    end
    local function waitAudio(poll, ceiling, continueOnTimeout)
      if poll() then
        return
      end
      local remaining = ceiling
      runner.waitingCheck = function()
        if not check() then
          return false
        end
        if poll() then
          return true
        end
        remaining = remaining - 1
        if remaining <= 0 then
          if continueOnTimeout then
            return true
          end
          token.finish(false, "native audio timed out")
        end
        return false
      end
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
        if Fields.ARITY[verb] then
          fields(ctx, row)
        elseif DialogueAudio.ARITY[verb] then
          dialogueAudio.arm(ctx, row)
        elseif Audio.ARITY[verb] then
          audio(ctx, row, waitAudio, check)
        elseif Shops.ARITY[verb] then
          shop(ctx, row)
        elseif Battles.ARITY[verb] then
          battle(ctx, row)
        elseif Travel.ARITY[verb] then
          warp(ctx, row)
        elseif Movement.ARITY[verb] then
          move(ctx, row)
        elseif WorldEdits.ARITY[verb] then
          local value, reason = edit(row, mutate)
          if not check() then
            return
          end
          if not value then
            error(reason, 0)
          end
        elseif Gifts.ARITY[verb] then
          if nativeGift(ctx, row) == math.huge then
            return
          end
        elseif State.ARITY[verb] then
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
      local before, step = snapshot(), token.step
      token.waitingUI = nil
      local ok, err = coroutine.resume(self.co, ...)
      discover(before, token.step or step)
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
