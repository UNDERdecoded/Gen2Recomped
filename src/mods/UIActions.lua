-- Per-mod, detached UI snapshots and revision-bound native actions.
local Commands = require("src.ui.UICommands")
local Intents = require("src.mods.BattleIntents")
local Ids = require("src.mods.UnifiedIds")
local Runtime = require("src.mods.Runtime")
local Actions = {}
local function copy(v, seen)
  if type(v) ~= "table" then
    if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
      return v
    end
    return nil
  end
  seen = seen or {}
  if seen[v] then
    return seen[v]
  end
  local out = {}
  seen[v] = out
  for k, value in pairs(v) do
    if type(k) == "string" or type(k) == "number" then
      out[k] = copy(value, seen)
    end
  end
  return out
end
local function equal(a, b, seen)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= "table" then
    return a == b or (a ~= a and b ~= b)
  end
  seen = seen or {}
  if seen[a] then
    return seen[a] == b
  end
  seen[a] = b
  for k, v in pairs(a) do
    if not equal(v, b[k], seen) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end
local function engine(fn, ...)
  local owner = Runtime.currentMod
  Runtime.currentMod = nil
  local ok, a, b, c = pcall(fn, ...)
  Runtime.currentMod = owner
  return ok, a, b, c
end
local function integer(n)
  return type(n) == "number" and n >= 1 and n <= 9007199254740991 and n % 1 == 0
end
local function normalize(raw)
  if type(raw) ~= "table" or getmetatable(raw) ~= nil then
    return nil, "intent must be a plain table"
  end
  if not integer(raw.id) or not integer(raw.revision) then
    return nil, "invalid UI id or revision"
  end
  local fields = ({ select = { index = true }, back = {}, advance = {}, pocket = { direction = true } })[raw.kind]
  if not fields then
    return nil, "unknown UI intent"
  end
  for k in pairs(raw) do
    if k ~= "id" and k ~= "revision" and k ~= "kind" and not fields[k] then
      return nil, "unknown UI intent field"
    end
  end
  if raw.kind == "select" and not integer(raw.index) then
    return nil, "invalid UI row"
  end
  if raw.kind == "pocket" and raw.direction ~= -1 and raw.direction ~= 1 then
    return nil, "invalid pocket direction"
  end
  return {
    id = raw.id,
    revision = raw.revision,
    kind = raw.kind,
    index = raw.index,
    direction = raw.direction,
  }
end
function Actions.new(provider, loader, builders)
  local ids = Ids.new(loader)
  ids:entries("pokemon")
  ids:entries("items")
  local facade = setmetatable({}, { __index = builders })
  local revision, consumed = 0, 0
  local previous, oldRefs, oldControls, oldEpoch, offered
  local function refresh()
    local game = provider()
    local states = game and game.stack and game.stack.states
    local top = states and states[#states]
    if not top then
      previous, oldRefs, oldControls, oldEpoch, offered = nil, nil, nil, nil, nil
      return nil, "no UI screen"
    end
    local ok, view, refs, kind = engine(Commands.describe, game, top, Ids.new(loader))
    if not ok or not view then
      previous, oldRefs, oldControls, oldEpoch, offered = nil, nil, nil, nil, nil
      return nil, ok and refs or "UI snapshot failed"
    end
    refs.game = game
    -- Capture live eligibility, target and inventory changes even when the
    -- native screen has not rebuilt its labels yet. Never return this data.
    local controls = copy({
      party = refs.party or type(top.party) == "table" and top.party or game.save and game.save.party,
      inventory = game.save and game.save.inventory,
      bagOrder = game.save and game.save.bagOrder,
      select = top.select,
      menu = top.menu,
      submenu = top.submenu,
      swapFrom = top.swapFrom,
      switchFrom = top.switchFrom,
      softboiledFrom = top.softboiledFrom,
      hpTransfer = top.hpTransfer,
      hpTransferFrom = top.hpTransferFrom,
      forceSwitch = top.forceSwitch,
      pickOnly = top.pickOnly,
      keepOpen = top.keepOpen,
      pick = top.pick,
      store = top.store,
      sell = top.sell,
      registeredItem = game.save and game.save.registeredItem,
      cur = top.cur,
      mem = top.mem,
      page = top.page,
      top = top.top,
      done = top.done,
      waiting = top.waiting,
      shown = top.shown,
      contAdvance = top.contAdvance,
      lineIndex = top.lineIndex,
      pageIndex = top.pageIndex,
      pending = top.pending,
      trash = top.trash,
      moving = top.moving,
      lockPocket = top.lockPocket,
      resultMessage = top.resultMessage,
      message = top.message,
      selectNotice = top.selectNotice,
    })
    local state = Intents.state(game)
    if
      not equal(view, previous)
      or not Intents.sameRefs(refs, oldRefs)
      or not equal(controls, oldControls)
      or state.epoch ~= oldEpoch
    then
      revision = revision + 1
    end
    previous, oldRefs, oldControls, oldEpoch = view, refs, controls, state.epoch
    return { game = game, top = top, view = view, kind = kind, state = state }
  end
  function facade:snapshot()
    local ctx, err = refresh()
    if not ctx then
      return nil, err
    end
    local out = copy(ctx.view)
    out.revision = revision
    if ctx.state.busy then
      out.locked, out.canBack, out.canAdvance, out.canPocket = true, false, false, false
    end
    offered = revision
    return out
  end
  function facade:submit(raw)
    local intent, err = normalize(raw)
    if not intent then
      return nil, err
    end
    if intent.id <= consumed then
      return nil, "replayed UI intent"
    end
    local ctx
    ctx, err = refresh()
    if not ctx then
      return nil, err
    end
    local state, view = ctx.state, ctx.view
    if state.busy then
      return nil, "UI action is already in progress"
    end
    if intent.revision ~= revision then
      return nil, "stale UI context"
    end
    if offered ~= revision then
      return nil, "fresh UI snapshot required"
    end
    if view.locked then
      return nil, "UI is locked"
    end
    if intent.kind == "select" then
      if not view.rows[intent.index] or not view.rows[intent.index].enabled then
        return nil, "unavailable UI row"
      end
    elseif intent.kind == "back" and not view.canBack then
      return nil, "UI cannot go back"
    elseif intent.kind == "advance" and not view.canAdvance then
      return nil, "UI cannot advance"
    elseif intent.kind == "pocket" and not view.canPocket then
      return nil, "UI cannot change pocket"
    end
    -- Native work can raise after partial effects. Consume before dispatch;
    -- the shared epoch also expires snapshots held by battle/other UI facades.
    consumed, offered = intent.id, nil
    state.busy, state.epoch = true, state.epoch + 1
    local ok, failure = engine(Commands.dispatch, ctx.top, ctx.kind, view, intent)
    state.busy, state.epoch = false, state.epoch + 1
    if not ok then
      local printable, message = pcall(tostring, failure)
      return nil, "UI action failed; intent consumed" .. (printable and ": " .. message or "")
    end
    return true
  end
  return facade
end
function Actions.withCapabilities(api)
  if api.supports then
    local supports = api.supports
    function api:supports(surface, name)
      if surface == "ui" then
        if name == "snapshot" or name == "submit" then
          return true
        end
        return false, "unknown UI capability: " .. tostring(name)
      end
      return supports(self, surface, name)
    end
  end
end
return Actions
