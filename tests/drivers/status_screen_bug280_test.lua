-- Driver: the status screen against engine/pokemon/status_screen.asm (#280).
-- The screen loads its OWN VRAM overlay (:86-97), which is the only reason
-- $73/$74 can be the <ID> and № glyphs here and cannot be in battle.  Also
-- covered: the dex column :109-113/:143-146, the mirrored pic :170, "<ID>№/"
-- :205-210, DrawLineBox :219-234, no level on page 2 :303-305, '<to>' :393-403.
--   POKEPORT_DRIVER=tests/drivers/status_screen_bug280_test.lua POKEPORT_IDENTITY=bug280 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Assets = require("src.render.Assets")
  local Font = require("src.render.Font")
  local HudTiles = require("src.render.HudTiles")
  local SummaryMenu = require("src.ui.SummaryMenu")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function top() return game.stack:top() end

  -- ---- preconditions no eye can check ------------------------------------
  -- A code that falls off the end of its sheet draws NOTHING (HudTiles' put
  -- returns early on a nil tile), which looks exactly like the old bug.
  U.log("======== #280 status screen: machine checks ========")
  check("HudTiles.statusTile exists", type(HudTiles.statusTile) == "function")
  check("HudTiles.tile still exists (battle layout untouched)",
        type(HudTiles.tile) == "function")
  local function tileCount(path)
    local ok, img = pcall(Assets.image, path)
    if not ok or not img then return 0 end
    local w, h = img:getDimensions()
    return math.floor(w / 8) * math.floor(h / 8)
  end
  local extra = tileCount("assets/generated/battle/font_battle_extra.png")
  U.log("font_battle_extra holds " .. extra .. " tiles at base $62")
  check("font_battle_extra reaches $70 <to> (needs 15 tiles)", extra >= 0x70 - 0x62 + 1)
  check("font_battle_extra reaches $73 <ID> (needs 18)", extra >= 0x73 - 0x62 + 1)
  check("font_battle_extra reaches $74 № (needs 19)", extra >= 0x74 - 0x62 + 1)
  check("battle_hud_2 has the 1 tile the status overlay copies to $78",
        tileCount("assets/generated/battle/battle_hud_2.png") >= 1)
  check("battle_hud_3 has the 2 tiles the status overlay copies to $76",
        tileCount("assets/generated/battle/battle_hud_3.png") >= 2)

  -- ---- the fixture -------------------------------------------------------
  -- NIDORINO: the intro shows the same sprite flipped (src/ui/OakSpeech.lua)
  -- so the mirror has a reference, and dex 33 makes the leading zero visible.
  local mon = Pokemon.new(game.data, "NIDORINO", 42)
  local maxed = Pokemon.new(game.data, "MEW", 100)
  mon.hp = math.max(1, math.floor(mon.stats.hp * 0.4))
  game.save.party = { mon, maxed }
  game.save.player.name = "RED"
  local dex = game.data.pokemon.NIDORINO.dex
  check("NIDORINO's dex number resolves", type(dex) == "number")
  U.log(("fixture: NIDORINO :L%d, dex %03d, %d/%d HP; MEW :L100 in slot 2")
          :format(mon.level, dex or 0, mon.hp, mon.stats.hp))

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  -- ---- open the status screen through the real UI ------------------------
  local function cursorTo(menu, field, want)
    for _ = 1, 40 do
      if not menu or menu[field] == want then return menu and menu[field] == want end
      U.tap(game, menu[field] < want and "down" or "up")
      U.wait(3)
    end
    return menu[field] == want
  end

  local function openStatsFor(slot)
    U.tap(game, "start")
    U.wait(10)
    local menu = top()
    if not (menu and menu.screenId == "StartMenu") then return nil, "no start menu" end
    local row
    for i, it in ipairs(menu.items or {}) do
      if it.label == "POKéMON" then row = i break end
    end
    if not row or not cursorTo(menu, "index", row) then return nil, "no POKéMON row" end
    U.tap(game, "a")
    U.wait(10)

    local party = top()
    if not (party and party.screenId == "PartyMenu") then return nil, "no party menu" end
    if not cursorTo(party, "index", slot) then return nil, "cursor never reached the slot" end
    U.tap(game, "a") -- opens the STATS/SWITCH/... submenu
    U.wait(8)
    if not party.submenu then return nil, "submenu never opened" end
    local subRow
    for i, it in ipairs(party.subItems or {}) do
      if it.action == "stats" then subRow = i break end
    end
    if not subRow or not cursorTo(party, "subIndex", subRow) then
      return nil, "no STATS row"
    end
    U.tap(game, "a")
    U.wait(20)
    local screen = top()
    if getmetatable(screen) ~= SummaryMenu and screen.screenId ~= "SummaryMenu" then
      return nil, "status screen never opened"
    end
    return screen
  end

  -- ---- record one real rendered frame ------------------------------------
  -- SummaryMenu.isOpaque is true, so StateStack:draw starts at it: everything
  -- recorded below belongs to this screen and nothing under it.
  local rec
  local realStatusTile, realTile = HudTiles.statusTile, HudTiles.tile
  local realDraw, realCode = Font.draw, Font.drawCode
  local realGDraw = love.graphics.draw

  local function instrument()
    rec = { status = {}, battle = {}, text = {}, code = {}, quads = {}, imgs = {} }
    HudTiles.statusTile = function(code, x, y, tint)
      rec.status[#rec.status + 1] = { code = code, x = x, y = y }
      return realStatusTile(code, x, y, tint)
    end
    HudTiles.tile = function(code, x, y, tint)
      rec.battle[#rec.battle + 1] = { code = code, x = x, y = y }
      return realTile(code, x, y, tint)
    end
    Font.draw = function(text, x, y)
      rec.text[#rec.text + 1] = { s = tostring(text), x = x, y = y }
      return realDraw(text, x, y)
    end
    Font.drawCode = function(code, x, y)
      rec.code[#rec.code + 1] = { code = code, x = x, y = y }
      return realCode(code, x, y)
    end
    love.graphics.draw = function(...)
      local a = { ... }
      -- draw(image, quad, x, y) vs draw(image, x, y, r, sx, sy).  Key off
      -- "argument 2 is not a number" rather than its type: the real Quad is
      -- userdata but the tests/love_stub one is a table.
      if a[2] ~= nil and type(a[2]) ~= "number" and type(a[3]) == "number" then
        -- a tile that actually reached the screen, so a recorded statusTile
        -- call with no draw behind it means a MISSING glyph
        rec.quads[#rec.quads + 1] = { x = a[3], y = a[4] }
      else
        rec.imgs[#rec.imgs + 1] = { img = a[1], x = a[2], y = a[3],
                                    r = a[4], sx = a[5], sy = a[6] }
      end
      return realGDraw(...)
    end
  end

  local function release()
    HudTiles.statusTile, HudTiles.tile = realStatusTile, realTile
    Font.draw, Font.drawCode = realDraw, realCode
    love.graphics.draw = realGDraw
  end

  local function capture()
    instrument()
    U.wait(2)
    release()
    return rec
  end

  local function hasTile(list, code, x, y)
    for _, e in ipairs(list) do
      if e.code == code and e.x == x and e.y == y then return true end
    end
    return false
  end
  local function anyTile(list, code)
    for _, e in ipairs(list) do if e.code == code then return e end end
    return nil
  end
  local function hasText(list, s, x, y)
    for _, e in ipairs(list) do
      if e.s == s and e.x == x and e.y == y then return true end
    end
    return false
  end
  local function drewAt(list, x, y)
    for _, e in ipairs(list) do
      if e.x == x and e.y == y then return true end
    end
    return false
  end

  -- ======== page 1 =========================================================
  U.log("======== #280 page 1 ========")
  local screen, why = openStatsFor(1)
  if not check("status screen opened" .. (why and (" (" .. why .. ")") or ""),
               screen ~= nil) then
    U.log("cannot continue without the status screen")
  else
    local p1 = capture()
    U.shot(game, DIR .. "/bug280_page1.png")

    -- (1) MIRRORED PIC: status_screen.asm:170
    local flipped
    for _, e in ipairs(p1.imgs) do
      if e.img == screen.sprite and type(e.sx) == "number" and e.sx < 0 then
        flipped = e
      end
    end
    check("the pic is drawn mirrored (negative x scale, asm:170)", flipped ~= nil)
    if flipped then
      U.log(("pic drawn at x=%d y=%d scale %d,%d"):format(flipped.x, flipped.y,
                                                          flipped.sx, flipped.sy))
    end

    -- (2) № GLYPH + DEX COLUMN: asm:109-113 and :143-146
    check("№ is the single tile $74 at (1,7) = px (8,56)",
          hasTile(p1.status, 0x74, 8, 56))
    check("...and it actually reached the screen (tile exists in the sheet)",
          drewAt(p1.quads, 8, 56))
    check("<DOT> is drawn as the charmap glyph $F2 at (2,7) = px (16,56)",
          hasTile(p1.code, 0xF2, 16, 56))
    check("the 3 dex digits start at (3,7) = px (24,56), a column left of the old \"No.\"",
          hasText(p1.text, ("%03d"):format(dex or 0), 24, 56))
    local spelled = false
    for _, e in ipairs(p1.text) do
      if e.s:find("No.", 1, true) or e.s:find("IDNo", 1, true) then spelled = true end
    end
    check("nothing spells \"No.\" out of letter tiles any more", not spelled)

    -- (3) LEVEL ON PAGE 1: PrintLevel at (14,2) = px (112,16)
    check("PrintLevel's :L tile $6E sits at (14,2) = px (112,16)",
          hasTile(p1.status, 0x6E, 112, 16))
    check("...with the level digits right after it at px (120,16)",
          hasText(p1.text, tostring(mon.level), 120, 16))

    -- (4) "<ID>№/": asm:205-210, three columns, not five letters
    check("<ID> is the single tile $73 at (10,13) = px (80,104)",
          hasTile(p1.status, 0x73, 80, 104))
    check("№ repeats at (11,13) = px (88,104)", hasTile(p1.status, 0x74, 88, 104))
    check("...and both reached the screen", drewAt(p1.quads, 80, 104)
                                            and drewAt(p1.quads, 88, 104))
    check("the slash follows at px (96,104)", hasText(p1.text, "/", 96, 104))

    -- (5) DrawLineBox rides the STATUS overlay, so $73 stays free for <ID>
    check("DrawLineBox's vertical is $78, not $73 (asm:222)",
          anyTile(p1.status, 0x78) ~= nil)
    local wrongVertical = false
    for _, e in ipairs(p1.status) do
      -- a $73 anywhere other than the two <ID> columns would be a line tile
      if e.code == 0x73 and not (e.x == 80 and e.y == 104) then wrongVertical = true end
    end
    check("no $73 is used as a line tile on this screen", not wrongVertical)
    check("the corner $77 and the run $76 come off the status overlay too",
          anyTile(p1.status, 0x77) ~= nil and anyTile(p1.status, 0x76) ~= nil)
    check("the HP bar still comes off the BATTLE table ($62-$6D are identical)",
          anyTile(p1.battle, 0x71) ~= nil)

    -- ======== page 2 =======================================================
    U.log("======== #280 page 2 ========")
    U.tap(game, "a") -- A flips the page (WaitForTextScrollButtonPress)
    U.wait(10)
    check("A flipped to page 2", screen.page == 2)
    local p2 = capture()
    U.shot(game, DIR .. "/bug280_page2.png")

    -- (6) NO LEVEL IN THE HEADER: ClearScreenArea (9,2) 5x10, asm:303-305
    check("no :L tile at the header slot (14,2) on page 2",
          not hasTile(p2.status, 0x6E, 112, 16))
    check("and no level digits there either",
          not hasText(p2.text, tostring(mon.level), 120, 16))

    -- (7) EXP RIGHT-ALIGNED: PrintNumber 7 columns at (12,4) = px (96,32)
    check("the exp is padded to 7 columns at px (96,32), not left-aligned",
          hasText(p2.text, ("%7d"):format(mon.exp), 96, 32))

    -- (8) THE MISSING '<to>': asm:393-397, tile $70 at (14,6) = px (112,48)
    check("'<to>' is the single tile $70 at (14,6) = px (112,48)",
          hasTile(p2.status, 0x70, 112, 48))
    check("...and it reached the screen", drewAt(p2.quads, 112, 48))
    check("PrintLevel follows at (16,6) = px (128,48)",
          hasTile(p2.status, 0x6E, 128, 48))
    check("the № header line is still on page 2 (it is shared)",
          hasTile(p2.status, 0x74, 8, 56))

    -- (9) the shared PrintLevel port: level 100 loses the ':L' to its third
    -- digit (home/pokemon.asm), which is the side effect to expect
    U.tap(game, "a") -- page 2 + A closes the screen
    U.wait(20)
    for _ = 1, 20 do
      if top() and top().screenId == "PartyMenu" then break end
      U.tap(game, "b")
      U.wait(6)
    end
    for _ = 1, 20 do
      if top() == game.overworld then break end
      U.tap(game, "b")
      U.wait(6)
    end
    local mewScreen = openStatsFor(2)
    if check("status screen opened for the :L100 MEW", mewScreen ~= nil) then
      local pm = capture()
      U.shot(game, DIR .. "/bug280_level100.png")
      check("at level 100 PrintLevel drops the :L tile entirely",
            not hasTile(pm.status, 0x6E, 112, 16))
      check("...and the three digits start where the :L tile was, px (112,16)",
            hasText(pm.text, "100", 112, 16))
    end
  end

  U.log(("======== machine checks: %d passed, %d failed ========"):format(pass, fail))

  -- ---- hand off with the screen open -------------------------------------
  -- back to slot 1, page 1: the screen the reporter photographed
  for _ = 1, 30 do
    if top() == game.overworld then break end
    U.tap(game, "b")
    U.wait(6)
  end
  openStatsFor(1)

  U.log("NIDORINO's status page 1 is up; A flips to page 2, A again closes.")
  U.log("Page 1: pic faces RIGHT, the dex line is one '№' glyph + raised dot +")
  U.log("'033', ':L42' in the header, ID line is 'ID' '№' '/'.  Page 2: no")
  U.log("level, EXP right-aligned, a narrow 'to' before ':L43' (#280).")
  U.log("Slot 2's :L100 MEW drops its ':L': that is PrintLevel, not a bug.")

  while true do
    coroutine.yield()
  end
end
