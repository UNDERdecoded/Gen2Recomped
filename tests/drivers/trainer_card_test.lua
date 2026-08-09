-- Driver: trainer card with empty badge slots (gym leader faces) and a
-- partial set (face/badge mix), matching DrawBadges in pokered.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  game.save.player.name = "RED"
  game.save.money = 3000
  game.save.playTime = 3661
  game.save.inventory = game.save.inventory or {}

  local TrainerCard = require("src.ui.TrainerCard")

  -- no badges: every slot should show the gym leader face
  for _, id in ipairs({
    "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
    "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
  }) do
    game.save.inventory[id] = nil
  end
  game.stack:push(TrainerCard.new(game))
  U.wait(5)
  U.shot(game, DIR .. "/trainer_card_0_faces.png")
  U.tap(game, "b"); U.wait(3)

  -- boulder + cascade owned: first two slots swap to badges
  game.save.inventory.BOULDERBADGE = true
  game.save.inventory.CASCADEBADGE = true
  game.stack:push(TrainerCard.new(game))
  U.wait(5)
  U.shot(game, DIR .. "/trainer_card_1_partial.png")
  U.tap(game, "b"); U.wait(3)
  U.log("TRAINER_CARD_DRIVER: done")
end
