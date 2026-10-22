-- Real loaders, adapters and host commands, with native-shaped map/render seams.
local M = {}
local unpack = table.unpack or unpack
function M.fixture(root, backend, version)
  local codeRoot = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)/world_edits%.lua$")
  local f = dofile(codeRoot .. "/warp.lua").fixture(root, backend, version, "edits")
  local Runtime = require("src.mods.Runtime")
  local ow, game = f.ow, f.game
  local def = game.data.maps[f.home]
  local flagged =
    { index = 4, localId = 4, name = "NPC", id = "npc", x = 1, y = 1, eventFlag = "FLAG_A", flag = 7 }
  local flagless = { index = 8, localId = 8, name = "TEMP", x = 0, y = 1 }
  def.objects = { flagged, flagless }
  def.blocks = { 7, 8, 7, 8, 7, 8 }
  local tiles = {
    walkable = {},
    blocks = { [1] = {}, [8] = {}, [9] = {}, [256] = {} },
    collision = {},
    blockCells = f.gen == 3 and 1 or 2,
    blockTiles = f.gen == 3 and 2 or 4,
  }
  f.flagged, f.flagless, f.visible = flagged, flagless, { NPC = true, TEMP = true }
  f.rebuilds, f.syncs, f.reloads = 0, 0, 0
  if backend == "gen1" and f.gen == 2 then
    -- Native Gen2 object definitions use list keys; public refs are still 1-based.
    flagged.index, flagless.index, flagged.eventFlag = 1, 2, 7
    ow.map = require("src.world.gen2.Map").new(def, tiles)
  elseif backend == "gen1" and f.gen == 3 then
    -- Native Gen3 uses the reflected layout and field override service.
    local overrides = {}
    def.midLayout.midAt = function(_, x, y)
      return def.blocks[y * def.width + x + 1]
    end
    f.field.metatileOverrideAt = function(_, x, y)
      return overrides[y * 1024 + x]
    end
    f.field.setMetatile = function(x, y, block)
      overrides[y * 1024 + x] = { metatile = block }
      f.rebuilds = f.rebuilds + 1
      Runtime.emit("world.block_replaced", { mapId = f.home, bx = x, by = y, block = block })
    end
    package.loaded["src.core.game3.objects"] = {
      _defs = { flagged, flagless },
      addObject = function(id)
        local obj = id == flagged.localId and flagged or flagless
        f.visible[obj.name] = true
        if obj.flag then
          game.save.flags[obj.flag] = false
        end
      end,
      removeObject = function(id)
        local obj = id == flagged.localId and flagged or flagless
        f.visible[obj.name] = false
        if obj.flag then
          game.save.flags[obj.flag] = true
        end
      end,
    }
  else
    ow.map = require("src.world.Map").new(def, tiles)
  end
  ow.map.renderer = {
    rebuild = function()
      f.rebuilds = f.rebuilds + 1
    end,
  }
  function ow:replaceBlock(x, y, block)
    self.map:setBlock(x, y, block)
    self.map.renderer:rebuild()
    self.map.blocksDirty = nil
    Runtime.emit("world.block_replaced", { mapId = self.map.id, bx = x, by = y, block = block })
  end
  function ow:changeBlock(x, y, block)
    self.map.blocks[y * self.map.width + x + 1] = block
    self.map.renderer:rebuild()
    Runtime.emit("world.block_replaced", { mapId = self.map.id, bx = x, by = y, block = block })
  end
  function ow:appearObject(id)
    local obj = def.objects[id - 1]
    f.visible[obj.name] = true
    if obj.eventFlag then
      game.save.flags[obj.eventFlag] = false
    end
  end
  function ow:disappearObject(id)
    local obj = def.objects[id - 1]
    f.visible[obj.name] = false
    if obj.eventFlag then
      game.save.flags[obj.eventFlag] = true
    end
  end
  function ow:syncObjectVisibility(obj)
    f.syncs = f.syncs + 1
    local save = game.save
    local session = f.gen == 2 and save.g2ObjectToggles or save.gen3SessionObjects
    local key = f.gen == 2 and obj.name or obj.index
    local value = session and session.mapId == f.home and session[key]
    if obj.eventFlag and save.flags and save.flags[obj.eventFlag] ~= nil then
      value = not save.flags[obj.eventFlag]
    end
    f.visible[obj.name] = value == nil and true or value
  end
  function ow:setMap(id, x, y, facing, opts)
    f.reloads = f.reloads + 1
    assert(id == f.home and x == 0 and y == 0 and facing == "left", "seamless refresh preserves player")
    assert(opts.seamless and opts.keepMusic and opts.via == "reload")
    for _, obj in ipairs(def.objects) do
      local toggles = game.save.objectToggles[id]
      if toggles[obj.name] ~= nil then
        f.visible[obj.name] = toggles[obj.name]
      end
    end
  end
  function f:flagValue()
    local key = backend == "gen1" and self.gen > 1 and 7 or "FLAG_A"
    return game.save.flags[key]
  end
  return f
