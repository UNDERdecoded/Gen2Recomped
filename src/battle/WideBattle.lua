-- Widescreen battle layout (OPTION -> BATTLE LAYOUT -> WIDE).
--
-- The battle simulation, timing, animations and rules stay BattleState's;
-- this module only replaces the composition and asks the renderer for a
-- 304x144 native-pixel UI surface while it is up.  Pictures, font pages,
-- border glyphs, species palettes and HP tiles all resolve through the
-- engine, so a COLORS mode or an asset mod still owns the look.
--
-- The extra 144 pixels of width buy a Gen 3-style arrangement: foe status
-- upper left with its picture upper right, the player's picture lower left
-- with their status lower right, a full-width message window, a split
-- prompt/command window, and a 2x2 move menu with an attached PP/type panel.

local Font = require("src.render.Font")
local HudTiles = require("src.render.HudTiles")
local PaletteFX = require("src.render.PaletteFX")
local Runtime = require("src.mods.Runtime")
local StatusHUDVisibility = require("src.battle.StatusHUDVisibility")
local UIVisibility = require("src.battle.UIVisibility")
local Strings = require("src.core.Strings")
local TypeChart = require("src.battle.TypeChart")

local WideBattle = {
  WIDTH = 304,
  HEIGHT = 144,
  -- everything above this line is battlefield; the 40 rows below it are
  -- the message / command / move windows
  FIELD_BOTTOM = 104,
}

