-- Manual check that BATTLE LAYOUT = WIDE draws move animations intact (#562).
-- A battle sets rWY to 0 (engine/battle/core.asm), so the window the shake
-- predefs displace is the whole screen; the wide composition moved only the
-- two pic regions, which slid the monsters across a nailed-down HUD and text
-- box.  TAIL WHIP is the reported case (wAnimationType 6,
-- AnimationShakeScreenHorizontallySlow b=3, animations.asm:526).  Composition
-- half: tests/engine/wide_battle_shake_bug562.lua.  Never under POKEPORT_SPEED.
--   POKEPORT_DRIVER=tests/drivers/wide_move_anim_bug562_test.lua POKEPORT_IDENTITY=bug562 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local WideBattle = require("src.battle.WideBattle")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- One move per shake family the wide composition has to carry.  `hitX` is
  -- the applying-attack amplitude PlayApplyingAttackAnimation plays after the
  -- move (AnimationTypePointerTable, animations.asm:475); `animX` is a shake
  -- the move's own subanimation runs.  wAnimationType 4, 5 and 6 are the
  -- player's turn -- the vertical 1 and the wide 2 / 3 are the foe's, and the
  -- foe's rows are reported below rather than driven.
  --   TAIL WHIP   type 6, AnimationShakeScreenHorizontallySlow b=3 (silent;
  --               every player status move takes this path)
  --   BUBBLEBEAM  type 5, fast horizontal b=2, with the damage thud
  --   EARTHQUAKE  SE_SHAKE_SCREEN inside its own animation (fastShakeProg 8),
  --               shared with FISSURE and SEISMIC TOSS
  --   WITHDRAW    the control: a stat-UP effect leaves wAnimationType at 0
  --               (effects.asm, PlayCurrentMoveAnimation), so nothing moves.
  --               It also fills the fourth grid slot, which the 2x2 needs.
  local MOVES = {
    { slot = 1, id = "TAIL_WHIP",  type = 6, hitX = 3 },
    { slot = 2, id = "BUBBLEBEAM", type = 5, hitX = 2 },
    { slot = 3, id = "EARTHQUAKE", type = 4, animX = 8 },
    { slot = 4, id = "WITHDRAW",   type = 0, hitX = 0, hitY = 0 },
  }

  -- ---- machine checks ----------------------------------------------------
  -- A move missing from the table, a layout that never switched and a battle
  -- that never reached WIDE all look like "the animation is fine" from a chair.
  U.log("#562 wide-layout move animations: machine checks")
  for _, m in ipairs(MOVES) do
    check(m.id .. " is in the move table", game.data.moves[m.id] ~= nil)
  end
  local anims = game.data.battle_anims and game.data.battle_anims.moveAnims
  check("battle_anims carries TAIL WHIP's own animation",
        anims ~= nil and anims.TAIL_WHIP ~= nil)
  check("...and EARTHQUAKE's, which carries SE_SHAKE_SCREEN itself",
        anims ~= nil and anims.EARTHQUAKE ~= nil)
  check("animations are on in OPTIONS (the shakes are gated on them)",
        game.save.options.animations ~= false)

  game.save.options.battleLayout = "wide"
  check("BATTLE LAYOUT is WIDE", game.save.options.battleLayout == "wide")

  local vol = game.save.options and game.save.options.sfxVol
  U.log("sfxVol", tostring(vol),
        vol == 0 and "-- SILENT, raise it in OPTION before judging the sound"
        or "-- BUBBLEBEAM and EARTHQUAKE carry the damage thud; TAIL WHIP is silent")

  -- ---- fixture -----------------------------------------------------------
  local squirtle = Pokemon.new(game.data, "SQUIRTLE", 40)
  squirtle.moves = {}
  for _, m in ipairs(MOVES) do
    squirtle.moves[m.slot] = { id = m.id, pp = game.data.moves[m.id].pp }
  end
  game.save.party = { squirtle }
  game.save.player.name = "RED"

  -- data/generated/maps.lua ROUTE_1: (5, 5) is open walkable ground; the
  -- battle is pushed straight in rather than encountered
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  local ow = game.overworld
  if ow and ow.map and not ow.map:isWalkableCell(5, 5) then
    -- a map edit moved the path: take the nearest walkable cell instead
    local sx, sy
    for r = 1, 6 do
      for dy = -r, r do
        for dx = -r, r do
          if not sx and ow.map:isWalkableCell(5 + dx, 5 + dy) then
            sx, sy = 5 + dx, 5 + dy
          end
        end
      end
      if sx then break end
    end
    if sx then
      U.log("(5, 5) is blocked, standing on", sx, sy)
      U.teleport(game, "ROUTE_1", sx, sy, "down")
      U.wait(10)
      ow = game.overworld
    end
  end
  check("the overworld is up on ROUTE_1", ow ~= nil)

  -- a Normal-type foe: PIDGEY is Flying and would sit out EARTHQUAKE entirely
  local battle = BattleState.newWild(game, "RATTATA", 20)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  for _ = 1, 400 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the battle reached the screen", game.stack:top() == battle)
  check("the battle is drawing the wide surface", battle:wideLayout() == true)
  local uw = battle:uiSize()
  check(("the surface is %dpx wide (got %s)"):format(WideBattle.WIDTH, tostring(uw)),
        uw == WideBattle.WIDTH)

  -- a foe that survives the whole run: every family needs its own turn, and
  -- EARTHQUAKE off a level 40 SQUIRTLE takes a large bite
  battle.enemy.mon.stats.hp = 900
  battle.enemy.mon.hp = 900
  battle.enemy.shownHP = 900
  -- WHIRLWIND ends a wild battle outright ("run"), taking the untested
  -- families with it; curMoves aliases mon.moves, so one pass covers both
  for i = #battle.enemy.mon.moves, 1, -1 do
    local id = battle.enemy.mon.moves[i].id
    if id == "WHIRLWIND" or id == "ROAR" or id == "TELEPORT" then
      table.remove(battle.enemy.mon.moves, i)
    end
  end

  -- ---- sample the offsets the composition is fed -------------------------
  -- One row per performMove, EITHER side: a row that stayed open across the
  -- foe's reply would credit the player's move with the foe's shake.  The
  -- split at the first applyHitFx separates a shake the move's own animation
  -- ran (SE_SHAKE_SCREEN) from the applying-attack one that follows it.
  local rows, cur = {}, nil
  local realPerform = battle.performMove
  battle.performMove = function(self, user, target, moveInst, ...)
    cur = { move = moveInst and moveInst.id, isPlayer = user.isPlayer,
            animX = 0, animY = 0, hitX = 0, hitY = 0, hitFrames = 0 }
    rows[#rows + 1] = cur
    return realPerform(self, user, target, moveInst, ...)
  end
  local realFx = battle.applyHitFx
  battle.applyHitFx = function(self, hit)
    if cur and cur.animType == nil then cur.animType = hit.animType or 0 end
    return realFx(self, hit)
  end

  local function sample()
    local fx = battle.fx
    if not (cur and fx) then return end
    local dx, dy = math.abs(fx.shakeX or 0), math.abs(fx.shakeY or 0)
    if cur.animType == nil then
      cur.animX, cur.animY = math.max(cur.animX, dx), math.max(cur.animY, dy)
      return
    end
    if dx > 0 or dy > 0 then cur.hitFrames = cur.hitFrames + 1 end
    cur.hitX, cur.hitY = math.max(cur.hitX, dx), math.max(cur.hitY, dy)
  end

  -- has this row finished its applying-attack effect?  Type 4 runs a pic
  -- blink and no screen program at all, so it is done as soon as it fires.
  local function settled(row)
    return row ~= nil and row.animType ~= nil
           and (battle.fx == nil or battle.fx.shakeProg == nil)
  end

  -- step n frames sampling every one, pressing A every `mash` frames but only
  -- while a box is up: an A on the FIGHT menu starts a turn behind our back
  local function pump(n, mash, stop)
    for i = 1, n do
      if mash and i % mash == 0 and battle.phase == "messages" then
        table.insert(game.input.pressQueue, "a")
      end
      U.wait(1)
      game.input.state.a = false
      sample()
      if stop and stop() then return end
    end
  end

  local function toMenu()
    pump(1500, 6, function() return battle.phase == "menu" and #battle.queue == 0 end)
    return battle.phase == "menu"
  end

  -- The wide move list is a 2x2 grid, and a press that would land on an
  -- absent fourth move holds the cursor still (WideBattle.moveGridIndex), so
  -- the route is searched through the engine's own navigation rather than
  -- assumed: walking the column never reaches slots 2 and 4, and walking the
  -- row can dead-end on a three-move party.
  local DIRS = { "up", "down", "left", "right" }
  local function routeTo(from, slot, count)
    local seen, queue = { [from] = true }, { { at = from, path = {} } }
    while #queue > 0 do
      local node = table.remove(queue, 1)
      if node.at == slot then return node.path end
      for _, dir in ipairs(DIRS) do
        local nxt = WideBattle.moveGridIndex(node.at, count, dir)
        if nxt and not seen[nxt] then
          seen[nxt] = true
          local path = { unpack(node.path) }
          path[#path + 1] = dir
          queue[#queue + 1] = { at = nxt, path = path }
        end
      end
    end
    return nil
  end

  -- FIGHT is slot 1 of the wide command grid; A opens moveSelect.  A press on
  -- a frame the battle is not reading input is simply lost, so retry.
  local function useMove(slot)
    for _ = 1, 80 do
      if battle.phase == "moveSelect" then break end
      if battle.phase == "menu" then
        if battle.menuIndex ~= 1 then
          U.tap(game, battle.menuIndex > 2 and "up" or "left")
        else
          U.tap(game, "a")
        end
      else
        U.tap(game, "a")
      end
      U.wait(4)
    end
    if battle.phase ~= "moveSelect" then return false end
    -- recompute the route every press: a press that lands on a frame the
    -- battle is not reading is lost, and the cursor simply did not move
    local count = #(battle.player.curMoves or {})
    for _ = 1, 30 do
      if battle.moveIndex == slot then break end
      local path = routeTo(battle.moveIndex, slot, count)
      if not path or #path == 0 then break end
      U.tap(game, path[1])
      U.wait(3)
    end
    if battle.moveIndex ~= slot then return false end
    for _ = 1, 20 do
      if battle.phase ~= "moveSelect" then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return false
  end

  local function lastPlayerRow(id)
    for i = #rows, 1, -1 do
      if rows[i].move == id and rows[i].isPlayer then return rows[i] end
    end
    return nil
  end

  local SHOTS = { TAIL_WHIP = "bug562_wide_tailwhip.png",
                  BUBBLEBEAM = "bug562_wide_bubblebeam.png",
                  EARTHQUAKE = "bug562_wide_earthquake.png" }
  -- the foe's vertical drop (type 1) plays on ITS turn, so it is taken
  -- whenever one goes past and chased down after the table below if not
  local vertShot = false

  check("the battle reached its FIGHT menu", toMenu())

  for _, m in ipairs(MOVES) do
    local shotAt, sent, r
    -- BUBBLEBEAM whiffs 1 in 6 and the foe's TAIL WHIP stacks accuracy drops,
    -- so give each move a few turns rather than reading a miss (which plays no
    -- applying animation at all) as a regression; hand the accuracy back first
    for _ = 1, 8 do
      battle.player.stages.accuracy = 0
      sent = useMove(m.slot)
      if not sent then
        U.log(("  could not reach slot %d for %s (phase %s, move index %s, result %s)")
                :format(m.slot, m.id, tostring(battle.phase),
                        tostring(battle.moveIndex), tostring(battle.result)))
        break
      end
      pump(1500, 8, function()
        local fx = battle.fx
        local row = lastPlayerRow(m.id)
        if not shotAt and row == cur and SHOTS[m.id] and fx
           and (fx.shakeX or 0) ~= 0 then
          shotAt = U.shot(game, DIR .. "/" .. SHOTS[m.id])
        end
        if not vertShot and fx and (fx.shakeY or 0) ~= 0
           and cur and not cur.isPlayer then
          vertShot = U.shot(game, DIR .. "/bug562_wide_foe_vertical.png")
        end
        if row and battle.phase == "menu" and #battle.queue == 0 then return true end
        return settled(row)
      end)
      toMenu()
      r = lastPlayerRow(m.id)
      -- a type-0 move never queues an applying-attack row, so one clean turn
      -- is all it owes
      if r and (r.animType ~= nil or m.type == 0) then break end
      U.log("  " .. m.id .. " did not connect that turn; using it again")
    end
    check("chose " .. m.id .. " from the wide move grid", sent)
    if sent and check(m.id .. " was performed", r ~= nil) then
      U.log(("  %s: type %s, own animation %dpx across / %dpx down, applying "
             .. "%dpx across / %dpx down over %d frames")
              :format(m.id, tostring(r.animType), r.animX, r.animY,
                      r.hitX, r.hitY, r.hitFrames))
      check(("%s is wAnimationType %d (got %d)")
              :format(m.id, m.type, r.animType or 0),
            (r.animType or 0) == m.type)
      if m.hitX then
        check(("%s shakes the screen %dpx sideways (got %d)")
                :format(m.id, m.hitX, r.hitX), r.hitX == m.hitX)
      end
      if m.hitY then
        check(("%s leaves the vertical alone (got %d)"):format(m.id, r.hitY),
              r.hitY == m.hitY)
      end
      if m.animX then
        check(("%s's own animation shakes %dpx sideways (got %d)")
                :format(m.id, m.animX, r.animX), r.animX == m.animX)
      end
      if SHOTS[m.id] then
        check("captured " .. m.id .. " mid-shake", shotAt == true)
      end
    end
  end

  -- The vertical drop (type 1) only plays on the foe's turn, so it is taken by
  -- spending harmless WITHDRAW turns until the RATTATA picks a plain damaging
  -- move.  Which move it picks is an AI roll, so a run where it never does is
  -- a thin run, not a regression.
  local function foeTypeOne()
    for _, row in ipairs(rows) do
      if not row.isPlayer and row.animType == 1 then return true end
    end
    return false
  end
  for _ = 1, 6 do
    if vertShot then break end
    if not useMove(4) then break end
    pump(1200, 8, function()
      local fx = battle.fx
      if not vertShot and fx and (fx.shakeY or 0) ~= 0
         and cur and not cur.isPlayer then
        vertShot = U.shot(game, DIR .. "/bug562_wide_foe_vertical.png")
      end
      return battle.phase == "menu" and #battle.queue == 0
    end)
    toMenu()
  end

  local foe = {}
  for _, row in ipairs(rows) do
    if not row.isPlayer and row.animType then
      foe[#foe + 1] = ("%s type %s (%dpx across, %dpx down)")
                        :format(tostring(row.move), tostring(row.animType),
                                math.max(row.animX, row.hitX),
                                math.max(row.animY, row.hitY))
    end
  end
  U.log("the RATTATA's rows: " .. (#foe > 0 and table.concat(foe, "; ") or "none"))
  if vertShot then
    U.log("captured the foe's 8px vertical drop as well")
  elseif foeTypeOne() then
    check("the foe's vertical drop was captured", false)
  else
    U.log("the RATTATA never used a plain damaging move in these turns, so")
    U.log("there was no vertical drop to capture; watch for one by hand")
  end
  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))

  -- ---- hand off ----------------------------------------------------------
  U.log("The pad is yours at the wide FIGHT menu, all four panels on screen.")
  U.log("Slot 1 TAIL WHIP creeps the WHOLE screen 1px at a time out to 3px and")
  U.log("back, twice, in silence: foe, both status panels and the message box")
  U.log("move as one sheet.  Slot 2 BUBBLEBEAM snaps it 2px across with the")
  U.log("damage thud, slot 3 EARTHQUAKE shakes it 8px from inside its own")
  U.log("animation.  Let the RATTATA hit back for the vertical one: a plain")
  U.log("TACKLE or QUICK ATTACK drops the same sheet 8px.  The near miss to")
  U.log("watch for is the one #562 reported: the monsters sliding while the HUD")
  U.log("panels and the text box stay nailed down, or a pic sheared off at the")
  U.log("seam between the two side windows on the way.")
  U.log("Slot 4 WITHDRAW is the control: it moves nothing at all, on purpose.")
  U.log("So are the animations' own sprites (the bubbles, the EARTHQUAKE rocks)")
  U.log("-- those are OAM and correctly do NOT ride the shake, same as in OG.")
  U.log("Flip OPTION -> BATTLE LAYOUT to OG and repeat: it should look the same.")
  U.log("Screenshots: " .. DIR .. "/bug562_*.png")

  while true do
    coroutine.yield()
  end
end
