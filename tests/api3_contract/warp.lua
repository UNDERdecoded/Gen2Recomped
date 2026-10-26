-- Shared driver, real production loaders/adapters, native-shaped world seams.
-- No backend distinction is passed into the mod files or public assertions.
local M = {}
local unpack = table.unpack or unpack
local function read(path)
  local f = assert(io.open(path, "rb"))
  local value = f:read("*a")
  f:close()
  return value
end
function M.fixture(root, backend, version)
  local Version = require("src.core.GameVersion")
  local Runtime = require("src.mods.Runtime")
  Version.set(version)
  local gen = Version.generation(version)
  local codeRoot = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)/warp%.lua$")
  local data = dofile(codeRoot .. "/run.lua").dataFor(backend, gen)
  local prefix = gen == 3 and (version == "emerald" and "EM_" or "FR_") or ""
  local home, dest = prefix .. "HOME", prefix .. "DEST"
  for _, id in ipairs({ home, dest }) do
    data.maps[id] = {
      id = id,
      width = 2,
      height = 3,
      tileset = "FIX",
      blocks = { 1 },
      midLayout = gen == 3 and { width = 2, height = 3 } or nil,
    }
    if data.gen2Maps then
      data.gen2Maps[id] = data.maps[id]
    end
  end
  local files = {}
  for _, name in ipairs({ "manifest.json", "main.lua" }) do
    files["mods/warp/" .. name] = read(root .. "/mods/warp/" .. name)
  end
  local fs = {
    read = function(path)
      return files[path]
    end,
    load = function(path)
      return loadstring(assert(files[path]), "@" .. path)
    end,
    getInfo = function(path)
      if files[path] then
        return { type = "file", size = #files[path] }
      end
      if path == "mods" or path == "mods/warp" then
        return { type = "directory" }
      end
    end,
    getDirectoryItems = function(path)
      return path == "mods" and { "warp" } or {}
    end,
  }
  local loader = require("src.mods.Loader").new({ fs = fs, dev = false, generation = gen, version = version })
  local f = { loader = loader, gen = gen, home = home, dest = dest, trace = {}, busy = false }
  loader._game = function(_, loadedOnly)
    assert(backend ~= "gen2" or loadedOnly, "no Game bootstrap")
    return f.live
  end
  assert(loader:load(data), table.concat(loader.errors, "; "))
  f.exports = assert(loader.exports.warp)
  local save = { party = {}, flags = {}, modData = {} }
  local player = { cellX = 0, cellY = 0, facing = "left" }
  local ow = {
    isOverworld = true,
    player = player,
    map = { id = home, def = data.maps[home] },
    maps = data.maps,
    runner = {
      isRunning = function()
        return false
      end,
    },
    scriptMoves = {},
  }
  local stack = { states = { ow } }
  function stack:top()
    return self.states[#self.states]
  end
  local game = { data = data, save = save, session = save, stack = stack, phase = "field", overworld = ow }
  f.game, f.live, f.ow, f.player = game, game, ow, player
  function f:dispatch(id, x, y, facing, opts)
    self.trace[#self.trace + 1] = {
      mapId = id,
      x = x,
      y = y,
      facing = facing,
      arrive = opts.arrive,
      keepMusic = opts.keepMusic,
      fade = opts.fade,
    }
    self.callback = opts.onDone
    self.destination = { id, x, y, facing }
    self.busy, ow.transitioning = true, true
    if self.synchronous then
      self:arrive()
      self:complete("sync", nil, "tail")
    end
    if self.failure == "throw" then
      error("native warp probe", 0)
    end
    if self.failure == "refuse" then
      return false, "warp refused"
    end
    return true
  end
  function ow:startWarpTo(id, x, y, facing, onDone, opts)
    local arrive = self.arriveWarp
    self.arriveWarp = nil
    local ok, why = f:dispatch(
      id,
      x,
      y,
      facing,
      { onDone = onDone, arrive = arrive, keepMusic = opts and opts.keepMusic, fade = opts and opts.fade }
    )
    if not ok then
      return ok, why
    end
    -- Native Gen 1/controller returns no value on successful admission.
  end
  function ow:acceptsMenuInput()
    return not (f.busy or player.moving)
  end
  function ow:warpToMapId(id, x, y, facing, opts)
    return f:dispatch(id, x, y, facing, opts or {})
  end
  if backend == "gen1" and gen == 2 then
    game.world = ow
  end
  if backend == "gen1" and gen == 3 then
    local field = { running = true, _game = game, _session = save, _locks = {} }
    f.field = field
    package.loaded["src.core.game3.field"] = field
    package.loaded["src.core.game3.runtime"] = {
      getSession = function()
        return game.session
      end,
      uiBusy = function()
        return f.busy
      end,
    }
    local map = {
      current = home,
      currentDef = function()
        return data.maps[f.map.current]
      end,
    }
    f.map = map
    package.loaded["src.core.game3.map"] = map
    package.loaded["src.core.game3.player"] = player
    package.loaded["src.core.game3.scripting.space"] = {}
    package.loaded["src.core.game3.battle.init"] = {
      isActive = function()
        return false
      end,
    }
    package.loaded["src.core.game3.warp"] = {
      isBusy = function()
        return f.busy
      end,
      request = function(_, owner, id, x, y, facing, opts)
        assert(owner == game, "native request retains Game")
        return f:dispatch(id, x, y, facing, opts)
      end,
    }
  end
  function f:arrive(id)
    local d = assert(self.destination)
    local from = ow.map.id
    Runtime.emit("map.exited", { mapId = from, toMapId = id or d[1] })
    ow.map = { id = id or d[1], def = data.maps[id or d[1]] }
    player.cellX, player.cellY, player.facing = d[2], d[3], d[4]
    if self.map then
      self.map.current = ow.map.id
    end
    Runtime.emit("map.entered", { mapId = ow.map.id, fromMapId = from, via = "warp", map = ow.map })
  end
  function f:complete(...)
    self.busy, ow.transitioning = false, false
    if self.callback then
      self.callback(...)
    end
  end
  function f:update()
    local name = backend == "gen1" and "core.update" or "input.step"
    return loader.hooks:call(name, function()
      return "updated", nil, "tail"
    end, game, 0)
  end
  return f
end
function M.run(root, backend, version)
  local Runtime = require("src.mods.Runtime")
  local Json = require("src.link.Json")
  local report = { invalid = {}, busy = {}, successful = {} }
  local function fixture()
    return M.fixture(root, backend, version)
  end
  local f = fixture()
  local function refused(args, expected)
    local before = #f.trace
    local ok, why = f.exports.request(unpack(args, 1, args.n or #args))
    assert(ok == nil and why == expected, tostring(why) .. " ~= " .. expected)
    assert(#f.trace == before and f.ow.map.id == f.home and f.player.cellX == 0)
    assert(f.ow.arriveWarp == nil and #f.exports.results().events == 0)
    report.invalid[#report.invalid + 1] = why
  end
  refused({ false, 0, 0 }, "invalid map id")
  refused({ "", 0, 0 }, "invalid map id")
  refused({ "bad\nmap", 0, 0 }, "invalid map id")
  refused({ string.rep("x", 257), 0, 0 }, "invalid map id")
  refused({ "UNKNOWN", 0, 0 }, "unknown map: UNKNOWN")
  for _, coordinate in ipairs({ -1, 0.5, math.huge, -math.huge, 0 / 0, "0", false }) do
    refused({ f.dest, coordinate, 0 }, "invalid coordinates")
    refused({ f.dest, 0, coordinate }, "invalid coordinates")
  end
  local scale = f.gen == 3 and 1 or 2
  refused({ f.dest, 2 * scale, 0 }, "coordinates out of bounds")
  refused({ f.dest, 0, 3 * scale }, "coordinates out of bounds")
  refused({ f.dest, 0, 0, "north" }, "invalid facing")
  refused({ f.dest, 0, 0, "up", false }, "invalid options")
  refused({ f.dest, 0, 0, "up", { arrive = "boat" } }, "invalid arrival")
  refused({ f.dest, 0, 0, "up", { onDone = false } }, "invalid callback")
  refused({ f.dest, 0, 0, "up", { keepMusic = 1 } }, "invalid options")
  refused({ f.dest, 0, 0, "up", { fade = 1 } }, "invalid options")
  refused({ f.dest, 0, 0, "up", { extra = true } }, "unknown warp option: extra")
  if f.gen ~= 3 then
    refused({ f.dest, 0, 0, "up", { fade = false } }, "unsupported fade")
  end
  for _, lock in ipairs({ "transitioning", "moving", "script", "overlay", "modscript" }) do
    f = fixture()
    if lock == "transitioning" then
      f.ow.transitioning, f.busy = true, true
      if f.field then
        f.field.locked = true
      end
    elseif lock == "moving" then
      f.player.moving = true
    elseif lock == "script" then
      f.ow.runner.isRunning = function()
        return true
      end
      f.busy = true
      if f.field then
        package.loaded["src.core.game3.scripting.space"] =
          { vm = {
            isRunning = function()
              return true
            end,
          } }
      end
    elseif lock == "overlay" then
      f.game.stack.states[2] = {}
      f.busy = true
    else
      f.ow._modScriptLock = {}
      f.busy = true
      if f.field then
        f.field._modScriptLock = {}
      end
    end
    local ok, why = f.exports.request(f.dest, 0, 0)
    assert(ok == nil and type(why) == "string" and #f.trace == 0, lock .. ": " .. tostring(why))
    report.busy[#report.busy + 1] = lock
  end
  for _, options in ipairs({
    {},
    { arrive = "fly", keepMusic = true },
    { arrive = "teleport", keepMusic = false },
  }) do
    f = fixture()
    options.onDone = f.exports.notify
    assert(f.exports.request(f.dest, 2 * scale - 1, 3 * scale - 1, "right", options))
    assert(f.exports.results().calls == 0 and #f.trace == 1)
    local expectedArrival, expectedMusic = options.arrive, options.keepMusic
    options.arrive, options.keepMusic, options.onDone =
      "changed", true, function()
        error("mutable options")
      end
    assert(f.trace[1].arrive == expectedArrival and f.trace[1].keepMusic == expectedMusic)
    f:arrive()
    f:complete("done", nil, "tail")
    f:complete("replay")
    assert(f.exports.results().calls == 1 and f.exports.results().args.n == 3)
    assert(f.exports.results().args.first == "done" and f.exports.results().args.third == "tail")
    local location = assert(f.exports.current())
    assert(location.mapId == f.dest and location.x == 2 * scale - 1 and location.y == 3 * scale - 1)
    report.successful[#report.successful + 1] = { native = f.trace[1], result = f.exports.results() }
  end
  f = fixture()
  assert(f.exports.request(f.dest, 0, 0))
  assert(f.trace[1].facing == (f.gen == 1 and "down" or "left"))
  f:arrive()
  f:complete()
  report.defaultFacing = f.trace[1].facing
  if f.gen == 3 then
    f = fixture()
    assert(f.exports.request("DEST", 1, 2, "up", { fade = false, onDone = f.exports.notify }))
    assert(f.trace[1].mapId == f.dest and f.trace[1].fade == false)
    f:arrive()
    f:complete()
    report.gen3Alias = true
  end
  f = fixture()
  f.synchronous = true
  assert(f.exports.request(f.dest, 0, 0, "up", { onDone = f.exports.notify }))
  assert(f.exports.results().calls == 1 and f.exports.results().args.first == "sync")
  report.synchronous = true
  for _, change in ipairs({ "game", "save", "world", "bus", "owner", "other_map" }) do
    f = fixture()
    assert(f.exports.request(f.dest, 0, 0, "up", { onDone = f.exports.notify }))
    f:arrive()
    local restore
    if change == "game" then
      local old = f.live
      f.live = {}
      restore = function()
        f.live = old
      end
    elseif change == "save" then
      local old = f.game.save
      f.game.save = {}
      f.game.session = f.game.save
      restore = function()
        f.game.save = old
        f.game.session = old
      end
    elseif change == "world" then
      if backend == "gen1" and f.gen == 3 then
        local old = package.loaded["src.core.game3.field"]
        package.loaded["src.core.game3.field"] = { running = true }
        restore = function()
          package.loaded["src.core.game3.field"] = old
        end
      else
        local old = f.game.stack.states
        f.game.stack.states = {}
        f.game.overworld = nil
        f.game.world = nil
        restore = function()
          f.game.stack.states = old
          f.game.overworld = f.ow
          if f.gen == 2 then
            f.game.world = f.ow
          end
        end
      end
    elseif change == "bus" then
      local old = Runtime.events
      Runtime.events = require("src.mods.Events").new()
      restore = function()
        Runtime.events = old
      end
    elseif change == "owner" then
      f.loader:_rollback("warp")
    else
      f:arrive(f.home)
    end
    f:update()
    -- A stale native completion must suppress the callback permanently.
    f:complete("stale")
    if restore then
      restore()
    end
    f:complete("revived")
    assert(f.exports.results().calls == 0, change .. " callback survived invalidation")
  end
  report.stale = true
  f = fixture()
  assert(f.exports.request(f.dest, 0, 0, "up", {
    onDone = function()
      error("authored warp failure", 0)
    end,
  }))
  f:arrive()
  f:complete()
  f:complete()
  assert(#f.loader.errors == 1 and f.loader.errors[1]:find("warp: world warp callback failed:", 1, true))
  assert(Runtime.currentMod == nil)
  report.attribution = true
  print("API3_CONTRACT " .. Json.encode(report))
  return report
end
return M
