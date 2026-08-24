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
  return previewModule(game) ~= nil
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
    -- PUT THE FILTER BACK.  This canvas is cached and re-blitted by other
    -- passes, so leaving it bilinear made every later 1:1 draw of the same
    -- target soft -- the "blurry, menus unreadable" half of the Stadium
    -- report: pixel-art UI reaching the screen through a filter chosen for
    -- one scaled 3D pic.  The mod's own AntiAlias pass restores "nearest"
    -- for exactly this reason; this path never did.
    pcall(canvas.setFilter, canvas, "linear", "linear")
    pcall(love.graphics.draw, canvas,
      dx + (dw - cw * scale) / 2, dy + (dh - ch * scale) / 2, 0, scale, scale)
    pcall(canvas.setFilter, canvas, "nearest", "nearest")
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


-- THE PER-BATTLER SCREEN IDENTITY, which BattleState asks for and this module
-- never defined -- so turning Stadium battle art on called a nil value and
-- took the battle down on the first pic drawn.
--
-- `screen` is a cache identity, nothing more: the mod keeps one rig resident
-- per screen, so a battle needs one key per SIDE rather than one for the whole
-- state (the player's mon and the enemy's are two different models on screen
-- at once, and sharing a key would make them evict each other every frame).
-- The battler itself is that identity, and it is already per-side and stable
-- for the life of the battle -- so it is returned directly, and release()
-- takes the same value back.
-- The keys handed out per battle, so releaseAll can give every one of them
-- back. Both tables are WEAK: a battle that is collected without exiting -- a
-- crash, a test, a headless run -- must not be kept alive by this bookkeeping,
-- and neither must a battler the fight has already replaced.
local keysByBattle = setmetatable({}, { __mode = "k" })

function StadiumArt.keyFor(game, battle, battler)
  if not (game and battle and battler) then return nil end
  local seen = keysByBattle[battle]
  if not seen then
    seen = setmetatable({}, { __mode = "k" })
    keysByBattle[battle] = seen
  end
  seen[battler] = true
  return battler
end

-- Drop every rig this battle was holding. BattleState:exit calls this and the
-- function did not exist, so ending a battle by switching or running raised
-- `attempt to call field 'releaseAll' (a nil value)` from inside the pop --
-- after the battle had already been taken off the stack.
--
-- It cannot simply release `battle.player` and `battle.enemy`: a fight
-- REPLACES its battler on every switch, every faint and every enemy send-out
-- (`self.player = makeBattler(...)` in eight places), so by the time exit runs,
-- the battlers still referenced by the state are the last pair only, and every
-- earlier one is gone from the state while its rig is still resident. Hence the
-- set above -- keyFor is the one door every key comes through.
function StadiumArt.releaseAll(game, battle)
  if not battle then return end
  local seen = keysByBattle[battle]
  keysByBattle[battle] = nil
  if not seen then return end
  for key in pairs(seen) do
    StadiumArt.release(game, key)
  end
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
  preview, warned = nil, false
  keysByBattle = setmetatable({}, { __mode = "k" })
end

return StadiumArt
