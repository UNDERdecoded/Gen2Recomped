-- Card Flip (`special CardFlip`, bank $38): checks the ripped board data, the
-- bet grid's payouts, the lowering of special $2B, and that the screen hands
-- PaletteFX the ROM's own palettes so ADVANCED still renders in GBC colour.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, label)
    if cond then pass = pass + 1 else fail = fail + 1 end
    U.log(("%s %s"):format(cond and "PASS" or "FAIL", label))
  end

  U.newGame(game)

  -- 1. extracted ROM data ----------------------------------------------------
  local cfg = game.data.field and game.data.field.gen2CardFlip
  ok(type(cfg) == "table", "field.gen2CardFlip exists")
  cfg = cfg or {}

  ok(type(cfg.tilemap) == "table" and #cfg.tilemap == 132,
     ("CardFlipTilemap is 132 bytes (got %s)"):format(cfg.tilemap and #cfg.tilemap))
  ok(cfg.tilemapWidth == 11, "board is 11 columns wide")
  ok(type(cfg.faceUp) == "table" and #cfg.faceUp == 30 and cfg.faceUpWidth == 5,
     "FaceUpCardTilemap is 5x6")

  local cards = cfg.cards or {}
  ok(cards[0] and cards[0].base == 0x4e, "card 0 is Pikachu, tile $4E")
  ok(cards[1] and cards[1].base == 0x57, "card 1 is Jigglypuff, tile $57")
  ok(cards[2] and cards[2].base == 0x69, "card 2 is Poliwag, tile $69")
  ok(cards[3] and cards[3].base == 0x60, "card 3 is Oddish, tile $60")
  ok(cards[23] and cards[23].digit == 0xfc, "card 23 shows the digit 6 ($FC)")

  local slots = cfg.slots or {}
  ok(#slots == 48, ("48 bet squares (got %d)"):format(#slots))
  ok(slots[1] and slots[1].shape == "Impossible", "square 0 is Impossible")
  ok(slots[3] and slots[3].shape == "PokeGroupPair", "square 2 selects a Pokemon pair")
  ok(slots[9] and slots[9].shape == "PokeGroup", "square 8 selects one Pokemon")
  ok(slots[13] and slots[13].shape == "NumGroupPair", "square 12 selects a number pair")
  ok(slots[14] and slots[14].shape == "NumGroup", "square 13 selects one number")
  ok(slots[15] and slots[15].shape == "SingleTile", "square 14 selects one card")

  local shapes = cfg.shapes or {}
  ok(shapes.SingleTile and #shapes.SingleTile == 6, "SingleTile is six sprites")
  ok(shapes.PokeGroupPair and #shapes.PokeGroupPair == 38, "PokeGroupPair is 38 sprites")

  for _, name in ipairs({ "bg", "cursor" }) do
    local path = cfg[name]
    ok(type(path) == "string" and love.filesystem.getInfo(path) ~= nil,
       ("cardflip %s art on disk"):format(name))
  end

  -- 2. palettes -------------------------------------------------------------
  local pals = cfg.palettes or {}
  ok(#pals == 9, ("CardFlip_InitAttrPals gave 9 palettes (got %d)"):format(#pals))
  local ranged = #pals == 9
  for _, pal in ipairs(pals) do
    for _, color in ipairs(pal) do
      for channel = 1, 3 do
        local v = color[channel]
        if type(v) ~= "number" or v < 0 or v > 255 or v ~= math.floor(v) then
          ranged = false
        end
      end
    end
  end
  ok(ranged, "palette channels are integers 0-255")
  ok(pals[2] and pals[2][2] and pals[2][2][1] == 239, "palette 1 is Pikachu yellow")
  ok(pals[9] and pals[9][3] and pals[9][3][1] == 255 and pals[9][3][2] == 0,
     "palette 8 is the red cursor")

  -- 3. script lowering ------------------------------------------------------
  require("src.script.Gen2Commands")
  local Commands = require("src.script.Commands")
  ok(type(Commands.g2_card_flip) == "function", "g2_card_flip is registered")

  local VM = require("src.script.Gen2ScriptVM")
  local rows = VM.compile(game.data, "S57_6A96")
  ok(type(rows) == "table", "a game corner script still compiles")

  -- 4. the screen -----------------------------------------------------------
  local Screens = require("src.ui.Screens")
  Screens.push(game, "Gen2CardFlip")
  U.wait(4)
  local screen = game.stack.states[#game.stack.states]
  ok(getmetatable(screen) == require("src.ui.Gen2CardFlip"), "Gen2CardFlip is on the stack")

  ok(#screen.deck == 24, "the deck holds 24 cards")
  local seen = {}
  for _, card in ipairs(screen.deck) do seen[card] = true end
  local complete = true
  for card = 0, 23 do if not seen[card] then complete = false end end
  ok(complete, "the shuffle is a permutation of 0-23")

  -- payouts, straight off CardFlip_CheckWinCondition
  screen.faceUpCard = 4 * 2 + 1          -- Jigglypuff, number 3
  local cases = {
    { slot = 4 * 6 + 3, want = 72, label = "exact card pays 72" },
    { slot = 2 * 6 + 2, want = 0, label = "wrong card pays nothing" },
    { slot = 4 * 6 + 1, want = 18, label = "its number pays 18" },
    { slot = 1 * 6 + 3, want = 12, label = "its Pokemon pays 12" },
    { slot = 4 * 6 + 0, want = 9, label = "its number pair pays 9" },
    { slot = 0 * 6 + 2, want = 6, label = "its Pokemon pair pays 6" },
    { slot = 0 * 6 + 4, want = 0, label = "the other Pokemon pair pays nothing" },
    { slot = 0 * 6 + 0, want = 0, label = "an impossible square pays nothing" },
  }
  for _, case in ipairs(cases) do
    screen.cursor = case.slot
    ok(screen:payout() == case.want, case.label)
  end

  -- palette zones survive every COLORS mode, ADVANCED included
  screen.stage = "bet"
  screen.cursor = 2 * 6 + 2
  local zones = screen:sgbPalettes()
  ok(type(zones) == "table" and #zones >= 6,
     ("sgbPalettes returned zones (got %s)"):format(zones and #zones))
  local PaletteFX = require("src.render.PaletteFX")
  local before = PaletteFX.mode
  local intact = true
  for _, mode in ipairs({ "redpp", "gbc", "ogred", "og", "classic" }) do
    PaletteFX.setMode(mode)
    local got = PaletteFX.effectiveColors(zones[1].colors)
    for index, color in ipairs(zones[1].colors) do
      for channel = 1, 3 do
        if got[index][channel] ~= color[channel] then intact = false end
      end
    end
  end
  PaletteFX.setMode(before)
  ok(intact, "ROM colours pass through unchanged in every COLORS mode")

  -- play a hand
  screen.stage = "ask"
  game.save.coins = 500
  U.tap(game, "a")
  U.wait(10)
  ok(screen.stage == "choose" and game.save.coins == 497, "three coins buys a hand")
  U.shot(game, ".scratchpad/gen2_cardflip_choose.png")
  U.tap(game, "a")
  U.wait(10)
  ok(screen.stage == "bet", "A stops the alternation and asks for a bet")
  U.shot(game, ".scratchpad/gen2_cardflip_bet.png")
  U.tap(game, "a")
  U.wait(10)
  ok(screen.stage == "reveal" and screen.faceUpCard ~= nil, "the card turns face up")
  ok(screen.discarded[screen.faceUpCard] == true, "the revealed card is discarded")
  U.shot(game, ".scratchpad/gen2_cardflip_reveal.png")

  U.log(("RESULT %s (%d pass, %d fail)"):format(fail == 0 and "PASS" or "FAIL", pass, fail))
end
