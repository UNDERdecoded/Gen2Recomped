-- Run:  texlua tools/gen4_turnback_cave_check.lua <cache dir>
--
-- TURNBACK CAVE IS A MAZE THE ROOM BUILDS AS IT LOADS.
--
-- `initturnbackcave` was the most widely reached unlowered command in the
-- cartridge -- 20 uses, one in the init script of every room of the cave, and
-- 20 distinct maps, more than anything else unlowered. Counting by MAPS rather
-- than by occurrences is what surfaced it: by raw count it sat twentieth.
--
-- Every room ships with all four of its exits pointing at the ENTRANCE. That
-- is not a shortfall of polish: it means the cave is one room you walk out of,
-- and the Giratina room has no route to it at all.

package.path = './?.lua;./?/init.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_turnback_cave_check.lua <cache dir>')
  os.exit(2)
end
local maps = assert(loadfile(cacheDir .. '/maps.lua'))()

require('src.script.Gen4Commands')
local Commands = require('src.script.Commands')
local Warp = require('src.world.Warp')

check(type(Commands.g4_init_turnback_cave) == 'function',
      'initturnbackcave must be lowered to a command')

-- The VM must emit it, or the command exists and nothing calls it.
local vm = io.open('src/script/Gen4ScriptVM.lua'):read('a')
check(vm:match('L%.initturnbackcave'), 'and the VM must lower the opcode')
check(vm:match('g4_init_turnback_cave'), 'to that command')

