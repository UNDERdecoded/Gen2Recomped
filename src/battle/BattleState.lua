-- The battle state: wild and trainer battles driven entirely by generated
-- data (species, moves, type chart, trainer parties, encounter tables).
--
-- Flow: intro -> menu (FIGHT/PKMN/ITEM/RUN) -> move select -> turn
-- resolution (a queue of messages/actions/UI pushes) -> back to menu,
-- until one side is out, then finish.  Pops itself and calls
-- onFinish("win"|"lose"|"run"|"caught").
--
-- The Gen 1 move-effect pipeline (multi-hit, charge, trapping, thrash,
-- bide, recharge, confusion, screens, substitute, transform, ...) is
-- ported from engine/battle/core.asm; see docs/behavior-porting-notes.md.

local Assets = require("src.render.Assets")
local Catching = require("src.battle.Catching")
local Damage = require("src.battle.Damage")
local Abilities = require("src.battle.Abilities")
local EffectRegistry = require("src.battle.EffectRegistry")
local HoldItems = require("src.battle.HoldItems")
local Experience = require("src.battle.Experience")
local HeldItems = require("src.battle.HeldItems")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local MoveEffects = require("src.battle.MoveEffects")
local Party = require("src.pokemon.Party")
local Pokemon = require("src.pokemon.Pokemon")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Status = require("src.battle.Status")
local StatusRegistry = require("src.battle.StatusRegistry")
local Timing = require("src.core.Timing")
local TrainerAI = require("src.battle.TrainerAI")
local TurnOrder = require("src.battle.TurnOrder")
local Targeting = require("src.battle.Targeting")
local TypeChart = require("src.battle.TypeChart")
local Strings = require("src.core.Strings")
local Weather = require("src.battle.Weather")
local WideBattle = require("src.battle.WideBattle")
local Gen3Battle = require("src.battle.Gen3Battle")
local GameVersion = require("src.core.GameVersion")

-- FORWARD-DECLARED, because they are defined next to the other doubles
-- helpers two thousand lines down but read from `stepHPDrain` up here.  A
-- `local function` at the definition site would have made a SECOND local
-- that the earlier callers cannot see, so those callers fell through to a
-- global and crashed with "attempt to call global 'activeBattlers'" the
-- first time a HP bar drained.
local activeBattlers, foesOf

local BattleState = {}
BattleState.__index = BattleState
BattleState.isOpaque = true

-- pokered prints the battle lines itself (engine/battle/core.asm and the
-- move-effect banks), and the importer extracts every one of them, so the
-- port paraphrasing them in Lua meant the screen showed a near-miss of the
-- game's own wording while the cache held the real line -- and on a
-- localized import it showed English over translated data.
--
-- fromRom prefers the extracted text and keeps the literal as the catalog
-- fallback, for a cache built before the label and for the pure-module
-- tests that run without a dataset.  The battle text's slots ({USER},
-- {TARGET}, the {RAM:...} buffers) are NOT in the token registry that
-- TextBox.substitute serves -- it only resolves {PLAYER}, {RIVAL} and
-- three string buffers -- so they are spliced here, in argument order,
-- before the box ever sees the string.  {PLAYER}/{RIVAL} are left alone
-- for that later pass.
-- {PLAYER}/{RIVAL} are the two slots TextBox.substitute can fill on its
-- own, so they are only consumed here when the caller clearly supplies
-- them: an argument count matching every slot.  Matching just the other
-- slots leaves those two for the later pass.  Anything else means the
-- extracted line cannot carry what the call has to say -- a few labels
-- stop at a dynamic marker the decoder does not follow, e.g.
-- _EnemysWeakText extracts as "The enemy's weak!\nGet'm! " with nowhere
-- to put the name -- so the engine's own wording stands in rather than
-- printing a sentence with a hole in it.
local function fromRom(data, label, fallback, ...)
  local text = data and data.text and data.text[label]
  if not text then return Strings(fallback, ...) end
  local args = { ... }
  if #args == 0 then return text end

  local slots, named = 0, 0
  for token in text:gmatch("%b{}") do
    slots = slots + 1
    if token == "{PLAYER}" or token == "{RIVAL}" then named = named + 1 end
  end
  local fillNamed
  if #args == slots then
    fillNamed = true
  elseif #args == slots - named then
    fillNamed = false
  else
    return Strings(fallback, ...)
  end

  local index = 0
  return (text:gsub("%b{}", function(token)
    if not fillNamed and (token == "{PLAYER}" or token == "{RIVAL}") then
      return token
    end
    index = index + 1
    local value = args[index]
    if value == nil then return token end
    return tostring(value)
  end))
end

function BattleState:romText(label, fallback, ...)
  return fromRom(self.data, label, fallback, ...)
end
-- Letterbox voids around the 160x144 battle canvas fill white so the
-- window reads as one continuous battle screen (no black bars).
BattleState.letterboxWhite = true

-- A battle is a self-contained SCREEN, not the window.  The overworld's
-- dialogue box docks to the window edge on purpose (Renderer:setUIAnchor) --
-- a box floating in the middle of a zoomed-out map reads as detached.  A
-- battle is the opposite: pokered draws its text box and YES/NO in the same
-- 160x144 tilemap as the HUD, and pulling them out to the window edge splits
-- the composition in two -- the caught-mon nickname prompt lands a whole
-- letterbox below the white field it is supposed to be printed on.  Anchors
-- are held off for as long as a battle is in the stack.
BattleState.holdsUIAnchors = true

-- BATTLE LAYOUT: the classic 160x144 arrangement, or the widescreen one on
-- a 304x144 surface (src/battle/WideBattle.lua).  Only the composition
-- differs; every battler, queue and animation below is shared.  Menus and
-- prompts pushed during a wide battle keep its wide canvas, while drawing
-- their classic 160px UI centred within it (Game:draw).
function BattleState:isWideBattleLayout()
  local options = self.game and self.game.save and self.game.save.options
  return options and options.battleLayout == "wide" or false
end

-- The four actions in the order Gen 1's 2x2 reads them.
BattleState.CLASSIC_ACTIONS = { "fight", "pkmn", "item", "run" }

function BattleState:wideLayout()
  return self:isWideBattleLayout()
end

-- EMERALD FIGHTS ON ITS OWN SCREEN.
--
-- Not an option, unlike the widescreen layout: a Gen 3 cache has a 240x160
-- overworld, and a battle that answers 160x144 gets letterboxed inside it and
-- then draws the GAME BOY'S menu -- FIGHT/<PK><MN> over ITEM/RUN -- in a
-- region a third the area of the screen around it.  The wide option still
-- wins where the player has asked for it.
function BattleState:gen3Layout()
  if self:isWideBattleLayout() then return false end
  return GameVersion.isGen3() and true or false
end

-- ---------------------------------------------------------------------------
-- WHERE EVERYTHING IS, PUBLISHED
--
-- A mod that composes something UNDER the battle -- DRAMATIC_SHAPE stages one
-- on the map -- needs to know where the two Pokemon stand, which rectangles
-- the HUD blocks occupy, and which rows the text box owns.  It had those as
-- its own constants, measured against the Game Boy screen, and its answer to
-- a second layout existing was to switch that layout off.  That works for an
-- OPTION.  It cannot work for Emerald's screen, which is not a preference --
-- so the numbers become the engine's to state, and a layout that moves
-- anything moves it in one place.
--
-- The classic figures below mirror drawClassic / drawHUDs / drawTextArea; the
-- suite pins them to the drawing code so the two cannot drift.  nil means
-- "this layout has no published geometry", which is the honest answer for the
-- widescreen option: it has one, but nothing has measured it.
BattleState.CLASSIC_GEOMETRY = {
  width = 160, height = 144,
  anchor = { player = { 26, 96 }, enemy = { 124, 56 } },
  hudRect = {
    enemy = { 8, 0, 80, 32 },
    player = { 72, 56, 88, 40 },
  },
  hudBand = {
    enemy = { 0, 0, 160, 48 },
    player = { 0, 48, 160, 48 },
  },
  textRect = {
    box = { 0, 96, 160, 48 },
    -- the move menu's TYPE/PP panel and the copy menu's list, which sit ABOVE
    -- the box on this layout and nowhere at all on Emerald's
    moves = { 0, 64, 88, 32 },
    mimic = { 0, 56, 128, 40 },
  },
}

function BattleState:layoutGeometry()
  if self:isWideBattleLayout() then return nil end
  if self:gen3Layout() then
    return Gen3Battle.geometry(BattleState.CLASSIC_GEOMETRY,
                               self.data and self.data.constants)
  end
  return BattleState.CLASSIC_GEOMETRY
end

-- BOTH WIDE LAYOUTS LAY THE FOUR MOVES OUT AS A 2x2, so both navigate it with
-- all four directions rather than the classic vertical list.  The maths is
-- the same grid in either case and lives once; what differs is only which
-- layouts ask for it.  nil means "no direction was pressed", and the caller
-- then runs its own list navigation and its A / B / SELECT handling.
function BattleState:moveGridNavigate(index, count, input)
  if not (self:isWideBattleLayout() or self:gen3Layout()) then return nil end
  return WideBattle.navigate(index, count, input)
end

-- The four actions, in the order this layout's grid reads them.  Gen 1 goes
-- fight / party / item / run across the 2x2; Emerald goes fight / bag /
-- party / run -- the same four in the other pair of diagonals, so a player
-- who reaches for BAG must not open the party.
function BattleState:menuActions()
  if self:gen3Layout() then return Gen3Battle.ACTIONS end
  return BattleState.CLASSIC_ACTIONS
end

-- BATTLE SIZE: "fixed" keeps the classic integer-scaled letterbox (a GB pixel
-- is a whole number of screen pixels, and the battle is the same size at any
-- zoom); "fill" scales the battle surface to the window instead, so it fills
-- vertically.  Filling means a fractional scale, so pixels stop being evenly
-- sized -- that is the trade, which is why it is a setting rather than a
-- change.  Only the battle surface is affected; the overworld is unchanged.
function BattleState:wantsFillScale()
  local options = self.game and self.game.save and self.game.save.options
  return options and options.battleFit == "fill" or false
end

-- BATTLE BG: what fills the screen AROUND the battle -- the letterbox voids
-- that grow as the window gets bigger or the view is zoomed out.  The battle
-- screen itself is untouched: it keeps its white paper field in every mode.
--
--   "white"  the display mode's paper shade (the classic look)
--   "black"  plain black bars
--   "world"  the frozen overworld, dimmed
--
-- "world" works by making the battle NON-opaque: StateStack:visibleBase then
-- finds the overworld below it and Game:draw keeps drawing the map, so the
-- voids show it instead of a flat clear.  The battle still paints its own
-- opaque 160x144 field over the top, so only the surround changes.
function BattleState:bgMode()
  local options = self.game and self.game.save and self.game.save.options
  local mode = options and options.battleBg
  if mode == "black" or mode == "world" then return mode end
  return "white"
end

-- How far to dim the overworld behind a "world" background, 0..1.  Enough
-- that the battle reads as the foreground rather than competing with a fully
-- lit map behind it.
BattleState.BG_WORLD_DIM = 0.55

-- ------- windows over a world
--
-- `bgMode` above is about the LETTERBOX -- the voids around the 160x144 -- and
-- the battle still paints its own opaque field inside them.  This is the other
-- case: something has replaced the field itself, so the boxes are sitting on a
-- picture rather than on paper.
--
-- STADIUM2_OVERWORLD_MODELS' in-world 3D battle is that something.  It fights
-- on the live map, and against a lit voxel world a solid white text box is not
-- a window, it is a hole -- and the black text that was legible on paper is the
-- one thing in the frame that still looks like a Game Boy.  So over a world
-- backdrop the dialogue and the FIGHT/PKMN/PACK/RUN box go to glass and their
-- text goes white.
--
-- The move list and the TYPE/PP panel deliberately do NOT: they are dense,
-- they are read rather than glanced at, and a translucent one over moving
-- geometry is genuinely hard to use.  One decision per window, not one for the
-- screen.
BattleState.WORLD_WINDOW_STYLE = {
  fill = { 1, 1, 1, 0.4 },
  text = { 1, 1, 1, 1 },
}

-- How often to re-ask whether the backdrop is live.  The answer changes at
-- most twice a battle (once when the staged fight produces its first frame,
-- once if it gives up), so this is a poll rather than a per-frame call --
-- and it is a poll rather than a latch because a renderer that falls back
-- mid-fight has to get the readable boxes back.
BattleState.BACKDROP_POLL_FRAMES = 10

-- Is something drawing a WORLD where this battle's flat field would be?
--
-- Asked of the mods rather than inferred: `render.compose` taking the frame
-- would be a proxy (a mod laying two Game Boy screens out side by side takes
-- it too, and its battle field is still opaque paper), and guessing wrong here
-- means white text on white. A mod that stages a battle over a world publishes
-- `inWorld3DBattleStatus()`, which is the same status the exit log reads --
-- `active` for "a staged fight exists" and `frames` for "it has actually put
-- something on screen". Both, because a renderer that never produced a frame
-- has left the flat field exactly where it was.
--
-- No mods, or no mod that answers: false, and every box is the one the Game
-- Boy drew.
function BattleState:worldBackdrop()
  local frame = self.frame or 0
  local last = self._backdropPolled
  if last ~= nil and (frame - last) < BattleState.BACKDROP_POLL_FRAMES then
    return self._backdropLive == true
  end
  self._backdropPolled = frame

  local live = false
  pcall(function()
    local mods = self.game and self.game.mods
    local exports = mods and mods.exports
    if type(exports) ~= "table" then return end
    for _, mod in pairs(exports) do
      local statusFn = type(mod) == "table" and mod.inWorld3DBattleStatus
      if type(statusFn) == "function" then
        local ok, st = pcall(statusFn)
        if ok and type(st) == "table" and st.active
           and (tonumber(st.frames) or 0) > 0 then
          live = true
          return
        end
      end
    end
  end)
  self._backdropLive = live
  return live
end

-- The style this battle's windows wear, or nil for the Game Boy's solid
-- white paper.  Separate from worldBackdrop so a caller can override the
-- look without re-deciding when it applies.
function BattleState:windowStyle()
  if not self:worldBackdrop() then return nil end
  return BattleState.WORLD_WINDOW_STYLE
end

-- Renderer:setUISize asks the top state for its surface before anything draws
function BattleState:uiSize()
  if self:wideLayout() then return WideBattle.WIDTH, WideBattle.HEIGHT end
  if self:gen3Layout() then return Gen3Battle.WIDTH, Gen3Battle.HEIGHT end
  return 160, 144
end

-- Battle colors itself per-pixel (species pics + HP bar tints), so the
-- SGB whole-screen remap must not run over it.  The wide layout still
-- needs a zone list of its own: the invented 160x144 one would leave its
-- extra columns unremapped in the forced-mono modes (WideBattle.zones).
function BattleState:sgbPalettes()
  if self:wideLayout() then return WideBattle.zones() end
  if self:gen3Layout() then return Gen3Battle.zones() end
  return nil
end

local Rulesets = {
  gen1_faithful = require("src.battle.rulesets.gen1_faithful"),
  modern_clean = require("src.battle.rulesets.modern_clean"),
}

-- the Poké Ball toss chain (TossBallAnimation) plays even with battle
-- animations off: PlayMoveAnimation jumps to it before checking wOptions
local BALL_ANIMS = {
  TOSS_ANIM = true, GREATTOSS_ANIM = true, ULTRATOSS_ANIM = true,
  BLOCKBALL_ANIM = true, POOF_ANIM = true, HIDEPIC_ANIM = true,
  SHAKE_ANIM = true, SHOWPIC_ANIM = true,
  -- Gen 2's shiny sparkle rides the same send-out script (see
  -- BattleState:shinyAnim), so it plays on the same terms the poof does.
  SHINY_ANIM = true,
}

local imageCache = {}
-- The three tables below are keyed by the Image OBJECT, not by a path, and a
-- running battle holds the pics it built at enter() (battler.sprite,
-- playerBackPic, trainerPic).  Weak keys let a dropped pic's row go with it,
-- so invalidate() can drop the path cache without orphaning what is on
-- screen right now (#316).
local WEAK_KEYS = { __mode = "k" }
-- fully transparent rows below a pic's content (the extracted 32x32 back
-- pics carry baked-in padding); used to sit the pic flush on the text box
local imagePadBottom = setmetatable({}, WEAK_KEYS)
-- fully transparent columns left of a pic's content; at 2x (back pics)
-- this is subtracted from hlcoord 1,5 so opaque pixels match hardware,
-- where those columns were white-on-white rather than shifted content
local imagePadLeft = setmetatable({}, WEAK_KEYS)
-- image -> { path, pal } so palette-fade variants (see fadeImage) can be
-- rebuilt for any battle pic, whatever code loaded it
local imageMeta = setmetatable({}, WEAK_KEYS)
-- pal = { name, colors } recolors the 4 GB shades like the Super Game Boy.
-- trueColor art (14 §the 4-shade contract) opts out of the quantize
-- entirely, so its palette variant collapses back onto the plain path.
-- `crop = { index =, width = }` slices the nth cell out of a horizontal
-- strip BEFORE the palette map, so a Crystal pic-animation frame goes
-- through exactly the same recolor, ground-padding measurement and cache
-- path as the still pic it stands in for (see src/pokemon/PicAnim.lua).
local function getImage(path, pal, trueColor, crop)
  if not path then return nil end
  if trueColor then pal = nil end
  local key = pal and (path .. "#" .. pal.name) or path
  if crop then key = key .. "@" .. crop.index end
  if not imageCache[key] then
    local img, pad, padL = nil, 0, 0
    if love.image and love.image.newImageData then
      local id = Assets.imageData(path)
      if crop then
        local strip = id
        id = love.image.newImageData(crop.width, strip:getHeight())
        id:paste(strip, 0, 0, (crop.index - 1) * crop.width, 0,
                 crop.width, strip:getHeight())
      end
      if pal then
        local c = pal.colors
        id:mapPixel(function(_, _, r, g, b, a)
          if a == 0 then return r, g, b, a end
          local col = r > 0.83 and c[1] or r > 0.5 and c[2]
                      or r > 0.17 and c[3] or c[4]
          return col[1] / 255, col[2] / 255, col[3] / 255, a
        end)
      end
      local w, h = id:getDimensions()
      local bottom = h - 1
      while bottom >= 0 do
        local opaque = false
        for x = 0, w - 1 do
          local _, _, _, a = id:getPixel(x, bottom)
          if a > 0 then opaque = true break end
        end
        if opaque then break end
        bottom = bottom - 1
      end
      local left = 0
      while left < w do
        local opaque = false
        for y = 0, h - 1 do
          local _, _, _, a = id:getPixel(left, y)
          if a > 0 then opaque = true break end
        end
        if opaque then break end
        left = left + 1
      end
      img = love.graphics.newImage(id)
      pad = h - 1 - bottom
      padL = left
    else
      img = Assets.image(path) -- headless stub: no pixel access
    end
    imageCache[key] = img
    imagePadBottom[img] = pad
    imagePadLeft[img] = padL
    -- crop rides along so fadeImage / grayImage / blackImage re-bake the
    -- SAME cell of the strip, not the whole strip
    imageMeta[img] = { path = path, pal = pal, trueColor = trueColor or nil,
                       crop = crop }
  end
  return imageCache[key]
end

-- Hot reload / COLORS change (PaletteFX.setMode calls this): the next
-- getImage re-resolves every pic through the asset search path and
-- re-measures its ground padding.  ONLY the path->image cache is dropped.
-- Wiping the three per-image tables as well orphaned the pics a running
-- battle already holds: imagePadBottom went nil, so backPlacement lost the
-- four transparent rows it grounds the back pic on and the pic jumped
-- pad * 2x = 8px UP the frame COLORS changed (#316), and imageMeta went nil,
-- so picImage's forced-mono grayImage (#207), fadeImage's BGP variants and
-- imagePathOf's battle_sprite_scales lookup all silently stopped resolving.
-- Those rows are weak-keyed, so entries for pics nothing references any more
-- are collected on their own rather than leaking.
function BattleState.invalidate()
  imageCache = {}
end

Assets.register(BattleState.invalidate)

-- the species' SGB palette (active COLORS pack), or nil
local function monPalette(data, species, shiny)
  local PaletteFX = require("src.render.PaletteFX")
  local colors = PaletteFX.monPal(data, species, nil, shiny)
  if not colors then return nil end
  local name = PaletteFX.monPalName(data, species, nil, shiny)
  -- prefix so GBC vs RED++ cache keys don't collide on shared names
  if PaletteFX.usesGbcPack() then name = "redpp:" .. name end
  return { name = name, colors = colors }
end

-- a named palette from the active COLORS pack as a getImage pal
local function namedPalette(data, name)
  local PaletteFX = require("src.render.PaletteFX")
  local colors = PaletteFX.pal(data, name)
  if not colors then return nil end
  local key = name
  if PaletteFX.usesGbcPack() then key = "redpp:" .. name end
  return { name = key, colors = colors }
end

-- Custom trainer portraits can opt into the same Advanced OBJ palette source
-- as their overworld walker. Vanilla trainers preserve the hardware-faithful
-- MEWMON fallback used during the battle introduction.
function BattleState.trainerPalette(data, trainer)
  local source = trainer and trainer.paletteSource
  if source then
    local PaletteFX = require("src.render.PaletteFX")
    local colors, group = PaletteFX.spriteObp({ paletteSource = source }, trainer.id)
    if colors then
      return { name = "trainer:" .. source .. ":" .. tostring(group), colors = colors }
    end
  end
  return namedPalette(data, "MEWMON")
end

-- Yellow only: ROCKET with wTrainerNo >= $2a is Jessie & James, who share
-- the class and the name "ROCKET" but battle behind their own pic
-- (home/trainers2.asm IsFightingJessieJames).  picJessieJames exists only
-- in a Yellow cache extracted after #439, so an older cache keeps the
-- grunt pic until it is re-imported.
function BattleState.trainerPicPath(data, trainer, oppClass, partyIndex)
  if oppClass == "OPP_ROCKET" and (partyIndex or 1) >= 42
     and trainer and trainer.picJessieJames then
    return trainer.picJessieJames
  end
  if trainer and trainer.pic then return trainer.pic end
  local base = trainer and trainer.basePic and data.trainers[trainer.basePic]
  return base and base.pic or nil
end

-- The battle-BGP fade variant of a pic (AnimationFlashScreen and the
-- SetAnimationBGPalette effects remap the four BG shades; on the SGB
-- the colorizer then colors the REMAPPED shade, so a faded pic shows
-- palette[bgp[shade]]).  bgp = shade map {[0..3] -> 0..3} or nil.
local function fadeImage(img, bgp)
  if not bgp or not img then return img end
  local meta = imageMeta[img]
  if not meta then return img end
  -- a full-color pic has no DMG shades to remap
  if meta.trueColor then return img end
  local PaletteFX = require("src.render.PaletteFX")
  local base = meta.pal and meta.pal.colors or PaletteFX.GRAYS
  local name = (meta.pal and meta.pal.name or "GB")
               .. "&" .. bgp[0] .. bgp[1] .. bgp[2] .. bgp[3]
  return getImage(meta.path,
                  { name = name, colors = PaletteFX.permute(base, bgp) },
                  nil, meta.crop)
end

-- the raw DMG-gray build of a colored pic (SE_WAVY_SCREEN bakes the
-- pics into the BG canvas so they wave with it; the zone pass then
-- colors them by region like the real SGB)
local function grayImage(img)
  local meta = imageMeta[img]
  if not meta or not meta.pal then return img end
  return getImage(meta.path, nil, nil, meta.crop) or img
end

-- The blacked-out battle screen.  HandlePlayerBlackOut (core.asm:1151) runs
-- SET_PAL_BATTLE_BLACK, i.e. SetPal_BattleBlack sends PalPacket_Black --
-- PAL_BLACK in all four slots of BlkPacket_Battle (engine/gfx/palettes.asm:
-- 22-25).  The mon pics are drawn OVER the zone pass with their palette
-- already baked in, so darkening them means re-baking through PAL_BLACK the
-- way fadeImage re-bakes through a BGP permutation (#292).  Reads the palette
-- out of the active pack, exactly like sgbBattlePals, so the zone pass and
-- the pics can never disagree.  trueColor art has no DMG shades to remap.
local function blackImage(data, img)
  local meta = imageMeta[img]
  if not meta or meta.trueColor then return img end
  local PaletteFX = require("src.render.PaletteFX")
  local pack = PaletteFX.pack(data)
  local colors = pack and pack.palettes and pack.palettes.BLACK
  if not colors then return img end
  local name = PaletteFX.usesGbcPack() and "redpp:BLACK" or "BLACK"
  return getImage(meta.path, { name = name, colors = colors }, nil, meta.crop)
    or img
end

-- the asset path a loaded battle image came from (nil for the headless
-- stub images), so the battle_sprite_scales registry can be looked up by
-- the same path data references
local function imagePathOf(img)
  local m = imageMeta[img]
  return m and m.path
end

-- the image a battler pic actually draws with this frame
function BattleState:picImage(img)
  local PaletteFX = require("src.render.PaletteFX")
  -- #207: OG / OG INV / CLASSIC are forced-mono display modes.  A battle that
  -- exposes no SGB zones (sgbPalettes() == nil) has a whole-screen GRAYS zone
  -- invented by PaletteFX.ensureZones, so Renderer:endFrame re-thresholds the
  -- WHOLE finished frame through the shade shader a second time (keyed on the
  -- red channel).  A pic baked with the species' SGB color is then remapped
  -- again and loses its warm mid shades -- REDMON's reds 1.0/0.839 both land in
  -- the c0 bucket, collapsing CHARMANDER's body into the white paper and
  -- leaving only the outline.  Emit the raw DMG-gray build instead (exactly
  -- what the SE_WAVY_SCREEN grayPics path already does) so the downstream remap
  -- recolors 255->c0/170->c1/85->c2/0->c3 and all four shades survive; cool
  -- palettes (CYANMON reds 0.678/0.451) already rendered correctly.  This mode
  -- set mirrors PaletteFX.ensureZones / effectiveColors -- keep them in sync.
  local mono = PaletteFX.mode == "og" or PaletteFX.mode == "og_inv"
               or PaletteFX.mode == "classic"
  if self.grayPics or mono then return grayImage(img) end
  -- SET_PAL_BATTLE_BLACK covers every battle palette slot, so the pics go
  -- dark with the HP bars while the blackout text is up (#292).  The intro
  -- silhouette slide (SlidePlayerAndEnemySilhouettesOnScreen) darkens the
  -- same way: the original slides both pics in under the %11100100
  -- silhouette palette and only runs SET_PAL_BATTLE once they have landed,
  -- so a still-sliding pic reads as a black silhouette, exactly like the
  -- evolution movie's PAL_BLACK (#577).  Below the mono check on purpose:
  -- the forced-mono modes re-threshold the whole frame downstream, and the
  -- DMG had no SGB darkening to begin with.
  if self.blackedOut or (self.introSlide or 0) > 0 then
    return blackImage(self.data, img)
  end
  return fadeImage(img, self:activeBgp())
end

-- Gen 1 trainer Pokémon have fixed DVs (engine/battle/core.asm);
-- constants.trainerDvs overrides, this is the imported-cache fallback
local TRAINER_DVS = { attack = 9, defense = 8, speed = 8, special = 8, hp = 8 }

-- charge-turn texts by move id; the move record's chargeText field wins
-- (ChargeEffect's per-move text pointers)
-- Strings.source, not Strings: this table is built at require time, before
-- Strings.load has a catalog, so translating here would freeze the English.
-- The marker is a no-op that puts these lines in the catalog anyway; the
-- lookup happens where chargeText is formatted below.
local CHARGE_TEXT = {
  FLY = Strings.source("%s\nflew up high!"),
  DIG = Strings.source("%s\ndug a hole!"),
  RAZOR_WIND = Strings.source("%s\nmade a whirlwind!"),
  SOLARBEAM = Strings.source("%s\ntook in sunlight!"),
  SKULL_BASH = Strings.source("%s\nlowered its head!"),
  SKY_ATTACK = Strings.source("%s\nis glowing!"),
}

-- pokered's <USER>/<TARGET> text macros (home/text.asm
-- PlaceMoveUsersName): battle texts naming the enemy mon print
-- "Enemy " before the nickname; player-side mons never get it.
local function displayName(b)
  return b.isPlayer and b.name or ("Enemy " .. b.name)
end

-- Apply the "Enemy " prefix to a pre-built message from a module that
-- only knows the raw nickname (Status.beforeMove/residual,
-- TrainerAI.useItem): splice it in before the first name occurrence.
local function prefixEnemy(msg, battler)
  if battler.isPlayer then return msg end
  local s = msg:find(battler.name, 1, true)
  if not s then return msg end
  return msg:sub(1, s - 1) .. "Enemy " .. msg:sub(s)
end

-- Level-up stats window (PrintStatsBox .LevelUpStatsBox: box (9,2)
-- 11x10 over the battle, dismissed with A/B)
local StatBox = {}
StatBox.__index = StatBox

function StatBox.new(game, mon, onDone)
  return setmetatable({ game = game, mon = mon, onDone = onDone }, StatBox)
end

function StatBox:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function StatBox:draw()
  local s = self.mon.stats
  if s.spatk and s.spdef then
    -- Gen 2's box carries five rows, so it needs a wider frame than the
    -- 11x10 pokered one to fit "SPCL.ATK" beside its value
    Font.drawBox(5, 2, 15, 11)
    love.graphics.setColor(0, 0, 0, 1)
    local rows = { { "ATTACK", s.attack }, { "DEFENSE", s.defense },
                   { "SPCL.ATK", s.spatk }, { "SPCL.DEF", s.spdef },
                   { "SPEED", s.speed } }
    for i, r in ipairs(rows) do
      local y = 24 + (i - 1) * 14
      Font.draw(r[1], 48, y)
      local value = ("%3d"):format(r[2])
      Font.draw(value, 152 - #value * 8, y)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  Font.drawBox(9, 2, 11, 10)
  love.graphics.setColor(0, 0, 0, 1)
  local rows = { { "ATTACK", s.attack }, { "DEFENSE", s.defense },
                 { "SPEED", s.speed }, { "SPECIAL", s.special } }
  for i, r in ipairs(rows) do
    Font.draw(r[1], 88, 24 + (i - 1) * 16)
    Font.draw(("%3d"):format(r[2]), 128, 32 + (i - 1) * 16)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------

local function makeBattler(data, mon, isPlayer, save)
  local def = data.pokemon[mon.species]
  local badgeBoosts = data.constants and data.constants.badgeBoosts
  local badges = nil
  if isPlayer and save then
    -- Gen 1 badge stat boosts (x9/8); the badge set follows the merged
    -- badgeBoosts rows so a retuned list changes what gets baked in
    badges = {}
    for _, row in ipairs(badgeBoosts or Damage.BADGE_BOOSTS) do
      if save.inventory[row.badge] then badges[row.badge] = true end
    end
  end
  return {
    mon = mon,
    def = def,
    name = mon.nickname or def.name,
    -- The species this battler is SHOWING, which is not always `mon.species`:
    -- a Transformed mon wears the copied species' pic and a Tower ghost wears
    -- none at all.  Both of those move this field where they move `sprite`,
    -- so anything drawing the battler -- the flat pic here, or a renderer
    -- standing a model in its place -- reads one answer and agrees with the
    -- other.  `mon.species` stays the truth about the Pokemon itself; this is
    -- the truth about the picture.
    species = mon.species,
    isPlayer = isPlayer,
    badges = badges,
    -- merged registry views consumed by the pure battle modules
    badgeBoosts = badgeBoosts,
    statuses = data.statuses,
    -- ...and the two HoldItems needs: the item table to look `mon.item` up
    -- in, and the nature table, because whether a FIGY BERRY confuses the
    -- Pokemon that ate it depends on which stat its nature lowers.  Views,
    -- not copies, so a berry eaten mid-battle is seen the next time it is
    -- asked for.
    items = data.items,
    natures = data.constants and data.constants.natures,
    shownHP = mon.hp, -- the HP the bar displays (UpdateHPBar drain)
    -- HUD status label (DrawHUDsAndHPBars); mon.status can land mid-move
    -- while the tilemap still shows the prior condition until the next
    -- post-action HUD refresh (core.asm after Execute*Move)
    shownStatus = mon.status,
    stages = {},
    -- volatile state; Transform/Conversion/Mimic override the cur* fields
    curStats = mon.stats,
    curTypes = def.types,
    curMoves = mon.moves,
    sprite = (function()
      local Sprites = require("src.pokemon.Sprites")
      local path, tc = Sprites.path(data, mon.species,
        isPlayer and "back" or "front",
        { mon = mon, kind = "battle" })
      return getImage(path, monPalette(data, mon.species,
        require("src.pokemon.Pokemon").isShiny(mon)), tc)
    end)(),
    -- Crystal's front-pic frame animation.  Only the FRONT pic carries
    -- animation tiles, so the player's back pic has none -- and Gold and
    -- Silver have none at all, where this stays nil and the pic holds still.
    -- forMon rather than new: a shiny Gen 3 Pokemon animates from its own
    -- strip, and only the Pokemon can say whether it is one
    picAnim = (not isPlayer)
      and require("src.pokemon.PicAnim").forMon(data, mon) or nil,
    -- Emerald's procedural front-pic animation -- the squash/hop/glow the
    -- sprite itself does when it appears.  Front pic only, same as above.
    monAnim = (not isPlayer)
      and require("src.pokemon.MonAnim").new(data, mon.species) or nil,
  }
end

-- LinkBattle builds clamped copies with save=nil (no badge boosts); wild
-- and trainer constructors pass the live save for the player side.
BattleState.makeBattler = makeBattler

-- The battle pic for `species` on the given side (back pic for the
-- player side, front pic for the enemy side), tinted PAL_GRAYMON --
-- the same path makeBattler uses, but forced gray -- since this is only
-- ever used for a Transformed mon's swapped-in pic (transform.asm:31-53
-- AnimationTransformMon; the SGB color comes from DeterminePaletteID,
-- which forces PAL_GRAYMON for a Transformed mon rather than the copied
-- species' own palette).
function BattleState:speciesSprite(species, isPlayerSide)
  local def = self.data.pokemon[species]
  if not def then return nil end
  local Sprites = require("src.pokemon.Sprites")
  local path, tc = Sprites.path(self.data, species,
    isPlayerSide and "back" or "front", { kind = "battle" })
  local PaletteFX = require("src.render.PaletteFX")
  local colors = PaletteFX.monPal(self.data, species, true)
  local name = "GRAYMON"
  if PaletteFX.usesGbcPack() then name = "redpp:GRAYMON" end
  return getImage(path,
                  colors and { name = name, colors = colors } or nil,
                  tc)
end

local function markSeen(game, species)
  local dex = game.save.pokedex
  if dex then dex.seen[species] = true end
end

-- newly obtained mons carry the player's OT name/ID (status screen)
--
-- ...AND, ON GEN 3, WHERE AND AT WHAT LEVEL IT WAS OBTAINED.  Emerald keeps a
-- met level and a met region-map section on every Pokemon, and the TRAINER
-- MEMO at the bottom of the summary screen is built out of them:
--
--     BOLD nature,
--     met at Lv5,
--     ROUTE 101.
--
-- The third argument is what tells the two callers apart, and it has to,
-- because they mean different things:
--
--   * A mon being CAUGHT or GIVEN passes one, and gets stamped.
--   * The load-time BACKFILL passes none.  It runs over a party that is
--     already the player's, and it has no idea where any of them came from --
--     stamping "met at <today's level>, <the map you are standing on>" would
--     invent a history and print it in the player's face as though the game
--     knew.  With no met data the memo falls back to the cartridge's own
--     one-line template, "<nature> nature", which is what Emerald itself
--     prints for a Pokemon whose history it does not have.
--
-- A met level of ZERO is not missing data: it is the cartridge's way of
-- saying HATCHED, and the memo reads it that way.
local function stampOT(save, mon, met)
  save.player.id = save.player.id or math.random(0, 65535)
  mon.ot = mon.ot or save.player.name
  mon.otId = mon.otId or save.player.id
  -- A SHINY THAT WAS PROMISED BEFORE IT HAD AN OT ID gets made true here.
  --
  -- Gen 3 shininess is personality xor trainer id, so a Pokemon marked shiny
  -- before anything stamped an id on it carries only a flag.  This is the
  -- moment the id exists, so it is the moment the personality can be moved to
  -- honour it -- otherwise the flag would be a port-only fiction the
  -- cartridge's own maths disagreed with.
  local Stats = require("src.pokemon.Stats")
  if mon.shiny and mon.personality ~= nil
     and not Stats.isShinyGen3(mon.personality, mon.otId) then
    mon.personality = Stats.shinyPersonality(mon.personality, mon.otId)
  end
  if met then
    if mon.metLevel == nil then mon.metLevel = met.level end
    if mon.metLocation == nil then mon.metLocation = met.location end
  end
end
BattleState.stampOT = stampOT

-- The region-map section the player is standing in, which is what the memo
-- names -- not the map id.  Emerald's memo says "ROUTE 101", and ROUTE 101 is
-- eleven separate map ids sharing one section; naming the map would print the
-- internal id of whichever screen the ball happened to land on.
function BattleState.metHere(game)
  local save = game and game.save
  local mapId = save and save.player and save.player.map
  local def = mapId and game.data and game.data.maps and game.data.maps[mapId]
  return def and def.regionMapSection or nil
end

local function markOwned(game, species)
  local dex = game.save.pokedex
  if dex then
    dex.seen[species] = true
    if not dex.owned[species] then
      -- new dex page registered (SFX_DEX_PAGE_ADDED)
      require("src.core.Sound").play(game.data, "Dex_Page_Added")
    end
    dex.owned[species] = true
  end
end
BattleState.markOwned = markOwned
BattleState.StatBox = StatBox -- the level-up stat window (PrintStatsBox)

local function newBattle(game)
  local self = setmetatable({}, BattleState)
  self.game = game
  self.data = game.data
  -- On this engine the battle screen IS the battle logic object: there is no
  -- separate model that a screen points at. Publishing the self-reference makes
  -- that explicit so anything holding "a thing with a .battle" (the party menu
  -- during a switch, mods walking the state stack) can treat the battle screen
  -- and the party menu uniformly instead of special-casing this one screen.
  self.battle = self
  -- ruleset from the merged registry (the requires above are the same
  -- records on a mod-free boot); an unknown save value falls back to the
  -- default with a notice instead of silently switching behavior
  local rulesets = game.data.rulesets or Rulesets
  local selected = game.save.options and game.save.options.ruleset
  local fallback = (game.data.constants and game.data.constants.defaultRuleset)
                   or "gen1_faithful"
  local ruleset = selected and rulesets[selected]
  if selected and not ruleset then
    Logger.warn("unknown ruleset %s; using %s", tostring(selected), fallback)
  end
  self.ruleset = ruleset or rulesets[fallback] or Rulesets.gen1_faithful
  self.rng = function(a, b) return love.math.random(a, b) end
  -- side/field substrate: vanilla writes nothing here, but every battle
  -- carries the stable shape mods hang screens/hazards/tokens on
  self.sides = {
    { index = 1, battlers = {}, screens = {}, hazards = {}, tokens = {} },
    { index = 2, battlers = {}, screens = {}, hazards = {}, tokens = {} },
  }
  self.field = { weather = nil, tokens = {}, sides = self.sides }
  TypeChart.load(game.data)
  -- the subanimation player (data/battle_anims via battle_anims.lua).
  -- Gen 2's animations are a different engine entirely (a bytecode VM
  -- rather than Gen 1's subanimation/frame-block tables), so they get
  -- their own player.
  if game.data.battle_anims then
    if game.data.battle_anims.gen2 then
      local ok, Gen2AnimPlayer = pcall(require, "src.battle.Gen2AnimPlayer")
      if ok then
        self.animPlayer = Gen2AnimPlayer.new(game.data)
      end
    else
      local ok, AnimPlayer = pcall(require, "src.battle.AnimPlayer")
      if ok then
        self.animPlayer = AnimPlayer.new(game.data.battle_anims)
      end
    end
  end
  -- EMERALD'S move animations are a third engine again -- a bytecode program
  -- whose particles the import reads off the cartridge -- and it exists only
  -- when that import wrote the sheets.
  do
    local ok, Gen3MoveAnim = pcall(require, "src.battle.Gen3MoveAnim")
    if ok and Gen3MoveAnim then
      self.gen3Anim = Gen3MoveAnim.new(game.data)
    end
  end
  -- THE WEATHER YOU BROUGHT IN WITH YOU.
  --
  -- A battle begun in Hoenn's rain starts under rain, and that is not a
  -- flourish: it doubles every Water move in the fight, halves every Fire
  -- one, makes THUNDER never miss, and is the difference between SWIFT SWIM
  -- being an ability and being nothing.  The overworld says which of the
  -- field's sixteen weathers this is, and only four of them mean anything
  -- here (the rest -- Mt Chimney's ash, the cave fog, the shade, the
  -- underwater bubbles -- are things you see).
  --
  -- Set PERMANENT, because the sky does not run out after five turns.  It is
  -- the same "permanent" DROUGHT and DRIZZLE use, so a move that sets its own
  -- weather still overrides it exactly as the cartridge lets it.
  do
    local ow = game.overworld
    local weather = ow and ow.battleWeather and ow:battleWeather() or nil
    if weather then
      local Weather = require("src.battle.Weather")
      Weather.start(self, weather, true)
      self.fieldWeatherFromMap = weather
    end
  end
  self.queue = {}
  self.phase = "intro"
  self.menuIndex = 1
  self.moveIndex = 1
  self.frame = 0
  return self
end

-- opts.hooked: rod encounter, announced with _HookedMonAttackedText
-- SetWildMonHeldItem (battle_main.c).  Silent on a dataset that names no
-- held items, which is every Gen 1 and Gen 2 one.
function BattleState.giveWildHeldItem(data, mon, rng)
  local def = data.pokemon and data.pokemon[mon.species]
  local common = def and def.heldItemCommon
  local rare = def and def.heldItemRare
  if not (common or rare) then return end
  if common and common == rare then
    mon.item = common
    return
  end
  local roll = (rng or love.math.random)(0, 99)
  if roll < 45 then return end
  if roll < 95 then mon.item = common or nil
  else mon.item = rare or nil end
end

function BattleState.newWild(game, species, level, opts)
  local self = newBattle(game)
  self.kind = "wild"
  local playerMon = Party.firstHealthy(game.save.party)
  if not playerMon then
    Logger.warn("wild battle with no healthy party; skipping")
    self.dead = true
  else
    self.player = makeBattler(game.data, playerMon, true, game.save)
  end
  local wild = Pokemon.new(game.data, species, level)
  -- SetWildMonHeldItem: a wild Gen 3 Pokemon may be carrying one of the two
  -- items its base-stat row names -- the first fifty times in a hundred, the
  -- second five, and nothing the other forty-five.  A species whose two are
  -- the SAME item always has it, which is how the cartridge says "always"
  -- without a third field.  147 species in Hoenn name something.
  BattleState.giveWildHeldItem(game.data, wild)
  -- BATTLETYPE_SHINY (`loadvar 3, 7` before the loadwildmon) overwrites the
  -- rolled DVs with the fixed shiny pair; the Lake of Rage Gyarados is the
  -- only encounter in Gold that uses it.
  if opts and opts.shiny then Pokemon.forceShiny(game.data, wild) end
  -- wBattleType, for the two rows PlayBattleMusic reads: BATTLETYPE_ROAMING
  -- and BATTLETYPE_SUICUNE both open on Music_SuicuneBattle.
  self.battleType = opts and opts.battleType or nil
  -- BATTLETYPE_ROAMING. The beast carries its wounds between meetings
  -- (wRoamMon1HP), so a beast you chipped to a sliver last week is still on
  -- a sliver -- that, and not a better ball, is what the long hunt buys you.
  -- InitRoamMons writes 0 for "generate new stats", which is also what a
  -- beast nobody has met yet has, so 0 means full health rather than dead.
  self.roamer = opts and opts.roamer or nil
  -- BATTLE_TYPE_FIRST_BATTLE, and nothing else in either cartridge sets these
  -- on a WILD battle: the Poochyena that jumps Birch cannot be run from and
  -- cannot black the player out.  Both are opt-in flags rather than a battle
  -- kind of their own, because everything else about the fight -- the music,
  -- the intro line, the wild-mon held item roll -- is an ordinary wild one.
  self.noRun = opts and opts.noRun or nil
  self.canLose = opts and opts.canLose or nil
  -- ...AND A ROAMER IS THE SAME INDIVIDUAL EVERY TIME.  The cartridge keeps
  -- its personality and IVs and rebuilds from them, which is what makes a
  -- hunt a hunt: nature, ability and shininess are settled the day it is
  -- released, not the day you corner it.  Applied BEFORE the battler is
  -- made, because the stats come off these.
  if opts and opts.roamerSeed then
    Pokemon.applySeed(game.data, wild, opts.roamerSeed)
  end
  self.enemy = makeBattler(game.data, wild, false)
  if self.roamer then
    local kept = math.floor(tonumber(opts.roamerHP) or 0)
    if kept > 0 then
      self.enemy.mon.hp = math.max(1, math.min(kept, self.enemy.mon.stats.hp))
    end
    -- ...AND THE STATUS CARRIES TOO, on the cartridge that has one to carry.
    -- Gen 2's roam slot keeps HP and nothing else; Gen 3's keeps a status
    -- byte beside it (UpdateRoamerHPStatus writes both), which is what makes
    -- a roamer you slept once still asleep the next time you corner it.
    if opts.roamerStatus then self.enemy.mon.status = opts.roamerStatus end
  end
  markSeen(game, species)
  if opts and opts.hooked then
    self.introText = self:romText("_HookedMonAttackedText", "The hooked\n%s\nattacked!", self.enemy.name)
  else
    self.introText = self:romText("_WildMonAppearedText", "Wild %s\nappeared!", self.enemy.name)
  end
  return self
end

-- data/trainers/special_moves.asm + read_trainer_party.asm: boss move
-- overrides, always written into the mon's THIRD move slot.
--   LoneMoves: the gym scripts write the gym number to wGymLeaderNo, so
--   these fire only for the leaders' gym battles (Giovanni: party 3);
--   the table's "index n" lands on the (n+1)-th party mon via AddNTimes.
--   TeamMoves: despite the "whole team" comment, the code writes only
--   wEnemyMon5Moves+2,  the FIFTH mon of each Elite Four member.
--   RIVAL3 (Champion): Pidgeot gets SKY ATTACK, the starter's final
--   form gets MEGA DRAIN / FIRE BLAST / BLIZZARD.
local LONE_MOVES = {
  OPP_BROCK = { 2, "BIDE" },
  OPP_MISTY = { 2, "BUBBLEBEAM" },
  OPP_LT_SURGE = { 3, "THUNDERBOLT" },
  OPP_ERIKA = { 3, "MEGA_DRAIN" },
  OPP_KOGA = { 4, "TOXIC" },
  OPP_SABRINA = { 4, "PSYWAVE" },
  OPP_BLAINE = { 4, "FIRE_BLAST" },
  OPP_GIOVANNI = { 5, "FISSURE", onlyParty = 3 },
}
local TEAM_MOVES = {
  OPP_LORELEI = "BLIZZARD", OPP_BRUNO = "FISSURE",
  OPP_AGATHA = "TOXIC", OPP_LANCE = "BARRIER",
}
local RIVAL_STARTER_MOVES = {
  VENUSAUR = "MEGA_DRAIN", CHARIZARD = "FIRE_BLAST", BLASTOISE = "BLIZZARD",
}

local function setThirdMove(data, mon, moveId)
  if not mon then return end
  local mdef = data.moves[moveId]
  local entry = { id = moveId, pp = mdef and mdef.pp or 0 }
  mon.moves[math.min(3, #mon.moves + 1)] = entry
end

local function applySpecialMoves(data, oppClass, partyIndex, party)
  local lone = LONE_MOVES[oppClass]
  if lone and (not lone.onlyParty or lone.onlyParty == partyIndex) then
    setThirdMove(data, party[lone[1]], lone[2])
    return
  end
  local team = TEAM_MOVES[oppClass]
  if team then
    setThirdMove(data, party[5], team)
    return
  end
  if oppClass == "OPP_RIVAL3" then
    setThirdMove(data, party[1], "SKY_ATTACK")
    local starter = party[6]
    if starter and RIVAL_STARTER_MOVES[starter.species] then
      setThirdMove(data, starter, RIVAL_STARTER_MOVES[starter.species])
    end
  end
end

-- The label every line in a trainer fight uses for the opponent: Hoenn's
-- class-and-name pair where there is a class, the bare name everywhere else.
-- In one place so a new line cannot quietly go back to the bare name.
-- ONE TRAINER'S SIX POKEMON.
--
-- Lifted out of newTrainer unchanged so a DOUBLE battle against two separate
-- trainers can build the second one's team the same way it builds the first
-- -- CreateNPCTrainerParty runs once per trainer on the cartridge too.
-- Nothing about the rules moved; only where the loop lives.
local function buildTrainerParty(game, oppClass, partyIndex, partyDef)
  local out = {}
  local trainerDvs = (game.data.constants and game.data.constants.trainerDvs)
                     or TRAINER_DVS
  out = {}
  for _, slot in ipairs(partyDef) do
    local mon = Pokemon.new(game.data, slot.species, slot.level)
    -- fixed trainer DVs, recomputed stats.  A party slot that carries its OWN
    -- DVs and stat exp is a stored mon rather than a generated one -- the
    -- Battle Tower's opponents come out of BattleTowerMons with both -- so its
    -- numbers win, and Stats.calc reproduces the cartridge's own stat block
    -- from them.  No ordinary TrainerGroups slot has either field, so every
    -- other trainer in the game is unchanged.
    local dvs = slot.dvs or trainerDvs
    mon.dvs = dvs
    if slot.statExp then mon.statExp = slot.statExp end
    if slot.happiness then mon.happiness = slot.happiness end
    if slot.stats then
      -- a stored stat block wins outright: the Battle Tower's opponents carry
      -- the party_struct the cartridge ships, and recomputing it would move
      -- some of them by a point
      local stats = {}
      for key, value in pairs(slot.stats) do stats[key] = value end
      mon.stats = stats
    else
      mon.stats = require("src.pokemon.Stats").calc(
        game.data.pokemon[slot.species], slot.level, dvs, slot.statExp)
    end
    mon.hp = mon.stats.hp
    table.insert(out, mon)
  end
  applySpecialMoves(game.data, oppClass, partyIndex, out)
  -- a party slot's own moves list wins over the legacy boss-move tables
  for i, slot in ipairs(partyDef) do
    local mon = out[i]
    if mon and slot.moves then
      mon.moves = {}
      for _, moveId in ipairs(slot.moves) do
        local mdef = game.data.moves[moveId]
        table.insert(mon.moves, { id = moveId, pp = mdef and mdef.pp or 0 })
      end
    end
  end
  return out
end

function BattleState:trainerLabel_()
  return self.trainerLabel or (self.trainer and self.trainer.name) or "?"
end

function BattleState.newTrainer(game, oppClass, partyIndex)
  local self = newBattle(game)
  self.kind = "trainer"
  self.oppClass = oppClass
  -- wOtherTrainerID: which trainer inside the class.  PlayBattleMusic reads
  -- it to tell the two RIVAL2 fights apart, so keep it on the battle.
  self.partyIndex = tonumber(partyIndex) or 1
  self.trainer = game.data.trainers[oppClass]
  assert(self.trainer, "unknown trainer class " .. tostring(oppClass))
  -- pret GetTrainerName_: RIVAL1/2/3 copy wRivalName into wTrainerName
  -- instead of TrainerNames ("RIVAL1" etc.).  Overlay so we don't mutate
  -- the shared data table.
  if oppClass == "OPP_RIVAL1" or oppClass == "OPP_RIVAL2"
     or oppClass == "OPP_RIVAL3" then
    local rivalName = (game.save.player and game.save.player.rival) or "BLUE"
    self.trainer = setmetatable({ name = rivalName }, { __index = self.trainer })
  elseif self.trainer.partyNames and self.trainer.partyNames[partyIndex or 1] then
    -- Gen2 names each trainer inside its class (TrainerGroups party headers)
    self.trainer = setmetatable({ name = self.trainer.partyNames[partyIndex or 1] },
                                { __index = self.trainer })
  end
  self.enemyAIMods = self.trainer.aiMods
  local partyDef = self.trainer.parties[partyIndex or 1]
  assert(partyDef, ("trainer %s has no party %s"):format(oppClass, tostring(partyIndex)))
  if Runtime.wantsHook("trainer.party") then
    partyDef = Runtime.call("trainer.party", function(_, _, party)
      return party
    end, oppClass, partyIndex or 1, partyDef) or partyDef
  end
  self.enemyParty = buildTrainerParty(game, oppClass, partyIndex or 1, partyDef)
  self.enemyIndex = 1
  local playerMon = Party.firstHealthy(game.save.party)
  if not playerMon then
    Logger.warn("trainer battle with no healthy party; skipping")
    self.dead = true
  else
    self.player = makeBattler(game.data, playerMon, true, game.save)
  end
  self.enemy = makeBattler(game.data, self.enemyParty[1], false)
  self.aiUses = self:aiUsesFor() -- wAICount, reset per enemy mon
  markSeen(game, self.enemyParty[1].species)

  -- AND THE SECOND PAIR, when this is a double battle.
  --
  -- `double` is decided before the battle is built -- from the trainer's own
  -- doubleBattle byte, which is literally BATTLE_TYPE_DOUBLE (0389BC does
  -- `gBattleTypeFlags |= gTrainers[n].doubleBattle`), or from a
  -- trainerbattle mode of 4, 6, 7 or 8.  Both sides then lead with TWO, and
  -- they are the next healthy one on each side -- the same rule the left
  -- flank used, applied once more.
  --
  -- Nothing here is reached in a single battle, and a single battle is what
  -- every Gen 1 and Gen 2 fight is: those cartridges have no doubles at all.
  if self.trainer and self.trainer.doubleBattle then self.double = true end
  self:sendOutSecondPair()
  -- SGB: the enemy-side battle palette while the trainer pic is up is
  -- MonsterPalettes[0] = PAL_MEWMON -- InitBattleCommon zeroes
  -- wEnemyMonSpecies2 before the intro's SET_PAL_BATTLE
  -- (engine/battle/core.asm:6682, engine/gfx/palettes.asm SetPal_Battle)
  self.trainerPic = getImage(
    BattleState.trainerPicPath(game.data, self.trainer, oppClass, partyIndex),
    BattleState.trainerPalette(game.data, self.trainer),
    self.trainer and self.trainer.trueColor)
  -- THE CLASS, WHICH HOENN PUTS IN FRONT OF THE NAME.
  --
  -- Emerald opens with "COOLTRAINER BRAXTON would like to battle!" -- the
  -- class from gTrainerClassNames, then the trainer's own name -- and every
  -- other line in the fight uses the pair as one label.  The extractor names
  -- the class on all 855 rows (`className`) and nothing read it, so every
  -- trainer in the region announced themselves by bare name, which reads as
  -- an NPC rather than a battle.
  --
  -- The two cartridges before this one really do use the bare name (Gen 1's
  -- classes ARE the trainer, "YOUNGSTER" and no more), so the pair is built
  -- only where there is a class to build it from.
  local shownName = self.trainer.name
  if self.trainer.className and self.trainer.className ~= ""
     and self.trainer.className ~= shownName then
    shownName = self.trainer.className .. " " .. tostring(shownName)
    self.trainerLabel = shownName
  end
  self.introText = Strings("%s wants\nto fight!", shownName)
  return self
end

-- ---------------------------------------------------------------------------
-- THE SECOND PAIR, AND WHY IT IS NOT WRITTEN INSIDE THE CONSTRUCTOR
-- ---------------------------------------------------------------------------
--
-- Reported from play: "Double battles still aren't working properly, the
-- second person doesn't throw out their pokemon and i don't throw out my
-- second pokemon."  Two Pokemon on the field, two healthboxes, and a
-- `double` flag that said there should be four.
--
-- THE ORDER WAS THE BUG.  Commands.start_battle builds the battle first and
-- decides afterwards whether it is a double:
--
--     battle = BattleState.newTrainer(game, class, 1)
--     if opts and opts.double then battle.double = true end
--     if battle.trainer and battle.trainer.doubleBattle then ... end
--
-- and it HAS to be that way round for the second of those two, because
-- `battle.trainer` is what the constructor produces.  But the code that
-- actually sends the second pair out lived inside the constructor, behind
-- `if self.double`, which at that moment was still nil.  So the flag was set
-- on a battle whose right-hand slots had already been skipped: `isDouble`
-- answered true, the turn loop sorted four entries, the layout drew four --
-- and two of the four were never put on the field.
--
-- So it moves out here, where either caller can reach it, and it is
-- IDEMPOTENT -- a slot that is already filled is left alone.  That matters
-- for the two-trainer battle, where `addOpponentTrainer` has already put the
-- SECOND trainer's lead in the right-hand opponent slot and this must not
-- overwrite it with the first trainer's second Pokemon.
--
-- Both sides lead with two and they are the next healthy one on each side --
-- the same rule the left flank used, applied once more.  Nothing here is
-- reached in a single battle, and a single battle is what every Gen 1 and
-- Gen 2 fight is: those cartridges have no doubles at all.
function BattleState:sendOutSecondPair()
  if self.double ~= true or not BattleState.DOUBLES_READY then return end
  if self.dead then return end
  local game = self.game
  if not (game and game.save) then return end

  if self:battlerAt(BattleState.POS.PLAYER_RIGHT) == nil then
    -- the next healthy one that is not already standing in the left slot
    local lead = self.player and self.player.mon
    local second = Party.firstHealthy(game.save.party, lead)
    if second then
      self:placeBattler(BattleState.POS.PLAYER_RIGHT,
                        makeBattler(game.data, second, true, game.save))
    else
      -- one usable mon and a double battle is a state the cartridge refuses
      -- to enter (special 64 answers non-zero and the approach is called
      -- off), so if it is somehow reached the battle is a single
      self.double = nil
      self:syncSides()
      return
    end
  end

  if self:battlerAt(BattleState.POS.OPPONENT_RIGHT) == nil then
    local party = self.enemyParty
    if party and party[2] then
      self.enemyIndexRight = 2
      self:placeBattler(BattleState.POS.OPPONENT_RIGHT,
                        makeBattler(game.data, party[2], false))
      markSeen(game, party[2].species)
    else
      -- a "double" trainer with one Pokemon fights alone on their side,
      -- which is what a two-on-one looks like on the cartridge too
      self.enemyIndexRight = nil
    end
  end
  self:syncSides()
end

-- THE SECOND TRAINER, WHEN TWO OF THEM WALKED UP.
--
-- BattleSetup_StartTrainerBattle (0B17E0) sets DOUBLE|TRAINER|TWO_OPPONENTS
-- -- 0x8009 -- when gNoOfApproachingTrainers is 2, and the battle then runs
-- with gTrainerBattleOpponent_A and _B and a party built for each.  So this
-- is not "the first trainer sends out two": it is two trainers, two records,
-- two teams, and later two payouts and two defeat lines.
--
-- The right-hand opponent slot is then filled from the SECOND trainer's
-- party rather than the first one's, which is the whole difference between
-- a two-opponent battle and a twin's.
function BattleState:addOpponentTrainer(oppClass)
  local def = self.game.data.trainers[oppClass]
  if not def then
    Logger.warn("gen3: no trainer %s -- the second opponent is dropped and "
                  .. "the battle is fought against the first alone",
                tostring(oppClass))
    return false
  end
  local partyDef = def.parties and def.parties[1]
  if not partyDef then return false end
  self.double = true
  if not BattleState.DOUBLES_READY then
    -- recorded, so the pairing is visible to anything that asks, but the
    -- second team is not sent out until the engine can run it
    self.trainerB = def
    return true
  end
  self.trainerB = def
  self.enemyPartyB = buildTrainerParty(self.game, oppClass, 1, partyDef)
  self.enemyIndexB = 1
  if self.enemyPartyB[1] then
    -- the right-hand opponent is the SECOND trainer's lead, replacing
    -- whatever the first trainer's second Pokemon had been put there
    self:placeBattler(BattleState.POS.OPPONENT_RIGHT,
                      makeBattler(self.game.data, self.enemyPartyB[1], false))
    markSeen(self.game, self.enemyPartyB[1].species)
  end
  return true
end

-- The Battle Tower's opponents are generated, not table-driven: its 70
-- trainers each supply only a name and a class, and the three mons are drawn
-- out of BattleTowerMons at battle time (src/world/BattleTower.lua).  Rather
-- than fork newTrainer, the generated opponent is installed under one reserved
-- class key and fought through the ordinary path, so the pic, the palette, the
-- AI and every battle rule are the same code the rest of the game uses.
--
-- The row is overwritten each time and is never reachable from a script, a
-- sight range or a save, so nothing else can ever battle it.
BattleState.BATTLE_TOWER_CLASS = "OPP_BATTLE_TOWER"

-- The same trick for a team the MAP EDITOR built.
--
-- An NPC the author made a trainer needs a party, and `trainerParty` only ever
-- selected one the cartridge already shipped -- so "make this NPC a trainer"
-- meant "borrow somebody else's six Pokemon". A team the author typed has
-- nowhere to live in `data.trainers`, which is generated from the ROM and
-- rebuilt by the next import.
--
-- So it is installed the way the Battle Tower's generated opponent is: one
-- reserved class key, overwritten per battle, fought through the ordinary
-- `newTrainer` path. The pic, the palette, the AI and every battle rule are
-- then the same code the rest of the game runs -- which is the whole reason
-- the Battle Tower does it this way rather than forking the battle.
--
-- The row is never reachable from a script, a sight range or a save, so
-- nothing else can ever fight it.
BattleState.EDITOR_TRAINER_CLASS = "OPP_EDITOR_TRAINER"

-- `party` is an array of slots in newTrainer's own shape; `look` is the class
-- to borrow a pic, palette and AI from (the NPC's own trainerClass, when it
-- named one).
function BattleState.newEditorTrainer(game, party, look, name)
  local trainers = game.data.trainers
  if type(party) ~= "table" or #party == 0 then return nil, "that team is empty" end
  local base = look and trainers[look] or nil
  local def = {
    id = (base and base.id) or BattleState.EDITOR_TRAINER_CLASS,
    index = (base and base.index) or 0,
    name = name or (base and base.name) or "TRAINER",
    source = "map editor",
    parties = { party },
    partyNames = { name or (base and base.name) or "TRAINER" },
    baseMoney = base and base.baseMoney or 0,
  }
  if base then
    def.pic, def.basePic, def.trueColor = base.pic, base.basePic, base.trueColor
    def.paletteSource, def.aiMods = base.paletteSource, base.aiMods
  end
  trainers[BattleState.EDITOR_TRAINER_CLASS] = def
  return BattleState.newTrainer(game, BattleState.EDITOR_TRAINER_CLASS, 1)
end

function BattleState.newBattleTowerTrainer(game, opponent)
  local trainers = game.data.trainers
  local base = opponent.classKey and trainers[opponent.classKey] or nil
  if not base and opponent.class then
    for _, row in pairs(trainers) do
      if row.index == opponent.class then base = row break end
    end
  end
  local def = {
    -- the palette is keyed off the real class, so keep its id
    id = (base and base.id) or BattleState.BATTLE_TOWER_CLASS,
    index = opponent.class or 0,
    name = opponent.name,
    source = "ROM:BattleTowerTrainers",
    parties = { opponent.party },
    partyNames = { opponent.name },
    -- RunBattleTowerTrainer sets wInBattleTowerBattle, which is what
    -- suppresses the prize money; no base money does the same here
    baseMoney = 0,
  }
  if base then
    def.pic, def.basePic, def.trueColor = base.pic, base.basePic, base.trueColor
    def.paletteSource, def.aiMods = base.paletteSource, base.aiMods
  end
  trainers[BattleState.BATTLE_TOWER_CLASS] = def
  local battle = BattleState.newTrainer(game, BattleState.BATTLE_TOWER_CLASS, 1)
  battle.battleTower = true
  return battle
end

-- The disguise itself.  InitWildBattle .isGhost (engine/battle/core.asm)
-- swaps only the pic and the nick -- wEnemyMonSpecies2 still holds the real
-- species, so the SGB palette stays the disguised mon's.  ghostReal keeps
-- what LoadEnemyMonData puts back when the scope unveils.
local function disguiseAsGhost(self)
  -- picAnim rides along with the pic it belongs to: the GHOST sheet has no
  -- animation of its own, and playing the real species' frames over it would
  -- give the disguise away.
  self.ghostReal = { name = self.enemy.name, sprite = self.enemy.sprite,
                     picAnim = self.enemy.picAnim,
                     species = self.enemy.species }
  self.enemy.name = "GHOST"
  -- and no species, so a renderer standing a MODEL where the pic goes stands
  -- nothing: the GHOST sheet IS the disguise, and a Marowak in full 3D over
  -- it would give the whole scene away before the Silph Scope does.
  self.enemy.species = nil
  self.enemy.picAnim = nil
  self.enemy.sprite = getImage("assets/generated/battle/front/ghost.png",
                               monPalette(self.data, self.enemy.mon.species))
  self.introText = Strings("The GHOST\nappeared!")
end

-- Pokémon Tower ghosts (engine/battle/core.asm): without the Silph Scope
-- the enemy is "GHOST", you're too scared to attack, and balls fail.
function BattleState:makeGhost()
  self.ghost = true
  disguiseAsGhost(self)
end

-- The RESTLESS SOUL with the SILPH SCOPE in the bag.  Mechanically this is
-- not a ghost battle at all -- IsGhostBattle (core.asm) returns false the
-- moment the scope is in the bag, so the mon attacks, is attacked and rolls
-- for flight normally -- but InitWildBattle still enters disguised: its
-- .isGhost branch fires on wCurOpponent == RESTLESS_SOUL as well.  Taking
-- the disguise off is PrintBeginningBattleText .isMarowak's job
-- (engine/battle/common_text.asm), which enter() queues through
-- queueScopeReveal (#492).
function BattleState:makeUnveiledGhost()
  self.scopeReveal = true
  disguiseAsGhost(self)
end

-- MarowakAnim (engine/battle/ghost_marowak_anim.asm) counted in frames: the
-- ghost pic is copied into OAM and flashed 8 times by xor-ing rOBP1 with
-- $80 (10 frames a side), the BG pic underneath is swapped to the RESTLESS
-- SOUL, rOBP1 is shifted left two bits every 10 frames until the ghost has
-- faded into the paper (3 shifts), and the Marowak copy fades back in the
-- same way (4 shifts).  Alpha over the paper is what those OBP shifts look
-- like on screen.
BattleState.GHOST_FLASH_FRAMES = 80
BattleState.GHOST_FADE_OUT_FRAMES = 30
BattleState.GHOST_FADE_IN_FRAMES = 40
BattleState.GHOST_REVEAL_FRAMES = 150

-- The rows .isMarowak prints over the disguise, after the "GHOST appeared!"
-- box enter() has already queued: the unveil line, MarowakAnim, then "Wild
-- MAROWAK appeared!" under the restored name.  The fall-through into
-- .playSFX at the end is the same SFX_TRAINER_APPEARED the port does not
-- play for trainer intros either, so it is left out here too.
function BattleState:queueScopeReveal()
  local unveiled = self.data.text and self.data.text._UnveiledGhostText
  self:say(unveiled
           or Strings("SILPH SCOPE\nunveiled the\vGHOST's identity!"))
  self:act(function() self.ghostReveal = { t = 0 } end)
  table.insert(self.queue, { wait = BattleState.GHOST_REVEAL_FRAMES })
  self:say(self:romText("_WildMonAppearedText", "Wild %s\nappeared!",
                   self.ghostReal and self.ghostReal.name or self.enemy.name))
end

-- The old man's catch tutorial (BATTLE_TYPE_OLD_MAN,
-- engine/battle/core.asm DisplayBattleMenu .oldManName branch): no
-- player mon; the battle menu appears under the OLD MAN's name and a
-- scripted cursor hovers FIGHT, hops to ITEM and forces the item menu
-- (one POKé BALL x50).  The throw always catches; nothing is kept.
-- Yellow's Pallet intro (BATTLE_TYPE_PIKACHU) is the same simulated
-- script under "PROF.OAK" (pokeyellow core.asm .profOakName), so the
-- displayed thrower name is a parameter.
function BattleState:makeOldManDemo(name)
  self.demo = true
  self.demoName = name or "OLD MAN"
  -- LoadPlayerBackPic and DisplayBattleMenu split on the same wBattleType:
  -- BATTLE_TYPE_OLD_MAN gets .oldManName + OldManPicBack, BATTLE_TYPE_PIKACHU
  -- gets .profOakName + ProfOakPicBack (pokeyellow core.asm).  The thrower
  -- name the caller passes IS that distinction here, so it picks the pic too
  -- -- data/scripts/story2.lua is the only site that names PROF.OAK (#557).
  self.oakDemo = name == "PROF.OAK"
  -- Yellow's Pallet intro runs this before the player owns any mon
  -- (BATTLE_TYPE_PIKACHU precedes the lab gift), so newWild flagged the
  -- battle dead for lack of a party.  The demo never sends out, draws, or
  -- acts with the player side; a hidden placeholder battler keeps the
  -- shared battle phases nil-safe.
  if not self.player then
    self.dead = false
    self.player = makeBattler(self.game.data,
      Pokemon.new(self.game.data, self.enemy.mon.species, 5), true)
  end
end

-- Gen2's catching tutorial (engine/events/catch_tutorial.asm CatchTutorial,
-- reached from `catchtutorial BATTLETYPE_TUTORIAL` on Route 29 in Gold,
-- Silver and Crystal alike).  It is the same shape as the old man's demo and
-- reuses all of it -- a scripted cursor, a one-entry bag, a throw that always
-- catches, nothing kept -- with three differences the ROM makes explicit:
--
--   * the thrower's name is DUDE, because CatchTutorial copies "DUDE" over
--     wPlayerName for the duration and puts the real name back afterwards;
--   * the player's OWN lead Pokemon is on the field.  Gen1's old man has no
--     mon at all, but core.asm's `.tutorial_debug` only SKIPS the
--     find-a-healthy-mon loop -- wCurBattleMon stays 0 -- so the back pic and
--     the player HUD are drawn normally;
--   * the bag holds one POKe BALL, not fifty (.LoadDudeData writes
--     wDudeNumBalls = 1).
--
-- The capture cannot fail: ItemUseBall reads wBattleType and jumps straight
-- to .catch_without_fail (item_effects.asm:243-246), and .FinishTutorial
-- returns before any of the caught-mon bookkeeping (:501-503).
--
-- HOENN'S IS THE SAME BATTLE.  BATTLE_TYPE_WALLY_TUTORIAL is Gen 2's shape
-- exactly -- a scripted cursor, one ball, a throw that cannot miss, nothing
-- kept, and the thrower's own Pokemon on the field (Wally is lent a ZIGZAGOON
-- by the script before it starts) -- so the only thing that differs is the
-- name over the menu, and that is a parameter.
function BattleState:makeDudeDemo(name)
  self:makeOldManDemo(name or "DUDE")
  self.dudeDemo = true
  self.demoBallCount = "x1"
end

-- Gen1's demo hides the player's side entirely; Gen2's does not (see
-- makeDudeDemo).  Every "is this a demo?" test that is really asking "is the
-- player's half of the screen empty?" goes through here.
function BattleState:demoHidesPlayer()
  return self.demo and not self.dudeDemo
end

-- Safari Zone battles (engine/battle/core.asm safari sections +
-- engine/battle/safari_zone.asm): no player mon acts; the menu is
-- BALL / BAIT / ROCK / RUN.  state is save.safari ({balls, steps}).
function BattleState:makeSafari(state)
  self.safari = state
  self.safariCatchRate = self.enemy.def.catchRate
  self.baitFactor = 0
  self.escapeFactor = 0
end

-- Bug Catching Contest battles (BATTLETYPE_CONTEST).  Unlike the Safari Zone
-- this is a NORMAL battle -- your lead is out, it can attack, and weakening
-- the wild mon first is the whole strategy.  Only the third menu slot
-- changes: BattleMenu_Pack's `.contest` arm (engine/battle/core.asm:4990)
-- skips the pack entirely and throws a PARK_BALL straight from the menu, so
-- the slot reads "PARKBALL x NN" instead of ITEM.
--
-- The ball count is NOT held here: wParkBallsRemaining lives on the save, so
-- the menu reads it live and a mid-battle save/quit cannot desync it.
function BattleState:makeBugContest()
  self.bugContest = true
end

-- wParkBallsRemaining, for the menu row and the out-of-balls exit.
function BattleState:bugContestBalls()
  return require("src.world.BugContest").ballsLeft(self.game.save)
end

-- ---------------------------------------------------------------------
-- message/action queue
-- ---------------------------------------------------------------------

function BattleState:say(text)
  table.insert(self.queue, { text = text })
end

-- Message that opens YES/NO once typed out, keeping the text visible
-- underneath (pokered `done` + TWO_OPTION_MENU / TextBox opts.choice).
function BattleState:sayChoice(text, onChoose)
  table.insert(self.queue, { text = text, choice = onChoose })
end

function BattleState:act(fn)
  table.insert(self.queue, { fn = fn })
end

-- push a UI state above the battle; the queue pauses until it pops
function BattleState:ui(factory)
  table.insert(self.queue, { ui = factory })
end

-- insert an animation row right after the current queue item (the
-- POOF/ball-toss animations past the move table); `shakes` marks the
-- ball-shake row with its wNumShakes repeat count, `ball` marks a toss
-- row with the thrown ball item (wCurItem -- a Master/Ultra toss
-- flickers the OBJ palette, DoBallTossSpecialEffects), and `caught` is the
-- roll's verdict, which Gen 2's toss script needs because it wobbles and
-- then clicks or breaks free from inside the animation itself
function BattleState:animNext(name, isPlayer, shakes, ball, caught)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert,
               { anim = name, attackerIsPlayer = isPlayer, shakes = shakes,
                 ball = ball, caught = caught })
end

-- ---------------------------------------------------------------------------
-- The Gen 2 shiny sparkle
--
-- GSC does not have a shiny animation of its own.  BattleAnim_SendOutMon
-- opens with `anim_if_param_equal $1, .Shiny`, and core.asm simply plays that
-- animation A SECOND TIME with wBattleAnimParam = 1 whenever CheckShininess
-- says the mon is shiny:
--
--   :3566  the enemy trainer's send-out -- normal pass, then the sparkle
--   :4057  the player's send-out        -- normal pass, then the sparkle
--   :9091  a WILD encounter             -- the sparkle ONLY; a wild mon is
--                                          already on screen and never gets
--                                          the poof
--
-- so this is queued after each send-out rather than being a row in the
-- animation table.  Gen 1 has no such thing, so it is gated on the Gen 2
-- player being the one running -- a Red/Blue battle queues nothing.
--
-- `isPlayer` follows the poof's convention (Gen2AnimPlayer flips it): false
-- for the player's own mon, true for the foe's.
function BattleState:shinyAnim(battler, isPlayer)
  if not (self.data and self.data.battle_anims and self.data.battle_anims.gen2) then
    return false
  end
  local mon = battler and battler.mon
  if not (mon and require("src.pokemon.Pokemon").isShiny(mon)) then return false end
  self:animNext("SHINY_ANIM", isPlayer)
  return true
end

-- The same, appended rather than inserted: the battle intro is built linearly
-- before the queue starts running, where animNext's insert point does not
-- apply.
function BattleState:shinyAnimAppend(battler, isPlayer)
  if not (self.data and self.data.battle_anims and self.data.battle_anims.gen2) then
    return false
  end
  local mon = battler and battler.mon
  if not (mon and require("src.pokemon.Pokemon").isShiny(mon)) then return false end
  table.insert(self.queue, { anim = "SHINY_ANIM", attackerIsPlayer = isPlayer })
  return true
end

-- insert an act right after the current queue item
function BattleState:actNext(fn)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { fn = fn })
end

-- insert message right after the currently-executing queue item (the
-- counter is reset by updateQueue before each fn item runs)
function BattleState:sayNext(text)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { text = text })
end

-- insert a UI push right after the current queue item (dex page, the
-- level-up stat box -- anything that must keep queue order)
function BattleState:uiNext(factory)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { ui = factory })
end

-- ui rows compose screens unpushed (updateQueue pushes them), so
-- Screens.push's mod-screen degrade can't cover them; mirror it here,
-- stamping the id the same way
-- THE GEN 3 ALIAS APPLIES HERE TOO.
--
-- Screens.push resolves "PartyMenu" to "Gen3PartyMenu" on a Hoenn cartridge,
-- but the battle does not push its screens -- it OWNS its UI slot and builds
-- them -- and this path went straight to Screens.get, which does not resolve.
-- So the four screens the alias exists for were Emerald's everywhere in the
-- game EXCEPT inside a battle, which is the one place a player is looking
-- hardest.  Same rule as the push: only a single options table can be
-- aliased, because that is the only shape the Gen 3 screens take.
-- The shortest a coarse reaction may be and still read as one, in frames.
BattleState.COARSE_ANIM_MIN = 8

function BattleState:buildScreen(id, ...)
  local game = self.game
  local unpack_ = table.unpack or unpack   -- LuaJIT (LOVE) compatibility
  local args = { n = select("#", ...), ... }
  local resolvedId = id
  if args.n <= 1 then
    local rid, rarg = Screens.resolveId(game, id, args[1])
    if rid ~= id then resolvedId, args = rid, { n = 1, rarg } end
  end
  local factory = Screens.get(game, resolvedId)
  local function build()
    return factory.new(game, unpack_(args, 1, args.n))
  end
  local inst
  if factory.__modOwned then
    -- a broken mod screen degrades to the builtin, never a dead end
    local ok, result = pcall(build)
    if ok and result then
      inst = result
    else
      Logger.error("mod screen '%s' failed: %s -- using builtin",
                   resolvedId, tostring(result))
      Screens.invalidate()
      inst = require("src.ui." .. resolvedId)
               .new(game, unpack_(args, 1, args.n))
    end
  else
    inst = build()
  end
  inst.screenId = inst.screenId or resolvedId
  return inst
end

-- insert a wait for the HP bars to finish draining (UpdateHPBar):
-- the queue holds until every battler's displayed HP catches up.
-- `stopAt` pins how far that battler's bar may drain on this row.  A
-- multi-hit move takes every strike off the model while the turn is still
-- being queued, so an unpinned row would drain straight to the
-- post-last-hit HP and the later strikes would animate nothing (#394);
-- ApplyDamageToEnemyPokemon runs UpdateHPBar2 once per strike inside the
-- wNumAttacksLeft loop (engine/battle/core.asm:4727).
function BattleState:drainNext(battler, stopAt)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert,
               { drain = true, battler = battler, stopAt = stopAt })
end

-- Queue AnimateExpBar at the current insert point.  `from` is the pixel length
-- the bar had BEFORE the exp was applied, and it is pinned immediately rather
-- than when the row runs, so the bar holds the old length through the "gained
-- EXP. Points!" box instead of flashing the new one first.
function BattleState:expBarNext(from)
  self.expShown = from
  self.expHold = 0
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { expBar = true })
end

-- Queue a pure frame hold at the current insert point, the way the original
-- spends DelayFrames between the beats of a turn.  Mirrors sayNext/drainNext
-- so a caller can interleave holds with messages in source order.
function BattleState:waitNext(frames)
  if not frames or frames <= 0 then return end
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = frames })
end

-- One frame of the HP-bar drain (engine/gfx/hp_bar.asm UpdateHPBar).
--
-- The original walks the bar ONE HP POINT per loop iteration (:81-120), and
-- what each iteration costs depends on the side:
--   * UpdateHPBar_PrintHPNumber spends a DelayFrame (:234) reprinting the
--     number, but only when wHPBarType is nonzero (:207-209) -- the player's
--     own HUD and the party menu, never the enemy's;
--   * UpdateHPBar_AnimateHPBar spends 2 frames for each pixel the bar
--     actually moved (:147-148), and most single-HP steps move none.
-- So the player's bar drains at 1 HP per frame plus 2 frames per pixel,
-- while the enemy's costs nothing until it crosses a pixel boundary.  The
-- old flat maxHP/96 rate was the enemy-side formula applied to both, which
-- ran a 150 HP mon's full drain in 96 frames against hardware's 249.
--
-- Returns true while animating.
function BattleState:stepHPDrain()
  local busy = false
  for _, b in activeBattlers(self) do
    if b and b.shownHP then
      -- drainFloor is the stop the running row carries (see drainNext)
      local goal = b.mon.hp
      if b.drainFloor and b.drainFloor > goal
         and b.shownHP >= b.drainFloor then
        goal = b.drainFloor
      end
      if (b.drainHold or 0) > 0 then
        b.drainHold = b.drainHold - 1
        busy = true
      elseif b.shownHP ~= goal then
        local maxHP = math.max(1, b.mon.stats.hp)
        -- by SIDE, not by identity: in a double the right-hand player
        -- slot is not `self.player` and its bar still drains downward
        local playerSide = b.isPlayer == true
        local cost = 0
        -- consume whole HP steps until this frame's budget is spent; on the
        -- enemy HUD several free steps can land in the same frame
        while b.shownHP ~= goal and cost < 1 do
          local nextHP = b.shownHP + ((b.shownHP > goal) and -1 or 1)
          cost = cost + Timing.hpDrainStepFrames(b.shownHP, nextHP,
                                                 maxHP, playerSide)
          b.shownHP = nextHP
        end
        b.drainHold = math.max(0, cost - 1)
        b.draining = true
        busy = true
      elseif b.draining then
        -- .animateHPBarDone's final number print, one more pixel step and
        -- Delay3 (hp_bar.asm:132-135); this frame is the first of them
        b.draining = nil
        b.drainHold = Timing.hpDrainClosingFrames(b.isPlayer == true) - 1
        busy = true
      end
    end
  end
  return busy
end

-- AnimateExpBar (engine/battle/experience.asm) creeps the bar to its new
-- length a pixel at a time with a tick of sound behind it, instead of
-- redrawing it at the new length; the bar drawing itself off the live exp is
-- why it snapped.  self.expShown is the pixel count the HUD draws while a
-- fill is running, and nil the rest of the time so the bar follows the mon.
BattleState.EXP_BAR_STEP_FRAMES = 2

-- HOW FULL THE BAR IS, 0 to 1 -- which is what a Hoenn healthbox wants.
--
-- Reported from play: "the exp bar doesnt increase at all after defeating a
-- pokemon".  The Emerald HUD drew its fill off `battle.expFraction`, and
-- nothing in the engine ever set that field: a reader with no writer, so the
-- bar sat at zero through every battle in the game while the exp itself went
-- up perfectly well behind it.
--
-- It follows the SAME state the Game Boy bar does: expShown while a fill is
-- creeping (so the Hoenn bar animates too, rather than snapping), and the
-- mon's own exp the rest of the time.
function BattleState:expFraction(mon)
  mon = mon or (self.player and self.player.mon)
  if not mon then return 0 end
  local HudTiles = require("src.render.HudTiles")
  local length = HudTiles.geometry().expBarTiles * 8
  if length <= 0 then return 0 end
  local pixels = (mon == (self.player and self.player.mon) and self.expShown)
                 or HudTiles.expBarPixels(self.data, mon)
  return math.max(0, math.min(1, pixels / length))
end

-- Returns true while still filling.
function BattleState:stepExpBar()
  if not (self.player and self.expShown) then return false end
  local HudTiles = require("src.render.HudTiles")
  local target = HudTiles.expBarPixels(self.data, self.player.mon)
  if self.expShown == target then
    self.expShown = nil
    return false
  end
  if (self.expHold or 0) > 0 then
    self.expHold = self.expHold - 1
    return true
  end
  local shown = self.expShown + 1
  -- a level-up moved the goal BACKWARDS: the ROM runs the bar off the right
  -- end, wraps it to empty and keeps going, which is what a level looks like.
  -- The wrap point is the BAR's length, not a constant: on a cartridge with a
  -- nine-tile bar every target from 65 to 72 sits past a hardcoded 64, so the
  -- fill wrapped to empty and set off again, forever.
  if shown > HudTiles.geometry().expBarTiles * 8 then shown = 0 end
  self.expShown = shown
  self.expHold = BattleState.EXP_BAR_STEP_FRAMES - 1
  return true
end

-- the integer HP the HUD shows for a battler (whole HP ticks, like
-- UpdateHPBar's 1-HP steps)
local function shownHP(b)
  local shown = b.shownHP or b.mon.hp
  if shown > b.mon.hp then return math.ceil(shown) end
  return math.floor(shown)
end

-- Parse a battle message into its rendered lines.  The extractor marks
-- \n = next line and \v = CONT (home/text.asm ContText: draw the blinking
-- ▼, WaitForTextScrollButtonPress, then ScrollTextUpOneLine); the boosted /
-- EXP.ALL exp lines end in the CONT code in the ROM (data/generated/text.lua
-- _BoostedText/_WithExpAllText = "...\011").  Each entry is { codes, cont },
-- cont true when the line was preceded by \v.  Splitting before Font.encode
-- keeps the control chars out of the glyph stream.  The box then types into
-- a rolling 2-line window (self.shown) that scrolls when a 3rd line arrives
-- instead of drawing it off-screen at y=144 (#216).
function BattleState:startMessage(item)
  self.current = item
  self.lines = {}
  self.total = 0
  local text = item.text or ""
  local pos, cont = 1, false
  while true do
    local npos = text:find("[\n\v]", pos)
    local chunk = npos and text:sub(pos, npos - 1) or text:sub(pos)
    local codes = Font.encode(chunk)
    self.lines[#self.lines + 1] = { codes = codes, cont = cont }
    self.total = self.total + #codes
    if not npos then break end
    cont = text:sub(npos, npos) == "\v"
    pos = npos + 1
  end
  self.shown = {}        -- up to two visible lines of revealed glyph codes
  self.lineIndex = 0
  -- self.charIndex counts glyphs typed across the WHOLE message (drivers read
  -- it against self.total); the current line's revealed count is #shown[last]
  self.charIndex = 0
  self.msgWaiting = nil
  self.msgPrompt = nil
  self.scrollPx = nil
  self:beginMsgLine()
end

-- Start typing the next line into the rolling window.  When the box already
-- shows two lines, drop the top one and set the pixel scroll-up
-- (ScrollTextUpOneLine), mirroring TextBox:beginLine.
function BattleState:beginMsgLine()
  self.lineIndex = self.lineIndex + 1
  local ln = self.lines[self.lineIndex]
  self.codes = ln and ln.codes or {}
  if #self.shown >= 2 then
    table.remove(self.shown, 1)
    self.scrollPx = 8
  end
  self.shown[#self.shown + 1] = {}
end

function BattleState:updateQueue()
  if self.waitingUI then
    if self.game.stack:top() ~= self then return true end
    self.waitingUI = nil
  end
  -- HOENN'S PARTICLES TICK BEFORE THE QUEUE'S OWN HOLD, and the whole
  -- reason the animations looked broken is that they used to tick after it.
  --
  -- Reported from play: "many dont show until after damage is done to the
  -- enemy pokemon".  The Gen 3 player does not hold the queue with
  -- animPlaying; it sets waitFrames to the animation's length.  The tick sat
  -- BELOW the waitFrames gate, so for exactly as long as the animation was
  -- meant to run, updateQueue returned at the gate and never advanced its
  -- clock -- the particles stood frozen on frame zero, and only once the
  -- hold expired did the animation begin to play, on top of the damage that
  -- had been waiting behind it.  It has to be counted where the frames are.
  if self.gen3AnimPlaying and self.gen3Anim then
    self.gen3Anim:update()
    if self.gen3Anim:isDone() then
      self.gen3AnimPlaying = false
      self.gen3Anim:release()
    end
  end
  -- ...and the ball's own timeline, ticked in the same place and for the same
  -- reason: its frames are counted where the hold is counted, or it would
  -- stand still for exactly as long as it is meant to be moving.
  if self.gen3BallPlaying and self.gen3Ball then
    local anim = self.gen3Ball
    anim:update()
    if anim.sound then
      require("src.core.Sound").playId(self.data, anim.sound)
    end
    -- the trainer is gone by the time his Pokemon is out of the ball
    if anim.sendOut == "player" and self.showPlayerBack
        and anim.phase ~= "throw" then
      self.showPlayerBack = false
      self:slidePic("back")
    end
    if anim:isDone() then
      self.gen3BallPlaying = false
      -- a caught Pokemon leaves the ball resting on screen through the text,
      -- exactly as the Game Boy chain does
      if not anim.caught then self.gen3Ball = nil end
    end
  end
  -- a queued hold (faint slide, hit blink) counts down before the next row
  if self.waitFrames and self.waitFrames > 0 then
    self.waitFrames = self.waitFrames - 1
    return true
  end
  -- WaitForSoundToFinish (home/delay.asm:15-20) blocks until the sfx has
  -- actually stopped sounding, which is how the original gives a sound its
  -- own clear window instead of letting the next beat play over it
  if self.waitingSound then
    local src = self.waitingSound
    if src and src.isPlaying and src:isPlaying() then return true end
    self.waitingSound = nil
  end
  -- an HP-bar drain holds the queue until the bar catches up
  if self.draining then
    if self:stepHPDrain() then return true end
    self.draining = nil
    if self.player then self.player.drainFloor = nil end
    if self.enemy then self.enemy.drainFloor = nil end
  end
  -- ...and the exp bar's own fill holds it the same way
  if self.expFilling then
    if self:stepExpBar() then return true end
    self.expFilling = nil
  end
  if self.animPlaying then
    self.animPlayer:update()
    if self.animPlayer.pollEffects and self.applyAnimEffect then
      for _, ev in ipairs(self.animPlayer:pollEffects()) do
        self:applyAnimEffect(ev)
      end
    end
    if self.animPlayer:isDone() then
      self.animPlaying = false
      -- BattleAnim_Clean ends every effect the script left running and the
      -- battle screen redraws with rBGP back at $e4, so a fade the script
      -- never closed itself (Growl's FADE_MON_TO_BLACK_REPEATING) cannot
      -- outlive its animation -- it used to tint the mon for the rest of
      -- the battle.  A running flash sequence is self-terminating and is
      -- left to ride out its own frames.
      if self.fx then self.fx.bgp = nil end
      -- ...and it redraws the mon PICS as well, so a hide the script never
      -- undid cannot outlive its animation either.  Moves like TAIL_WHIP
      -- queue a hide with no matching show; that used to sit there until the
      -- NEXT animation's resetPicFx happened to clear it, which from the
      -- player's side looks like the mon vanishing until something hits it
      -- again.  Dig/Fly's charge hide and a genuinely invulnerable battler
      -- are the two that must survive, same as in resetPicFx.
      self:restoreHiddenPics()
      -- the target's hit blink + damage sound follow the animation
      -- (pokered plays them after PlayMoveAnimation returns)
      if self.pendingHit then
        self:applyHitFx(self.pendingHit)
        self.pendingHit = nil
      end
    end
    return true
  end
  if not self.current then
    local item = table.remove(self.queue, 1)
    if not item then return false end
    if item.fn then
      self.nextInsert = 0 -- sayNext inserts right after this item
      item.fn()
      self.current = nil
      return true
    end
    if item.ui then
      self.waitingUI = true
      self.game.stack:push(item.ui())
      return true
    end
    if item.drain then
      self.draining = true
      if item.battler then item.battler.drainFloor = item.stopAt end
      return true
    end
    if item.expBar then
      self.expFilling = true
      return true
    end
    if item.wait then
      self.waitFrames = item.wait
      return true
    end
    if item.waitSound then
      -- the source is fetched now, not when the row was queued, so the
      -- act() that started the sound has already run
      self.waitingSound = item.waitSound()
      return true
    end
    if item.mimicSelect then
      -- pause the queue on Mimic's copy menu (MoveSelectionMenu with
      -- wMoveMenuType = 1 lists the enemy's moves; cursor starts on 1)
      local ctx = item.mimicSelect
      local rows = {}
      for i, m in ipairs(ctx.target.curMoves) do
        if m.id and m.pp ~= nil then rows[#rows + 1] = { slot = i, id = m.id } end
      end
      self.mimicMoves = rows
      self.mimicIndex = 1
      self.mimicCtx = ctx
      self.phase = "mimicSelect"
      return true
    end
    -- animation queue rows: play the move sound and start the
    -- subanimation (or just the coarse fx when animations are off).
    -- item.hit carries the target's blink + damage sound, applied when
    -- the animation ends (hitRow rows carry a hit with no animation --
    -- thrash/rage continuation turns that skip the announcement).
    if item.anim or item.hitRow then
      -- PlayMoveAnimation writes wAnimationID, calls Delay3, and only then
      -- jumps to MoveAnimation (core.asm:6635-6640), so three frames pass
      -- between the move's announcement and the first frame of its
      -- animation.  Put the row back and pay that first.
      if item.anim and not item.animDelayed then
        item.animDelayed = true
        table.insert(self.queue, 1, item)
        self.waitFrames = Timing.MOVE_ANIM_PRE
        return true
      end
      local mdef = item.anim and self.data.moves[item.anim]
      local anim = mdef and mdef.anim
      if item.anim == "POOF_ANIM" then
        -- the send-out poof plays SFX_BALL_POOF
        require("src.core.Sound").play(self.data, "Ball_Poof")
      elseif item.anim == "HIDEPIC_ANIM" then
        self.enemyHidden = true    -- SE_HIDE_ENEMY_MON_PIC
      elseif item.anim == "SHOWPIC_ANIM" then
        self.enemyHidden = false   -- SE_SHOW_ENEMY_MON_PIC
      end
      -- ball/send-out anims ignore the OPTIONS toggle: PlayMoveAnimation
      -- short-circuits to TossBallAnimation before its wOptions check
      -- (engine/battle/animations.asm:415)
      if item.anim and (self:animationsOn() or BALL_ANIMS[item.anim]) then
        -- HOENN'S OWN ANIMATION, when the move has one.  It does not take the
        -- animPlaying path: that one belongs to the Game Boy players, which
        -- carry their own per-row sounds, and this one does not -- so the
        -- single-sound fallback below still runs and the move both looks and
        -- sounds like itself.  The queue is held with waitFrames instead, for
        -- as long as the script's own delays plus the particles' life.
        if self.gen3Anim and self.gen3Anim:has(item.anim)
           and self.gen3Anim:start(item.anim, item.attackerIsPlayer) then
          self.gen3AnimPlaying = true
          self.waitFrames = math.max(self.waitFrames or 0,
                                     self.gen3Anim.total or 0)
        elseif self.animPlayer then
          local ok, started = pcall(self.animPlayer.start, self.animPlayer,
                           item.anim, item.attackerIsPlayer,
                           (item.shakes or item.ball)
                             and { shakes = item.shakes, ball = item.ball,
                                   caught = item.caught,
                                   -- Gen 2's toss script branches on the
                                   -- ball's item index (wBattleAnimParam)
                                   ballIndex = item.ball
                                     and (self:itemDef(item.ball) or {}).index
                                     or nil,
                                   ballFlicker = item.ball
                                     and self:ballFlicker(item.ball) or nil }
                             or nil)
          -- a player that reports no data for the move (Gen 2 returns
          -- false) falls through to the single-sound path below
          self.animPlaying = ok and started ~= false
        end
        self.fx = self.fx or {}
        -- HOW LONG THE COARSE REACTION LASTS.
        --
        -- The reaction is a class this port chose; its LENGTH is the move's
        -- own. Every one of these scripts still walks its delays, and the
        -- import carries that total across (`anim.duration`), so EARTHQUAKE
        -- heaves for as long as its script runs and HARDEN's flourish is over
        -- in its own handful of frames. The old fixed 24 and 16 are what a
        -- dataset imported before that stamp still gets.
        local coarse = anim and tonumber(anim.duration) or nil
        -- A REACTION HAS TO LAST LONG ENOUGH TO BE ONE.  Thirteen of the
        -- twenty-five carry a length; the shortest of them is a single frame,
        -- because everything that script does happens inside its task and the
        -- delays it walks are almost none. One frame of shake is not a
        -- reaction, it is a glitch, so below one visible beat the port's own
        -- minimum stands.
        if coarse and coarse < BattleState.COARSE_ANIM_MIN then coarse = nil end
        -- THE HEAVE FIRST, because it is the cartridge's own numbers and
        -- the wobble below is this port's.  EARTHQUAKE swings the field
        -- thirteen pixels fifty times, every second frame; the coarse
        -- fallback swung it two, for twenty-four frames.  The program is
        -- the same one the SE-driven shakes already run.
        if anim and anim.heave and not self.animPlaying then
          local h = anim.heave
          local amplitude = tonumber(h.amplitude) or 0
          local every = math.max(1, tonumber(h.every) or 2)
          local swings = math.max(1, tonumber(h.swings) or 1)
          if amplitude > 0 then
            local prog = {}
            for i = 0, swings - 1 do
              prog[#prog + 1] = { dx = (i % 2 == 0) and amplitude
                                       or -amplitude, frames = every }
            end
            -- ...and back to where it started, as the task's own last act is
            -- to put the register back
            prog[#prog + 1] = { dx = 0, frames = every }
            self.fx.shakeProg = prog
            self.waitFrames = math.max(self.waitFrames or 0,
                                       (swings + 1) * every)
          end
        end
        if anim and anim.shake and not self.animPlaying then
          self.fx.shake = coarse or 24
        end
        if anim and anim.flash and not self.animPlaying then
          self.fx.flash = coarse or 16
        end
        -- IN HOENN the coarse reaction is the move's whole animation, not a
        -- consolation for one that could not play: the moves that get it are
        -- the ones whose every pixel is drawn by a task -- HARDEN, AGILITY,
        -- EARTHQUAKE -- and there is nothing else coming.  So the queue waits
        -- for it, the way it waits for the particles; on a Game Boy dataset
        -- (no Gen 3 player at all) the timing is untouched.
        if self.gen3Anim and not self.gen3AnimPlaying and anim
           and (anim.shake or anim.flash) and not self.animPlaying then
          self.waitFrames = math.max(self.waitFrames or 0,
                                     coarse or (anim.shake and 24 or 16))
        end
      end
      if self.animPlaying then
        -- the animation rows carry their own sounds (PlayAnimation
        -- plays each row's MoveSoundTable entry with its pitch/tempo
        -- modifiers); which side the pic effects target follows the
        -- attacker (hWhoseTurn)
        self.animName = item.anim
        self.animAttackerIsPlayer = item.attackerIsPlayer
        self:resetPicFx()
        for _, ev in ipairs(self.animPlayer:pollEffects()) do
          self:applyAnimEffect(ev) -- frame-0 rows (first sound/effect)
        end
        self.pendingHit = item.hit
      else
        -- no subanimation player: keep the single-sound fallback (with
        -- the move's pitch/tempo modifiers; GROWL/ROAR play the
        -- attacker's cry -- GetMoveSound/IsCryMove)
        if item.anim == "GROWL" or item.anim == "ROAR" then
          local attacker = item.attackerIsPlayer and self.player or self.enemy
          if attacker then
            require("src.core.Sound").playMoveCry(self.data, attacker.mon.species,
                                                   anim and anim.tempo)
          end
        elseif anim and anim.sound then
          local Sound = require("src.core.Sound")
          if Sound.playMove then
            Sound.playMove(self.data, anim)
          else
            Sound.play(self.data, anim.sound)
          end
        end
        if item.hit then
          self:applyHitFx(item.hit)
        end
      end
      self.current = nil
      return true
    end
    self:startMessage(item)
  end
  local input = self.game.input
  -- a \v CONT wait holds the box until A/B, then scrolls the next line in
  -- (home/text.asm ContText); this keeps a 3rd line on-screen (#216)
  if self.msgWaiting then
    -- _ContText prints the â–¼ and runs ProtectedDelay3 BEFORE ManualTextScroll
    -- starts watching the joypad (home/text.asm:263-267), so three frames
    -- pass with the arrow up and the button ignored
    if (self.msgPreWait or 0) > 0 then
      self.msgPreWait = self.msgPreWait - 1
      return true
    end
    if input:wasPressed("a") or input:wasPressed("b") then
      self.msgWaiting = nil
      self:beginMsgLine()
      -- then the two ScrollTextUpOneLine calls block for 5 frames each
      -- (home/text.asm:280-305) before the next line starts typing
      self.waitFrames = Timing.TEXT_SCROLL_PAIR
    end
    return true
  end
  local cur = self.shown[#self.shown]
  if #cur < #self.codes then
    -- Battle text prints through the same PrintText path as everything
    -- else, so it pays PrintLetterDelay per character (home/print_text.asm:
    -- 4-45): hFrameCounter is loaded from wOptions & $f -- the OPTION text
    -- speed, 1/3/5, default 3 -- and the loop spins until it drains, unless
    -- A or B is held, which collapses the wait to a single DelayFrame.
    -- This used to run two glyphs per frame flat, six times hardware speed
    -- at the default setting, and ignored the text-speed option entirely.
    local delay = (self.game.save.options and self.game.save.options.textSpeed)
                  or 3
    if delay ~= 1 and delay ~= 3 and delay ~= 5 then delay = 3 end
    if input:isDown("a") or input:isDown("b") then delay = 1 end
    self.charTimer = (self.charTimer or 0) + 1
    while self.charTimer >= delay and #cur < #self.codes do
      self.charTimer = self.charTimer - delay
      cur[#cur + 1] = self.codes[#cur + 1]
      self.charIndex = self.charIndex + 1
    end
  elseif self.lineIndex < #self.lines then
    -- current line finished, more lines remain: \v waits for A/B + ▼ before
    -- scrolling, \n advances now (beginMsgLine scrolls if the box is full)
    if self.lines[self.lineIndex + 1].cont then
      self.msgWaiting = true
      self.msgPreWait = Timing.TEXT_PRE_ADVANCE
    else
      self:beginMsgLine()
    end
  else
    local item = self.current
    -- TrainerAboutToUseText ends in `done` then DisplayTextBoxID: YES/NO
    -- overlays the still-visible "Will … change POKéMON?" page.
    if item and item.choice and not item.choiceOpen then
      item.choiceOpen = true
      self.waitingUI = true
      local ChoiceBox = require("src.ui.ChoiceBox")
      local battle = self
      self.game.stack:push(ChoiceBox.new(self.game, function(yes)
        local fn = item.choice
        battle.current = nil
        fn(yes)
      end))
      return true
    end
    if not (item and item.choice) then
      -- The page is typed out and waiting on the player: PromptText
      -- (home/text.asm:209-217) writes '▼' at (18,16) and ManualTextScroll
      -- blinks it until A/B, so the arrow belongs on a finished page and not
      -- only on a \v CONT hold (#317).  A flag of its own, not msgWaiting:
      -- that branch above scrolls the NEXT line in, which this page has not
      -- got, so reusing it would call beginMsgLine on a drained message.
      if not self.msgPrompt then
        self.msgPrompt = true
        -- PromptText runs ProtectedDelay3 between writing the arrow and
        -- ManualTextScroll (home/text.asm:213-217), so the page holds for
        -- three frames with the button ignored before it can be dismissed.
        -- Without it a queued A press could clear a page the same frame its
        -- last glyph landed, which is most of "it doesn't hold sometimes".
        self.msgPromptWait = Timing.TEXT_PRE_ADVANCE
      end
      if (self.msgPromptWait or 0) > 0 then
        self.msgPromptWait = self.msgPromptWait - 1
      elseif input:wasPressed("a") or input:wasPressed("b") then
        self.msgPrompt = nil
        self.current = nil
      end
    end
  end
  return true
end

-- ---------------------------------------------------------------------
-- update / menus
-- ---------------------------------------------------------------------

-- PrintSendOutMonMessage (engine/battle/common_text.asm): the shout
-- scales with the enemy's remaining HP percentage, approximated as
-- curHP * 25 / (maxHP / 4): >=70 "Go!", 40-69 "Do it!", 10-39
-- "Get'm!", below 10 "The enemy's weak!  Get'm!".
function BattleState:sendOutText(name)
  local e = self.enemy and self.enemy.mon
  local pct = 100
  if e and e.hp > 0 and math.floor(e.stats.hp / 4) > 0 then
    pct = math.floor(e.hp * 25 / math.floor(e.stats.hp / 4))
  end
  if pct >= 70 then return Strings("Go! %s!", name) end
  if pct >= 40 then return Strings("Do it! %s!", name) end
  if pct >= 10 then return Strings("Get'm! %s!", name) end
  return self:romText("_EnemysWeakText", "The enemy's weak!\nGet'm! %s!", name)
end

-- audio/play_battle_music.asm: gym leaders (wGymLeaderNo) get the
-- gym-leader theme, Lance does too, and the Champion (OPP_RIVAL3)
-- gets the final-battle theme
-- PlayBattleMusic (11:$458D) picks the trainer theme off the trainer CLASS,
-- not off any badge table: CHAMPION ($10) and $3F take the champion theme,
-- then IsKantoGymLeader / IsGymLeader test the class against GymLeaders
-- (0F:$5089) for the gym themes.  These are that list, read out of the ROM.
--
-- Every Gen2 leader shares the class NAME "LEADER", so there is nothing to
-- match on by name -- it has to be the class id.
local GEN2_BADGE_LEADER_CLASSES = {
  -- Johto, then Kanto (IsKantoGymLeader, 0F:$5097)
  [1] = true, [2] = true, [3] = true, [4] = true,
  [5] = true, [6] = true, [7] = true, [8] = true,
  [17] = true, [18] = true, [19] = true, [21] = true,
  [26] = true, [35] = true, [46] = true, [64] = true,
}
-- Also in GymLeaders, so they take the gym theme, but they hand out no badge
-- and must not count as a gym leader for the companion happiness bump.
local GEN2_ELITE_FOUR_CLASSES = {
  [11] = true, [13] = true, [14] = true, [15] = true,
}
local GEN2_CHAMPION_CLASSES = { [16] = true, [63] = true }
-- Only these two Kanto lists exist; GymLeaders (0F:$5137) runs straight on
-- into KantoGymLeaders (0F:$5145) and the $FF that ends it, so IsGymLeader
-- matches the whole run while IsKantoGymLeader matches only the tail.
local GEN2_KANTO_LEADER_CLASSES = {
  [0x11] = true, [0x12] = true, [0x13] = true, [0x15] = true,
  [0x1A] = true, [0x23] = true, [0x2E] = true, [0x40] = true,
}
-- `ld de, MUSIC_RIVAL_BATTLE / cp RIVAL1 / jr z / cp RIVAL2`.  Both classes
-- are named "RIVAL"; RIVAL2 keeps the rival theme only while wOtherTrainerID
-- is below 4 -- the Indigo Plateau fight is party 4 and takes the champion
-- theme instead.
local GEN2_RIVAL_CLASSES = { [0x09] = true, [0x2A] = true }
-- `ld de, MUSIC_ROCKET_BATTLE / cp $1F / jr z / cp $42`.  Both are named
-- "ROCKET"; the other Rocket classes (the executives, the scientists) are
-- deliberately not in this test and take the ordinary trainer theme.
local GEN2_ROCKET_CLASSES = { [0x1F] = true, [0x42] = true }

-- RegionCheck (crystal 72:$6EA1): the current map's landmark decides the
-- region, and PlayBattleMusic swaps the wild AND the plain-trainer theme on
-- it.  $5F is SPECIAL_MAP and counts as Johto; landmark 0 means the map has
-- none of its own, and the backup map is consulted instead; below $2F is
-- Johto and everything else is not.
local GEN2_LANDMARK_KANTO_FIRST = 0x2F
local GEN2_LANDMARK_SPECIAL_MAP = 0x5F
local function gen2InKanto(game)
  local ow = game and game.overworld
  local landmark = ow and ow.map and ow.map.def and tonumber(ow.map.def.landmark)
  if not landmark or landmark == GEN2_LANDMARK_SPECIAL_MAP then return false end
  return landmark >= GEN2_LANDMARK_KANTO_FIRST
end

-- Which of the three victory jingles each battle theme resolves to; see
-- playVictoryMusic.  Anything not listed keeps its own name.
local GEN2_VICTORY_KIND = {
  wild = "wild", wildNight = "wild", kantoWild = "wild", suicune = "wild",
  trainer = "trainer", kantoTrainer = "trainer",
  rival = "trainer", rocket = "trainer",
  gym = "gym", kantoGym = "gym", final = "gym",
}

-- PlayBattleMusic in full (crystal 11:$6E6C, gold 17:$4556).  The branches
-- are tested in this order and the FIRST match wins, which is why the
-- champion test comes before the gym-leader lists -- CHAMPION ($10) is in
-- GymLeaders too and would otherwise take the gym theme.
-- Which theme a Hoenn battle opens on, by the class of who you are fighting.
-- The Frontier brains share one theme; the two teams share theirs and their
-- leaders share another.
local GEN3_CLASS_MUSIC = {
  ["LEADER"] = "gym",
  ["ELITE FOUR"] = "elite",
  ["CHAMPION"] = "final",
  ["TEAM AQUA"] = "aquaMagma",
  ["TEAM MAGMA"] = "aquaMagma",
  ["AQUA ADMIN"] = "aquaMagma",
  ["MAGMA ADMIN"] = "aquaMagma",
  ["AQUA LEADER"] = "aquaMagmaLeader",
  ["MAGMA LEADER"] = "aquaMagmaLeader",
  ["SALON MAIDEN"] = "frontierBrain",
  ["DOME ACE"] = "frontierBrain",
  ["PALACE MAVEN"] = "frontierBrain",
  ["ARENA TYCOON"] = "frontierBrain",
  ["FACTORY HEAD"] = "frontierBrain",
  ["PIKE QUEEN"] = "frontierBrain",
  ["PYRAMID KING"] = "frontierBrain",
}
BattleState.GEN3_CLASS_MUSIC = GEN3_CLASS_MUSIC

-- ...and the legends, which BattleSetup_StartLegendaryBattle picks by SPECIES
-- rather than by class, because they are wild battles and there is no class
-- to read.
local GEN3_LEGEND_MUSIC = {
  KYOGRE = "weatherTrio", GROUDON = "weatherTrio",
  RAYQUAZA = "rayquaza",
  REGIROCK = "regi", REGICE = "regi", REGISTEEL = "regi",
  MEW = "mew", DEOXYS = "mew",
}
BattleState.GEN3_LEGEND_MUSIC = GEN3_LEGEND_MUSIC

function BattleState:gen3MusicKind()
  local audio = self.data and self.data.audio
  local themes = audio and audio.battle
  if not themes then return nil end
  if self.kind == "trainer" and self.trainer then
    local classes = self.data.constants and self.data.constants.trainerClasses
    local name = classes and self.trainer.class
                 and classes[(tonumber(self.trainer.class) or -1) + 1]
    local kind = name and GEN3_CLASS_MUSIC[name]
    if kind and themes[kind] then
      -- the badge fights are the ones that bump the companion's happiness
      self.isGymLeader = (kind == "gym")
      return kind
    end
    self.isGymLeader = false
    return themes.trainer and "trainer" or nil
  end
  if self.kind == "wild" then
    local mon = self.enemy and self.enemy.mon
    local species = mon and mon.species
    local def = species and self.data.pokemon and self.data.pokemon[species]
    local kind = GEN3_LEGEND_MUSIC[(def and def.name) or species]
    if kind and themes[kind] then return kind end
  end
  return nil
end

function BattleState:computeMusicKind()
  -- Gen2 first: data/scripts/victories is the hand-authored Gen1 badge table
  -- and no Gen2 trainer id is in it, which is why Bugsy opened on the plain
  -- trainer theme instead of the gym theme.
  if require("src.core.GameVersion").isGen2() then
    if self.kind == "trainer" and self.trainer then
      local class = tonumber(self.trainer.index)
      if class then
        -- wGymLeaderNo, the happiness bump: the badge fights only.
        self.isGymLeader = GEN2_BADGE_LEADER_CLASSES[class] == true
        if GEN2_CHAMPION_CLASSES[class] then return "final" end
        if GEN2_ROCKET_CLASSES[class] then return "rocket" end
        if GEN2_KANTO_LEADER_CLASSES[class] then return "kantoGym" end
        if GEN2_BADGE_LEADER_CLASSES[class] or GEN2_ELITE_FOUR_CLASSES[class] then
          return "gym"
        end
        if GEN2_RIVAL_CLASSES[class] then
          -- `cp RIVAL2 / jr nz, .othertrainer / ld a, [wOtherTrainerID] /
          -- cp 4 / jr c, .done` -- RIVAL2's fourth party is the Indigo
          -- Plateau rematch and drops through to the champion theme.
          if class == 0x2A and (tonumber(self.partyIndex) or 1) >= 4 then
            return "final"
          end
          return "rival"
        end
      end
    end
    if self.kind == "trainer" or self.kind == "link" then
      self.isGymLeader = self.isGymLeader or false
      -- .othertrainer: a link battle is always the Johto theme; otherwise
      -- the region picks.
      if self.kind == "link" then return "trainer" end
      return gen2InKanto(self.game) and "kantoTrainer" or "trainer"
    end
    if self.kind == "wild" then
      self.isGymLeader = false
      -- BATTLETYPE_ROAMING ($05) and BATTLETYPE_SUICUNE ($0C) both open on
      -- Music_SuicuneBattle, which Gold does not have at all -- extractAudio
      -- drops the key there and playBattle falls back to the wild theme.
      if self.battleType == "roaming" or self.battleType == "suicune" then
        return "suicune"
      end
      if gen2InKanto(self.game) then return "kantoWild" end
      local ow = self.game and self.game.overworld
      local tod = ow and ow.timeOfDay and ow:timeOfDay()
      -- `ld a, [wTimeOfDay] / cp NITE` -- only NITE has its own song; MORN
      -- and DAY share Music_JohtoWildBattle.
      if tod == "NITE" or tod == "NIGHT" then return "wildNight" end
      return "wild"
    end
  end

  -- ---------------------------------------------------------------------
  -- HOENN PICKS ITS BATTLE THEME BY TRAINER CLASS.
  --
  -- Reported from play: "music doesnt change upon encountering a wild
  -- pokemon".  The first half of that was the role table the import never
  -- wrote; this is the second.  With no Gen 3 branch here every trainer in
  -- the region opened on the plain trainer theme, because the test below it
  -- is `data.scripts.victories` -- the hand-authored GEN 1 badge table, which
  -- names no Hoenn trainer at all.
  --
  -- The class is the cartridge's own: gTrainers carries it per trainer and
  -- the class NAMES come out of the ROM's own table, so LEADER, ELITE FOUR,
  -- CHAMPION and the two teams are read rather than listed here by id.
  if require("src.core.GameVersion").isGen3() then
    local kind = self:gen3MusicKind()
    if kind then return kind end
  end

  local isBoss = false
  if self.kind == "trainer" and self.trainer then
    local victories = require("data.scripts.victories")
    for key, reward in pairs(victories) do
      if reward.badge and key:find(self.trainer.id .. "#", 1, true) == 1 then
        isBoss = true
        break
      end
    end
  end
  -- init_battle.asm: challenging a gym leader (wGymLeaderNo, the badge
  -- fights only -- not Lance or the Champion) bumps the companion's
  -- happiness the moment the battle starts
  self.isGymLeader = isBoss
  if self.kind == "trainer" and self.trainer
     and self.trainer.id == "OPP_RIVAL3" then
    return "final"
  elseif isBoss or (self.trainer and self.trainer.id == "OPP_LANCE") then
    return "gym"
  elseif self.kind == "trainer" or self.kind == "link" then
    return "trainer"
  end
  return "wild"
end

-- side tables mirror the singles battlers; called before every
-- battler-switch notification so sides[i].battlers[1] stays honest
-- ---------------------------------------------------------------------------
-- WHERE A BATTLER STANDS
--
-- Emerald numbers the four places on the field, and the number is not
-- arbitrary -- it is two bits with a meaning each:
--
--     0  PLAYER_LEFT      1  OPPONENT_LEFT
--     2  PLAYER_RIGHT     3  OPPONENT_RIGHT
--
--     side  = position % 2        0 the player's, 1 the opponent's
--     flank = floor(position / 2) 0 the left one, 1 the right one
--     the partner is position ~ 2; the foes are the other side's two
--
-- which is why `self.player` and `self.enemy` can stay exactly what they
-- always were: they ARE positions 0 and 1, the left-hand pair, and a single
-- battle is a double with the right-hand pair empty.  Nothing that reads
-- them has to learn about positions to keep being correct; only the code
-- that must consider BOTH flanks does.
--
-- A single battle therefore walks through here unchanged, and `sides` --
-- which mods already hang screens and hazards on -- keeps the shape it has
-- had all along.
-- ---------------------------------------------------------------------------
BattleState.POS = {
  PLAYER_LEFT = 0, OPPONENT_LEFT = 1, PLAYER_RIGHT = 2, OPPONENT_RIGHT = 3,
}

-- THE SWITCH.
--
-- A double battle was not one change; it was six, and they had to land in
-- order: the positions, the four-way turn order, targeting and a second
-- player choice, the spread and screen numbers, fainting and send-out with
-- an empty slot beside a full one, and a 2v2 screen with four panels.  This
-- was false while they were arriving, because two on a side with a turn
-- loop that takes one action and a screen that draws one Pokemon is worse
-- than the single battle it replaces, not better.
--
-- They are all in.  It is kept as a named flag rather than deleted because
-- it is the one line to turn over if a double battle misbehaves in play --
-- everything falls back to a single, which is what the port did before.
BattleState.DOUBLES_READY = true

function BattleState:isDouble()
  return self.double == true and BattleState.DOUBLES_READY == true
end

-- ...and what the battle was ASKED to be, regardless of whether the engine
-- can field it yet.  Everything that only records the fact reads this.
function BattleState:wantsDouble() return self.double == true end

-- side index (1 or 2) and flank index (1 or 2) for a position
local function slotOf(pos)
  pos = tonumber(pos) or 0
  return (pos % 2) + 1, math.floor(pos / 2) + 1
end
BattleState.slotOf = slotOf

function BattleState:battlerAt(pos)
  local side, flank = slotOf(pos)
  return self.sides[side] and self.sides[side].battlers[flank]
end

-- Put a battler on the field.  The left flanks keep their old names, so
-- `self.player` and `self.enemy` remain the two battlers every existing
-- caller already means.
function BattleState:placeBattler(pos, battler)
  local side, flank = slotOf(pos)
  self.sides[side].battlers[flank] = battler
  if battler then battler.position = pos end
  if flank == 1 then
    if side == 1 then self.player = battler else self.enemy = battler end
  end
  return battler
end

function BattleState:partnerOf(battler)
  if not (battler and self:isDouble()) then return nil end
  local pos = tonumber(battler.position)
  if not pos then return nil end
  -- the partner is the same side, the other flank: position xor 2
  return self:battlerAt(pos < 2 and pos + 2 or pos - 2)
end

-- The live battlers on the other side, in position order.
--
-- A plain local as well as a method, because parts of this engine are called
-- standalone -- `abilitySwitchIn` is lifted off the class and run against a
-- bare table in the tests -- and this reads nothing but `sides`, which every
-- such table has.
function foesOf(battle, battler)
  local out = {}
  if not (battler and battle and battle.sides) then return out end
  local theirs = battler.isPlayer and 2 or 1
  local side = battle.sides[theirs]
  for flank = 1, 2 do
    local b = side and side.battlers and side.battlers[flank]
    if b and b.mon and (b.mon.hp or 0) > 0 then out[#out + 1] = b end
  end
  -- a bare table may never have been syncSides'd; fall back to the two
  -- names every battle in this engine has always had
  if #out == 0 then
    local other = battler.isPlayer and battle.enemy or battle.player
    if other and other.mon and (other.mon.hp or 0) > 0 then out[1] = other end
  end
  return out
end

function BattleState:foesOf(battler) return foesOf(self, battler) end

-- EVERY SLOT THAT IS STANDING, in position order 0,1,2,3.
--
-- In a single battle this yields exactly `self.player, self.enemy`, in that
-- order -- which is precisely the list the dozen `for _, b in ipairs({
-- self.player, self.enemy })` sweeps in this file already walk.  They can
-- move onto this one at a time with no change in behaviour.
-- A plain local as well as a method, for the same reason foesOf is one:
-- several of this engine's methods are lifted off the class and run against
-- a bare battle table, and this must keep working there.  With no `sides`
-- filled in it falls back to the two names every battle has always had,
-- which is exactly the list the sweeps that call it used to walk.
function activeBattlers(battle)
  local out, n = {}, 0
  for pos = 0, 3 do
    local side, flank = slotOf(pos)
    local s = battle.sides and battle.sides[side]
    local b = s and s.battlers and s.battlers[flank]
    if b then n = n + 1; out[n] = b end
  end
  if n == 0 then
    if battle.player then n = n + 1; out[n] = battle.player end
    if battle.enemy then n = n + 1; out[n] = battle.enemy end
  end
  local i = 0
  return function()
    i = i + 1
    if out[i] then return i, out[i] end
  end
end

function BattleState:activeBattlers() return activeBattlers(self) end

function BattleState:syncSides()
  self.sides[1].battlers[1] = self.player
  self.sides[2].battlers[1] = self.enemy
  if self.player then self.player.position = BattleState.POS.PLAYER_LEFT end
  if self.enemy then self.enemy.position = BattleState.POS.OPPONENT_LEFT end
  if not self:isDouble() then
    -- a single battle has no right-hand pair, and leaving a stale one there
    -- would make activeBattlers walk a battler that is not on the field
    self.sides[1].battlers[2] = nil
    self.sides[2].battlers[2] = nil
  else
    local pr = self.sides[1].battlers[2]
    local orr = self.sides[2].battlers[2]
    if pr then pr.position = BattleState.POS.PLAYER_RIGHT end
    if orr then orr.position = BattleState.POS.OPPONENT_RIGHT end
  end
end

-- IS THIS SIDE STILL ARRIVING?
--
-- Reported from play: "when the enemy trainer sprites come out their second
-- pokemon comes out with them already."  It did.  The right-hand pair are
-- drawn plainly, on the platform offsets sBattlerCoords gives them, and that
-- pass carries none of the intro state the left flanks carry -- so while the
-- trainer's own picture was still on screen, before the slide, before the
-- ball and before the send-out, the Pokemon standing behind them was already
-- there.
--
-- ONE TEST IS ENOUGH BECAUSE A SIDE ARRIVES TOGETHER.  Both of a trainer's
-- Pokemon come out on the same command; whatever is hiding the left flank
-- during the intro is hiding its partner for the same reason.  So this asks
-- about the SIDE rather than about the slot, and the right-hand pair simply
-- wait for it.
function BattleState:sideArriving(isPlayer, slide)
  -- the whole field is still sliding in, or the party balls are still up
  if (tonumber(slide) or 0) ~= 0 then return true end
  if self.introBalls then return true end
  if isPlayer then
    -- the player's back pic is up until "Go!", and `sendingOut` covers the
    -- gap between the throw and the Pokemon appearing
    if self.showPlayerBack or self.sendingOut then return true end
    return self:growInScale(self.player) ~= nil
  end
  if self.showEnemyTrainer or self.enemySendingOut or self.enemyHidden then
    return true
  end
  -- ...and while the foe's own lead is still growing out of its ball
  return self.enemy ~= nil and self:growInScale(self.enemy) ~= nil
end

function BattleState:sideOf(battler)
  return (battler and battler.isPlayer) and self.sides[1] or self.sides[2]
end

-- battle.started's kind verb: the mutated ghost/safari/oldman variants
-- override the constructor's wild/trainer/link
function BattleState:battleKind()
  if self.ghost then return "ghost" end
  if self.safari then return "safari" end
  -- the Dude fights with the player's own mon, so the back pic is the
  -- ordinary wild-battle one
  if self.demo and not self.dudeDemo then return "oldman" end
  return self.kind
end

function BattleState:enter()
  -- Out of useable POKéMON before the battle even starts.  pokered does not
  -- skip the battle: .checkAnyPartyAlive (engine/battle/core.asm:158-162)
  -- runs right after the intro and jumps to HandlePlayerBlackOut, so the
  -- player blacks out and afterBattle's "lose" path revives the party at the
  -- last heal point.  Handing the map back with a 0 HP party instead bricked
  -- the save: every later encounter aborted here too and sighted trainers
  -- re-engaged forever (#425).  self.dead alone is not the test --
  -- makeOldManDemo and LinkBattle install a player battler after the
  -- constructor flagged the battle dead.
  if self.dead and not self.player then
    local name = self.game.save.player.name
    self.result = "lose"
    self.game.stack:pop()
    require("src.core.Music").restoreMap(self.data)
    Runtime.emit("battle.ended", { battle = self, result = "lose", skipped = true })
    local onFinish = self.onFinish
    local function blackedOut()
      if onFinish then onFinish("lose") end
    end
    -- the Oak's Lab starter rival returns above PlayerBlackedOutText2 and
    -- afterBattle keeps the player in the lab, so print nothing there
    if BattleState.isOaksLabStarterRival(self) then return blackedOut() end
    -- _PlayerBlackedOutText2 (data/text/text_2.asm:896): the two paragraphs
    -- playerMonFainted queues on the battle screen; there is no battle
    -- screen to queue them on here, so they print over the map.
    self.game.stack:push(require("src.render.TextBox").new(self.game,
      Strings("%s is out of\nuseable POKéMON!", name) .. "\f"
      .. Strings("%s blacked\nout!", name), blackedOut))
    return
  end
  local Music = require("src.core.Music")
  self.musicKind = self:computeMusicKind()
  if self.isGymLeader then
    require("src.world.PikachuFollower")
      .modifyHappiness(self.game.save, "GYMLEADER")
  end
  -- normally already playing: the transition wipe starts the theme
  -- (audio/play_battle_music.asm runs before the transition, and
  -- Music.play no-ops on the same song); this covers battles pushed
  -- without a transition (link battles, scripted pushes)
  Music.playBattle(self.data, self.musicKind)
  -- intro presentation (SlidePlayerAndEnemySilhouettesOnScreen): both
  -- sides slide in; the trainer pics stay up until the send-outs
  -- BATTLE BG "world" drops this battle's opacity so StateStack keeps drawing
  -- the overworld underneath it (see bgMode).  Per instance, so the class
  -- default stays opaque for every other battle and for older saves.
  self.isOpaque = self:bgMode() ~= "world"
  self.introSlide = Timing.BATTLE_SLIDE_IN_FRAMES
  self.showEnemyTrainer = self.kind == "trainer" and self.trainerPic ~= nil
  -- DrawAllPokeballs (common_text.asm:27) puts the party ball rows AND the
  -- HUD corner/underline tiles under them (PlacePlayerHUDTiles /
  -- PlaceEnemyHUDTiles, draw_hud_pokeball_gfx.asm:119-165) on screen with
  -- the intro text; _InitBattleCommon (core.asm:6755-6762) ClearScreenArea's
  -- both HUD blocks and ClearSprites's the balls the moment that text is
  -- dismissed.  This flag is exactly that window: drawHUDs draws the intro
  -- chrome while it is up and holds the real enemy HUD back, since a wild
  -- battle's DrawEnemyHUDAndHPBar only runs after the text (#317).  The
  -- draw is still gated on the slide having landed, so nothing shows while
  -- the silhouettes are still coming in.
  self.introBalls = true
  -- SGB: the player-side battle palette while the back pic is up is
  -- MonsterPalettes[0] = PAL_MEWMON (wBattleMonSpecies is still 0 when
  -- the intro's SET_PAL_BATTLE runs -- SetPal_Battle,
  -- engine/gfx/palettes.asm:28)
  -- field.playerPics picks the pic (the catch tutorial's old man fights in
  -- the player's place), then the player.sprite hook gets the last word so
  -- a mod can vary it per save.  It loads through getImage like every other
  -- battle pic, so a replacement keeps the SGB recolor, the transition
  -- fade, the ground-padding measurement and battle_sprite_scales.
  local backPath, backTrueColor =
    require("src.pokemon.Sprites").playerPath(self.data, "back",
      { kind = "battle", demo = self.demo, oakDemo = self.oakDemo,
        battle = self })
  self.playerBackPic = getImage(backPath,
    namedPalette(self.data, "MEWMON"), backTrueColor)
  self.showPlayerBack = self.playerBackPic ~= nil
  -- the enemy's cry as it appears (data/pokemon/cries.asm); PlayCry sits at
  -- a different point in each battle kind, so queue it per branch
  local function queueEnemyCry()
    self:act(function()
      require("src.core.Sound").playCry(self.data, self.enemy.mon.species)
      HeldItems.onEntry(self, self.enemy)
    end)
  end
  -- PrintBeginningBattleText (engine/battle/common_text.asm:10-19): a wild
  -- battle calls PlayCry BEFORE PrintText WildMonAppearedText, so the cry
  -- sounds with the "Wild X appeared!" box instead of waiting on the A
  -- press that clears its `prompt` (#303).  The Silph-Scope-less tower
  -- ghost gets no cry at all (common_text.asm:43-48), and neither does the
  -- unveiled MAROWAK: .isMarowak never reaches PlayCry (#492).
  if self.kind ~= "trainer" and self.kind ~= "link"
     and not self.ghost and not self.scopeReveal then
    -- PrintBeginningBattleText .wild (core.asm:9091-9103) checks the WILD
    -- mon's shininess and plays the sparkle BEFORE the cry -- and only the
    -- sparkle: a wild mon is already standing there, so it never gets the
    -- send-out poof the sparkle normally follows.  This is the one players
    -- actually notice, and it was missing entirely.
    if not self:shinyAnimAppend(self.enemy, true) then
      -- ...and Hoenn's own, which is a different animation entirely
      self.queue[#self.queue + 1] =
        { fn = function() self:gen3ShinyBurst(self.enemy) end }
    end
    queueEnemyCry()
  end
  -- PrintBeginningBattleText .trainerBattle (common_text.asm): a trainer
  -- battle gives SFX_SILPH_SCOPE a clear window -- PlaySound, then
  -- WaitForSoundToFinish, which blocks -- and only after `ld c, 20 /
  -- DelayFrames` do DrawAllPokeballs and the "wants to fight!" text run.
  -- The balls and the text used to appear on the same frame the silhouettes
  -- landed, so the sound had to share its whole duration with the ball draw
  -- and the text scroll instead of landing on its own.
  --
  -- The sfx is extracted as "Trainer_Appeared" (tools/rom_manifest.json
  -- sfxHeaders, bank 8 / $42bb -- the same header pokered names
  -- SFX_Silph_Scope); nothing had ever played it.
  if self.kind == "trainer" then
    self:act(function()
      self.introSfx = require("src.core.Sound").play(self.data,
                                                     "Trainer_Appeared")
    end)
    table.insert(self.queue, { waitSound = function() return self.introSfx end })
    table.insert(self.queue, { wait = Timing.TRAINER_INTRO_SFX_GAP })
  end
  self:say(self.introText)
  -- the unveil rides on that same box, before _InitBattleCommon clears the
  -- intro chrome below (#492)
  if self.scopeReveal then self:queueScopeReveal() end
  -- _InitBattleCommon (core.asm:6755-6762): the instant the intro text is
  -- dismissed both HUD blocks are cleared and ClearSprites drops the
  -- pokeball OAM, so the intro chrome never returns for the rest of the
  -- battle -- not on a switch, and not when the beaten trainer's pic
  -- scrolls back in (#317, #282)
  self:act(function() self.introBalls = nil end)
  if self.kind == "trainer" then
    -- EnemySendOutFirstMon (core.asm:1308-1310): SlideTrainerPicOffScreen
    -- walks the foe's pic off the RIGHT edge (hlcoord 18,0, a = 8 tiles,
    -- one tile every 2 frames) BEFORE TrainerSentOutText -- the pic does
    -- not blink out under the text (#317)
    self:act(function() self:slidePic("foe", 0, 64, 4) end)
    table.insert(self.queue, { wait = 16 })
    self:act(function()
      self.showEnemyTrainer = false
      -- the slot is EMPTY from here until AnimateSendingOutMon runs below:
      -- the pic has walked off and the mon is still in its ball, so nothing
      -- stands in the enemy slot while TrainerSentOutText prints.  Without
      -- this the front sprite popped in full-size the instant the trainer
      -- left, sat there through the whole text box, and the grow-in then
      -- restarted it from nothing -- the mon appearing before it was sent
      -- out.  Mirrors the flag the mid-battle replacement already sets.
      self.enemySendingOut = true
      self:slidePic("foe")
    end)
    self:say(Strings("%s sent\nout %s!", self:trainerLabel_(), self.enemy.name))
    self:act(function()
      -- EnemySendOutFirstMon (core.asm:1421-1434): after the text the
      -- pic grows out of the ball (AnimateSendingOutMon), then the cry
      self.enemySendingOut = false
      self:startGrowIn(self.enemy)
    end)
    self:shinyAnimAppend(self.enemy, true)
    queueEnemyCry()
  elseif self.kind == "link" then
    -- Colosseum has no foe trainer pic, but the enemy mon still grows
    -- out of the ball after "X sent out Y!" (not the wild "already there"
    -- intro that LinkBattle previously inherited from newWild).
    self.enemySendingOut = true
    self:say(Strings("%s sent\nout %s!", self.opponentName or "FOE",
                                          self.enemy.name))
    self:act(function()
      self.enemySendingOut = false
      self:startGrowIn(self.enemy)
    end)
    self:shinyAnimAppend(self.enemy, true)
    queueEnemyCry()
  end
  -- StartBattle .foundFirstAliveEnemyMon (core.asm:152-156): the `call nz`
  -- gates only EnemySendOutFirstMon -- the `ld c, 40 / call DelayFrames`
  -- after it is unconditional, so a wild battle pays it too, between
  -- "Wild X appeared!" and "Go! Y!".  It lands before .playerSendOutFirstMon
  -- (:166), not at the end of the intro.  Appended, not waitNext'd: the
  -- intro is built linearly, and waitNext's insert point is for rows added
  -- while the queue is already running.
  table.insert(self.queue, { wait = Timing.BATTLE_START_SENDOUT })
  if not self.safari and not self.demo then
    -- StartBattle .playerSendOutFirstMon (core.asm:236-240): the back pic
    -- walks off the LEFT edge (SlideTrainerPicOffScreen, hlcoord 1,5,
    -- a = 9 tiles, one tile every 2 frames) BEFORE SendOutMon prints
    -- "Go! X!" -- Red does not simply vanish under the message (#317)
    --
    -- ...AND ON HOENN HE STAYS TO THROW.  Reported from play: the ball "is
    -- supposed to be in the players hand".  Emerald's trainer is still on
    -- screen for "Go! X!" and leaves WHILE the ball is in the air, so on a
    -- dataset that has the send-out throw the walk-off is handed to
    -- gen3SendOut and happens on the throw's own frame instead of eighteen
    -- frames before the text.
    local throws = self:gen3ThrowsSendOut()
    if not throws then
      self:act(function() self:slidePic("back", 0, -72, 4) end)
      table.insert(self.queue, { wait = 18 })
    end
    self:act(function()
      if not throws then
        self.showPlayerBack = false
        self:slidePic("back")
      end
      self.sendingOut = true
    end)
    self:say(self:sendOutText(self.player.name))
    -- then the POOF plays and the mon appears with its cry
    -- (SendOutMon: message -> AnimateSendingOutMon -> PlayCry)
    table.insert(self.queue, { anim = "POOF_ANIM", attackerIsPlayer = false })
    self:shinyAnimAppend(self.player, false)
    self:act(function()
      self.sendingOut = false
      -- SendOutMon (core.asm:1757-1762): after the poof the mon grows
      -- out of the ball (AnimateSendingOutMon at hlcoord 4,11)
      self:startGrowIn(self.player)
      require("src.core.Sound").playCry(self.data, self.player.mon.species)
      HeldItems.onEntry(self, self.player)
    end)
    self:markParticipant()
  end
  self.phase = "messages"
  self.afterQueue = "menu"
  self:syncSides()
  -- THE FIRST SEND-OUT COUNTS TOO.  ABILITYEFFECT_ON_SWITCHIN runs the
  -- moment a Pokemon is on the field, so a MIGHTYENA leading a trainer
  -- battle drops the player's attack before either side has moved and a
  -- GROUDON's sun is up from turn one.  Appended rather than actNext'd:
  -- the intro is built linearly before the queue starts running.  Enemy
  -- first, then the player, which is the order they were sent out in.
  if not (self.safari or self.demo) then
    table.insert(self.queue, { fn = function()
      self:abilitySwitchIn(self.enemy)
      self:abilitySwitchIn(self.player)
    end })
  end
  Runtime.emit("battle.started", {
    battle = self, kind = self:battleKind(),
    trainerId = self.trainer and self.trainer.id,
    species = self.enemy and self.enemy.mon.species,
    level = self.enemy and self.enemy.mon.level,
  })
end

-- any pop (finish, script teardown) must silence the alarm loop
-- (end_of_battle.asm clears wLowHealthAlarm when a battle ends)
function BattleState:exit()
  require("src.core.Sound").stopLoop("Low_Health_Alarm")
  -- Free this battle's own GPU objects now rather than waiting on a GC
  -- finalizer: the two full-screen wavy-effect canvases (colorMode) and
  -- the AnimPlayer's per-instance tilesheet images/quads.  The shared
  -- module caches (imageCache/imagePadBottom, keyed by path+palette) are
  -- reused by the next battle, so they are deliberately left alone -- only
  -- the per-instance objects, which are dead once this battle is popped,
  -- are released here.
  -- the Stadium rigs are per-battler 3D actors with their own GPU buffers,
  -- and belong to this battle exactly like the canvases below
  require("src.render.StadiumArt").releaseAll(self.game, self)
  -- What the in-world 3D battle actually did, once per battle.  The mod
  -- composites it through render.compose and answers a status; without asking,
  -- "the models did not appear" is indistinguishable from "the 3D battle never
  -- rendered a frame", and those have completely different causes.
  self:reportStadiumBattle("end")
  local function rel(o) if o and o.release then pcall(o.release, o) end end
  rel(self.bgCanvas); self.bgCanvas = nil
  rel(self.waveCanvas); self.waveCanvas = nil
  self.colorFxReady = nil
  if self.animPlayer and self.animPlayer.release then
    self.animPlayer:release()
  end
end

-- End a trapping sequence (USING_TRAPPING_MOVE).  SendOutMon clears the
-- foe's bit (core.asm:1761-1762); EnemySendOutFirstMon clears the
-- player's (core.asm:1314-1315).  Any switch frees the other side.
local function clearTrapping(battler)
  if not battler then return end
  battler.trappingTurns = nil
  battler.trapMove = nil
  battler.trapDamage = nil
end

-- core.asm:297-300: both sides' FLINCHED bits are cleared as a turn's move
-- selection opens, but the clear is skipped for a mon that must recharge or
-- is locked into Rage (core.asm:293-295 -- the Hyper Beam flinch-recharge
-- glitch).
--
-- A method rather than three lines inside the menu branch, because two
-- other places need the identical rule at the identical point in the turn
-- and both got it wrong by not having it:
--
--   * guarded PER BATTLER, not off self.player alone.  This runs on
--     whichever machine is looking at its own menu, and in a lockstep link
--     battle "self.player" is the host's mon on one peer and the guest's on
--     the other, so one shared guard let one peer clear both flags while
--     the other cleared neither -- a bogus desync draw in a winnable match.
--   * a tournament spectator never enters the menu phase at all (it has no
--     decision to make), so nothing cleared a flinch in its replay: the
--     flag survived into the next turn, ate a move the real players saw
--     land, and from there the replay was watching a different battle.
--     LinkBattle.newSpectator calls this at the head of every turn.
function BattleState:clearTurnFlinches()
  for _, b in activeBattlers(self) do
    if b and not (b.mustRecharge or b.rageMove) then b.flinched = false end
  end
end

-- Actions that skip DisplayBattleMenu entirely (core.asm:300-310):
-- recharge, Rage, thrash, charge.  Bide / trapping / being held do NOT
-- skip the menu -- the player can still item/switch (and must press
-- FIGHT to continue a trapping sequence).
function BattleState:menuLockedAction(battler)
  -- a slot with nobody in it -- a double battle between a faint and the
  -- end-of-turn replacement -- is not locked into anything
  if not battler then return nil end
  if battler.mustRecharge then return { special = "recharge" } end
  if battler.charging then return battler.charging end
  if battler.thrashTurns and battler.thrashTurns > 0 then return battler.thrashMove end
  if battler.rageMove then return battler.rageMove end
  return nil
end

-- After FIGHT: skip MoveSelectionMenu (core.asm:320-329).  Own
-- trapping/Bide continues; foe trapping forces CANNOT_MOVE ($ff).
function BattleState:fightLockedAction(battler)
  if not battler then return nil end
  if battler.trappingTurns and battler.trappingTurns > 0 then
    return { special = "trapping" }
  end
  if battler.bideTurns then return { special = "bide" } end
  -- held while the OPPONENT's trapping bit is set (live mirror so a
  -- trap ended early by paralysis/faint frees the victim immediately).
  -- Read, not written: executeAction refreshes battler.boundTurns from the
  -- same expression when the action actually runs, and that site runs on
  -- both peers of a link battle.  Storing it here instead wrote a hashed
  -- field on whichever machine happened to open its own FIGHT menu, which
  -- left the two peers holding boundTurns=0 against nil for the same
  -- battler and ended the match as a desync over a mirror of a mirror.
  local opp = battler.isPlayer and self.enemy or self.player
  local bound = opp and opp.trappingTurns
                and math.max(1, opp.trappingTurns) or nil
  if bound then
    return { special = "bound" }
  end
  -- ENCORE: the same move again, whether the Pokemon wants to or not.  Only
  -- if it still has the move -- an ENCOREd move that ran out of PP frees it.
  if battler.encoreTurns and battler.encoreMove then
    for _, m in ipairs(battler.curMoves or battler.mon.moves or {}) do
      if m.id == battler.encoreMove and (m.pp or 0) > 0 then
        return { move = m }
      end
    end
    battler.encoreTurns, battler.encoreMove = nil, nil
  end
  return nil
end

-- TAUNT: a status move is not selectable while it lasts.  Asked by the move
-- menu rather than enforced after the fact, so the player is never told to
-- pick again for a move the game was never going to allow.
function BattleState:tauntBlocks(battler, move)
  if not (battler and battler.tauntTurns and move) then return false end
  return (move.power or 0) == 0
end

-- TORMENT: not the same move twice in a row.
function BattleState:tormentBlocks(battler, move)
  if not (battler and battler.tormented and move) then return false end
  return battler.lastMove ~= nil and move.id == battler.lastMove
end

-- Full lock for AI / callers that need any forced action.
function BattleState:lockedAction(battler)
  return self:menuLockedAction(battler) or self:fightLockedAction(battler)
end

-- THE POKEMON THE MENU IS STANDING IN FRONT OF.
--
-- Reported from play: "after selecting an attack it doesnt have my select an
-- attack from my second pokemon to use for the second attack, it asks me to
-- use one of my first pokemons moves again."  That is exactly what it did.
-- The turn loop DID ask twice -- the second pass was there -- but every one
-- of these read `self.player`, so the right-hand slot was shown the LEFT
-- one's four moves, its PP, and its DISABLE, and the action it produced
-- carried the left Pokemon's move object.  It looked like being asked the
-- same question twice because the answer sheet was the same.
--
-- `choosingBattler` has known which slot is being asked since doubles
-- landed; nothing downstream of the menu was reading it.
function BattleState:menuBattler()
  return self:choosingBattler() or self.player
end

function BattleState:playerHasPP(who)
  who = who or self:menuBattler()
  if not (who and who.curMoves) then return false end
  for i, mv in ipairs(who.curMoves) do
    if mv.pp > 0 and who.disabledSlot ~= i then return true end
  end
  return false
end

function BattleState:swapMoves(i, j, who)
  if i == j then return end
  who = who or self:menuBattler()
  if not who then return end
  local moves = who.curMoves
  local a, b = moves[i], moves[j]
  if not (a and b) then return end
  moves[i], moves[j] = b, a
  local stored = who.mon and who.mon.moves
  if stored and stored ~= moves and stored[i] and stored[j] then
    stored[i], stored[j] = stored[j], stored[i]
  end
  local disabled = who.disabledSlot
  if disabled == i then
    who.disabledSlot = j
  elseif disabled == j then
    who.disabledSlot = i
  end
  require("src.core.Sound").play(self.data, "Swap")
end

-- One frame of the presentational clock: the BGP flash sequences, the
-- per-battler pic slide/hide programs, the send-out grow-in, the intro
-- slide and the screen-shake programs all advance in updateFx and nowhere
-- else.  It lives behind its own entry point because a caller that has to
-- skip the rest of update() for a frame must still tick this, and a link
-- battle does exactly that on two hot paths -- waiting on the peer's action,
-- and draining a resolved lockstep turn.  Skipping it there froze whatever
-- was mid-flight: a flash stuck on its inverted BGP step repainted the whole
-- UI in inverted shades, and a pic part-way through a slide-off or a grow-in
-- simply stayed gone -- for as long as the opponent took to choose.
function BattleState:tickFx()
  self.frame = self.frame + 1
  self:updateFx()
end

-- The pic to actually draw for `battler` this frame: its Crystal animation
-- frame if one is up, otherwise the still.  Placement is always measured off
-- the still (same dimensions, same ground padding), so only the texture
-- changes -- see drawBattlerPic and the enemy branch of drawPics.
function BattleState:battlerPic(battler)
  local still = self:picImage(battler.sprite)
  local anim = battler and battler.picAnim
  -- THE ANIMATION BELONGS TO THE MOMENT IT LANDS, NOT THE MOMENT IT APPEARS.
  --
  -- Reported from play: "pokemon also play their sprite animations before
  -- ariving on their tile".  The first DRAW was starting the clock, and the
  -- first draw is 72 frames before the Pokemon is anywhere near its slot:
  -- SlidePlayerAndEnemySilhouettesOnScreen slides both sides in over
  -- BATTLE_SLIDE_IN_FRAMES, and the pic is drawn -- offset -- for every one
  -- of them.  So Emerald's intro squash and Crystal's front-pic frames both
  -- played out while the sprite was still travelling, and were over by the
  -- time it arrived.  The cartridge launches the front animation from the
  -- send-out, after the sprite is in place.
  local sliding = (self.introSlide or 0) > 0
  if anim and not sliding then anim:start() end
  if battler and battler.monAnim and not sliding then
    battler.monAnim:start()
  end
  local frame = anim and anim:frame() or 0
  if frame <= 0 then return still end
  local meta = imageMeta[battler.sprite]
  local record = anim.anim
  -- ...AND A SHINY ANIMATES IN ITS OWN COLOURS.  The still pic and the strip
  -- are two separate decodes on this side, so a battler whose still is the
  -- shiny picture has to be handed the shiny STRIP as well or it drops back
  -- to ordinary colours for exactly the frames it is moving.
  local sheet = require("src.pokemon.PicAnim").sheetFor(record, battler.mon)
  local swapped = getImage(sheet, meta and meta.pal,
                           meta and meta.trueColor,
                           { index = frame, width = record.width })
  if not swapped then return still end
  return self:picImage(swapped)
end

-- What the mod's in-world 3D battle is doing, as a line.  Sampled from
-- update rather than only at exit, because the interesting moment is while the
-- battle is ON SCREEN -- an exit-only report says nothing at all until the
-- fight is over, which is exactly when it stops being useful.
function BattleState:reportStadiumBattle(when)
  pcall(function()
    local mods = self.game and self.game.mods
    local exports = mods and mods.exports
    local mine = exports and exports["STADIUM2_OVERWORLD_MODELS"]
    local statusFn = mine and mine.inWorld3DBattleStatus
    local Logger = require("src.core.Logger")
    if type(statusFn) ~= "function" then
      Logger.info("in-world 3D battle (%s): no status to read -- mods=%s "
        .. "exports=%s mod=%s statusFn=%s", tostring(when),
        tostring(mods ~= nil), tostring(exports ~= nil), tostring(mine ~= nil),
        type(statusFn))
      return
    end
    local okStatus, st = pcall(statusFn)
    if not (okStatus and type(st) == "table") then
      Logger.info("in-world 3D battle (%s): status call failed: %s",
        tostring(when), tostring(st))
      return
    end
    -- ...and ask Stadium itself whether it HAS a model for each side.  This is
    -- the question the frame counters cannot answer: a stage that renders 400
    -- frames with no rigs loaded looks identical, from the engine, to one that
    -- renders 400 frames of models.  `mod.exports.overworld` IS the Stadium
    -- module (main.lua), so this is a direct read, not an inference.
    local sides = ""
    -- `mod.exports.overworld` is OverworldStadium -- the OVERWORLD renderer,
    -- which has no battle model state and answered "?" to both questions.
    -- The battle one is a different module reached through the mod's own
    -- loader: mod.exports.lib.require("Stadium").
    local Stadium = nil
    local lib = mine.lib
    if type(lib) == "table" and type(lib.require) == "function" then
      local okLib, got = pcall(lib.require, "Stadium")
      if okLib and type(got) == "table" then Stadium = got end
    end
    if type(Stadium) == "table" then
      for _, side in ipairs({ "player", "enemy" }) do
        local has, vis = "?", "?"
        if type(Stadium.hasModel) == "function" then
          local okHas, v = pcall(Stadium.hasModel, side)
          has = okHas and tostring(v) or "err"
        end
        if type(Stadium.visible) == "function" then
          local okVis, v = pcall(Stadium.visible, side)
          vis = okVis and tostring(v) or "err"
        end
        sides = sides .. (" %s(model=%s visible=%s)"):format(side, has, vis)
      end
      if type(Stadium.active) == "function" then
        local okActive, v = pcall(Stadium.active)
        sides = sides .. (" active=%s"):format(okActive and tostring(v) or "err")
      end
    else
      sides = " <lib.require(\"Stadium\") unavailable>"
    end
    Logger.info("in-world 3D battle (%s): installed=%s active=%s frames=%s "
      .. "fallbacks=%s err=%s --%s", tostring(when),
      tostring(st.installed), tostring(st.active), tostring(st.frames),
      tostring(st.fallbacks), tostring(st.error), sides)
  end)
end

function BattleState:update(dt)
  self:tickFx()
  -- one sample a second into the fight, while it is still on screen
  self._stadiumReportTicks = (self._stadiumReportTicks or 0) + 1
  if self._stadiumReportTicks == 60 then self:reportStadiumBattle("mid") end
  -- Crystal pic animations run off the wall clock like every other battle
  -- pic effect; a Gold/Silver battler has no picAnim and this is a no-op.
  for _, b in activeBattlers(self) do
    if b and b.picAnim then b.picAnim:update(dt) end
    if b and b.monAnim then b.monAnim:update(dt) end
  end
  local input = self.game.input

  -- safety net: HP/status changed outside a queued drain (level-up heals,
  -- field effects, bag cures) snaps once the queue is idle
  if self.phase == "menu" then
    for _, b in activeBattlers(self) do
      if b then
        if b.shownHP then b.shownHP = b.mon.hp end
        b.drainFloor = nil
        b.shownStatus = b.mon.status
      end
    end
  end

  if self.phase == "messages" then
    -- Nothing queued starts until the silhouettes have finished sliding in:
    -- SlidePlayerAndEnemySilhouettesOnScreen ends with `jpfar
    -- PrintBeginningBattleText` (engine/battle/core.asm:100), so the enemy
    -- cry and the "Wild X appeared!" box belong at the end of the slide, not
    -- on its first frame (#303).  The hold sits here rather than in
    -- updateQueue because only this loop has a frame clock: updateFx above
    -- counts introSlide down, and a headless caller driving updateQueue on
    -- its own has no slide to wait for.
    if (self.introSlide or 0) > 0 then return end
    if not self:updateQueue() then
      if self.afterQueue == "menu" then
        self.phase = "menu"
      elseif self.afterQueue == "finish" then
        self:finish()
      end
    end
    return
  end

  if self.phase == "menu" and self.demo then
    -- DisplayBattleMenu's old-man branch (core.asm:2018-2050): input is
    -- never read.  The player name is swapped to OLD MAN, then the
    -- keystrokes are simulated on screen -- the '▶' cursor sits next to
    -- FIGHT (9,14) for 80 frames, hops down to ITEM (9,16) for 50, goes
    -- hollow ('▷') and the ITEM menu is forced (a = $2 ->
    -- .upperLeftMenuItemWasNotSelected).  The old man never attacks;
    -- backing out of the ball menu re-enters DisplayBattleMenu, which
    -- replays the whole script.
    self.demoTimer = (self.demoTimer or 0) + 1
    if self.demoTimer > 130 then
      self.demoTimer = nil
      self:openOldManBag()
    end
    return
  end

  if self.phase == "menu" and self.safari then
    if self.safari.balls <= 0 then
      self:say(Strings("PA: You're out of\nSAFARI BALLs!\nGame over!"))
      self.phase = "messages"
      self.result = "run"
      self.afterQueue = "finish"
      return
    end
    local col = (self.menuIndex - 1) % 2
    local row = math.floor((self.menuIndex - 1) / 2)
    if input:wasPressed("left") then
      col = math.max(0, col - 1)
    elseif input:wasPressed("right") then
      col = math.min(1, col + 1)
    elseif input:wasPressed("up") then
      row = math.max(0, row - 1)
    elseif input:wasPressed("down") then
      row = math.min(1, row + 1)
    end
    self.menuIndex = row * 2 + col + 1
    if input:wasPressed("a") then
      self:safariAction(({ "ball", "bait", "rock", "run" })[self.menuIndex])
    end
    return
  end

  if self.phase == "menu" then
    -- forced replacement after a faint: ChooseNextMon (core.asm:1086)
    -- loops the party menu until a healthy mon is picked, so B and
    -- fainted picks land back here and reopen it
    if self.player.mon.hp <= 0 then
      if Party.firstHealthy(self.game.save.party) then
        self:openReplacementMenu()
      end
      return
    end
    self:clearTurnFlinches()
    -- only recharge/Rage/thrash/charge skip DisplayBattleMenu; trapping
    -- victims (and wrappers) still get FIGHT/PKMN/ITEM/RUN (core.asm:312)
    local locked = self:menuLockedAction(self.player)
    if locked then
      self:resolveTurn(locked)
      return
    end
    local col = (self.menuIndex - 1) % 2
    local row = math.floor((self.menuIndex - 1) / 2)
    if input:wasPressed("left") then
      col = math.max(0, col - 1)
    elseif input:wasPressed("right") then
      col = math.min(1, col + 1)
    elseif input:wasPressed("up") then
      row = math.max(0, row - 1)
    elseif input:wasPressed("down") then
      row = math.min(1, row + 1)
    end
    self.menuIndex = row * 2 + col + 1
    if input:wasPressed("a") then
      local choice = self:menuActions()[self.menuIndex]
      -- BattleMenu_Pack `.contest` (core.asm:4990): `ld a, PARK_BALL /
      -- ld [wCurItem], a / call DoItemEffect`.  No pack, no submenu -- the
      -- third slot IS the ball, so the item action becomes the throw.
      if choice == "item" and self.bugContest then
        self:bugContestBall()
        return
      end
      if choice == "fight" and self.ghost then
        self:say(Strings("%s is too\nscared to move!", self.player.name))
        self.phase = "messages"
        self.afterQueue = "menu"
        self:act(function()
          self:executeAction(self.enemy, self.player, self:enemyAction())
        end)
        self:act(function() self:endOfTurn() end)
      elseif choice == "fight" then
        -- After the menu: own trapping/Bide or foe Wrap skips the move
        -- list and forces the locked action (core.asm:320-329)
        local fightLock = self:fightLockedAction(self.player)
        if fightLock then
          self:resolveTurn(fightLock)
          return
        end
        local who = self:menuBattler()
        if not self:playerHasPP(who) then
          -- _NoMovesLeftText, then Struggle engages
          self:say(Strings("%s has no\nmoves left!", who.name))
          self:chooseAction({ id = "STRUGGLE", pp = 1, struggle = true })
          return
        end
        self.phase = "moveSelect"
        self.moveIndex = math.min(self.moveIndex, #who.curMoves)
        self.moveSwapIndex = nil
      elseif choice == "run" then
        self:tryRun()
      elseif choice == "item" then
        self:openItems()
      else
        self:openParty()
      end
    end
    return
  end

  if self.phase == "moveSelect" then
    local chooser = self:menuBattler()
    local moves = chooser.curMoves
    -- The wide layouts lay the four slots out as a 2x2 grid, so all four
    -- directions navigate it; nil means no direction was pressed and
    -- A / B / SELECT below behave the same in every layout.
    local grid = self:moveGridNavigate(self.moveIndex, #moves, input)
    if grid then
      self.moveIndex = grid
    elseif input:wasPressed("up") then
      self.moveIndex = self.moveIndex > 1 and self.moveIndex - 1 or #moves
    elseif input:wasPressed("down") then
      self.moveIndex = self.moveIndex < #moves and self.moveIndex + 1 or 1
    elseif input:wasPressed("select") then
      if self.moveSwapIndex then
        self:swapMoves(self.moveSwapIndex, self.moveIndex)
        self.moveSwapIndex = nil
      else
        self.moveSwapIndex = self.moveIndex
      end
    elseif input:wasPressed("b") then
      self.moveSwapIndex = nil
      self.phase = "menu"
    elseif input:wasPressed("a") then
      if self.moveSwapIndex then
        self:swapMoves(self.moveSwapIndex, self.moveIndex)
        self.moveSwapIndex = nil
        return
      end
      local mv = moves[self.moveIndex]
      local mvDef = mv and self.data.moves[mv.id]
      if chooser.disabledSlot == self.moveIndex then
        self:say(self:romText("_MoveDisabledText", "The move is\ndisabled!"))
        self.phase = "messages"
        self.afterQueue = "menu"
      -- TAUNT and TORMENT refuse the move at SELECTION rather than after the
      -- fact, the way DISABLE already does, so the player is never told to
      -- pick again for something the game was never going to allow.
      elseif self:tauntBlocks(chooser, mvDef) then
        self:say(Strings("%s can't use\n%s after the\ntaunt!",
                         chooser.name, mvDef and mvDef.name or mv.id))
        self.phase = "messages"
        self.afterQueue = "menu"
      elseif self:tormentBlocks(chooser, mvDef) then
        self:say(Strings("%s can't use the\nsame move twice in\na row due to the\nTORMENT!",
                         chooser.name))
        self.phase = "messages"
        self.afterQueue = "menu"
      elseif mv.pp <= 0 then
        self:say(self:romText("_MoveNoPPText", "No PP left for\nthis move!"))
        self.phase = "messages"
        self.afterQueue = "menu"
      elseif Targeting.needsChoice(self, self:choosingBattler(), mvDef) then
        -- WHICH OF THE TWO, when the move takes one and there are two.
        --
        -- Emerald's selector cycles over the legal slots and names the
        -- candidate; nothing else in the menu changes.  A single battle
        -- never gets here, because needsChoice answers false whenever there
        -- is only one thing to aim at -- and on the Game Boy cartridges the
        -- moves carry no target byte at all, so it answers false for every
        -- move in the game.
        self.pendingMove = mv
        self.targetChoices = Targeting.choices(self, self:menuBattler())
        self.targetIndex = 1
        self.phase = "targetSelect"
      else
        self:chooseAction(mv)
      end
    end
    return
  end

  -- ...and the picker itself.  LEFT and RIGHT walk the candidates, A takes
  -- one, B goes back to the move list.
  if self.phase == "targetSelect" then
    local list = self.targetChoices or {}
    if #list <= 1 then
      self.phase = "moveSelect"
      return
    end
    if input:wasPressed("left") or input:wasPressed("up") then
      self.targetIndex = self.targetIndex > 1 and self.targetIndex - 1 or #list
    elseif input:wasPressed("right") or input:wasPressed("down") then
      self.targetIndex = self.targetIndex < #list and self.targetIndex + 1 or 1
    elseif input:wasPressed("b") then
      self.pendingMove, self.targetChoices = nil, nil
      self.phase = "moveSelect"
    elseif input:wasPressed("a") then
      local mv = self.pendingMove
      local pick = list[self.targetIndex]
      self.pendingMove, self.targetChoices = nil, nil
      self.chosenTargets = self.chosenTargets or {}
      local who = self:menuBattler()
      if who and who.position then self.chosenTargets[who.position] = pick end
      self:chooseAction(mv)
    end
    return
  end

  -- Mimic's mid-move copy menu (MimicEffect .letPlayerChooseMove,
  -- effects.asm:1243-1260): opened by the queue AFTER the hit test
  -- passes.  MoveSelectionMenu's mimic type watches only UP/DOWN/A
  -- (core.asm:2553-2557), so there is no backing out with B.
  if self.phase == "mimicSelect" then
    local moves = self.mimicMoves
    -- the copy menu shares whichever move grid is up, so it navigates the
    -- same way there (the classic layout keeps the vertical list)
    local grid = self:moveGridNavigate(self.mimicIndex, #moves, input)
    if grid then
      self.mimicIndex = grid
    elseif input:wasPressed("up") then
      self.mimicIndex = self.mimicIndex > 1 and self.mimicIndex - 1 or #moves
    elseif input:wasPressed("down") then
      self.mimicIndex = self.mimicIndex < #moves and self.mimicIndex + 1 or 1
    elseif input:wasPressed("a") then
      local pick = moves[self.mimicIndex]
      local ctx = self.mimicCtx
      self.mimicMoves, self.mimicCtx = nil, nil
      self.phase = "messages"
      self.nextInsert = 0 -- the copy's anim + text go to the queue head
      self:applyMimic(ctx.user, ctx.target, ctx.moveInst, pick.slot)
    end
    return
  end
end

-- MimicEffect (engine/battle/effects.asm:1203-1273) runs MID-move: a
-- 50-frame beat, MoveHitTest, and only on a hit does the player's copy
-- menu open (.letPlayerChooseMove).  The enemy's Mimic -- and either
-- side of a link battle -- copies a RANDOM non-empty slot instead
-- (.getRandomMove).  Both failure paths (accuracy roll, mid-Fly/Dig
-- target) print PrintButItFailedText_ and skip the move animation.
function BattleState:resolveMimic(user, target, move, moveInst)
  -- ld c, 50 / call DelayFrames before anything happens
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = 50 })
  if target.invulnerable
     or not self:accuracyRoll(move, user, target) then
    self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
    return
  end
  local slots = {}
  for i, m in ipairs(target.curMoves) do
    if m.id and m.pp ~= nil then slots[#slots + 1] = i end
  end
  if #slots == 0 then
    -- .getRandomMove rerolls empty slots forever; a moveless target
    -- can't happen in practice, so just fail instead of hanging
    self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
    return
  end
  if user.isPlayer and self.kind ~= "link" then
    if self.mimicChoice then -- test-injection hook for the player pick
      local slot = self:mimicChoice(target)
      if slot and target.curMoves[slot] and target.curMoves[slot].pp ~= nil then
        self:applyMimic(user, target, moveInst, slot)
        return
      end
    end
    -- pause the queue on a chooser row; the mimicSelect phase applies
    -- the pick and resumes
    self.nextInsert = self.nextInsert + 1
    table.insert(self.queue, self.nextInsert, {
      mimicSelect = { user = user, target = target, moveInst = moveInst },
    })
    return
  end
  self:applyMimic(user, target, moveInst, slots[self.rng(1, #slots)])
end

-- The copied move OVERWRITES the used slot's move id in place; the PP
-- byte is untouched (only wBattleMonMoves is written, effects.asm:
-- 1261-1266), so the copy inherits Mimic's remaining PP and keeps
-- draining that same slot (DecrementPP hits both the battle copy and
-- the party struct).  curMoves aliases mon.moves, so the original id is
-- remembered and restored when the battler leaves play -- pokered never
-- writes the party copy, and the battle copy is rebuilt from it on a
-- switch or at battle end.  Then PlayCurrentMoveAnimation and
-- _MimicLearnedMoveText.
function BattleState:applyMimic(user, target, moveInst, slot)
  local src = target.curMoves[slot]
  if not (src and src.id) then return end
  local mySlot
  for i, m in ipairs(user.curMoves) do
    if m == moveInst then mySlot = i break end
  end
  if not mySlot then
    -- a called Mimic (Metronome) isn't in the list.  For the player,
    -- non-link case, MimicEffect snapshots wCurrentMenuItem BEFORE the
    -- copy-picker menu opens and restores it afterward as the write
    -- index (effects.asm:1247, 1256/1261) -- it reuses whatever slot
    -- was left highlighted by the FIGHT menu.  That's provably always
    -- the calling move's own slot (e.g. METRONOME's): selecting a move
    -- syncs wCurrentMenuItem and wPlayerMoveListIndex together
    -- (core.asm's SelectMenuItem), and nothing touches either before
    -- the effect runs.  self.moveIndex mirrors this exactly -- it's
    -- frozen at the FIGHT-menu confirm and untouched through mid-move
    -- resolution -- so it already equals the calling move's slot here;
    -- there's no separate "reused index" to chase.  (Enemy/link Mimic
    -- instead reads w*MoveListIndex directly, effects.asm:1235-1241.)
    mySlot = user.isPlayer and math.min(self.moveIndex or 1, #user.curMoves) or 1
  end
  local entry = user.curMoves[mySlot]
  self.mimicRestores = self.mimicRestores or {}
  table.insert(self.mimicRestores, { battler = user, entry = entry, id = entry.id })
  entry.id = src.id
  entry.mimic = true
  self:animNext("MIMIC", user.isPlayer)
  -- _MimicLearnedMoveText: "<USER> / learned / MOVE!"
  self:sayNext(self:romText("_MimicLearnedMoveText", "%s\nlearned\n%s!", displayName(user),
                                           self.data.moves[src.id].name))
end

-- Undo Mimic's in-place id overwrite for a battler leaving play (the GB
-- battle copy is discarded; the party struct never changed).
function BattleState:restoreMimicked(battler)
  if not self.mimicRestores then return end
  local keep = {}
  -- iterate newest-first so the oldest snapshot (the true pre-Mimic
  -- move id, from before any repeated Mimic-on-Mimic via Metronome)
  -- is applied last and wins, instead of a stale intermediate id
  for i = #self.mimicRestores, 1, -1 do
    local r = self.mimicRestores[i]
    if r.battler == battler then
      r.entry.id, r.entry.mimic = r.id, nil
    else
      keep[#keep + 1] = r
    end
  end
  self.mimicRestores = #keep > 0 and keep or nil
end

-- BagWasSelected's old-man fork (core.asm:2193-2210): the list menu is
-- fed OldManItemList -- one POKé BALL x50 -- instead of the player's
-- bag.  The list is as scripted as the battle menu (DisplayListMenuID's
-- old-man branch, home/list_menu.asm:65-80): no input is ever read --
-- backing out is impossible -- the '▶' sits in front of POKé BALL for
-- 80 frames, then A is auto-pressed and .buttonAPressed's
-- PlaceUnfilledArrowMenuCursor leaves the hollow '▷' on the row for the
-- handful of frames UseBagItem takes to reach ItemUseBall's screen
-- restore (item_effects.asm:145) and the throw text.
-- ...AND ON HOENN IT IS THE GEN 3 BAG.
--
-- Reported from play: "the bag he opens in the tutorial is the gen1 bag".  It
-- was: this pushes the engine's generic ListMenu, which is the Game Boy's
-- list, and Emerald's tutorial opens the real BAG screen -- pockets, the
-- picture, the description panel -- with a scripted one-ball list in it.  The
-- SHAPE is the cartridge's either way and is not changed here: the list is
-- still fixed, no button is ever read, the cursor still goes hollow on the
-- eighty-first frame and the throw still follows.  Only the screen it is
-- drawn on differs, which is the whole of the report.
function BattleState:gen3TutorialBag()
  if not require("src.core.GameVersion").isGen3() then return false end
  local ok, Gen3BagMenu = pcall(require, "src.ui.Gen3BagMenu")
  if not (ok and type(Gen3BagMenu) == "table"
          and type(Gen3BagMenu.new) == "function") then
    return false
  end
  local game = self.game
  self.phase = "messages"
  self.afterQueue = "menu"
  self:ui(function()
    local bag
    bag = Gen3BagMenu.new(game, {
      pocket = "BALL",
      noInput = true,
      rows = { { id = "POKE_BALL", label = Strings("POKé BALL"),
                 qty = tonumber((self.demoBallCount or "x1"):match("%d+")) } },
      script = function(b)
        b.scriptTimer = (b.scriptTimer or 0) + 1
        if b.scriptTimer > 88 then
          b.script = nil
          game.stack:pop()
          self:oldManThrow()
        end
      end,
    })
    return bag
  end)
  return true
end

function BattleState:openOldManBag()
  if self:gen3TutorialBag() then return end
  local ListMenu = require("src.ui.ListMenu")
  local game = self.game
  self.phase = "messages"
  self.afterQueue = "menu"
  self:ui(function()
    local list
    list = ListMenu.new(game, "ITEMS", {
      -- .LoadDudeData gives the Gen2 tutorial exactly one ball
      { value = "POKE_BALL", label = Strings("POKé BALL"),
        right = self.demoBallCount or "x50" },
    }, {
      script = function(l)
        l.scriptTimer = (l.scriptTimer or 0) + 1
        if l.scriptTimer == 81 then
          -- the auto A-press: the cursor goes hollow on the chosen row
          l.hollowIndex = l.index
        elseif l.scriptTimer > 88 then
          -- ItemUseBall takes over: list down, OLD MAN throws
          l:close()
          self:oldManThrow()
        end
      end,
    })
    return list
  end)
end

-- ItemUseBall for BATTLE_TYPE_OLD_MAN: the party/box-full checks are
-- skipped (item_effects.asm:114-118), every capture calculation is
-- skipped -- the old man branch jumps straight to .captured, $43 anim
-- data = 3 shakes and caught (:155-164 + :193-200) -- and
-- .oldManCaughtMon prints the caught text WITHOUT adding the mon to
-- the party or the dex (:568-570).  The "used" line reads OLD MAN
-- because DisplayBattleMenu swapped wPlayerName (core.asm:2024-2037);
-- no ball is consumed (.done returns early, :576-578).
function BattleState:oldManThrow()
  self.phase = "messages"
  self.afterQueue = "finish"
  self.result = "run" -- nothing is kept; wBattleResult only ends the demo
  self:say(Strings("%s used\nPOKé BALL!", self.demoName or "OLD MAN"))
  self:act(function()
    require("src.core.Sound").play(self.data, "Ball_Toss")
    -- ItemUseBall's beat before the toss chain (like throwBall)
    self.nextInsert = (self.nextInsert or 0) + 1
    table.insert(self.queue, self.nextInsert, { wait = 20 })
    self:ballChain("TOSS_ANIM", true, 3, "POKE_BALL")
    self:actNext(function()
      require("src.core.Sound").play(self.data, "Caught_Mon")
    end)
    self:sayNext(Strings("All right!\n%s was\ncaught!", self.enemy.name))
  end)
end

-- ---------------------------------------------------------------------
-- turn resolution
-- ---------------------------------------------------------------------

function BattleState:moveDef(moveInst)
  return self.data.moves[moveInst.id]
end

-- the merged move_effects record for an effect id; the module records
-- cover battles built without a loader
function BattleState:effectRecord(effect)
  local effects = self.data.move_effects
  if effects then return effects[effect] end
  return MoveEffects.RECORDS[effect]
end

-- the merged ball record (Catching.attempt handles the unknown-id default)
function BattleState:ballDef(ball)
  local balls = self.data.balls
  return balls and balls[ball] or Catching.BALLS[ball]
end

-- Gen2's item ids are ITEM_nnn while the battle code keys balls by Gen1's
-- name-derived ids, so fall back to the def carrying that id as its `key`.
function BattleState:itemDef(id)
  local items = self.data.items
  if not items then return nil end
  if items[id] then return items[id] end
  self.itemsByKey = self.itemsByKey or (function()
    local byKey = {}
    for itemId, def in pairs(items) do
      byKey[def.key or itemId] = def
    end
    return byKey
  end)()
  return self.itemsByKey[id]
end

-- the HUD label drawn in place of the level for a statused mon
function BattleState:statusLabel(mon)
  local record = Status.recordFor(self.data.statuses, mon.status)
  if record then
    return record.hudLabel or record.label or mon.status
  end
  return mon.status
end

-- The one accuracy roll (MoveHitTest), hooked as battle.accuracy.
-- accuracyRaw is a 0-255 threshold that stands in for the move's accuracy byte
-- this turn -- Gen 2's BattleCommand_ThunderAccuracy overwrites that byte in
-- sun and rain, and `50 percent + 1` is 128 rather than the 127 a percentage
-- would round to.
function BattleState:accuracyRoll(move, user, target, accuracyRaw)
  -- LOCK-ON / MIND READER: the next move cannot miss, and the aim is spent
  -- whether it was needed or not.
  if user.lockedOn == target then
    user.lockedOn = nil
    return true
  end
  if Runtime.wantsHook("battle.accuracy") then
    return Runtime.call("battle.accuracy", function(c)
      return Damage.accuracyRoll(c.ruleset, c.move, c.user, c.target, c.rng,
                                 c.accuracyRaw, c.data, c.weather)
    end, { battle = self, ruleset = self.ruleset, move = move,
           user = user, target = target, rng = self.rng, data = self.data,
           accuracyRaw = accuracyRaw, weather = Weather.current(self) })
  end
  return Damage.accuracyRoll(self.ruleset, move, user, target, self.rng,
                             accuracyRaw, self.data, Weather.current(self))
end

-- Damage.compute, hooked as battle.damage; the ctx table is only built
-- when a chain is installed, so the no-mod path allocates nothing
function BattleState:computeDamage(user, target, move, opts)
  -- Damage's Gen II held-item path needs the imported item records alongside
  -- the ordinary formula options. Keep Gen I's no-mod fast path allocation-free.
  if self.data and self.data.constants and self.data.constants.generation == 2 then
    opts = opts or {}
    opts.data = opts.data or self.data
  end
  -- DoWeatherModifiers reads wBattleWeather inside the damage calc; the port
  -- keeps it on the field, so it rides in on opts rather than widening
  -- Damage.compute's signature.  nil on Gen 1 and whenever no weather is up.
  -- Weather.current rather than field.weather: CLOUD NINE and AIR LOCK do
  -- not clear the sky, they stop it counting, and the damage calc is the
  -- biggest thing that counts it
  local sky = Weather.current(self)
  if sky then
    opts = opts or {}
    if opts.weather == nil then opts.weather = sky end
  end
  -- MUD SPORT and WATER SPORT ride in the same way, and for the same reason:
  -- they live on the field and Damage.compute is handed battlers.
  if self.field and (self.field.mudSport or self.field.waterSport) then
    opts = opts or {}
    if opts.sports == nil then
      opts.sports = { self.field.mudSport, self.field.waterSport }
    end
  end
  -- HOW MANY ARE STILL STANDING ON THE OTHER SIDE, which is the condition
  -- BOTH of the cartridge's doubles damage rules hang on.
  --
  -- CountAliveMonsInBattle(BATTLE_ALIVE_DEF_SIDE) == 2 gates the spread
  -- halving (0806_9BB2) and the weaker screens (0806_9B6C) alike -- with one
  -- foe left, a spread move does FULL damage and a screen halves normally.
  -- Both ride in on opts, the way the weather and the sports already do,
  -- rather than widening Damage.compute's signature.
  if self:isDouble() and target then
    opts = opts or {}
    local alive = 0
    for flank = 1, 2 do
      local b = self.sides[target.isPlayer and 1 or 2].battlers[flank]
      if b and b.mon and (b.mon.hp or 0) > 0 then alive = alive + 1 end
    end
    if alive == 2 then
      if opts.doublesScreens == nil then opts.doublesScreens = true end
      -- ...and the spread half, but ONLY for MOVE_TARGET_BOTH.  The compare
      -- at 0806_9BA4 is `cmp #8`, not a mask: EARTHQUAKE and EXPLOSION are
      -- $20 and are not reduced at all on this cartridge.
      if opts.spread == nil and tonumber(move and move.target) == 0x08 then
        opts.spread = true
      end
    end
  end
  if Runtime.wantsHook("battle.damage") then
    return Runtime.call("battle.damage", function(c)
      return Damage.compute(c.ruleset, c.user, c.target, c.move, c.opts)
    end, { battle = self, ruleset = self.ruleset, user = user,
           target = target, move = move, opts = opts, rng = self.rng })
  end
  return Damage.compute(self.ruleset, user, target, move, opts)
end

-- Catching.attempt against the merged registry, hooked as catch.rate
function BattleState:catchAttempt(ball, rateOverride)
  if Runtime.wantsHook("catch.rate") then
    local battle = self
    return Runtime.call("catch.rate", function(b, mon, def, o)
      return Catching.attempt(b, mon, def, o.rng, o.rateOverride,
        { ballDef = battle:ballDef(b), statuses = battle.data.statuses,
          battle = battle })
    end, ball, self.enemy.mon, self.enemy.def,
    { rng = self.rng, rateOverride = rateOverride, battle = self })
  end
  return Catching.attempt(ball, self.enemy.mon, self.enemy.def, self.rng,
    rateOverride, { ballDef = self:ballDef(ball),
                    statuses = self.data.statuses, battle = self })
end

-- wAICount: item/switch uses per enemy Pokémon for this trainer class
function BattleState:aiUsesFor()
  if self.kind ~= "trainer" or not self.trainer then return 0 end
  local class = TrainerAI.classFor(self)
  return class and class.uses or 0
end

-- Exp participants: every player mon that has been in against the
-- current enemy mon (wPartyGainExpFlags).
function BattleState:markParticipant()
  self.participants = self.participants or {}
  if self.player and self.player.mon then
    self.participants[self.player.mon] = true
    HeldItems.observeParticipant(self, self.player)
  end
end

-- the whole choke point is hooked (battle.enemy_action), so a mod can
-- rewrite any trainer's choice without registering brains
--
-- WHICH SLOT IS ASKED.  In a single battle there is one foe and this took no
-- argument at all; `actionFor` passes the right-hand opponent here in a
-- double and the argument was being DROPPED, so both enemy slots ran the
-- action chosen for the left one -- two Pokemon using the same move against
-- the same target, chosen by a scorer that had only looked at one of them.
--
-- And the left slot can be EMPTY: a foe that faints in a double battle is
-- lifted off the field (doubleFaint) and only replaced at the end of the
-- turn, so with the bench exhausted `self.enemy` is nil while the other slot
-- is still fighting.  That is the crash reported from play --
-- "menuLockedAction: attempt to index local 'battler' (a nil value)" after
-- killing their first Pokemon.  A slot with nobody in it has no action.
function BattleState:enemyAction(battler)
  battler = battler or self.enemy
  if not battler then return nil end
  if Runtime.wantsHook("battle.enemy_action") then
    return Runtime.call("battle.enemy_action", function(battle, who)
      return battle:vanillaEnemyAction(who)
    end, self, battler)
  end
  return self:vanillaEnemyAction(battler)
end

function BattleState:vanillaEnemyAction(battler)
  battler = battler or self.enemy
  if not battler then return nil end
  local locked = self:lockedAction(battler)
  if locked then return locked end
  -- an ai_classes brain (or one on the trainer record) supersedes the
  -- class action and move scoring entirely
  if self.kind == "trainer" and self.trainer then
    local class = TrainerAI.classFor(self)
    local brain = self.trainer.brain or (class and class.brain)
    if brain then return brain(self, battler) end
  end
  -- CLASS AI MAY SPEND THE TURN ON AN ITEM OR A SWITCH -- but a trainer has
  -- one bag and one bench, not one per slot, so it is asked once, for the
  -- slot the whole of TrainerAI already reads (`battle.enemy`).  Letting the
  -- right-hand slot ask too would have a trainer drink two SUPER POTIONs on
  -- the same Pokemon in the same turn.
  if battler == self.enemy then
    local classAct = TrainerAI.classAction(self)
    if classAct then return classAct end
  end
  return TrainerAI.chooseMove(battler, self.rng, self)
end

local function orderMove(action, data)
  if action and action.id then return data.moves[action.id] end
  return nil
end

-- TWO CHOICES BEFORE THE TURN RUNS.
--
-- A single battle asks the player once and resolves.  A double asks twice --
-- the left slot then the right -- and only then does anybody move, which is
-- why Emerald lets B on the second choice take you back to the first.
--
-- Everything upstream of here is unchanged: the menu still chooses for
-- `self:choosingBattler()`, and in a single battle that is `self.player` and
-- this is one call straight through to resolveTurn.
-- WHICH OF THE PLAYER'S TWO SLOTS THE MENU IS STANDING IN FRONT OF.
--
-- Not simply "the left one first": a left slot whose Pokemon has fainted is
-- EMPTY until the end of the turn fills it, and the menu still has to be
-- asked -- for the partner.  Answering PLAYER_LEFT there asked the question
-- for a Pokemon that was not on the field and then, because the answer was
-- filed under the left slot, asked again for the right one and threw the
-- first answer away.
function BattleState:choosingSlotNow()
  local pos = self.choosingSlot
  if pos and self:battlerAt(pos) then return pos end
  for _, p in ipairs({ BattleState.POS.PLAYER_LEFT,
                       BattleState.POS.PLAYER_RIGHT }) do
    if self:battlerAt(p) then return p end
  end
  return BattleState.POS.PLAYER_LEFT
end

function BattleState:chooseAction(action)
  if not self:isDouble() then return self:resolveTurn(action) end
  local pos = self:choosingSlotNow()
  self.pendingActions = self.pendingActions or {}
  self.pendingActions[pos] = action
  if pos ~= BattleState.POS.PLAYER_RIGHT
     and self:battlerAt(BattleState.POS.PLAYER_RIGHT) then
    -- ask the other one before anybody moves
    self.choosingSlot = BattleState.POS.PLAYER_RIGHT
    self.phase = "menu"
    self.moveIndex = 1
    return
  end
  self.choosingSlot = nil
  local first = self.pendingActions[BattleState.POS.PLAYER_LEFT]
  self:resolveTurn(first)
end

-- WHICH SLOT THE MENU IS CHOOSING FOR.  `self.player` in a single battle,
-- which is every call this had before doubles.
function BattleState:choosingBattler()
  if not self:isDouble() then return self.player end
  return self:battlerAt(self:choosingSlotNow()) or self.player
end

function BattleState:resolveTurn(playerAction)
  -- nil in a double battle whose left-hand foe has fainted with nothing on
  -- the bench to replace it; `actionFor` asks each surviving slot for its own
  local enemyAction = self:enemyAction(self.enemy)
  self.turnCount = (self.turnCount or 0) + 1
  -- TURN-SCOPED FLAGS, cleared before anybody moves.  REVENGE reads
  -- hurtThisTurn, FAKE OUT reads turnsOut, and PROTECT and ENDURE only stand
  -- for the turn they were used on.
  for _, b in activeBattlers(self) do
    if b then
      b.hurtThisTurn = nil
      b.specialDamageTaken, b.physicalDamageTaken = nil, nil
      b.protecting, b.enduring = nil, nil
      b.turnsOut = (b.turnsOut or 0) + 1
    end
  end
  Runtime.emit("battle.turn_started", {
    battle = self, turn = self.turnCount,
    playerAction = playerAction, enemyAction = enemyAction,
  })
  local pMove = orderMove(playerAction, self.data)
  local eMove = orderMove(enemyAction, self.data)
  -- QUICK CLAW, before the speed comparison and before priority is even
  -- read: AI_TryToFaint's caller rolls Random() % 100 against the item's own
  -- parameter for each side and a winner simply goes first.  Both sides
  -- rolling it is not a draw -- the cartridge checks the player's first, so
  -- a double claw is the player's turn.
  local pClaw = self:quickClawWins(self.player)
  local eClaw = not pClaw and self:quickClawWins(self.enemy)
  local pFirst
  -- EITHER LEFT SLOT CAN BE EMPTY IN A DOUBLE.  A fainted battler is lifted
  -- off the field at once and only replaced when the turn ends, so between
  -- those two moments `self.player` or `self.enemy` is nil while the other
  -- flank fights on.  The pairwise comparison below is the SINGLE battle's
  -- ordering and has nothing to compare; the double branch sorts all four
  -- entries with the same comparator a few lines down and does not read it.
  if not (self.player and self.enemy) then
    pFirst = true
  elseif pClaw or eClaw then
    pFirst = pClaw == true
  elseif Runtime.wantsHook("battle.turn_order") then
    pFirst = Runtime.call("battle.turn_order", function(a, aMove, b, bMove, c)
      return TurnOrder.firstMover(a, aMove, b, bMove, c.rng, c.invertTie,
                                  c.battle, c.data)
    end, self.player, pMove, self.enemy, eMove,
       { rng = self.rng, battle = self, data = self.data })
  else
    -- the battle goes along so SWIFT SWIM and CHLOROPHYLL can see the weather,
    -- and the dataset so Gen II's own QUICK CLAW can be looked up
    pFirst = TurnOrder.firstMover(self.player, pMove, self.enemy, eMove,
                                  self.rng, nil, self, self.data)
  end
  if pClaw or eClaw then
    local holder = pClaw and self.player or self.enemy
    self:say(Strings("%s's QUICK CLAW\nactivated!", displayName(holder)))
  end
  local order
  if self:isDouble() then
    -- FOUR ENTRIES, SORTED WITH THE SAME COMPARATOR.
    --
    -- SetActionsAndBattlersTurnOrder builds the list in position order and
    -- bubbles it with GetWhoStrikesFirst, which is firstMover -- so this is
    -- the same rule applied to four rather than a second rule for doubles.
    -- Built in position order 0,1,2,3 because that is the order the
    -- cartridge fills its own array in, and a bubble is stable, so
    -- equal-speed entries fall out the same way it does.
    local entries = {}
    for pos = 0, 3 do
      local b = self:battlerAt(pos)
      if b and b.mon and (b.mon.hp or 0) > 0 then
        local action = self:actionFor(b, playerAction, enemyAction)
        entries[#entries + 1] = { battler = b, move = orderMove(action, self.data),
                                  action = action }
      end
    end
    TurnOrder.order(entries, self.rng, self)
    -- and a QUICK CLAW winner is simply hoisted to the front
    if pClaw or eClaw then
      local holder = pClaw and self.player or self.enemy
      for i, e in ipairs(entries) do
        if e.battler == holder then
          table.remove(entries, i)
          table.insert(entries, 1, e)
          break
        end
      end
    end
    -- ...AND EVERY SWITCH HAPPENS BEFORE EVERY MOVE.
    --
    -- SetActionsAndBattlersTurnOrder runs the switch actions out of the array
    -- first and only then sorts what is left, so a Pokemon that is being
    -- withdrawn is gone before anybody swings at it.  A stable partition
    -- keeps the speed order the sort just produced within each group.
    local switches, moves = {}, {}
    for _, e in ipairs(entries) do
      local sp = e.action and e.action.special
      if sp == "playerSwitch" or sp == "aiSwitch" then
        switches[#switches + 1] = e
      else
        moves[#moves + 1] = e
      end
    end
    if #switches > 0 then
      entries = switches
      for _, e in ipairs(moves) do entries[#entries + 1] = e end
    end
    order = {}
    for _, e in ipairs(entries) do
      -- the target is resolved as the entry runs, not now: it may have
      -- fainted in between
      order[#order + 1] = { e.battler, nil, e.action }
    end
  elseif pFirst then
    order = { { self.player, self.enemy, playerAction },
              { self.enemy, self.player, enemyAction } }
  else
    order = { { self.enemy, self.player, enemyAction },
              { self.player, self.enemy, playerAction } }
  end

  self.phase = "messages"
  self.afterQueue = "menu"

  for _, entry in ipairs(order) do
    self:act(function()
      -- WHO IT HITS IS DECIDED HERE, not when the turn was sorted.
      --
      -- Between the sort and this entry running, the target can faint --
      -- your partner moved first, or its own ally hit it.  The cartridge
      -- re-points at whoever is still standing rather than wasting the turn
      -- (MOVEEND / GetBattlerAtPosition).  In a single battle `entry[2]` is
      -- already the one foe and this changes nothing.
      local target = entry[2]
      if target == nil then
        -- what the player aimed at, if they were asked; otherwise whoever
        -- is standing on the other side
        local chosen = (self.chosenTargets or {})[entry[1].position]
        target = Targeting.redirect(self, entry[1], nil, chosen)[1]
                 or self:defaultTargetFor(entry[1])
      end
      self:executeAction(entry[1], target, entry[3])
    end)
  end
  self:act(function()
    -- the collected choices belong to the turn that just ran, not the next
    self.pendingActions, self.chosenTargets = nil, nil
    self:endOfTurn()
  end)
end

-- WHICH ACTION BELONGS TO WHICH SLOT.
--
-- The turn loop collects one action for the player and asks the AI for one
-- for the enemy, and in a single battle that is the whole field.  In a
-- double the two right-hand slots need theirs too: the player's from the
-- second menu pass, the opponent's from the AI, run once per enemy slot.
function BattleState:actionFor(battler, playerAction, enemyAction)
  if battler == self.player then return playerAction end
  if battler == self.enemy then return enemyAction end
  if battler.isPlayer then
    return (self.pendingActions or {})[battler.position] or playerAction
  end
  return self:enemyAction(battler)
end

-- The foe a move goes to when nothing has chosen one: the first still
-- standing on the other side, which in a single battle is the only one.
function BattleState:defaultTargetFor(battler)
  local foes = foesOf(self, battler)
  return foes[1]
end

-- A switch action: replace the player's mon, enemy gets a free move.
function BattleState:resolveSwitch(newMon)
  -- INGRAIN: a Pokemon that has put its roots down does not leave.  Refused
  -- here rather than at the menu so a forced switch is refused too.
  if self.player and self.player.ingrained and self.player.mon.hp > 0 then
    self:say(Strings("%s anchored\nitself with its\nroots!",
                     displayName(self.player)))
    self.phase = "messages"
    self.afterQueue = "menu"
    return
  end
  self.phase = "messages"
  self.afterQueue = "menu"
  self:act(function() self:switchPlayerInto(BattleState.POS.PLAYER_LEFT,
                                            newMon) end)
  self:act(function()
    self:executeAction(self.enemy, self.player, self:enemyAction())
  end)
  self:act(function() self:endOfTurn() end)
end

-- ONE SLOT LEAVES AND ANOTHER ARRIVES IN IT.
--
-- Lifted out of resolveSwitch unchanged except that it names a POSITION
-- rather than `self.player`.  A single battle has one slot to switch and
-- passes PLAYER_LEFT, which is what `self.player` means -- so nothing about
-- that path moves.  A double has two, and the menu can be standing in front
-- of either: choosing POKeMON for the right-hand slot used to withdraw the
-- LEFT one, because there was no way to say which.
function BattleState:switchPlayerInto(pos, newMon)
  local previous = self:battlerAt(pos)
  self:restoreMimicked(previous)      -- the battle copy leaves with it
  local incoming = makeBattler(self.data, newMon, true, self.game.save)
  self:placeBattler(pos, incoming)
  -- BATON PASS: the stat stages and the volatiles go with the switch, which
  -- is the whole move.  Nothing else survives a switch, so a pass that was
  -- never set leaves the incoming Pokemon exactly as makeBattler built it.
  local pass = previous and previous.batonPass
  if pass then
    incoming.stages = pass.stages or incoming.stages
    incoming.confusedTurns = pass.confusedTurns
    incoming.substituteHP = pass.substituteHP
    incoming.leechSeeded = pass.leechSeeded
    incoming.perishTurns = pass.perishTurns
    previous.batonPass, previous.wantsSwitch = nil, nil
  end
  -- SendOutMon (core.asm:1761-1762): player's send-out clears the
  -- foe's USING_TRAPPING_MOVE -- Wrap/Bind/etc. ends on any switch.  With
  -- four on the field that is every foe, not "the" foe.
  if self:isDouble() then
    for _, foe in ipairs(foesOf(self, incoming)) do clearTrapping(foe) end
  else
    clearTrapping(self.enemy)
  end
  self:syncSides()
  Runtime.emit("battle.battler_switched", {
    battle = self, side = self.sides[1], battler = incoming,
    previous = previous,
  })
  self:abilitySwitchOut(previous)
  self:markParticipant()
  self.sendingOut = true
  self:sayNext(self:sendOutText(incoming.name))
  self:animNext("POOF_ANIM", false)
  self:shinyAnim(incoming, false)
  self:actNext(function()
    self.sendingOut = false
    -- SendOutMon (core.asm:1757-1762): poof, then the grow-in
    self:startGrowIn(incoming)
    require("src.core.Sound").playCry(self.data, incoming.mon.species)
    HeldItems.onEntry(self, incoming)
  end)
  -- ABILITYEFFECT_ON_SWITCHIN, after the send-out and its cry: an
  -- INTIMIDATE drops the foe's attack now, before the free move below
  self:actNext(function() self:abilitySwitchIn(incoming) end)
  return incoming
end

-- ---------------------------------------------------------------------
-- ABILITIES IN THE TURN LOOP
-- ---------------------------------------------------------------------
--
-- src/battle/Abilities.lua decides WHAT happens and this decides what that
-- costs on screen: which message, whose bar moves, which stage changes.
-- Every one of these is a nil check away from doing nothing at all, which
-- is what a Gen 1 or Gen 2 battle gets.

-- "X's ABILITY!" is not a line the cartridge prints on its own -- the
-- ability's name is folded into the sentence each effect prints.  These
-- helpers keep that wording in one place.
local ABILITY_LABEL = {
  INTIMIDATE = "INTIMIDATE", SPEED_BOOST = "SPEED BOOST",
  SHED_SKIN = "SHED SKIN", RAIN_DISH = "RAIN DISH",
  VOLT_ABSORB = "VOLT ABSORB", WATER_ABSORB = "WATER ABSORB",
  FLASH_FIRE = "FLASH FIRE", STATIC = "STATIC",
  POISON_POINT = "POISON POINT", FLAME_BODY = "FLAME BODY",
  ROUGH_SKIN = "ROUGH SKIN", DRIZZLE = "DRIZZLE", DROUGHT = "DROUGHT",
  SAND_STREAM = "SAND STREAM", ROCK_HEAD = "ROCK HEAD",
}

local function abilityLabel(name)
  return ABILITY_LABEL[name] or (tostring(name):gsub("_", " "))
end

BattleState.abilityLabel = abilityLabel

local function maxHpOf(battler)
  local mon = battler.mon
  return (mon.stats and mon.stats.hp) or mon.maxHp or 1
end

-- Heal a fraction of maximum HP, floored at 1, capped at full.  Returns the
-- HP actually restored so a caller can stay quiet when nothing moved.
function BattleState:abilityHeal(battler, numerator, denominator)
  local max = maxHpOf(battler)
  local amount = math.max(1, math.floor(max * numerator / denominator))
  local before = battler.mon.hp
  battler.mon.hp = math.min(max, before + amount)
  local gained = battler.mon.hp - before
  if gained > 0 then self:drainNext(battler, battler.mon.hp) end
  return gained
end

-- SWITCH-IN.  Called wherever a Pokemon reaches the field -- the first
-- send-out of the battle and all four switch paths -- because that is when
-- ABILITYEFFECT_ON_SWITCHIN runs on the cartridge.  A MIGHTYENA leading a
-- trainer battle drops the player's attack before either side has moved,
-- and a GROUDON's sun is up from the first turn.
function BattleState:abilitySwitchIn(battler)
  if not (battler and battler.mon and battler.mon.hp > 0) then return end
  -- SPIKES first: the hazard is paid on arrival, before the ability speaks.
  -- An eighth of maximum HP, and a FLYING or LEVITATing Pokemon never lands
  -- on them at all.
  local side = self.sideOf and self:sideOf(battler)
  if side and side.spikes then
    local grounded = Abilities.of(battler) ~= "LEVITATE"
    for _, t in ipairs(battler.curTypes or {}) do
      if t == "FLYING" then grounded = false end
    end
    if grounded then
      local max = (battler.mon.stats and battler.mon.stats.hp) or battler.mon.hp
      self:sayNext(Strings("%s is hurt\nby SPIKES!", displayName(battler)))
      self:applyDamage(battler, math.max(1, math.floor(max / 8)))
      self:drainNext()
      if battler.mon.hp <= 0 then
        self:onFaint(battler)
        return
      end
    end
  end
  -- FORECAST first: a CASTFORM arriving into rain is a WATER type before
  -- anything else on the field gets to speak.
  self:abilityForecast(battler)
  local act = Abilities.onSwitchIn(battler)
  if not act then return end
  self:abilitySwitchInEffect(battler, act)
end

-- The visible half of a switch-in ability, split out so TRACE can run the
-- effect of whatever it just copied.
function BattleState:abilitySwitchInEffect(battler, act)
  local who = displayName(battler)
  if act.kind == "weather" then
    -- permanent: DROUGHT's sun does not run out the way SUNNY DAY's does
    Weather.start(self, act.weather, act.permanent)
    self:sayNext(Strings("%s's\n%s!", who, abilityLabel(act.ability)))
    local started = Weather.STARTED_TEXT[act.weather]
    if started then self:sayNext(Strings(started)) end
    return
  end
  -- TRACE takes the foe's ability the moment it arrives, and keeps it until
  -- it leaves -- abilityOverride is a BATTLER field, so switching out drops
  -- it exactly as the cartridge does.  Nothing to copy (a Gen 1 foe, an
  -- empty slot, or one of the three the cartridge refuses) and TRACE simply
  -- stays TRACE and says nothing.
  if act.kind == "trace" then
    for _, foe in ipairs(foesOf(self, battler)) do
      local copied = Abilities.traceable(foe)
      if copied then
        battler.abilityOverride = copied
        self:sayNext(Strings("%s TRACED\n%s's\n%s!", who, displayName(foe),
                             abilityLabel(copied)))
        -- ...and the copied ability arrives too.  A TRACE onto an
        -- INTIMIDATE or a DROUGHT fires it, because on the cartridge the
        -- switch-in effect runs off the ability the Pokemon HAS.
        local traced = Abilities.onSwitchIn(battler)
        if traced and traced.kind ~= "trace" then
          self:abilitySwitchInEffect(battler, traced)
        end
        return
      end
    end
    return
  end
  if act.kind == "intimidate" then
    -- INTIMIDATE FACES THE WHOLE OTHER SIDE.  In a single battle foesOf
    -- answers the one battler this used to name; in a double it answers
    -- both, which is what the cartridge does -- the ability drops the
    -- attack of every opposing Pokemon on the field, not just one.
    local foes = foesOf(self, battler)
    if #foes == 0 then return end
    self:sayNext(Strings("%s's\n%s!", who, abilityLabel(act.ability)))
    -- through changeStage, so CLEAR BODY and HYPER CUTTER get their say and
    -- a substitute blocks it exactly as it blocks a GROWL
    for _, foe in ipairs(foes) do
      for _, m in ipairs(MoveEffects.changeStage(self, foe, act.stat,
                                                 act.delta, true)) do
        self:sayNext(m)
      end
    end
  end
end

-- SWITCH-OUT, which is one ability and one that nobody notices is missing
-- until they meet a STARMIE.
--
-- NATURAL CURE clears the status the moment the Pokemon leaves the field --
-- not at the end of the battle, not on the next heal.  It is why a
-- BLISSEY can absorb a TOXIC and walk it off, and it is the only reason the
-- ability exists.
--
-- The status lives on the MON, which stays in the party, so this is the one
-- ability whose effect outlives the battler it belongs to.
function BattleState:abilitySwitchOut(previous)
  if not (previous and previous.mon) then return end
  if not Abilities.curesOnSwitchOut(previous) then return end
  if not previous.mon.status then return end
  previous.mon.status = nil
  previous.toxicCounter = nil
  previous.sleepTurns = nil
end

-- ON CONTACT, after the move has finished resolving.  Only a move whose
-- extracted flags byte says it touches gets here (Abilities.onContact
-- refuses the rest), so a FLAMETHROWER never burns its user on a FLAME BODY
-- while a TACKLE does.
function BattleState:abilityOnContact(user, target, move)
  if not (user and target and move) then return end
  if user.mon.hp <= 0 then return end
  -- a substitute took the hit, so nothing touched the Pokemon behind it
  if target.substituteHP then return end
  local act = Abilities.onContact(target, move)
  if not act then return end
  local rng = self.rng or love.math.random
  if act.kind == "status" then
    if rng(1, act.oneIn) ~= 1 then return end
    local msgs = StatusRegistry.inflict(self, user, act.status,
                                        { secondary = true, user = target,
                                          source = act.ability })
    if #msgs == 0 then return end
    self:sayNext(Strings("%s's\n%s!", displayName(target),
                         abilityLabel(act.ability)))
    for _, m in ipairs(msgs) do self:sayNext(m) end
    return
  end
  -- EFFECT SPORE is ONE roll with three outcomes: Random() % 10, and 0, 1
  -- and 2 are poison, sleep and paralysis.  Not three separate rolls, and
  -- not a 30% chance of a random one of the three -- 10% each, which is why
  -- it could not be another row in CONTACT_STATUS.
  if act.kind == "statusRoll" then
    local roll = rng(0, act.outOf - 1)
    local status = act.table[roll]
    if not status then return end
    local msgs = StatusRegistry.inflict(self, user, status,
                                        { secondary = true, user = target,
                                          source = act.ability })
    if #msgs == 0 then return end
    self:sayNext(Strings("%s's\n%s!", displayName(target),
                         abilityLabel(act.ability)))
    for _, m in ipairs(msgs) do self:sayNext(m) end
    return
  end
  -- CUTE CHARM, on the same one-in-three, and only between a male and a
  -- female.  Two of the same gender, or anything genderless, and touching a
  -- SKITTY is just touching a SKITTY.
  if act.kind == "infatuate" then
    if rng(1, act.oneIn) ~= 1 then return end
    if not require("src.pokemon.Pokemon").oppositeGenders(self.data, user.mon,
                                                          target.mon) then
      return
    end
    if user.infatuated then return end
    if Abilities.refusesStatus(user, "INFATUATION") then return end
    user.infatuated = target
    self:sayNext(Strings("%s's\n%s!", displayName(target),
                         abilityLabel(act.ability)))
    self:sayNext(Strings("%s fell in love!", displayName(user)))
    return
  end
  if act.kind == "recoil" then
    -- ROUGH SKIN bites for a sixteenth of the ATTACKER's maximum, every
    -- time, with no roll at all
    local hurt = math.max(1, math.floor(maxHpOf(user)
                                        * act.numerator / act.denominator))
    self:sayNext(Strings("%s's\n%s!", displayName(target),
                         abilityLabel(act.ability)))
    self:applyDamage(user, hurt)
    self:drainNext()
    if user.mon.hp <= 0 then self:onFaint(user) end
  end
end

-- COLOR CHANGE.  KECLEON is the only Pokemon with it, and it is the whole of
-- what KECLEON is: whatever just hit it, that is now its type -- one type,
-- replacing both if it had two.
--
-- curTypes is the battler's own list, so it goes when the Pokemon does,
-- which is the cartridge's rule as well.
function BattleState:abilityColorChange(target, move, damage)
  local act = Abilities.colorChange(target, move, damage)
  if not act then return end
  target.curTypes = { act.type }
  self:sayNext(Strings("%s's\n%s!", displayName(target),
                       abilityLabel(act.ability)))
  self:sayNext(Strings("%s transformed\ninto the %s type!",
                       displayName(target), tostring(act.type)))
end

-- FORECAST.  CASTFORM is the sky: sun makes it FIRE, rain WATER, hail ICE,
-- and anything else -- including a sandstorm, which has no CASTFORM form --
-- puts it back to NORMAL.
--
-- Asked wherever the weather can have changed: a switch-in, a weather move,
-- and the end of a turn when a weather ran out.  Answers true when it moved,
-- so the caller can decide whether a line is worth printing.
function BattleState:abilityForecast(battler)
  if not (battler and battler.mon and battler.mon.hp > 0) then return false end
  local want = Abilities.forecastType(battler, Weather.current(self))
  if not want then return false end
  local types = battler.curTypes
  if type(types) == "table" and #types == 1 and types[1] == want then
    return false
  end
  battler.curTypes = { want }
  self:sayNext(Strings("%s's\n%s!", displayName(battler),
                       abilityLabel("FORECAST")))
  self:sayNext(Strings("%s transformed\ninto the %s type!",
                       displayName(battler), want))
  return true
end

-- Both sides, for the callers that only know the weather changed.
function BattleState:forecastAll()
  for _, b in ipairs({ self.player, self.enemy }) do
    if b then self:abilityForecast(b) end
  end
end

-- THE ABSORBS.  Abilities.blocks already stopped the damage; this is the
-- half that was missing -- a quarter of maximum HP for VOLT ABSORB and
-- WATER ABSORB, and the standing fire boost for FLASH FIRE.  Returns true
-- when it printed something, so the caller can skip the plain
-- "It doesn't affect X!" line the type chart would otherwise print.
function BattleState:abilityAbsorb(target, move)
  local act = Abilities.absorbs(target, move)
  if not act then return false end
  local who = displayName(target)
  self:sayNext(Strings("%s's\n%s!", who, abilityLabel(act.ability)))
  if act.kind == "flashFire" then
    if target.flashFire then
      self:sayNext(Strings("But, it failed!"))
    else
      target.flashFire = true
      self:sayNext(Strings("%s's FIRE\nmoves were\npowered up!", who))
    end
    return true
  end
  local max = maxHpOf(target)
  if target.mon.hp >= max then
    self:sayNext(Strings("%s's\nHP is full!", who))
    return true
  end
  self:abilityHeal(target, act.numerator, act.denominator)
  self:sayNext(Strings("%s\nrestored health!", who))
  return true
end

-- END OF TURN, one battler at a time, in the order endOfTurn already walks.
function BattleState:abilityEndOfTurn(battler)
  if not (battler and battler.mon and battler.mon.hp > 0) then return end
  local act = Abilities.endOfTurn(battler, Weather.current(self))
  if not act then return end
  local who = displayName(battler)
  local rng = self.rng or love.math.random
  if act.kind == "heal" then
    if battler.mon.hp >= maxHpOf(battler) then return end
    self:sayNext(Strings("%s's\n%s!", who, abilityLabel(act.ability)))
    self:abilityHeal(battler, act.numerator, act.denominator)
    self:sayNext(Strings("%s\nrestored health!", who))
    return
  end
  if act.kind == "shedSkin" then
    -- a one-in-three roll, and only then does the ability announce itself
    if rng(1, act.oneIn) ~= 1 then return end
    battler.mon.status = nil
    battler.toxicCounter = nil
    self:syncShownStatus()
    self:sayNext(Strings("%s's\n%s!", who, abilityLabel(act.ability)))
    self:sayNext(Strings("%s's\nstatus returned to\nnormal!", who))
    return
  end
  if act.kind == "statUp" then
    -- SPEED BOOST at +6 changes nothing and says nothing, rather than
    -- printing "Nothing happened!" every turn for the rest of the battle.
    -- Asked BEFORE the change, or the stage it reads is the new one.
    if ((battler.stages or {})[act.stat] or 0) >= 6 then return end
    self:sayNext(Strings("%s's\n%s!", who, abilityLabel(act.ability)))
    for _, m in ipairs(MoveEffects.changeStage(self, battler, act.stat,
                                               act.delta, false)) do
      self:sayNext(m)
    end
  end
end

-- ---------------------------------------------------------------------
-- HELD ITEMS IN THE TURN LOOP
-- ---------------------------------------------------------------------
--
-- Same division of labour as the abilities above: src/battle/HoldItems.lua
-- decides WHAT should happen and this decides what it costs on screen.

-- QUICK CLAW: a percentage roll, taken once per battler per turn.
function BattleState:quickClawWins(battler)
  if not (battler and battler.mon and battler.mon.hp > 0) then return false end
  local chance = HoldItems.quickClawChance(battler)
  if chance <= 0 then return false end
  return (self.rng or love.math.random)(0, 99) < chance
end

-- FOCUS BAND, asked the moment a hit would knock the holder out.  Returns
-- true when the band held and the Pokemon is standing on one HP.
function BattleState:focusBandHolds(battler, incoming)
  if not (battler and battler.mon) then return false end
  -- only a hit that would actually finish it, and only from full-ish health
  -- is NOT a condition: the cartridge lets a band save a Pokemon on 1 HP too
  if battler.mon.hp <= 0 or incoming < battler.mon.hp then return false end
  local chance = HoldItems.focusBandChance(battler)
  if chance <= 0 then return false end
  if (self.rng or love.math.random)(0, 99) >= chance then return false end
  return true
end

-- SHELL BELL, after a move has landed: the attacker takes back a share of
-- what it dealt.
function BattleState:shellBellDrain(attacker, dealt)
  if not (attacker and attacker.mon and attacker.mon.hp > 0) then return end
  if (dealt or 0) <= 0 then return end
  local share = HoldItems.shellBellShare(attacker)
  if not share then return end
  local max = (attacker.mon.stats and attacker.mon.stats.hp) or attacker.mon.hp
  if attacker.mon.hp >= max then return end
  local heal = math.max(1, math.floor(dealt / share))
  local before = attacker.mon.hp
  attacker.mon.hp = math.min(max, before + heal)
  if attacker.mon.hp == before then return end
  self:drainNext(attacker, attacker.mon.hp)
  self:sayNext(Strings("%s restored a\nlittle HP using\nits SHELL BELL!",
                       displayName(attacker)))
end

-- Eat what was held, once the effect has been spent.  A berry leaves the
-- Pokemon for good -- it is not put back in the bag, which is the whole
-- reason a SITRUS BERRY is a one-shot.
local function consumeItem(battler)
  local mon = battler.mon
  battler.lastConsumedItem = mon.item or mon.heldItem
  mon.item, mon.heldItem = nil, nil
end

-- THE ONE PLACE AN ITEM GOES OFF.  `when` is "hit" (a move has just landed
-- on the holder) or "turn" (end of turn); HoldItems.trigger decides which
-- effects answer to which, and this spends the answer.
function BattleState:holdItemTrigger(battler, when)
  if not (battler and battler.mon and battler.mon.hp > 0) then return false end
  local act = HoldItems.trigger(battler, when)
  if not act then return false end
  local who = displayName(battler)
  local def = HoldItems.defOf(battler)
  local label = (def and def.name) or "the item"
  local rng = self.rng or love.math.random

  if act.kind == "heal" then
    local max = (battler.mon.stats and battler.mon.stats.hp) or battler.mon.hp
    battler.mon.hp = math.min(max, battler.mon.hp + act.amount)
    self:drainNext(battler, battler.mon.hp)
    if act.effect == "LEFTOVERS" then
      self:sayNext(Strings("%s restored a little\nHP using its\n%s!",
                           who, label))
    else
      self:sayNext(Strings("%s restored\nhealth using its\n%s!", who, label))
    end
    if act.confuse then
      -- the five flavour berries confuse a Pokemon whose nature dislikes
      -- them, which is derived from the nature's own lowered stat
      battler.confusedTurns = battler.confusedTurns
                              or rng(2, 5)
      self:sayNext(Strings("%s became\nconfused!", who))
    end

  elseif act.kind == "cure" then
    battler.mon.status = nil
    battler.toxicCounter = nil
    if act.status == "ALL" then battler.confusedTurns = nil end
    self:syncShownStatus()
    self:sayNext(Strings("%s's %s\nrestored its status!", who, label))

  elseif act.kind == "cureConfusion" then
    battler.confusedTurns = nil
    self:sayNext(Strings("%s's %s\nsnapped it out of\nconfusion!", who, label))

  elseif act.kind == "cureAttract" then
    battler.infatuated = nil
    self:sayNext(Strings("%s's %s\ncured its infatuation!", who, label))

  elseif act.kind == "restorePP" then
    local moves = battler.curMoves or battler.mon.moves
    local slot = moves and moves[act.slot]
    if not slot then return false end
    local cap = slot.maxPp or slot.pp_max or act.amount
    slot.pp = math.min(cap, (slot.pp or 0) + act.amount)
    self:sayNext(Strings("%s's %s\nrestored %s's PP!", who, label,
                         tostring(slot.id or "its move")))

  elseif act.kind == "restoreStats" then
    for stat, v in pairs(battler.stages or {}) do
      if v < 0 then battler.stages[stat] = 0 end
    end
    self:sayNext(Strings("%s's %s\nrestored its stats!", who, label))

  elseif act.kind == "statUp" then
    local stat = act.stat
    if not stat then
      -- STARF BERRY picks one of the five at random
      local list = HoldItems.RANDOM_STATS
      stat = list[rng(1, #list)]
    end
    self:sayNext(Strings("%s used its\n%s!", who, label))
    for _, m in ipairs(MoveEffects.changeStage(self, battler, stat,
                                               act.delta, false)) do
      self:sayNext(m)
    end

  elseif act.kind == "critUp" then
    battler.critStage = (battler.critStage or 0) + act.delta
    self:sayNext(Strings("%s used its\n%s!", who, label))
    self:sayNext(Strings("%s is getting\npumped!", who))

  else
    return false
  end

  if act.consume then consumeItem(battler) end
  return true
end

function BattleState:endOfTurn()
  -- the same ret: a decided battle never reaches HandlePoisonBurnLeechSeed
  -- or CheckNumAttacksLeft (core.asm:417-421, 456-460), so the residual
  -- sweep and the trapping-counter release are skipped on the turn a
  -- Teleport escape (or a win/loss/capture) settles it (#441).  The
  -- turn_ended hook still fires: mods count turns, not residuals.
  if self.result then
    Runtime.emit("battle.turn_ended", { battle = self, turn = self.turnCount or 0 })
    return
  end
  -- sideToxic mirrors w*ToxicCounter: it advances only while the
  -- battler's badly-poisoned flag (toxicCounter) is set, an item/AI
  -- cure clears the flag but NOT the side counter, and a fresh Toxic
  -- re-seeds it (effects.asm:137-139 zeroes the counter when setting
  -- BADLY_POISONED).  It is never copied back onto a battler: pokered
  -- reads the counter only while the flag is set, and the only code
  -- that sets the flag also zeroes the counter, so a stale value is
  -- unobservable (a switch or cure downgrades Toxic to plain poison).
  self.sideToxic = self.sideToxic or {}
  -- a battler whose opponent was already knocked out by a move this turn
  -- skips its own residual (HandlePoisonBurnLeechSeed is bypassed when the
  -- move faints the target); snapshot before residual so one side's
  -- residual faint can't suppress the other's
  --
  -- WITH FOUR ON THE FIELD THE TWO NAMES ARE NOT THE FIELD.  A Pokemon that
  -- faints in a double battle is lifted off at once and only replaced at the
  -- bottom of this function, so `self.player` or `self.enemy` can be nil here
  -- while the other flank is still standing -- and the two right-hand slots
  -- were taking no residual at all.  Built from whoever is actually there.
  local sweep
  if self:isDouble() then
    sweep = {}
    for _, b in activeBattlers(self) do
      local foes = foesOf(self, b)
      sweep[#sweep + 1] = { b, foes[1], b.isPlayer and "player" or "enemy",
                            foes[1] ~= nil }
    end
  else
    local playerAlive = self.player.mon.hp > 0
    local enemyAlive = self.enemy.mon.hp > 0
    sweep = { { self.player, self.enemy, "player", enemyAlive },
              { self.enemy, self.player, "enemy", playerAlive } }
  end
  for _, pair in ipairs(sweep) do
    local b, opp, side, oppAlive = pair[1], pair[2], pair[3], pair[4]
    if b.mon.hp > 0 and oppAlive then
      local msgs = Status.residual(b, opp, self)
      for _, m in ipairs(msgs) do self:sayNext(prefixEnemy(m, b)) end
      if #msgs > 0 then self:drainNext() end -- poison/burn/seed HP moved
      if b.toxicCounter then
        self.sideToxic[side] = b.toxicCounter
      end
      if b.mon.hp <= 0 then
        self:onFaint(b)
      end
    end
    -- CheckNumAttacksLeft (core.asm:683-697): a trapping counter that
    -- hit 0 this turn releases its bit only now, at the end of the turn
    if b.trappingTurns and b.trappingTurns <= 0 then
      b.trappingTurns = nil
    end
  end
  -- HandleWeather (core.asm:1685), called once per turn from
  -- HandleBetweenTurnEffects: the count ticks down, the "continues" or "ended"
  -- line prints, and a live sandstorm bites both sides for an eighth of max HP
  -- (player first, then enemy -- that order is the serial-connection one, not
  -- a speed check).
  Weather.upkeep(self)
  -- Gen II HandleBetweenTurnEffects reaches held items only after weather and
  -- the associated faint checks.  HeldItems.endTurn keeps Leftovers, PP and
  -- healing-item phases in cartridge order and never revives a residual KO.
  HeldItems.endTurn(self)
  -- ABILITYEFFECT_ENDTURN, after the weather: RAIN DISH heals, SHED SKIN
  -- may shrug the status off, SPEED BOOST raises.  Player then enemy, the
  -- same order the residual sweep above walks.
  -- ...and again for four rather than two, for the same reason
  if self:isDouble() then
    for _, b in activeBattlers(self) do self:abilityEndOfTurn(b) end
  else
    self:abilityEndOfTurn(self.player)
    self:abilityEndOfTurn(self.enemy)
  end
  -- ...and then the held items: LEFTOVERS, every berry, WHITE HERB.  After
  -- the abilities, which is where ItemBattleEffects sits relative to
  -- AbilityBattleEffects in HandleBetweenTurnEffects.
  if self:isDouble() then
    for _, b in activeBattlers(self) do self:holdItemTrigger(b, "turn") end
  else
    self:holdItemTrigger(self.player, "turn")
    self:holdItemTrigger(self.enemy, "turn")
  end
  self:gen3CountersTick()
  self:tickTokens()
  self:roamerFlees()
  -- AND THE EMPTY PLACES ARE FILLED HERE, not when the mon fell.
  --
  -- HandleFaintedMonActions runs at the end of the turn and asks slot by
  -- slot in position order, which is why a double battle can have a Pokemon
  -- faint on the first action and its partner still take the third.  Does
  -- nothing at all in a single battle, where the faint path fills the slot
  -- itself and there is nothing pending.
  self:fillEmptySlots()
  Runtime.emit("battle.turn_ended", { battle = self, turn = self.turnCount or 0 })
end

-- THE COUNTERS HOENN'S NEW MOVES SET, ticked once per turn in the order
-- HandleBetweenTurnEffects walks them.  Each one is a plain countdown; the
-- interesting part is what happens when it runs out.
function BattleState:gen3CountersTick()
  for _, b in activeBattlers(self) do
    if b and b.mon and b.mon.hp > 0 then
      -- YAWN: the sleep lands at the END of the turn AFTER the one it was
      -- used on, which is the whole reason it is worth using at all.
      if b.drowsyTurns then
        b.drowsyTurns = b.drowsyTurns - 1
        if b.drowsyTurns <= 0 then
          b.drowsyTurns = nil
          for _, m in ipairs(StatusRegistry.inflict(self, b, "SLP", {})) do
            self:sayNext(m)
          end
        end
      end
      if b.tauntTurns then
        b.tauntTurns = b.tauntTurns - 1
        if b.tauntTurns <= 0 then
          b.tauntTurns = nil
          self:sayNext(Strings("%s's taunt\nwore off!", displayName(b)))
        end
      end
      if b.encoreTurns then
        b.encoreTurns = b.encoreTurns - 1
        if b.encoreTurns <= 0 then
          b.encoreTurns, b.encoreMove = nil, nil
          self:sayNext(Strings("%s's ENCORE\nended!", displayName(b)))
        end
      end
      if b.safeguardTurns then
        b.safeguardTurns = b.safeguardTurns - 1
        if b.safeguardTurns <= 0 then
          b.safeguardTurns = nil
          self:sayNext(Strings("%s's party is no\nlonger protected!",
                               displayName(b)))
        end
      end
      -- WISH: half of maximum HP, arriving at the end of the turn AFTER the
      -- one it was made on -- which is what makes it a switch-in heal.
      if b.wishTurns then
        b.wishTurns = b.wishTurns - 1
        if b.wishTurns <= 0 then
          local heal = b.wishHeal or math.max(1, math.floor(maxHpOf(b) / 2))
          b.wishTurns, b.wishHeal = nil, nil
          local max = maxHpOf(b)
          if b.mon.hp < max then
            b.mon.hp = math.min(max, b.mon.hp + heal)
            self:drainNext(b, b.mon.hp)
            self:sayNext(Strings("%s's wish\ncame true!", displayName(b)))
          end
        end
      end
      -- INGRAIN: a sixteenth back every turn for as long as it stands there
      if b.ingrained and b.mon.hp < maxHpOf(b) then
        b.mon.hp = math.min(maxHpOf(b),
                            b.mon.hp + math.max(1, math.floor(maxHpOf(b) / 16)))
        self:drainNext(b, b.mon.hp)
        self:sayNext(Strings("%s absorbed\nnutrients with its\nroots!",
                             displayName(b)))
      end
      -- UPROAR: three turns of noise, and nobody sleeps through it
      if b.uproarTurns then
        b.uproarTurns = b.uproarTurns - 1
        if b.uproarTurns <= 0 then
          b.uproarTurns = nil
          self:sayNext(Strings("%s calmed down.", displayName(b)))
        else
          self:sayNext(Strings("%s is making\nan UPROAR!", displayName(b)))
        end
      end
    end
  end
  -- FUTURE SIGHT and DOOM DESIRE, whose damage was rolled two turns ago and
  -- lands on whoever is standing there now.
  for index, side in ipairs(self.sides or {}) do
    local pending = side.futureSight
    if pending then
      pending.turns = pending.turns - 1
      if pending.turns <= 0 then
        side.futureSight = nil
        local victim = (index == 1) and self.player or self.enemy
        if victim and victim.mon and victim.mon.hp > 0 then
          self:sayNext(Strings("%s took the\n%s attack!", displayName(victim),
                               pending.move or "FUTURE SIGHT"))
          self:applyDamage(victim, pending.damage)
          self:drainNext()
          if victim.mon.hp <= 0 then self:onFaint(victim) end
        end
      end
    end
  end
  -- PERISH SONG last, and both sides together: the counter reaching zero
  -- faints the Pokemon whatever its HP is.
  for _, b in activeBattlers(self) do
    if b and b.perishTurns and b.mon and b.mon.hp > 0 then
      b.perishTurns = b.perishTurns - 1
      if b.perishTurns <= 0 then
        b.perishTurns = nil
        self:sayNext(Strings("%s's PERISH count\nfell to 0!", displayName(b)))
        b.mon.hp = 0
        self:drainNext(b, 0)
        self:onFaint(b)
      else
        self:sayNext(Strings("%s's PERISH count\nfell to %d!",
                             displayName(b), b.perishTurns))
      end
    end
  end
end

-- side/field tokens ({ id, turns?, onResidual?, onExpire? }) tick after
-- the residual sweep; with the tables empty this is a nil check per list
local function tickTokenList(battle, tokens, holder)
  if tokens[1] == nil then return end
  for i = #tokens, 1, -1 do
    local token = tokens[i]
    if token.turns then token.turns = token.turns - 1 end
    if token.onResidual then token.onResidual(battle, holder) end
    if token.turns and token.turns <= 0 then
      if token.onExpire then token.onExpire(battle, holder) end
      table.remove(tokens, i)
    end
  end
end

function BattleState:tickTokens()
  for _, side in ipairs(self.sides) do
    tickTokenList(self, side.tokens, side)
  end
  tickTokenList(self, self.field.tokens, self.field)
end

-- ---------------------------------------------------------------------
-- battle animation layer
-- ---------------------------------------------------------------------
--
-- An approximation of the original's subanimation bytecode engine
-- (docs/known-differences.md): the move's real sound (data/moves/sfx.asm
-- via each move's anim table), screen shake / flash for moves whose
-- animation data uses SE_SHAKE_SCREEN / screen-flash effects, target
-- blink on damage, and a faint slide with the cry.  The Poké Ball toss
-- chain (toss/poof/hide/shake/show) rides the queue as anim rows.

-- the OPTIONS animation toggle (sounds always play)
function BattleState:animationsOn()
  local o = self.game.save.options
  return not o or o.animations ~= false
end

-- Drop the announcement-time move-anim row.  Gen 1 queues PlayMoveAnimation
-- only after MoveHitTest / the effect lands (HandleIfPlayerMoveMissed skips
-- it on a miss unless EXPLODE_EFFECT); we insert early for blink attachment
-- and peel it back on miss/fail paths.
-- Dig/Fly charge leaves the user pic hidden (SLIDE_DOWN / TELEPORT); the
-- second-turn DIG/FLY anim restores it via SE_SLIDE_MON_UP / SE_SHOW_MON_PIC.
-- Cancelling that row on miss/immune would otherwise leave the digger
-- invisible until another anim's resetPicFx (#100).
function BattleState:cancelMoveAnim()
  local row = self.moveAnimRow
  if not row then return end
  self.moveAnimRow = nil
  if row.anim == "DIG" or row.anim == "FLY" then
    local user = row.attackerIsPlayer and self.player or self.enemy
    local pf = user and self.picFx and self.picFx[user]
    if pf then pf.hidden = nil end
  end
  for i, item in ipairs(self.queue) do
    if item == row then
      table.remove(self.queue, i)
      if self.nextInsert and i <= self.nextInsert then
        self.nextInsert = self.nextInsert - 1
      end
      return
    end
  end
end

-- ------------------------------------------------------------------
-- special-effect (SE_*) implementations.  Palette effects are BGP
-- shade maps ({[i] = shade color index i displays as}); on the SGB the
-- colorizer colors the REMAPPED shade, so the zone palettes are
-- permuted through the active map (engine/battle/animations.asm
-- SetAnimationBGPalette / AnimationFlashScreen / ...ScreenLong).
-- ------------------------------------------------------------------

local BGP_IDENTITY = { [0] = 0, 1, 2, 3 }              -- $e4
local BGP_INVERT   = { [0] = 3, 2, 1, 0 }              -- $1b (flash phase 1)
local BGP_WHITE    = { [0] = 0, 0, 0, 0 }              -- $00 (flash phase 2)
local BGP_DARK     = { [0] = 3, 3, 2, 1 }              -- $6f DarkScreenPalette
local BGP_LIGHT    = { [0] = 0, 0, 1, 2 }              -- $90 LightScreenPalette
local BGP_DARKEN   = { [0] = 0, 1, 3, 3 }              -- $f4 DarkenMonPalette (SGB)

-- FlashScreenLongSGB (animations.asm:1010): 12 BGP values per cycle,
-- 3 cycles; the first cycle holds each for 2 frames, the rest for 1
-- (FlashScreenLongDelay)
local FLASH_LONG_MAPS = {
  { [0] = 0, 2, 3, 3 }, { [0] = 0, 3, 3, 3 }, { [0] = 3, 3, 3, 3 },
  { [0] = 0, 3, 3, 3 }, { [0] = 0, 2, 3, 3 }, { [0] = 0, 1, 2, 3 },
  { [0] = 0, 0, 1, 2 }, { [0] = 0, 0, 0, 1 }, { [0] = 0, 0, 0, 0 },
  { [0] = 0, 0, 0, 1 }, { [0] = 0, 0, 1, 2 }, { [0] = 0, 1, 2, 3 },
}

-- the shade map in force this frame (a running flash wins over the
-- persistent palette)
function BattleState:activeBgp()
  local fx = self.fx
  if not fx then return nil end
  local seq = fx.bgpSeq
  if seq then
    local st = seq.steps[seq.idx]
    if st then return st.map end
  end
  return fx.bgp
end

-- per-battler pic effect state (offsets/hides driven by the SE rows)
function BattleState:picFxFor(battler)
  if not battler then return nil end
  self.picFx = self.picFx or {}
  local pf = self.picFx[battler]
  if not pf then
    pf = { ox = 0, oy = 0 }
    self.picFx[battler] = pf
  end
  return pf
end

-- transient pic effects reset when a new animation row starts (each
-- PlayAnimation redraws from a clean slate); `minimized` survives --
-- the minimize sprite replaces the pic DATA until reload. Dig/Fly's
-- charge hide is a cleared tilemap that must survive until SE_SHOW_* /
-- SE_SLIDE_MON_UP (or cancelMoveAnim on a missed Dig/Fly release):
-- clearing it here made Dig pop in before emerge and wrap/bounce (#100).
-- Other hides (Acid Armor, etc.) still clear so the next anim restores.
function BattleState:resetPicFx()
  if not self.picFx then return end
  local digFlyUser = self:hiddenPicKeeper()
  for battler, pf in pairs(self.picFx) do
    pf.kind, pf.t = nil, nil
    pf.endHidden = nil
    pf.ox, pf.oy = 0, 0
    local keepHide = battler.invulnerable or battler == digFlyUser
    if not keepHide then
      pf.hidden = nil
    end
  end
end

-- Which battlers are allowed to stay hidden past the end of an animation:
-- the Dig/Fly user mid-charge, and anything already flagged invulnerable.
function BattleState:hiddenPicKeeper()
  local digFly = self.animName == "DIG" or self.animName == "FLY"
  if not digFly then return nil end
  return self.animAttackerIsPlayer and self.player or self.enemy
end

function BattleState:restoreHiddenPics()
  if not self.picFx then return end
  local keeper = self:hiddenPicKeeper()
  for battler, pf in pairs(self.picFx) do
    if pf.hidden and not (battler.invulnerable or battler == keeper) then
      pf.hidden = nil
    end
  end
end

-- the battler an SE row's routine acts on: "the mon" is the attacker's
-- side; the SE_*_ENEMY_* variants run through CallWithTurnFlipped.
-- A Gen 2 anim_bgeffect names its own side instead (BGEffect_CheckBattleTurn
-- resolves BG_EFFECT_STRUCT_BATTLE_TURN against hBattleTurn), and that wins:
-- ANIM_THROW_POKE_BALL aims its RETURN_MON at the target, so routing it to
-- the attacker drew the player's own mon into the ball and left the wild one
-- standing there for the whole capture.
function BattleState:animFxBattler(flipped)
  local isPlayer = self.animAttackerIsPlayer
  local side = self.animFxSide
  if side then
    if side == "target" then isPlayer = not isPlayer end
  elseif flipped then
    isPlayer = not isPlayer
  end
  return isPlayer and self.player or self.enemy
end

-- a row's sound byte is a move id: GetMoveSound plays its
-- MoveSoundTable sfx with the pitch/tempo modifier bytes; for the
-- GROWL/ROAR animations (IsCryMove) it plays the attacker's cry, with
-- the move's own pitch/tempo bytes (from its own row, soundMove ==
-- self.animName for these) layered on as the extra shift
function BattleState:playAnimSound(soundMove)
  local Sound = require("src.core.Sound")
  local mdef = self.data.moves[soundMove]
  if self.animName == "GROWL" or self.animName == "ROAR" then
    local attacker = self:animFxBattler(false)
    if attacker then
      Sound.playMoveCry(self.data, attacker.mon.species,
                         mdef and mdef.anim and mdef.anim.tempo)
    end
    return
  end
  if mdef and mdef.anim then
    if Sound.playMove then
      Sound.playMove(self.data, mdef.anim)
    else
      Sound.play(self.data, mdef.anim.sound)
    end
  end
end

-- Gen 1's pic routines end on a cleared tilemap and let the caller redraw
-- (AnimationShakeBackAndForth's last act is ClearMonPicFromTileMap), so the
-- kinds below finish hidden.  Gen 2's counterparts are LY-override
-- deformations whose last state is BattleAnim_ResetLCDStatCustom -- the pic
-- never left the screen -- so a Gen 2 row finishes shown.  Ending them
-- hidden left a Tail Whip user invisible until the next animation's
-- resetPicFx put it back.
local function startPicKind(self, pf, kind)
  if not pf then return end
  pf.kind, pf.t = kind, 0
  pf.hidden = nil
  pf.endHidden = (not self.animFxGen2) or nil
end

-- PredefShakeScreenHorizontally (engine/gfx/screen_effects.asm): the window
-- jumps right by b for 5 frames then home for 4, b counting down to 1.
-- b = 8 for SE_SHAKE_SCREEN and the heavy applying-attack shake, b = 2 for
-- the light one.
local function fastShakeProg(b)
  local prog = {}
  for i = b, 1, -1 do
    prog[#prog + 1] = { dx = i, frames = 5 }
    prog[#prog + 1] = { dx = 0, frames = 4 }
  end
  return prog
end

-- AnimationShakeScreenHorizontallySlow (engine/battle/animations.asm:526):
-- rWX creeps 1px right every 2 frames b times, then back down to 0, c times
-- over.  Silent -- this is the non-damaging move's feedback.
local function slowShakeProg(b, c)
  local prog = {}
  for _ = 1, c do
    for i = 1, b do prog[#prog + 1] = { dx = i, frames = 2 } end
    for i = b - 1, 0, -1 do prog[#prog + 1] = { dx = i, frames = 2 } end
  end
  return prog
end

-- Route one AnimPlayer event into the fx layer.  Frame counts and
-- amplitudes are the routines' own (engine/battle/animations.asm;
-- shakes: engine/gfx/screen_effects.asm).
function BattleState:applyAnimEffect(ev)
  self.fx = self.fx or {}
  local fx = self.fx
  if ev.sound then
    self:playAnimSound(ev.sound)
  end
  -- anim_cry from Gen2AnimPlayer: the attacker's cry, with the move's own
  -- tempo shift layered on where the data carries one (GetMoveSound).
  if ev.cry then
    local attacker = self:animFxBattler(false)
    if attacker then
      local mdef = self.data.moves[self.animName]
      require("src.core.Sound").playMoveCry(self.data, attacker.mon.species,
        mdef and mdef.anim and mdef.anim.tempo)
    end
  end
  local e = ev.effect
  if not e then return end
  -- a Gen 2 bgeffect carries the side it was queued with; the SE handlers
  -- below read it back through animFxBattler / startPicKind
  self.animFxSide, self.animFxGen2 = ev.side, ev.gen2

  if e == "SFX_TINK" then
    -- each ball shake opens with a tink (DoBallShakeSpecialEffects)
    require("src.core.Sound").play(self.data, "Tink")

  -- ---------------------------------------------- palette effects
  elseif e == "SE_DARK_SCREEN_PALETTE" then
    fx.bgp = BGP_DARK
  elseif e == "SE_LIGHT_SCREEN_PALETTE" then
    fx.bgp = BGP_LIGHT
  elseif e == "SE_DARKEN_MON_PALETTE" then
    fx.bgp = BGP_DARKEN
  elseif e == "SE_RESET_SCREEN_PALETTE" then
    fx.bgp = nil
  elseif e == "SE_DARK_SCREEN_FLASH" then
    -- AnimationFlashScreen: 2 frames inverted, 2 frames white, restore
    fx.bgpSeq = { steps = { { map = BGP_INVERT, frames = 2 },
                            { map = BGP_WHITE, frames = 2 } },
                  idx = 1, left = 2 }
  elseif e == "SE_FLASH_SCREEN_LONG" then
    local steps = {}
    for cycle = 1, 3 do
      for _, m in ipairs(FLASH_LONG_MAPS) do
        steps[#steps + 1] = { map = m, frames = (cycle == 1) and 2 or 1 }
      end
    end
    fx.bgpSeq = { steps = steps, idx = 1, left = steps[1].frames }

  -- ---------------------------------------------- screen shakes
  elseif e == "SE_SHAKE_SCREEN" then
    fx.shakeProg = fastShakeProg(8)
  elseif e == "SE_ROCK_SLIDE_SHAKE" then
    -- DoRockSlideSpecialEffects: 1px horizontal then vertical rumble
    fx.shakeProg = { { dx = 1, frames = 5 }, { dx = 0, frames = 4 },
                     { dy = 1, frames = 3 }, { dy = 0, frames = 3 } }
  elseif e == "SE_SHAKE_ENEMY_HUD" then
    -- AnimationShakeEnemyHUD: SCX +-2 for 2 frames each, 8 times; the
    -- window + a sprite copy of the back pic keep everything below the
    -- enemy HUD still, so only the HUD area moves
    local prog = {}
    for _ = 1, 8 do
      prog[#prog + 1] = { dx = 2, frames = 2 }
      prog[#prog + 1] = { dx = -2, frames = 2 }
    end
    fx.hudShakeProg = prog
  elseif e == "SE_WAVY_SCREEN" then
    -- AnimationWavyScreen: 255 frames of per-scanline SCX offsets
    -- walking WavyScreenLineOffsets
    fx.wavy = { left = 255, phase = 0 }

  -- ---------------------------------------------- mon pic effects
  elseif e == "SE_SLIDE_MON_OFF" then
    startPicKind(self, self:picFxFor(self:animFxBattler(false)), "slideOff")
  elseif e == "SE_SLIDE_ENEMY_MON_OFF" then
    startPicKind(self, self:picFxFor(self:animFxBattler(true)), "slideOff")
  elseif e == "SE_SLIDE_MON_HALF_OFF" then
    startPicKind(self, self:picFxFor(self:animFxBattler(false)), "slideHalf")
  elseif e == "SE_SLIDE_MON_UP" then
    startPicKind(self, self:picFxFor(self:animFxBattler(false)), "slideUp")
  elseif e == "SE_SLIDE_MON_DOWN" then
    startPicKind(self, self:picFxFor(self:animFxBattler(false)), "slideDown")
  elseif e == "SE_SLIDE_MON_DOWN_AND_HIDE" then
    startPicKind(self, self:picFxFor(self:animFxBattler(false)), "slideDownHide")
  elseif e == "SE_SHAKE_BACK_AND_FORTH" then
    startPicKind(self, self:picFxFor(self:animFxBattler(false)), "shakeBF")
  elseif e == "SE_BOUNCE_UP_AND_DOWN" then
    startPicKind(self, self:picFxFor(self:animFxBattler(false)), "bounce")
  elseif e == "SE_SQUISH_MON_PIC" then
    startPicKind(self, self:picFxFor(self:animFxBattler(false)), "squish")
  elseif e == "SE_BLINK_MON" then
    startPicKind(self, self:picFxFor(self:animFxBattler(false)), "blink")
  elseif e == "SE_BLINK_ENEMY_MON" then
    startPicKind(self, self:picFxFor(self:animFxBattler(true)), "blink")
  elseif e == "SE_MOVE_MON_HORIZONTALLY" then
    -- redraw one tile inward: player pic at hlcoord 2,5 (from 1,5),
    -- enemy pic at 11,0 (from 12,0)
    local b = self:animFxBattler(false)
    local pf = self:picFxFor(b)
    if pf then
      pf.kind, pf.hidden = nil, nil
      pf.ox = b.isPlayer and 8 or -8
      pf.oy = 0
      -- Gen 2's BattleBGEffect_Tackle is a two-state jumptable --
      -- Tackle_MoveForward then Tackle_ReturnMove -- so the lunge walks
      -- back to the mon's own slot instead of parking there until the
      -- next animation reset it.
      if self.animFxGen2 then pf.kind, pf.t = "lunge", 0 end
    end
  elseif e == "SE_RESET_MON_POSITION" then
    local pf = self:picFxFor(self:animFxBattler(false))
    if pf then
      pf.kind, pf.hidden, pf.ox, pf.oy = nil, nil, 0, 0
    end
  elseif e == "SE_SHOW_MON_PIC" then
    local pf = self:picFxFor(self:animFxBattler(false))
    if pf then pf.kind, pf.hidden, pf.ox, pf.oy = nil, nil, 0, 0 end
  elseif e == "SE_SHOW_ENEMY_MON_PIC" then
    local pf = self:picFxFor(self:animFxBattler(true))
    if pf then pf.kind, pf.hidden, pf.ox, pf.oy = nil, nil, 0, 0 end
  elseif e == "SE_HIDE_MON_PIC" or e == "SE_HIDE_ATTACKER_PIC" then
    local pf = self:picFxFor(self:animFxBattler(false))
    if pf then pf.kind, pf.hidden = nil, true end
  elseif e == "SE_HIDE_ENEMY_MON_PIC" then
    local pf = self:picFxFor(self:animFxBattler(true))
    if pf then pf.kind, pf.hidden = nil, true end
  elseif e == "SE_MINIMIZE_MON" then
    -- the pic data is replaced by the tiny MinimizedMonSprite blob
    local pf = self:picFxFor(self:animFxBattler(false))
    if pf then
      pf.kind, pf.hidden = nil, nil
      pf.minimized = true
    end
  elseif e == "SE_FLASH_MON_PIC" or e == "SE_FLASH_ENEMY_MON_PIC" then
    -- ChangeMonPic reloads the mon's own pic (clears a minimize)
    local pf = self:picFxFor(self:animFxBattler(e == "SE_FLASH_ENEMY_MON_PIC"))
    if pf then pf.kind, pf.hidden, pf.minimized = nil, nil, nil end
  elseif e == "SE_TRANSFORM_MON" then
    -- AnimationTransformMon redraws the user as the opposing species
    -- (MoveEffects.TRANSFORM_EFFECT swaps the rest when it applies)
    local user = self:animFxBattler(false)
    local target = self:animFxBattler(true)
    if user and target and self.speciesSprite then
      user.sprite = self:speciesSprite(target.mon.species, user.isPlayer)
                    or user.sprite
      -- the shown species moves with the shown pic, so a model swaps too
      user.species = target.mon.species
      -- a Transformed mon wears the copied species' pic, animation included
      -- (still gray: speciesSprite forces PAL_GRAYMON, and the frames go
      -- through the same palette because battlerPic reuses the pic's meta)
      user.picAnim = (not user.isPlayer)
        and require("src.pokemon.PicAnim").new(self.data, target.mon.species)
        or nil
      local pf = self:picFxFor(user)
      if pf then pf.minimized = nil end
    end
  end
  -- SE_SUBSTITUTE_MON needs no visual here: the doll is drawn while
  -- battler.substituteHP is set (MoveEffects raises it with the move)
  self.animFxSide, self.animFxGen2 = nil, nil
end

-- The post-animation applying-attack feedback (PlayApplyingAttackAnimation
-- -> AnimationTypePointerTable, engine/battle/animations.asm:475-524).
-- hit.animType is wAnimationType, 1..6:
--   1 enemy damaging, no added effect   ShakeScreenVertically (b=8)
--   2 enemy damaging, added effect      fast horizontal shake, b=8
--   3 enemy non-damaging                slow horizontal shake, b=6, c=2
--   4 player damaging, no added effect  BlinkEnemyMonSprite
--   5 player damaging, added effect     fast horizontal shake, b=2
--   6 player non-damaging               slow horizontal shake, b=3, c=2
-- Types 3 and 6 are silent; the rest open with PlayApplyingAttackSound,
-- which is the damage sound hit.sfx already carries.  Only 1 and 4 were
-- implemented, so every move with an added effect blinked (or shook
-- vertically) instead of shaking sideways and every status move showed
-- nothing at all -- Bubblebeam, Confusion, Hypnosis (#354).  A hold keeps
-- the queue still until the effect finishes.
function BattleState:applyHitFx(hit)
  self.fx = self.fx or {}
  -- rows queued before animType existed carry only the blink target
  local t = hit.animType
  if not t and hit.blink then t = hit.blink.isPlayer and 1 or 4 end
  if hit.sfx then
    require("src.core.Sound").play(self.data, hit.sfx)
  end
  if not t or not self:animationsOn() then return end
  if t == 1 then
    -- PredefShakeScreenVertically b=8: the window drops by b for 3 frames
    -- then home for 3, b counting down
    local prog = {}
    for b = 8, 1, -1 do
      prog[#prog + 1] = { dy = b, frames = 3 }
      prog[#prog + 1] = { dy = 0, frames = 3 }
    end
    self.fx.shakeProg = prog
    self.waitFrames = Timing.SHAKE_VERTICAL -- the predef blocks until it settles
  elseif t == 2 then
    self.fx.shakeProg = fastShakeProg(8)
    self.waitFrames = Timing.SHAKE_HORIZ_HEAVY
  elseif t == 3 then
    self.fx.shakeProg = slowShakeProg(6, 2)
    self.waitFrames = Timing.SHAKE_HORIZ_SLOW
  elseif t == 4 then
    if hit.blink then
      -- AnimationBlinkMon: 6 iterations of hide/5 frames/show/5 frames.
      -- This is the animation for every plain damaging move the player
      -- uses, and it ran at a third of its length.
      self.fx.blink = { target = hit.blink, frames = Timing.BLINK_MON }
      self.waitFrames = Timing.BLINK_MON
    end
  elseif t == 5 then
    self.fx.shakeProg = fastShakeProg(2)
    self.waitFrames = Timing.SHAKE_HORIZ_LIGHT
  elseif t == 6 then
    self.fx.shakeProg = slowShakeProg(3, 2)
    self.waitFrames = Timing.SHAKE_HORIZ_SLOW2
  end
end

-- Primary status effects whose pokered handler ends in
-- PlayCurrentMoveAnimation2 (engine/battle/effects.asm:1448), which sets
-- wAnimationType 6 on the player's turn and 3 on the enemy's: sleep,
-- poison, confuse, disable and the primary stat-down effects.  Every other
-- primary effect goes through PlayCurrentMoveAnimation and leaves the type
-- at 0 (no applying animation): paralysis (FreezeBurnParalyzeEffect),
-- leech seed, the stat-UP effects, Splash.  Side-effect stat drops are
-- skipped too -- UpdateLoweredStatDone bails out for them because the
-- damaging move's own type 2/5 shake already played.
local SLOW_SHAKE_EFFECTS = {
  SLEEP_EFFECT = true, POISON_EFFECT = true, CONFUSION_EFFECT = true,
  DISABLE_EFFECT = true,
  ATTACK_DOWN1_EFFECT = true, DEFENSE_DOWN1_EFFECT = true,
  DEFENSE_DOWN2_EFFECT = true, SPEED_DOWN1_EFFECT = true,
  ACCURACY_DOWN1_EFFECT = true,
}

-- AnimateSendingOutMon (core.asm:6801-6838): the mon grows out of the
-- ball -- a 3-frame ball beat, 4 frames of the pic at 3/7 scale (a 3x3
-- block of its 7x7 tiles), 5 frames at 5/7 (5x5), then full size.
-- Queues a hold so the text stays up while it grows.  Runs inside a
-- queued fn (updateQueue resets nextInsert before each one).
function BattleState:startGrowIn(battler)
  -- ...and on Hoenn the ball is thrown instead; see gen3SendOut.  This is the
  -- one place every send-out in the file goes through, which is why the
  -- switch lives here rather than at each of the seven callers.
  if self:gen3SendOut(battler) then return end
  -- ...and if it did NOT take over -- an older cache, or a ball already in
  -- the air -- the trainer does not stay standing there waiting to throw one.
  if self.showPlayerBack and battler == self.player then
    self.showPlayerBack = false
    self:slidePic("back")
  end
  self.growIn = { battler = battler, frame = 0 }
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = 12 })
end

-- Should the low-health alarm sound this frame?  pokered keys it off
-- the drawn bar color: DrawPlayerHUDAndHPBar (core.asm:1846-1875) sets
-- wLowHealthAlarm bit 7 when GetHealthBarColor says the player bar is
-- red (< 10 of 48 pixels -- the same threshold HudTiles.drawHPBar
-- tints with) and clears it when the bar isn't red or the mon fainted
-- (RemoveFaintedPlayerMon).  Winning disables it for the rest of the
-- battle (EndLowHealthAlarm sets wLowHealthAlarmDisabled, mirrored by
-- playVictoryMusic) and every other outcome tears it down in
-- end_of_battle.asm -- self.result covers those.  The damage drain
-- gates the START (the HUD redraw runs after UpdateHPBar finishes) but
-- never the stop, and healing out of the red silences it at once
-- (item_effects.asm:991-994 clears the alarm before the bar animates).
-- No alarm before the player HUD first draws (send-out), nor in the
-- safari/old-man battles, which have no player mon HUD.
function BattleState:lowHealthAlarmActive()
  local p = self.player
  if not p or self.safari or self.demo or self.result
     or self.lowHealthAlarmDisabled then return false end
  if self.showPlayerBack or (self.introSlide or 0) > 0 then return false end
  if p.fainted then return false end
  -- A siren that is ALREADY sounding follows the drawn bar, not the
  -- model: wLowHealthAlarm is a latch DrawPlayerHUDAndHPBar only revisits
  -- once UpdateHPBar2 has finished animating (core.asm:4727-4729 /
  -- core.asm:4845-4847 both drain first, then jp DrawHUDsAndHPBars), and
  -- a KO clears it in RemoveFaintedPlayerMon (core.asm:1011-1016), i.e.
  -- after the bar has drained empty.  applyDamage takes the HP off the
  -- model while the turn is still being queued, so keying a running alarm
  -- off mon.hp cut it dead for the whole "used X!" line + move animation
  -- + drain window (#293).  max() keeps a heal out of the red silencing
  -- it on the spot, the way item_effects.asm does.
  local hp = p.mon.hp
  if self.lowHealthAlarmOn then
    hp = math.max(hp, shownHP(p))
  elseif p.shownHP and p.shownHP > hp then
    return false -- drain running: the HUD redraw has not happened yet
  end
  if hp <= 0 then return false end
  local px = math.max(1, math.floor(hp * 48 / math.max(1, p.mon.stats.hp)))
  return px < 10
end

-- advance a {dx/dy, frames} step program; returns the current step
local function stepProgram(prog)
  local head = prog[1]
  while head and head.frames <= 0 do
    table.remove(prog, 1)
    head = prog[1]
  end
  if head then head.frames = head.frames - 1 end
  return head
end

-- Trainer-pic slides.  SlideTrainerPicOffScreen (core.asm:1235) walks a
-- trainer pic off its own screen edge one tile every 2 frames (9 tiles left
-- for the player back pic, 8 tiles right for the foe), and
-- _ScrollTrainerPicAfterBattle (engine/battle/scroll_draw_trainer_pic.asm)
-- brings the beaten foe back in from the right one column every 4 frames.
-- picOff holds the live programs by slot -- "foe" = the enemy trainer pic,
-- "back" = the player's back pic -- as a screen-pixel x offset stepped
-- toward `to`; updateFx advances them, drawPicsLayer adds them, and the
-- queue rows that start them park a { wait } of the matching length.  Call
-- with no target to clear a slot (#317, #282).
function BattleState:slidePic(slot, from, to, step)
  self.picOff = self.picOff or {}
  if to == nil then
    self.picOff[slot] = nil
    return
  end
  self.picOff[slot] = { x = from or 0, to = to, step = step or 4 }
end

-- the live x offset for a pic slot, 0 when nothing is sliding
function BattleState:picOffset(slot)
  local p = self.picOff and self.picOff[slot]
  return p and p.x or 0
end

function BattleState:updateFx()
  if self.introSlide and self.introSlide > 0 then
    self.introSlide = self.introSlide - 1
  end
  -- step each live trainer-pic slide toward its target; a landed program
  -- holds its offset (the after-battle scroll-in rests two tiles right of
  -- the battle slot) until its owner clears the slot
  if self.picOff then
    for _, p in pairs(self.picOff) do
      if p.x < p.to then
        p.x = math.min(p.to, p.x + p.step)
      elseif p.x > p.to then
        p.x = math.max(p.to, p.x - p.step)
      end
    end
  end
  local fx = self.fx
  if fx then
    if fx.shake and fx.shake > 0 then fx.shake = fx.shake - 1 end
    if fx.flash and fx.flash > 0 then fx.flash = fx.flash - 1 end
    if fx.blink and fx.blink.frames > 0 then
      fx.blink.frames = fx.blink.frames - 1
    end
    if fx.faint and fx.faint.frames > 0 then
      fx.faint.frames = fx.faint.frames - 1
    end
    -- SE-driven screen offsets (window/SCX shakes)
    fx.shakeX, fx.shakeY = 0, 0
    if fx.shakeProg then
      local st = stepProgram(fx.shakeProg)
      if st then
        fx.shakeX, fx.shakeY = st.dx or 0, st.dy or 0
      else
        fx.shakeProg = nil
      end
    end
    fx.hudShakeX = 0
    if fx.hudShakeProg then
      local st = stepProgram(fx.hudShakeProg)
      if st then
        fx.hudShakeX = st.dx or 0
      else
        fx.hudShakeProg = nil
      end
    end
    -- BGP flash sequences
    local seq = fx.bgpSeq
    if seq then
      seq.left = seq.left - 1
      if seq.left <= 0 then
        seq.idx = seq.idx + 1
        local st = seq.steps[seq.idx]
        if st then
          seq.left = st.frames
        else
          fx.bgpSeq = nil -- restore: activeBgp falls back to fx.bgp
        end
      end
    end
    if fx.wavy then
      fx.wavy.left = fx.wavy.left - 1
      fx.wavy.phase = fx.wavy.phase + 1
      if fx.wavy.left <= 0 then fx.wavy = nil end
    end
  end
  -- SE-driven pic effects: advance the per-battler programs and apply
  -- their end states (timings in the SE_* handlers' comments)
  if self.picFx then
    for b, pf in pairs(self.picFx) do
      if pf.kind then
        pf.t = (pf.t or 0) + 1
        local k, t = pf.kind, pf.t
        if k == "slideOff" and t >= 24 then
          pf.kind, pf.hidden = nil, pf.endHidden
        elseif k == "slideHalf" and t >= 19 then
          pf.kind = nil
          pf.ox = b.isPlayer and -32 or 32 -- the pic stays half off
        elseif k == "slideUp" and t >= 14 then
          pf.kind = nil -- a full cyclic wrap lands back on the pic
        elseif k == "slideDown" and t >= 21 then
          pf.kind, pf.hidden = nil, pf.endHidden
        elseif k == "slideDownHide" and t >= 19 then
          pf.kind, pf.hidden = nil, pf.endHidden
        elseif k == "shakeBF" and t >= 96 then
          pf.kind, pf.hidden = nil, pf.endHidden -- Gen 1's loop ends cleared
        elseif k == "bounce" and t >= 105 then
          pf.kind = nil -- AnimationShowMonPic after the last bounce
        elseif k == "squish" and t >= 24 then
          pf.kind, pf.hidden = nil, pf.endHidden
        elseif k == "blink" and t >= 60 then
          pf.kind = nil -- ends shown
        elseif k == "lunge" and t >= 16 then
          pf.kind, pf.ox = nil, 0 -- Tackle_ReturnMove lands back on 0
        end
      end
    end
  end
  -- The Silph Scope unveil (MarowakAnim; queueScopeReveal parks a wait row
  -- of GHOST_REVEAL_FRAMES over it): the ghost flashes, fades out, the pic
  -- and the nick swap back the way LoadEnemyMonData restores them, and the
  -- real mon fades in (#492).
  local gr = self.ghostReveal
  if gr and self.enemy then
    gr.t = gr.t + 1
    local pf = self:picFxFor(self.enemy)
    local flashEnd = BattleState.GHOST_FLASH_FRAMES
    local outEnd = flashEnd + BattleState.GHOST_FADE_OUT_FRAMES
    if gr.t <= flashEnd then
      pf.fade = (math.floor((gr.t - 1) / 10) % 2 == 1) and 0.5 or 1
    elseif gr.t <= outEnd then
      pf.fade = 1 - math.ceil((gr.t - flashEnd) / 10) / 3
    else
      if not gr.swapped then
        gr.swapped = true
        local real = self.ghostReal
        if real then
          self.enemy.name = real.name or self.enemy.name
          self.enemy.sprite = real.sprite or self.enemy.sprite
          self.enemy.species = real.species or self.enemy.species
          self.enemy.picAnim = real.picAnim
        end
      end
      pf.fade = math.min(1, math.ceil((gr.t - outEnd) / 10) / 4)
    end
    if gr.t >= BattleState.GHOST_REVEAL_FRAMES then
      self.ghostReveal, self.scopeReveal, pf.fade = nil, nil, nil
    end
  end
  -- the send-out grow-in (AnimateSendingOutMon): 3+4+5 frames, then
  -- the pic draws at full size again
  if self.growIn then
    self.growIn.frame = self.growIn.frame + 1
    if self.growIn.frame >= 12 then self.growIn = nil end
  end
  -- low-HP alarm (audio/low_health_alarm.asm): the two-tone siren
  -- loops while the player's bar is red; see lowHealthAlarmActive
  local Sound = require("src.core.Sound")
  -- self.lowHealthAlarmOn mirrors wLowHealthAlarm's bit 7: a latch read
  -- back inside lowHealthAlarmActive (the RHS sees last frame's value)
  -- so a sounding siren rides out the next hit's HP drain instead of
  -- dropping out mid-announcement (#293)
  self.lowHealthAlarmOn = self:lowHealthAlarmActive()
  -- battle.low_health_alarm: on/off toggle for the siren loop, ctx.on
  -- mirrors self.lowHealthAlarmOn. Vanilla just starts/stops the loop
  -- each frame; a mod can wrap this to reshape the toggle (e.g. force
  -- ctx.on false after some budget) before letting vanilla act on it.
  if Runtime.wantsHook("battle.low_health_alarm") then
    Runtime.call("battle.low_health_alarm", function(ctx)
      if ctx.on then
        Sound.startLoop(ctx.battle.data, "Low_Health_Alarm")
      else
        Sound.stopLoop("Low_Health_Alarm")
      end
    end, { on = self.lowHealthAlarmOn, battle = self })
  else
    if self.lowHealthAlarmOn then
      Sound.startLoop(self.data, "Low_Health_Alarm")
    else
      Sound.stopLoop("Low_Health_Alarm")
    end
  end
end

-- ---------------------------------------------------------------------
-- move execution pipeline
-- ---------------------------------------------------------------------

-- Mirror DrawHUDsAndHPBars: reveal mon.status on the HUD only after the
-- current action's queued anim/text have played (PoisonEffect sets the
-- bit before PlayCurrentMoveAnimation2 + PrintText, but the HUD redraw
-- waits until after Execute*Move returns).
function BattleState:syncShownStatus()
  for _, b in activeBattlers(self) do
    if b then b.shownStatus = b.mon.status end
  end
end

function BattleState:executeAction(user, target, action)
  -- MainInBattleLoop reads wEscapedFromBattle right after Execute*Move and
  -- rets (core.asm:417-421, 456-460): a Teleport/Roar/Whirlwind escape ends
  -- the turn where it lands and the second mover never moves.  self.result
  -- is only ever set once the battle is over (run/win/lose/caught), and the
  -- faint cases are already covered by the HP guard below (#441)
  if self.result then return end
  if not (user and user.mon) then return end
  if user.mon.hp <= 0 then return end
  if not action then return end
  -- A SWITCH NEEDS NO TARGET.  Everything else does, and with four on the
  -- field the one it was aimed at can already be off it -- the entry's
  -- target is resolved as the entry runs, and there may be nobody left to
  -- resolve it to.
  local isSwitch = action.special == "playerSwitch"
                   or action.special == "aiSwitch"
  if not isSwitch and not (target and target.mon and target.mon.hp > 0) then
    return
  end

  local function run()
    -- ghost battles: the ghost never attacks; its whole turn is the
    -- GetOutText (ExecuteEnemyMove -> PrintGhostText, core.asm:5462-5463)
    if self.ghost and not user.isPlayer then
      self:sayNext(self.data.text._GetOutText or Strings("GHOST: Get out...\nGet out..."))
      return
    end

    -- refresh the held-in-place mirror before the status checks (see
    -- lockedAction): the victim is held exactly while the opponent's
    -- trapping bit is set -- including a counter sitting at 0 until the
    -- end-of-turn CheckNumAttacksLeft clear
    user.boundTurns = target and target.trappingTurns
                      and math.max(1, target.trappingTurns) or nil

    -- trainer class AI actions (engine/battle/trainer_ai.asm)
    if action.special == "aiItem" then
      self.aiUses = (self.aiUses or 1) - 1
      for _, m in ipairs(TrainerAI.useItem(self, action.item)) do
        self:sayNext(prefixEnemy(m, self.enemy))
      end
      self:drainNext()
      require("src.core.Sound").play(self.data, "Heal_Ailment")
      return
    end
    if action.special == "aiSwitch" then
      self.aiUses = (self.aiUses or 1) - 1
      local previous = self.enemy
      local oldName = self.enemy.name
      self.enemyIndex = action.index
      self.enemy = makeBattler(self.data, self.enemyParty[action.index], false)
      -- EnemySendOutFirstMon (core.asm:1314-1315): clears player's trap
      clearTrapping(self.player)
      self:syncSides()
      Runtime.emit("battle.battler_switched", {
        battle = self, side = self.sides[2], battler = self.enemy,
        previous = previous,
      })
      self:abilitySwitchOut(previous)
      self.aiUses = self:aiUsesFor()
      markSeen(self.game, self.enemy.mon.species)
      -- _AIBattleWithdrawText: "X with-/drew Y!"
      self:sayNext(Strings("%s with-\ndrew %s!", self:trainerLabel_(), oldName))
      self:sayNext(Strings("%s sent\nout %s!", self:trainerLabel_(),
                           self.enemy.name))
      HeldItems.onEntry(self, self.enemy)
      self:actNext(function() self:abilitySwitchIn(self.enemy) end)
      return
    end

    -- THE PLAYER'S OWN SWITCH, in a double battle where it is one of four
    -- actions rather than the whole turn.  A single battle never reaches
    -- here: resolveSwitch does the send-out itself and gives the foe its
    -- free move, which is the cartridge's single-battle flow.
    if action.special == "playerSwitch" then
      if action.mon and action.mon.hp and action.mon.hp > 0 then
        self:switchPlayerInto(user.position or BattleState.POS.PLAYER_LEFT,
                              action.mon)
      end
      return
    end

    -- special locked actions.  All of them still run the status gauntlet:
    -- CheckPlayerStatusConditions (core.asm:3328-3583) evaluates sleep ->
    -- freeze -> held-in-place -> flinch -> recharge -> disable tick ->
    -- confusion -> paralysis BEFORE the bide/thrash/trapping handling.
    if action.special == "recharge" then
      -- only reaching .HyperBeamCheck consumes the flag (core.asm:3384-
      -- 3392): sleep/freeze/held/flinch keep the mon recharging next turn
      if self:preRechargeChecks(user, target) then return end
      user.mustRecharge = nil
      self:sayNext(self:romText("_MustRechargeText", "%s\nmust recharge!", displayName(user)))
      return
    end
    if action.special == "bound" then
      if not target.trappingTurns then
        -- the trap ended earlier this turn: the CANNOT_MOVE selection is
        -- simply lost (ExecutePlayerMove returns immediately on $ff)
        return
      end
      -- sleep/freeze take precedence over the held-in-place message
      if self:statusInterrupt(user, target) then return end
      return
    end
    if action.special == "trapping" then
      if self:statusInterrupt(user, target) then return end
      self:continueTrapping(user, target)
      return
    end
    if action.special == "bide" then
      if self:statusInterrupt(user, target) then return end
      self:continueBide(user, target)
      return
    end

    if self:statusInterrupt(user, target) then return end
    -- ONE MOVE, POSSIBLY SEVERAL TARGETS.
    --
    -- The cartridge prints "X used SURF!" once and then resolves the move
    -- against each battler in turn (MOVEEND_NEXT_TARGET).  Which battlers
    -- those are is the move's own `target` byte, which the extractor has
    -- always read and nothing consulted: SURF and its twenty-one siblings
    -- hit both foes, and EARTHQUAKE and its four hit both foes AND your own
    -- partner.
    --
    -- In a single battle -- and for every move on the two cartridges before
    -- this one, whose records carry no target byte at all -- resolve answers
    -- exactly the one target that was passed in, and this is the single call
    -- it has always been.
    local list = { target }
    if self:isDouble() then
      local def = self:moveDef(action)
      if def then
        local chosen = (self.chosenTargets or {})[user.position] or target
        local got = Targeting.resolve(self, user, def, chosen)
        if #got > 0 then list = got end
      end
    end
    for i, one in ipairs(list) do
      if one and one.mon and (one.mon.hp or 0) > 0 then
        -- only the first announces; the rest are the same move landing again
        self:performMove(user, one, action, i > 1)
      end
    end
  end
  run()
  -- after announce/anim/effect text (pokered DrawHUDsAndHPBars)
  self:actNext(function() self:syncShownStatus() end)
end

-- Sleep / confusion onomatopoeia from Check*StatusConditions
-- (core.asm): side-specific SLP_*/CONF_* anims, not the Rest/Amnesia
-- move rows.  Player sleep plays the anim before FastAsleepText;
-- enemy sleep and both confusion sides print the text first.
function BattleState:statusOnomatopoeia(user, kind)
  local isPlayer = user.isPlayer
  local anim
  if kind == "sleep" then
    anim = isPlayer and "SLP_PLAYER_ANIM" or "SLP_ANIM"
  else
    anim = isPlayer and "CONF_PLAYER_ANIM" or "CONF_ANIM"
  end
  local text = kind == "sleep"
    and self:romText("_FastAsleepText", "%s\nis fast asleep!", displayName(user))
    or self:romText("_IsConfusedText", "%s\nis confused!", displayName(user))
  if kind == "sleep" and isPlayer then
    self:animNext(anim, isPlayer)
    self:sayNext(text)
  else
    self:sayNext(text)
    self:animNext(anim, isPlayer)
  end
end

-- Queue status text (+ sleep/confusion FX when the line matches).
-- Wake / snap-out / flinch / etc. stay text-only.
function BattleState:sayStatusMsg(user, msg)
  local text = prefixEnemy(msg, user)
  if msg:find("is fast asleep!", 1, true) then
    self:statusOnomatopoeia(user, "sleep")
  elseif msg:find("is confused!", 1, true) then
    self:statusOnomatopoeia(user, "confused")
  else
    self:sayNext(text)
  end
end

-- The pre-recharge slice of CheckPlayerStatusConditions (core.asm:
-- 3328-3382): sleep -> freeze -> held-in-place -> flinch, each losing
-- the turn WITHOUT consuming the recharge flag.  The disable/confusion/
-- paralysis ticks come after the recharge consume in the asm, so they
-- must not run on a recharge turn.  Mirrors Status.beforeMove's early
-- checks (kept there for normal moves).
function BattleState:preRechargeChecks(user, target)
  if user.skipMove then -- Haze forfeit (selected move = CANNOT_MOVE)
    user.skipMove = nil
    return true
  end
  local mon = user.mon
  if mon.status == "SLP" then
    -- EARLY BIRD sleeps HALF as long.  The cartridge does not roll a shorter
    -- count -- it decrements the counter TWICE -- which is the same thing
    -- except that a one-turn sleep still costs the turn it is spent on.
    user.sleepTurns = (user.sleepTurns or 1) - Abilities.sleepStep(user)
    if user.sleepTurns <= 0 then
      mon.status = nil
      self:sayNext(self:romText("_WokeUpText", "%s\nwoke up!", displayName(user)))
    else
      self:statusOnomatopoeia(user, "sleep")
    end
    return true
  end
  if mon.status == "FRZ" then
    -- ...and in Hoenn it thaws one turn in five, here as in the ordinary
    -- gauntlet: this is the same check Status.FRZ makes, spelled again
    -- because this shorter path does not go through the records
    local oneIn = Status.rule(self, "freezeThawOneIn")
    if oneIn and self.rng(1, oneIn) == 1 then
      mon.status = nil
      self:sayNext(Strings("%s\nwas defrosted!", displayName(user)))
      return false
    end
    self:sayNext(self:romText("_IsFrozenText", "%s\nis frozen solid!", displayName(user)))
    return true
  end
  if target.trappingTurns then
    self:sayNext(self:romText("_CantMoveText", "%s\ncan't move!", displayName(user)))
    return true
  end
  if user.flinched then
    -- reachable: the turn-start flinch reset is skipped while the
    -- player recharges, so the flinch eats the recharge turn and the
    -- flag survives (the Hyper Beam flinch glitch)
    user.flinched = false
    self:sayNext(self:romText("_FlinchedText", "%s\nflinched!", displayName(user)))
    return true
  end
  return false
end

-- Runs Status.beforeMove plus the shared interruption bookkeeping;
-- returns true when the user's action is interrupted.
function BattleState:statusInterrupt(user, target)
  -- TRUANT, before the conditions.  SLAKING and SLAKOTH move every OTHER
  -- turn: the cartridge sets a flag after a move and reads it before the
  -- next one, which is why this is a toggle rather than "every second turn
  -- of the battle".  The flag is the BATTLER's, so switching out clears it,
  -- exactly as it does on hardware.
  if Abilities.loafs(user) then
    if user.truantLoafing then
      user.truantLoafing = nil
      self:sayNext(Strings("%s is\nloafing around!", displayName(user)))
      return true
    end
    user.truantLoafing = true
  end
  local canMove, msgs, selfHit = Status.beforeMove(user, self.rng, self)
  for _, m in ipairs(msgs) do self:sayStatusMsg(user, m) end
  if selfHit then
    -- confusion self-hit (core.asm:3428-3434): clears everything in
    -- status1 except CONFUSED, then HandleSelfConfusionDamage deals a
    -- 40-power typeless hit against the mon's own defense -- with the
    -- OPPONENT's Reflect still applying (the screen check keeps
    -- reading the opponent's battle status)
    local dmg = self:computeDamage(user, user,
                                   { id = "CONFUSED", power = 40, type = "NORMAL", accuracy = 100 },
                                   { rng = self.rng, forceCrit = false, typeless = true,
                                     screens = target })
    self:sayNext(self:romText("_HurtItselfText", "It hurt itself in\nits confusion!"))
    self:clearVolatiles(user, true)
    self:applyDamage(user, dmg)
    if user.mon.hp <= 0 then self:onFaint(user) end
    return true
  end
  if not canMove then
    -- full paralysis (core.asm:3459-3464) clears bide/thrash/charge/
    -- trapping; sleep, freeze, flinch and held-in-place leave every
    -- volatile in place (a sleeping wrapper keeps its victim held)
    if user.mon.status == "PAR" and msgs[#msgs]
       and msgs[#msgs]:find("fully paralyzed", 1, true) then
      self:clearVolatiles(user, false)
    end
    return true
  end
  -- UPROAR wakes everybody and keeps them awake: a Pokemon cannot be asleep
  -- while one is going on, on either side.
  if (self.player and self.player.uproarTurns)
     or (self.enemy and self.enemy.uproarTurns) then
    if user.mon.status == "SLP" then
      user.mon.status = nil
      self:sayNext(Strings("%s woke up in\nthe UPROAR!", displayName(user)))
    end
  end
  -- INFATUATION, after the older statuses and before the move: half the
  -- time an ATTRACTed Pokemon simply does not attack.  The line prints
  -- either way, which is what makes it visible that it is in love at all.
  if user.infatuated and user.infatuated.mon
     and user.infatuated.mon.hp > 0 then
    self:sayNext(Strings("%s is in love\nwith %s!", displayName(user),
                         displayName(user.infatuated)))
    if self.rng(0, 1) == 0 then
      self:sayNext(Strings("%s is\nimmobilized by love!", displayName(user)))
      return true
    end
  end
  return false
end

-- The status1 volatile clears shared by full paralysis and the
-- confusion self-hit.  selfHit additionally clears INVULNERABLE and
-- FLINCHED (status1 &= CONFUSED); full paralysis does NOT touch
-- INVULNERABLE -- the famous Fly/Dig invulnerability glitch.
function BattleState:clearVolatiles(user, selfHit)
  user.bideTurns, user.bideDamage = nil, nil
  user.thrashTurns, user.thrashMove, user.thrashAnnounced = nil, nil, nil
  user.charging, user.chargeReady = nil, nil
  user.trappingTurns = nil -- the opponent is freed via the live mirror
  if selfHit then
    user.invulnerable = nil
    user.flinched = false
  end
end

-- performMove runs a move (possibly via Metronome/Mirror Move recursion).
-- Decomposed into a staged pipeline over the merged move_effects record:
-- announcement -> callsMove -> charge -> perform -> primary run -> the
-- damaging pipeline (EffectRegistry.runDamaging).

-- Gen 1 status/stat primary effects call PlayCurrentMoveAnimation only
-- after they land; these failure texts print with no animation.
local function primaryEffectFailed(msgs)
  if not msgs or #msgs == 0 then return true end
  local m = msgs[1]
  if m == "But, it failed!" or m == "Nothing happened!" then return true end
  if m:find("didn't affect", 1, true) then return true end
  if m:find("is unaffected", 1, true) then return true end
  if m:find("protected by MIST", 1, true) then return true end
  if m:find("Already", 1, true) then return true end
  -- BattleCommand_TimeBasedHealContinue's .Full branch calls AnimateFailedMove
  -- before HPIsFullText, so Morning Sun / Synthesis / Moonlight at full HP show
  -- no animation either
  if m:find("HP is full", 1, true) then return true end
  return false
end

function BattleState:performMove(user, target, moveInst, isCalled)
  local move = self:moveDef(moveInst)
  if not move then
    Logger.warn("unknown move instance %s", tostring(moveInst.id))
    return
  end
  -- who is swinging, for GRUDGE and DESTINY BOND to read back if this
  -- knocks someone out (see killerOf)
  self.lastAttacker = user
  local record = self:effectRecord(move.effect)

  -- charge release?
  local releasing = user.charging == moveInst and user.chargeReady
  if releasing then
    user.charging, user.chargeReady, user.invulnerable = nil, nil, nil
    user.hiddenAs = nil
  end

  -- PP: not for continuations, struggle, called moves, or (under
  -- gen1_faithful) wild/trainer enemies -- pokered DecrementPP only ever
  -- mutates wBattleMonPP / party PP (engine/battle/decrement_pp.asm).
  -- That rule doesn't apply in a link battle: "the enemy" there is a real
  -- human peer independently tracking their own PP the normal way, not an
  -- AI Gen 1 never bothered to decrement -- applying it made each side
  -- silently skip decrementing the OTHER side's PP for the move it just
  -- used, so both simulations' party state diverged by exactly 1 PP on
  -- the very first move either side made, failing the lockstep hash
  -- check turn 1 of literally every link battle.
  local isContinuation = releasing
      or (user.thrashTurns and user.thrashTurns > 0 and moveInst == user.thrashMove)
      or moveInst == user.rageMove
  local enemyUnlimited = not user.isPlayer and self.kind ~= "link"
      and self.ruleset and self.ruleset.enemyUnlimitedPP
  if not isContinuation and not moveInst.struggle and not isCalled
      and not enemyUnlimited then
    -- PRESSURE costs the ATTACKER an extra point for every move aimed at its
    -- holder.  Two per use, not double the total -- which is why it is
    -- subtracted here rather than multiplying the cost.
    local cost = 1 + Abilities.extraPP(target)
    moveInst.pp = math.max(0, moveInst.pp - cost)
  end

  self.moveAnimRow = nil
  if not (user.thrashTurns and moveInst == user.thrashMove and user.thrashAnnounced) then
    self:sayNext(self:romText("_ItemUseText001", "%s\nused %s!", displayName(user), move.name))
    -- the move's animation plays right after the announcement; the
    -- damage path attaches the target's hit blink to this row so the
    -- blink follows the animation (pokered's order).  Mimic is the
    -- exception (announceAnim = false): PlayCurrentMoveAnimation runs
    -- only after a successful copy, never on a miss -- applyMimic queues it
    if not (record and record.announceAnim == false) then
      self.nextInsert = (self.nextInsert or 0) + 1
      self.moveAnimRow = { anim = move.id, attackerIsPlayer = user.isPlayer }
      table.insert(self.queue, self.nextInsert, self.moveAnimRow)
    end
  end
  Runtime.emit("battle.move_used", {
    battle = self, user = user, target = target, move = move,
    isCalled = isCalled or false,
  })

  -- PROTECT stops a status move too, and it is the only check that has to
  -- happen before the effect record is consulted at all.
  if target.protecting and move.power == 0 and move.protectAffected ~= false
     and record and record.kind == "primary" then
    self:cancelMoveAnim()
    self:sayNext(Strings("%s\nprotected itself!", displayName(target)))
    return
  end

  local ctx = EffectRegistry.makeCtx(self, user, target, move, moveInst, isCalled)

  -- Metronome / Mirror Move re-entry; a nil pick means the record
  -- already said its failure text
  if record and record.callsMove then
    local pick = record.callsMove(ctx)
    -- Mirror Move never plays its own anim (MetronomePickMove does;
    -- MirrorMoveCopyMove only reloads the copied move or prints fail)
    if move.id == "MIRROR_MOVE" or not pick then
      self:cancelMoveAnim()
    end
    if pick then
      self:performMove(user, target, { id = pick, pp = 1 }, true)
    end
    return
  end
  -- A DIFFERENT MOVE ENDS THE RUN.  PROTECT and ENDURE halve their odds for
  -- each consecutive use and reset the moment the user does anything else;
  -- FURY CUTTER and ROLLOUT double for each consecutive LANDING and reset
  -- the same way.  Both counters live on the user and are cleared here,
  -- which is the one place every move passes through.
  if move.id ~= "PROTECT" and move.id ~= "DETECT" and move.id ~= "ENDURE" then
    user.protectRun = nil
  end
  if user.rampMove and user.rampMove ~= move.id then
    user.rampRun, user.rampMove = nil, nil
  end
  user.lastMove = move.id

  -- charge moves: first turn just charges; the text comes from the move
  -- record (chargeText) and the invulnerability from semiInvulnerable,
  -- falling back to the id tables (Fly AND Dig go semi-invulnerable:
  -- ChargeEffect sets INVULNERABLE for both)
  -- BattleCommand_SkipSunCharge (effect_commands.asm:6535): Solar Beam jumps
  -- straight past `charge` while the sun is up and fires on the turn it was
  -- selected.  Every other charge move ignores the weather.
  if record and record.charge and not releasing
     and not Weather.skipsCharge(self, record) then
    self:cancelMoveAnim()
    user.charging = moveInst
    user.chargeReady = true
    local invulnerable = move.semiInvulnerable
    if invulnerable == nil then
      invulnerable = record.charge.invulnerable or move.id == "DIG"
    end
    if invulnerable then
      user.invulnerable = true
      -- WHERE it went, which is what GUST and EARTHQUAKE need to know: a
      -- Pokemon in the air is reachable by one and a Pokemon underground by
      -- the other, each for double damage.
      user.hiddenAs = (move.id == "DIG") and "underground" or "air"
    end
    local chargeAnim = record.charge.anim
    if move.id == "DIG" then
      chargeAnim = "SLIDE_DOWN_ANIM"
    elseif record.charge.enemyAnim and not user.isPlayer then
      chargeAnim = record.charge.enemyAnim
    end
    if chargeAnim then
      self:animNext(chargeAnim, user.isPlayer)
    end
    local chargeText = move.chargeText or CHARGE_TEXT[move.id]
                       or Strings.source("%s\nis charging up!")
    -- the template is a source string (a move record may supply its own),
    -- so translate it here rather than where it was declared
    self:sayNext(Strings(chargeText, displayName(user)))
    return
  end

  -- fully custom resolution (Bide, Roar/Teleport, Mimic)
  if record and record.perform then
    record.perform(ctx)
    return
  end

  -- pure status moves
  if move.power == 0 and record and record.kind == "primary" and record.run then
    -- accuracy-checked status effects run MoveHitTest, which has no
    -- 100%-accuracy early-out (even Thunder Wave misses on the 255
    -- roll) and misses outright against a mid-Fly/Dig target; the
    -- never-miss paths (X ACCURACY) live inside Damage.accuracyRoll
    if record.accuracyChecked
       and (target.invulnerable
            or not self:accuracyRoll(move, user, target)) then
      -- SleepEffect/PoisonEffect/... call PlayCurrentMoveAnimation only
      -- after the effect lands; a miss skips it
      self:cancelMoveAnim()
      self:sayNext(self:romText("_AttackMissedText", "%s's\nattack missed!", displayName(user)))
      return
    end
    local msgs = record.run(ctx)
    -- SLEEP TALK names a move rather than doing something itself: the record
    -- picks one of the user's OTHER moves and this is where it is used.  The
    -- call is `isCalled`, so it costs no PP and cannot recurse into another
    -- SLEEP TALK.
    if user.callsMoveId then
      local picked = user.callsMoveId
      user.callsMoveId = nil
      for _, m in ipairs(msgs) do self:sayNext(m) end
      self:performMove(user, target, { id = picked, pp = 1 }, true)
      return
    end
    -- Gen 1 status/stat effects animate only when they take effect
    -- (AlreadyAsleep / NothingHappened / ButItFailed print with no anim)
    if primaryEffectFailed(msgs) then
      self:cancelMoveAnim()
    elseif SLOW_SHAKE_EFFECTS[move.effect] and self.moveAnimRow then
      self.moveAnimRow.hit = { animType = user.isPlayer and 6 or 3 }
    end
    for _, m in ipairs(msgs) do
      self:sayNext(m)
    end
    self:drainNext() -- REST/RECOVER/SOFTBOILED move the user's bar
    return
  end
  if move.power == 0 and not (record and record.kind == "full") then
    MoveEffects.warnUnknown(move.effect)
    self:cancelMoveAnim()
    self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
    return
  end

  -- damaging pipeline, driven by the record's stage callbacks
  EffectRegistry.runDamaging(self, ctx, record)
  -- CHARGE is spent by the first Electric move that follows it, landed or
  -- not -- the cartridge clears the flag when the move resolves, not when
  -- it connects.
  if user.charged
     and require("src.battle.Abilities").normalizeType(move.type)
         == "ELECTRIC" then
    user.charged = nil
  end
end

function BattleState:continueTrapping(user, target)
  self:sayNext(self:romText("_AttackContinuesText", "%s's\nattack continues!", displayName(user)))
  -- .MultiturnMoveCheck (core.asm:3554-3566) prints AttackContinuesText
  -- then jumps to GetPlayerAnimationType, so the trapping move's full
  -- animation replays each locked turn (same damage, animation shown).
  -- Mirror performMove's anim row (BattleState.lua ~1307), gated on the
  -- OPTIONS animation toggle.
  if user.trapMove and self:animationsOn() then
    self.nextInsert = (self.nextInsert or 0) + 1
    table.insert(self.queue, self.nextInsert,
                 { anim = user.trapMove, attackerIsPlayer = user.isPlayer })
  end
  -- the counter can sit at 0 until the END of the turn: the trapping
  -- bit is only cleared by CheckNumAttacksLeft (core.asm:439/467)
  -- after BOTH battlers acted, so a slower victim is still held
  -- through the attacker's final hit (endOfTurn nils it)
  user.trappingTurns = user.trappingTurns - 1
  self:applyDamage(target, user.trapDamage or 1)
  if target.mon.hp <= 0 then self:onFaint(target) end
end

function BattleState:continueBide(user, target)
  user.bideTurns = user.bideTurns - 1
  if user.bideTurns > 0 then
    self:sayNext(Strings("%s\nis storing energy!", displayName(user)))
    return
  end
  self:sayNext(self:romText("_UnleashedEnergyText", "%s\nunleashed energy!", displayName(user)))
  local dmg = (user.bideDamage or 0) * 2
  user.bideTurns, user.bideDamage = nil, nil
  if dmg <= 0 then
    self:cancelMoveAnim()
    self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
    return
  end
  -- .UnleashEnergy (core.asm:3501-3529) re-points wPlayerMoveNum at BIDE
  -- and rejoins HandleIfPlayerMoveMissed, so BIDE's own animation plays
  -- here, after UnleashedEnergyText and before the damage (#375)
  self:animNext("BIDE", user.isPlayer)
  self:applyDamage(target, dmg)
  if target.mon.hp <= 0 then self:onFaint(target) end
end

function BattleState:selfDestruct(user)
  user.mon.hp = 0
  self:onFaint(user)
end

-- Applies damage honoring Substitute, Bide storage and Rage; returns the
-- amount that counts as dealt (for recoil/drain).
-- `fromMove` marks damage a MOVE is dealing, which FOCUS BAND is the only
-- caller that cares about: the band saves a Pokemon from an attack and not
-- from a sandstorm, its own recoil or a Substitute's upkeep, and applyDamage
-- is the one door all of those come through.
function BattleState:applyDamage(target, dmg, fromMove)
  if target.substituteHP then
    target.substituteHP = target.substituteHP - dmg
    if target.substituteHP <= 0 then
      target.substituteHP = nil
      self:sayNext(self:romText("_SubstituteBrokeText", "%s's\nSUBSTITUTE broke!", displayName(target)))
    else
      self:sayNext(self:romText("_SubstituteTookDamageText", "The SUBSTITUTE\ntook damage for\n%s!", displayName(target)))
    end
    return dmg
  end
  -- FOCUS BAND, asked before the HP is taken: a one-in-ten hold leaves the
  -- Pokemon standing on a single HP instead of fainting.  Asked here rather
  -- than at the faint check because the cartridge's band changes the DAMAGE,
  -- and everything downstream -- Bide's tally, Rage, the exp award -- reads
  -- what was actually dealt.
  -- ENDURE first: it is a certainty where the band is a roll, so a Pokemon
  -- that used ENDURE this turn never needs the band at all.
  local endured = fromMove == true and target.enduring == true
                  and target.mon.hp > 0 and dmg >= target.mon.hp
  local band = not endured and fromMove == true
               and self:focusBandHolds(target, dmg)
  if endured or band then dmg = math.max(0, target.mon.hp - 1) end
  local dealt = math.min(dmg, target.mon.hp)
  if fromMove and dealt > 0 then target.hurtThisTurn = true end
  target.mon.hp = target.mon.hp - dealt
  if dealt > 0 then self:drainNext(target, target.mon.hp) end -- animate the bar down
  if endured then
    self:sayNext(Strings("%s endured\nthe hit!", displayName(target)))
  elseif band then
    self:sayNext(Strings("%s hung on\nusing its FOCUS BAND!", displayName(target)))
  end
  if target.bideTurns then
    target.bideDamage = (target.bideDamage or 0) + dealt
  end
  if target.rageMove and dealt > 0 then
    target.stages.attack = math.min(6, (target.stages.attack or 0) + 1)
    self:sayNext(self:romText("_BuildingRageText", "%s's\nRAGE is building!", displayName(target)))
  end
  return dealt
end

-- ---------------------------------------------------------------------
-- fainting / exp / party
-- ---------------------------------------------------------------------

-- WHO KNOCKED THIS ONE OUT.
--
-- GRUDGE and DESTINY BOND both need the battler that landed the blow, and
-- in a single battle "the other one" is the same answer, which is how this
-- was written.  With four on the field it is not: the mon that fainted may
-- have been hit by either foe, or by its own partner's EARTHQUAKE.  So the
-- attacker is recorded as the move resolves and read back here, and "the
-- other one" is only the fallback for a faint with no attacker behind it --
-- poison, a hazard, recoil at the end of a turn.
function BattleState:killerOf(battler)
  local by = self.lastAttacker
  if by and by ~= battler and by.mon and self:sideOf(by) ~= self:sideOf(battler)
  then
    return by
  end
  if by and by ~= battler and by.mon then return by end
  local foes = self:foesOf(battler)
  return foes[1]
end

function BattleState:onFaint(battler)
  if battler.faintQueued then return end
  battler.faintQueued = true
  -- GRUDGE: the move that did it loses every PP it had.  Asked before
  -- DESTINY BOND, because a Pokemon carrying both spends both.
  if battler.grudge then
    battler.grudge = nil
    local killer = self:killerOf(battler)
    local lastId = killer and killer.lastMove
    if lastId then
      for _, m in ipairs(killer.curMoves or killer.mon.moves or {}) do
        if m.id == lastId then
          m.pp = 0
          self:sayNext(Strings("%s's %s\nlost all its PP!",
                               displayName(killer), lastId))
          break
        end
      end
    end
  end
  -- DESTINY BOND: whoever knocked it out goes with it.  Asked here, once,
  -- before the faint is queued for anything else.
  if battler.destinyBond then
    battler.destinyBond = nil
    local killer = self:killerOf(battler)
    if killer and killer.mon and killer.mon.hp > 0 then
      self:sayNext(Strings("%s took\n%s with it!", displayName(battler),
                           displayName(killer)))
      killer.mon.hp = 0
      self:drainNext(killer, 0)
      self:onFaint(killer)
    end
  end
  if battler.isPlayer and self.participants then
    self.participants[battler.mon] = nil
  end
  Runtime.emit("battle.fainted", { battle = self, battler = battler })
  if battler.isPlayer then
    -- HandlePlayerMonFainted (core.asm:1070-1085): the companion loses
    -- happiness on its own faint; an enemy 30+ levels above it makes
    -- that the CARELESSTRAINER hit instead
    local enemyLevel = self.enemy and self.enemy.mon
                       and self.enemy.mon.level or 0
    local reason = (enemyLevel - (battler.mon.level or 0)) >= 30
                   and "CARELESSTRAINER" or "FAINTED"
    require("src.world.PikachuFollower")
      .modifyHappiness(self.game.save, reason, battler.mon)
  end
  -- the faint slide + cry ride the queue (after the move animation and
  -- the HP-bar drain, pokered's order); the slide finishes before the
  -- faint text via a queued hold
  self:actNext(function()
    battler.fainted = true
    local Sound = require("src.core.Sound")
    Sound.playCry(self.data, battler.mon.species)
    Sound.play(self.data, "Faint_Fall")
    self.fx = self.fx or {}
    -- SlideDownFaintedMonPic: PIC_HEIGHT (7) slide steps, each closing with
    -- DelayFrames 2 (core.asm:1186-1222).  The port held this one twice as
    -- long as hardware.
    self.fx.faint = { battler = battler, frames = Timing.FAINT_SLIDE }
  end)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = Timing.FAINT_SLIDE })
  if not battler.isPlayer and self.kind == "wild" then
    -- FaintEnemyPokemon .wild_win (core.asm:792-795): beating a wild
    -- mon calls EndLowHealthAlarm and starts MUSIC_DEFEATED_WILD_MON
    -- as the slide lands, BEFORE EnemyMonFaintedText and the exp text;
    -- trainer battles keep the battle theme until TrainerBattleVictory.
    -- (Starting it even when the player mon dropped too matches the
    -- acknowledged core.asm:797-798 bug.)
    self:actNext(function() self:playVictoryMusic() end)
  end
  -- _EnemyMonFaintedText "Enemy X fainted!" / _PlayerMonFaintedText
  self:sayNext(Strings("%s\nfainted!", displayName(battler)))
  -- A FAINT IN A DOUBLE BATTLE ENDS NOTHING.
  --
  -- The two functions below are the SINGLE-battle flow, and they are shaped
  -- like one all the way down: the foe's is "award exp, find the next mon,
  -- offer SHIFT, otherwise you win", the player's is "open the party menu
  -- now or lose".  Neither sentence is true with four on the field -- the
  -- other slot is still fighting, the side is not defeated, and Emerald does
  -- not offer SHIFT in a double at all.
  --
  -- And the cartridge does not replace anybody mid-turn either:
  -- HandleFaintedMonActions runs at the END of the turn and asks slot by
  -- slot in position order.  So the empty place is REMEMBERED here and
  -- filled when the turn is over, and the singles path below is left exactly
  -- as it was.
  -- ...AND IT RUNS BEFORE THE END OF THE TURN, WHICH IS ALREADY QUEUED.
  --
  -- Reported from play: "after i defeat both of the enemies pokemon it doesnt
  -- say they were defeated, and it forces me to attack and defeat my ally
  -- pokemon before it says they were defeated".
  --
  -- The turn is built as a queue -- one entry per action, then `endOfTurn` --
  -- before any of it runs, and a faint happens INSIDE one of those action
  -- entries.  `act` APPENDS, so `doubleFaint` landed after the endOfTurn that
  -- was queued before the turn began: the slot was still occupied when
  -- fillEmptySlots looked, nothing was pending, and the side check was
  -- skipped.  It only ran at the end of the NEXT turn -- and with both foes
  -- gone the only thing left to aim a move at is your own partner, which is
  -- exactly what the report describes.
  --
  -- `actNext` puts it right after the faint it belongs to, which is where the
  -- rest of this sequence already goes (the slide, the hold, the "fainted!"
  -- line are all inserted, not appended).
  if self:isDouble() then
    self:actNext(function() self:doubleFaint(battler) end)
    return
  end
  if battler.isPlayer then
    self:act(function() self:playerMonFainted() end)
  else
    self:act(function() self:enemyMonFainted() end)
  end
end

-- ---------------------------------------------------------------------------
-- FOUR ON THE FIELD, AND ONE OF THEM IS DOWN
-- ---------------------------------------------------------------------------

-- Everything still standing on a side, and everything on its bench that
-- could still come out.
function BattleState:sideCanContinue(isPlayer)
  local side = self.sides[isPlayer and 1 or 2]
  for flank = 1, 2 do
    local b = side.battlers[flank]
    if b and b.mon and (b.mon.hp or 0) > 0 then return true end
  end
  -- BOTH BENCHES, when the far side is two trainers.  benchFor answers per
  -- POSITION, and asked without one it answers the first trainer's team --
  -- so a two-opponent battle called itself over while the second trainer
  -- still had a full party sitting behind them.
  for _, pos in ipairs(isPlayer and { BattleState.POS.PLAYER_LEFT }
                       or { BattleState.POS.OPPONENT_LEFT,
                            BattleState.POS.OPPONENT_RIGHT }) do
    for _, mon in ipairs(self:benchFor(isPlayer, pos)) do
      if (mon.hp or 0) > 0 and not Party.isEgg(mon) then return true end
    end
  end
  return false
end

-- The party a side draws replacements from.  A two-opponent battle has two
-- benches on the far side, one per trainer, and each slot draws from its own
-- -- which is the difference between two trainers and one trainer's twins.
function BattleState:benchFor(isPlayer, position)
  if isPlayer then return self.game.save.party or {} end
  if position == BattleState.POS.OPPONENT_RIGHT and self.enemyPartyB then
    return self.enemyPartyB
  end
  return self.enemyParty or {}
end

function BattleState:doubleFaint(battler)
  -- the exp is owed whichever slot fell, and only for a foe
  if not battler.isPlayer then
    self:awardExp(battler)
    -- ...AND THE LEVEL THE PRIZE IS COUNTED FROM.  The last foe to fall is
    -- lifted off the field before the victory sequence runs, so by the time
    -- the prize is worked out there is no `self.enemy` left to read a level
    -- off.  Remembered here, which is the last moment it exists.
    self.lastFoeLevel = battler.mon and battler.mon.level or self.lastFoeLevel
    -- and the exp for this one is already paid; the victory path must not
    -- pay it a second time
    self.expPaidPerSlot = true
  end
  local pos = tonumber(battler.position)
  if pos then
    self.pendingReplacements = self.pendingReplacements or {}
    self.pendingReplacements[#self.pendingReplacements + 1] = pos
  end
  self:placeBattler(pos, nil)
  self:syncSides()
end

-- Called from endOfTurn: fill every empty place, in position order, which is
-- the order HandleFaintedMonActions walks them in.
function BattleState:fillEmptySlots()
  local pending = self.pendingReplacements
  self.pendingReplacements = nil
  if not (pending and #pending > 0) then
    -- NOTHING TO FILL IS NOT NOTHING TO CHECK.
    --
    -- The side test below used to sit behind this early return, so a battle
    -- could reach the end of a turn with a side already wiped out and say
    -- nothing -- which is what happened when the faint arrived after the
    -- endOfTurn that was queued before the turn began.  That ordering is
    -- fixed above; this makes the check unmissable rather than merely
    -- correctly ordered, because ANY future path that empties a slot without
    -- queuing a replacement would reopen the same hole.
    --
    -- Only in a double: a single battle's faint path calls the victory and
    -- defeat sequences itself, and running them from here as well would play
    -- each one twice.
    if self:isDouble() then self:checkSideBeaten() end
    return
  end
  table.sort(pending)
  for _, pos in ipairs(pending) do
    if self:battlerAt(pos) == nil then
      local isPlayer = (pos % 2) == 0
      local bench = self:benchFor(isPlayer, pos)
      local taken = {}
      for p = 0, 3 do
        local b = self:battlerAt(p)
        if b then taken[b.mon] = true end
      end
      local pick
      for _, mon in ipairs(bench) do
        if (mon.hp or 0) > 0 and not Party.isEgg(mon) and not taken[mon] then
          pick = mon
          break
        end
      end
      if pick then
        self:placeBattler(pos, makeBattler(self.data, pick, isPlayer,
                                           isPlayer and self.game.save or nil))
        self:syncSides()
        if not isPlayer then markSeen(self.game, pick.species) end
        local who = self:battlerAt(pos)
        self:sayNext(Strings("%s sent\nout %s!",
                             isPlayer and (self.game.save.player.name or "")
                                       or self:trainerLabel_(),
                             who.name))
        self:actNext(function() self:abilitySwitchIn(who) end)
      end
    end
  end
  -- ...and only once nobody can be sent out at all is the side beaten
  self:checkSideBeaten()
end

-- IS EITHER SIDE OUT OF POKEMON?  Latched, because the victory and defeat
-- sequences are queued rather than immediate: a second end-of-turn arriving
-- before the first one has played would queue the whole thing again.
function BattleState:checkSideBeaten()
  if self.sideBeaten then return end
  if not self:sideCanContinue(false) then
    self.sideBeaten = "enemy"
    self:act(function() self:enemyMonFainted() end)
  elseif not self:sideCanContinue(true) then
    self.sideBeaten = "player"
    self:act(function() self:playerMonFainted() end)
  end
end

-- Exp for the defeated enemy, shared by the faint path (enemyMonFainted)
-- and, when a mod's battle.catch_exp hook says so, the catch path
-- (storeCaughtMon).
-- WHICH FOE PAID.  A single battle has one and every caller left it out;
-- a double battle has two and the one that fell is not always `self.enemy`
-- -- and after IT fell there is no `self.enemy` to read at all, which is
-- what the exp lookups below used to walk into.
function BattleState:awardExp(fallen)
  local foe = fallen or self.enemy
  if not (foe and foe.mon) then return end
  -- exp is split among the mons that fought this enemy
  -- (engine/battle/experience.asm); traded mons earn x1.5; each
  -- participant gets the full stat exp
  -- a mon that fainted mid-fight has had its gain-exp flag cleared
  -- (RemoveFaintedPlayerMon), so it drops out of the divisor and only
  -- the surviving participants are counted and paid
  local participants, alive = 0, {}
  for _, mon in ipairs(self.game.save.party) do
    if self.participants and self.participants[mon] then
      participants = participants + 1
      if mon.hp > 0 then table.insert(alive, mon) end
    end
  end
  if participants == 0 and self.player and self.player.mon
     and self.player.mon.hp > 0 then
    participants, alive = 1, { self.player.mon }
  end
  local HudTiles = require("src.render.HudTiles")
  local function applyShare(mon, split, announce)
    -- how full the bar is before any of this is applied; AnimateExpBar starts
    -- from here and creeps to the new length
    local expBefore = self.player and mon == self.player.mon
      and HudTiles.expBarPixels(self.data, mon) or nil
    local levels, gained = Experience.apply(self.data, mon, foe.def,
                                            foe.mon.level, self.kind == "trainer",
                                            split, mon.traded)
    -- Track level-ups for EvolveAfterBattle (OverworldState:afterBattle ->
    -- Evolution.checkParty).  B-cancel leaves the mon at/above threshold;
    -- without this gate it re-triggers after every later fight (#213).
    if #levels > 0 then
      self.leveledUp = self.leveledUp or {}
      self.leveledUp[mon] = true
    end
    Runtime.emit("battle.exp_gained", {
      battle = self, mon = mon, gained = gained, levels = levels,
    })
    local name = mon.nickname or self.data.pokemon[mon.species].name
    if announce then
      -- GainedText (experience.asm:342-354): "X gained" plus one of
      -- _WithExpAllText / _BoostedText / _ExpPointsText; the EXP.ALL
      -- pass beats the traded boost (wBoostExpByExpAll checks first),
      -- and _ExpPointsText prints wExpAmountGained -- the raw share,
      -- captured before the max-level cap (experience.asm:92-100).
      -- _BoostedText / _WithExpAllText end in the CONT code (\v, "...\011"
      -- in data/generated/text.lua): the box waits for A/B + ▼ then scrolls
      -- the amount line in, so it stays on-screen instead of at y=144 (#216).
      local text = Strings.source("%s gained\n%d EXP. Points!")
      if announce == "expAll" then
        text = Strings.source("%s gained\nwith EXP.ALL,\v%d EXP. Points!")
      elseif mon.traded then
        text = Strings.source("%s gained\na boosted\v%d EXP. Points!")
      end
      self:sayNext(Strings(text, name, gained))
    end
    -- AnimateExpBar runs after the gained-EXP box and before the first
    -- GrewLevelText, so a level-up is the bar reaching the end and wrapping.
    if expBefore and expBefore ~= HudTiles.expBarPixels(self.data, mon) then
      self:expBarNext(expBefore)
    end
    -- per level: GrewLevelText -> the stats window (PrintStatsBox) ->
    -- the move-learn checks (experience.asm:245-256)
    local game = self.game
    for _, lv in ipairs(levels) do
      -- experience.asm:248 fires per grew-level text
      require("src.world.PikachuFollower")
        .modifyHappiness(game.save, "LEVELUP", mon)
      -- Gen2's own per-mon happiness byte (ChangeHappiness HAPPINESS_GAINLEVEL),
      -- which is what the HAPPINESS evolutions read.
      require("src.pokemon.Evolution").changeHappiness(mon, "LEVELUP")
      self:sayNext(Strings("%s grew\nto level %d!", name, lv))
      self:uiNext(function()
        require("src.core.Sound").play(game.data, "Level_Up")
        return StatBox.new(game, mon)
      end)
      -- After PrintStatsBox, experience.asm reloads the active battler's
      -- wBattleMon and runs DrawHUDsAndHPBars, so its HP bar reflects the
      -- higher current HP.  Experience.lua:84 already raised mon.hp by
      -- (newMaxHP - oldMaxHP); the party mon and the battler share one table
      -- (makeBattler), so mon.stats.hp (the bar's denominator) jumps to the
      -- new max instantly while the battler's shownHP numerator lags at the
      -- old current HP -- the bar SHRINKS (#224).  Animate shownHP up to the
      -- new current HP (house convention: potions drain the bar too, see
      -- itemUsed) so the bar grows instead.  Only the active player battler
      -- shares its table with the HUD; other party mons (EXP.ALL) have no bar.
      if mon == self.player.mon then self:drainNext() end
      for _, moveId in ipairs(Experience.movesLearnedAt(
          self.data.pokemon[mon.species], lv)) do
        self:learnMove(mon, moveId)
      end
    end
  end
  -- battle.exp_award: the participant/EXP.ALL split, factored out so a
  -- mod can replace it wholesale (e.g. a flat undivided share to every
  -- non-fainted party mon) without re-deriving participants/alive.
  -- ctx.applyShare(mon, split, announce) is the same helper vanilla uses.
  -- GEN 2'S EXP SHARE IS A HELD ITEM, AND IT WAS NEVER IMPLEMENTED.
  --
  -- Gen 1's EXP.ALL is a BAG item, and that is the only exp sharing this
  -- knew about.  Gen 2 replaced it with EXP_SHARE, held by one mon
  -- (engine/battle/experience.asm): the exp is halved, the participants
  -- divide one half, and the HOLDERS divide the other -- paid whether or
  -- not they fought.  With nothing reading `mon.item` here, a benched
  -- Kadabra holding the Exp.Share earned exactly nothing and its
  -- exp-to-next-level never moved.
  --
  -- The id is resolved through ItemEffects.alias rather than compared to a
  -- literal: Gen 2 names every item ITEM_nnn off the cartridge and the
  -- number differs per cart (ITEM_057 on Crystal, ITEM_121 on Polished),
  -- while the extractor stamps Gen 1's canonical `key` alongside -- so
  -- "EXP.SHARE" and "Exp.Share" both normalise to EXP_SHARE.
  local ItemEffects = require("src.inventory.ItemEffects")
  local function holdsExpShare(mon)
    -- `heldItem` is what one script path writes (giveegg); `item` is the
    -- field the bag and every menu use
    local id = mon.item or mon.heldItem
    if not id then return false end
    local items = self.data.items
    return ItemEffects.alias(id, items and items[id]) == "EXP_SHARE"
  end

  local function vanillaExpAward(ctx)
    -- with EXP.ALL, participants split half the exp and the other half
    -- is divided among the whole party (engine/battle/experience.asm)
    local expAll = (self.game.save.inventory.EXP_ALL or 0) > 0
    if not expAll then
      local holders = {}
      for _, mon in ipairs(self.game.save.party) do
        if (mon.hp or 0) > 0 and holdsExpShare(mon) then
          holders[#holders + 1] = mon
        end
      end
      if #holders > 0 then
        -- half to the participants, half to the holders.  A mon that both
        -- fought and holds one is paid from both halves and prints two
        -- boxes, exactly as the EXP.ALL second pass already does -- GSC
        -- prints one box per gaining mon and no summary line.
        for _, mon in ipairs(ctx.alive) do
          ctx.applyShare(mon, math.max(1, ctx.participants) * 2, true)
        end
        for _, mon in ipairs(holders) do
          ctx.applyShare(mon, #holders * 2, true)
        end
        return
      end
    end
    for _, mon in ipairs(ctx.alive) do
      ctx.applyShare(mon, ctx.participants * (expAll and 2 or 1), true)
    end
    if expAll then
      -- the second GainExperience pass sets the gain flags for the WHOLE
      -- party, so DivideExpDataByNumMonsGainingExp divides the already
      -- halved-and-participant-divided exp again by the party count, and
      -- .partyMonLoop still skips fainted mons (core.asm:818-858 +
      -- experience.asm:9-13); each mon gets its own GainedText with the
      -- "with EXP.ALL," tail (wBoostExpByExpAll) -- pokered prints no
      -- summary line
      for _, mon in ipairs(self.game.save.party) do
        if mon.hp > 0 then
          ctx.applyShare(mon, math.max(1, ctx.participants) * #self.game.save.party * 2, "expAll")
        end
      end
    end
  end
  local awardCtx = { battle = self, participants = participants, alive = alive,
                      applyShare = applyShare }
  if Runtime.wantsHook("battle.exp_award") then
    Runtime.call("battle.exp_award", vanillaExpAward, awardCtx)
  else
    vanillaExpAward(awardCtx)
  end
  self.participants = {}
end

function BattleState:enemyMonFainted()
  -- IN A DOUBLE THE EXP IS ALREADY PAID.  Each foe's share is awarded as it
  -- falls (doubleFaint), because by the time the side is beaten there is no
  -- longer a Pokemon on the field to award it for.  Paying again here would
  -- double every double battle's exp.
  if not self.expPaidPerSlot then self:awardExp() end

  if self.kind == "trainer" then
    -- EnemySendOutFirstMon / AnyEnemyPokemonAliveCheck (core.asm): scan
    -- the whole enemy party for the first mon with HP left.  Blindly
    -- doing enemyIndex+1 softlocks after an AI switch (Agatha): a later
    -- slot can already be fainted, so the empty-HP mon comes out, the
    -- FIGHT menu returns, and executeAction no-ops on target.hp <= 0.
    local nextIndex
    for i, mon in ipairs(self.enemyParty) do
      if mon.hp > 0 then
        nextIndex = i
        break
      end
    end
    if nextIndex then
      self.enemyIndex = nextIndex
      -- EnemySendOutFirstMon (core.asm:1366-1443): SHIFT offers a free
      -- switch when party count > 1, the active mon is alive, and the
      -- battle-style bit is clear.  pokered counts party slots (not
      -- remaining HP); SET / single-mon / fainted active skip the prompt.
      local nextMon = self.enemyParty[self.enemyIndex]
      local nextName = nextMon.nickname or self.data.pokemon[nextMon.species].name
      local style = tostring((self.game.save.options or {}).battleStyle or "shift")
        :lower()
      local partyCount = #self.game.save.party
      -- ReplaceFaintedEnemyMon (core.asm:892-896): DrawEnemyPokeballs puts the
      -- foe's party ball row -- and the HUD chrome PlaceEnemyHUDTiles lays
      -- down under it (draw_hud_pokeball_gfx.asm:9-11, 33-45, 134-141) -- into
      -- the block FaintEnemyPokemon just cleared, after the exp text and
      -- BEFORE the next send-out.  It survives EnemySendOutFirstMon's
      -- SlideTrainerPicOffScreen (core.asm:1308-1310, 8 steps x DelayFrames 2)
      -- so SET style gets the brief flash, and stays up through the whole
      -- SHIFT prompt below (#283).
      self:act(function() self.showEnemyBalls = true end)
      table.insert(self.queue, { wait = 16 })
      -- SwitchPlayerMon runs AFTER TrainerSentOutText (core.asm:1436-1443)
      local shiftSwitchMon = nil
      if style ~= "set" and partyCount > 1 and self.player.mon.hp > 0 then
        -- _TrainerAboutToUseText (data/text/text_2.asm): "X is" / "about to
        -- use" then a CONT to the nick, not a fresh box -- the box scrolls
        -- "X is" off so "about to use" stays above the name, instead of the
        -- page ending on a bare nick (#565).  Then para "Will PLAYER" /
        -- "change POKéMON?" with YES/NO.
        self:say(Strings("%s is\nabout to use\v%s!", self:trainerLabel_(), nextName))
        self:sayChoice(
          Strings("Will %s\nchange POKéMON?", self.game.save.player.name),
          function(yes)
            if not yes then return end
            local game = self.game
            Screens.push(game, "PartyMenu", {
              battle = self,
              forceSwitch = true,
              onSwitch = function(mon)
                if mon ~= self.player.mon and mon.hp > 0 then
                  shiftSwitchMon = mon
                end
              end,
            })
          end)
      end
      self:act(function()
        local previous = self.enemy
        self.enemy = makeBattler(self.data, self.enemyParty[self.enemyIndex], false)
        -- EnemySendOutFirstMon (core.asm:1314-1315): clears player's trap
        clearTrapping(self.player)
        self:syncSides()
        Runtime.emit("battle.battler_switched", {
          battle = self, side = self.sides[2], battler = self.enemy,
          previous = previous,
        })
        self:abilitySwitchOut(previous)
        self.aiUses = self:aiUsesFor()
        markSeen(self.game, self.enemy.mon.species)
        -- EnemySendOutFirstMon .next4 (core.asm:1413-1417): ClearSprites and
        -- the 4x11 ClearScreenArea take the ball row away with the rest of
        -- the enemy HUD block, right before TrainerSentOutText (#283)
        self.showEnemyBalls = nil
        self:markParticipant()
        -- EnemySendOutFirstMon (core.asm:1413-1435): the enemy HUD area
        -- clears, TrainerSentOutText prints, THEN the pic appears
        -- (AnimateSendingOutMon) with the cry; no POOF -- that animation
        -- belongs to the player-side SendOutMon (core.asm:1757-1762)
        self.enemySendingOut = true
        self:sayNext(Strings("%s sent\nout %s!", self:trainerLabel_(), self.enemy.name))
        self:actNext(function()
          self.enemySendingOut = false
          self:startGrowIn(self.enemy)
          self:shinyAnim(self.enemy, true)
          self:actNext(function()
            require("src.core.Sound").playCry(self.data, self.enemy.mon.species)
            HeldItems.onEntry(self, self.enemy)
          end)
        end)
        self:actNext(function() self:abilitySwitchIn(self.enemy) end)
      end)
      -- SwitchPlayerMon after the enemy is out (core.asm:1436-1443)
      self:act(function()
        local mon = shiftSwitchMon
        if not mon then return end
        local previous = self.player
        self.player = makeBattler(self.data, mon, true, self.game.save)
        clearTrapping(self.enemy)
        self:syncSides()
        Runtime.emit("battle.battler_switched", {
          battle = self, side = self.sides[1],
          battler = self.player, previous = previous,
        })
        self:abilitySwitchOut(previous)
        -- Taking the SHIFT offer ZEROES wPartyGainExpFlags and
        -- wPartyFoughtCurrentEnemyFlags before jumping to SwitchPlayerMon
        -- (EnemySendOutFirstMon tail, core.asm:1436-1443), and SwitchPlayerMon
        -- then FLAG_SETs only the mon coming in (core.asm:2424-2433).  Without
        -- the reset the mon that was out when the enemy fainted -- marked by
        -- the send-out act above, which mirrors EnemySendOut's own re-flag
        -- (core.asm:1276-1289) -- stayed a participant, so the exp divisor in
        -- enemyMonFainted counted two mons and the switch-in earned half the
        -- next KO (#275).  Voluntary switches (resolveSwitch) and post-faint
        -- replacements (openReplacementMenu) must NOT do this: pokered's
        -- party-menu SwitchPlayerMon keeps the outgoing mon flagged, which is
        -- the deliberate exp-share, and a fainted mon is already dropped by
        -- onFaint mirroring RemoveFaintedPlayerMon (core.asm:1002-1007).
        self.participants = {}
        self:markParticipant()
        self.nextInsert = 0
        self.sendingOut = true
        self:sayNext(self:sendOutText(self.player.name))
        self:animNext("POOF_ANIM", false)
        self:shinyAnim(self.player, false)
        self:actNext(function()
          self.sendingOut = false
          self:startGrowIn(self.player)
          require("src.core.Sound").playCry(self.data, self.player.mon.species)
          HeldItems.onEntry(self, self.player)
        end)
        self:actNext(function() self:abilitySwitchIn(self.player) end)
      end)
      return
    end
    -- ComputeTrainerReward (0E:58D4) sets wBattleReward = the class's base
    -- reward byte (TrainerClassAttributes+2) times wCurPartyLevel, the level
    -- of the LAST mon the party reader loaded.  That is only a QUARTER of the
    -- payout though: WinTrainerBattle (0F:4F46) then runs `ld c, 4` and adds
    -- wBattleReward once per iteration -- b of the four quarters through
    -- .AddMoneyToMom, the remaining c through .AddMoneyToWallet -- so the
    -- trainer is worth base * level * 4 in total.  b comes from
    -- wMomSavingMoney & 7 (0 = you keep it all, 3 = she banks all four), and
    -- is forced to 0 when Mom's account is already maxed.  Nothing here
    -- models Mom's savings account, which is the `keep it all` branch, so all
    -- four quarters land in the wallet -- Falkner pays 25 * 9 * 4 = 900 and a
    -- Sprout Tower sage 8 * 3 * 4 = 96, instead of the 225 and 24 a single
    -- quarter gives.  Gen1's TrainerBattleVictory has no such split, so the
    -- multiplier stays on the Gen2 side of the fence.
    -- THE LEVEL THE PRIZE IS COUNTED FROM.
    --
    -- Gen 1 and Gen 2 count from the mon that was out when the battle ended.
    -- Emerald counts from the trainer's LAST PARTY MEMBER -- which is usually
    -- the same Pokemon and is not always: a trainer whose last mon never got
    -- sent out still pays for it.  The multiplier itself is already folded
    -- into baseMoney by the import (four times the class's own), so the
    -- generation shows up here only as which level to use.
    -- THE FIELD CAN BE EMPTY BY NOW.
    --
    -- Reported from play, as a crash: "after defeating them both ... then
    -- crashes -- BattleState.lua:6957: attempt to index field 'enemy' (a nil
    -- value)".  A foe that faints in a double is lifted off the field at
    -- once, so beating the LAST one leaves nothing to read a level from.  The
    -- level of the one that fell is remembered as it goes (doubleFaint), and
    -- Gen 3 overrides it below with the trainer's last party member anyway.
    local level = (self.enemy and self.enemy.mon and self.enemy.mon.level)
                  or self.lastFoeLevel
                  or (self.enemyParty and self.enemyParty[#self.enemyParty]
                      and self.enemyParty[#self.enemyParty].level) or 1
    if require("src.core.GameVersion").isGen3() then
      local party = self.trainer.party
                    or (self.trainer.parties and self.trainer.parties[1])
      local last = party and party[#party]
      if last and tonumber(last.level) then level = tonumber(last.level) end
    end
    local prize = (self.trainer.baseMoney or 0) * level
    if require("src.core.GameVersion").isGen2() then
      prize = prize * 4
    end
    prize = HeldItems.modifyPrize(self, prize)
    self.game.save.money = self.game.save.money + prize
    -- Prism's Spurge Bank ATM (event/bank.asm) offers DIRECT DEPOSIT: with it
    -- enabled, a quarter of what you win in battle is routed to the account
    -- instead of the wallet.  The switch lives in the ATM special
    -- (g2_spurge_bank); this is the only place the money it skims comes from,
    -- so a save that turned it on and never saw a deduction was the switch
    -- doing nothing at all.
    local bank = self.game.save.g2Bank
    if bank and bank.direct then
      local cut = math.floor(prize / 4)
      self.game.save.money = self.game.save.money - cut
      bank.balance = (bank.balance or 0) + cut
    end
    -- TrainerBattleVictory (core.asm:915-949) in order: EndLowHealthAlarm
    -- and the victory theme, TrainerDefeatedText, ScrollTrainerPicAfterBattle
    -- (the beaten trainer scrolls back in from the right, one column every 4
    -- frames, resting two tiles right of the battle slot), DelayFrames 40,
    -- PrintEndBattleText -- the trainer's OWN loss line, on the battle
    -- screen -- and only then MoneyForWinningText.  Every row rides the
    -- *Next inserters so it keeps that order behind the running queue item;
    -- the plain act() the pic used to ride appended to the END of the queue,
    -- which is why the trainer only flashed up for a frame or two as the
    -- battle popped and the loss line had to be printed by the overworld
    -- afterwards, stranding any evolution between two cuts (#282).
    -- endBattleText is filled in by whoever started the battle
    -- (OverworldState:engageTrainer in src/world/OverworldController.lua);
    -- scripted battles that print their own follow-up leave it nil.
    self:actNext(function() self:playVictoryMusic() end)
    -- _TrainerDefeatedText: "<PLAYER> defeated\nTRAINER!"
    self:sayNext(self:romText("_TrainerDefeatedText", "%s defeated\n%s!", self.game.save.player.name,
                                             self:trainerLabel_()))
    self:actNext(function()
      self.showEnemyTrainer = self.trainerPic ~= nil
      if self.showEnemyTrainer then self:slidePic("foe", 64, 16, 2) end
    end)
    -- the 24-frame scroll-in plus the DelayFrames 40 that follows it
    self.nextInsert = (self.nextInsert or 0) + 1
    table.insert(self.queue, self.nextInsert, { wait = 64 })
    if self.endBattleText then
      -- PrintEndBattleText prints one text box; a `para` (\f) inside it
      -- starts a fresh page, which is a message row of its own here (five
      -- EndBattleTexts carry one, e.g. _Route9Youngster1EndBattleText)
      -- TrainerEndBattleText (home/trainers.asm) prints _TrainerNameText
      -- (wNameBuffer then ": ", data/text/text_1.asm) and only then the
      -- saved pointer, so the loss line opens with the trainer class tag on
      -- its first line (RIVAL1/2/3 tag with the rival's name:
      -- TrainerNamePointers aims those entries at wTrainerName).  The tag
      -- prints once, so a `para` page carries no second copy (#566).
      local tag = self.trainer and self.trainer.name
      if require("src.core.GameVersion").isGen2() then tag = nil end -- GSC prints the line plainly
      for page in (self.endBattleText .. "\f"):gmatch("(.-)\f") do
        if page ~= "" then
          self:sayNext(tag and (tag .. ": " .. page) or page)
          tag = nil
        end
      end
    end
    self:sayNext(self:romText("_MoneyForWinningText", "%s got ¥%d\nfor winning!", self.game.save.player.name, prize))
  end
  self.result = "win"
  self.afterQueue = "finish"
end

-- Queue the learn-a-move flow (auto if a slot is free, else the forget UI)
function BattleState:learnMove(mon, moveId)
  local mdef = self.data.moves[moveId]
  if not mdef then return end
  for _, mv in ipairs(mon.moves) do
    if mv.id == moveId then return end
  end
  if #mon.moves < 4 then
    table.insert(mon.moves, { id = moveId, pp = mdef.pp })
    Runtime.emit("pokemon.move_learned", { mon = mon, moveId = moveId })
    self:sayNext(self:romText("_MimicLearnedMoveText", "%s learned\n%s!", mon.nickname or self.data.pokemon[mon.species].name,
                                            mdef.name))
    return
  end
  -- the "trying to learn" preamble lives inside MoveLearnMenu:enter;
  -- ordered insert so multi-level gains keep each level's checks
  -- between its own stat box and the next "grew to level" text
  self:uiNext(function()
    return self:buildScreen("MoveLearnMenu", mon, moveId)
  end)
end

-- Map the battle was fought on (overworld wins; save.player.map is fallback).
function BattleState.currentMapId(self)
  local game = self.game
  local ow = game and game.overworld
  if ow and ow.map then return ow.map.id end
  local player = game and game.save and game.save.player
  return player and player.map
end

-- pret HandlePlayerBlackOut: OPP_RIVAL1 in OAKS_LAB prints Rival1WinText
-- and returns without blacking out.  OaksLabRivalEndBattleScript then heals.
function BattleState.isOaksLabStarterRival(self)
  return self.oppClass == "OPP_RIVAL1"
    and BattleState.currentMapId(self) == "OAKS_LAB"
end

function BattleState:playerMonFainted()
  local nextMon = Party.firstHealthy(self.game.save.party)
  -- Being out of useable POKéMON blacks you out even when the battle was
  -- already decided in our favour.  A double faint -- our last mon dying
  -- to residual damage on the turn it lands the KO -- used to hit the
  -- "battle is decided" guard below and return with result = "win", so
  -- afterBattle never took the lose branch: no revive, no warp to the
  -- heal point, and the player was left standing on the map with a party
  -- at 0 HP.  Nothing recovers from that state (every later encounter
  -- aborts with "no healthy party"), and it is not reachable in pokered:
  -- HandlePlayerMonFainted runs the player-side check on its own, so
  -- losing your last mon always blacks you out whatever the enemy did.
  -- Exception: the Oak's Lab starter rival (HandlePlayerBlackOut).
  if not nextMon and self.result ~= "lose" then
    if self.oppClass == "OPP_RIVAL1" then
      local TextBox = require("src.render.TextBox")
      local raw = (self.data.text and self.data.text._Rival1WinText)
        or Strings("{RIVAL}: Yeah! Am\nI great or what?")
      self:sayNext(TextBox.substitute(self.game, raw))
    end
    -- Oak's Lab starter rival: Rival1WinText only (no blackout lines).
    -- Any other wipe, including Route 22 RIVAL1, still blacks out.
    if not BattleState.isOaksLabStarterRival(self) then
      -- HandlePlayerBlackOut (core.asm:1150-1159): SET_PAL_BATTLE_BLACK runs
      -- BEFORE PlayerBlackedOutText2, so the enemy pic and both HP bars are
      -- already dark under the blackout lines (#292).  The Oak's Lab starter
      -- rival returns one line above that call and never darkens.  Set here
      -- rather than queued: this whole function already runs from a queued
      -- act after "<mon> fainted!" was dismissed, which is where the palette
      -- command sits.  (The Route 22 RIVAL1 wipe darkens one box early, over
      -- Rival1WinText, which pokered prints just before the same command.)
      self.blackedOut = true
      self:sayNext(Strings("%s is out of\nuseable POKéMON!", self.game.save.player.name))
      self:sayNext(Strings("%s blacked\nout!", self.game.save.player.name))
    end
    self.result = "lose"
    self.afterQueue = "finish"
    return
  end
  if self.result then return end -- double faint: the battle is decided
  -- DoUseNextMonDialogue (core.asm:1052-1078): only WILD battles ask
  -- "Use next POKéMON?"; NO goes through the run check with party slot
  -- 1's speed, and a failed run still forces the party menu.  Trainer
  -- battles go straight to the party menu (the menu-phase guard).
  if self.kind ~= "wild" then return end
  local game = self.game
  self:say(self.data.text._UseNextMonText or Strings("Use next POKéMON?"))
  self:ui(function()
    local ChoiceBox = require("src.ui.ChoiceBox")
    return ChoiceBox.new(game, function(yes)
      if yes then return end -- the menu-phase guard opens the party menu
      local pSpd = (game.save.party[1].stats or { speed = 0 }).speed or 0
      if self:runRoll(pSpd, TurnOrder.effectiveSpeed(self.enemy)) then
        require("src.core.Sound").play(self.data, "Run")
        self:say(self:romText("_GotAwayText", "Got away safely!"))
        self.result = "run"
        self.afterQueue = "finish"
      else
        self:say(self:romText("_CantEscapeText", "Can't escape!"))
      end
    end)
  end)
end

-- ChooseNextMon (core.asm:1086-1128): the battle party menu; a fainted
-- pick re-prompts (via the menu-phase guard), a healthy pick is sent
-- out with no free enemy move.
function BattleState:openReplacementMenu()
  local game = self.game
  self.phase = "messages"
  self.afterQueue = "menu"
  self:ui(function()
    return self:buildScreen("PartyMenu", {
      battle = self,
      -- ChooseNextMon: pick immediately (no SWITCH/STATS/CANCEL)
      forceSwitch = true,
      onSwitch = function(mon)
        if Party.isEgg(mon) then
          self:say(self:romText("_EggNoWillText", "An EGG can't\nbattle!"))
          return -- the menu-phase guard reopens the menu
        end
        if mon.hp <= 0 then
          self:say(self:romText("_NoWillText", "There's no will\nto fight!"))
          return -- the menu-phase guard reopens the menu
        end
        self:restoreMimicked(self.player)
        local previous = self.player
        self.player = makeBattler(self.data, mon, true, game.save)
        clearTrapping(self.enemy) -- SendOutMon clears foe trap
        self:syncSides()
        Runtime.emit("battle.battler_switched", {
          battle = self, side = self.sides[1], battler = self.player,
          previous = previous,
        })
        self:abilitySwitchOut(previous)
        self:markParticipant()
        self.nextInsert = 0
        self.sendingOut = true
        self:sayNext(self:sendOutText(self.player.name))
        self:animNext("POOF_ANIM", false)
        self:shinyAnim(self.player, false)
        self:actNext(function()
          self.sendingOut = false
          -- SendOutMon (core.asm:1757-1762): poof, then the grow-in
          self:startGrowIn(self.player)
          require("src.core.Sound").playCry(self.data, self.player.mon.species)
          HeldItems.onEntry(self, self.player)
        end)
        self:actNext(function() self:abilitySwitchIn(self.player) end)
      end,
    })
  end)
end

-- ---------------------------------------------------------------------
-- Safari game turns
-- ---------------------------------------------------------------------

-- BAIT halves the working catch rate and raises the bait factor by 1-5
-- (zeroing the escape factor); ROCK doubles the catch rate and raises
-- the escape factor by 1-5 (zeroing bait) -- ItemUseBait/ItemUseRock,
-- engine/items/item_effects.asm.
function BattleState:safariAction(choice)
  self.phase = "messages"
  self.afterQueue = "menu"
  local st = self.safari
  local playerName = self.game.save.player.name

  if choice == "run" then
    require("src.core.Sound").play(self.data, "Run")
    self:say(self:romText("_GotAwayText", "Got away safely!"))
    self.result = "run"
    self.afterQueue = "finish"
    return
  end

  if choice == "ball" then
    st.balls = st.balls - 1
    self:say(Strings("%s used\nSAFARI BALL!", playerName))
    self:act(function()
      require("src.core.Sound").play(self.data, "Ball_Toss")
      self.lastBall = "SAFARI_BALL"
      local caught, shakes = self:catchAttempt("SAFARI_BALL", self.safariCatchRate)
      Runtime.emit("battle.ball_thrown", {
        battle = self, ball = "SAFARI_BALL", caught = caught, shakes = shakes,
      })
      -- SAFARI_BALL is neither POKE nor GREAT, so TossBallAnimation
      -- lands on the ULTRATOSS arc (no flicker: SAFARI_BALL is $08,
      -- above DoBallTossSpecialEffects's <= ULTRA_BALL check)
      self:ballChain(self:tossAnimFor("SAFARI_BALL"), caught, shakes, "SAFARI_BALL")
      if caught then
        -- ItemUseBallText05's sound_caught_mon: fanfare with the text
        self:actNext(function()
          require("src.core.Sound").play(self.data, "Caught_Mon")
        end)
        self:sayNext(Strings("All right!\n%s was\ncaught!", self.enemy.name))
        -- same ItemUseBall .captured flow as a regular ball
        self:act(function() self:storeCaughtMon() end)
      else
        self:sayNext(self:ballMissMessage(shakes))
        self:act(function() self:safariEnemyTurn() end)
      end
    end)
    return
  end

  if choice == "bait" then
    self:say(self:romText("_ThrewBaitText", "%s threw some\nBAIT.", playerName))
    self.safariCatchRate = math.floor(self.safariCatchRate / 2)
    self.baitFactor = math.min(255, self.baitFactor + self.rng(1, 5))
    self.escapeFactor = 0
  else -- rock
    self:say(self:romText("_ThrewRockText", "%s threw a\nROCK.", playerName))
    self.safariCatchRate = math.min(255, self.safariCatchRate * 2)
    self.escapeFactor = math.min(255, self.escapeFactor + self.rng(1, 5))
    self.baitFactor = 0
  end
  self:act(function() self:safariEnemyTurn() end)
end

-- Per-turn factor decay (PrintSafariZoneBattleText,
-- engine/battle/safari_zone.asm: when the escape factor runs out the
-- catch rate resets) then the flee check (engine/battle/core.asm:
-- b = 2*speed, quartered while eating, doubled while angry; the mon
-- flees when speed > 127 or rand(0,255) < b).
function BattleState:safariEnemyTurn()
  if self.baitFactor > 0 then
    self.baitFactor = self.baitFactor - 1
    self:sayNext(self:romText("_SafariZoneEatingText", "Wild %s\nis eating!", self.enemy.name))
  elseif self.escapeFactor > 0 then
    self.escapeFactor = self.escapeFactor - 1
    if self.escapeFactor == 0 then
      self.safariCatchRate = self.enemy.def.catchRate
    end
    self:sayNext(self:romText("_SafariZoneAngryText", "Wild %s\nis angry!", self.enemy.name))
  end
  self:act(function()
    local speed = self.enemy.curStats.speed % 256
    local fled = speed > 127
    local b = (speed * 2) % 256
    if not fled then
      if self.baitFactor > 0 then
        b = math.floor(b / 4)
      end
      if self.escapeFactor > 0 then
        b = math.min(255, b * 2)
      end
      fled = self.rng(0, 255) < b
    end
    if fled then
      self:sayNext(self:romText("_WildRanText", "Wild %s\nran!", self.enemy.name))
      self:actNext(function()
        require("src.core.Sound").play(self.data, "Run")
        -- `self` first: startPicKind is a plain local, not a method, and
        -- every other call site passes it. Without it `pf` was the STRING
        -- "slideOff" and the next line wrote a field onto a string, so a
        -- Safari mon fleeing raised instead of sliding off screen.
        startPicKind(self, self:picFxFor(self.enemy), "slideOff")
      end)
      self.nextInsert = (self.nextInsert or 0) + 1
      table.insert(self.queue, self.nextInsert, { wait = 24 })
      self.result = "run"
      self.afterQueue = "finish"
    end
  end)
end

-- A roaming beast gives you exactly one turn and then it is gone.
--
-- That single turn is the whole shape of the fight: it is why the received
-- way to hunt one is a fast lead with MEAN LOOK and a sleep move, and why
-- anything slower than the beast usually never gets to act at all. Trapping
-- it holds it -- MEAN LOOK sets `trapped`, and a trapped mon cannot flee --
-- so the escape is checked here rather than announced unconditionally.
--
-- Nothing happens once the battle is already decided: a beast that fainted,
-- was caught, or won does not also run away.
function BattleState:roamerFlees()
  if not self.roamer then return end
  if self.result then return end
  local enemy = self.enemy
  if not (enemy and enemy.mon and enemy.mon.hp > 0) then return end
  if enemy.trapped then return end
  self:sayNext(self:romText("_WildFledText", "Wild %s\nfled!", enemy.name))
  self:actNext(function()
    require("src.core.Sound").play(self.data, "Run")
    startPicKind(self, self:picFxFor(enemy), "slideOff")
  end)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = 24 })
  self.roamerEscaped = true
  self.result = "run"
  self.afterQueue = "finish"
end

-- ---------------------------------------------------------------------
-- run / items / party
-- ---------------------------------------------------------------------

-- Gen 1 escape formula (engine/battle/core.asm TryRunningFromBattle),
-- shared by the RUN menu choice and the faint dialogue's NO branch;
-- counts a run attempt each call.  Hooked as battle.run.
function BattleState:runRoll(pSpd, eSpd)
  self.runAttempts = (self.runAttempts or 0) + 1
  -- Smoke Ball guarantees escape from a wild battle without consuming the
  -- ordinary speed/RNG formula.  Trainer battles are rejected by tryRun first.
  if self.kind ~= "trainer" and HeldItems.canEscape(self.data, self.player) then
    return true
  end
  if Runtime.wantsHook("battle.run") then
    local battle = self
    return Runtime.call("battle.run", function(c)
      return battle:runRollVanilla(c.pSpd, c.eSpd)
    end, { battle = self, pSpd = pSpd, eSpd = eSpd,
           attempts = self.runAttempts, rng = self.rng })
  end
  return self:runRollVanilla(pSpd, eSpd)
end

function BattleState:runRollVanilla(pSpd, eSpd)
  if self.ghost then
    return true -- IsGhostBattle -> always escapes
  end
  if pSpd >= eSpd then return true end
  local b = math.floor(eSpd / 4) % 256
  if b == 0 then
    return true -- divisor of zero auto-escapes
  end
  local x = math.floor(pSpd * 32 / b)
  -- +30 per PREVIOUS attempt, escape on 8-bit overflow or on
  -- rand <= x (the original's jr nc keeps the equal case)
  x = x + 30 * (self.runAttempts - 1)
  return x >= 256 or self.rng(0, 255) <= x
end

-- Gen 1 escape formula (engine/battle/core.asm TryRunningFromBattle)
function BattleState:tryRun()
  self.phase = "messages"
  self.afterQueue = "menu"
  -- A wild battle the script says cannot be escaped.  There is exactly one in
  -- Emerald -- the first -- and the roll is skipped rather than rigged, so a
  -- lucky roll can never break the scene.
  if self.noRun then
    self:say(self:romText("_CantEscapeText", "Can't escape!"))
    self:act(function()
      self:executeAction(self.enemy, self.player, self:enemyAction())
    end)
    self:act(function() self:endOfTurn() end)
    return
  end
  if self.kind == "trainer" then
    -- _NoRunningText is three lines in a two-line box, so the third arrives
    -- on a \v scroll (ContText: ▼ then a button press) rather than a \n.
    -- Spelling it with three \n dropped "trainer battle!" and handed the
    -- menu straight back (#239).
    self:say(self.data.text._NoRunningText
      or Strings("No! There's no\nrunning from a\vtrainer battle!"))
    return
  end
  -- ...AND THREE ABILITIES DECIDE IT BEFORE THE SPEEDS DO.
  --
  -- RUN AWAY always gets out of a wild battle, whatever the speeds are and
  -- whatever is holding it.  SHADOW TAG, ARENA TRAP and MAGNET PULL on the
  -- other side stop it getting out at all -- which is the same rule that
  -- stops a switch, asked of the same function, so a WOBBUFFET is as
  -- inescapable here as it is from the party menu.
  local escaped
  local trapper = Abilities.trapsSwitch(self.enemy, self.player)
  if Abilities.alwaysFlees(self.player) then
    escaped = true
  elseif trapper then
    escaped = false
    self:say(Strings("%s's\n%s\nprevents escape!", displayName(self.enemy),
                     abilityLabel(trapper)))
  else
    -- modified in-battle speeds (stat stages + paralysis), like the
    -- wBattleMonSpeed the original hands to TryRunningFromBattle
    escaped = self:runRoll(TurnOrder.effectiveSpeed(self.player),
                           TurnOrder.effectiveSpeed(self.enemy))
  end
  if escaped then
    require("src.core.Sound").play(self.data, "Run")
    self:say(self:romText("_GotAwayText", "Got away safely!"))
    self.result = "run"
    self.afterQueue = "finish"
  else
    self:say(self:romText("_CantEscapeText", "Can't escape!"))
    self:act(function()
      self:executeAction(self.enemy, self.player, self:enemyAction())
    end)
    self:act(function() self:endOfTurn() end)
  end
end

function BattleState:openItems()
  self.phase = "messages"
  self.afterQueue = "menu"
  self:ui(function()
    return self:buildScreen("BagMenu", { battle = self })
  end)
end

-- called by BagMenu after an item is used in battle (consumes the turn)
function BattleState:itemUsed(messages)
  -- bag cures clear mon.status before the message UI; refresh the HUD
  -- once control returns (pokered DrawHUDsAndHPBars after item use)
  self:syncShownStatus()
  for _, m in ipairs(messages or {}) do self:say(m) end
  table.insert(self.queue, { drain = true }) -- potions animate the bar
  self:act(function()
    self:executeAction(self.enemy, self.player, self:enemyAction())
  end)
  self:act(function() self:endOfTurn() end)
end

-- Wobble messages by shake count (ItemUseBallText01..04)
function BattleState:ballMissMessage(shakes)
  local t = self.data.text
  if shakes == 0 then
    return t._ItemUseBallText01 or Strings("You missed the\nPOKéMON!")
  elseif shakes == 1 then
    return t._ItemUseBallText02 or Strings("Darn! The POKéMON\nbroke free!")
  elseif shakes == 2 then
    return (t._ItemUseBallText03 or self:romText("_ItemUseBallText03", "Aww! It appeared\nto be caught!")):gsub("%s+$", "")
  end
  return t._ItemUseBallText04 or self:romText("_ItemUseBallText04", "Shoot! It was so\nclose too!")
end

-- AskName (engine/menus/naming_screen.asm): ClearSprites, wild field blank,
-- PrintText, YES/NO while text stays (TextBox opts.choice). Shared by party
-- AddPartyMon and SendNewMonToBox (#172).
function BattleState:askNicknameUI(mon, displayName)
  local game = self.game
  self.lockedBall = nil
  self.blankForAskName = true
  local TextBox = require("src.render.TextBox")
  local text = self:romText("_DoYouWantToNicknameText", "Do you want to\ngive a nickname\nto %s?", displayName)
  local label = game.data.text and game.data.text._DoYouWantToNicknameText
  if label then
    -- extractor CONT is \t; TextBox scrolls on \n/\v
    text = label:gsub("\t", "\n"):gsub("{RAM:?[%w_]*}", displayName)
  end
  return TextBox.new(game, text, nil, {
    choice = function(yes)
      self.blankForAskName = false
      if not yes then return end
      pcall(Screens.push, game, "NamingScreen", {
        title = Strings("NICKNAME?"), maxLen = 10,
        onDone = function(name)
          if name and #name > 0 then mon.nickname = name end
        end,
      })
    end,
  })
end

-- The caught mon joins the party or a PC box (ItemUseBall .captured,
-- item_effects.asm:518-566): the caught text, then for a NEW species
-- "New POKéDEX data will be added" + the dex entry page, then
-- AddPartyMon or SendNewMonToBox (both call AskName), then the PC
-- transfer text when the party was full.
function BattleState:storeCaughtMon()
  -- ItemUseBall reloads the caught mon via LoadEnemyMonData
  -- (item_effects.asm:472-501), regenerating its move list from the
  -- base data -- a Mimic'd slot never leaves the battle with it
  self:restoreMimicked(self.enemy)
  -- battle.catch_exp: vanilla catches never grant exp; a mod can flip
  -- this to true to pay out the same award a faint would have.
  if Runtime.wantsHook("battle.catch_exp")
     and Runtime.call("battle.catch_exp", function() return false end, { battle = self }) then
    self:awardExp()
  end
  local game = self.game
  local dex = game.save.pokedex
  local species = self.enemy.mon.species
  local isNew = dex ~= nil and not dex.owned[species]
  local destination = "party"
  markOwned(game, species)
  -- BATTLERESULT_CAUGHT_CELEBI (wBattleResult bit 6).  The Ilex shrine script
  -- reads it back through `special CheckCaughtCelebi` to decide whether Kurt's
  -- GS Ball chain is finished, so it has to be recorded at the catch itself --
  -- the battle result is gone by the time the script runs.
  if species == "SPECIES_251" then game.save.g2CaughtCelebi = true end
  -- UnownCaught (readvar 14) counts distinct letters, which is what the
  -- Ruins of Alph researcher and the dex's UNOWN mode gate on
  local form = require("src.pokemon.Sprites").formIndex(
    game.data.pokemon[species], self.enemy.mon)
  if dex and form then
    dex.unownForms = dex.unownForms or {}
    if not dex.unownForms[form] then
      dex.unownForms[form] = true
      -- UpdateUnownDex (engine/pokedex/unown_dex.asm) appends the letter to
      -- wUnownDex the first time it is caught and never reorders it, so the
      -- dex's UNOWN MODE lists the letters in catch order, not alphabetically
      -- ("It records them in the sequence that they were caught.")
      dex.unownDex = dex.unownDex or {}
      dex.unownDex[#dex.unownDex + 1] = form
    end
  end
  -- CAUGHT: the memo's "met at Lv5, ROUTE 101" comes from right here, and the
  -- level is the one it was caught AT rather than the one it is now, which is
  -- the whole reason the cartridge stores it separately.
  stampOT(game.save, self.enemy.mon,
          { level = self.enemy.mon.level, location = BattleState.metHere(game) })
  if isNew then
    -- _ItemUseBallText06 + ShowPokedexData
    self:sayNext(Strings("New POKéDEX data\nwill be added for\n%s!", self.enemy.name))
    self:uiNext(function()
      return self:buildScreen("DexEntryMenu", species)
    end)
  end
  local function askCaughtNickname()
    local caught = self.enemy.mon
    local enemyName = self.enemy.name
    self:uiNext(function()
      return self:askNicknameUI(caught, enemyName)
    end)
  end
  -- ...AND WHAT IT WAS CAUGHT IN, before it goes anywhere.
  --
  -- Emerald sends a Pokemon out in the ball it was caught in (the four bits
  -- in Misc's packed half-word), so this is the moment those bits are
  -- written.  The ITEM ID rather than a sheet row: the row is a jump table
  -- the cartridge owns, and an id still means the right ball after a
  -- re-import renumbers nothing.  Recorded whether it lands in the party or
  -- a box, because a box Pokemon is sent out in its own ball too.
  if self.enemy.mon and self.lastBall and self.enemy.mon.ball == nil then
    self.enemy.mon.ball = self.lastBall
  end
  if Party.add(game.save.party, self.enemy.mon) then
    askCaughtNickname()
  else
    destination = "box"
    local boxNum = require("src.pokemon.Boxes").deposit(game.save, self.enemy.mon)
    if boxNum then
      askCaughtNickname()
      -- _ItemUseBallText07/08 keyed on EVENT_MET_BILL
      local pc = (game.save.flags and game.save.flags.EVENT_MET_BILL)
                 and "BILL's PC" or Strings("someone's PC")
      self:sayNext(Strings("%s was\ntransferred to\n%s!", self.enemy.name, pc))
    else
      self:sayNext(Strings("But every BOX\nis full!"))
    end
  end
  -- CatchMon copies the species name into wStringBuffer1, which is what the
  -- Bug Contest's "Caught <MON>!" and friends splice back out with text_ram
  game.stringBuffer = self.enemy.name
  Runtime.emit("pokemon.caught", {
    battle = self, mon = self.enemy.mon, species = species, isNew = isNew,
    ball = self.lastBall, destination = destination, game = game,
  })
  self.result = "caught"
  self.afterQueue = "finish"
end

-- TossBallAnimation (engine/battle/animations.asm:2582): the tier's toss
-- anim, then wPokeBallAnimData's upper-nybble count of .PokeBallAnimations
-- entries -- POOF+HIDEPIC+SHAKE for a capture ($43), all five (plus a
-- reappearing POOF+SHOWPIC) for a breakout ($6x); a clean miss ($20)
-- stops after the poof, so the mon never hides
-- HOENN THROWS ITS OWN BALL.
--
-- Reported from play: "Pokeball throwing animations dont exist in battle
-- either", "neither do the capturing shaking etc eniamtions".  Both are the
-- same gap: this chain is written in Gen 1's and Gen 2's animation SCRIPTS --
-- TOSS_ANIM, POOF_ANIM, SHAKE_ANIM -- and a Gen 3 dataset has none of them,
-- so every row below was a lookup that found nothing and the whole capture
-- happened with the ball never drawn.
--
-- Emerald's is not a script either: it is a task with a timeline, so this
-- port's is a timeline too (src/battle/Gen3BallAnim.lua).  The queue holds
-- for its length and the screen reads its fields.
function BattleState:gen3BallChain(caught, shakes, ball)
  local record = (self.data.constants or {}).gen3BallAnim
  if type(record) ~= "table" then return false end
  local Gen3BallAnim = require("src.battle.Gen3BallAnim")
  local Gen3Battle = require("src.battle.Gen3Battle")
  -- WHERE IT IS THROWN TO, AND WHERE IT LANDS, which are two places.
  --
  -- Reported from play: "the ball shakes and catches but its hovering instead
  -- of being on the ground".  It was: this asked picPlacement for the foe's
  -- corner and passed it two arguments when it takes five, so the call threw
  -- inside its own pcall every time and the fallback below -- a fixed point
  -- level with the middle of the Pokemon -- was where the ball bounced, shook
  -- and sat.  It never touched the ground because nothing ever told it where
  -- the ground was.
  --
  -- The throw goes to the Pokemon's BODY, because that is what it has to
  -- absorb; the bounce afterwards happens on the PLATFORM, which is the same
  -- line the foe's feet stand on and is measured out of the drawn background.
  local to = { x = 176, y = 40 }
  local centre = Gen3Battle.battlerCentre
                 and select(2, pcall(Gen3Battle.battlerCentre, self, self.enemy))
  local cy = select(3, pcall(Gen3Battle.battlerCentre, self, self.enemy))
  if type(centre) == "number" and type(cy) == "number" then
    to = { x = centre, y = cy }
  end
  local spots = Gen3Battle.platforms and select(2, pcall(Gen3Battle.platforms, self))
  local ground = type(spots) == "table" and spots.opponent
                 and tonumber(spots.opponent.y) or nil
  local anim = Gen3BallAnim.new(self.data, {
    ball = Gen3BallAnim.ballIndex(self.data, ball, self.data.items),
    caught = caught, shakes = shakes,
    -- a trainer's Pokemon swats the ball away, which is case 5 and its own
    -- little arc rather than a shake count
    blocked = self.kind ~= "wild",
    to = to,
    ground = ground,
  })
  self.gen3Ball = anim
  self.gen3BallPlaying = true
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = anim:estimate() })
  return true
end

-- ...AND HOENN THROWS ITS OWN BALL TO SEND ONE OUT AS WELL.
--
-- Reported from play, with a picture: the ball above the text box "is
-- supposed to be in the players hand unscrambled and its supposed to play the
-- animation of him throwing it out".  Half of that was the party-ball row
-- drawing the Game Boy's sheet; this is the other half.  There was no
-- send-out animation on Hoenn at all -- the queue ran Gen 1's POOF_ANIM,
-- which a Gen 3 dataset has no script for, and then Gen 2's grow-in, which is
-- the Game Boy's three-stage tile beat rather than anything Emerald does.
--
-- WHAT EMERALD DOES, and all of it comes off the cartridge:
--
--   the PLAYER's ball starts in the trainer's hand at (24,68) and arcs 25
--   frames and thirty pixels to a point twenty-four BELOW the Pokemon's own
--   centre -- a flatter, shorter throw than the capture's;
--
--   the FOE's is not thrown: it is placed on the spot and waits sixteen
--   frames, which is why an opposing trainer's send-out has no arc;
--
--   and both end the same way -- the ball opens, throws its particle ring,
--   and the Pokemon comes out un-blending from the ball's OWN colour over
--   fourteen frames.
--
-- Returns false on a dataset with no send-out record, and the Game Boy's
-- grow-in runs instead: a ball thrown to the wrong place would be worse.
-- Is the ball's timeline talking about THIS Pokemon?  A capture is always
-- about the foe, but a send-out can be about either side, and without the
-- question the player's throw shrank the Pokemon standing opposite.
-- A WILD SHINY, which has no ball to sparkle out of.
--
-- PrintBeginningBattleText's wild branch plays the shiny animation and
-- nothing else, because the Pokemon is already standing there -- Gen 2 does
-- the same thing at core.asm:9091 and this is Hoenn's half of it.  Every
-- other send-out in the file goes through startGrowIn -> gen3SendOut, which
-- carries its own sparkle, so this one path is the only one that needs it and
-- there is no double sparkle anywhere.
function BattleState:gen3ShinyBurst(battler)
  if not battler then return false end
  if not self:gen3ThrowsSendOut() then return false end
  if self.data and self.data.battle_anims and self.data.battle_anims.gen2 then
    return false -- Johto has its own SHINY_ANIM; this is the Gen 3 dataset
  end
  local mon = battler.mon
  if not (mon and require("src.pokemon.Pokemon").isShiny(mon)) then return false end
  if self.gen3Ball and self.gen3BallPlaying then return false end
  local Gen3BallAnim = require("src.battle.Gen3BallAnim")
  local Gen3Battle = require("src.battle.Gen3Battle")
  local cx = select(2, pcall(Gen3Battle.battlerCentre, self, battler))
  local cy = select(3, pcall(Gen3Battle.battlerCentre, self, battler))
  if type(cx) ~= "number" or type(cy) ~= "number" then return false end
  local anim = Gen3BallAnim.new(self.data, {
    shinyOnly = true, battler = battler, to = { x = cx, y = cy },
  })
  self.gen3Ball = anim
  self.gen3BallPlaying = true
  -- called from inside a queue row, so the hold goes right after it rather
  -- than on the end of the list behind everything else
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = anim:estimate() })
  return true
end

function BattleState:gen3BallFor(battler)
  local anim = self.gen3Ball
  if not anim then return nil end
  if anim.battler and anim.battler ~= battler then return nil end
  if not anim.battler and battler ~= self.enemy then return nil end
  return anim
end

function BattleState:gen3ThrowsSendOut()
  local record = (self.data or {}).constants
  record = type(record) == "table" and record.gen3BallAnim or nil
  local timing = type(record) == "table" and record.timing or nil
  return type(timing) == "table" and type(timing.sendOut) == "table"
end

-- WHICH OF THE TWELVE SHEETS a Pokemon's ball is drawn from.  Accepts either
-- the item id a save and a capture now record, or the bare sheet row an older
-- save may already carry, because ItemIdToBallId is a jump table and not an
-- order: POKe is row 0, GREAT is 1, SAFARI is 2, ULTRA is 3 and MASTER is 4.
function BattleState:gen3BallSheet(mon)
  local ball = mon and mon.ball
  if type(ball) == "number" then return math.max(0, math.floor(ball)) end
  if type(ball) ~= "string" then return 0 end
  local Gen3BallAnim = require("src.battle.Gen3BallAnim")
  local ok, row = pcall(Gen3BallAnim.ballIndex, self.data, ball, self.data.items)
  return (ok and tonumber(row)) or 0
end

function BattleState:gen3SendOut(battler)
  if not battler then return false end
  if not self:gen3ThrowsSendOut() then return false end
  local record = (self.data.constants or {}).gen3BallAnim
  local timing = record.timing
  -- one ball at a time: a capture already owns the timeline
  if self.gen3Ball and self.gen3BallPlaying then return false end
  local Gen3BallAnim = require("src.battle.Gen3BallAnim")
  local Gen3Battle = require("src.battle.Gen3Battle")
  local cx = select(2, pcall(Gen3Battle.battlerCentre, self, battler))
  local cy = select(3, pcall(Gen3Battle.battlerCentre, self, battler))
  if type(cx) ~= "number" or type(cy) ~= "number" then return false end
  local anim = Gen3BallAnim.new(self.data, {
    -- WHICH BALL IT WAS CAUGHT IN.
    --
    -- Emerald sends a Pokemon out in the ball it was caught in, and the four
    -- bits that say so live in the Misc substruct's packed half-word -- which
    -- the save codec never read, so every send-out here was a POKe BALL
    -- whatever it was caught with.  Both ends are fixed now: a save carries
    -- it in and a capture writes it, and both write the ITEM ID rather than a
    -- sheet row, because the row is a jump table the cartridge owns
    -- (MASTER is sheet 4 and POKe is 0) and an id survives a re-import.
    ball = self:gen3BallSheet(battler.mon),
    sendOut = (battler == self.player) and "player" or "opponent",
    battler = battler,
    to = { x = cx, y = cy },
    -- ...AND IF IT SPARKLES, IT SPARKLES HERE.  TryShinyAnimation is called
    -- out of the send-out, once the mon is out of the ball, which is exactly
    -- what this animation owns -- so the shiny beat rides it rather than
    -- becoming a second thing the queue has to schedule.
    shiny = require("src.pokemon.Pokemon").isShiny(battler.mon),
  })
  self.gen3Ball = anim
  self.gen3BallPlaying = true
  -- the trainer throws and walks off on the same frame; showPlayerBack is
  -- dropped when the ball opens, by which time the slide has finished
  if self.showPlayerBack and battler == self.player then
    self:slidePic("back", 0, -72, 4)
  end
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = anim:estimate() })
  return true
end

function BattleState:ballChain(tossAnim, caught, shakes, ball)
  if self:gen3BallChain(caught, shakes, ball) then return end
  -- Gen 2 has no chain: BattleAnim_ThrowPokeBall runs the arc, the
  -- RETURN_MON bgeffect that draws the mon in, the wobble loop
  -- (anim_checkpokeball -> GetPokeBallWobble) and finally the click or the
  -- break-out, all from one script.  Replaying Gen 1's POOF/HIDEPIC/SHAKE
  -- rows on top of it would only double up pieces of what it just did.
  if self.data and self.data.battle_anims and self.data.battle_anims.gen2 then
    self:animNext(tossAnim, true, shakes, ball, caught)
    if caught then
      self:actNext(function()
        self.lockedBall = self.animPlayer and self.animPlayer:finalSprites() or nil
      end)
    end
    return
  end
  self:animNext(tossAnim, true, nil, ball)
  self:animNext("POOF_ANIM", true)
  if not caught and shakes == 0 then return end
  self:animNext("HIDEPIC_ANIM", true)
  self:animNext("SHAKE_ANIM", true, shakes)
  if not caught then
    self:animNext("POOF_ANIM", true)
    self:animNext("SHOWPIC_ANIM", true)
    return
  end
  -- on a capture the $43 chain simply ends after SHAKE_ANIM
  -- (TossBallAnimation returns): the GB leaves the resting closed ball
  -- in OAM, so it stays on screen through the caught text
  self:actNext(function()
    self.lockedBall = self.animPlayer and self.animPlayer:finalSprites() or nil
  end)
end

-- TossBallAnimation picks the toss arc from the ball record's tossAnim;
-- an unknown ball keeps the wCurItem mapping: POKE->TOSS,
-- GREAT->GREATTOSS, everything else (ULTRA/MASTER/SAFARI...)->ULTRATOSS
function BattleState:tossAnimFor(ball)
  local def = self:ballDef(ball)
  if def and def.tossAnim then return def.tossAnim end
  return ball == "POKE_BALL" and "TOSS_ANIM"
         or ball == "GREAT_BALL" and "GREATTOSS_ANIM"
         or "ULTRATOSS_ANIM"
end

-- the Master/Ultra OBJ-palette flicker, from the ball record
function BattleState:ballFlicker(ball)
  local def = self:ballDef(ball)
  return (def and def.flicker) or false
end

-- called by BagMenu when a ball is thrown
function BattleState:throwBall(ball)
  -- ItemUseBall branches to ThrowBallAtTrainerMon on wIsInBattle != 1
  -- (item_effects.asm:109-113) BEFORE it reaches `ld hl, ItemUseText00 /
  -- call PrintText` (:146-147), so a trainer battle never shows the
  -- "<PLAYER> used <ITEM>!" line (#291).  Safari and the old man demo are
  -- still wIsInBattle == 1, and this port models both as kind == "wild".
  if self.kind == "wild" then
    local def = self:itemDef(ball)
    self:say(self:romText("_ItemUseText001", "%s used\n%s!", self.game.save.player.name,
                                     (def and def.name) or ball))
  end
  self:act(function()
    require("src.core.Sound").play(self.data, "Ball_Toss")
    if self.kind ~= "wild" then
      -- ThrowBallAtTrainerMon (item_effects.asm:2292-2303) still animates the
      -- toss: MoveAnimation routes TOSS_ANIM to TossBallAnimation, which takes
      -- its .BlockBall branch in a trainer battle (animations.asm:2582-2585,
      -- 2629-2637) -- the plain TOSS arc whatever the ball tier, then
      -- SFX_FAINT_THUD and BLOCKBALL_ANIM, and only then the two texts.  The
      -- ball still counts as used: UseItem_ sets
      -- wActionResultOrTookBattleTurn = 1 (item_effects.asm:1-3) and this path
      -- never clears it, so UseBagItem does not fall back to the bag
      -- (core.asm:2257-2259) and the turn is spent -- the foe moves (#291).
      local t = self.data.text
      self:animNext("TOSS_ANIM", true, nil, ball)
      self:actNext(function()
        require("src.core.Sound").play(self.data, "Faint_Thud")
      end)
      self:animNext("BLOCKBALL_ANIM", true)
      self:sayNext(t._ThrowBallAtTrainerMonText1
                   or self:romText("_ThrowBallAtTrainerMonText1", "The trainer\nblocked the BALL!"))
      self:sayNext(t._ThrowBallAtTrainerMonText2
                   or self:romText("_ThrowBallAtTrainerMonText2", "Don't be a thief!"))
      self:act(function()
        self:executeAction(self.enemy, self.player, self:enemyAction())
      end)
      self:act(function() self:endOfTurn() end)
      return
    end
    if self.ghost or self.noCatch then
      -- ItemUseBall's can't-be-caught path (item_effects.asm:149-153):
      -- the ball is thrown (TossBallAnimation still picks the arc from
      -- wCurItem, so a Master/Ultra toss keeps its flicker), dodged
      -- ($10 anim data, no wobbles), and the turn is spent like any
      -- failed throw.  battle.noCatch is the .notOldManBattle half of the
      -- same check (item_effects.asm:166-175): the POKEMON_TOWER_6F
      -- RESTLESS SOUL dodges balls even once the scope has revealed it,
      -- so it is not a ghost battle any more (#444)
      self:animNext(self:tossAnimFor(ball), true, nil, ball)
      self:sayNext(Strings("It dodged the\nthrown BALL!"))
      self:sayNext(Strings("This POKéMON\ncan't be caught!"))
      self:act(function()
        self:executeAction(self.enemy, self.player, self:enemyAction())
      end)
      self:act(function() self:endOfTurn() end)
      return
    end
    self.lastBall = ball
    local caught, shakes = self:catchAttempt(ball)
    Runtime.emit("battle.ball_thrown", {
      battle = self, ball = ball, caught = caught, shakes = shakes,
    })
    -- ItemUseBall's 20-frame beat, then the toss chain for the outcome
    self.nextInsert = (self.nextInsert or 0) + 1
    table.insert(self.queue, self.nextInsert, { wait = 20 })
    self:ballChain(self:tossAnimFor(ball), caught, shakes, ball)
    if caught then
      -- ItemUseBallText05 carries sound_caught_mon (item_effects.asm:
      -- 608-614): the fanfare sounds with the caught message, before
      -- the prompt, not after the text is dismissed
      self:actNext(function()
        require("src.core.Sound").play(self.data, "Caught_Mon")
      end)
      self:sayNext(Strings("All right!\n%s was\ncaught!", self.enemy.name))
      self:act(function() self:storeCaughtMon() end)
    else
      self:sayNext(self:ballMissMessage(shakes))
      self:act(function()
        self:executeAction(self.enemy, self.player, self:enemyAction())
      end)
      self:act(function() self:endOfTurn() end)
    end
  end)
end

-- Throwing a Park Ball.  Modelled on the Safari Ball path above, with the
-- three things that make the contest different:
--
--   * the count is on the SAVE (wParkBallsRemaining), and `.used_park_ball`
--     (item_effects.asm:718) decrements it on EVERY throw, caught or not --
--     it never goes through TossItem because there is no bag item;
--   * ParkBallMultiplier gives the species catch rate x 1.5;
--   * a catch does NOT join the party.  BugContest_SetCaughtContestMon puts
--     it in wContestMon, which is the one mon that gets scored.
function BattleState:bugContestBall()
  local BugContest = require("src.world.BugContest")
  local save = self.game.save
  -- `.used_park_ball` (item_effects.asm:718) is a bare `dec [hl]` with no
  -- floor, because on a cartridge you can never reach the menu again with the
  -- count at zero: BugCatchingContestBattleScript ends the run the moment the
  -- battle it was spent in is over.  When THAT check went missing the player
  -- kept throwing past twenty, so refuse here as well -- one guard for the
  -- last ball of a battle, one for the run.
  if BugContest.ballsLeft(save) <= 0 then
    self.phase = "messages"
    self.afterQueue = "menu"
    self:say(Strings("You have no\nPARK BALLs left!"))
    return
  end
  self.phase = "messages"
  self.afterQueue = "menu"
  BugContest.useBall(save)
  self:say(self:romText("_ItemUseText001", "%s used\n%s!",
                        save.player.name, Strings("PARK BALL")))
  self:act(function()
    require("src.core.Sound").play(self.data, "Ball_Toss")
    self.lastBall = "PARK_BALL"
    local rate = BugContest.parkBallRate(self.enemy.def.catchRate)
    local caught, shakes = self:catchAttempt("PARK_BALL", rate)
    Runtime.emit("battle.ball_thrown", {
      battle = self, ball = "PARK_BALL", caught = caught, shakes = shakes,
    })
    self:ballChain(self:tossAnimFor("PARK_BALL"), caught, shakes, "PARK_BALL")
    if caught then
      self:actNext(function()
        require("src.core.Sound").play(self.data, "Caught_Mon")
      end)
      self:act(function() self:storeContestMon() end)
    else
      self:sayNext(self:ballMissMessage(shakes))
      -- the ball is the player's turn, so the foe still moves
      self:act(function()
        self:executeAction(self.enemy, self.player, self:enemyAction())
      end)
      self:act(function() self:endOfTurn() end)
    end
  end)
end

-- BugContest_SetCaughtContestMon (engine/events/bug_contest/caught_mon.asm).
-- Nothing is held yet -> keep it and print _ContestCaughtMonText.  Something
-- IS held -> the already-caught line, the new one's stats, and a yes/no; NO
-- (`ret c`) keeps the mon you already had, and the battle ends either way.
function BattleState:storeContestMon()
  local BugContest = require("src.world.BugContest")
  local save = self.game.save
  local caught = self.enemy.mon
  local name = self.enemy.name
  local held = BugContest.caught(save)

  local function keepNew()
    -- .generatestats rebuilds the mon from base data before storing it, the
    -- same reload a normal catch does (storeCaughtMon's restoreMimicked).
    self:restoreMimicked(self.enemy)
    BugContest.setCaught(save, caught)
    self:sayNext(Strings("%s was\ncaught!", name))
  end

  markOwned(self.game, caught.species)
  if not held then
    keepNew()
  else
    -- _ContestAlreadyCaughtText names the mon you are ALREADY holding, not the
    -- one you just caught: DisplayAlreadyCaughtText is called with
    -- wNamedObjectIndex = [wContestMon] (caught_mon.asm:6-8).  Resolve that
    -- through the nickname, then the species record, then the raw id -- a nil
    -- here used to reach string.format and come back as the untouched source
    -- string, which is why the line arrived with no name in it at all.
    local heldName = held.nickname
    if not heldName then
      local heldDef = held.species and self.game.data.pokemon
                      and self.game.data.pokemon[held.species]
      heldName = heldDef and heldDef.name
    end
    heldName = heldName or tostring(held.species or "?")
    self:sayNext(Strings("You already caught\na %s.", heldName))
    -- _ContestAskSwitchText is exactly "Switch #MON?", asked over the
    -- STOCK/THIS comparison box; YES keeps the new one (PlaceYesNoBox's
    -- `ret c` on NO leaves the stock mon alone).
    self:sayNext(Strings("%s\nLv%d  vs  %s\nLv%d", heldName,
                         tonumber(held.level) or 0, name,
                         tonumber(caught.level) or 0))
    self:sayNext(Strings("Switch POKéMON?"))
    self:uiNext(function()
      local ChoiceBox = require("src.ui.ChoiceBox")
      return ChoiceBox.new(self.game, function(yes)
        if yes then
          keepNew()
        else
          self:sayNext(Strings("%s was\nreleased.", name))
        end
      end)
    end)
  end
  -- A capture ends a wild battle, contest or not -- same result value
  -- storeCaughtMon uses, so afterBattle treats it identically.
  self:actNext(function()
    self.result = "caught"
    self.afterQueue = "finish"
  end)
end

function BattleState:openParty()
  self.phase = "messages"
  self.afterQueue = "menu"
  self:ui(function()
    return self:buildScreen("PartyMenu", {
      battle = self,
      onSwitch = function(mon)
        -- "ALREADY OUT" IS BOTH SLOTS IN A DOUBLE.  The partner standing
        -- beside you cannot be sent out again either, and asking `self.player`
        -- alone let the right-hand slot pick the Pokemon already fighting
        -- next to it.
        local standing
        for _, b in activeBattlers(self) do
          if b.isPlayer and b.mon == mon then standing = b end
        end
        if standing then
          self:say(Strings("%s is\nalready out!", standing.name))
        elseif Party.isEgg(mon) then
          -- CheckFirstMonIsEgg (01:$728B): an EGG can never be sent out
          self:say(self:romText("_EggNoWillText",
            "An EGG can't\nbattle!"))
        elseif mon.hp <= 0 then
          self:say(self:romText("_NoWillText", "There's no will\nto fight!"))
        elseif self:isDouble() then
          -- A SWITCH IN A DOUBLE IS AN ACTION, NOT AN ANSWER.  The other
          -- three slots still move this turn, so it goes into the same
          -- pending list a chosen move does and is resolved in the turn --
          -- ahead of every move, which is where the cartridge puts it.
          self:chooseAction({ special = "playerSwitch", mon = mon })
        else
          self:resolveSwitch(mon)
        end
      end,
    })
  end)
end

-- PlayBattleVictoryMusic (core.asm:959-967) + EndLowHealthAlarm
-- (core.asm:864-872): winning stops the low-health alarm and disables
-- it for the rest of the battle (wLowHealthAlarmDisabled), then starts
-- the victory theme once; gym leaders, Lance and the final rival share
-- MUSIC_DEFEATED_GYM_LEADER (core.asm:917-926).
function BattleState:playVictoryMusic()
  require("src.core.Sound").stopLoop("Low_Health_Alarm")
  self.lowHealthAlarmDisabled = true
  if self.victoryMusicPlayed then return end
  self.victoryMusicPlayed = true
  -- PlayVictoryMusic (0F:$50EA) has only three songs: the wild jingle, then
  -- MUSIC_DEFEATED_GYM_LEADER when IsGymLeader matches the class -- which
  -- covers the Kanto leaders, the Elite Four and the Champion -- and
  -- MUSIC_DEFEATED_TRAINER for everyone else, the rival and Team Rocket
  -- included.  Map the eleven battle themes back onto those three.
  local kind = GEN2_VICTORY_KIND[self.musicKind or "wild"]
    or (self.musicKind or "wild")
  require("src.core.Music").playVictory(self.data, kind)
end

function BattleState:finish()
  if self.payDay and self.result == "win" then
    self.game.save.money = self.game.save.money + self.payDay
    self:say(self:romText("_PickUpPayDayMoneyText", "%s picked up\n¥%d!", self.game.save.player.name, self.payDay))
    self.payDay = nil
    self.afterQueue = "finish"
    self.phase = "messages"
    return
  end
  -- Invariant: a battle can never hand the overworld a party with nothing
  -- healthy in it -- except the Oak's Lab starter rival, where pret skips
  -- the blackout and OaksLabRivalEndBattleScript HealParty's immediately.
  -- afterBattle only revives and warps to the heal point on a normal
  -- "lose", so any other result here strands the player at 0 HP with no
  -- way back -- an unrecoverable state, not merely a wrong one.
  -- playerMonFainted is the path that should have caught this; if we land
  -- here it did not, so say so rather than silently papering over it.
  -- The old-man / PROF.OAK demo also skips it: the party never fought
  -- (Yellow's Pallet intro runs before the player owns a mon at all).
  if self.result ~= "lose" and not self.demo
     and not Party.firstHealthy(self.game.save.party) then
    Logger.warn("battle finished %s with no healthy party; forcing blackout",
                tostring(self.result))
    self.result = "lose"
  end
  self.lockedBall = nil
  -- pokered never writes Mimic's copy into the party struct; leaving
  -- battle discards the battle copy, so the original ids come back
  self:restoreMimicked(self.player)
  self:restoreMimicked(self.enemy)
  -- end_of_battle.asm clears wLowHealthAlarm at battle teardown
  require("src.core.Sound").stopLoop("Low_Health_Alarm")
  -- the victory theme already started when the win was decided
  -- (FaintEnemyPokemon .wild_win / TrainerBattleVictory) and loops until
  -- the battle screen closes; leaving battle brings back the map theme,
  -- like the overworld reload's PlayDefaultMusicFadeOutCurrent
  -- (home/overworld.asm:2343-2348)
  require("src.core.Music").restoreMap(self.data)
  self.game.stack:pop()
  Runtime.emit("battle.ended", { battle = self, result = self.result or "run" })
  -- Coming back from the battle screen is a fade, not a cut: EnterMap sees
  -- BIT_BATTLE_OVER_OR_BLACKOUT set and runs MapEntryAfterBattle
  -- (home/overworld.asm:22, :749-753) = GBFadeInFromWhite.  This is the one
  -- choke point every battle -- wild, trainer, walk-up, scripted, link --
  -- passes through on its way out, so the fade is guaranteed here rather
  -- than depending on each caller having wrapped onFinish correctly.
  local result = self.result or "run"
  local onFinish = self.onFinish
  if result == "lose" then
    -- the blackout path warps to the heal point with its own transition
    if onFinish then onFinish(result) end
    return
  end
  self.game.stack:push(require("src.render.Transition").battleReturn(self.game,
    function() if onFinish then onFinish(result) end end))
end

-- ---------------------------------------------------------------------
-- draw
-- ---------------------------------------------------------------------

-- In-battle HUD tiles + the tile HP bar live in src/render/HudTiles.lua
-- (shared with the status screen)
local HudTiles = require("src.render.HudTiles")
local hudTile = HudTiles.tile
local drawHPBar = HudTiles.drawHPBar

-- CenterMonName: 1-2 letter names print two tiles right, 3-4 one tile.
-- Counted in glyphs, not bytes: a nickname carrying "é" or "♂" is one
-- charmap sequence per glyph, and byte length would push it a tile left.
local function nameX(tx, name)
  local n = #Font.split(name)
  return tx * 8 + (n <= 2 and 16 or n <= 4 and 8 or 0)
end

-- Party pokeball row (SetupPokeballs tiles: ball / status ball /
-- fainted ball / empty), 6 slots stepping dx from (x,y).
--
-- GEN 2 COLOUR.  These are not BG tiles on a Game Boy Color: LoadTrainerHudOAM
-- writes all twelve of them into wShadowOAMSprite00 as OBJECT sprites and
-- stamps every one with `ld a, PAL_BATTLE_OB_YELLOW` as its attribute byte
-- (engine/battle/trainer_huds.asm:201-213).  So their colour is fixed --
-- BattleObjectPals' yellow row, white / bright yellow / orange / black -- and
-- has nothing to do with the HP-bar palette the BG zone under them carries.
-- Baked into the grey BG canvas they instead wore whatever the zone pass gave
-- that region, which is why they came out looking flat and grey.
--
-- PAL_BATTLE_OB_GRAY is 2 and BattleObjectPals starts there, so the
-- extractor's row 1 is PAL_BATTLE_OB_YELLOW (3).  The literal below is the
-- ROM's own gfx/battle_anims/battle_anims.pal, byte-identical in Gold and
-- Crystal, through the same round(v * 255 / 31) the extractor uses -- kept as
-- the fallback for a cache written before battle_anims carried the table.
local GEN2_BALL_PAL_INDEX = 1
local GEN2_BALL_PAL = {
  { 255, 255, 255 }, { 255, 255, 58 }, { 255, 132, 8 }, { 0, 0, 0 },
}

-- the ball sprites' OBJ palette, or nil on Gen 1 (where pokered's own
-- SetupPokeballs has no CGB attribute of its own and the SGB zone is right)
function BattleState:gen2BallColors()
  if not require("src.core.GameVersion").isGen2() then return nil end
  local anims = self.data and self.data.battle_anims
  local pals = anims and anims.palettes
  local pal = pals and pals[GEN2_BALL_PAL_INDEX]
  if type(pal) == "table" and #pal >= 4 then return pal end
  return GEN2_BALL_PAL
end

local ballQuads
function BattleState:drawBallRow(party, x, y, dx)
  -- self.deferBalls is set (Gen 2 only) while the colorized classic pipeline
  -- is filling the grey BG canvas: an OBJ sprite belongs OVER the zone pass,
  -- not inside the canvas the zone pass recolors.  drawClassic flushes the
  -- list immediately afterwards, back through this same function.
  if self.deferBalls then
    self.deferBalls[#self.deferBalls + 1] = { party, x, y, dx }
    return
  end
  if ballQuads == nil then
    local ok, img = pcall(love.graphics.newImage, "assets/generated/battle/balls.png")
    if ok then
      ballQuads = { img = img }
      for i = 0, 3 do
        ballQuads[i] = love.graphics.newQuad(i * 8, 0, 8, 8, img:getDimensions())
      end
    else
      ballQuads = false
    end
  end
  if not ballQuads then return end
  -- the sheet is DMG shades; the shade-remap shader paints the OBJ palette on
  -- (a no-op on Gen 1, which has no fixed attribute for these)
  local shader
  local colors = self:gen2BallColors()
  if colors then
    local PaletteFX = require("src.render.PaletteFX")
    shader = PaletteFX.shader()
    if shader then
      love.graphics.setShader(shader)
      PaletteFX.sendColors(shader, colors)
    else
      shader = nil
    end
  end
  for i = 1, 6 do
    local mon = party[i]
    local tile = not mon and 3 or mon.hp <= 0 and 2 or mon.status and 1 or 0
    love.graphics.draw(ballQuads.img, ballQuads[tile], x + (i - 1) * dx, y)
  end
  if shader then love.graphics.setShader() end
end

-- the grow-in scale for a battler's pic this frame: nil when not
-- growing, else 0 (ball beat) / 3/7 / 5/7 -- AnimateSendingOutMon's
-- stages (core.asm:6801-6838): 3 frames of the ball tile, 4 frames of
-- a 3x3 block of the 7x7 pic tiles, 5 frames of 5x5, then full size
function BattleState:growInScale(battler)
  local grow = self.growIn
  if not grow or grow.battler ~= battler then return nil end
  local f = grow.frame
  return f < 3 and 0 or f < 7 and 3 / 7 or 5 / 7
end

-- battler hidden this frame? (damage blink)
--
-- AnimationBlinkMon hides the pic, waits DelayFrames 5, shows it, waits
-- DelayFrames 5, six times over (animations.asm:1360-1376) -- a 10-frame
-- period, not 8.  With Timing.BLINK_MON that is exactly six blinks.
function BattleState:fxHidden(battler)
  local fx = self.fx
  if fx and fx.blink and fx.blink.target == battler and fx.blink.frames > 0 then
    return self.frame % 10 < 5
  end
  return false
end

-- is the faint slide currently playing for this battler?
function BattleState:fxFaintActive(battler)
  local fx = self.fx
  return fx and fx.faint and fx.faint.battler == battler
         and fx.faint.frames > 0 or false
end

-- vertical slide offset for a fainting battler.  The offset is in screen
-- pixels, so it scales with the pic's draw scale (the player's default 2x
-- sinks 2x as fast to sink at the same visual rate); a mod scale composes
-- the same way.  scale defaults to the vanilla side scale when unknown.
-- SlideDownFaintedMonPic drops the pic one 8px row per 2-frame step, so
-- the offset advances Timing.FAINT_SLIDE_STEP (4px) per frame at 1x --
-- the full 56px PIC_HEIGHT slide over the 14-frame budget (#671: the
-- old (30 - frames) math teleported the sprite 32px down on frame one).
function BattleState:fxFaintOffset(battler, scale)
  local fx = self.fx
  if self:fxFaintActive(battler) then
    scale = scale or (battler.isPlayer and 2 or 1)
    return (Timing.FAINT_SLIDE - fx.faint.frames) * Timing.FAINT_SLIDE_STEP * scale
  end
  return 0
end

-- Substitute doll (AnimationSubstitute, engine/battle/animations.asm):
-- while a battler's substitute is up, its pic is replaced by the mini
-- doll from gfx/sprites/monster.png -- the facing-DOWN frame for the
-- enemy, facing-UP for the player, a 16x16 sprite at pic tiles
-- (2..3,4..5) / (3..4,4..5) of the 7x7 frame: screen (112,32) enemy,
-- (32,72) player.
local substDoll
function BattleState:drawSubstituteDoll(battler)
  if substDoll == nil then
    local ok, img = pcall(love.graphics.newImage,
                          "assets/generated/sprites/monster.png")
    if ok then
      local w, h = img:getDimensions()
      substDoll = { img = img,
                    down = love.graphics.newQuad(0, 0, 16, 16, w, h),
                    up = love.graphics.newQuad(0, 16, 16, 16, w, h) }
    else
      substDoll = false
    end
  end
  if not substDoll then return end
  -- in colorized mode the doll (drawn from BG tiles on the GB) takes
  -- its screen zone's SGB palette like everything else in the region
  local shader
  if self:colorMode() then
    local PaletteFX = require("src.render.PaletteFX")
    shader = PaletteFX.shader()
    if shader then
      local colors = self:zoneColorsAt(battler.isPlayer and 32 or 112,
                                       battler.isPlayer and 72 or 32)
      if colors then
        love.graphics.setShader(shader)
        PaletteFX.sendColors(shader,
          require("src.render.PaletteFX").permute(colors, self:activeBgp()))
      else
        shader = nil
      end
    end
  end
  if battler.isPlayer then
    love.graphics.draw(substDoll.img, substDoll.up, 32, 72)
  else
    love.graphics.draw(substDoll.img, substDoll.down, 112, 32)
  end
  if shader then love.graphics.setShader() end
end

-- MinimizedMonSprite (animations.asm:1745): the 8x5 blob that replaces
-- a minimized mon's pic, written at pic tile (3,4)+2px.  Rows are bit
-- patterns, drawn as shade-3 pixels.
local MINIMIZED_ROWS = {
  { 3, 4 },          -- ...XX...
  { 2, 5 },          -- ..XXXX..
  { 1, 6 },          -- .XXXXXX.
  { 2, 5 },          -- ..XXXX..
  { 2, 2, 5, 5 },    -- ..X..X..
}
function BattleState:drawMinimizedBlob(battler, x, y)
  local r, g, b, a = love.graphics.getColor()
  local col = { 0, 0, 0, 1 }
  local pals = self:colorMode() and self:sgbBattlePals()
  if pals then
    local P = pals[battler.isPlayer and 2 or 3]
    local shade = P[4]
    col = { shade[1] / 255, shade[2] / 255, shade[3] / 255, 1 }
  end
  love.graphics.setColor(col)
  for row, runs in ipairs(MINIMIZED_ROWS) do
    for i = 1, #runs, 2 do
      love.graphics.rectangle("fill", x + 24 + runs[i], y + 34 + row - 1,
                              runs[i + 1] - runs[i] + 1, 1)
    end
  end
  love.graphics.setColor(r, g, b, a)
end

-- Draw a battler pic, sinking it behind its own baseline while the
-- faint slide plays (pokered's AnimationSlideMonDown); a fainted
-- battler stays hidden once the slide ends.  A standing substitute
-- shows the mini doll instead of the mon's own pic.  The SE-driven
-- pic effects (slides/squish/blink/minimize; see applyAnimEffect)
-- offset, clip or replace the pic, and an active BGP fade swaps in a
-- shade-remapped recolor of it.
-- BATTLE PKMN = STADIUM: the player's own Stadium 2 model standing in for the
-- cartridge pic, in the pic's own footprint so every placement, scale and HUD
-- clip around it is unchanged.
--
-- Deliberately only on the UNDISTURBED frame.  Its caller has already handled
-- the substitute doll, the faint slide and the palette fade, and every pic
-- effect below it -- slideOff, bounce, minimize, the SE displacements -- is
-- authored against a flat pic in tile space.  A model has no frames for any of
-- those, so anything mid-effect keeps the cartridge pic and the two never
-- disagree about where the Pokemon is.  In practice that means the model is
-- what you look at between animations, which is when you are looking.
--
-- One resident rig per battler, so a switch retires the old model with the
-- battler it belonged to.
--
-- KNOWN GAP: the mod's preview renderer only offers a front, camera-facing
-- view, so the player's side shows its model's face rather than its back.
-- There is no yaw control on that API to pass; when there is, it goes in the
-- frameOpts below and the back view costs one argument.
function BattleState:drawStadiumBattlerPic(battler, img, x, y, scale)
  if not (battler and img) then return false end
  local StadiumArt = require("src.render.StadiumArt")
  if StadiumArt.battleMode(self.game) ~= "stadium" then return false end
  local mon = battler.mon
  if not (mon and mon.species) then return false end
  local key = StadiumArt.keyFor(self.game, self, battler)
  if not key then return false end
  local w = img:getWidth() * (scale or 1)
  local h = img:getHeight() * (scale or 1)
  return StadiumArt.drawInto(self.game, key, mon, x, y, w, h)
end

-- Emerald's procedural animation moves the SPRITE, not its pixels, and it
-- moves it about the pic's BOTTOM CENTRE -- the point the mon stands on.
-- That is what makes a squash compress downwards instead of about the middle
-- of the picture, and a rotation pivot on the feet rather than the navel.
--
-- The colour routines (GLOW_*, FLASH_YELLOW) blend the sprite's palette
-- toward a colour on hardware; the same pic drawn again in that colour, at
-- the blend's strength, is what that looks like.
local function drawMonAnimated(battler, img, x, y, scale)
  local anim = battler and battler.monAnim
  local tf = anim and anim:transform()
  if not tf or (tf.dx == 0 and tf.dy == 0 and tf.sx == 1 and tf.sy == 1
                and tf.rot == 0 and tf.alpha == 1 and not tf.tint) then
    love.graphics.draw(img, x, y, 0, scale, scale)
    return
  end
  local w, h = img:getWidth(), img:getHeight()
  local cx = x + w * scale / 2 + (tf.dx or 0) * scale
  local cy = y + h * scale + (tf.dy or 0) * scale
  local r, g, b, a = love.graphics.getColor()
  if tf.alpha ~= 1 then love.graphics.setColor(r, g, b, a * tf.alpha) end
  love.graphics.draw(img, cx, cy, tf.rot, scale * tf.sx, scale * tf.sy,
                     w / 2, h)
  local tint = tf.tint
  if tint then
    love.graphics.setColor(tint[1], tint[2], tint[3], a * (tint[4] or 1))
    love.graphics.draw(img, cx, cy, tf.rot, scale * tf.sx, scale * tf.sy,
                       w / 2, h)
  end
  love.graphics.setColor(r, g, b, a)
end

BattleState.drawMonAnimated = drawMonAnimated

-- HOW FAR A GEN 3 MOVE HAS SHOVED THIS POKEMON OUT OF ITS PLACE.
--
-- AnimTask_ShakeMon writes the battler's OWN sprite offset, so the flinch has
-- to happen where the mon is drawn rather than as a particle laid over it --
-- which is why it is here and not in Gen3MoveAnim's own draw.
function BattleState:gen3AnimShake(battler)
  if not (self.gen3AnimPlaying and self.gen3Anim and battler) then
    return 0, 0
  end
  local ok, dx, dy = pcall(self.gen3Anim.monOffset, self.gen3Anim,
                           battler == self.player)
  if not ok then return 0, 0 end
  return dx or 0, dy or 0
end

-- ...AND WHAT COLOUR IT HAS BEEN WASHED.
--
-- BlendPalettes lerps the battler's own palette toward a colour, which two
-- draws reproduce exactly: the sprite dimmed by (1 - c), and the colour added
-- back at c through the sprite's own alpha.
function BattleState:gen3AnimTint(battler)
  if not (self.gen3AnimPlaying and self.gen3Anim and battler) then return nil end
  if not love.graphics.setBlendMode then return nil end
  local ok, r, g, b, c = pcall(self.gen3Anim.monTint, self.gen3Anim,
                               battler == self.player)
  if not (ok and c and c > 0) then return nil end
  return r, g, b, c
end

-- ...AND THE COPIES OF IT.
--
-- DOUBLE TEAM makes two ghosts of the attacker and swings them sideways in
-- opposite phase; the import reads the cartridge's own numbers for that and
-- Gen3MoveAnim:monGhosts works the arithmetic (see both).  They are the mon's
-- own picture drawn again at an x offset, which is what the hardware does --
-- the copies are sprites sharing the attacker's tiles on a palette of their
-- own.
function BattleState:gen3AnimGhosts(battler)
  if not (self.gen3AnimPlaying and self.gen3Anim and battler) then return nil end
  if not self.gen3Anim.monGhosts then return nil end
  local ok, list = pcall(self.gen3Anim.monGhosts, self.gen3Anim,
                         battler == self.player)
  if not (ok and type(list) == "table" and #list > 0) then return nil end
  return list
end

-- ...AND HOW BIG IT IS.
--
-- MINIMIZE hands the attacker's sprite to SetSpriteRotScale every frame; the
-- import reads that task's whole state machine and Gen3MoveAnim:monScale
-- walks it (see both).  What comes back is a multiplier, 1 being life size.
function BattleState:gen3AnimScale(battler)
  if not (self.gen3AnimPlaying and self.gen3Anim and battler) then return nil end
  if not self.gen3Anim.monScale then return nil end
  local ok, mul = pcall(self.gen3Anim.monScale, self.gen3Anim,
                        battler == self.player)
  if not (ok and type(mul) == "number" and mul > 0 and mul < 1) then
    return nil
  end
  return mul
end

-- ...AND WHETHER IT IS TIPPED OVER.
--
-- WITHDRAW hands the attacker's sprite to the same helper MINIMIZE uses, with
-- a rotation instead of a scale; the import reads its three states and
-- Gen3MoveAnim:monRotate walks them (see both).  What comes back is radians
-- and a rise in pixels.
function BattleState:gen3AnimRotate(battler)
  if not (self.gen3AnimPlaying and self.gen3Anim and battler) then return nil end
  if not self.gen3Anim.monRotate then return nil end
  local ok, angle, rise = pcall(self.gen3Anim.monRotate, self.gen3Anim,
                                battler == self.player)
  if not (ok and type(angle) == "number" and angle ~= 0) then return nil end
  return angle, tonumber(rise) or 0
end

-- A WRAPPER, and not a line inside the draw below, because that draw has
-- eight early returns down its length -- the substitute doll, the faint
-- wipe, the fade, the stadium path -- and a transform pushed at the top of it
-- would be left on the stack by any one of them.  The rotation belongs around
-- the whole thing or nowhere.
-- ...AND WHETHER IT IS SQUASHED.
--
-- SPLASH, MEDITATE and TELEPORT run an affine table the cartridge keeps as
-- data; Gen3MoveAnim:monAffine walks it (see both).  Two multipliers come
-- back, not one, because the table moves the axes independently.
function BattleState:gen3AnimSquash(battler)
  if not (self.gen3AnimPlaying and self.gen3Anim and battler) then return nil end
  if not self.gen3Anim.monAffine then return nil end
  local ok, sx, sy = pcall(self.gen3Anim.monAffine, self.gen3Anim,
                           battler == self.player)
  if not (ok and type(sx) == "number" and type(sy) == "number") then
    return nil
  end
  if math.abs(sx - 1) < 1e-6 and math.abs(sy - 1) < 1e-6 then return nil end
  return sx, sy
end

function BattleState:drawBattlerPic(battler, x, y, scale)
  local angle, rise = self:gen3AnimRotate(battler)
  local sqx, sqy = self:gen3AnimSquash(battler)
  if not (angle or sqx) then
    return self:drawBattlerPicAt(battler, x, y, scale)
  end
  local pic = self:battlerPic(battler)
  local w = (pic and pic.getWidth and pic:getWidth() or 0) * scale
  local h = (pic and pic.getHeight and pic:getHeight() or 0) * scale
  local g = love.graphics
  g.push()
  -- A SQUASH KEEPS ITS FEET ON THE PLATFORM.  The hardware scales an affine
  -- sprite about its centre and then moves it back down by half of what it
  -- lost, which comes to the bottom edge staying where it was -- and a
  -- Pokemon that sinks into the ground when it flattens looks wrong in a way
  -- centring alone does not fix.  So the pivot for the scale is the middle of
  -- the foot of the picture.
  if sqx then
    g.translate(x + w / 2, y + h)
    g.scale(sqx, sqy)
    g.translate(-(x + w / 2), -(y + h))
  end
  -- ...and the rotation IS about the centre, because that is the one the
  -- hardware turns about and a tipping Pokemon pivots on its middle.
  if angle then
    local cx, cy = x + w / 2, y + h / 2
    g.translate(cx, cy - (rise or 0))
    g.rotate(angle)
    g.translate(-cx, -cy)
  end
  local ok, err = pcall(self.drawBattlerPicAt, self, battler, x, y, scale)
  g.pop()
  if not ok then error(err) end
end

function BattleState:drawBattlerPicAt(battler, x, y, scale)
  local shakeX, shakeY = self:gen3AnimShake(battler)
  x, y = x + shakeX, y + shakeY
  -- ...and how big it is.  The hardware scales an affine sprite about its own
  -- CENTRE, so shrinking here has to move the picture back in by half of what
  -- it lost, or the Pokemon shrinks toward its top-left corner and slides off
  -- its own platform.
  local shrink = self:gen3AnimScale(battler)
  if shrink then
    local pic = self:battlerPic(battler)
    if pic and pic.getWidth then
      local w, h = pic:getWidth() * scale, pic:getHeight() * scale
      x = x + (w - w * shrink) / 2
      y = y + (h - h * shrink) / 2
      scale = scale * shrink
    end
  end
  -- the ghosts go down FIRST, so the Pokemon itself stays on top of its own
  -- copies rather than being hidden behind them
  local ghosts = self:gen3AnimGhosts(battler)
  if ghosts and not battler.fainted and not self:fxFaintActive(battler)
     and not battler.substituteHP then
    local img = self:battlerPic(battler)
    if img then
      local cr, cg, cb, ca = love.graphics.getColor()
      for _, ghost in ipairs(ghosts) do
        if (ghost.x or 0) ~= 0 then
          love.graphics.setColor(cr, cg, cb, ca * (ghost.alpha or 0.5))
          love.graphics.draw(img, x + (ghost.x or 0), y, 0, scale, scale)
        end
      end
      love.graphics.setColor(cr, cg, cb, ca)
    end
  end
  local img = self:battlerPic(battler)
  if battler.substituteHP and not self:fxFaintActive(battler)
     and not battler.fainted then
    self:drawSubstituteDoll(battler)
    return
  end
  if self:fxFaintActive(battler) then
    local off = self:fxFaintOffset(battler, scale)
    local visible = img:getHeight() - math.floor(off / scale)
    if visible > 0 then
      local quad = love.graphics.newQuad(0, 0, img:getWidth(), visible,
                                         img:getWidth(), img:getHeight())
      love.graphics.draw(img, quad, x, y + off, 0, scale, scale)
    end
    return
  end
  if battler.fainted then return end

  -- MarowakAnim's rOBP1 fades (updateFx): alpha over the paper is what those
  -- palette shifts look like, and the test has to sit ahead of the plain
  -- fast path below (#492)
  local fadePf = self.picFx and self.picFx[battler]
  if fadePf and fadePf.fade then
    local cr, cg, cb, ca = love.graphics.getColor()
    love.graphics.setColor(cr, cg, cb, ca * fadePf.fade)
    love.graphics.draw(img, x, y, 0, scale, scale)
    love.graphics.setColor(cr, cg, cb, ca)
    return
  end

  local pf = self.picFx and self.picFx[battler]
  if not pf or (not pf.kind and not pf.hidden and not pf.minimized
                and (pf.ox or 0) == 0 and (pf.oy or 0) == 0) then
    if self:drawStadiumBattlerPic(battler, img, x, y, scale) then return end
    local tr, tg, tb, tc = self:gen3AnimTint(battler)
    if tc then
      local cr, cg, cb, ca = love.graphics.getColor()
      local keep = 1 - tc
      love.graphics.setColor(cr * keep, cg * keep, cb * keep, ca)
      drawMonAnimated(battler, img, x, y, scale)
      love.graphics.setBlendMode("add")
      love.graphics.setColor(tr * tc, tg * tc, tb * tc, ca)
      drawMonAnimated(battler, img, x, y, scale)
      love.graphics.setBlendMode("alpha")
      love.graphics.setColor(cr, cg, cb, ca)
      return
    end
    drawMonAnimated(battler, img, x, y, scale)
    return
  end
  if pf.hidden then return end
  if pf.minimized then
    self:drawMinimizedBlob(battler, x, y)
    return
  end

  local w, h = img:getWidth(), img:getHeight()
  local ox, oy = pf.ox or 0, pf.oy or 0
  local k, t = pf.kind, pf.t or 0
  local xscale = 1
  -- while an SE effect displaces the pic, confine it to its side's
  -- tile window like the GB tilemap does (the pic can never overwrite
  -- the HUD columns or the text box rows)
  -- ...except under the widescreen layout, where the side's own region
  -- scissor is already that window on a battlefield the classic tile
  -- columns do not describe (an 88..160 clip would fall entirely outside
  -- the enemy's region and erase the pic).
  local clip = love.graphics.setScissor and love.graphics.intersectScissor
                 and not self.wideRegion
  local scx, scy, scw, sch
  if clip then
    scx, scy, scw, sch = love.graphics.getScissor()
    if battler.isPlayer then
      love.graphics.intersectScissor(0, 0, 80, 96)
    else
      love.graphics.intersectScissor(88, 0, 72, 56)
    end
  end
  if k == "slideOff" then
    -- one tile (8px) toward the mon's own screen edge per 3 frames
    local dir = battler.isPlayer and -1 or 1
    ox = ox + dir * 8 * math.min(8, math.floor(t / 3) + 1)
  elseif k == "slideHalf" then
    local dir = battler.isPlayer and -1 or 1
    ox = ox + dir * 8 * math.min(4, math.floor(t / 4) + 1)
  elseif k == "slideDown" then
    oy = oy + 8 * math.min(7, math.floor(t / 3) + 1)
  elseif k == "slideDownHide" then
    oy = oy + 16 * (math.floor(t / 8) + 1)
  elseif k == "bounce" then
    -- 5 back-to-back AnimationSlideMonDown passes
    oy = oy + 8 * math.min(7, math.floor((t % 21) / 3) + 1)
  elseif k == "shakeBF" then
    ox = ox + ((math.floor(t / 3) % 2 == 0) and -8 or 8)
  elseif k == "squish" then
    xscale = math.max(0, 7 - 2 * (math.floor(t / 6) + 1)) / 7
  elseif k == "blink" then
    -- skip; falls through to the scissor-restore below instead of an
    -- early return that would leave the pic-window scissor stuck
  end

  local skipDraw = (k == "squish" and xscale <= 0)
                    or (k == "blink" and math.floor(t / 5) % 2 == 0)

  if skipDraw then
    -- draw nothing this frame, but still restore the scissor rect
  elseif oy > 0 then
    -- sink below the baseline (AnimationSlideMonDown-style row clip)
    local visible = h - math.floor(oy / scale)
    if visible > 0 then
      local quad = love.graphics.newQuad(0, 0, w, visible, w, h)
      love.graphics.draw(img, quad, x + ox, y + oy, 0, scale, scale)
    end
  elseif k == "slideUp" then
    -- AnimationSlideMonUp (animations.asm): 7 row steps x 2f. After Dig's
    -- SLIDE_DOWN the tilemap is blank; each step fills the next bottom
    -- row so the mon emerges from underground. A cyclic wrap of a full
    -- pic looked like a bounce at Dig's end (#100).
    local step = math.min(7, math.floor((t - 1) / 2) + 1)
    local visible = math.floor(h * step / 7)
    if visible > 0 then
      local quad = love.graphics.newQuad(0, h - visible, w, visible, w, h)
      love.graphics.draw(img, quad, x + ox,
                         y + (h - visible) * scale, 0, scale, scale)
    end
  elseif xscale < 1 then
    -- AnimationSquishMonPic: columns collapse toward the middle
    love.graphics.draw(img, x + w * scale * (1 - xscale) / 2, y,
                       0, scale * xscale, scale)
  else
    love.graphics.draw(img, x + ox, y + oy, 0, scale, scale)
  end
  if clip then
    if scx then
      love.graphics.setScissor(scx, scy, scw, sch)
    else
      love.graphics.setScissor()
    end
  end
end

-- ------------------------------------------------------------------
-- SGB battle colorization.  SetPal_Battle (engine/gfx/palettes.asm:28)
-- assigns pal 0 = player HP-bar palette, pal 1 = enemy HP-bar palette,
-- pal 2 = player mon palette, pal 3 = enemy mon palette;
-- BlkPacket_Battle (data/sgb/sgb_packets.asm:65) maps them onto screen
-- regions.  The BG layer is drawn in DMG grays to a canvas and each
-- region is recolored through the PaletteFX shader; the OAM anim
-- sprites are colored per sprite afterwards (BGP fades never touch
-- them, matching the hardware).
-- ------------------------------------------------------------------

-- BlkPacket_Battle ATTR_BLK data: pal slot + inclusive tile rect.
-- The first entry is the %111 outside fill; the blocks are disjoint.
local BATTLE_ZONES = {
  { pal = 0, 0, 0, 19, 17 },  -- everything else
  { pal = 1, 1, 0, 10, 3 },   -- enemy HUD
  { pal = 0, 10, 7, 19, 10 }, -- player HUD
  { pal = 2, 0, 4, 8, 11 },   -- player mon
  { pal = 3, 11, 0, 19, 6 },  -- enemy mon
  { pal = 2, 0, 12, 19, 17 }, -- message box
}

-- Gen2 only.  The exp bar row is its own BG attribute carrying
-- ExpBarPalette (LoadHPBar loads it beside the HP bar's), which the SGB
-- packet had no fifth slot for -- so it rides on the end of the list,
-- where it overdraws the catch-all zone the row would otherwise take.
--
-- The zone is as wide as the bar: Prism's is nine tiles rather than Crystal's
-- eight (_CGB_BattleColors fills `lb bc, 1, 9` at hlcoord 10,11 with BG
-- attribute 4), so a fixed right edge left its last tile wearing the player's
-- HP-bar colour.
local function gen2ExpZone()
  local tiles = require("src.render.HudTiles").geometry().expBarTiles
  return { pal = 4, 10, 11, 9 + tiles, 11 }
end

-- the colorizer needs canvases + shaders + pixel access (headless
-- stubs and stripped-down builds fall back to the flat colored path)
function BattleState:colorMode()
  if self.colorFxReady == nil then
    local ready = false
    local g = love and love.graphics
    local PaletteFX = require("src.render.PaletteFX")
    if g and g.newCanvas and g.setScissor and g.setShader and g.getCanvas
       and love.image and PaletteFX.pack(self.data)
       and PaletteFX.shader() then
      -- 160x144 real pixels, not DPI units, or the colored battle background
      -- resamples against the UI canvas on mobile (#208; PixelCanvas.lua)
      local PixelCanvas = require("src.render.PixelCanvas")
      local ok1, bg = pcall(PixelCanvas.new, 160, 144)
      local ok2, wv = pcall(PixelCanvas.new, 160, 144)
      if ok1 and ok2 and bg and wv then
        self.bgCanvas, self.waveCanvas = bg, wv
        ready = true
      end
    end
    self.colorFxReady = ready
  end
  return self.colorFxReady
end

-- The four SGB palettes SetPal_Battle would currently send: bar
-- palettes track the drawn HP bars (GetHealthBarColor), the mon slots
-- hold MonsterPalettes[wBattleMonSpecies]/[wEnemyMonSpecies2] --
-- PAL_MEWMON (= MonsterPalettes[0]) while a side still shows its
-- trainer/back pic (the species bytes are 0 then).
function BattleState:sgbBattlePals()
  local PaletteFX = require("src.render.PaletteFX")
  local pack = PaletteFX.pack(self.data)
  local pals = pack and pack.palettes
  if not pals then return nil end
  -- HandlePlayerBlackOut (core.asm:1151) runs SET_PAL_BATTLE_BLACK:
  -- SetPal_BattleBlack sends PalPacket_Black, PAL_BLACK in all four slots of
  -- BlkPacket_Battle (engine/gfx/palettes.asm:22-25), so every zone of the
  -- battle screen -- both HP bars and both mon regions -- goes dark behind
  -- the blackout text.  picImage re-bakes the pics through the same palette,
  -- since those draw over the zone pass rather than through it (#292).
  if self.blackedOut and pals.BLACK then
    local b = pals.BLACK
    return { [0] = b, [1] = b, [2] = b, [3] = b }
  end
  local function bar(b)
    if not b then return pals.GREENBAR end
    local hp = b.shownHP or b.mon.hp
    return pals[PaletteFX.barPalName(hp, b.mon.stats.hp)] or pals.GREENBAR
  end
  local function mon(b, placeholder)
    if placeholder or not b then return pals.MEWMON or pals.GREENBAR end
    return PaletteFX.monPal(self.data, b.mon.species, nil,
      require("src.pokemon.Pokemon").isShiny(b.mon)) or pals.MEWMON
  end
  local out = {
    [0] = bar(self.player),
    [1] = bar(self.enemy),
    [2] = mon(self.player,
              self.showPlayerBack or self.safari or self:demoHidesPlayer()),
    [3] = mon(self.enemy, self.showEnemyTrainer),
    -- ...through PaletteFX.pal, not off `pals` directly: under RED++ the
    -- active pack is pokered's GBC table, which has no EXPBAR, and a nil here
    -- dropped GEN2_EXP_ZONE out of drawZonePass entirely -- so the exp bar row
    -- fell through to zone 0 and wore the player's HP-bar colour, turning
    -- green, yellow and red with the HP instead of staying blue.  pal() falls
    -- back to the ROM pack for exactly this case.
    [4] = pals.EXPBAR or PaletteFX.pal(self.data, "EXPBAR"),
  }
  -- OG RED: the Game Boy Color drew the whole battle from one BG palette --
  -- white paper, black ink -- so every zone shares the same background and
  -- outline; only the two mid shades differ per element (green HP bar, red
  -- mon pic).  The bar/base zones otherwise carry the SGB off-white
  -- (255,239,255) as color 0 while the mon zones (monPal -> GBC_BG) carry a
  -- true white, which is what drew a white box around each pic on the pink
  -- field.  Snap every zone's color 0/3 to the global GBC white/black; the
  -- mid shades (and the green bar the user prefers) stay untouched.
  -- Boot-ROM OG only (Red/Blue): snap zone paper to the global GBC white/black.
  -- OG YELLOW keeps each CGBBasePalettes endpoint (already near-white / near-black).
  if PaletteFX.mode == "ogred" and not require("src.core.GameVersion").isYellow() then
    local white, black = PaletteFX.GBC_BG[1], PaletteFX.GBC_BG[4]
    for i = 0, 3 do
      local c = out[i]
      out[i] = { white, c[2], c[3], black }
    end
  end
  return out
end

-- the SGB palette covering a screen pixel (BlkPacket_Battle regions)
function BattleState:zoneColorsAt(x, y)
  local pals = self:sgbBattlePals()
  if not pals then return nil end
  local tx = math.floor(x / 8)
  local ty = math.floor(y / 8)
  if ty >= 12 then return pals[2] end                      -- message box
  if tx >= 11 and ty <= 6 then return pals[3] end          -- enemy mon
  if tx <= 8 and ty >= 4 and ty <= 11 then return pals[2] end -- player mon
  if tx >= 1 and tx <= 10 and ty <= 3 then return pals[1] end -- enemy HUD
  return pals[0]
end

-- AnimationWavyScreen's per-scanline SCX offsets
-- (WavyScreenLineOffsets, animations.asm:1926)
local WAVY_OFFSETS = { 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1,
                       0, 0, 0, 0, 0, -1, -1, -1, -2, -2, -2, -2, -2,
                       -1, -1, -1 }

-- wave the BG canvas one scanline at a time; the offset table walks
-- one entry per frame like the asm's advancing pointer
function BattleState:applyWavy(src)
  local wavy = self.fx and self.fx.wavy
  if not wavy then return src end
  local g = love.graphics
  local prev = g.getCanvas()
  g.setCanvas(self.waveCanvas)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", 0, 0, 160, 144)
  self.waveQuad = self.waveQuad or g.newQuad(0, 0, 160, 1, 160, 144)
  for line = 0, 143 do
    self.waveQuad:setViewport(0, line, 160, 1)
    g.draw(src, self.waveQuad,
           WAVY_OFFSETS[(line + wavy.phase) % 32 + 1], line)
  end
  g.setCanvas(prev)
  return self.waveCanvas
end

-- recolor the grayscale BG canvas per zone; an active BGP fade permutes
-- the zone palette (the SGB colors the remapped DMG shade).  A window
-- shake draws only the offset copy: the baked canvas holds the HUDs and
-- text box (window-layer content), so compositing an unshifted copy
-- underneath ghosted every name in the vacated strip (#295).  The strip
-- shows blank color 0 instead, like the hardware revealing empty BG.
function BattleState:drawZonePass(src, sx, sy)
  local PaletteFX = require("src.render.PaletteFX")
  local shader = PaletteFX.shader()
  -- sgbBattlePals returns nil outright when the active pack has no palette
  -- table at all; the zone loop below then indexed nil. Same failure class as
  -- the per-zone nil, one level up.
  local pals = self:sgbBattlePals() or {}
  local bgp = self:activeBgp()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader(shader)
  local shaking = sx ~= 0 or sy ~= 0
  local zones = BATTLE_ZONES
  if pals[4] and self.player and not (self.safari or self:demoHidesPlayer())
     and require("src.core.GameVersion").isGen2() then
    zones = {}
    for i, z in ipairs(BATTLE_ZONES) do zones[i] = z end
    zones[#zones + 1] = gen2ExpZone()
  end
  for _, z in ipairs(zones) do
    -- ...and a zone whose palette the pack does not name falls back to the
    -- four DMG grays rather than to nil. Prism's pack carries neither MEWMON
    -- nor GREENBAR -- the last fallbacks sgbBattlePals itself reaches for --
    -- so a zone could resolve to nil and every frame of the battle died in
    -- permute. Gray is the honest answer for "this pack named no colour
    -- here": the art is grayscale before colorization, so the zone simply
    -- draws unshaded instead of taking the game down.
    PaletteFX.sendColors(shader,
      PaletteFX.permute(pals[z.pal] or PaletteFX.GRAYS, bgp))
    local zx, zy = z[1] * 8, z[2] * 8
    local zw, zh = (z[3] - z[1] + 1) * 8, (z[4] - z[2] + 1) * 8
    love.graphics.setScissor(zx, zy, zw, zh)
    if shaking then
      love.graphics.rectangle("fill", zx, zy, zw, zh)
      love.graphics.draw(src, sx, sy)
    else
      love.graphics.draw(src, 0, 0)
    end
  end
  love.graphics.setScissor()
  love.graphics.setShader()
end

-- colors for one anim-layer OAM sprite at screen pixel (px, py): the
-- zone palette under that pixel's 8x8 attribute cell (the SGB colors
-- the composited picture per cell, so AnimPlayer samples once per cell
-- the tile overlaps), through the OBJ palette the routine ran with
-- (SetAnimationPalette: wAnimPalette = $f0 on SGB, rOBP1 = $6c,
-- ambient rOBP0 = $e4)
local OBJ_SHADES = {
  f0 = { 0, 3, 3 },   -- color 1 -> shade 0, colors 2/3 -> shade 3
  f0x = { 3, 0, 3 },  -- $f0 xor %00111100 = $cc: the Master/Ultra ball
                      -- toss flicker (DoBallTossSpecialEffects)
  e4 = { 1, 2, 3 },   -- identity
  obp1 = { 3, 2, 1 }, -- $6c
}
function BattleState:animSpriteColors(s, px, py)
  local P = self:zoneColorsAt(px or (s.x - 8 + 4), py or (s.y - 16 + 4))
  if not P then return nil end
  local m = OBJ_SHADES[s.obp or "f0"] or OBJ_SHADES.f0
  local function c(shade)
    local col = P[shade + 1]
    return { col[1] / 255, col[2] / 255, col[3] / 255 }
  end
  return { c(m[1]), c(m[2]), c(m[3]) }
end

-- the OAM anim layer (subanimation sprites / the resting caught ball)
function BattleState:drawAnimLayer(colorized)
  -- EMERALD'S OWN, and reached through this method rather than around it.
  -- Gen3Battle.draw used to call its layer functions directly, which meant a
  -- mod wrapping this name never saw a Gen 3 battle at all.
  if self:gen3Layout() then return Gen3Battle.drawAnimationLayer(self) end
  local colorFn
  if colorized then
    colorFn = function(s, px, py) return self:animSpriteColors(s, px, py) end
  end
  if self.animPlaying and self.animPlayer then
    love.graphics.setColor(1, 1, 1, 1)
    pcall(self.animPlayer.draw, self.animPlayer, colorFn)
  elseif self.lockedBall and self.animPlayer then
    -- the resting closed ball stays on screen through the caught text
    -- (the $43 chain ends after SHAKE_ANIM and the GB never clears the
    -- ball's OAM entries until the battle screen is torn down)
    love.graphics.setColor(1, 1, 1, 1)
    pcall(self.animPlayer.drawSprites, self.animPlayer, self.lockedBall,
          colorFn)
  end
end

-- ------------------------------------------------------------------
-- Mod-facing battle sprite scaling.  The enemy front pic draws at 1x and
-- the player back pic at 2x on the GB; a mod can override either per
-- species (pokemon.battleScaleFront / battleScaleBack) or per image path
-- (the battle_sprite_scales registry, which is the only handle on the
-- non-species pics like the trainer back).  These resolvers and the
-- placement math are pure (no love.*) so the grounding contract -- feet
-- pinned at any scale -- is unit-tested directly.
-- ------------------------------------------------------------------

-- the vanilla scale for a side: enemy front 1x, player back 2x
BattleState.BATTLE_SCALE_DEFAULT = { front = 1, back = 2 }
-- Gen2 stores back pics at 6x6 tiles and draws them 1:1 at hlcoord 1,6;
-- only Gen1's 4x4 rips are doubled.
BattleState.BATTLE_SCALE_GEN2 = { front = 1, back = 1 }
-- ...and Gen 3's are 64x64, which is bigger again.  Doubled they are 128
-- pixels tall on a 160-pixel screen: the player's Pokemon filled half the
-- field and ran off the bottom through the message window.
BattleState.BATTLE_SCALE_GEN3 = { front = 1, back = 1 }

-- image-level override for an asset path, or nil.  scales is the merged
-- data.battle_sprite_scales table (record id -> { path, scale }).
function BattleState.imageBattleScale(scales, path)
  if not scales or not path then return nil end
  for id, rec in pairs(scales) do
    if id ~= "_owners" and type(rec) == "table" and rec.path == path then
      return rec.scale
    end
  end
  return nil
end

-- effective battle scale for a pic: image-level override, else the
-- species-level override for the side, else the side default.  side is
-- "front" (enemy) or "back" (player); species may be nil (a non-species
-- pic like the trainer back, which only image-level scaling reaches).
function BattleState.resolveBattleScale(data, side, path, species)
  local img = data and BattleState.imageBattleScale(data.battle_sprite_scales, path)
  if img then return img end
  local def = species and data and data.pokemon and data.pokemon[species]
  local field = side == "back" and "battleScaleBack" or "battleScaleFront"
  local override = def and def[field]
  if override then return override end
  local V = require("src.core.GameVersion")
  local defaults = BattleState.BATTLE_SCALE_DEFAULT
  if V.isGen3() then
    defaults = BattleState.BATTLE_SCALE_GEN3
  elseif V.isGen2() then
    defaults = BattleState.BATTLE_SCALE_GEN2
  end
  return defaults[side] or 1
end

-- Player (back) placement: feet flush on the text-box top (y=96) at any
-- scale, with the left transparent columns pulled back so opaque pixels
-- land where hardware's white-on-white columns left them.  Returns the
-- top-left x, y and the scale (slide/shake offsets are added by the
-- caller).  Feet stay at 96 for every scale: y + (h - pad) * scale == 96.
function BattleState.backPlacement(w, h, pad, padL, scale)
  return 8 - padL * scale, 96 - (h - pad) * scale, scale
end

-- Enemy (front) placement: given the s=1 slot origin (ex, ey) from the
-- 7x7 tile layout, keep the bottom edge and horizontal centre pinned as
-- the pic scales -- the same compensation AnimateSendingOutMon's grow
-- uses.  Returns top-left x, y and the scale.  The bottom edge stays put
-- for every scale: y + h * scale == ey + h.
function BattleState.frontPlacement(ex, ey, w, h, scale)
  return ex + w * (1 - scale) / 2, ey + h * (1 - scale), scale
end

-- Front/trainer pics: LoadUncompressedSpriteData centers the sprite in
-- a 7x7 tile buffer, then CopyUncompressedPicToTilemap places that
-- buffer at hlcoord 12,0.  Horizontal pad is floor((8-w)/2) tiles;
-- vertical pad is (7-h) -- bottom-aligned inside the 7x7.
local function enemyPicXY(img, slide, sx, sy)
  local tw = math.floor(img:getWidth() / 8)
  local th = math.floor(img:getHeight() / 8)
  if tw < 1 then tw = 1 elseif tw > 7 then tw = 7 end
  if th < 1 then th = 1 elseif th > 7 then th = 7 end
  local hPad = math.floor((8 - tw) / 2)
  local vPad = 7 - th
  return 96 + 8 * hPad - slide + sx, 8 * vPad + sy
end

-- the two mon pics (or the trainer/back pics), offset by the window
-- shake -- on the GB the pics are BG tiles, so they move with it
-- onlySide ("player" / "enemy") draws one side's pic alone, and
-- skipMenuClip drops the move-menu row clip below: the widescreen layout
-- composites each side into its own region of a taller battlefield, where
-- neither the other side's pixels nor the classic menu rows apply.
function BattleState:drawPicsLayer(slide, sx, sy, onlySide, skipMenuClip)
  -- The move-select boxes are BG tiles on the GB, so they REPLACE the
  -- player pic's rows: the TYPE/PP box at (0,8) (PrintMenuItem) wipes
  -- pic rows 8+, and Mimic's copy menu at (0,7) (MoveSelectionMenu
  -- .mimicmenu) wipes rows 7+.  The port draws pics above the menu
  -- layer in the colorized pipeline, so clip them to the visible rows.
  local g = love.graphics
  local clipY = not skipMenuClip
                and (self.phase == "mimicSelect" and 56
                     or self.phase == "moveSelect" and 64)
                or nil
  local clipped, cs1, cs2, cs3, cs4
  if clipY and g.getScissor and g.intersectScissor then
    cs1, cs2, cs3, cs4 = g.getScissor()
    g.intersectScissor(0, 0, 160, clipY)
    clipped = true
  end
  -- Enemy: front sprite in the 7x7 slot at hlcoord 12,0.
  if onlySide ~= "player" and self.showEnemyTrainer and self.trainerPic then
    -- the enemy trainer pic holds the mon slot until the send-out
    local img = self:picImage(self.trainerPic)
    love.graphics.setColor(1, 1, 1, 1)
    local ex, ey = enemyPicXY(img, slide, sx, sy)
    -- SlideTrainerPicOffScreen / _ScrollTrainerPicAfterBattle offset (#317)
    love.graphics.draw(img, ex + self:picOffset("foe"), ey)
  elseif onlySide ~= "player"
     and self.enemy and self.enemy.sprite and not self.enemyHidden
     and not self.enemySendingOut and not self:fxHidden(self.enemy)
     -- SWALLOWED.  While a ball is being thrown the foe's pic belongs to the
     -- ball's timeline: it shrinks into the ball and comes back out of it,
     -- and once it is inside there is nothing to draw at all.
     and not ((self:gen3BallFor(self.enemy) or {}).monHidden) then
    local img = self:picImage(self.enemy.sprite)
    love.graphics.setColor(1, 1, 1, 1)
    local ex, ey = enemyPicXY(img, slide, sx, sy)
    local s = BattleState.resolveBattleScale(self.data, "front",
      imagePathOf(img), self.enemy.mon and self.enemy.mon.species)
    -- EMERALD PLACES ITS POKEMON ON A PLATFORM, and the 7x7 tile slot above
    -- is the Game Boy's rule for a 160x144 letterbox that has none.  On the
    -- Gen 3 field it left the foe up in the corner well clear of the ground
    -- it is supposed to be standing on.
    if self:gen3Layout() then
      ex, ey = Gen3Battle.picPlacement(self, self.enemy, img,
                                       imagePathOf(img), s)
      ex = ex - slide + sx
      ey = ey + sy
    end
    local gs = self:growInScale(self.enemy)
    if gs then
      -- AnimateSendingOutMon: the downscaled pic keeps its bottom edge
      -- and horizontal center pinned to the mon's slot while it grows --
      -- the mod scale composes multiplicatively with the grow stage
      local eff = s * gs
      if eff > 0 then
        local dx, dy
        if self:gen3Layout() then
          dx, dy = Gen3Battle.picPlacement(self, self.enemy, img,
                                           imagePathOf(img), eff)
          dx, dy = dx - slide + sx, dy + sy
        else
          dx, dy = BattleState.frontPlacement(ex, ey,
            img:getWidth(), img:getHeight(), eff)
        end
        love.graphics.draw(img, dx, dy, 0, eff, eff)
      end
    elseif self:gen3BallFor(self.enemy)
        and (self:gen3BallFor(self.enemy).monScale or 1) < 1 then
      -- THE ABSORB, and it is two things at once: the pic shrinks to about a
      -- fifth over 28 frames while its whole palette blends to the BALL'S
      -- OWN colour -- a Net Ball's catch is green and a Dive Ball's is blue.
      -- Its centre travels to the ball's, which is what makes it look sucked
      -- in rather than merely small.
      local anim = self:gen3BallFor(self.enemy)
      local eff = s * math.max(0.01, anim.monScale or 1)
      local cx, cy = ex + img:getWidth() * s / 2, ey + img:getHeight() * s / 2
      -- a Pokemon coming OUT of a ball rises a few pixels as it does
      -- (SpriteCB_ReleaseMonFromBall walks its pos2.y); one being absorbed
      -- does not, and its rise is zero
      cy = cy + (anim.monRise or 0)
      local t = math.max(0, math.min(1, anim.monBlend or 0))
      cx = cx + (anim.x - cx) * t
      cy = cy + (anim.y - cy) * t
      local colour = require("src.battle.Gen3BallAnim").colour(anim)
      love.graphics.setColor(1 - t * (1 - colour[1] / 255),
                             1 - t * (1 - colour[2] / 255),
                             1 - t * (1 - colour[3] / 255), 1)
      love.graphics.draw(img, cx, cy, 0, eff, eff,
                         img:getWidth() / 2, img:getHeight() / 2)
      love.graphics.setColor(1, 1, 1, 1)
    elseif self:gen3Layout() then
      self:drawBattlerPic(self.enemy, ex, ey, s)
    else
      local dx, dy = BattleState.frontPlacement(ex, ey,
        img:getWidth(), img:getHeight(), s)
      self:drawBattlerPic(self.enemy, dx, dy, s)
    end
  end

  -- Player: back sprite at hlcoord 1,5 (x=8), 2x like the GB, feet at y=96.
  -- Left transparent columns (matted white) are pulled back so opaque
  -- pixels land where hardware's white-on-white columns left them.
  local hidePlayer = self.safari or self:demoHidesPlayer()
  if onlySide ~= "enemy" and self.showPlayerBack and self.playerBackPic then
    -- Red's (or the old man's) back pic until "Go!"; it stays up for
    -- the whole safari / catch-demo battle like the original
    local img = self:picImage(self.playerBackPic)
    local pad = imagePadBottom[self.playerBackPic] or 0
    local padL = imagePadLeft[self.playerBackPic] or 0
    -- the trainer back is a bare pic, not species-keyed, so only an
    -- image-level battle_sprite_scales entry can rescale it
    local s = BattleState.resolveBattleScale(self.data, "back",
      imagePathOf(self.playerBackPic), nil)
    love.graphics.setColor(1, 1, 1, 1)
    -- THE TRAINER STANDS ON THE PLATFORM TOO.
    --
    -- Reported from play: "my characters back sprite in battle sits a little
    -- too high".  backPlacement below pins the feet at y=96, which is the top
    -- of the Game Boy's text box on a 144-pixel screen -- the right answer for
    -- Red and Crystal, and fifteen pixels of air on Emerald, whose player
    -- platform is lower and whose screen is taller.  The Pokemon on that side
    -- already stand on the measured platform; the trainer who throws them was
    -- the one thing still placed by the older rule.
    local dx, dy
    if self:gen3Layout() then
      dx, dy = Gen3Battle.picPlacement(self, { isPlayer = true }, img,
                                       imagePathOf(self.playerBackPic), s)
    else
      dx, dy = BattleState.backPlacement(img:getWidth(), img:getHeight(),
                                         pad, padL, s)
    end
    -- picOffset: SlideTrainerPicOffScreen walking the back pic off the left
    love.graphics.draw(img, dx + slide + sx + self:picOffset("back"),
                       dy + sy, 0, s, s)
  elseif onlySide ~= "enemy"
     and self.player and self.player.sprite and not hidePlayer
     and not self.sendingOut and not self:fxHidden(self.player)
     -- INSIDE THE BALL.  While the player's send-out ball is still in the
     -- air there is no Pokemon on that side to draw; without this it stood
     -- there at full size waiting for its own ball to arrive.
     and not ((self:gen3BallFor(self.player) or {}).monHidden) then
    local img = self:picImage(self.player.sprite)
    love.graphics.setColor(1, 1, 1, 1)
    -- feet flush on the text box top (y=96), ignoring baked-in padding
    local pad = imagePadBottom[self.player.sprite] or 0
    local padL = imagePadLeft[self.player.sprite] or 0
    local s = BattleState.resolveBattleScale(self.data, "back",
      imagePathOf(self.player.sprite),
      self.player.mon and self.player.mon.species)
    local gs = self:growInScale(self.player)
    local ballOut = self:gen3BallFor(self.player)
    if ballOut and (ballOut.monScale or 1) >= 1 then ballOut = nil end
    if gs then
      -- the player-side AnimateSendingOutMon grow (after the poof,
      -- core.asm:1757-1762): feet pinned at y=96, horizontal centre
      -- pinned, mod scale composed with the grow stage
      local eff = s * gs
      if eff > 0 then
        love.graphics.draw(img,
          8 - padL * s + img:getWidth() * s * (1 - gs) / 2 + sx,
          96 - (img:getHeight() - pad) * eff + sy, 0, eff, eff)
      end
    elseif ballOut then
      -- COMING OUT OF THE BALL, which is the absorb run backwards: the pic
      -- starts at the ball's own place tinted the ball's own colour and
      -- grows out to full size and full colour over fourteen frames.  Same
      -- two numbers the foe's side reads, off the same timeline.
      local dx, dy
      if self:gen3Layout() then
        dx, dy = Gen3Battle.picPlacement(self, self.player, img,
                                         imagePathOf(self.player.sprite), s)
      else
        dx, dy = BattleState.backPlacement(img:getWidth(), img:getHeight(),
                                           pad, padL, s)
      end
      local eff = s * math.max(0.01, ballOut.monScale or 1)
      local cx = dx + sx + img:getWidth() * s / 2
      local cy = dy + sy + img:getHeight() * s / 2 + (ballOut.monRise or 0)
      local t = math.max(0, math.min(1, ballOut.monBlend or 0))
      cx = cx + (ballOut.x - cx) * t
      cy = cy + (ballOut.y - cy) * t
      local colour = require("src.battle.Gen3BallAnim").colour(ballOut)
      love.graphics.setColor(1 - t * (1 - colour[1] / 255),
                             1 - t * (1 - colour[2] / 255),
                             1 - t * (1 - colour[3] / 255), 1)
      love.graphics.draw(img, cx, cy, 0, eff, eff,
                         img:getWidth() / 2, img:getHeight() / 2)
      love.graphics.setColor(1, 1, 1, 1)
    elseif self:gen3Layout() then
      local dx, dy = Gen3Battle.picPlacement(self, self.player, img,
                                             imagePathOf(self.player.sprite), s)
      self:drawBattlerPic(self.player, dx + sx, dy + sy, s)
    else
      local dx, dy = BattleState.backPlacement(img:getWidth(),
        img:getHeight(), pad, padL, s)
      self:drawBattlerPic(self.player, dx + sx, dy + sy, s)
    end
  end
  if clipped then
    if cs1 then
      g.setScissor(cs1, cs2, cs3, cs4)
    else
      g.setScissor()
    end
  end

  -- THE OTHER TWO, when there are four.
  --
  -- The two passes above carry the whole intro: the trainer pic that holds
  -- the foe's slot, the slide, the grow-in, the send-out gap.  All of that
  -- belongs to a SIDE rather than to a slot -- both of a trainer's Pokemon
  -- arrive together -- so the right-hand pair are drawn plainly here, on
  -- the platform offsets sBattlerCoords gives them, rather than by
  -- duplicating a hundred lines of intro state for a case that has none.
  if self:gen3Layout() and self:isDouble() then
    for _, pos in ipairs({ BattleState.POS.PLAYER_RIGHT,
                           BattleState.POS.OPPONENT_RIGHT }) do
      local b = self:battlerAt(pos)
      local side = b and b.isPlayer and "player" or "enemy"
      if b and b.sprite and onlySide ~= (side == "player" and "enemy" or "player")
         and not self:fxHidden(b)
         and not self:sideArriving(b.isPlayer, slide) then
        local img = self:picImage(b.sprite)
        if img then
          love.graphics.setColor(1, 1, 1, 1)
          local sc = BattleState.resolveBattleScale(
            self.data, b.isPlayer and "back" or "front",
            imagePathOf(img), b.mon and b.mon.species)
          local x, y = Gen3Battle.picPlacement(self, b, img, imagePathOf(img), sc)
          self:drawBattlerPic(b, x - slide + sx, y + sy, sc)
        end
      end
    end
  end
end

-- the BG-tile UI: HUDs, pokeball rows, safari ball count.  Grayscale;
-- the zone pass colors it in colorized mode.
function BattleState:drawHUDs(slide)
  -- EMERALD'S OWN, and reached through this method rather than around it.
  -- Gen3Battle.draw used to call its layer functions directly, which meant a
  -- mod wrapping this name never saw a Gen 3 battle at all.
  if self:gen3Layout() then return Gen3Battle.drawHUDs(self, slide) end
  -- the HUD clears with the send-out text (ClearScreenArea,
  -- core.asm:1414-1417) and DrawEnemyHUDAndHPBar (1435) only redraws
  -- it after the grow-in + cry
  -- In colorized modes the zone pass (drawZonePass over BATTLE_ZONES pal 0/1)
  -- recolors the bar's DMG gray fill by region, so drawHPBar must skip its
  -- per-pixel tint (grayFill) -- otherwise GREENBAR's red-channel-0 fill
  -- double-applies and the zone shade shader maps the whole bar to black (#229).
  local grayFill = self:colorMode()
  local barData = self.data
  local fx = self.fx
  local hudShake = (fx and fx.hudShakeX) or 0
  -- FaintEnemyPokemon clears the enemy HUD area; it stays blank through
  -- TrainerAboutToUseText until DrawEnemyHUDAndHPBar after the next send-out
  -- ...and it is not up yet during the intro text either: a wild battle's
  -- DrawEnemyHUDAndHPBar is called from _InitBattleCommon (core.asm:6763)
  -- AFTER PrintBeginningBattleText returns, so "Wild X appeared!" shows the
  -- player's ball row with no enemy HUD beside it (#317)
  if self.enemy and not self.showEnemyTrainer and not self.enemySendingOut
     and not self:growInScale(self.enemy) and slide == 0
     and not self.introBalls and not self.enemy.fainted then
    -- enemy HUD (DrawEnemyHUDAndHPBar): name row 0, <LV>+level (4,1),
    -- HP bar (2,2) with the vertical tick at (1,2), underline row 3;
    -- AnimationShakeEnemyHUD nudges just this block via SCX
    if hudShake ~= 0 then
      love.graphics.push()
      love.graphics.translate(hudShake, 0)
    end
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(self.enemy.name, nameX(1, self.enemy.name), 0)
    if self.enemy.shownStatus then
      Font.draw(self:statusLabel({ status = self.enemy.shownStatus }), 40, 8)
    else
      hudTile(0x6E, 32, 8) -- <LV>
      Font.draw(tostring(self.enemy.mon.level), 40, 8)
    end
    hudTile(0x73, 8, 16)
    drawHPBar(barData, 2, 2,
              { hp = shownHP(self.enemy), stats = self.enemy.mon.stats },
              nil, grayFill)
    hudTile(0x74, 8, 24)
    for i = 2, 9 do hudTile(0x76, i * 8, 24) end
    hudTile(0x78, 80, 24)
    if hudShake ~= 0 then
      love.graphics.pop()
    end
  end

  -- ReplaceFaintedEnemyMon -> DrawEnemyPokeballs (core.asm:896,
  -- draw_hud_pokeball_gfx.asm:9-11 -> SetupEnemyPartyPokeballs :33-45):
  -- between a KO and the next send-out the foe's ball row sits in the enemy
  -- HUD block FaintEnemyPokemon cleared, over the chrome PlaceEnemyHUDTiles
  -- writes with it -- the same $73 (1,2) / $74 (1,3) / $76 run / $78 tiles
  -- the live HUD draws, minus the HP bar (#283).  Its own block rather than
  -- a third arm of showIntroBalls below: that window is DrawAllPokeballs's
  -- (#317) and clears for the rest of the battle, this one reopens on every
  -- enemy faint.  wBaseCoordX $48 / wBaseCoordY $20 stepping -8 is screen
  -- (64,16) leftward, the same row the intro draws.
  if self.showEnemyBalls and self.enemyParty and slide == 0 then
    hudTile(0x73, 8, 16)
    hudTile(0x74, 8, 24)
    for i = 2, 9 do hudTile(0x76, i * 8, 24) end
    hudTile(0x78, 80, 24)
    love.graphics.setColor(1, 1, 1, 1)
    self:drawBallRow(self.enemyParty, 64, 16, -8)
  end

  -- A safari / old-man battle has no player mon out, so no player HUD (see
  -- hidePlayer below).  Nothing takes its place: PrintSafariZoneSteps -- the
  -- "nnn/500 / BALLx nn" box -- is start-menu only and returns early off the
  -- nine interior maps (engine/overworld/player_state.asm:219-224), so no
  -- ball count belongs over the battlefield.  The count lives in the BALL
  -- menu item instead (drawTextArea, #540).
  -- Party pokeball rows and the HUD chrome under them, for exactly the
  -- window DrawAllPokeballs owns (common_text.asm:27, with the intro text).
  -- SetupOwnPartyPokeballs runs in EVERY battle, so the player's row belongs
  -- on the wild intro too -- keying it off the enemy trainer pic meant a
  -- wild battle never drew one (#317) -- and SetupEnemyPartyPokeballs is
  -- skipped when wIsInBattle == 1, so only a trainer/link battle gets the
  -- foe's row.  Gating on introBalls rather than on the pics also stops the
  -- rows coming back when the beaten trainer scrolls in (#282):
  -- _ScrollTrainerPicAfterBattle redraws tilemap columns and never touches
  -- OAM, which ClearSprites emptied when the intro text was dismissed.
  local showIntroBalls = self.introBalls and slide == 0
  if showIntroBalls then
    if self.enemyParty and (self.kind == "trainer" or self.kind == "link") then
      -- PlaceEnemyHUDTiles (hlcoord 1,2): $73, then $74 + 8x $76 + $78
      -- rightward along row 3 (draw_hud_pokeball_gfx.asm:133-165)
      hudTile(0x73, 8, 16)
      hudTile(0x74, 8, 24)
      for i = 2, 9 do hudTile(0x76, i * 8, 24) end
      hudTile(0x78, 80, 24)
      love.graphics.setColor(1, 1, 1, 1)
      self:drawBallRow(self.enemyParty, 64, 16, -8)
    end
    -- PlacePlayerHUDTiles (hlcoord 18,10): $73, then $77 + 8x $76 + $6F
    -- LEFTWARD along row 11 (draw_hud_pokeball_gfx.asm:119-131)
    hudTile(0x73, 144, 80)
    hudTile(0x77, 144, 88)
    for i = 10, 17 do hudTile(0x76, i * 8, 88) end
    hudTile(0x6F, 72, 88)
    love.graphics.setColor(1, 1, 1, 1)
    self:drawBallRow(self.playerParty or self.game.save.party, 88, 80, 8)
  end
  local hidePlayer = self.safari or self:demoHidesPlayer()
  if self.player and not hidePlayer and not self.showPlayerBack
     and slide == 0 then
    -- player HUD (DrawPlayerHUDAndHPBar): name (10,7), <LV>+level
    -- (14,8), HP bar (10,9), HP numbers row 10, underline row 11 with
    -- the tick at (18,10) and the triangle at (9,11)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(self.player.name, nameX(10, self.player.name), 56)
    if self.player.shownStatus then
      Font.draw(self:statusLabel({ status = self.player.shownStatus }), 120, 64)
    else
      hudTile(0x6E, 112, 64) -- <LV>
      Font.draw(tostring(self.player.mon.level), 120, 64)
    end
    drawHPBar(barData, 10, 9,
              { hp = shownHP(self.player), stats = self.player.mon.stats },
              1, grayFill) -- wHPBarType 1: the $6D cap
    Font.draw(("%3d/%3d"):format(shownHP(self.player), self.player.mon.stats.hp), 88, 80)
    -- The block's right edge follows the HP bar: two label tiles from column
    -- 10, then the segments, then the cap -- column 18 with Crystal's
    -- six-segment bar and 19 with Prism's seven, which is where Prism's own
    -- DrawPlayerHUD writes them (core.asm:1110-1116).
    local geo = HudTiles.geometry()
    local edge = (12 + geo.hpBarTiles) * 8
    hudTile(0x73, edge, 80)
    -- Gen2 spends row 11 on the exp bar instead of a plain underline: the
    -- $76 run IS the bar's empty state there, and FillInExpBar overwrites
    -- hlcoord 10,11 with the bar's own tiles (core.asm DrawPlayerHUD).
    if require("src.core.GameVersion").isGen2() then
      -- and where the exp sheet carries its own ends it carries the corner
      -- the row closes on too -- Prism's $5E, nine tiles past the empty one
      hudTile(geo.expBarEmptyTile and (geo.expBarEmptyTile + 9) or 0x77,
              edge, 88)
      HudTiles.drawExpBar(barData, 10, 11,
                          self.expShown
                            or HudTiles.expBarPixels(barData, self.player.mon),
                          grayFill)
    else
      hudTile(0x77, edge, 88)
      for i = 10, 17 do hudTile(0x76, i * 8, 88) end
    end
    hudTile(0x6F, 72, 88)
  end
end

function BattleState:drawTextArea()
  -- EMERALD'S OWN, and reached through this method rather than around it.
  -- Gen3Battle.draw used to call its layer functions directly, which meant a
  -- mod wrapping this name never saw a Gen 3 battle at all.
  if self:gen3Layout() then return Gen3Battle.drawTextArea(self) end
  -- The move list and Mimic's copy menu keep the solid paper (see
  -- WORLD_WINDOW_STYLE); everything else in here is the dialogue box and the
  -- battle menu, which are what goes to glass over a world backdrop.
  local dense = self.phase == "moveSelect" or self.phase == "mimicSelect"
  Font.pushStyle(not dense and self:windowStyle() or nil)
  self:drawTextAreaInner()
  Font.popStyle()
end

function BattleState:drawTextAreaInner()
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  if self.phase == "messages" and (self.current or self.animPlaying) then
    -- during the move animation self.current is nil but shown still holds
    -- the "used X!" lines; keep drawing them like pokered, whose move
    -- animations only touch sprites and never the textbox tilemap (#296)
    -- rolling 2-line window: shown[1] at row y=112, shown[2] at y=128 (battle
    -- text uses every other tile row, hlcoord *,14 / *,16).  scrollPx animates
    -- the lines up one row (ScrollTextUpOneLine) so a 3rd line scrolls into
    -- view instead of drawing off-screen at y=144 (#216).
    if self.scrollPx and self.scrollPx > 0 then
      self.scrollPx = self.scrollPx - 2
      if self.scrollPx <= 0 then self.scrollPx = nil end
    end
    local off = self.scrollPx or 0
    local ys = { 112, 128 }
    for li, line in ipairs(self.shown or {}) do
      local y = (ys[li] or 128) + off
      for i = 1, #line do
        Font.drawCode(line[i], 8 + (i - 1) * 8, y)
      end
    end
    -- the blinking down arrow ('▼', glyph $EE) while a \v CONT wait
    -- (_ContText) or a typed-out page (PromptText) holds the box; both write
    -- it at (18,16), bottom-right, like TextBox / home/text.asm (#317)
    if (self.msgWaiting or self.msgPrompt) and self.frame % 60 < 30 then
      Font.drawCode(0xEE, (0 + 20 - 2) * 8, (12 + 6 - 1) * 8 - 4)
    end
  elseif self.phase == "menu" and self.demo then
    -- the old-man script (DisplayBattleMenu, core.asm:2038-2049): the
    -- standard menu, with the '▶' hand drawn by the scripted keystrokes
    -- -- next to FIGHT (9,14) for the first 80 frames, then ITEM (9,16)
    Font.drawBox(8, 12, 12, 6)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("FIGHT"), 80, 112)
    Font.drawCode(0xE1, 128, 112); Font.drawCode(0xE2, 136, 112)
    Font.draw(Strings("ITEM"), 80, 128); Font.draw(Strings("RUN"), 128, 128)
    Font.drawCode(0xED, 72, (self.demoTimer or 0) <= 80 and 112 or 128)
  elseif self.phase == "menu" then
    local col = (self.menuIndex - 1) % 2
    local row = math.floor((self.menuIndex - 1) / 2)
    if self.safari then
      -- SAFARI_BATTLE_MENU_TEMPLATE: full-width box, "BALLx  BAIT /
      -- THROW ROCK  RUN" from (2,14)
      Font.drawBox(0, 12, 20, 6)
      Font.draw(Strings("BALLx"), 16, 112); Font.draw(Strings("BAIT"), 112, 112)
      Font.draw(Strings("THROW ROCK"), 16, 128); Font.draw(Strings("RUN"), 112, 128)
      -- DisplayBattleMenu .safariLeftColumn / .safariRightColumn print
      -- wNumSafariBalls at hlcoord 7,14 with `lb bc, 1, 2` -- one byte, two
      -- digits, space padded -- right after the "BALLx" label at columns
      -- 2..6 (engine/battle/core.asm:2074-2079, 2107-2112) (#540)
      Font.draw(("%2d"):format(self.safari.balls), 56, 112)
      Font.drawCode(0xED, (col == 0 and 8 or 104), 112 + row * 16)
    elseif self.bugContest then
      -- ContestBattleMenuHeader (engine/battle/menu.asm:76): the same 2x2
      -- menu as always, but wider and shifted left to fit the ball row --
      -- menu_coords 2, 12, 19, 17 with a spacing of 12, against the normal
      -- menu's 8, 12, 19, 17 and spacing 6.  Its text is
      --
      --     FIGHT        <PK><MN>
      --     PARKBALLx NN  RUN
      --
      -- so FIGHT and POKeMON are exactly where they are in a normal battle;
      -- only PACK is replaced.  Item text sits at column x1+2 and the cursor
      -- at x1+1, which is the same relationship the normal and Safari menus
      -- have, so: text at columns 4 and 16, cursor at 3 and 15.
      Font.drawBox(2, 12, 18, 6)
      Font.draw(Strings("FIGHT"), 32, 112)
      Font.drawCode(0xE1, 128, 112); Font.drawCode(0xE2, 136, 112)
      Font.draw(Strings("PARKBALLx"), 32, 128)
      Font.draw(Strings("RUN"), 128, 128)
      -- .PrintParkBallsRemaining writes at hlcoord 13, 16 -- two digits,
      -- leading-zeros flag clear, i.e. space padded -- which lands in the two
      -- cells right after the 'x' of the label.
      Font.draw(("%2d"):format(self:bugContestBalls()), 104, 128)
      Font.drawCode(0xED, (col == 0 and 24 or 120), 112 + row * 16)
    else
      -- BATTLE_MENU_TEMPLATE: box (8,12)-(19,17), "FIGHT <PK><MN> /
      -- ITEM  RUN" from (10,14); cursor columns 9 / 15
      Font.drawBox(8, 12, 12, 6)
      Font.draw(Strings("FIGHT"), 80, 112)
      Font.drawCode(0xE1, 128, 112); Font.drawCode(0xE2, 136, 112)
      Font.draw(Strings("ITEM"), 80, 128); Font.draw(Strings("RUN"), 128, 128)
      Font.drawCode(0xED, (col == 0 and 72 or 120), 112 + row * 16)
    end
  elseif self.phase == "moveSelect" then
    -- pokered MoveSelectionMenu: move list in a box at (4,12) 16x6,
    -- names at column 6 from row 13, cursor at column 5.  PrintMenuItem:
    -- the TYPE/PP box at (0,8) 11x5, with "TYPE/" at (1,9), the type at
    -- (2,10) and "PP cur/max" at (5,11); its bottom border merges into
    -- the move box's top border ('─' at (4,12), '┘' at (10,12)).
    Font.drawBox(0, 8, 11, 5)
    Font.drawBox(4, 12, 16, 6)
    -- Those two cells are REPLACED on hardware: MoveSelectionMenu writes them
    -- straight into the tilemap over the border it just laid down
    -- (core.asm:2492-2501), and PrintMenuItem's own TextBoxBorder then redraws
    -- the whole row on top (core.asm:2838-2844).  Font.drawCode blits a
    -- black-on-transparent glyph instead, so the tile underneath survives: the
    -- move box's '┌' keeps its Poké Ball corner showing through the '─', and
    -- the '─' the move box drew at (10,12) pokes two dots out from under the
    -- '┘' (#240).  Wipe each cell back to box white first, the way a tilemap
    -- write does.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 32, 96, 8, 8)
    love.graphics.rectangle("fill", 80, 96, 8, 8)
    Font.drawCode(Font.BORDER.h, 32, 96)
    Font.drawCode(Font.BORDER.br, 80, 96)
    love.graphics.setColor(0, 0, 0, 1)
    local chooser = self:menuBattler()
    for i, mv in ipairs(chooser.curMoves) do
      -- unknown ids (mod-injected moves) print raw instead of crashing
      local def = self.data.moves[mv.id]
      Font.draw(def and def.name or tostring(mv.id), 48, 96 + i * 8)
    end
    Font.drawCode((self.moveSwapIndex == self.moveIndex) and 0xEC or 0xED,
                  40, 96 + self.moveIndex * 8)
    if self.moveSwapIndex and self.moveSwapIndex ~= self.moveIndex then
      Font.drawCode(0xEC, 40, 96 + self.moveSwapIndex * 8)
    end
    local sel = chooser.curMoves[self.moveIndex]
    if sel then
      local def = self.data.moves[sel.id]
      if chooser.disabledSlot == self.moveIndex then
        Font.draw(Strings("disabled!"), 8, 80)
      elseif def then
        Font.draw(Strings("TYPE/"), 8, 72)
        -- the type record's display name (a mod type shows its name, and
        -- PSYCHIC_TYPE prints PSYCHIC like the original)
        Font.draw(def.type and TypeChart.displayName(def.type) or "", 16, 80)
        local maxPP = def.pp + (sel.ppUps or 0) * math.floor(def.pp / 5)
        Font.draw(("%2d/%2d"):format(sel.pp, maxPP), 40, 88)
      end
    end
  elseif self.phase == "mimicSelect" then
    -- Mimic's copy menu (MoveSelectionMenu .mimicmenu, core.asm:
    -- 2506-2517): the enemy's move list in a 16x6 box at (0,7), names
    -- single-spaced from (2,8), cursor at column 1
    Font.drawBox(0, 7, 16, 6)
    love.graphics.setColor(0, 0, 0, 1)
    for i, m in ipairs(self.mimicMoves) do
      Font.draw(self.data.moves[m.id].name, 16, (7 + i) * 8)
    end
    Font.drawCode(0xED, 8, (7 + self.mimicIndex) * 8)
  end
end

function BattleState:draw()
  if self:wideLayout() then return WideBattle.draw(self) end
  if self:gen3Layout() then return Gen3Battle.draw(self) end
  return self:drawClassic()
end

-- THE FIELD -- the paper and the ground standing on it.
--
-- Its own method so a mod can take it away.  The classic layout has no
-- backdrop at all, so nothing here ever needed the seam; Emerald's screen
-- does have one, and a mod staging its own scene behind the battle
-- (DRAMATIC_SHAPE's in-world 3D arena) had that scene painted straight over
-- by a flat terrain picture.  Every other layer of this screen is already a
-- method for exactly this reason.
function BattleState:drawBattleField()
  if self:gen3Layout() then return Gen3Battle.drawField(self) end
  -- the classic and widescreen layouts paint their field inside their own
  -- draw, where it has always been
end

function BattleState:drawClassic()
  -- AskName: ClearSprites + wild ClearScreenArea -- white field under the
  -- nickname TextBox / YES/NO (naming_screen.asm); overlays draw on top.
  if self.blankForAskName then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    return
  end
  local fx = self.fx
  -- window shakes (SE_SHAKE_SCREEN / the enemy-hit vertical shake);
  -- the animations-off fallback keeps the old +-2 alternation
  local sx = (fx and fx.shakeX) or 0
  local sy = (fx and fx.shakeY) or 0
  if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
    sx = self.frame % 4 < 2 and 2 or -2
  end
  -- intro slide-in offset: 2 px per frame, so 144 px over 72 frames
  local slide = (self.introSlide or 0) * Timing.BATTLE_SLIDE_PX_PER_FRAME

  if self:colorMode() then
    -- SGB pipeline: gray BG canvas -> (wavy) -> zone recolor with the
    -- BGP fade -> mon pics -> OAM anim sprites (never BGP-faded)
    local g = love.graphics
    local prev = g.getCanvas()
    local wavy = fx and fx.wavy
    g.setCanvas(self.bgCanvas)
    -- The white paper the whole battle is drawn on -- unless something has
    -- put a WORLD where the paper goes, in which case painting it is what
    -- hides the world.  Clearing to transparent instead leaves only what is
    -- actually drawn (HUDs, boxes, pics) and lets the 3D frame underneath
    -- show between them.  The zone shader passes alpha through unchanged
    -- (PaletteFX.shader: `vec4(mapped, p.a)`), so transparency survives the
    -- colour pass rather than being remapped to a palette shade.
    if self:worldBackdrop() then
      g.clear(0, 0, 0, 0)
    else
      g.setColor(1, 1, 1, 1)
      g.rectangle("fill", 0, 0, 160, 144)
    end
    g.setColor(1, 1, 1, 1)
    -- the party ball rows are OBJ sprites on hardware (see drawBallRow):
    -- collect them here and draw them over the finished zone pass instead
    local balls = self:gen2BallColors() and {} or nil
    self.deferBalls = balls
    self:drawHUDs(slide)
    self.deferBalls = nil
    self:drawTextArea()
    if wavy then
      -- the mon pics are BG tiles on the GB, so SE_WAVY_SCREEN bends
      -- them too: bake them into the canvas as DMG grays and let the
      -- zone pass color them by region (exactly what the SGB did)
      self.grayPics = true
      g.setScissor(0, 0, 160, 96) -- BG pics live above the text box
      self:drawPicsLayer(slide, 0, 0)
      g.setScissor()
      self.grayPics = nil
    end
    g.setCanvas(prev)
    self:drawZonePass(self:applyWavy(self.bgCanvas), sx, sy)
    if balls and balls[1] then
      -- they ride the window shake with the HUD chrome they sit in
      local shifted = sx ~= 0 or sy ~= 0
      if shifted then g.push() g.translate(sx, sy) end
      g.setColor(1, 1, 1, 1)
      for _, row in ipairs(balls) do
        self:drawBallRow(row[1], row[2], row[3], row[4])
      end
      if shifted then g.pop() end
    end
    if not wavy then
      -- the pics are BG tiles in rows 0-11 on the GB: they can never
      -- cover the text box, whatever the SE offsets do (a vertical
      -- window shake moves the box down with everything else)
      g.setScissor(0, 0, 160, 96 + math.max(0, sy))
      self:drawPicsLayer(slide, sx, sy)
      g.setScissor()
    end
    self:drawAnimLayer(true)
  else
    -- flat fallback (headless / no shader support): pre-colorized pics
    -- on white, no palette fades -- and the same exception as above, so the
    -- two paths agree about when there is paper to paint
    love.graphics.setColor(1, 1, 1, 1)
    if not self:worldBackdrop() then
      love.graphics.rectangle("fill", 0, 0, 160, 144)
    end
    local shaking = sx ~= 0 or sy ~= 0
    if shaking then
      love.graphics.push()
      love.graphics.translate(sx, sy)
    end
    self:drawPicsLayer(slide, 0, 0)
    self:drawHUDs(slide)
    self:drawAnimLayer(false)
    self:drawTextArea()
    if shaking then
      love.graphics.pop()
    end
  end
  -- screen flash (flash-effect moves without the subanimation player):
  -- white flicker overlay
  if fx and fx.flash and fx.flash > 0 and self.frame % 4 < 2 then
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  love.graphics.setColor(1, 1, 1, 1)
  -- battle.overlay: shiny sparkles, custom HUD chrome, etc.  Draw-only;
  -- the vanilla link is a no-op so an empty chain costs nothing.
  if Runtime.wantsHook("battle.overlay") then
    Runtime.call("battle.overlay", function() end, self)
  end
end

return BattleState
