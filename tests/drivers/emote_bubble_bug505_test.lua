-- Manual check on the "!" bubble a trainer pops when he spots you (#505).
-- The sheet is OBJ art, so it displays through OBP0, and GBPalNormal
-- (pokered home/palettes.asm:20-26, `ld a, %11010000 ; 3100`) shows OBJ
-- color 1 as shade 0.  The draw site blitted the raw png instead, leaving
-- the bubble's interior at its pre-OBP0 grey.  Do not add POKEPORT_SPEED:
-- the sight-line freeze and the 60-frame bubble hold are being watched.
--   POKEPORT_DRIVER=tests/drivers/emote_bubble_bug505_test.lua POKEPORT_IDENTITY=bug505 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Assets = require("src.render.Assets")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local failed = 0
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = failed + 1 end
    return ok
  end

  -- extraction, asset resolution and a renamed crop all look like the bug on
  -- screen (grey bubble, or no bubble at all), so separate them here first
  local bubble = game.data.field and game.data.field.emotionBubbles
  check("field data carries the emote sheet",
        type(bubble) == "table" and type(bubble.path) == "string")
  local crop = bubble and bubble.bubbles and bubble.bubbles[1]
  check("crop 1 is EXCLAMATION_BUBBLE 16x16 at the sheet origin",
        crop ~= nil and crop.name == "EXCLAMATION_BUBBLE"
        and crop.w == 16 and crop.h == 16 and crop.x == 0 and crop.y == 0)

  -- the source art is the pre-OBP0 art and is supposed to look grey: the
  -- body is OBJ color 1, which the extractor writes as DMG shade 1 (170),
  -- and OBJ color 0 (the corners) carries the sheet's tRNS alpha.  If this
  -- ever reads white the extractor changed and the bake below is moot.
  local BODY_X, BODY_Y = 4, 5   -- inside the outline, left of the "!" stem
  local EDGE_X, EDGE_Y = 1, 4   -- the black outline column
  if bubble and bubble.path then
    local ok, src = pcall(Assets.imageData, bubble.path)
    check("the sheet resolves and decodes: " .. bubble.path, ok and src ~= nil)
    if ok and src then
      local r = select(1, src:getPixel(BODY_X, BODY_Y))
      local _, _, _, ca = src:getPixel(0, 0)
      U.log(("source art body pixel %.3f, corner alpha %.3f"):format(r, ca))
      check("source body is the shade 1 grey the bug showed on screen",
            math.abs(r - 170 / 255) < 0.04)
      check("source corner is keyed out by tRNS", ca < 0.5)
    end
  end

  -- pokered data/maps/objects/Route3.asm:22 -- the Bug Catcher stands at
  -- (10, 6) with range RIGHT, so his line runs east along row 6 and (12, 6)
  -- is the detection tile.  Start one cell outside it and walk in.
  local MAP, TRAINER = "ROUTE_3", "ROUTE3_YOUNGSTER1"
  local stand = { x = 13, y = 6, facing = "left", walk = "left" }

  U.teleport(game, MAP, stand.x, stand.y, stand.facing)
  local ow = game.overworld
  local npc
  for _, n in ipairs(ow.npcs or {}) do
    if n.def and n.def.name == TRAINER then npc = n end
  end
  check("the Bug Catcher loaded on " .. MAP, npc ~= nil)

  -- a map edit that moves or re-aims him would park us facing empty grass,
  -- so re-derive the approach from where he actually is and which way he
  -- looks: stand three cells down his line and walk back along it
  if npc and (npc.cellX ~= 10 or npc.cellY ~= 6 or npc.facing ~= "right") then
    local away = { up = { 0, -1 }, down = { 0, 1 },
                   left = { -1, 0 }, right = { 1, 0 } }
    local back = { up = "down", down = "up", left = "right", right = "left" }
    local d = away[npc.facing] or away.right
    local cx, cy = npc.cellX + d[1] * 3, npc.cellY + d[2] * 3
    if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
      U.log("he is not at (10, 6) facing right any more, approaching from",
            cx, cy)
      stand = { x = cx, y = cy, facing = back[npc.facing] or "left",
                walk = back[npc.facing] or "left" }
      U.teleport(game, MAP, stand.x, stand.y, stand.facing)
      ow = game.overworld
    end
  end

  -- walk into the line one frame at a time and stop the moment the bubble
  -- is up, so the shot lands well inside the 60-frame hold
  local spotted = false
  for _ = 1, 90 do
    U.hold(game, stand.walk, 1)
    if ow.emote and ow.emote.npc and ow.emote.bubble ~= false then
      spotted = true
      break
    end
  end
  check("walking in triggered the bubble", spotted)
  U.log("player at", ow.player.cellX, ow.player.cellY,
        "bubble frames left:", ow.emote and ow.emote.frames)

  local shotPath = DIR .. "/bug505_emote.png"
  local wrote = U.shot(game, shotPath)
  check("the window rendered and the screenshot reached disk", wrote)

  -- what the human sees is one 16x16 blit of ow.emoteImg, so read that
  -- image back rather than hunting pixels in the framebuffer: draw it to a
  -- scratch canvas and sample it.  Canvas readback outside love.draw is not
  -- guaranteed on every driver, hence the pcall.
  local img = ow.emoteImg
  check("the draw site built its emote image", img ~= nil)
  if img then
    local ok, body, edge, corner = pcall(function()
      local canvas = love.graphics.newCanvas(img:getDimensions())
      love.graphics.setCanvas(canvas)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, 0, 0)
      love.graphics.setCanvas()
      local id = canvas:newImageData()
      local b = select(1, id:getPixel(BODY_X, BODY_Y))
      local e = select(1, id:getPixel(EDGE_X, EDGE_Y))
      local _, _, _, a = id:getPixel(0, 0)
      return b, e, a
    end)
    if ok then
      U.log(("baked body %.3f, outline %.3f, corner alpha %.3f")
              :format(body, edge, corner))
      check("the bubble body came out white, not the 170 grey of #505",
            body > 0.9)
      check("the outline is still black", edge < 0.1)
      check("the corners are still keyed out", corner < 0.5)
    else
      U.log("could not read the baked image back:", tostring(body))
      U.log("judge the colour off the screenshot alone")
    end
  end

  if failed > 0 then
    U.log(failed, "check(s) failed above; fix those before eyeballing anything")
  end

  -- put him back on the board so the moment can be replayed by hand
  U.wait(20)
  U.teleport(game, MAP, stand.x, stand.y, stand.facing)
  U.log("the bubble has already been triggered once and saved to " .. shotPath)
  U.log("its interior should read pure white with a black outline and the")
  U.log("grass showing through the corners; #505 was a flat mid grey inside.")
  U.log("hold " .. stand.walk .. " to walk into his line and pop it again.")

  while true do
    coroutine.yield()
  end
end
