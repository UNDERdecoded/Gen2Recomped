-- Driver (#214): status screen page 1 must print the type's DISPLAY name.
-- pokered engine/pokemon/status_screen.asm PrintMonType prints the type's
-- entry from the TypeNames table (data/types/names.asm), which for the
-- PSYCHIC_TYPE constant is "PSYCHIC".  The engine stores each species'
-- types as pokered CONSTANT names (RomExtractor:typesById), and PSYCHIC's
-- constant is "PSYCHIC_TYPE" so it does not collide with the PSYCHIC move.
-- Drawing the raw constant overflowed the TYPE field: "PSYCHIC" fills
-- x=88..144, then "_TYPE" runs into the right DrawLineBox bracket (the
-- stray "+" tick the reporter circled).  SummaryMenu must route the label
-- through TypeChart.displayName like HallOfFame / BattleState already do.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local SummaryMenu = require("src.ui.SummaryMenu")
  local TypeChart = require("src.battle.TypeChart")
  local Font = require("src.render.Font")

  game.save.player.name = "YOSHIRB"

  -- Capture what SummaryMenu actually draws at the TYPE1 value slot
  -- (x=88, y=80 in SummaryMenu:draw).  Monkeypatch the Font table field so
  -- the local Font reference inside SummaryMenu resolves to our wrapper at
  -- call time; this reads the real rendered string, not TypeChart in
  -- isolation, so it fails while the raw constant is drawn.
  local realDraw = Font.draw
  local captured
  local function recordShot(game, mon, path)
    local summary = SummaryMenu.new(game, mon)
    game.stack:push(summary)
    U.wait(4)
    captured = nil
    Font.draw = function(text, x, y)
      if x == 88 and y == 80 then captured = text end
      return realDraw(text, x, y)
    end
    U.shot(game, path)
    Font.draw = realDraw
    game.stack:pop()
    U.wait(2)
    return captured
  end

  -- Psychic mon: the bug case.  MEW is pure PSYCHIC.
  local mew = Pokemon.new(game.data, "MEW", 10)
  local mewDrawn = recordShot(game, mew, DIR .. "/summary_type_214_mew_p1.png")
  U.log("MEW raw types[1]=", tostring(game.data.pokemon.MEW.types[1]),
        "drawn TYPE1=", tostring(mewDrawn))

  -- Control: RATTATA is pure NORMAL, whose constant == display name, so it
  -- was never affected; it should still read "NORMAL".
  local ratt = Pokemon.new(game.data, "RATTATA", 5)
  local rattDrawn = recordShot(game, ratt, DIR .. "/summary_type_214_rattata_p1.png")
  U.log("RATTATA raw types[1]=", tostring(game.data.pokemon.RATTATA.types[1]),
        "drawn TYPE1=", tostring(rattDrawn))

  U.log("shots under", DIR)

  -- Raw data must still carry the pokered constant: it is the shared key for
  -- TypeChart matchups and move.type, so the fix lives at the display layer.
  assert(game.data.pokemon.MEW.types[1] == "PSYCHIC_TYPE",
    "expected MEW raw type constant PSYCHIC_TYPE, got "
      .. tostring(game.data.pokemon.MEW.types[1]))
  assert(TypeChart.displayName("PSYCHIC_TYPE") == "PSYCHIC",
    "TypeChart.displayName(PSYCHIC_TYPE) must be PSYCHIC")

  -- The bug: SummaryMenu drew the raw constant "PSYCHIC_TYPE" (overflowing).
  -- The fix: it must draw the display name "PSYCHIC" (7 chars, fits 88..144).
  assert(mewDrawn == "PSYCHIC",
    "#214: status screen TYPE1 for MEW must render PSYCHIC, drew "
      .. tostring(mewDrawn))
  assert(not tostring(mewDrawn):find("_"),
    "#214: TYPE1 label must not contain '_' (no glyph, overflows bracket)")
  assert(rattDrawn == "NORMAL",
    "control: RATTATA TYPE1 must render NORMAL, drew " .. tostring(rattDrawn))

  U.log("#214 PASS: status-screen TYPE1 renders display names")
end
