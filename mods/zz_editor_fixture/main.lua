return function(mod)
  local giftFlag = "MOD_EDITMON_GIFT"
  mod.exports.giftFlag = giftFlag
  mod.content.pokemon:register("EDITMON", {
    id = "EDITMON", name = "EDITMON", dex = 152,
    types = { "NORMAL" },
    baseStats = { hp = 50, attack = 50, defense = 50, speed = 50, special = 50 },
    catchRate = 45, baseExp = 100,
    level1Moves = { "GROWL" },
    growthRate = "MEDIUM_FAST",
    learnset = { { level = 10, move = "TACKLE" } },
    evolutions = {},
    spriteFront = "editmon_front.png", spriteBack = "editmon_back.png",
    frontSize = 5,
  })
end
