-- Run:  texlua tools/gen4_movement_concurrency_check.lua
--
-- `applymovement` STARTS A WALK; `waitmovement` IS WHAT WAITS FOR IT.
--
-- Reported from play: *"in oreburg where the npc walks you to the gym it has me
-- walk to the gym and then the player walks to the gym after i get there
-- instead of following"* -- with *"ensure we have rom parity for events like
-- this"*.
--
-- `ScrCmd_ApplyMovement` starts an animation and lets the script run on. This
-- port played the whole list inline through `walkEntity`, which yields per
-- step, so two objects told to move in consecutive rows moved one after the
-- other. The source said so and called it a timing difference; it is a timing
-- difference in precisely the scenes that are about timing.
--
-- MEASURED over the cartridge's 8,567 scripts: 3,025 `applymovement` against
-- 2,167 `waitmovement`, and 862 applies are issued BACK-TO-BACK with no wait
-- between -- two or more actors the cartridge moves together. Every one of
-- those 862 was being serialised.

package.path = './?.lua;./?/init.lua;./tools/save-editor/?.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

require('src.script.Gen4Commands')
local Commands = require('src.script.Commands')
check(type(Commands.g4_move) == 'function', 'applymovement must be registered')
check(type(Commands.g4_wait_move) == 'function',
      'waitmovement must be a FUNCTION -- it was `noop`, which it could afford '
      .. 'to be only while applymovement blocked')