-- The forced-mono display modes re-threshold the whole finished frame
-- through the shade shader, and picImage hands them raw DMG grays for that
-- (#207).  The wide layout has to know: it exposes a matching whole-surface
-- zone and leaves the HP bar fill gray, exactly like the zone pass does in
-- the classic layout (#229).  Keep in sync with picImage / ensureZones.
local function monoMode()
  local m = PaletteFX.mode
  return m == "og" or m == "og_inv" or m == "classic"
end

local function shownHP(battler)
  return math.max(0, math.floor(battler.shownHP or battler.mon.hp or 0))
end

-- a name truncated to `pixels` with a trailing '.', measured through the
-- font's own advances so a variable-width page still fits
local function fitName(text, pixels)
  local spans = Font.split(text or "")
  local n = Font.spansFitting(spans, pixels)
  if n >= #spans then return text or "" end
  local out = {}
  for i = 1, math.max(0, n - 1) do
    out[#out + 1] = (text or ""):sub(spans[i].from, spans[i].to)
  end
  return table.concat(out) .. "."
end

local function saveScissor()
  if not love.graphics.getScissor then return nil end
  local x, y, w, h = love.graphics.getScissor()
  if x == nil then return false end
  return { x, y, w, h }
end

local function restoreScissor(saved)
  if not love.graphics.setScissor then return end
  if saved and saved ~= false then
    love.graphics.setScissor(saved[1], saved[2], saved[3], saved[4])
  else
    love.graphics.setScissor()
  end
end

-- Draw fn's content translated by (dx, dy) and clipped to a surface rect.
-- The scissor is in canvas space, so it bounds the region itself while the
-- translate moves the classic 160x144 coordinates into it.
local function inRegion(x, y, w, h, dx, dy, fn)
  local g = love.graphics
  local saved = saveScissor()
  g.setScissor(x, y, w, h)
  g.push()
  g.translate(dx, dy)
  fn()
  g.pop()
  restoreScissor(saved)
end

local function levelAt(battle, battler, x, y)
  if battler.shownStatus then
    Font.draw(battle:statusLabel({ status = battler.shownStatus }), x, y)
  else
    HudTiles.tile(0x6E, x, y) -- '<LV>'
    Font.draw(tostring(battler.mon.level), x + 8, y)
  end
end

-- CenterMonName, the same two-then-one tile nudge the classic layout uses.
local function nameX(x, name)
  local glyphs = #Font.split(name or "")
  return x + (glyphs <= 2 and 16 or glyphs <= 4 and 8 or 0)
end

-- THE GAME BOY HUD IS NOT A BOX, AND ON GEN 2 IT CARRIES AN EXP BAR.
--
-- Reported from play, with a screenshot: "widescreen in gen2 and prism is
-- missing the gen2 ui i dont see my xp bar or the style of gen2".  The wide
-- layout was drawing ONE panel for every generation -- a framed Font.drawBox
-- with the HP bar stretched to fill it -- which is Gen 3's arrangement and
-- nothing like the Game Boy's.  Gen 2 has no frame at all: the block is a
-- name, a level, the bar, and a rule drawn UNDER it out of the HUD's own
-- chrome tiles, with the player's exp bar closing the bottom row.
--
-- Every offset here is the cartridge's, lifted from the classic layout's own
-- placement so the two cannot drift: at the classic origins -- tile (0,0) for
-- the foe and (9,7) for the player -- this draws exactly what the 160x144
-- screen does, and the wide layout simply hands it different origins.
--
--   foe     name row 0 from column 1, <LV> and level at column 4 of row 1,
--           the tick $73 at (1,2), the bar at (2,2), and row 3 closed by
--           $74, a run of $76 and $78.
--   player  name at column 1, <LV> at column 5 of row 1, the bar at (1,2),
--           the HP numbers at (2,3), the vertical $73 at the bar's right
--           edge, then the exp bar across row 4 with $6F at its left and the
--           row-end corner at its right.
--
-- AND THE WIDTHS ARE THE CARTRIDGE'S TOO, which is what makes this Prism's
-- own HUD rather than Crystal's: HudTiles.geometry() answers seven HP tiles
-- and nine exp tiles there against Crystal's six and eight, so the rule under
-- the bar and the corner that closes it move with them.  Prism's exp sheet
-- carries that corner itself, nine tiles past its empty one ($5E).
local function drawGen2Panel(battle, battler, x, y, player, gray)
  local geo = HudTiles.geometry()
  local tx, ty = math.floor(x / 8), math.floor(y / 8)
  local data = battle.data
  local bar = { hp = shownHP(battler), stats = battler.mon.stats }
  love.graphics.setColor(0, 0, 0, 1)
  if player then
    Font.draw(fitName(battler.name, 64), nameX(x + 8, battler.name), y)
    levelAt(battle, battler, x + 40, y + 8)
    -- wHPBarType 1: the player's bar closes with the double-bar cap
    HudTiles.drawHPBar(data, tx + 1, ty + 2, bar, 1, gray)
    Font.draw(("%3d/%3d"):format(shownHP(battler), battler.mon.stats.hp),
              x + 16, y + 24)
    local edgeCol = tx + 3 + geo.hpBarTiles
    local edge = edgeCol * 8
    HudTiles.tile(0x73, edge, y + 24)
    -- ROW 11 IS THE ONE ROW THE TWO GENERATIONS SPEND DIFFERENTLY.  Gen 2
    -- puts the exp bar there -- the $76 run IS its empty state, and
    -- FillInExpBar overwrites hlcoord 10,11 with the bar's own tiles -- while
    -- Gen 1 has no exp bar in battle at all and closes the block with the
    -- plain underline PlacePlayerHUDTiles draws.  Same split, same tiles, as
    -- the classic layout's own player block.
    if require("src.core.GameVersion").isGen2() then
      -- and where the exp sheet carries its own ends it carries the corner
      -- the row closes on too -- Prism's $5E, nine tiles past the empty one
      HudTiles.tile(geo.expBarEmptyTile and (geo.expBarEmptyTile + 9) or 0x77,
                    edge, y + 32)
      HudTiles.drawExpBar(data, tx + 1, ty + 4,
                          battle.expShown
                            or HudTiles.expBarPixels(data, battler.mon), gray)
    else
      HudTiles.tile(0x77, edge, y + 32)
      for i = tx + 1, edgeCol - 1 do HudTiles.tile(0x76, i * 8, y + 32) end
    end
    HudTiles.tile(0x6F, x, y + 32)
  else
    Font.draw(fitName(battler.name, 80), nameX(x + 8, battler.name), y)
    levelAt(battle, battler, x + 32, y + 8)
    HudTiles.tile(0x73, x + 8, y + 16)
    HudTiles.drawHPBar(data, tx + 2, ty + 2, bar, nil, gray)
    HudTiles.tile(0x74, x + 8, y + 24)
    local edge = tx + 4 + geo.hpBarTiles
    for i = tx + 2, edge - 1 do HudTiles.tile(0x76, i * 8, y + 24) end
    HudTiles.tile(0x78, edge * 8, y + 24)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Exposed so the layout test can drive it at the CARTRIDGE'S OWN origins --
-- tile (0,0) for the foe, (9,7) for the player -- and check that what it puts
-- on screen there is what the 160x144 screen puts there.  That is the whole
-- guarantee this panel offers: the same block, handed a different corner.
WideBattle.gen2Panel = drawGen2Panel

-- One side's status box: name and level on the first line, a long HP bar
-- under it, and the numeric HP on the player's box only (the foe's exact
-- HP is never shown, like the original).
local function drawStatusPanel(battle, battler, x, y, player)
  -- EVERY cartridge this layout is reached for, not just Gen 2.  The wide
  -- option declines on Hoenn (BattleState:isWideBattleLayout), so the only
  -- games that reach here are Game Boy ones, and the Game Boy block is what
  -- they draw -- Gen 1's is the same block minus the exp bar.  The framed
  -- panel below stays as the shape no cartridge asks for.
  if not require("src.core.GameVersion").isGen3() then
    return drawGen2Panel(battle, battler, x, y, player, monoMode())
  end
  local tx, ty = math.floor(x / 8), math.floor(y / 8)
  local tw, th = player and 15 or 16, player and 5 or 4
  Font.drawBox(tx, ty, tw, th)
  love.graphics.setColor(0, 0, 0, 1)

  local nameWidth = player and 64 or 80
  Font.draw(fitName(battler.name, nameWidth), x + 8, y + 8)
  levelAt(battle, battler, x + tw * 8 - 40, y + 8)

  HudTiles.drawHPBar(battle.data, tx + 1, ty + 2, {
    hp = shownHP(battler),
    stats = battler.mon.stats,
  }, nil, monoMode(), tw - 5)

  if player then
    Font.draw(("%3d/%3d"):format(shownHP(battler), battler.mon.stats.hp),
      x + tw * 8 - 64, y + 24)
  end
end

-- the party ball rows DrawAllPokeballs puts up with the intro text, moved
-- out to the wide screen's own corners
local function drawIntroBalls(battle)
  if not battle.introBalls then return end
  if battle.enemyParty and
      (battle.kind == "trainer" or battle.kind == "link") then
    battle:drawBallRow(battle.enemyParty, 88, 40, -8)
  end
  battle:drawBallRow(battle.playerParty or battle.game.save.party, 216, 96, 8)
end

local function drawHUDs(battle, slide)
  local showStatus = StatusHUDVisibility.forBattle(battle)
  if showStatus and battle.enemy and not battle.showEnemyTrainer
      and not battle.enemySendingOut and not battle:growInScale(battle.enemy)
      and slide == 0 and not battle.introBalls and not battle.enemy.fainted then
    drawStatusPanel(battle, battle.enemy, 0, 0, false)
  end

  -- No player status panel in a safari / old-man battle: no mon of the
  -- player's is out.  Nothing replaces it either -- the ball count is a menu
  -- item, not a HUD element (DisplayBattleMenu prints wNumSafariBalls inside
  -- the battle menu box, engine/battle/core.asm:2074-2079), so it rides in
  -- drawCommandMenu below like the classic layout's (#540).
  if showStatus and not battle.safari and battle.player and not battle.demo
      and not battle.showPlayerBack and slide == 0 then
    -- WHERE THE PLAYER'S BLOCK SITS.  The framed panel was fifteen tiles
    -- wide and filled the corner; the Game Boy block is only four tiles plus
    -- the bar, so left at the same origin it would float with a gap after it.
    -- The cartridge hangs this block off the RIGHT edge of the screen -- its
    -- corner tile is the last column -- and the wide layout puts the player's
    -- status in the lower right for the same reason, so it hangs off this
    -- screen's right edge the same way.
    local px = 184
    if not require("src.core.GameVersion").isGen3() then
      px = (WideBattle.WIDTH / 8 - 1 - (3 + HudTiles.geometry().hpBarTiles)) * 8
    end
    drawStatusPanel(battle, battle.player, px, 56, true)
  end
  drawIntroBalls(battle)
end

local function drawMessageBox(battle)
  Font.drawBox(0, 13, 38, 5)
  love.graphics.setColor(0, 0, 0, 1)
  if battle.scrollPx and battle.scrollPx > 0 then
    battle.scrollPx = battle.scrollPx - 2
    if battle.scrollPx <= 0 then battle.scrollPx = nil end
  end
  local off = battle.scrollPx or 0
  local ys = { 112, 128 }
  for li, line in ipairs(battle.shown or {}) do
    local y = (ys[li] or 128) + off
    for i = 1, #line do
      Font.drawCode(line[i], 8 + (i - 1) * 8, y)
    end
  end
  if (battle.msgWaiting or battle.msgPrompt) and battle.frame % 60 < 30 then
    Font.drawCode(0xEE, 288, 132)
  end
end

local function drawCommandMenu(battle)
  local col = (battle.menuIndex - 1) % 2
  local row = math.floor((battle.menuIndex - 1) / 2)
  if battle.safari then
    Font.drawBox(0, 13, 38, 5)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("BALLx"), 16, 112)
    -- wNumSafariBalls immediately after the label, as at hlcoord 7,14
    -- (engine/battle/core.asm:2074-2079) (#540)
    Font.draw(("%2d"):format(battle.safari.balls), 56, 112)
    Font.draw(Strings("BAIT"), 168, 112)
    Font.draw(Strings("THROW ROCK"), 16, 128)
    Font.draw(Strings("RUN"), 168, 128)
    Font.drawCode(0xED, col == 0 and 8 or 160, 112 + row * 16)
    return
  end

  -- the prompt on the left, the 2x2 commands on the right
  Font.drawBox(0, 13, 20, 5)
  Font.drawBox(20, 13, 18, 5)
  love.graphics.setColor(0, 0, 0, 1)
  -- The old-man / PROF.OAK catch demo has no party, so makeOldManDemo parks
  -- the WILD mon in battle.player as a placeholder (BattleState:1209).  The
  -- classic layout's demo branch never names anyone (DisplayBattleMenu,
  -- core.asm:2038-2049, just draws the menu), so naming it here printed
  -- "What will PIKACHU do?" over Oak's scripted throw (#557).  Leave the
  -- prompt side blank and run the same scripted hand the classic does.
  if battle.demo then
    Font.draw(Strings("FIGHT"), 176, 112)
    Font.drawCode(0xE1, 240, 112); Font.drawCode(0xE2, 248, 112)
    Font.draw(Strings("ITEM"), 176, 128)
    Font.draw(Strings("RUN"), 240, 128)
    -- next to FIGHT for the first 80 frames, then ITEM
    Font.drawCode(0xED, 168, (battle.demoTimer or 0) <= 80 and 112 or 128)
    return
  end
  Font.draw(Strings("What will"), 8, 112)
  local who = battle.player and battle.player.name or ""
  Font.draw(fitName(who, 112) .. Strings(" do?"), 8, 128)
  Font.draw(Strings("FIGHT"), 176, 112)
  Font.drawCode(0xE1, 240, 112) -- 'PK'
  Font.drawCode(0xE2, 248, 112) -- 'MN'
  Font.draw(Strings("ITEM"), 176, 128)
  Font.draw(Strings("RUN"), 240, 128)
  Font.drawCode(0xED, col == 0 and 168 or 232, 112 + row * 16)
end

local function drawMoveDetails(battle, move)
  Font.drawBox(28, 13, 10, 5)
  if not move then return end
  local def = battle.data.moves[move.id]
  if not def then return end
  local maxPP = def.pp + (move.ppUps or 0) * math.floor(def.pp / 5)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(("PP %2d/%2d"):format(move.pp or 0, maxPP), 232, 112)
  Font.draw(fitName(TypeChart.displayName(def.type), 64), 232, 128)
end

local function drawMoveGrid(battle, moves, selected)
  -- The 8px font needs 28 tiles for two complete twelve-character move
  -- names plus their cursors; the details panel gets the other ten.
  Font.drawBox(0, 13, 28, 5)
  love.graphics.setColor(0, 0, 0, 1)
  for i, move in ipairs(moves or {}) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local x, y = col == 0 and 16 or 120, 112 + row * 16
    local def = battle.data.moves[move.id]
    Font.draw(fitName(def and def.name or move.id or "", 96), x, y)
  end
  local col = (selected - 1) % 2
  local row = math.floor((selected - 1) / 2)
  Font.drawCode(0xED, col == 0 and 8 or 112, 112 + row * 16)
  drawMoveDetails(battle, moves and moves[selected])
end

local function drawMoveMenu(battle)
  drawMoveGrid(battle, battle.player.curMoves, battle.moveIndex)
  if battle.moveSwapIndex then
    local col = (battle.moveSwapIndex - 1) % 2
    local row = math.floor((battle.moveSwapIndex - 1) / 2)
    Font.drawCode(0xEC, col == 0 and 8 or 112, 112 + row * 16)
  end
end

local function drawTextArea(battle)
  if not UIVisibility.bottomVisible(battle, true) then return end
  if battle.phase == "messages" and (battle.current or battle.animPlaying) then
    drawMessageBox(battle)
  elseif battle.phase == "menu" then
    drawCommandMenu(battle)
  elseif battle.phase == "moveSelect" then
    drawMoveMenu(battle)
  elseif battle.phase == "mimicSelect" then
    drawMoveGrid(battle, battle.mimicMoves, battle.mimicIndex)
  else
    Font.drawBox(0, 13, 38, 5)
  end
end

-- Battle animations are authored in the original 160px coordinate space.
-- Shift each complete OAM frame as one rigid group between the new player
-- and enemy anchors: drawing the whole animation through both side regions
-- would duplicate any tiles overlapping the other side's source range (most
-- visibly the send-out POOF reappearing on the far right).
-- ...and the band it is blended across is the two PICTURES, with room to
-- overshoot at both ends.
--
-- Reported from play: "with gen2 the pokeballs when thrown have some weird
-- effects with widescreen mode on".  A thrown ball is the one animation that
-- CROSSES this map rather than sitting at one end of it, so it is the one
-- that shows what the map does wrong.
--
-- The band used to be 40..120 in source pixels, hard-clamped, and neither
-- number is either Pokemon.  The two pics stand at 26 and 124 (see
-- CLASSIC_GEOMETRY.anchor), so:
--
--   * the throw began LEFT of the band, where the clamp holds the offset
--     flat -- the ball crept along at source speed, crossed 40, and jumped to
--     roughly two and a half times that speed for the rest of its flight;
--   * the ball comes to rest ON the far end of the band, where the clamp bites
--     again -- so the capture wobble was amplified on the frames that leaned
--     left and flattened on the ones that leaned right, which is the tilt
--     reading as a twitch;
--   * the y term slid 8 -> 0 across the same kinked t, so the arc came down
--     sooner on one side than it went up on the other.
--
-- Anchoring the band on the pictures and letting t run a fifth of the way
-- past each end makes the map ONE straight line over everything an animation
-- actually occupies: the ball still has to cover the extra 116 pixels between
-- the two, because the foe really is that much further away, but it covers
-- them at one speed and its resting wobble is symmetrical.
WideBattle.ANCHOR_X = { player = 26, enemy = 124 }
WideBattle.ANCHOR_DX = { player = 20, enemy = 136 }
WideBattle.ANCHOR_DY = { player = 8, enemy = 0 }
WideBattle.ANCHOR_OVERSHOOT = 0.2