end
function M.run(root, backend, version)
  local Json = require("src.link.Json")
  local f = M.fixture(root, backend, version)
  local report = { invalid = {}, toggles = {}, blocks = {} }
  local function unchanged()
    assert(#f.exports.events() == 0 and f.rebuilds == 0 and f.reloads == 0 and f.syncs == 0)
    assert(next(f.game.save.flags) == nil and f.game.save.objectToggles == nil)
    assert(f.visible.NPC and f.visible.TEMP and f.player.cellX == 0 and f.player.cellY == 0)
  end
  local function refusal(method, args, reason)
    local ok, why = f.exports[method](unpack(args, 1, args.n or #args))
    assert(ok == nil and why == reason, tostring(why) .. " ~= " .. reason)
    unchanged()
    report.invalid[#report.invalid + 1] = why
  end
  for _, bad in ipairs({ false, "", "bad\nname", string.rep("x", 257) }) do
    refusal("toggle", { bad, "NPC", false }, "invalid object toggle")
    refusal("toggle", { f.home, bad, false }, "invalid object toggle")
  end
  for _, bad in ipairs({ -1, 0.5, math.huge, 0 / 0 }) do
    refusal("toggle", { f.home, bad, false }, "invalid object toggle")
  end
  refusal("toggle", { "UNKNOWN", "NPC", false }, "unknown map: UNKNOWN")
  refusal("toggle", { f.home, "NPC", "yes" }, "invalid object toggle")
  for _, bad in ipairs({ -1, 0.5, math.huge, 0 / 0, "7", false, f.gen == 3 and 1024 or 256 }) do
    refusal("replace", { 0, 0, bad }, "invalid block id")
  end
  for _, bad in ipairs({ -1, 0.5, math.huge, 0 / 0, "0", false }) do
    refusal("replace", { bad, 0, 7 }, "invalid block coordinates")
    refusal("replace", { 0, bad, 7 }, "invalid block coordinates")
  end
  refusal("replace", { 2, 0, 7 }, "block coordinates out of bounds")
  refusal("replace", { 0, 3, 7 }, "block coordinates out of bounds")
  if f.gen ~= 3 then
    refusal("replace", { 0, 0, 9 }, "unknown block id")
  end
  if f.gen > 1 then
    refusal("toggle", { f.dest, "NPC", false }, "map is not active: " .. f.dest)
    refusal("toggle", { f.home, "UNKNOWN", false }, "no such object: UNKNOWN")
    refusal("toggle", { f.home, 0, false }, "no such object: 0")
  end
  for _, state in ipairs({ "overlay", "moving", "script", "transition" }) do
    local other = M.fixture(root, backend, version)
    if state == "overlay" then
      other.game.stack.states[2] = {}
      other.busy = true
    elseif state == "moving" then
      other.player.moving = true
    elseif state == "script" then
      other.busy = true
      other.ow.runner.isRunning = function()
        return true
      end
      if other.field then
        package.loaded["src.core.game3.scripting.space"] =
          { vm = {
            isRunning = function()
              return true
            end,
          } }
      end
    else
      other.busy, other.ow.transitioning = true, true
      if other.field then
        other.field.locked = true
      end
    end
    for _, method in ipairs({ "toggle", "replace" }) do
      local ok, why
      if method == "toggle" then
        ok, why = other.exports.toggle(other.home, "NPC", false)
      else
        ok, why = other.exports.replace(0, 0, 7)
      end
      assert(ok == nil and type(why) == "string" and #other.exports.events() == 0)
    end
  end
  f = M.fixture(root, backend, version)
  for _, visible in ipairs({ false, true, true, false }) do
    assert(f.exports.toggle(f.home, "NPC", visible))
    assert(f.visible.NPC == visible and f.visible.TEMP == true)
    if f.gen > 1 then
      assert(f:flagValue() == not visible)
    end
    report.toggles[#report.toggles + 1] = { visible = f.visible.NPC, flag = f:flagValue() }
  end
  -- Numeric refs retain native generation meaning: Gen1 a key, Gen2 list
  -- position, Gen3 local id. A portable mod queries the active map definition.
  if f.gen > 1 then
    assert(f.exports.toggle(f.home, f.gen == 2 and 2 or 8, false))
    assert(not f.visible.TEMP)
    assert(f.exports.toggle(f.home, "TEMP", true))
    assert(f.visible.TEMP)
  else
    assert(f.exports.toggle(f.dest, "LATER", false))
    assert(f.game.save.objectToggles[f.dest].LATER == false)
  end
  for _, op in ipairs({ { 0, 0, 8 }, { 1, 2, f.gen == 3 and 1023 or 255 }, { 0, 0, 0 } }) do
    assert(f.exports.replace(unpack(op)))
    local value, metadata = f.exports.read(f.home, op[1], op[2])
    assert(value == op[3] and metadata.coordinateBase == 0 and metadata.tileSize == (f.gen == 3 and 16 or 32))
    report.blocks[#report.blocks + 1] = { x = op[1], y = op[2], block = value, kind = metadata.kind }
  end
  assert(f.rebuilds == 3 and f.player.cellX == 0 and f.player.cellY == 0)
  assert(#f.loader.errors == 0)
  report.events = f.exports.events()
  report.busy = true
  print("API3_CONTRACT " .. Json.encode(report))
  return report
end
return M
