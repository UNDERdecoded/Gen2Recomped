-- Screen id -> factory resolution.  The screens registry (Data.screens)
-- wins; engine screens are the require fallback, so a mod-free boot
-- resolves every id to the exact module it required before.  One cache,
-- dropped with the rest of the asset caches on dev-mode hot reload.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")

local Screens = {}

-- ids whose builtin module is not under src/ui/
local BUILTIN = {
  ManagerState = "src.mods.ManagerState",
}

local cache = {}

local function builtinFor(id)
  return require(BUILTIN[id] or ("src.ui." .. id))
end

-- What to show when a mod screen cannot be constructed.
--
-- The old recovery was `builtinFor(id).new(game, ...)` unconditionally, and a
-- MOD-OWNED id has no builtin by definition -- the id is the mod's own.  So
-- requiring it raised "module 'src.ui.<Id>' not found" OUT of Screens.push,
-- into whatever was pushing: a party-menu update, a script step, a battle
-- callback, all places where a raise ends the game.  The rescue was strictly
-- worse than the failure, and it hid it -- the reported error named a module
-- nobody wrote instead of the mod that broke.
--
-- Callers rely on push returning an instance, so this always returns one.
local function noticeScreen(game, id, err)
  local text = ("SCREEN FAILED\n\n%s\n\n%s"):format(tostring(id), tostring(err))
  return {
    screenId = id,
    isOpaque = true,
    update = function()
      if game.input and game.input:wasPressed("b") then game.stack:pop() end
    end,
    draw = function()
      -- Required here, not at the top of the file: Screens is pulled in early
      -- and the render stack is not needed to resolve an id.
      local Font = require("src.render.Font")
      Font.drawBox(0, 0, 20, 18)
      local y = 8
      for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        while #line > 18 do            -- 18 chars is the interior at one tile in
          Font.draw(line:sub(1, 18), 8, y)
          line, y = line:sub(19), y + 8
        end
        Font.draw(line, 8, y)
        y = y + 8
        if y > 136 then break end
      end
    end,
  }
end

local function resolve(game, id)
  local hit = cache[id]
  if hit then return hit end
  local screens = game and game.data and game.data.screens
  local record = screens and screens[id]
  local factory
  if record then
    -- registry record: { new = fn } or a bare function (05-registry-system)
    factory = (type(record) == "function") and { new = record } or record
    factory.__modOwned = true
  else
    factory = builtinFor(id)
  end
  cache[id] = factory
  return factory
end

function Screens.get(game, id)
  return resolve(game, id)
end

function Screens.push(game, id, ...)
  local factory = resolve(game, id)
  local inst
  if factory.__modOwned then
    -- A broken mod screen degrades, and the degrade itself cannot raise.
    local ok, result = pcall(factory.new, game, ...)
    if ok and result then
      inst = result
    else
      Logger.error("mod screen '%s' failed: %s", id, tostring(result))
      cache[id] = nil
      -- Only where a builtin genuinely exists -- an engine id a mod overrode.
      local okBuiltin, builtin = pcall(builtinFor, id)
      if okBuiltin and type(builtin) == "table" and type(builtin.new) == "function" then
        local okNew, built = pcall(builtin.new, game, ...)
        if okNew and built then
          inst = built
        else
          Logger.error("builtin screen '%s' also failed: %s", id, tostring(built))
        end
      end
      inst = inst or noticeScreen(game, id, result)
    end
  else
    inst = factory.new(game, ...)
  end
  inst.screenId = inst.screenId or id
  game.stack:push(inst)
  return inst
end

function Screens.invalidate()
  cache = {}
end

Assets.register(Screens.invalidate)

return Screens
