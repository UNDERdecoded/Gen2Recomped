-- Gen2 evolutions (EvosAttacks methods) and the Gen2-only item effects.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function check(cond, label)
    if cond then pass = pass + 1 else fail = fail + 1 end
    U.log("[driver] %s %s", cond and "ok  " or "FAIL", label)
  end

  local data = game.data
  local Evolution = require("src.pokemon.Evolution")
  local Pokemon = require("src.pokemon.Pokemon")
  local ItemEffects = require("src.inventory.ItemEffects")

  -- ---- extracted data ----------------------------------------------------
  local function evos(id) return (data.pokemon[id] or {}).evolutions or {} end
  check(#evos("SPECIES_158") == 1 and evos("SPECIES_158")[1].level == 18
        and evos("SPECIES_158")[1].species == "SPECIES_159",
        "TOTODILE has LEVEL 18 -> CROCONAW")
  check(#evos("SPECIES_133") == 5, "EEVEE has all five Gen2 evolutions")
  check(#evos("SPECIES_095") == 1 and evos("SPECIES_095")[1].method == "TRADE"
        and evos("SPECIES_095")[1].heldItem ~= nil,
        "ONIX trades with a held METAL COAT")
  local tyrogue = evos("SPECIES_236")
  check(#tyrogue == 3 and tyrogue[1].method == "STAT" and tyrogue[1].level == 20,
        "TYROGUE has three STAT evolutions at level 20")

  -- ---- happiness ---------------------------------------------------------
  local chansey = Pokemon.new(data, "SPECIES_113", 20)
  check(chansey.happiness == Evolution.BASE_HAPPINESS,
        "a new Gen2 mon starts at BASE_HAPPINESS")
  check(Evolution.pendingFor(game, chansey, { kind = "levelup" }) == nil,
        "CHANSEY does not evolve at base happiness")
  chansey.happiness = 219
  Evolution.changeHappiness(chansey, "LEVELUP")   -- 219 -> 221
  check(chansey.happiness == 221, "ChangeHappiness LEVELUP uses the 200+ band")
  check(Evolution.pendingFor(game, chansey, { kind = "levelup" })
        == "SPECIES_242", "CHANSEY evolves once happiness passes 220")

  -- Espeon / Umbreon are the same happiness gate plus the clock
  local eevee = Pokemon.new(data, "SPECIES_133", 20)
  eevee.happiness = 250
  local want = Evolution.isNight() and "SPECIES_197" or "SPECIES_196"
  check(Evolution.pendingFor(game, eevee, { kind = "levelup" }) == want,
        "EEVEE picks the time-of-day happiness evolution")

  -- ---- stat comparison ---------------------------------------------------
  local tyro = Pokemon.new(data, "SPECIES_236", 20)
  tyro.stats.attack, tyro.stats.defense = 30, 40
  check(Evolution.pendingFor(game, tyro, { kind = "levelup" }) == "SPECIES_106",
        "TYROGUE with atk < def becomes HITMONLEE")
  tyro.stats.attack, tyro.stats.defense = 50, 40
  check(Evolution.pendingFor(game, tyro, { kind = "levelup" }) == "SPECIES_107",
        "TYROGUE with atk > def becomes HITMONCHAN")
  tyro.stats.attack, tyro.stats.defense = 40, 40
  check(Evolution.pendingFor(game, tyro, { kind = "levelup" }) == "SPECIES_237",
        "TYROGUE with atk == def becomes HITMONTOP")
  tyro.level = 19
  check(Evolution.pendingFor(game, tyro, { kind = "levelup" }) == nil,
        "TYROGUE below level 20 does not evolve")

  -- ---- stones ------------------------------------------------------------
  local function itemByKey(key)
    for id, def in pairs(data.items) do
      if def.key == key then return id end
    end
  end
  local thunder = itemByKey("THUNDERSTONE")
  check(thunder ~= nil and ItemEffects.isStone(thunder),
        "THUNDERSTONE is recognised as an evolution stone")
  local eevee2 = Pokemon.new(data, "SPECIES_133", 20)
  local result, _, extra = ItemEffects.use(data, game.save, thunder, eevee2)
  check(result == "consumed" and extra and extra.evolveTo == "SPECIES_135",
        "a THUNDERSTONE on EEVEE evolves it into JOLTEON")
  local sun = itemByKey("SUN_STONE")
  check(sun ~= nil and ItemEffects.isStone(sun), "SUN STONE is a stone too")

  -- ---- berries -----------------------------------------------------------
  local hurt = Pokemon.new(data, "SPECIES_155", 20)
  hurt.hp = 1
  local berry = itemByKey("BERRY")
  local r = ItemEffects.use(data, game.save, berry, hurt)
  check(r == "consumed" and hurt.hp == 11, "BERRY restores 10 HP")

  hurt.hp = 1
  local gold = itemByKey("GOLD_BERRY")
  r = ItemEffects.use(data, game.save, gold, hurt)
  check(r == "consumed" and hurt.hp == 31, "GOLD BERRY restores 30 HP")

  local burned = Pokemon.new(data, "SPECIES_155", 20)
  burned.status = "BRN"
  r = ItemEffects.use(data, game.save, itemByKey("ICE_BERRY"), burned)
  check(r == "consumed" and burned.status == nil, "ICE BERRY cures a burn")

  local asleep = Pokemon.new(data, "SPECIES_155", 20)
  asleep.status = "SLP"
  r = ItemEffects.use(data, game.save, itemByKey("MINT_BERRY"), asleep)
  check(r == "consumed" and asleep.status == nil, "MINT BERRY cures sleep")

  local poisoned = Pokemon.new(data, "SPECIES_155", 20)
  poisoned.status = "PSN"
  r = ItemEffects.use(data, game.save, itemByKey("PSNCUREBERRY"), poisoned)
  check(r == "consumed" and poisoned.status == nil, "PSNCUREBERRY cures poison")

  local confused = Pokemon.new(data, "SPECIES_155", 20)
  local fakeBattle = { player = { mon = confused, confusedTurns = 3 }, enemy = nil }
  r = ItemEffects.use(data, game.save, itemByKey("BITTER_BERRY"), confused,
                      fakeBattle)
  check(r == "consumed" and fakeBattle.player.confusedTurns == nil,
        "BITTER BERRY clears confusion in battle")

  local drained = Pokemon.new(data, "SPECIES_155", 20)
  drained.moves[1].pp = 0
  r = ItemEffects.use(data, game.save, itemByKey("MYSTERYBERRY"), drained,
                      nil, 1)
  check(r == "consumed" and drained.moves[1].pp == 5,
        "MYSTERYBERRY restores 5 PP to one move")

  -- ---- escape rope -------------------------------------------------------
  local caves = 0
  for _, def in pairs(data.maps) do
    if def.environment == 4 or def.environment == 7 then caves = caves + 1 end
  end
  check(caves > 0, "maps carry the Gen2 environment byte (" .. caves .. " caves)")
  check(ItemEffects.use(data, game.save, itemByKey("ESCAPE_ROPE"))
        == "escape_rope", "ESCAPE ROPE reaches the escape path")

  -- ---- prize money -------------------------------------------------------
  local withMoney = 0
  for _, t in pairs(data.trainers) do
    if (t.baseMoney or 0) > 0 then withMoney = withMoney + 1 end
  end
  check(withMoney > 50, "trainer classes carry a base reward (" .. withMoney .. ")")

  U.log("[driver] RESULT %s (%d pass, %d fail)",
        fail == 0 and "PASS" or "FAIL", pass, fail)
  love.event.quit()
end
