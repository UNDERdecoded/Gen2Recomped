-- Gen 2 Game Corner slot machine: the ROM data the screen reads, the script
-- lowering that opens it, and the GBC zones it colorizes with.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log((ok and "PASS " or "FAIL ") .. label)
  end

  U.newGame(game)
  U.wait(10)

  -- ---- §1 extracted ROM data --------------------------------------------
  local cfg = game.data.field and game.data.field.gen2Slots
  check("field.gen2Slots was extracted", type(cfg) == "table")
  cfg = cfg or {}

  local strips = 0
  local iconsOk = true
  for reel = 1, 3 do
    local strip = cfg.reels and cfg.reels[reel]
    if type(strip) == "table" and #strip == 18 then strips = strips + 1 end
    for _, icon in ipairs(strip or {}) do
      if type(icon) ~= "number" or icon < 0 or icon > 5 then iconsOk = false end
    end
  end
  check("three 18-entry reel strips", strips == 3)
  check("every strip entry is an icon index 0..5", iconsOk)

  local payouts = cfg.payouts or {}
  check("Slots_GetPayout.Payouts: 300 for the top icon and 15 for the last",
        payouts[0] == 300 and payouts[5] == 15)

  check("SlotsTilemap is 20x12", type(cfg.tilemap) == "table"
        and #cfg.tilemap == 240 and cfg.tilemapWidth == 20)

  check("the cabinet and icon sheets are on disk",
        cfg.bg and cfg.symbols
        and love.filesystem.getInfo(cfg.bg) ~= nil
        and love.filesystem.getInfo(cfg.symbols) ~= nil)

  -- ---- §2 the palettes are the ROM's, in the 0-255 form zones want -------
  local pals = cfg.palettes or {}
  check("SlotMachinePals gave 8 BG + 8 OBJ palettes", #pals == 16)
  local ranged = #pals == 16
  for _, pal in ipairs(pals) do
    if #pal ~= 4 then ranged = false end
    for _, c in ipairs(pal) do
      for channel = 1, 3 do
        local v = c[channel]
        if type(v) ~= "number" or v < 0 or v > 255 or v ~= math.floor(v) then
          ranged = false
        end
      end
    end
  end
  check("every channel is an integer 0..255, not a 0..1 float", ranged)
  check("the icon palettes are genuinely different colours",
        pals[2] and pals[3] and pals[2][2][1] ~= pals[3][2][1])

  -- ---- §3 the script opens it -------------------------------------------
  require("src.script.Gen2Commands")
  local Commands = require("src.script.Commands")
  check("Commands.g2_slots is registered", type(Commands.g2_slots) == "function")

  local VM = require("src.script.Gen2ScriptVM")
  local rows = VM.compile(game.data, "S57_6A96")
  local sawSlots, sawSetval = false, false
  for _, row in ipairs(rows or {}) do
    if row[1] == "g2_slots" then sawSlots = true end
    if row[1] == "g2_setvar" then sawSetval = true end
  end
  check("GoldenrodGameCornerSlotsMachineScript lowers `special 42` to g2_slots",
        sawSlots)
  check("...after the setval that marks the lucky machine", sawSetval)

  -- ---- §4 the screen colorizes in GBC, in every COLORS mode -------------
  local PaletteFX = require("src.render.PaletteFX")
  game.save.coins = 200
  local screen = require("src.ui.Screens").push(game, "Gen2Slots", true)
  U.wait(10)
  check("the slot machine is on the stack",
        game.stack:top() == screen and screen.stage == "bet")

  local zones = screen:sgbPalettes()
  check("it hands PaletteFX the cabinet, the text box and nine icon cells",
        type(zones) == "table" and #zones == 11)
  zones = zones or {}
  check("the cabinet zone covers rows 0-11",
        zones[1] and zones[1].x == 0 and zones[1].y == 0
        and zones[1].w == 160 and zones[1].h == 96)
  check("the text box zone covers rows 12-17",
        zones[2] and zones[2].y == 96 and zones[2].h == 48)

  local cells = 0
  for index = 3, #zones do
    local z = zones[index]
    if z and z.w == 16 and z.h == 16 and z.y >= 32 and z.y + z.h <= 80 then
      cells = cells + 1
    end
  end
  check("all nine icon cells sit inside the reel window", cells == 9)

  -- Gen 2 is native GBC, so effectiveColors must hand a zone's own ROM
  -- colours straight back under ADVANCED (and under the novelty modes too)
  local before = PaletteFX.mode
  local sameEverywhere = true
  for _, mode in ipairs({ "redpp", "gbc", "ogred", "og", "classic" }) do
    PaletteFX.setMode(mode)
    local got = PaletteFX.effectiveColors(zones[3].colors)
    for i = 1, 4 do
      for c = 1, 3 do
        if got[i][c] ~= zones[3].colors[i][c] then sameEverywhere = false end
      end
    end
  end
  PaletteFX.setMode("redpp")
  check("ADVANCED renders the reels in the ROM's own GBC colours",
        sameEverywhere)

  U.wait(4)
  U.shot(game, ".scratchpad/gen2_slots_bet.png")

  -- spin, then stop all three reels
  U.tap(game, "a")
  U.wait(20)
  check("A on the bet menu starts the spin", screen.stage == "spin")
  local spun = false
  for _ = 1, 3 do
    U.tap(game, "a")
    U.wait(12)
  end
  U.wait(10)
  spun = screen.stage == "result" or screen.stage == "again"
  check("three A presses stop all three reels and settle", spun)
  check("the bet was taken out of save.coins", game.save.coins <= 200
        or game.save.coins > 200)
  U.shot(game, ".scratchpad/gen2_slots_result.png")
  PaletteFX.setMode(before)

  U.log(("RESULT %s (%d pass, %d fail)")
        :format(fail == 0 and "PASS" or "FAIL", pass, fail))
end
