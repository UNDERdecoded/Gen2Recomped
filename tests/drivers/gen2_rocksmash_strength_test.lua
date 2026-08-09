-- Gen2 ROCK SMASH / STRENGTH: the smashable-vs-pushable object split
-- (MAPOBJECT_MOVEMENT $18 vs $19), the callasm lowering that makes
-- AskRockSmashScript / AskStrengthScript actually check the party, and the
-- rock_smash movement operand that used to decode as an extra step.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else
      fail = fail + 1
      U.log("FAIL " .. what)
    end
  end

  -- everything a TextBox is currently holding, pages and all
  local function boxText(box)
    local out = {}
    for _, lines in ipairs(box and box.pages or {}) do
      for _, line in ipairs(lines) do out[#out + 1] = line end
    end
    return table.concat(out, " ")
  end

  U.newGame(game)
  U.wait(2)
  -- U.newGame lands on CONTINUE when a save already exists, so the party below
  -- would otherwise be whatever an earlier run left behind -- and on a genuine
  -- new game it is empty, because the starter comes later.  The move checks
  -- need one mon whose moveset the driver owns outright.
  game.save.party = { require("src.pokemon.Pokemon").new(game.data, "SPECIES_155", 10) }

  local Map = require("src.world.Map")

  -- 1. the rock_smash movement no longer eats its operand as a step --------
  local movements = game.data.map_scripts and game.data.map_scripts.movements
  local rs
  for _, rows in pairs(movements or {}) do
    if rows[1] and rows[1][1] == "rock_smash" then rs = rows break end
  end
  ok(rs ~= nil, "a rock_smash movement exists")
  ok(rs == nil or (#rs == 2 and rs[2][1] == "step_end"),
     "rock_smash movement is shake + step_end (no stray slow_step_left)")

  -- 2. callasm resolves to pret labels -------------------------------------
  local scripts = game.data.map_scripts and game.data.map_scripts.scripts or {}
  local sawHasRockSmash, sawTryStrength = false, false
  for _, rows in pairs(scripts) do
    for _, row in ipairs(rows) do
      if row[1] == "callasm" then
        if row[2] == "HasRockSmash" then sawHasRockSmash = true end
        if row[2] == "TryStrengthOW" then sawTryStrength = true end
      end
    end
  end
  ok(sawHasRockSmash, "callasm HasRockSmash resolved by name")
  ok(sawTryStrength, "callasm TryStrengthOW resolved by name")

  -- 3. ROCK_SMASH is not badge-gated (it is TM08, not an HM) ---------------
  local hmBadges = game.data.constants.hmBadges or {}
  ok(hmBadges.ROCK_SMASH == nil, "ROCK_SMASH has no badge gate")
  ok(hmBadges.STRENGTH and hmBadges.STRENGTH.badge == "PLAINBADGE",
     "STRENGTH gated on PLAINBADGE")

  -- 4. whirlpool block swaps extracted -------------------------------------
  local wp = game.data.field.gen2Whirlpools
  ok(type(wp) == "table" and next(wp) ~= nil, "field.gen2Whirlpools extracted")

  -- 4b. the prompts are PROSE ---------------------------------------------
  -- Every field-move message in the ROM is a `text_far` block: four bytes
  -- that name another bank.  The extractor used to print those four bytes
  -- as glyphs, so "This rock looks breakable." reached the box as
  -- "{BYTE:16}Z{BYTE:41}{BYTE:65}" and the player saw a line of noise.
  local text = game.data.text or {}
  local function prose(const, want)
    local s = text[const]
    ok(type(s) == "string" and not s:find("{BYTE:", 1, true),
       const .. " decoded (no raw text_far bytes)")
    ok(type(s) == "string" and s:find(want, 1, true) ~= nil,
       const .. " reads \"" .. want .. "\"")
  end
  prose("TEXT_S03_4F7A", "Want to use ROCK")   -- AskRockSmashText
  prose("TEXT_S03_4F75", "able to break it")   -- MaySmashText
  prose("TEXT_S03_4F5B", "used")               -- <mon> used ROCK SMASH!
  prose("TEXT_S03_4D6C", "Want to use")        -- AskStrengthText
  prose("TEXT_S03_4D76", "able to move this")  -- MayMoveText
  prose("TEXT_S03_4D71", "Boulders may now")   -- BouldersMayNowBeMovedText

  -- 5. the Route 40 beach rocks are smashable, not pushable ----------------
  U.teleport(game, "ROUTE40", 10, 10)
  U.wait(4)
  local ow = game.stack:top()
  ok(ow and ow.map and ow.map.id == "ROUTE40", "in Route 40")
  local rock
  for _, obj in ipairs(ow and ow.map.def.objects or {}) do
    if obj.smashable then rock = obj break end
  end
  ok(rock ~= nil, "Route 40 has a smashable rock object")
  if rock then
    ok(Map.isSmashable(rock), "Map.isSmashable(rock)")
    ok(not Map.isPushable(rock), "Strength cannot push a Rock Smash rock")
  end

  -- 6. a real Strength boulder is still pushable ---------------------------
  local boulder
  for _, def in pairs(game.data.maps) do
    for _, obj in ipairs(def.objects or {}) do
      if obj.pushable then boulder = obj break end
    end
    if boulder then break end
  end
  ok(boulder ~= nil, "some map has a Strength boulder object")
  ok(boulder == nil or Map.isPushable(boulder), "Strength boulder is pushable")

  -- 7. talking to the rock with no ROCK_SMASH prints MaySmashText ----------
  if rock then
    for _, mon in ipairs(game.save.party) do
      for _, mv in ipairs(mon.moves) do mv.id = "TACKLE" end
    end
    local npc = ow:npcAtCell(rock.x, rock.y)
    ok(npc ~= nil, "the rock spawned as an entity")
    if npc then
      ow.player.cellX, ow.player.cellY = rock.x, rock.y + 1
      ow.player.facing = "up"
      ow:talkTo(npc)
      U.wait(20)
      local top = game.stack:top()
      ok(top ~= nil and top ~= ow, "a text box opened for the rock")
      -- with no ROCK_SMASH the script must NOT reach the yes/no prompt
      ok(not (top and top.choice), "no yes/no prompt without ROCK_SMASH")
      ok(boxText(top):find("able to break it", 1, true) ~= nil,
         "the box shows MaySmashText, not decoded pointer bytes")
      while game.stack:top() ~= ow do U.tap(game, "b"); U.wait(4) end
    end

    -- 8. with ROCK_SMASH the prompt appears -------------------------------
    game.save.party[1].moves[1].id = "ROCK_SMASH"
    local npc2 = ow:npcAtCell(rock.x, rock.y)
    if npc2 then
      npc2.frozen = false
      ow:talkTo(npc2)
      U.wait(20)
      local top = game.stack:top()
      ok(top ~= nil and top ~= ow, "a text box opened with ROCK_SMASH")
      ok(boxText(top):find("Want to use ROCK", 1, true) ~= nil,
         "the box asks the ROCK SMASH question")
      while game.stack:top() ~= ow do U.tap(game, "a"); U.wait(6) end
      U.wait(30)
      ok(ow:npcAtCell(rock.x, rock.y) == nil, "the smashed rock disappeared")
    end
  end

  -- 9. Strength pushes on the FIRST bump, in the direction walked ----------
  local bmap, bobj
  for id, def in pairs(game.data.maps) do
    for _, obj in ipairs(def.objects or {}) do
      if obj.pushable then bmap, bobj = id, obj break end
    end
    if bmap then break end
  end
  if bmap then
    U.teleport(game, bmap, bobj.x, bobj.y + 1)
    U.wait(6)
    local ow2 = game.stack:top()
    local b = ow2.npcAtCell and ow2:npcAtCell(bobj.x, bobj.y)
    ok(b ~= nil, "the Strength boulder spawned")
    if b then
      ow2.strengthActive = false
      ok(not ow2:checkBoulderPush("up"), "no push without STRENGTH active")
      ow2.strengthActive = true
      ow2.boulderTried = nil
      ok(ow2:checkBoulderPush("up") or not ow2.map:isWalkableCell(bobj.x, bobj.y - 1),
         "GSC pushes on the first bump (no Gen1 two-attempt arming)")
    end
  end

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
  return fail == 0
end
