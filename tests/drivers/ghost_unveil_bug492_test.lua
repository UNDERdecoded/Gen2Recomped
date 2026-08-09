-- Manual check of the Silph Scope unveil in the POKEMON_TOWER_6F battle (#492).
-- PrintBeginningBattleText .isMarowak (engine/battle/common_text.asm:49-60)
-- enters disguised even with the scope and plays UnveiledGhostText + MarowakAnim
-- over the GHOST before "Wild MAROWAK appeared!"; the port used to open the
-- battle with MAROWAK already loaded.  Sequencing half:
-- tests/engine/ghost_unveil_bug492.lua.  Never under POKEPORT_SPEED -- the
-- unveil is the thing being timed.
--   POKEPORT_DRIVER=tests/drivers/ghost_unveil_bug492_test.lua POKEPORT_IDENTITY=bug492 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- machine checks ----------------------------------------------------
  -- A missing text key, a renamed asset and an unarmed branch all look like
  -- the bug from outside: the battle just opens with MAROWAK on screen.
  U.log("#492 Silph Scope unveil: machine checks")
  check("SILPH_SCOPE is a real item", game.data.items.SILPH_SCOPE ~= nil)
  check("MAROWAK is a real species", game.data.pokemon.MAROWAK ~= nil)
  check("BattleState:makeUnveiledGhost exists",
        type(BattleState.makeUnveiledGhost) == "function")
  local unveil = game.data.text._UnveiledGhostText
  check("_UnveiledGhostText extracted", type(unveil) == "string" and unveil ~= "")
  if type(unveil) == "string" then
    U.log("the unveil line reads:", (unveil:gsub("[\n\011\012]", " / ")))
  end
  check("_PokemonTower6FBeGoneText extracted",
        type(game.data.text._PokemonTower6FBeGoneText) == "string")
  -- the disguise pic resolves through the same override chain the battle uses
  local Assets = require("src.render.Assets")
  local GHOST_PIC = "assets/generated/battle/front/ghost.png"
  check("the ghost front pic is in the cache",
        Assets.exists(Assets.resolve(GHOST_PIC)))

  local opts = game.save.options or {}
  U.log("sfxVol", tostring(opts.sfxVol), "musicVol", tostring(opts.musicVol))
  if opts.sfxVol == 0 or opts.musicVol == 0 then
    U.log("a volume is at 0: raise it in OPTION before judging what you hear")
  end
  U.log("no intro cry here is CORRECT -- .isMarowak never reaches PlayCry.")
  U.log("The CHANNELER at (12, 10) is the control: her GASTLY cries normally.")

  -- ---- reach the trigger -------------------------------------------------
  -- pokered scripts/PokemonTower6F.asm PokemonTower6FMarowakCoords:
  -- dbmapcoord 10, 16.  Row 17 is solid wall and (9, 16) is the stairwell
  -- warp down to 5F, so the approach is from (10, 15) facing down.
  local MAP = "POKEMON_TOWER_6F"
  local TRIGGER = { x = 10, y = 16 }
  local STAND = { x = 10, y = 15, facing = "down", step = "down" }

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.player.name = "RED"
  game.save.inventory.SILPH_SCOPE = 1
  game.save.flags.EVENT_BEAT_GHOST_MAROWAK = nil

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up on " .. MAP, ow ~= nil and ow.map ~= nil)

  if ow and ow.map and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit moved the approach: take any walkable neighbour of the
    -- trigger that is not the stairwell warp, and step back toward it.
    -- {dx, dy, facing} is the offset from the trigger to the stand cell plus
    -- the direction that walks back onto it.
    local sides = { { 0, -1, "down" }, { 1, 0, "left" },
                    { -1, 0, "right" }, { 0, 1, "up" } }
    for _, s in ipairs(sides) do
      local cx, cy = TRIGGER.x + s[1], TRIGGER.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow.map:warpAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, approaching from"):format(STAND.x, STAND.y),
              cx, cy, "stepping", s[3])
        STAND = { x = cx, y = cy, facing = s[3], step = s[3] }
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        ow = game.overworld
        break
      end
    end
  end

  -- walk onto the trigger; MapScripts onStep fires on the completed step
  U.hold(game, STAND.step, 20)
  U.wait(20)
  check("the Be-gone text opened", game.stack:top() ~= game.overworld)

  -- ---- into the battle ---------------------------------------------------
  local battle
  for _ = 1, 300 do
    local top = game.stack:top()
    if getmetatable(top) == BattleState then battle = top break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the MAROWAK battle opened", battle ~= nil)
  if not battle then
    U.log(("machine checks: %d passed, %d failed"):format(pass, fail))
    while true do coroutine.yield() end
  end

  battle.onFinish = battle.onFinish or function() end
  check("the scope armed the unveil, not a plain wild battle",
        battle.scopeReveal == true)
  check("IsGhostBattle stays false with the scope in the bag", not battle.ghost)
  check("the battle OPENED as the GHOST, not as MAROWAK (#492)",
        battle.enemy and battle.enemy.name == "GHOST")
  check("the real nick is held back for the unveil",
        battle.ghostReal ~= nil and battle.ghostReal.name == "MAROWAK")

  -- ---- watch the unveil --------------------------------------------------
  -- A turns the "GHOST appeared!" and unveil boxes; stop pressing the moment
  -- MarowakAnim arms so nothing mashes past "Wild MAROWAK appeared!".
  for _ = 1, 600 do
    if battle.ghostReveal then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("MarowakAnim started", battle.ghostReveal ~= nil)

  local FLASH = BattleState.GHOST_FLASH_FRAMES
  local FADE_OUT = BattleState.GHOST_FADE_OUT_FRAMES
  local shotFlash, swapT, nameDuringFlash = false, nil, true
  for _ = 1, 400 do
    local gr = battle.ghostReveal
    local t = gr and gr.t or nil
    if t and t <= FLASH + FADE_OUT and battle.enemy.name ~= "GHOST" then
      nameDuringFlash = false
    end
    if t and not swapT and battle.enemy.name ~= "GHOST" then swapT = t end
    if t and t >= 25 and not shotFlash then
      shotFlash = U.shot(game, DIR .. "/bug492_ghost_flashing.png")
    end
    if not gr and swapT then break end
    U.wait(1)
  end

  check("the GHOST was still on screen through the flash and fade-out (#492)",
        nameDuringFlash)
  check(("the swap landed after the fade-out (frame %s of %d)")
          :format(tostring(swapT), FLASH + FADE_OUT),
        swapT ~= nil and swapT > FLASH + FADE_OUT)
  check("the foe is MAROWAK once the animation finishes",
        battle.enemy.name == "MAROWAK")
  check("captured the flashing ghost", shotFlash)

  -- the "Wild MAROWAK appeared!" box that closes .isMarowak
  U.wait(30)
  check("captured the unveiled MAROWAK",
        U.shot(game, DIR .. "/bug492_marowak_revealed.png"))
  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))

  -- ---- hand off ----------------------------------------------------------
  U.log("The pad is yours in the battle the unveil just finished.  What you")
  U.log("should have seen: the box says the GHOST appeared, the SILPH SCOPE")
  U.log("line follows, and only THEN does the ghost flash, dissolve and come")
  U.log("back as MAROWAK before \"Wild MAROWAK appeared!\".  The near miss to")
  U.log("watch for is the sprite swapping early -- MAROWAK already standing")
  U.log("there while the unveil text is still typing, which is #492 itself.")
  U.log("To see it again: run from the battle (that steps you one cell right),")
  U.log("walk back to (10, 15) and step down onto (10, 16).  Beating it sets")
  U.log("EVENT_BEAT_GHOST_MAROWAK and the trigger is spent for this save.")
  U.log("Screenshots: " .. DIR .. "/bug492_*.png")

  while true do
    coroutine.yield()
  end
end
