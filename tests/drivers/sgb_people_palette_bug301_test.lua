-- Driver: in SGB mode a character wears the palette of the map it stands on,
-- not the GBC boot ROM's object palette (#301).  pokered never sends OBJ_TRN
-- (data/sgb/sgb_packets.asm), and home/fade.asm:68 FadePal4 leaves rOBP0 = $D0,
-- so OBJ colours lift to DMG shades 0/1/3 and the zone shader owns the colour.
--   POKEPORT_DRIVER=tests/drivers/sgb_people_palette_bug301_test.lua \
--     POKEPORT_IDENTITY=bug301 POKEPORT_VERSION=red SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Probe = dofile("tests/drivers/shot_probe.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(ok, msg)
    U.log(ok and "PASS" or "FAIL", msg)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function rgb(c)
    return c and ("(%d,%d,%d)"):format(c[1], c[2], c[3]) or "nil"
  end
  local function ramp(p)
    if not p then return "nil" end
    local s = {}
    for i = 1, 4 do s[i] = rgb(p[i]) end
    return table.concat(s, " ")
  end

  -- a party + starter flag so the overworld behaves like a real save
  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))
  end
  -- Game:applyOptions re-reads save.options.colors every frame's worth of
  -- option handling, so a bare setMode() would be reverted under us.
  game.save.options = game.save.options or {}
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")

  -- ---- Part 1: the render decisions no screenshot can spell out -----------
  check(PaletteFX.usesSpriteObp("gbc") == false,
        "SGB bakes NO object palette (it cannot colour an OBJ apart from the BG)")
  check(PaletteFX.usesSpriteObp("ogred") == true,
        "OG RED still does (the GBC boot ROM really does hand out one OBJ palette)")
  check(PaletteFX.usesSpriteObp("og") == false
        and PaletteFX.usesSpriteObp("og_inv") == false
        and PaletteFX.usesSpriteObp("gbc_inv") == false
        and PaletteFX.usesSpriteObp("classic") == false
        and PaletteFX.usesSpriteObp("redpp") == false,
        "no other mode bakes one either")

  local obp = PaletteFX.dmgObj()
  U.log("rOBP0 bake ramp:", ramp(obp))
  -- FadePal4's second entry, `dc 3,1,0,0` = $D0.  Index 1 is never read (OBJ
  -- colour 0 is keyed to alpha); 2..4 are OBJ colours 1..3 as shades 0/1/3.
  check(obp ~= nil and obp[2][1] == 255, "OBJ colour 1 -> DMG shade 0 (255)")
  check(obp ~= nil and obp[3][1] == 170, "OBJ colour 2 -> DMG shade 1 (170)")
  check(obp ~= nil and obp[4][1] == 0, "OBJ colour 3 -> DMG shade 3 (0)")
  local grey = true
  for i = 1, 4 do
    if obp[i][1] ~= obp[i][2] or obp[i][2] ~= obp[i][3] then grey = false end
  end
  check(grey, "the bake stays in DMG GREYS, so the zone shader still owns the colour")

  local OGOBJ = PaletteFX.ogObj()
  local clash = false
  for i = 1, 4 do
    for j = 1, 4 do
      if obp[i][1] == OGOBJ[j][1] and obp[i][2] == OGOBJ[j][2]
         and obp[i][3] == OGOBJ[j][3] and OGOBJ[j][1] ~= OGOBJ[j][2] then
        clash = true
      end
    end
  end
  check(not clash, "no boot-ROM object colour is baked into an SGB sprite")

  -- ---- Part 2: stand next to a person, on two maps with unlike palettes ---
  local function npcNamed(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  -- Teleport to `stand`; if a map edit or a mod moved the NPC out of reach,
  -- take any free walkable neighbour of where it actually is and face back.
  local function standNextTo(mapId, npcName, stand)
    U.teleport(game, mapId, stand.x, stand.y, stand.facing)
    U.wait(12)
    local ow = game.overworld
    local npc = ow and npcNamed(ow, npcName)
    if not npc then
      check(false, npcName .. " object loaded on " .. mapId)
      return ow, nil
    end
    local fx, fy = ow.player:facingCell()
    if ow:npcAtCell(fx, fy) ~= npc then
      local sides = {
        { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
      }
      for _, s in ipairs(sides) do
        local cx, cy = npc.cellX + s[1], npc.cellY + s[2]
        if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
          U.log(("stand cell (%d,%d) is no longer beside %s -- using")
                  :format(stand.x, stand.y, npcName), cx, cy, "facing", s[3])
          U.teleport(game, mapId, cx, cy, s[3])
          U.wait(12)
          ow = game.overworld
          npc = npcNamed(ow, npcName)
          break
        end
      end
    end
    local ax, ay = ow.player:facingCell()
    check(npc ~= nil and ow:npcAtCell(ax, ay) == npc,
          "player is standing face to face with " .. npcName .. " on " .. mapId)
    return ow, npc
  end

  -- Every colour a correct SGB frame may contain: the map's own four plus the
  -- letterbox black.  Before the fix the boot-ROM greens were on screen and
  -- belonged to no palette the map ever asked for.
  local function paletteAudit(label, palette)
    local shot = Probe.grab()
    if not shot then
      U.log("WARN pixel probe unavailable; judge", label, "by eye only")
      return
    end
    local top, total = Probe.top(shot, 8)
    U.log(("probe[%s] %d px sampled, top colours: %s")
            :format(label, total, Probe.fmt(top)))
    local allowed = { { 0, 0, 0 } }
    for i = 1, 4 do allowed[#allowed + 1] = palette[i] end
    local strays = {}
    for _, c in ipairs(top) do
      local ok = false
      for _, a in ipairs(allowed) do
        if c[1] == a[1] and c[2] == a[2] and c[3] == a[3] then ok = true end
      end
      -- ignore the thin filtered edges: only a colour with real area on
      -- screen is evidence of a wrong palette
      if not ok and c.share > 0.002 then
        strays[#strays + 1] = ("(%d,%d,%d) %.1f%%")
          :format(c[1], c[2], c[3], c.share * 100)
      end
    end
    check(#strays == 0, label
          .. ": every colour with real area comes from the map's own palette"
          .. (#strays > 0 and (" -- strays: " .. table.concat(strays, ", ")) or ""))
    return shot
  end

  local function countIn(shot, wanted)
    if not shot then return nil end
    local counts = Probe.count(shot, wanted)
    local parts = {}
    for name, n in pairs(counts) do parts[#parts + 1] = ("%s=%d"):format(name, n) end
    table.sort(parts)
    U.log("   ", table.concat(parts, "  "))
    return counts
  end

  -- OBJ colour 0 is transparent on the hardware and the bake keys it to alpha.
  -- A love Image exposes no pixels, so the only way to read that back is to
  -- draw it into a cleared canvas.  A guard, not a gate: the extracted sheets
  -- already ship a tRNS key, so this only fires if a later change hands a
  -- pipeline or the tilt pass an unkeyed image and the sprite grows a backdrop.
  local function transparentShare(spr)
    if not (spr and spr.resolveImage and love.graphics.newCanvas) then return nil end
    local ok, share = pcall(function()
      local img = spr:resolveImage()
      local w, h = img:getWidth(), img:getHeight()
      local cv = love.graphics.newCanvas(w, h)
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, 0, 0)
      love.graphics.setCanvas()
      local id = cv:newImageData()
      local clear = 0
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local _, _, _, a = id:getPixel(x, y)
          if a < 0.02 then clear = clear + 1 end
        end
      end
      return clear / (w * h)
    end)
    love.graphics.setCanvas()
    return ok and share or nil
  end

  local GBC_OBJ = PaletteFX.ogObj()
  local BOOT = { bootGreen = GBC_OBJ[2], bootDarkGreen = GBC_OBJ[3] }

  -- ---- ROUTE_1, beside a YOUNGSTER, in grass -----------------------------
  -- ../pokered/data/maps/objects/Route1.asm: ROUTE1_YOUNGSTER2 walks
  -- left/right on (15, 13), so (14, 13) facing right is beside it.
  local ROUTE = PaletteFX.pal(game.data, "ROUTE")
  U.log("ROUTE palette:", ramp(ROUTE))
  local ow = standNextTo("ROUTE_1", "ROUTE1_YOUNGSTER2",
                         { x = 14, y = 13, facing = "right" })
  U.wait(40) -- let the grass / flower tile animation cycle
  U.shot(game, DIR .. "/bug301_1_route1_sgb.png")
  local shot = paletteAudit("ROUTE_1 / SGB", ROUTE)
  local c = countIn(shot, {
    bootGreen = BOOT.bootGreen, bootDarkGreen = BOOT.bootDarkGreen,
    routeGrassGreen = ROUTE[2], routeLightBlue = ROUTE[3],
  })
  if c then
    check(c.bootGreen == 0 and c.bootDarkGreen == 0,
          "no Game Boy Color boot-ROM green anywhere on the SGB screen (#301)")
    check(c.routeGrassGreen > 0,
          "ROUTE's own grass green IS on screen (the cap and the grass share it, #150)")
  end

  local spr = ow and ow.player and ow.player.sprite
  check(spr ~= nil and spr.image ~= nil and spr:resolveImage() ~= spr.image,
        "the player's sprite resolves to a BAKED image in SGB, not the raw sheet")
  local share = transparentShare(spr)
  if share == nil then
    U.log("WARN could not read the baked sprite back; judge transparency by eye")
  else
    U.log(("baked player sheet is %.1f%% fully transparent"):format(share * 100))
    check(share > 0.1,
          "OBJ colour 0 stays keyed to alpha, so a character has no backdrop")
  end

  -- ---- LAVENDER_TOWN, beside a COOLTRAINER, on a PINK palette ------------
  -- ../pokered/data/maps/objects/LavenderTown.asm: LAVENDERTOWN_COOLTRAINER_M
  -- stands on (9, 10), so (9, 9) facing down is beside it.  No green anywhere
  -- in this palette, so a green person here is unmistakable.
  local LAVENDER = PaletteFX.pal(game.data, "LAVENDER")
  U.log("LAVENDER palette:", ramp(LAVENDER))
  standNextTo("LAVENDER_TOWN", "LAVENDERTOWN_COOLTRAINER_M",
              { x = 9, y = 9, facing = "down" })
  U.wait(24)
  U.shot(game, DIR .. "/bug301_2_lavender_sgb.png")
  shot = paletteAudit("LAVENDER_TOWN / SGB", LAVENDER)
  c = countIn(shot, {
    bootGreen = BOOT.bootGreen, bootDarkGreen = BOOT.bootDarkGreen,
    lavenderPink = LAVENDER[2], routeGrassGreen = ROUTE[2],
  })
  if c then
    check(c.bootGreen == 0 and c.bootDarkGreen == 0,
          "no boot-ROM green in LAVENDER TOWN either")
    check(c.lavenderPink > 0,
          "the characters here wear LAVENDER's pink -- they changed with the map")
    check(c.routeGrassGreen == 0,
          "and no ROUTE green followed them over (nothing is palette-pinned)")
  end

  -- ---- OG RED, the mode that IS supposed to have an object palette -------
  -- A GBC boots the cartridge with one BG and one OBJ palette, so there the
  -- people really are green.  Losing that green means the fix went too far.
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")
  standNextTo("ROUTE_1", "ROUTE1_YOUNGSTER2",
              { x = 14, y = 13, facing = "right" })
  U.wait(30)
  U.shot(game, DIR .. "/bug301_3_route1_ogred.png")
  local ogShot = Probe.grab()
  c = countIn(ogShot, {
    bootGreen = BOOT.bootGreen, bootDarkGreen = BOOT.bootDarkGreen,
    ogBgRed = PaletteFX.GBC_BG[3], ogBgPink = PaletteFX.GBC_BG[2],
  })
  if c then
    check(c.bootGreen + c.bootDarkGreen > 0,
          "OG RED keeps its boot-ROM green characters (regression guard)")
    check(c.ogBgRed + c.ogBgPink > 0, "over OG RED's red terrain")
  end
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")
  U.wait(20)

  -- ---- tilt mode, as a guard rather than a gate --------------------------
  -- Tilt colorizes each billboard on its own, outside the whole-canvas zone
  -- pass, so it is the path most likely to disagree with the flat one.  Pure
  -- white and raw DMG grey belong to no SGB palette (they all open on paper,
  -- 255,239,255), so either one here means an uncolorized sheet got through.
  standNextTo("ROUTE_1", "ROUTE1_YOUNGSTER2",
              { x = 14, y = 13, facing = "right" })
  game.save.options.tilt = 2
  require("src.render.Tilt").setLevel(2)
  U.wait(70) -- the tilt tween is presentational and runs on real time
  U.shot(game, DIR .. "/bug301_4_route1_tilt_sgb.png")
  local tiltShot = Probe.grab()
  c = countIn(tiltShot, {
    pureWhite = { 255, 255, 255 }, rawGrey170 = { 170, 170, 170 },
    bootGreen = BOOT.bootGreen, paper = ROUTE[1],
  })
  if c then
    check(c.pureWhite == 0 and c.rawGrey170 == 0,
          "tilt billboards carry no uncolorized sheet pixels")
    check(c.bootGreen == 0, "and no boot-ROM green in tilt mode either")
  end
  game.save.options.tilt = 0
  require("src.render.Tilt").setLevel(0)
  U.wait(50)

  U.log(fails == 0 and "all #301 preconditions passed"
                    or (fails .. " #301 precondition(s) FAILED -- read up"))

  -- ---- Part 3: hand off, standing next to somebody, in the default mode ---
  standNextTo("ROUTE_1", "ROUTE1_YOUNGSTER2",
              { x = 14, y = 13, facing = "right" })

  U.log("You are on ROUTE 1 in SGB colour, face to face with a YOUNGSTER. Both")
  U.log("of you should take colour from the ground's own palette (Red's cap on")
  U.log("ROUTE's grass green) and change with every map you walk onto. #301")
  U.log("was everyone painted boot-ROM lime green everywhere. Shots in " .. DIR)

  while true do
    coroutine.yield()
  end
end
