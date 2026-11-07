-- A DS battle on the map fills the window (NativeGen4 stages it).
--
-- Reported from play: "fix the dramatic shapes mod not showing the battle
-- screen in full screen. It's currently locked to a 4:3 window instead of full
-- screen for gen4 and 5."
--
-- Gen 1-3 get full screen for nothing: their stage is a window-sized world
-- image (Renderer:setWorldOverride) with the battle's small UI surface floating
-- over it. A DS battle's stage is different: NativeGen4 draws the 3D field INTO
-- the battle's own UI surface, in order to keep Platinum's move animations and
-- depth together with it -- so the field can only ever be as big as that
-- surface, and that surface is 256x192 (or 256x248 with the single-screen
-- panel), integer-scaled and letterboxed unless the player found BATTLE LAYOUT
-- and BATTLE SIZE.
--
-- So the surface is what grows. BattleState already knows how to compose on a
-- wider surface (BATTLE LAYOUT = WIDE: Gen4Battle.width drives the backdrop,
-- the boxes, the panel and BW's 3D field), and NativeGen4 draws its field at
-- Gen4Battle.width. What this adds, while a battle is staged:
--
--   * the width comes from the shape of the screen the battle really has: the
--     main panel in a split layout (Renderer:pixelSize answers for it), and
--     measured against the rows actually in use -- the panel's 56 included,
--     which the option's own 192-row sum leaves out -- so 256x248 becomes
--     440x248 at 16:9 and not 344x248 in a pillarbox;
--   * the fit is the window's, not whole pixels (BATTLE SIZE = FILL);
--   * the width is not rounded to a tile: nothing on this surface is tiled to
--     the window and an 8-pixel step leaves bars at most window sizes;
--   * a full-screen menu opened from the battle (party, bag) keeps its own DS
--     surface while it is the picture, since nothing of the battle shows;
--   * the bottom screen swapped up sits in the middle of the surface.
--
-- Nothing is stretched: rows stay 192 + panel, columns are added.
-- Presentational only, as the whole mod is. With the mod off none of this is on
-- the engine, and with 3D-BTL off every wrapper hands straight through.

local V = ...

local Wide = {}

function Wide.install(enabled, supports)
  local Rewrap = V.require("Rewrap")
  local BattleState = require("src.battle.BattleState")
  local Battle = require("src.battle.Gen4Battle")

  -- the live question: is this a battle NativeGen4 is staging?
  local function live(battle)
    if not (battle and battle.gen4Layout and battle:gen4Layout()) then return false end
    local game = battle.game
    return enabled() and supports(game and game.overworld) or false
  end
  Wide.live = live

  local function surfaceWidth(battle)
    local Renderer = require("src.render.Renderer")
    local okP, pw, ph = pcall(Renderer.pixelSize, Renderer)
    local panel = Battle.singlePanel(battle)
    if not (okP and type(pw) == "number" and type(ph) == "number" and pw > 0 and ph > 0) then
      return Battle.WIDTH
    end
    -- memoised for the reason BattleState:gen4SurfaceWidth gives: asked many
    -- times a frame, and every answer in a frame has to be the same number
    local key = pw .. "x" .. ph .. (panel and "/panel" or "")
    if battle.dramaticWideKey ~= key then
      local rows = Battle.HEIGHT + (panel and Battle.PANEL_H or 0)
      local want = math.floor(rows * pw / ph / 2 + 0.5) * 2
      battle.dramaticWideKey = key
      battle.dramaticWideW = math.max(Battle.WIDTH, math.min(Renderer.MAX_UI_WIDTH or 640, want))
    end
    return battle.dramaticWideW
  end

  -- BLACK AND WHITE'S BATTLE BAG is a whole 256x192 picture that is not marked
  -- opaque and asks for the battle's own surface, so on a wider one it sat in
  -- the top-left corner with the fight showing beside it. It is a full-screen
  -- menu like the party and the same rule covers it.
  local BattleBag = require("src.ui.Gen5BattleBag")
  local function isBattleBag(state)
    return getmetatable(state) == BattleBag
  end

  Rewrap.install({
    { BattleBag, "dramaticNativeWideHook", { "uiSize" } },
    { BattleState, "dramaticNativeWideHook",
      { "gen4SurfaceWidth", "wantsFillScale", "holdsUISurface" } },
    { Battle, "dramaticNativeWideHook", { "width", "drawMoveFace" } },
  }, function()
    local innerBagSize = BattleBag.uiSize
    function BattleBag:uiSize()
      if live(self.battle) then return Battle.WIDTH, Battle.HEIGHT end
      return innerBagSize(self)
    end

    local innerSurface = BattleState.gen4SurfaceWidth
    function BattleState:gen4SurfaceWidth()
      if live(self) then return surfaceWidth(self) end
      return innerSurface(self)
    end

    local innerFill = BattleState.wantsFillScale
    function BattleState:wantsFillScale()
      if live(self) then return true end
      return innerFill(self)
    end

    local innerHolds = BattleState.holdsUISurface
    function BattleState:holdsUISurface()
      if not live(self) then return innerHolds(self) end
      -- an opaque screen above the battle IS the picture: it keeps its own
      -- surface, as it does without this mod, rather than shrinking into the
      -- middle of the battle's taller one
      local states = self.game and self.game.stack and self.game.stack.states or {}
      for i = #states, 1, -1 do
        local state = states[i]
        if state == self then break end
        if state.isOpaque or isBattleBag(state) then return false end
      end
      return true
    end

    local innerWidth = Battle.width
    function Battle.width(battle)
      if live(battle) then return surfaceWidth(battle) end
      return innerWidth(battle)
    end

    -- A MOVE TILE GROWS WITH THE PANEL AND ITS WORDS GO WITH IT: the face is
    -- laid out on the cartridge's 128-wide half, so it is centred in the wider
    -- tile rather than left at the 256-pixel column it was handed.
    local innerFace = Battle.drawMoveFace
    function Battle.drawMoveFace(battle, i, colX, nameTop, infoTop, small)
      if small and live(battle) then
        local x, _, w = Battle.compactMoveRect(i)
        colX = math.floor(x + (w - 128) / 2)
      end
      return innerFace(battle, i, colX, nameTop, infoTop, small)
    end
  end)

  -- THE BOTTOM SCREEN, SWAPPED UP OVER A WIDE BATTLE, is still the DS's 256x192
  -- picture and the player's own choice to look at it. It goes in the middle of
  -- the surface with black either side, not in the top-left corner with half a
  -- healthbox showing beside it. rect is what toLocal asks too, so taps follow.
  local SecondScreen = require("src.ui.SecondScreen")
  local function swappedOverWide(game)
    if SecondScreen.mode(game) ~= "swap" then return nil end
    local G = require("src.core.Game")
    local held = G.heldSurfaceInStack(G.stack)
    if not (held and live(held)) then return nil end
    local uw, uh = require("src.render.Renderer"):uiSize()
    if uw <= Battle.WIDTH then return nil end
    return uw, uh
  end
  Rewrap.install({
    { SecondScreen, "dramaticNativeWideHook", { "rect", "draw" } },
  }, function()
    local innerRect = SecondScreen.rect
    function SecondScreen.rect(game)
      local x, y, scale = innerRect(game)
      local uw = swappedOverWide(game)
      if x and uw then x = math.floor((uw - Battle.WIDTH) / 2) end
      return x, y, scale
    end

    local innerDraw = SecondScreen.draw
    function SecondScreen.draw(game, body)
      local uw, uh = swappedOverWide(game)
      if uw then
        local g = love.graphics
        g.setColor(0, 0, 0, 1)
        g.rectangle("fill", 0, 0, uw, uh)
        g.setColor(1, 1, 1, 1)
      end
      return innerDraw(game, body)
    end
  end)
end

return Wide
