-- Pokemon Stadium art in engine-owned screens.
--
-- STADIUM2_OVERWORLD_MODELS extracts 3D battle models from a Pokemon Stadium 2
-- cartridge the player supplies, and can render any of them to a canvas.  Its
-- own UI skin already uses that in its custom menus -- but those menus replace
-- the engine's, need the mod's whole Stadium look switched on, and go away
-- with the mod.
--
-- This is the other direction: the ENGINE's Pokedex, status screen and battle
-- keep their own layout and simply ask, per pic, "is there a Stadium render
-- for this species?".  So the option lives in the engine's OPTIONS menu, it
-- survives a mod update, and with the mod absent, disabled, or without a ROM
-- imported, every call answers nil and the caller draws the Game Boy pic it
-- always drew.  Nothing here is allowed to raise: it runs inside draws.
--
-- The model rendered is a LIVE one.  `Preview.render` owns its own clock and
-- advances a slow showroom turn on each call, so drawing once per frame is all
-- the animation needs -- there is no separate tick to schedule, and a screen
-- that draws less often simply turns more slowly rather than desynchronising.

local Logger = require("src.core.Logger")
local NativeOverlay = require("src.render.NativeOverlay")

local StadiumArt = {}

StadiumArt.MOD_ID = "STADIUM2_OVERWORLD_MODELS"

-- Resolved `PartyModelPreview`, once we have it.  A MISS is deliberately not
-- cached: this is first asked during a draw, which can happen before the mod
-- has published its exports, and a cached miss would mean "no Stadium art for
-- the rest of the session" with nothing to say so.  The re-probe is a pcall
-- into the mod's own memoising loader, so the repeated cost is a table lookup.
local preview = nil
local warned = false
local reported = false

local function modExports(game)
  local mods = game and game.mods
  local exports = mods and mods.exports
  return exports and exports[StadiumArt.MOD_ID] or nil
end

local function previewModule(game)
  if preview then return preview end
  local exports = modExports(game)
  local lib = exports and exports.lib
  if not (type(lib) == "table" and type(lib.require) == "function") then
    return nil
  end
  local ok, module = pcall(lib.require, "PartyModelPreview")
  if not (ok and type(module) == "table" and type(module.render) == "function") then
    if not warned then
      warned = true
      Logger.warn("StadiumArt: %s is loaded but has no usable "
        .. "PartyModelPreview (%s) -- Game Boy pics will be used",
        StadiumArt.MOD_ID, tostring(ok and "no render()" or module))
    end
    return nil
  end
  preview = module
  return preview
end

-- Which art a screen family should use.  One of "gb" (the four-shade
-- cartridge pic, and the default everywhere) or "stadium".
local function mode(game, key)
  local options = game and game.save and game.save.options
  local value = options and options[key]
  return value == "stadium" and "stadium" or "gb"
end

function StadiumArt.menuMode(game) return mode(game, "menuArt") end
function StadiumArt.battleMode(game) return mode(game, "battleArt") end

-- Whether the mod could serve a render at all, regardless of the options.
-- The OPTIONS rows use this to stay honest: offering STADIUM with no mod and
-- no cartridge behind it is a switch that visibly does nothing.
function StadiumArt.available(game)
  if previewModule(game) then return true end
  -- ...and SAY WHY, once.  A false here removes the OPTIONS rows entirely, so
  -- without this the failure mode is a setting that is simply not in the menu,
  -- which is indistinguishable from "this build does not have that feature".
  -- Each stage is named because they fail for different reasons: no mod
  -- installed, mod installed but disabled, mod loaded but its entry chunk died
  -- before publishing exports.
  if not reported then
    reported = true
    local mods = game and game.mods
    local exports = mods and mods.exports
    local mine = exports and exports[StadiumArt.MOD_ID]
    Logger.info("StadiumArt: no Stadium renders available -- mods=%s "
      .. "exports=%s %s=%s lib=%s. Game Boy pics will be used and the "
      .. "PKMN ART / BATTLE PKMN rows are hidden.",
      tostring(mods ~= nil), tostring(exports ~= nil),
      StadiumArt.MOD_ID, tostring(mine ~= nil),
      tostring(mine and mine.lib ~= nil))
  end
  return false
end

-- A stable render key for a caller that is not itself a screen table.
--
-- The mod caches one rig per key and reads `key.game`, so the key has to be a
-- table it can hold onto and it has to carry the game.  A battle has two
-- battlers and wants a resident model for each, so `owner` is the state to
-- hang the keys off and `slot` is whatever identifies the side.  Weak keys: a
-- battler swapped out mid-battle takes its proxy with it.
function StadiumArt.keyFor(game, owner, slot)
  if not (type(owner) == "table" and slot ~= nil) then return nil end
  local keys = rawget(owner, "_stadiumArtKeys")
  if not keys then
    keys = setmetatable({}, { __mode = "k" })
    rawset(owner, "_stadiumArtKeys", keys)
  end
  local key = keys[slot]
  if not key then
    key = { game = game }
    keys[slot] = key
  end
  return key
