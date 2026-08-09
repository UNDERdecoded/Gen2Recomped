local U = dofile("tests/drivers/util.lua")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL " .. name) end
end

return function(game)
  U.newGame(game)
  U.wait(20)
  U.teleport(game, "NEW_BARK_TOWN", 5, 6)
  U.wait(20)
  local ow = game.stack:top()
  local save = game.save
  local gates = require("src.world.FieldDefaults").constant(game.data, "hmBadges")

  check("gen2 hmBadges present", gates ~= nil)
  local want = {
    FLASH = "ZEPHYRBADGE", CUT = "HIVEBADGE", STRENGTH = "PLAINBADGE",
    SURF = "FOGBADGE", FLY = "STORMBADGE", WHIRLPOOL = "GLACIERBADGE",
    WATERFALL = "RISINGBADGE",
  }
  for move, badge in pairs(want) do
    local gate = gates and gates[move]
    check("gate " .. move .. " = " .. badge, gate and gate.badge == badge)
  end

  local mon = require("src.pokemon.Pokemon").new(game.data, "SPECIES_001", 20)
  mon.moves = {
    { id = "CUT", pp = 30 }, { id = "SURF", pp = 15 },
    { id = "FLASH", pp = 20 }, { id = "STRENGTH", pp = 15 },
  }
  save.party = { mon }
  save.flags = save.flags or {}
  check("no CUT without HIVEBADGE", ow:partyKnows("CUT") == nil)
  save.flags.HIVEBADGE = true
  check("CUT once HIVEBADGE is set", ow:partyKnows("CUT") == mon)
  check("still no SURF", ow:partyKnows("SURF") == nil)
  save.flags.FOGBADGE = true
  check("SURF once FOGBADGE is set", ow:partyKnows("SURF") == mon)
  save.flags.ZEPHYRBADGE = true
  check("FLASH once ZEPHYRBADGE is set", ow:partyKnows("FLASH") == mon)
  save.flags.PLAINBADGE = true
  check("STRENGTH once PLAINBADGE is set", ow:partyKnows("STRENGTH") == mon)
  check("no FLY without the move", ow:partyKnows("FLY") == nil)

  -- everything a TextBox is holding, pages and all
  local function boxText(box)
    local out = {}
    for _, lines in ipairs(box and box.pages or {}) do
      for _, line in ipairs(lines) do out[#out + 1] = line end
    end
    return table.concat(out, " ")
  end
  local function dismiss()
    for _ = 1, 40 do
      if game.stack:top() == game.overworld then break end
      U.tap(game, "b"); U.wait(6)
    end
  end

  -- WHIRLPOOL ---------------------------------------------------------------
  -- Route 41's eddy sits at cell 22,12 (collision $24).  TryWhirlpoolOW only
  -- fires while SURFing, refuses with MayPassWhirlpoolText when no party mon
  -- knows it, and on YES swaps the eddy block for plain water WITHOUT moving
  -- the player (DisappearWhirlpool).
  U.teleport(game, "ROUTE41", 22, 13)
  U.wait(20)
  ow = game.stack:top()
  check("on Route 41", ow.map and ow.map.id == "ROUTE41")
  ow.player.cellX, ow.player.cellY = 22, 13
  ow.player.facing = "up"
  ow.player.surfing = true

  check("whirlpool cell is collision $24", ow.map:cellTile(22, 12) == 0x24)
  check("no WHIRLPOOL in the party yet", ow:partyKnows("WHIRLPOOL") == nil)
  check("refusal is shown", ow:tryFieldMoveOW(22, 12) == true)
  local box = game.stack:top()
  check("MayPassWhirlpoolText, decoded",
        boxText(box):find("able to pass it", 1, true) ~= nil)
  dismiss()

  mon.moves[1] = { id = "WHIRLPOOL", pp = 15 }
  save.flags.GLACIERBADGE = true
  check("WHIRLPOOL usable with GLACIERBADGE",
        ow:partyKnows("WHIRLPOOL") == mon)
  check("the prompt opens", ow:tryFieldMoveOW(22, 12) == true)
  box = game.stack:top()
  check("AskWhirlpoolText, decoded",
        boxText(box):find("Want to use", 1, true) ~= nil)
  -- and the prompt really is a YES/NO: page through it (AskWhirlpoolText has
  -- a \f page break) and watch the choice box come up over the still-visible
  -- question (TextBox opts.choice)
  for _ = 1, 60 do
    if box.done or game.stack:top() ~= box then break end
    U.tap(game, "a"); U.wait(8)
  end
  check("the question finished typing", box.done == true)
  U.wait(2)
  check("a YES/NO box came up over it", game.stack:top() ~= box)
  dismiss()

  -- answering YES runs Script_UsedWhirlpool.  Drive that directly rather than
  -- racing the choice box's 15-frame answer hold.
  ow:gen2UseFieldMove("WHIRLPOOL", mon, 22, 12)
  U.wait(2)
  local used = game.stack:top()
  check("UseWhirlpoolText names the mon",
        boxText(used):find("used", 1, true) ~= nil
        and boxText(used):find("{RAM:", 1, true) == nil)
  dismiss()
  U.wait(90)
  check("the eddy became plain water", ow.map:cellTile(22, 12) ~= 0x24)
  check("the player did not move into the current",
        ow.player.cellX == 22 and ow.player.cellY == 13)
  ow.player.surfing = false

  -- FLY ---------------------------------------------------------------------
  local flyWarps = game.data.field.flyWarps or {}
  check("flyWarps extracted", next(flyWarps) ~= nil)
  U.teleport(game, "NEW_BARK_TOWN", 5, 6)
  U.wait(20)
  ow = game.stack:top()
  local dest, spot
  for id, s in pairs(flyWarps) do
    if id ~= "NEW_BARK_TOWN" and game.data.maps[id] then dest, spot = id, s break end
  end
  check("some other town is a fly destination", dest ~= nil)
  if dest then
    ow:flyTo(dest)
    U.wait(180)
    local now = game.stack:top()
    check("FLY landed on " .. tostring(dest),
          now.map and now.map.id == dest)
    check("FLY landed on the town's fly spot",
          now.player and now.player.cellX == spot.x
          and now.player.cellY == spot.y)
  end

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
end
