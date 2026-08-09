-- Driver: dump the exact pic textures a live 3D battle draws, per stage --
-- the sprite as loaded (raw) and what picImage hands the billboard after the
-- palette bake and BattlePics' paper fill (final). Diagnostic for pics that
-- render with holes: whichever stage the transparency first appears in is
-- the stage that made it.
--
--   SHOT_DIR=.scratchpad/pic_dump \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/pic_dump.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or ".scratchpad/pic_dump"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local function save(img, path)
    if not img then U.log("NIL image for " .. path) return end
    local w, h = img:getDimensions()
    local g = love.graphics
    local prev = g.getCanvas()
    local canvas = g.newCanvas(w, h, { dpiscale = 1 })
    g.setCanvas(canvas)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("replace", "premultiplied")
    g.setColor(1, 1, 1, 1)
    g.draw(img, 0, 0)
    g.setCanvas(prev)
    g.setBlendMode("alpha")
    local f = assert(io.open(path, "wb"))
    f:write(canvas:newImageData():encode("png"):getString())
    f:close()
  end

  local SPECIES = os.getenv("PIC_SPECIES")
  local list = {}
  if SPECIES then
    for id in SPECIES:gmatch("[^,%s]+") do list[#list + 1] = id:upper() end
  else
    list = { "PIKACHU", "SEEL", "BULBASAUR", "MEWTWO" }
  end

  for _, id in ipairs(list) do
    game.save.party = { Pokemon.new(game.data, id, 50) }
    U.teleport(game, "ROUTE_1", 5, 8, "down")
    U.wait(30)
    local battle = BattleState.newWild(game, id, 50)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    U.wait(80)
    local lo = id:lower()
    save(battle.enemy.sprite, ("%s/%s_front_raw.png"):format(DIR, lo))
    save(battle:picImage(battle.enemy.sprite), ("%s/%s_front_final.png"):format(DIR, lo))
    save(battle.player.sprite, ("%s/%s_back_raw.png"):format(DIR, lo))
    save(battle:picImage(battle.player.sprite), ("%s/%s_back_final.png"):format(DIR, lo))
    U.log("dumped " .. id)
    while game.stack:top() and game.stack:top() ~= game.overworld do
      game.stack:pop()
    end
    U.wait(5)
  end

  U.log("done -- " .. DIR)
  love.event.quit()
end