-- ============================== 1. the cave is unreachable without this
--
-- The premise, asserted rather than assumed. If a future import gave these
-- rooms varied destinations the whole command would be unnecessary and this
-- check should say so loudly rather than keep passing.
local ROOMS = {}
for id, def in pairs(maps) do
  local h = tonumber(def.header)
  if h and ((h >= 268 and h <= 273) or (h >= 518 and h <= 532)) then
    ROOMS[#ROOMS + 1] = { id = id, header = h, def = def }
  end
end
table.sort(ROOMS, function(a, b) return a.header < b.header end)
check(#ROOMS == 21,
      'the cache must carry all 21 Turnback Cave rooms, got ' .. #ROOMS)

local pillarRooms, allToEntrance = 0, 0
for _, r in ipairs(ROOMS) do
  if r.header >= 271 then
    pillarRooms = pillarRooms + 1
    local warps = r.def.warps or {}
    local toEntrance = 0
    for _, w in ipairs(warps) do
      if tonumber(w.destHeader) == 268 then toEntrance = toEntrance + 1 end
    end
    if #warps > 0 and toEntrance == #warps then allToEntrance = allToEntrance + 1 end
  end
end
check(pillarRooms == 18, 'eighteen of them are pillar rooms, got ' .. pillarRooms)
check(allToEntrance == pillarRooms,
      'and as shipped EVERY exit of EVERY pillar room must lead back to the '
      .. 'entrance -- that is what makes the cave impassable without this '
      .. 'command; ' .. allToEntrance .. ' of ' .. pillarRooms)

-- ===================== 2. the room ids are the cartridge's, not invented
--
-- Each of the 21 headers must be carried by exactly one map, or the lookup the
-- command does resolves to nothing and the maze silently does not build.
local byHeader = {}
for _, r in ipairs(ROOMS) do
  check(byHeader[r.header] == nil,
        'header ' .. r.header .. ' must name one map, not two')
  byHeader[r.header] = r.id
end
for _, h in ipairs({ 268, 269, 270, 271, 273, 518, 520, 521, 526, 527, 532 }) do
  check(byHeader[h], 'header ' .. h .. ' must be carried by a map')
end

-- =========================== 3. the command repoints every exit but one
local function harness(mapId, px, pz)
  local save = { vars = {} }
  local ow = { map = { id = mapId }, player = { cellX = px, cellY = pz } }
  return { save = save, overworld = ow,
           game = { data = { maps = maps } } }, save
end

-- A room, entered by the north door at (11, 1) -- the cartridge's warp 0.
local room = byHeader[271]
local ctx, save = harness(room, 11, 1)
Commands.g4_init_turnback_cave(ctx, 0, 0)
local tb = save.gen4Turnback
check(type(tb) == 'table', 'the command must record the maze it built')
check(tb and tb.map == room, 'against the room it ran on')
check(tb and tb.keep == 1,
      'entering at (11,1) is the cartridge\'s warp 0, so our warp 1 must be '
      .. 'the one kept; got ' .. tostring(tb and tb.keep))
check(tb and tb.dest and maps[tb.dest],
      'and the destination must be a map this cache has, got '
      .. tostring(tb and tb.dest))

-- The other three entrances, transcribed from the cartridge's own test.
local function keepFor(px, pz)
  local c, s = harness(room, px, pz)
  Commands.g4_init_turnback_cave(c, 0, 0)
  return s.gen4Turnback and s.gen4Turnback.keep
end
check(keepFor(20, 11) == 2, 'x=20 is warp 1, so our 2')
check(keepFor(11, 20) == 3, 'x=11 z=20 is warp 2, so our 3')
check(keepFor(2, 11) == 4, 'anything else with x~=11 is warp 3, so our 4')
-- ...AND THE SENTINEL. x == 11 with z neither 1 nor 20 answers 5 on the
-- cartridge, which matches no warp in its 0..3 loop -- so all four are
-- repointed. Reproduced rather than tidied into a fourth door.
check(keepFor(11, 9) == nil,
      'standing mid-room keeps NO exit, because the cartridge\'s answer of 5 '
      .. 'matches none of the four it rewrites')

-- ================================ 4. the ladder the destination is chosen by
--
-- Three pillars seen is the way out; thirty rooms without them returns you to
-- the entrance. Both are exact and neither involves the dice.
local c3 = harness(room, 11, 1)
Commands.g4_init_turnback_cave(c3, 3, 0)
local tb3 = c3.save.gen4Turnback
check(tb3 and tb3.dest == byHeader[270],
      'three pillars seen must lead to the Giratina room, got '
      .. tostring(tb3 and tb3.dest))

local c30 = harness(room, 11, 1)
Commands.g4_init_turnback_cave(c30, 0, 30)
local tb30 = c30.save.gen4Turnback
check(tb30 and tb30.dest == byHeader[268],
      'thirty rooms without them must put you back at the entrance, got '
      .. tostring(tb30 and tb30.dest))

-- ...and with neither condition met the destination is a pillar room or one of
-- the six belonging to the pillar you are on. Sampled, because it is random:
-- what must hold is that it is ALWAYS one of those seven, never anything else.
local allowed = { [byHeader[269]] = true }
for i = 0, 5 do allowed[byHeader[271 + i] or byHeader[518 + (i - 3)]] = true end
-- band 0 is headers 271,272,273,518,519,520
allowed[byHeader[271]] = true ; allowed[byHeader[272]] = true
allowed[byHeader[273]] = true ; allowed[byHeader[518]] = true
allowed[byHeader[519]] = true ; allowed[byHeader[520]] = true
local picked, outside = {}, 0
for _ = 1, 400 do
  local c = harness(room, 11, 1)
  Commands.g4_init_turnback_cave(c, 0, 0)
  local d = c.save.gen4Turnback and c.save.gen4Turnback.dest
  picked[d] = (picked[d] or 0) + 1
  if not allowed[d] then outside = outside + 1 end
end
check(outside == 0,
      'with no pillars seen the destination must always be the pillar room or '
      .. 'one of pillar 1\'s six, got ' .. outside .. ' outside that set')
local distinct = 0
for _ in pairs(picked) do distinct = distinct + 1 end
check(distinct >= 5,
      'and it must actually vary -- a maze that always picks one room is a '
      .. 'corridor; saw ' .. distinct .. ' distinct destinations in 400 draws')

-- The pillar band moves with the counter: with two pillars seen the six rooms
-- must come from pillar 3's block, never pillar 1's.
local band3 = {}
for h = 527, 532 do band3[byHeader[h]] = true end
band3[byHeader[269]] = true
local wrongBand = 0
for _ = 1, 400 do
  local c = harness(room, 11, 1)
  Commands.g4_init_turnback_cave(c, 2, 0)
  local d = c.save.gen4Turnback and c.save.gen4Turnback.dest
  if not band3[d] then wrongBand = wrongBand + 1 end
end
check(wrongBand == 0,
      'two pillars seen must draw from pillar 3\'s six rooms, got '
      .. wrongBand .. ' from elsewhere')

-- ====================== 5. and the warp resolver actually honours it
--
-- A command that records a maze nothing reads is the same bug one layer along.
-- DRIVEN THROUGH `Warp.destination` ITSELF, not scanned for in its source.
--
-- The first version of this section matched three strings in `Warp.lua` and
-- passed with the one line that does the work replaced by `destMap = destMap`:
-- every other string was still there. A name is not a call. These assertions
-- take a real warp out of a real room's def and ask where it leads.
local function wentTo(mapId, index, save)
  local def = maps[mapId]
  local warpDef = def and def.warps and def.warps[index]
  if not warpDef then return nil end
  local dest = Warp.destination({ maps = maps }, warpDef, nil, nil, save)
  return dest
end

local liveSave = { vars = {} }
local liveCtx = { save = liveSave, overworld = { map = { id = room },
                  player = { cellX = 11, cellY = 1 } },
                  game = { data = { maps = maps } } }
-- Three pillars, so the destination is fixed and this tests routing rather
-- than the dice.
Commands.g4_init_turnback_cave(liveCtx, 3, 0)
local giratina = byHeader[270]
check(liveSave.gen4Turnback and liveSave.gen4Turnback.dest == giratina,
      'the maze under test must lead to the Giratina room')

check(wentTo(room, 2, liveSave) == giratina,
      'an exit the player did not come in by must now lead where the maze says '
      .. '-- got ' .. tostring(wentTo(room, 2, liveSave)))
check(wentTo(room, 3, liveSave) == giratina, 'and so must the next')
check(wentTo(room, 4, liveSave) == giratina, 'and the last')
-- ...AND THE ONE THEY CAME IN BY IS UNTOUCHED.
check(wentTo(room, 1, liveSave) == maps[room].warps[1].destMap,
      'the exit the player entered by must keep the destination it shipped '
      .. 'with -- got ' .. tostring(wentTo(room, 1, liveSave)))

-- A ROOM THE MAZE IS NOT ABOUT must be unaffected, which is what the identity
-- match buys: warp 2 of some other map is a different table.
local other
for _, r in ipairs(ROOMS) do
  if r.id ~= room and r.header >= 271 then other = r.id break end
end
check(other, 'another pillar room must exist to test against')
if other then
  check(wentTo(other, 2, liveSave) == maps[other].warps[2].destMap,
        'another room\'s warp of the same index must NOT pick up this room\'s '
        .. 'maze -- got ' .. tostring(wentTo(other, 2, liveSave)))
end

-- With no maze recorded at all, every warp leads where it always did.
check(wentTo(room, 2, { vars = {} }) == maps[room].warps[2].destMap,
      'and with no maze built, nothing is redirected')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
