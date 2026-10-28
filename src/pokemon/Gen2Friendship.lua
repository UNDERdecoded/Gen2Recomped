-- Original Gold/Silver/Crystal friendship rules (ChangeHappiness and
-- StepHappiness). Keep these separate from Yellow's companion happiness.
local Friendship = {}
local changes = {
  LEVELUP = {5,3,2}, VITAMIN = {5,3,2}, XITEM = {1,1,0},
  GYMBATTLE = {3,2,1}, LEARNMOVE = {1,1,0},
  FAINT = {-1,-1,-1}, POISONFAINT = {-5,-5,-10},
  STRONGFOE = {-5,-5,-10},
  BITTERPOWDER = {-5,-5,-10}, ENERGYROOT = {-10,-10,-15},
  REVIVALHERB = {-15,-15,-20},
  LEVELUPATHOME = {10,6,4},
}

local events={LEVELUP=1,VITAMIN=2,XITEM=3,GYMBATTLE=4,LEARNMOVE=5,
  FAINT=6,POISONFAINT=7,STRONGFOE=8,BITTERPOWDER=15,ENERGYROOT=16,REVIVALHERB=17,LEVELUPATHOME=19}
local sourceEvents={LEVELUP='GAINLEVEL',VITAMIN='USEDITEM',XITEM='USEDXITEM',
  FAINT='FAINTED',STRONGFOE='BEATENBYSTRONGFOE',LEVELUPATHOME='GAINLEVELATHOME'}
local function changed(mon,from,event,reason)
  local Runtime=require('src.mods.Runtime')
  -- Applied source events remain observable even at byte saturation;
  -- unchanged walking steps do not report a change.
  if (event~=nil or from~=mon.happiness) and Runtime.wants("happiness.changed")then
    Runtime.emit("happiness.changed",{mon=mon,event=event and (sourceEvents[event]or event),
      eventId=events[event],reason=reason,
      from=from,to=mon.happiness,delta=mon.happiness-from})
  end
end

function Friendship.isVanilla()
  return require("src.pokemon.Gen2Breeding").isVanilla()
end

function Friendship.change(mon, reason)
  if not Friendship.isVanilla() then return false end
  if not mon or require("src.pokemon.Party").isEgg(mon) then return true end
  local row = changes[reason]
  if not row or mon.happiness == nil then return true end
  local h = mon.happiness
  local band = h < 100 and 1 or h < 200 and 2 or 3
  mon.happiness = math.max(0, math.min(255, h + row[band]))
  changed(mon,h,reason,"event")
  return true
end

function Friendship.stepCycle(save)
  if not Friendship.isVanilla() then return end
  -- CountStep calls this at byte-counter wrap. StepHappiness itself only
  -- raises friendship on every second call, giving +1 per 512 steps.
  save.g2HappinessStepCount = ((save.g2HappinessStepCount or 0) + 1) % 2
  if save.g2HappinessStepCount ~= 0 then return end
  for _, mon in ipairs(save.party or {}) do
    if not require("src.pokemon.Party").isEgg(mon) and mon.happiness ~= nil then
      local from=mon.happiness
      mon.happiness = math.min(255, mon.happiness + 1)
      changed(mon,from,nil,"step")
    end
  end
end

function Friendship.levelUp(data, save, mon)
  local reason = "LEVELUP"
  if require("src.core.GameVersion").get() == "crystal" then
    local mapId = save.player and save.player.map
    local map = data.maps and data.maps[mapId]
    local location = map and tonumber(map.landmark)
    -- Crystal stores the caught landmark in the low seven bits; Gold and
    -- Silver have no LevelUpHappinessMod and always use the ordinary row.
    if location and location == (tonumber(mon.caughtData) or 0) % 128 then
      reason = "LEVELUPATHOME"
    end
  end
  return Friendship.change(mon,reason)
end

function Friendship.gymBattle(save)
  for _, mon in ipairs(save.party or {}) do
    if (mon.hp or 0) > 0 then Friendship.change(mon,"GYMBATTLE") end
  end
end

function Friendship.faint(mon, enemyLevel)
  -- The cartridge compares against (level + 30) as an eight-bit value.
  local threshold = ((mon.level or 0) + 30) % 256
  return Friendship.change(mon, (enemyLevel or 0) >= threshold and "STRONGFOE" or "FAINT")
end

return Friendship
