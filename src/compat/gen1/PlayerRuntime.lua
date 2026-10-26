-- One compatibility call scope inside the native overworld player phase.
-- An idle tick is deferred: free-body wrappers may then submit their one
-- cell arrival without advancing animation, bobbing or events a second time.
local Session = require('src.compat.gen1.NativeSession')
local M = {}
function M.new()
  local active
  local records = setmetatable({},{__mode='k'})
  local runtime = {}
  function runtime:scope() return active end
  function runtime:record(player)
    local record=records[player]
    if not record then record={stepSerial=0};records[player]=record end
    return record
  end
  function runtime:tick(game)
    local c = active
    if not c or (game and game ~= c.game and game ~= c.facade) then
      return nil, 'player ticks belong to the native fixed-step phase'
    end
    if c.advanced then return false end
    local _, world, player = Session.resolve(c.game)
    if world ~= c.world or player ~= c.player then return false end
    if not c.finishing and not player.moving then return false end
    c.advanced = true
    local x,y=player.cellX,player.cellY
    if not player.moving and player.compatWalkInPlace and not (player.bumpFrames and player.bumpFrames>0) then
      player.animClock=(player.animClock or 0)+1
    end
    local stepped = player:update()
    if stepped then
      local record=self:record(player)
      record.prevCellX,record.prevCellY=x,y;record.stepSerial=record.stepSerial+1
    end
    c.world:finishPlayerStep(stepped, false)
    return stepped
  end
  function runtime:input(input)
    local c = active
    if not c or c.inputPolled or not Session.acceptsInput(c.game,c.world,c.player) then return end
    c.inputPolled = true
    local previous = c.game.input
    c.game.input = input or previous
    local ok, result = xpcall(function() return c.world:handleInput() end, debug.traceback)
    c.game.input = previous
    if not ok then error(result,0) end
    return result
  end
  function runtime:run(game, world, facade, input, update)
    assert(not active, 'nested native player phase')
    local c = {game=game,world=world,player=world.player,facade=facade}
    active = c
    local ok, why = xpcall(function()
      update(facade,input)
      if active ~= c then return end -- teardown during a callback retires the scope
      c.finishing = true
      self:tick(game)
    end, debug.traceback)
    active = nil
    if not ok then error(why,0) end
  end
  function runtime:release() active = nil;records=setmetatable({},{__mode='k'})end
  return runtime
end
return M
