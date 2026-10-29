-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- pokecrystal GetMovePriority/data/moves/effects_priorities.asm. Older native
-- caches only stamp priority-hit moves; derive the other GSC classes from
-- their native effect rather than treating Protect/Endure as ordinary moves.
local Priority = {}
local effects = {
  PROTECT_EFFECT = 3, ENDURE_EFFECT = 3,
  COUNTER_EFFECT = -1, MIRROR_COAT_EFFECT = -1,
  FORCE_SWITCH_EFFECT = -1,
}
local ids = {
  QUICK_ATTACK = 1, COUNTER = -1, VITAL_THROW = -1,
  -- The shared native cache merges Roar/Whirlwind and Teleport into
  -- SWITCH_AND_TELEPORT_EFFECT. Teleport is not a negative-priority move.
  ROAR = -1, WHIRLWIND = -1,
}
function Priority.get(move)
  if not move then return 0 end
  -- Preserve explicit cartridge/mod data, including an explicit zero.
  if move.priority then return move.priority end
  return effects[move.effect] or ids[move.id] or 0
end
return Priority
