-- Round 5: windcrests, Mt. Crenel and the Cave of Flames.
--
-- Hooks (small calls from shared files):
--   Dungeon:spawnObject -> Crenel.spawnObject(dungeon, d)   (nil = not ours)
--   Dungeon:checkFall   -> Crenel.holeLaunch(dungeon, p)    (true = handled)
--   Enemies:spawn       -> Crenel.spawnEnemy(enemies, dat, def) (nil = not ours)
--   Player:useItem      -> Crenel.useItem(player, item, button, input)
--   RoomCode            -> Crenel.windcrest(field, bit)     (activated?)

local bit = require("bit")
local band, lshift = bit.band, bit.lshift

local Crenel = {}

-- gSave.windcrests: bit n set when that windcrest was activated
-- (WINDCREST_* in the decomp's flags.h, bits 24..31)
function Crenel.windcrest(f, n)
  local w = f.save and f.save.windcrests or 0
  return band(w, lshift(1, n)) ~= 0
end

function Crenel.setWindcrest(f, n)
  f.save.windcrests = bit.bor(f.save.windcrests or 0, lshift(1, n))
end

-- round 6: windcrest.c Windcrest_Unlock (the script_Windcrest Call at
-- $080A2138): SFX_SECRET, gSave.windcrests |= 1 << (type2 + 24),
-- FX_GIANT_EXPLOSION on the crest
local Native = require("src.zelda.tmc.Native")
require("src.zelda.tmc.CrenelPath") -- round 8: registers the Melari's Mines natives
Native.N[0x080A2138] = function(f, e)
  f:sound(0x72)
  local t2 = e.data and band(e.data.type2 or e.data.paramB or 0, 0xFF) or 0
  Crenel.setWindcrest(f, t2 + 24)
  if f.addFx then f:addFx(e.x, e.y, 0x0F, 0x46) end
end

function Crenel.spawnObject(dungeon, d)
  if d.id == 0x55 then return require("src.zelda.tmc.Minecart").spawn(dungeon, d) or false end -- MINECART (round 7)
  if d.id == 0x41 then return require("src.zelda.tmc.LadderUp").spawn(dungeon, d) end -- LADDER_UP (round 18)
  if d.id == 0x95 then return require("src.zelda.tmc.ItemOcarina").spawnObject(dungeon, d) end -- BIRD (round 26A, bird.c)
  do local x = require("src.zelda.tmc.CrenelPath").spawnObject(dungeon, d) if x ~= nil then return x end end -- round 8
  return nil
end
function Crenel.holeLaunch(dungeon, p) return require("src.zelda.tmc.Pacci").holeLaunch(dungeon, p) end -- round 7
function Crenel.spawnEnemy(enemies, dat, def)
  if dat.id == 0x24 then -- GLEEROK (round 8, simplified; round 25: gleerok.c ported, BossGleerok2.lua)
    if require("src.zelda.tmc.BossGleerok").simple then return require("src.zelda.tmc.BossGleerok").new(enemies.field, enemies):spawn(dat, def) or false end
    return require("src.zelda.tmc.BossGleerok2").new(enemies.field, enemies):spawn(dat, def) or false
  end
  if dat.id == 0x16 then -- BUSINESS_SCRUB (round 8)
    local BS = require("src.zelda.tmc.BusinessScrub")
    return BS.new(enemies.field, enemies):spawn(dat, def) or false
  end
  return nil
end
function Crenel.useItem(player, item, button, input)
  if require("src.zelda.tmc.Bombs").use(player, item) then return true end -- round 18: bombs
  if require("src.zelda.tmc.ItemsR26").use(player, item, button, input) then return true end -- round 26A: items (ItemsR26.lua)
  if require("src.zelda.tmc.CrenelPath").useBottle(player, item, button) then return true end -- round 8
  return require("src.zelda.tmc.Pacci").use(player, item, button) -- round 7
end

return Crenel