end

-- Hand back every rig an owner minted through keyFor.  Called from a state's
-- exit, so it must tolerate an owner that never minted one.
function StadiumArt.releaseAll(game, owner)
  local keys = type(owner) == "table" and rawget(owner, "_stadiumArtKeys")
  if not keys then return end
  for _, key in pairs(keys) do StadiumArt.release(game, key) end
  rawset(owner, "_stadiumArtKeys", nil)
end

-- Render `mon` for `screen` at up to `w` x `h`, or nil.
--
-- `screen` is the menu/battle state itself: the mod keys its rig cache on that
-- identity, so passing the live screen is what keeps one model resident per
-- open menu instead of rebuilding it per frame.  Release it when the screen
-- goes away.
function StadiumArt.render(game, screen, mon, w, h, opts)
  local module = previewModule(game)
  if not (module and screen and mon and w and h) then return nil end
  local ok, canvas = pcall(module.render, screen, mon, w, h, opts)
  if not ok then
    Logger.warn("StadiumArt: render failed, using the Game Boy pic: %s",
      tostring(canvas))
    return nil
  end
  -- render() answers `nil, info` for the ordinary "no model for this species"
  -- cases (no ROM imported, pack missing, models switched off in the mod);
  -- those are not failures and must not be logged per frame.
  return canvas or nil
end

-- Draw the Stadium render for `mon` into the (x, y, w, h) well a pic would
-- have occupied, letterboxed to keep its aspect.  Returns true when it drew,
-- so a call site reads:
--
--     if StadiumArt.drawInto(...) then return end
--     ... draw the Game Boy pic ...
--
-- The canvas comes back larger than requested (the mod overscans so animated
-- wings and tails are not clipped at the frame edge), which is why this scales
-- rather than blitting 1:1.
function StadiumArt.drawInto(game, screen, mon, x, y, w, h, opts)
  if previewModule(game) == nil then return false end
  if not (screen and mon and w and h and w > 0 and h > 0) then return false end

  -- Hand the drawing forward to the composite, where a screen pixel is a
  -- screen pixel.  Rasterising a model into a 56x56 well and then multiplying
  -- it by six throws away detail that exists and magnifies what is left: the
  -- model ends up looking like a photograph of a sprite.  The render is
  -- therefore requested at the SIZE IT WILL OCCUPY ON SCREEN, which is only
  -- known out here.
  local queued = NativeOverlay.queue(function(dx, dy, dw, dh)
    local canvas = StadiumArt.render(game, screen, mon, dw, dh, opts)
    if not canvas then return end
    local okDims, cw, ch = pcall(canvas.getDimensions, canvas)
    if not (okDims and cw and ch and cw > 0 and ch > 0) then return end
    -- the mod overscans deliberately (animated wings and tails need room
    -- before projection), so this is a fit, not a blit
    local scale = math.min(dw / cw, dh / ch)
    pcall(canvas.setFilter, canvas, "linear", "linear")
    pcall(love.graphics.draw, canvas,
      dx + (dw - cw * scale) / 2, dy + (dh - ch * scale) / 2, 0, scale, scale)
  end, x, y, w, h)
  if queued then return true end

  -- No overlay available (a headless host, a caller outside a frame): fall
  -- back to drawing in Game Boy space rather than losing the model entirely.
  local canvas = StadiumArt.render(game, screen, mon, w, h, opts)
  if not canvas then return false end
  local okDims, cw, ch = pcall(canvas.getDimensions, canvas)
  if not (okDims and cw and ch and cw > 0 and ch > 0) then return false end
  local scale = math.min(w / cw, h / ch)
  local dw, dh = cw * scale, ch * scale
  local dx, dy = x + (w - dw) / 2, y + (h - dh) / 2
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(1, 1, 1, 1)
  local okDraw = pcall(love.graphics.draw, canvas, dx, dy, 0, scale, scale)
  love.graphics.setColor(r, g, b, a)
  if not okDraw then return false end
  pcall(function()
    require("src.render.PaletteFX").markTrueColor(dx, dy, dw, dh)
  end)
  return true
end


-- Drop the rig a screen was holding.  Safe to call for a screen that never
-- had one, and safe to call twice.
function StadiumArt.release(game, screen)
  local module = previewModule(game)
  if not (module and screen and type(module.release) == "function") then return end
  pcall(module.release, screen)
end

-- Test/reload hygiene: forget the resolved module so the next call re-probes.
function StadiumArt.forget()
  preview, warned, reported = nil, false, false
end

return StadiumArt
