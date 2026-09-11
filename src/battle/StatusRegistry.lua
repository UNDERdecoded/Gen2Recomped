-- Status infliction against the merged statuses registry: the shared
-- immunity rules stay here, the per-status ones live on the records
-- (canInflict) and so does the landing text (onInflict), so a mod status
-- inflicts through the same path as the vanilla five.

local Runtime = require("src.mods.Runtime")
local Status = require("src.battle.Status")
local Strings = require("src.core.Strings")
local HeldItems = require("src.battle.HeldItems")

local StatusRegistry = {}

-- pokered's <USER>/<TARGET> text macros (home/text.asm
-- PlaceMoveUsersName): enemy-mon texts print "Enemy " before the name
local function displayName(b)
  return b.isPlayer and b.name or ("Enemy " .. b.name)
end

-- opts: toxic (start the Toxic counter), moveType (for the type gates),
-- secondary (side-effect of a damaging move), source (inflicting move id).
-- Returns messages; empty means the status did not land.
function StatusRegistry.inflict(battle, target, status, opts)
  opts = opts or {}
  if target.mon.status then return {} end
  -- Substitutes block poison (PoisonEffect calls CheckTargetSubstitute)
  -- and every secondary status, but NOT primary Sleep or Thunder Wave,
  -- their handlers never check the substitute in Gen 1.
  if target.substituteHP and (opts.secondary or status == "PSN") then
    return {}
  end
  -- FreezeBurnParalyzeEffect: a secondary status never lands when the
  -- move's type matches either of the target's types (Body Slam can't
  -- paralyze Normals, Fire can't burn Fire, Ice can't freeze Ice)
  if opts.secondary and status ~= "PSN" then
    for _, t in ipairs(target.curTypes or {}) do
      if opts.moveType == t then return {} end
    end
  end
  -- AN ABILITY THAT SIMPLY REFUSES IT.  A SLUGMA with MAGMA ARMOR cannot be
  -- frozen, a MAKUHITA with GUTS can be burned but a WAILMER with WATER VEIL
  -- cannot -- and no roll and no move gets round any of them.  A Pokemon
  -- from a generation without abilities answers false and nothing changes.
  if require("src.battle.Abilities").refusesStatus(target, status) then
    return {}
  end
  -- SAFEGUARD: the veil refuses every status for its five turns.  A status a
  -- Pokemon inflicts on ITSELF still lands -- REST is the whole reason that
  -- distinction exists -- which is what opts.selfInflicted marks.
  if target.safeguardTurns and not opts.selfInflicted then
    return {}
  end
  local statuses = battle and battle.data and battle.data.statuses
  local record = Status.recordFor(statuses, status)
  -- `battle` is passed so a record can ask the RULESET: Hoenn's poison
  -- immunity covers STEEL as well as POISON, and the records are shared
  if record and record.canInflict
     and not record.canInflict(target, opts, battle) then
    return {}
  end
  target.mon.status = status
  local msgs
  local display = displayName(target)
  if record and record.onInflict then
    msgs = record.onInflict(battle, target, opts, display)
  else
    msgs = { Strings("%s\nwas afflicted\nby %s!", display,
               record and record.label or tostring(status)) }
  end
  Runtime.emit("battle.status_inflicted", {
    battle = battle, target = target, status = status, source = opts.source,
  })
      -- Gen II status berries resolve immediately after the condition lands.
      -- Keep the infliction text first, then append the held-item cure line.
      for _, msg in ipairs(HeldItems.onStatus(battle, target)) do
        msgs[#msgs + 1] = msg
      end

      -- SYNCHRONIZE HANDS IT STRAIGHT BACK.  A poisoned, burned or paralysed
      -- Pokemon with it gives the same condition to whoever did it -- and NOT
      -- sleep or freeze, which is the cartridge's own list rather than a
      -- simplification.  `opts.user` is the one who inflicted it; a status a
      -- Pokemon gave itself has none and nothing bounces.
      --
      -- Guarded against its own recursion: the returned status is inflicted with
      -- `synchronized` set, so a SYNCHRONIZE against a SYNCHRONIZE stops after
      -- one bounce instead of ringing back and forth forever.
      local Abilities = require("src.battle.Abilities")
      local back = (not opts.synchronized) and opts.user
                   and Abilities.synchronizes(target, status) or nil
      if back and opts.user.mon and opts.user.mon.hp > 0 then
        local extra = StatusRegistry.inflict(battle, opts.user, back.status,
                                             { synchronized = true,
                                               user = target,
                                               source = "SYNCHRONIZE" })
        if #extra > 0 then
          msgs[#msgs + 1] = Strings("%s's\nSYNCHRONIZE!", display)
          for _, m in ipairs(extra) do msgs[#msgs + 1] = m end
        end
  end
  return msgs
end

return StatusRegistry
