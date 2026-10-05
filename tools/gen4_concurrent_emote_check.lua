-- Run:  texlua tools/gen4_concurrent_emote_check.lua <cache dir>
--
-- TWO "!" BUBBLES AT ONCE MUST BOTH FINISH.
--
-- Reported from play: in Sandgem, after the Pokedex, leaving Rowan's lab "the
-- exclamation point appears but it freezes there". The scene (M1059/S057D)
-- gives the player and object 4 an EMOTE_EXCLAMATION_MARK back to back and
-- `waitmovement`s on both; the overworld had one emote slot, the second bubble
-- overwrote the first, and the first movement never released its wait.
--
-- This runs the cartridge's own two `applymovement` rows from that script
-- through the real Gen4Commands step chain, then counts the bubbles down the
-- way OverworldState:update does, and requires the join to come back to 0.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = (arg and arg[1] or 'G:/Gen2Recomped/platinum/data/generated'):gsub('[/\\]$', '')
package.loaded['src.core.Sound'] = { play = function() end }
local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local scripts = assert(loadfile(cacheDir .. '/map_scripts.lua'))()

local sc = scripts.scripts['M1059/S057D']
check(sc, 'the Sandgem lab-exit scene is in the cache')
local moves = {}
for _, ins in ipairs(sc and sc.instructions or {}) do
  if ins.name == 'applymovement' then moves[#moves + 1] = ins end
end
check(#moves >= 3, 'with its movements')
local playerMove, objMove = moves[2], moves[3]
check(playerMove and playerMove.args[1] == 255 and playerMove.movement[1].action == 75,
      'the player\'s starts with EMOTE_EXCLAMATION_MARK')
check(objMove and objMove.args[1] == 4 and objMove.movement[1].action == 75,
      'and so does object 4\'s, in the same breath')

-- a stub field: the player and object 4, with the queue methods the steps use
local player = { localId = 255, cellX = 5, cellY = 8, facing = 'down', stepFrames = 16 }
local obj4 = { localId = 4, cellX = 6, cellY = 8, facing = 'down', stepFrames = 16, def = { localId = 4 } }
local ow = { map = { id = 'T02', def = {} }, entities = { obj4 }, player = player }
local pending = {}
function ow:scriptPause(_, _, done) pending[#pending + 1] = done end
function ow:scriptMove(_, _, _, done) pending[#pending + 1] = done end
local ctx = { overworld = ow, save = { flags = {}, gen4Vars = {} }, game = { data = {} },
              runner = { parallel = false, resume = function() end } }

C.g4_move(ctx, playerMove.args[1], playerMove.movement)
C.g4_move(ctx, objMove.args[1], objMove.movement)
check(ow.emote and ow.extraEmotes and #ow.extraEmotes == 1,
      'both bubbles are up: one in the slot, one alongside it')
check((ctx.g4Moving or 0) == 2, 'and both movements hold the wait')

-- count down as OverworldState:update does (extras first, then the slot)
for _ = 1, 200 do
  if ow.extraEmotes and ow.extraEmotes[1] then
    local keep, finished = {}, {}
    for _, e in ipairs(ow.extraEmotes) do
      e.frames = e.frames - 1
      if e.frames <= 0 then finished[#finished + 1] = e else keep[#keep + 1] = e end
    end
    ow.extraEmotes = keep
    for _, e in ipairs(finished) do if e.onDone then e.onDone() end end
    if not ow.emote and ow.extraEmotes[1] then ow.emote = table.remove(ow.extraEmotes, 1) end
  end
  if ow.emote then
    ow.emote.frames = ow.emote.frames - 1
    if ow.emote.frames <= 0 then
      local done = ow.emote.onDone
      ow.emote = nil
      if ow.extraEmotes and ow.extraEmotes[1] then ow.emote = table.remove(ow.extraEmotes, 1) end
      if done then done() end
    end
  end
  local p = pending
  pending = {}
  for _, f in ipairs(p) do f() end
  if (ctx.g4Moving or 0) == 0 and not ow.emote then break end
end
check((ctx.g4Moving or 0) == 0, 'the wait is released -- the scene goes on (was: frozen at the "!")')
check(player.facing == 'up', 'and the player turned north as the movement says')

-- the real update and draw use the same machinery
local src = io.open('src/world/OverworldController.lua'):read('a')
check(src:find('if self.extraEmotes and self.extraEmotes[1] then', 1, true),
      'OverworldState:update counts the extra bubbles down')
check(src:find('function OverworldState:eachEmote(fn)', 1, true), 'and draws every bubble')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
