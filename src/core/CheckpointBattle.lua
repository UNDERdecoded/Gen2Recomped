-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Reconstruct native battle decision points from data, preserving relationships
-- between parties, battlers, sides and field state. No controller is serialized.
local B = {}
-- Native callbacks and script contexts can point back to their battle. Keep
-- provenance alive from that owner, never from a registry value that would
-- root the complete retired battle/coroutine graph on LuaJIT.
local owners = setmetatable({}, { __mode = "kv" })
local function names(words)
  local out = {}
  for k in words:gmatch("%S+") do
    out[k] = true
  end
  return out
end
local FIELDS = names([[
g4fx g4PrevMove g4TrickRoomResort turnActions
Abilities AllyAI AnimPlayer BattleCommands BattleState CatchTutorialDemo Catching CaughtMarker
Damage EffectRegistry EnemyActionContext EnemyMoveChoice Experience FieldResiduals GbaItemSchedule
Gen2AnimPlayer Gen2BattleView Gen2Wild Gen3AI Gen3AIAttackingMoves Gen3AIItemKnowledge
Gen3AIMoveKnowledge Gen3AIOrder Gen3AIPartyStatus Gen3AIQueries Gen3Accuracy Gen3Arena Gen3BallAnim
Gen3BatonPass Gen3Battle Gen3BattleWeather Gen3BeatUp Gen3Builtins Gen3Catching Gen3Critical
Gen3DamageStats Gen3Disable Gen3Encore Gen3FollowMe Gen3HelpingHand Gen3LockOn Gen3MoveAnim
Gen3MoveEffects Gen3MultiHit Gen3OHKO Gen3OrderCore Gen3Palace Gen3Rage Gen3Secondary Gen3SleepTalk
Gen3TripleKick Gen4AnimMath Gen4BallAnim Gen4Battle Gen4Catching Gen4EffectProjection
Gen4MoveAnimExtras Gen4MoveAnimFuncsA Gen4MoveAnimFuncsB Gen4MoveAnimFuncsC Gen4MoveAnimFuncsD
Gen4MoveAnimPlayer Gen4PalParkBattle Gen4ParticleSystem Gen4Safari Gen5BallAnim Gen5BallArt
Gen5BattleHud Gen5BattleLayout Gen5BattleText Gen5Catching Gen5HoldItems Gen5MoveAnimPlayer
Gen5MoveEffects Gen5MoveRules Gen5Transform HeldItemRead HeldItems HoldItems MenuAuxiliary
MoveEffects MoveNavigation POS PlayerPartyScope RulesetDefaults Status StatusHUDVisibility
StatusRegistry Targeting TrainerAI TurnOrder TypeChart UIVisibility Weather WideBattle
_actionTargetOrder _aiHistory _backdropLive _backdropPolled _battle _dsThrowQuads _frlgCallbackLives
_gbaActionFrame _gbaMoveFrame _gbaResidualPriority _gen3BatonParty _gen3BatonPending _gen3BatonPoll
_gen3BatonRequest _gen3BatonSwitching _gen3HelpingHand _gen3OamCompositedFrame
_gen3OamGlobalTieResidual _gen3OamObjectRanks _gen3OamResidual _gen3SurfaceKey _gen3SurfaceW
_gen4SurfaceKey _gen4SurfaceW _gen5Text _mementoTiming _modFieldResidualTurn _nativeOrderReady
_nativeOrderSelectionTurn _nativeOrderTurn _pokerusDone _stadiumReportTicks _stagedLive
_stagedPolled _transformApplied abilityAbsorb abilityColorChange abilityOnContact acc accuracy
acidArmor active activeBattlers affine affineTasks affines afterQueue afterimage aiUses ally
amuletCoin angle animAttackerIsPlayer animFxGen2 animFxSide animName animPlaying anims
applyAnimEffect applyGen3TransformVisual arena arenaOutcome arenaState asm atWord attackerIsPlayer
attackerPosition backgrounds badges baitFactor ball ballChain ballFrame ballId ballObj ball_thrown
batonPassChooser battleRef battleTower battleType battler battlerAt battlerPic battler_switched
battlers bg bgAnim bgCanvas bgLayer bgScroll bgShake bgSides bgSwitchState bgTask bgWaits bideDamage
bideTurns blackedOut blankForAskName blends blocked bottom_ui_visible bounceAmp bounceAngle
bounceStep boundTurns branchCtx brightness bugContest bugContestBalls bw bwAquaRing bwAutoSwitch
bwBalloon bwBattle bwBound bwCharged bwChoice bwChoiceLock bwConsumedItem bwDisabled bwEmbargo
bwFirstTurn bwGravityGround bwGrounded bwHealBlock bwHungOn bwLightFromSide bwLockKind bwMagnetRise
bwMicle bwMistFromSide bwMoveIdByName bwMovedTurn bwOwnStats bwReflectFromSide bwRoll bwRoost
bwSkyDropped bwSnatch bwSpeedMultiplier bwTelekinesis bwTrappedByBind bwUproarInst bwUproarTurn
bwWeightLoss callStack calls cam camTask camouflage canLose cancelMoveAnim carry catch_exp caught
caughtMark caughtMarkerVisible caught_marker_visible cell cellArt charIndex charTimer chargeReady
charge_required charging children choosingBattler choosingSlot chosenTargets closed code codes
colorFxReady confusedTurns consumedItem contest contestBallName count counterpartBack crit
cryPending cryPlaying curMoves curStats curTypes current cursed cycles damage damage_dealt darkGrass
dead deepFog def deferBalls delay demo demoBackPath demoBallCount demoName demoTimer depth dest
destinyBond direction disabledMove disabledSlot disabledTurns done double drainFloor drainHold
drainNext draining dramaticNativePositions drawBattlerPic drawBattlerPicAt drawGen3MonBg
drawGen3MonBgState drowsyTurns dudeDemo effectPlaying effectWindow effects elapsed emitterAt
emitterSeq emitterWaits emitterX emitterY emitters encoreMove encoreTurns endBattleText ended
enduring enemy enemyAIMods enemyHidden enemyIndex enemyIndexB enemyIndexRight enemyParty enemyPartyB
enemySendingOut enemySide enemy_action enemy_switch_or_item enigmaBerries enigmaBerry escapeFactor
event eventCursor eventOamY events expFilling expFraction expHold expPaidPerSlot expShown exp_award
exp_gained f fades fainted fan field fieldHidden fieldWeatherFromMap field_residual finished
firstBattle firstBattleKind flashFire flinched flipped flourish focusEnergy foeSummaryParty foesOf
forecastAll foresighted forfeitable forfeited frame frames frlgIntro from fromX fromY fx g2MomAward
gaugesHidden gen3AnimPlaying gen3AnimShake gen3Ball gen3BallPlaying gen3Frontier gen3ItemsUsed
gen3Scene gen3SurfaceWidth gen3Terrain gen4AnimAttackerIsPlayer gen4AnimPlaying gen4Ball
gen4BallChain gen4BallWobble gen4BallWobbleFrame gen4CursorActive gen4Gauge gen4ItemTargetScreen
gen4Layout gen4MenuColumn gen4PenaltyPaid gen4Safari gen4SurfaceWidth gen4TouchPress gen5
gen5CriticalCapture gen5Terrain gen5ThickGrass gfx ghost ghostReal ghostReveal ghostUnveiled
grayPics grayscale ground groundY groups growIn grudge hazeStatReset header heaves
heldConfusionCounters hiddenAs hold hurtThisTurn i images index infatuated ingrained
interactiveChoices introBalls introBallsFrom introSlide introText invulnerable isDouble isGymLeader
isPlayer itemDef items itemsByKey keepSprites keptSprites key kind kinds lastAttacker lastBall
lastConsumedItem lastDamage lastFoeLevel lastMove layer layout leechSeeded letterboxWhite leveledUp
lightScreen lineIndex lines link linkRole live liveChildren lockedBall loops lowHealthAlarmDisabled
lowHealthAlarmOn low_health_alarm managers markMissed memento menuBattler menuIndex menuLockedAction
menu_auxiliary mimicChoice mimicCtx mimicIndex mimicMoves mimicRestores missing mist mode mon
monAnim monBgSide monBgTimeline monBlend monHidden monPriority monRise monScale monSpriteManager
monSprites monToSwitchInto monWindowRect move moveAnimRow moveEvent moveId moveIndex moveSwapIndex
move_grid_navigation move_used msgPreWait msgPrompt msgPromptWait msgWaiting musicKind mustRecharge
name nextInsert nightmare noCatch noExp noItems noRun oakDemo oakMsgFlags oamGlobalTieResidual
oamRanks oamY objIndex objects objs onDone onSound onTransform oneWay open oppClass opponentName
opts orbit overlay p palCache palPark palace palaceLow participants particles partnerOf partyIndex
payDay pc pendingActions pendingHit pendingLayout pendingMove pendingReplacements performMove
perishTurns phase phaseFrame phases physicalDamageTaken picAnim picFx picHidden picImage picOff
picOffset platformsHidden player playerParty playerPartyIndices playing pokedude pokedudeDemo
position presetVars priority programs projections protectRun protecting quads queue quiet rage
rageMove rampMove rampTurns ranFrames randomTurnNumber rank record reflect reload remainder result
rngState roamer roamerEscaped rolling rolloutTurns rotate rotateTracks rulesets run runAttempts
safari safariCatchRate safeguardTurns saidBallMissing save savedCam scale scanlines scopeReveal
screenFlash screens script scriptObjs scriptTimer scrollPx seed send sendOut sendingOut seq shake
shakeOffset shakeTask shakes shakesShown shellBellDrain shiny shinyStars showEnemyBalls
showEnemyTrainer showPlayerBack shown shownHP shownStatus side sideBeaten sideOf sideToxic sides
silentEnemyIntro sine size skipped sleepTurns slidingBackpic slots sound soundEvents soundWaitTimer
soundWaits sounds specialDamageTaken species speciesSprite spectating speed spin splitFx sprite
spriteCtxs spriteReloads sprites stack stages stars start started starved state statusHUDVisible
statusLabel status_hud_visible status_inflicted statuses step stepCount stepDelta stepIndex stepLeft
steps stockpile style substituteHP surf switchingOut syncShownStatus t tail target targetChoices
targetIndex targetPosition tasks tauntBlocks tauntTurns terrain textures throw timing to
tormentBlocks tormented total toxicCounter trainerB trainerLabel trainerPicB transform transformed
trapped trappingTurns turn turnCount turn_ended turn_order turn_started turnsOut typeSource
unsupported uproarTurns usedItem value vars victoryMusicPlayed visible voltTackle wait waitFrames
waitKind waitReload waitingSound waitingSoundT waitingUI wallyTutorial warned waveCanvas waveQuad
weather what whiteout wideRegion wildFoesStanding wishHeal wishTurns wobbles wordAt work x xAccuracy
y yield z
]])
local BATTLER_SKIP = names("def badgeBoosts statuses items natures sprite picAnim monAnim")
local DATA = names("rulesets pokemon moves statuses items constants type_chart trainers move_effects")
local function keys(t)
  local out = {}
  for key in pairs(t) do
    assert(type(key) == "string" or type(key) == "number" or type(key) == "boolean", "semantic state has an object key")
    out[#out + 1] = key
  end
  table.sort(out, function(a, b)
    if type(a) == type(b) then
      if type(a) == "boolean" then return not a and b end
      return a < b
    end
    return type(a) < type(b)
  end)
  return out
end
local function anchors(game)
  local byObject = {}
  local function visit(value, path, depth)
    if type(value) ~= "table" or byObject[value] or depth > 6 then
      return
    end
    byObject[value] = path
    for _, key in ipairs(keys(value)) do
      local child = {}
      for i, v in ipairs(path) do
        child[i] = v
      end
      child[#child + 1] = key
      visit(value[key], child, depth + 1)
    end
  end
  visit(game.save.party, { "party" }, 0)
  for _, name in ipairs(keys(DATA)) do
    visit(game.data[name], { "data", name }, 0)
  end
  return byObject
end
local function anchor(game, path)
  assert(type(path) == "table" and #path >= 1 and #path <= 9, "invalid semantic anchor")
  local value, first
  if path[1] == "party" then
    value, first = game.save.party, 2
  else
    assert(path[1] == "data" and DATA[path[2]], "invalid content anchor")
    value, first = game.data[path[2]], 3
  end
  for i = first, #path do
    assert(type(value) == "table", "missing content anchor")
    value = value[path[i]]
  end
  assert(type(value) == "table", "semantic anchor is unavailable")
  return value
end
local function encode(game, root)
  local known = anchors(game)
  local nodes, seen = {}, {}
  local function value(v)
    local kind = type(v)
    if kind ~= "table" then
      assert(kind == "string" or kind == "number" or kind == "boolean", "opaque battle continuation")
      return { scalar = v }
    end
    if known[v] then
      return { anchor = known[v] }
    end
    if seen[v] then
      return { node = seen[v] }
    end
    local actionSlot
    if getmetatable(v) ~= nil then
      -- Only the native PP-slot owner can authenticate this action view.
      -- Its existing factory reconstructs the binding; no metatable is saved.
      local choices = package.loaded["src.battle.EnemyMoveChoice"]
      if type(choices) == "table" and choices.slot and choices.withMove then
        local selected = choices.slot(v)
        if selected ~= v then
          assert(not choices.nativeView(v), "delegated action metadata is opaque")
          for key in pairs(v) do
            local _, _, reference = choices.publicReference(v, key)
            assert(not reference, "delegated action references are opaque")
          end
          actionSlot = selected
        end
      end
      assert(actionSlot, "opaque battle state")
    end
    assert(#nodes < 20000, "battle continuation exceeds node limit")
    local id = #nodes + 1
    seen[v] = id
    local battler = v.mon and v.curMoves and type(v.isPlayer) == "boolean"
    local node = { kind = battler and "battler" or actionSlot and "moveAction" or "data", entries = {} }
    nodes[id] = node
    if actionSlot then node.slot = value(actionSlot) end
    for _, key in ipairs(keys(v)) do
      if not (battler and BATTLER_SKIP[key]) then
        node.entries[#node.entries + 1] = { key = key, value = value(v[key]) }
      end
    end
    return { node = id }
  end
  local first = value(root)
  return { schema = 1, root = first, nodes = nodes }
end
local function decode(game, graph, battle)
  assert(
    type(graph) == "table" and graph.schema == 1 and type(graph.nodes) == "table" and #graph.nodes <= 20000,
    "invalid battle graph"
  )
  local tables = {}
  for i in ipairs(graph.nodes) do
    tables[i] = {}
  end
  local function value(v)
    assert(type(v) == "table", "invalid semantic value")
    if v.anchor then
      return anchor(game, v.anchor)
    end
    if v.node then
      return assert(tables[v.node], "invalid semantic reference")
    end
    assert(
      type(v.scalar) == "number" or type(v.scalar) == "string" or type(v.scalar) == "boolean",
      "invalid semantic scalar"
    )
    return v.scalar
  end
  for i, node in ipairs(graph.nodes) do
    assert(node.kind == "data" or node.kind == "battler" or node.kind == "moveAction", "invalid semantic node")
    assert(type(node.entries) == "table", "invalid semantic entries")
    for _, entry in ipairs(node.entries) do
      assert(type(entry.key) == "string" or type(entry.key) == "number" or type(entry.key) == "boolean", "invalid semantic key")
      assert(node.kind ~= "moveAction" or entry.key ~= "pp", "native action PP must come from its slot")
      assert(tables[i][entry.key] == nil, "duplicate semantic key")
      tables[i][entry.key] = value(entry.value)
    end
  end
  local rebound = false
  for i, node in ipairs(graph.nodes) do
    if node.kind == "moveAction" then
      local choices = package.loaded["src.battle.EnemyMoveChoice"]
      assert(type(choices) == "table" and choices.withMove, "native action factory is unavailable")
      local action, slot = tables[i], value(node.slot)
      assert(type(slot) == "table" and type(slot.pp) == "number" and action.id ~= nil,
        "invalid native action PP slot")
      tables[i] = choices.withMove(action, action.id, slot, action.slot)
      rebound = true
    end
  end
  if rebound then
    -- Resolve every graph edge again after allocating the authenticated native
    -- views, so aliases point at the new view rather than a temporary table.
    for i, node in ipairs(graph.nodes) do
      for _, entry in ipairs(node.entries) do
        rawset(tables[i], entry.key, value(entry.value))
      end
    end
  end
  local state = value(graph.root)
  if battle then
    for i, node in ipairs(graph.nodes) do
      if node.kind == "battler" then
        local t = tables[i]
        local fresh = require("src.battle.BattleState").makeBattler(
          game.data,
          t.mon,
          t.isPlayer,
          t.isPlayer and game.save or nil,
          battle
        )
        for key in pairs(BATTLER_SKIP) do
          t[key] = fresh[key]
        end
        -- The native factory loads this read service on hosts that use it.
        -- Earlier owners read held items directly and have no separate binder.
        local itemReads = package.loaded["src.battle.HeldItemRead"]
        if type(itemReads) == "table" then itemReads.bind(t, battle) end
      end
    end
  end
  return state
end
local PHASES = { menu = true, moveSelect = true, targetSelect = true }
local EXCLUDED = names(
  "linkBattle safari gen4Safari ghost scopeReveal demo pokedudeDemo bugContest palace arena gen3Frontier battleTower dead result"
)
local function decision(battle)
  assert(getmetatable(battle) == require("src.battle.BattleState"), "not a native battle")
  assert(PHASES[battle.phase], "battle is not at a player decision")
  for key in pairs(EXCLUDED) do
    assert(not battle[key], "special battle has no qualified continuation")
  end
  assert(
    not battle.current and not battle.animPlaying and not battle.hpDraining and not battle.expDraining,
    "battle animation or message is active"
  )
  assert(type(battle.queue) == "table" and next(battle.queue) == nil, "battle action queue is active")
  assert(not battle.introSlide or battle.introSlide == 0, "battle intro is active")
  assert(require("src.battle.BattleState")._checkpointOwnsRng(battle), "custom battle RNG is opaque")
  for _, who in ipairs({ battle.player, battle.player2 }) do
    if who then
      for _, key in ipairs({ "mustRecharge", "rageMove", "thrashTurns", "charging", "bwSkyDropped" }) do
        assert(not who[key] or who[key] == 0, "battle requires a forced action")
      end
    end
  end
end
function B.bind(battle, descriptor, callback)
  local owner = { descriptor = descriptor, callback = callback or battle.onFinish }
  battle._checkpointContinuation = owner
  owners[battle] = owner
end
local function continuation(game, battle, clone)
  if battle.onFinish == nil then
    return { kind = "none" }
  end
  local owner = assert(owners[battle], "battle completion callback is opaque")
  assert(owner.callback == battle.onFinish, "battle completion callback was replaced")
  if owner.descriptor.kind == "script" then
    return require("src.core.CheckpointScript").capture(game, owner.descriptor, clone)
  end
  local record = {}
  for key, v in pairs(owner.descriptor) do
    if key ~= "onDone" then
      record[key] = v
    end
  end
  record.onDone = require("src.core.CheckpointCallbacks").capture(owner.descriptor.onDone, clone)
  return clone(record)
end
-- Native turnActions uses battlers as dictionary keys. Encode that one
-- relationship explicitly; arbitrary object-keyed mod tables remain refused.
local function actionPosition(actor)
  assert(type(actor) == "table" and actor.mon and actor.curMoves
    and type(actor.isPlayer) == "boolean", "opaque native action owner")
  -- Ordinary singles do not populate the optional double-battle position.
  local position = actor.position
  if position == nil then position = actor.isPlayer and 0 or 1 end
  assert(type(position) == "number" and position % 1 == 0 and position >= 0 and position <= 3,
    "invalid native action position")
  return position
end
local function actionRows(actions)
  if not actions then return nil end
  local out = { schema = 1, turn = actions.turn, rows = {} }
  for actor, action in pairs(actions) do
    if actor ~= "turn" then
      out.rows[#out.rows + 1] = { actor = actor, action = action, position = actionPosition(actor) }
    end
  end
  table.sort(out.rows, function(a, b) return a.position < b.position end)
  return out
end
local function nativeActions(record)
  if not record then return nil end
  assert(record.schema == 1 and type(record.rows) == "table", "invalid native action relationships")
  assert(record.turn == nil or (type(record.turn) == "number" and record.turn >= 0
    and record.turn % 1 == 0), "invalid native action turn")
  local out, positions = { turn = record.turn }, {}
  for _, row in ipairs(record.rows) do
    local actor = row.actor
    local position = actionPosition(actor)
    assert(row.position == position, "native action position differs")
    assert(not positions[position] and type(row.action) == "table", "duplicate or invalid native action")
    local choices = package.loaded["src.battle.EnemyMoveChoice"]
    local slot = type(choices) == "table" and choices.slot and choices.slot(row.action)
    if slot and slot ~= row.action then
      local belongs = false
      for _, move in ipairs(actor.curMoves) do if move == slot then belongs = true end end
      assert(belongs, "native action PP slot belongs to another battler")
    end
    positions[position] = true
    out[actor] = row.action
  end
  return out
end
function B.capture(game, battle, clone)
  decision(battle)
  local world = game.overworld
  for _, key in ipairs({ "parallelRunners", "parallelQueue", "pendingScripts", "scriptMoves" }) do
    assert(not world[key] or next(world[key]) == nil, "concurrent world work is active")
  end
  local owner = owners[battle]
  if world.runner and world.runner:isRunning() then
    assert(owner and owner.descriptor.kind == "script", "world script completion is opaque")
  end
  local state = {}
  for key in pairs(FIELDS) do
    if rawget(battle, key) ~= nil then
      state[key] = battle[key]
    end
  end
  state.turnActions = actionRows(battle.turnActions)
  local ruleset
  for key, v in pairs(game.data.rulesets or {}) do
    if v == battle.ruleset then
      ruleset = key
      break
    end
  end
  assert(ruleset, "battle ruleset is unavailable")
  return clone({
    schema = 1,
    graph = encode(game, state),
    ruleset = ruleset,
    trainerName = battle.trainer and battle.trainer.name,
    continuation = continuation(game, battle, clone),
  })
end
function B.validate(game, snapshot, save, actors)
  local ok = pcall(function()
    assert(
      type(snapshot) == "table" and snapshot.schema == 1 and game.data.rulesets[snapshot.ruleset],
      "invalid battle payload"
    )
    local view = { data = game.data, save = save }
    local s = decode(view, snapshot.graph)
    nativeActions(s.turnActions)
    for key in pairs(s) do
      assert(FIELDS[key], "unknown native battle field")
    end
    assert(PHASES[s.phase] and (s.kind == "wild" or s.kind == "trainer"), "invalid battle decision")
    assert(s.player and s.enemy and s.player.mon and s.enemy.mon, "missing native battlers")
    for key in pairs(EXCLUDED) do
      assert(not s[key], "special battle state is not reconstructible")
    end
    assert(
      type(s.queue) == "table" and next(s.queue) == nil and not s.current and not s.animPlaying,
      "battle actions or messages are active"
    )
    for _, key in ipairs({ "menuIndex", "moveIndex", "frame", "enemyIndex", "partyIndex" }) do
      local n = s[key]
      assert(
        n == nil or (type(n) == "number" and n % 1 == 0 and n >= 0 and n < 1000000000),
        "invalid native battle counter"
      )
    end
    assert(s.field and s.sides and s.field.sides == s.sides, "battle field relationships differ")
    for _, who in ipairs({ s.player, s.enemy, s.player2, s.enemy2 }) do
      if who then
        assert(
          type(who.isPlayer) == "boolean" and type(who.mon) == "table" and game.data.pokemon[who.mon.species],
          "invalid active native battler"
        )
        assert(
          type(who.curMoves) == "table" and type(who.curStats) == "table" and type(who.stages) == "table",
          "invalid active battle statistics"
        )
        for _, move in ipairs(who.curMoves) do
          assert(
            type(move) == "table"
              and (game.data.moves[move.id] or move.id == "STRUGGLE")
              and type(move.pp) == "number"
              and move.pp >= 0,
            "unavailable native move"
          )
        end
        for _, value in pairs(who.curStats) do
          assert(type(value) == "number", "invalid native stat")
        end
        for _, value in pairs(who.stages) do
          assert(type(value) == "number" and value >= -6 and value <= 6, "invalid native stage")
        end
        assert(type(who.mon.hp) == "number" and who.mon.hp >= 0, "invalid native HP")
      end
    end
    local found = false
    for _, mon in ipairs(save.party or {}) do
      if s.player.mon == mon then
        found = true
        break
      end
    end
    assert(found, "active player is outside the saved party")
    for _, node in ipairs(snapshot.graph.nodes) do
      if node.kind == "battler" then
        -- All battlers are reached again during reconstruction; invalid content
        -- cannot be deferred to a later turn.
        for _, entry in ipairs(node.entries) do
          if entry.key == "mon" then
            local mon
            if entry.value.anchor then
              mon = anchor(view, entry.value.anchor)
            elseif entry.value.node then
              local n = snapshot.graph.nodes[entry.value.node]
              for _, e in ipairs(n.entries) do
                if e.key == "species" then
                  mon = { species = e.value.scalar }
                end
              end
            end
            assert(mon and game.data.pokemon[mon.species], "battle species is unavailable")
          end
        end
      end
    end
    local c = snapshot.continuation
    assert(
      type(c) == "table"
        and (c.kind == "none" or c.kind == "world" or c.kind == "script" or c.kind == "trainer" or c.kind == "static"),
      "invalid native completion"
    )
    if c.kind == "trainer" or c.kind == "static" then
      assert(
        type(c.npc) == "string" and require("src.core.CheckpointCallbacks").valid(c.onDone),
        "invalid trainer continuation"
      )
    end
    assert(c.kind ~= "static" or c.onDone ~= nil, "static continuation needs its native completion")
    if actors then
      if c.npc then assert(actors.records[c.npc], "native continuation actor is absent") end
      if c.onDone then assert(actors.records[c.onDone.npc], "native completion actor is absent") end
    end
    if c.kind == "script" then
      assert(require("src.core.CheckpointScript").validate(game, c), "invalid story continuation")
    end
  end)
  return ok
end
function B.apply(game, snapshot, clone)
  assert(B.validate(game, snapshot, game.save), "invalid battle continuation")
  snapshot = clone(snapshot)
  local battle = require("src.battle.BattleState")._checkpointNew(game)
  local state = decode(game, snapshot.graph, battle)
  state.turnActions = nativeActions(state.turnActions)
  for key in pairs(FIELDS) do
    if rawget(battle, key) ~= nil then
      battle[key] = nil
    end
  end
  for key, v in pairs(state) do
    battle[key] = v
  end
  battle.ruleset = assert(game.data.rulesets[snapshot.ruleset])
  battle._checkpointTrainerName = snapshot.trainerName
  battle:_checkpointArt()
  local c = snapshot.continuation
  if c.kind == "world" then
    battle.onFinish = function(result)
      game.overworld:afterBattle(result, battle)
    end
  elseif c.kind == "static" then
    local callbacks = require("src.core.CheckpointCallbacks")
    local npc = callbacks.actor(game.overworld, c.npc)
    local done = callbacks.build(game.overworld, c.onDone)
    battle.onFinish = function(result)
      game.overworld:_checkpointStaticFinished(battle, npc, done, result)
    end
    B.bind(battle, { kind = "static", npc = c.npc, onDone = done }, battle.onFinish)
  elseif c.kind == "trainer" then
    local callbacks = require("src.core.CheckpointCallbacks")
    local npc = callbacks.actor(game.overworld, c.npc)
    local done = callbacks.build(game.overworld, c.onDone)
    battle.onFinish = function(result)
      game.overworld:_checkpointTrainerFinished(battle, npc, { event = c.event }, npc.def, done, result)
    end
    B.bind(battle, { kind = "trainer", npc = c.npc, event = c.event, onDone = done }, battle.onFinish)
  elseif c.kind == "script" then
    require("src.core.CheckpointScript").apply(game, battle, c)
  end
  if c.kind ~= "none" and c.kind ~= "script" and c.kind ~= "trainer" and c.kind ~= "static" then
    B.bind(battle, c, battle.onFinish)
  end
  return battle
end
return B