function WideBattle.animationOffset(sprites)
  if not sprites or #sprites == 0 then return 0, 0 end
  local minX, maxX = math.huge, -math.huge
  for _, sprite in ipairs(sprites) do
    minX = math.min(minX, sprite.x - 8)
    maxX = math.max(maxX, sprite.x)
  end
  local center = (minX + maxX) / 2
  local from, to = WideBattle.ANCHOR_X.player, WideBattle.ANCHOR_X.enemy
  local t = (center - from) / (to - from)
  local slack = WideBattle.ANCHOR_OVERSHOOT
  t = math.max(-slack, math.min(1 + slack, t))
  local dx = WideBattle.ANCHOR_DX.player
             + (WideBattle.ANCHOR_DX.enemy - WideBattle.ANCHOR_DX.player) * t
  local dy = WideBattle.ANCHOR_DY.player
             + (WideBattle.ANCHOR_DY.enemy - WideBattle.ANCHOR_DY.player) * t
  return math.floor(dx + 0.5), math.floor(dy + 0.5)
end

local function currentAnimationSprites(battle)
  if battle.animPlaying and battle.animPlayer then
    local step = battle.animPlayer.steps[battle.animPlayer.stepIndex]
    return step and step.sprites
  end
  if battle.lockedBall and battle.animPlayer then
    return battle.lockedBall
  end
