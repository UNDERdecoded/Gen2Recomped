-- THE PARTNER ON THE PLAYER'S SIDE: how an ally trainer's Pokemon picks its
-- move in a tag battle (Platinum's starttagbattle -- the story's tag battles
-- and the Battle Tower's multi rooms).
--
-- The cartridge runs the partner through the same trainer AI as a foe, with
-- the trainer's AI flags. This port's trainer AI scores against `battle.player`
-- and has no notion of an ally, so the partner gets a small one of its own:
-- every usable damaging move against every standing foe, scored by power,
-- type effectiveness, same-type bonus and accuracy, the best pair taken; a
-- Pokemon with nothing that can hurt anybody picks among what it can use.

local TypeChart = require("src.battle.TypeChart")

local AllyAI = {}

local function stab(battler, moveType)
  for _, t in ipairs(battler.curTypes or {}) do
    if t == moveType then return 1.5 end
  end
  return 1
end

function AllyAI.score(battle, battler, moveDef, foe)
  local power = tonumber(moveDef and moveDef.power) or 0
  if power <= 1 then return 0 end
  local ok, eff = pcall(TypeChart.effectiveness, moveDef.type, foe.curTypes)
  eff = ok and tonumber(eff) or 1
  local acc = tonumber(moveDef.accuracy) or 100
  if acc <= 0 then acc = 100 end
  return power * eff * stab(battler, moveDef.type) * acc / 100
end

-- a move entry from battler.curMoves (or Struggle), with the target recorded
-- where the turn reads a chosen one
function AllyAI.choose(battle, battler, rng)
  rng = rng or love.math.random
  local usable = {}
  for i, mv in ipairs(battler.curMoves or {}) do
    if battler.disabledSlot ~= i and (mv.pp or 0) > 0 then usable[#usable + 1] = mv end
  end
  if #usable == 0 then return { id = "STRUGGLE", pp = 1, struggle = true } end
  -- PLATINUM / HGSS: the partner runs the cartridge's trainer AI with its own
  -- trainer's aiMask (TrainerAI_PickCommand, then TrainerAI_Main doubles)
  local okG4, Gen4AI = pcall(require, "src.battle.Gen4AI")
  if okG4 and Gen4AI.applies(battle) then
    local okC, act = pcall(Gen4AI.command, battle, battler)
    if okC and act then return act end
    if Gen4AI.program(battle) then
      local okP, move, target = pcall(Gen4AI.choose, battle, battler, usable)
      if okP and move then
        for _, u in ipairs(usable) do
          if u == move then
            if battler.position and target then
              battle.chosenTargets = battle.chosenTargets or {}
              battle.chosenTargets[battler.position] = target
            end
            return move
          end
        end
      end
    end
  end
  local foes = battle.foesOf and battle:foesOf(battler) or {}
  local best, bestMove, bestFoe = 0, nil, nil
  for _, mv in ipairs(usable) do
    local def = battle.data.moves and battle.data.moves[mv.id]
    for _, foe in ipairs(foes) do
      if foe and foe.mon and (foe.mon.hp or 0) > 0 then
        local s = AllyAI.score(battle, battler, def, foe)
        if s > best then best, bestMove, bestFoe = s, mv, foe end
      end
    end
  end
  if bestMove then
    if battler.position and bestFoe then
      battle.chosenTargets = battle.chosenTargets or {}
      battle.chosenTargets[battler.position] = bestFoe
    end
    return bestMove
  end
  return usable[rng(1, #usable)]
end

return AllyAI