-- A fake OVERWORLD and RUNNER -- the collaborators, not the subject. `g4_move`
-- and `g4_wait_move` themselves are the real ones, unstubbed: a fake of either
-- would be this check grading its own mirror.
local function harness()
  local H = { queue = {}, resumed = 0, yielded = 0, killedParallel = false }
  local ow = {
    entities = {},
    npcMoveLocks = {},
    scriptMoves = {},
    map = { id = 'T01' },
    scriptMove = function(self, entity, dir, tiles, onDone)
      H.queue[#H.queue + 1] =
        { entity = entity, dir = dir, tiles = tiles, onDone = onDone, kind = 'walk' }
    end,
    scriptPause = function(self, entity, frames, onDone)
      H.queue[#H.queue + 1] =
        { entity = entity, frames = frames, onDone = onDone, kind = 'pause' }
    end,
    marchInPlace = function(self, entity, onDone)
      H.queue[#H.queue + 1] = { entity = entity, onDone = onDone, kind = 'march' }
    end,
  }
  H.ow = ow
  H.runner = {
    parallel = false,
    yield = function() H.yielded = H.yielded + 1 end,
    resume = function() H.resumed = H.resumed + 1 end,
  }
  H.ctx = { overworld = ow, runner = H.runner, save = {} }
  -- Finish the oldest queued entry, as the overworld's update would.
  H.finish = function()
    local e = table.remove(H.queue, 1)
    if e and e.onDone then e.onDone() end
    return e
  end
  return H
end

local function actor(localId, name)
  return { localId = localId, name = name, cellX = 0, cellY = 0,
           facing = 'down', stepFrames = 16 }
end

-- ACTION 4 IS A WALK. Taken from the movement table rather than assumed: 0 is
-- a FACE, and a list of faces queues nothing at all -- every assertion below
-- would then pass on a `g4_move` that did no work. The guard under this says
-- so out loud rather than leaving it to be noticed.
local WALK = 4
local WALK_DOWN = { { action = WALK, count = 1 } }

-- The movement table has to name action 0 as a walk for the rest of this to
-- mean anything; if it does not, these assertions would pass on a list that
-- queues nothing.
local Gen4Movement = require('src.import.Gen4Movement')
local a0 = Gen4Movement.action(WALK)
check(a0 and a0.kind == 'walk' and a0.dir,
      'action ' .. WALK .. ' must be a walk for this check to exercise '
      .. 'queueing, got ' .. tostring(a0 and a0.kind))

-- ================================= 1. an apply QUEUES and does not block
local H = harness()
local npc, player = actor(1, 'npc'), actor(255, 'player')
H.ow.entities = { npc, player }
H.ow.player = player
H.ow.npcByIndex = function() return npc end

Commands.g4_move(H.ctx, 1, WALK_DOWN)
check(#H.queue == 1, 'an applymovement must queue a step, got ' .. #H.queue)
check(H.yielded == 0,
      'and must NOT yield the script -- yielding here is what serialised the '
      .. 'two walks; yielded ' .. H.yielded .. ' time(s)')

-- ========================== 2. TWO ACTORS ARE IN FLIGHT AT THE SAME TIME
--
-- THE PROPERTY THE REPORT IS ABOUT. Two applies with no wait between them --
-- 862 sites on this cartridge -- must both be moving before either finishes.
local H2 = harness()
local a, b = actor(1, 'a'), actor(2, 'b')
H2.ow.entities = { a, b }
H2.ow.player = b
local byId = { [1] = a, [2] = b }
H2.ow.npcByIndex = function(_, i) return byId[i] end

Commands.g4_move(H2.ctx, 1, WALK_DOWN)
Commands.g4_move(H2.ctx, 2, WALK_DOWN)
local movers = {}
for _, e in ipairs(H2.queue) do movers[e.entity] = true end
local count = 0
for _ in pairs(movers) do count = count + 1 end
check(count == 2,
      'two applymovements issued back to back must put BOTH actors in flight '
      .. 'at once -- that is the escort, and 862 scenes do it; got '
      .. count .. ' actor(s) moving')
check(H2.yielded == 0, 'with neither of them having blocked the script')

-- ...and the first finishing must not be what starts the second.
check(#H2.queue == 2, 'both steps must be queued before either completes')

-- ================================ 3. waitmovement joins, and only then
local H3 = harness()
local c = actor(1, 'c')
H3.ow.entities = { c }
H3.ow.player = c
H3.ow.npcByIndex = function() return c end

Commands.g4_move(H3.ctx, 1, WALK_DOWN)
Commands.g4_wait_move(H3.ctx)
check(H3.yielded == 1,
      'waitmovement must yield while a movement is in flight, yielded '
      .. H3.yielded)
check(H3.resumed == 0, 'and must not resume before it lands')
H3.finish()
check(H3.resumed == 1,
      'the movement finishing must resume the script exactly once, got '
      .. H3.resumed)

-- A wait with NOTHING in flight must not park the script for ever. This is the
-- failure that would lock the player where they stand with nothing on screen,
-- which the overworld's own gate comments describe.
local H4 = harness()
local d = actor(1, 'd')
H4.ow.entities = { d } ; H4.ow.player = d
H4.ow.npcByIndex = function() return d end
Commands.g4_wait_move(H4.ctx)
check(H4.yielded == 0,
      'waitmovement with nothing in flight must return at once, not yield')

-- ...and a wait AFTER the movement already landed must not yield either.
local H5 = harness()
local e = actor(1, 'e')
H5.ow.entities = { e } ; H5.ow.player = e
H5.ow.npcByIndex = function() return e end
Commands.g4_move(H5.ctx, 1, WALK_DOWN)
H5.finish()
Commands.g4_wait_move(H5.ctx)
check(H5.yielded == 0, 'nor one whose movement has already finished')

-- TWO IN FLIGHT, ONE WAIT: the script must hold until BOTH land, or the scene
-- runs on while an actor is still walking -- the same class of fault as the
-- one being fixed, in the other direction.
local H6 = harness()
local f, g = actor(1, 'f'), actor(2, 'g')
H6.ow.entities = { f, g } ; H6.ow.player = g
local byId6 = { [1] = f, [2] = g }
H6.ow.npcByIndex = function(_, i) return byId6[i] end
Commands.g4_move(H6.ctx, 1, WALK_DOWN)
Commands.g4_move(H6.ctx, 2, WALK_DOWN)
Commands.g4_wait_move(H6.ctx)
check(H6.yielded == 1, 'one wait for two movements')
H6.finish()
check(H6.resumed == 0,
      'the first of two landing must NOT resume the script -- the other actor '
      .. 'is still walking')
H6.finish()
check(H6.resumed == 1, 'and the second must')

-- =================================== 4. a multi-step list stays in order
--
-- The chain is callback-driven now, so "the next step starts when the last one
-- finishes" is a property of the code rather than of the script runner.
local H7 = harness()
local h = actor(1, 'h')
H7.ow.entities = { h } ; H7.ow.player = h
H7.ow.npcByIndex = function() return h end
Commands.g4_move(H7.ctx, 1, { { action = WALK, count = 1 },
                              { action = WALK, count = 1 },
                              { action = WALK, count = 1 } })
check(#H7.queue == 1, 'only the FIRST step of a list may be queued at once, got '
      .. #H7.queue)
H7.finish()
check(#H7.queue == 1, 'finishing one step must queue the next')
H7.finish() ; H7.finish()
check(#H7.queue == 0, 'and the list must run out')
Commands.g4_wait_move(H7.ctx)
check(H7.yielded == 0, 'a finished list leaves nothing to wait for')

-- ================================= 5. nothing in the chain may yield
--
-- Every link after the first runs from the overworld's update, NOT from inside
-- the script coroutine. A `Commands.wait` or `Commands.emote` in there -- both
-- of which yield -- raises "attempt to yield from outside a coroutine" at a
-- point far from the line that caused it.
local src = io.open('src/script/Gen4Commands.lua'):read('a')
local body = src:match('function Commands%.g4_move%(ctx, id, steps%).-\nend\r?\n')
check(body, 'g4_move must be findable')
if body then
  -- COMMENT LINES STRIPPED FIRST. This assertion failed on its own
  -- subject: the rewritten `g4_move` explains in prose that it used to go
  -- through `walkEntity`, and a scan of the raw text cannot tell the
  -- explanation from the call. Same shape as the `goto` assertion that matched
  -- the comment saying why there is no `goto`.
  local code = {}
  for line in body:gmatch('[^\n]*') do
    if not line:match('^%s*%-%-') then code[#code + 1] = line end
  end
  code = table.concat(code, '\n')
  check(not code:find('Commands.wait(', 1, true),
        'the chain must not call Commands.wait -- it yields')
  check(not code:find('Commands.emote(', 1, true),
        'nor Commands.emote -- it yields too; the bubble is armed directly')
  check(not code:find('walkEntity', 1, true),
        'nor walkEntity, which yields per step and is what serialised the scene')
  check(not code:find('runner:yield', 1, true), 'and must not yield itself')
  check(code:find('ow:scriptPause', 1, true),
        'a pause must ride the queue so the other actor keeps moving through it')
  check(code:find('Commands.claimMove', 1, true),
        'and the move lock must still be taken -- it came from walkEntity, '
        .. 'which is no longer in the path')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