end

local function drawAnimationLayer(battle)
  local sprites = currentAnimationSprites(battle)
  if not sprites or #sprites == 0 then return end
  local dx, dy = WideBattle.animationOffset(sprites)
  inRegion(0, 0, WideBattle.WIDTH, WideBattle.FIELD_BOTTOM, dx, dy,
    function() battle:drawAnimLayer(false) end)
end

-- The whole 304x144 composition for one frame.
function WideBattle.draw(battle)
  local g = love.graphics
  -- The field is the display mode's paper.  Under a forced-mono mode the
  -- whole surface is remapped downstream (WideBattle.zones), so the field
  -- goes down as DMG white and comes out of that pass as the mode's paper;
  -- painting the resolved shade there would run it through the remap twice
  -- and land a shade off the letterbox the renderer fills around it.
  if monoMode() then
    g.setColor(1, 1, 1, 1)
  else
    g.setColor(PaletteFX.paperShade(battle.data))
  end
  g.rectangle("fill", 0, 0, WideBattle.WIDTH, WideBattle.HEIGHT)
  -- AskName clears the field the same way the classic layout does
  if battle.blankForAskName then return end

  local fx = battle.fx
  local sx = (fx and fx.shakeX) or 0
  local sy = (fx and fx.shakeY) or 0
  if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
    sx = battle.frame % 4 < 2 and 2 or -2
  end
  -- same 2 px/frame silhouette slide the 160px layout uses
  local slide = (battle.introSlide or 0)
                * require("src.core.Timing").BATTLE_SLIDE_PX_PER_FRAME

  -- Each side keeps its original sprite pixels and placement math: the two
  -- 160x144 OAM regions are translated apart and clipped into the wider
  -- battlefield rather than either monster being scaled.  wideRegion tells
  -- drawBattlerPic its own side window is already the clip.  A shake moves
  -- each region's clip with its contents, so a pic pushed toward a region
  -- edge is not sheared off it (a vertical shake used to clip the player's
  -- feet at FIELD_BOTTOM).
  battle.wideRegion = true
  inRegion(sx, 32 + sy, 160, WideBattle.FIELD_BOTTOM - 32, 20 + sx, 8 + sy,
    function() battle:drawPicsLayer(slide, 0, 0, "player", true) end)
  inRegion(160 + sx, sy, 144, WideBattle.FIELD_BOTTOM, 136 + sx, sy,
    function() battle:drawPicsLayer(slide, 0, 0, "enemy", true) end)
  battle.wideRegion = nil

  -- A battle sets rWY to 0 (engine/battle/core.asm), so the window the
  -- shakes move IS the whole screen: PredefShakeScreenHorizontally,
  -- PredefShakeScreenVertically and AnimationShakeScreenHorizontallySlow
  -- displace the HUDs and the message window along with the pics, exactly as
  -- drawClassic offsets its whole BG canvas.  Shaking only the two pic
  -- regions left the foe gliding sideways across a nailed-down screen on
  -- every applying-attack shake -- TAIL WHIP and every other status move
  -- (#562).  The OAM anim layer stays put, as it does in drawClassic.
  local function shaken(fn)
    if sx == 0 and sy == 0 then return fn() end
    g.push()
    g.translate(sx, sy)
    fn()
    g.pop()
  end
  shaken(function() drawHUDs(battle, slide) end)
  drawAnimationLayer(battle)
  shaken(function() drawTextArea(battle) end)

  if fx and fx.flash and fx.flash > 0 and battle.frame % 4 < 2 then
    g.setColor(1, 1, 1, 0.85)
    g.rectangle("fill", 0, 0, WideBattle.WIDTH, WideBattle.HEIGHT)
  end
  g.setColor(1, 1, 1, 1)
  if Runtime.wantsHook("battle.overlay") then
    Runtime.call("battle.overlay", function() end, battle)
  end
end

-- The palette zones for the wide surface.  The composition already resolves
-- species colors, paper shade and HP-bar colors itself, so the colorized
-- modes take the trueColor opt-out (`colors = false`) over the whole
-- surface; the forced-mono modes still want their whole-screen remap, and
-- get one sized to the wide surface instead of the 160x144 rectangle
-- PaletteFX.ensureZones would invent (which would leave 144 columns raw).
function WideBattle.zones()
  local w, h = WideBattle.WIDTH, WideBattle.HEIGHT
  if monoMode() then
    -- sendColors runs the mode's own substitution (CLASSIC's pea greens,
    -- the inverted permutation), exactly as it does for ensureZones' zone
    return { PaletteFX.zone(PaletteFX.GRAYS, 0, 0, w / 8 - 1, h / 8 - 1) }
  end
  return { { colors = false, x = 0, y = 0, w = w, h = h } }
end

-- 2x2 move-grid navigation: LEFT/RIGHT cross the row, UP/DOWN the column,
-- and a direction pointing at an empty slot holds the current one.
function WideBattle.moveGridIndex(index, count, direction)
  if count < 1 then return nil end
  local row = math.floor((index - 1) / 2)
  local col = (index - 1) % 2
  if direction == "left" or direction == "right" then
    local other = row * 2 + (1 - col) + 1
    return other <= count and other or index
  end
  local otherRow = 1 - row
  local other = otherRow * 2 + col + 1
  return other <= count and other or index
end

local DIRECTIONS = { "left", "right", "up", "down" }

-- the slot a directional press selects, or nil when none was pressed (the
-- caller then runs its normal list navigation / A / B / SELECT handling)
function WideBattle.navigate(index, count, input)
  for _, key in ipairs(DIRECTIONS) do
    if input:wasPressed(key) then
      return WideBattle.moveGridIndex(index, count, key)
    end
  end
  return nil
end

return WideBattle
