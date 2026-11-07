-- BLACK / WHITE: THE BATTLE SUBWAY'S WIRELESS MULTI TRAIN, with a friend.
--
-- Two players against the Subway's trainer pairs, car after car: a co-op
-- 4-player multi battle (src/online/MultiBattle.lua) whose seats 1 and 3 are
-- the computer.  Everything the train counts goes through the Subway's own
-- code (src/script/Gen5BattleSubway.lua) on BOTH machines, on the friend
-- line (BSWAY_MODE 3, or 8 for the Super line), so each player's save keeps
-- its own streak, record and Battle Points:
--
--   0x158 create (members: the two chosen)   0x167 a train begun
--   0x13C the train's fourteen trainers -- the LEADER's draw, sent across
--   0x133 the car's pair, with their teams -- the leader's, sent across
--   0x135 the battle -- here the multi battle on the link
--   0x165 a car won (car + 1, streak + 1)    0x130 lost
--   0x139 the train's BP (each player's own purse)   0x131 the train won
--
-- The cartridge runs this from the Multi platform's receptionist and the car's
-- own scripts, with the two DSes in sync (functions 0x190-0x1A0,
-- "Communicating...").  The port keeps its own messages (sw_*) in place of those
-- functions and does not run those scripts' comm branches: both players stand
-- on the car (Z075, the friend beside you) from the first battle to the last,
-- with no walk-in and no trainers walking up (a stated divergence).  Two Pokemon
-- each at level 50 (ov21 0x021CA270: MEMBERS[3] = 2), healed before every car
-- (the Subway heals between battles).
--
-- REST.  Between cars the leader may stop: KEEP GOING, else REST (each save
-- keeps the train, in save.gen5Subway.friendRest: the counter's own "rested"
-- bit is for the one-player scripts, which can't carry a friend on) or RETIRE.
-- Next time at the counter with a friend, if both players have that same train
-- rested (the same line and car, the same trainers), it carries on; otherwise
-- a new train starts and the rest is dropped.
--
--   SubwayMulti.run(game, session, opts, onDone)
--     session  as MultiLobby.open (nil: host code / code entry)
--     opts     role "host" | "join", super (mode 8), trains (stop after n
--              trains; nil = ask the leader after each), autoTeam, seed,
--              restAfter (tests: rest after this many cars, no question),
--              noCar (tests: stay on the map)
--     onDone(summary)  { result = "lost"|"retired"|"rested"|"cancelled"|"failed",
--                        streak, bp, trains, cars, why, resumed }

local BattleRules = require("src.online.BattleRules")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local SubwayMulti = {}

SubwayMulti.COMM_MULTI, SubwayMulti.S_COMM_MULTI = 3, 8

local function Sub() return require("src.script.Gen5BattleSubway") end

-- the car, on the field under the battles: the zone, where the player stands,
-- and the friend beside them
SubwayMulti.CAR = { map = "Z075", x = 7, y = 4 }
SubwayMulti.CAR_HOLD = 1.5   -- seconds on the car before each pair's battle

local function ownMap(game)
  local ow = game and game.overworld
  return ow and ow.map and ow.player and ow or nil
end

local function pack(list)
  local Protocol = require("src.link.Protocol")
  return Protocol.packParty(list or {})
end

function SubwayMulti.run(game, session, opts, onDone)
  opts = opts or {}
  local mode = opts.super and SubwayMulti.S_COMM_MULTI or SubwayMulti.COMM_MULTI
  local ctx = { game = game, save = game.save }
  local S = Sub()
  local train = { cars = 0, trains = 0, battles = 0 }
  local lobby
  local finished = false

  -- on / off the car
  local car = {}
  local function friendBeside(ow)
    local okP, Presence = pcall(require, "src.online.world.Presence")
    if not okP or not (car.friendName and ow.player) then return end
    local p = ow.player
    local g = car.ghost
    if not (g and g.ow == ow and g.mapId == ow.map.id) then
      local member = { name = car.friendName, look = car.friendLook,
                       pos = { m = "@car", x = p.cellX + 1, y = p.cellY, f = p.facing, d = 16, mv = "walk" } }
      g = Presence.makeRoomGhost(game, ow, 991, member)
      if not g then return end
      g.mapId = ow.map.id
      car.ghost = g
    end
    ow.entities = ow.entities or {}
    for _, e in ipairs(ow.entities) do if e == g.npc then return end end
    table.insert(ow.entities, g.npc)
  end
  local function boardCar()
    local ow = ownMap(game)
    if opts.noCar or car.back or not ow or not (game.data.maps and game.data.maps[SubwayMulti.CAR.map]) then return end
    local p = ow.player
    car.back = { map = ow.map.id, x = p.cellX, y = p.cellY, facing = p.facing }
    local okS, err = pcall(ow.setMap, ow, SubwayMulti.CAR.map, SubwayMulti.CAR.x, SubwayMulti.CAR.y, "right")
    if not okS then
      Logger.warn("subway multi: can't show the car: %s", tostring(err))
      car.back = nil
      return
    end
    friendBeside(ow)
  end
  local function leaveCar()
    local back = car.back
    car.back, car.ghost = nil, nil
    local ow = ownMap(game)
    if back and ow then
      local okS, err = pcall(ow.setMap, ow, back.map, back.x, back.y, back.facing)
      if not okS then Logger.warn("subway multi: can't leave the car: %s", tostring(err)) end
    end
  end

  local function finish(result, why)
    if finished then return end
    finished = true
    leaveCar()
    local s = S.score(game.save)
    local summary = { result = result, why = why, mode = mode,
                      streak = tonumber(s.streak[mode + 1]) or 0, best = tonumber(s.best[mode + 1]) or 0,
                      bp = S.bp(game.save), trains = train.trains, cars = train.cars,
                      resumed = train.resumed }
    Logger.info("subway multi: done (%s) streak %d, %d BP, %d trains", tostring(result), summary.streak,
                summary.bp, train.trains)
    game.gen5Subway = nil
    if lobby then
      lobby.keep = false
      lobby:done(result, why)
    end
    if onDone then onDone(summary) end
  end

  -- the challenge's work, on this machine's save
  local function fillMembers(w, info, mySeat)
    -- the members entered: this player's own two (their party slots)
    w.count = S.MEMBERS[mode] or 2
    local mine = info.seats[mySeat]
    w.species, w.items = {}, {}
    for i, p in ipairs(mine and mine.party or {}) do
      w.species[i] = tonumber(p.species) or 0
      w.items[i] = tonumber(p.item) or 0
    end
  end

  local function newWork(info, mySeat)
    local w = S.create(ctx, 0, mode)
    fillMembers(w, info, mySeat)
    S.W[0x167](ctx, w)
    return w
  end

  -- the train this save rested (read off before the new work cleared it)
  local rested
  local function resumeWork(info)
    local p = S.score(game.save).play
    p.mode, p.car, p.trainers = mode, rested.car, rested.trainers
    S.score(game.save).friendRest = nil
    local w = S.create(ctx, 1, mode)
    fillMembers(w, info, lobby.seat)
    return w
  end

  local function playerSeats(info)
    return { [0] = info.seats[0], [2] = info.seats[2] }
  end

  local isHost
  local w
  local pendingCar      -- (guest) the car message, once it arrives
  local waiting = false

  local function after(won)
    if won then
      S.W[0x165](ctx, w)
      train.cars = train.cars + 1
      if S.W[0x12F](ctx, w) == 1 then
        -- the train is cleared: the BP, then the train counted
        local bp = S.W[0x139](ctx, w)
        S.W[0x131](ctx, w)
        train.trains = train.trains + 1
        train.lastBp = bp
        Logger.info("subway multi: train %d cleared, %d BP", train.trains, bp)
        -- 0x14D: the next train starts uncleared, no boss
        S.W[0x14D](ctx, w)
        local more = not opts.trains or train.trains < opts.trains
        return more and "train" or "retire"
      end
      return "car"
    end
    S.W[0x130](ctx, w)
    return "lost"
  end

  -- one car: build (leader) or receive (friend) the pair, then battle
  local function runCar(info, msg)
    -- a moment on the car first, the friend beside you
    if not msg.held then
      boardCar()
      if car.back then
        msg.held = true
        train.hold = { t = SubwayMulti.CAR_HOLD, info = info, msg = msg }
        return
      end
    end
    train.battles = train.battles + 1
    -- the leader's word that this is the two players' rested train
    if msg.resume and not isHost and not train.resumed then
      train.resumed = true
      w = resumeWork(info)
    end
    w.trainers = msg.trainers or w.trainers
    -- a new train: whatever was rested is gone
    if not train.resumed then S.score(game.save).friendRest = nil end
    local seats = playerSeats(info)
    seats[1] = { name = msg.foes[1].name, party = msg.foes[1].party, ai = true }
    seats[3] = { name = msg.foes[2].name, party = msg.foes[2].party, ai = true }
    local battle, why = lobby:battleOn(seats, tonumber(msg.seed) or 1, function(result, b)
      -- the leader's word on the car (both machines decided the same battle)
      local won = result == "win"
      if isHost then
        lobby.net:broadcast({ type = "sw_result", car = msg.car, won = won })
      end
      local nextStep = after(won)
      Logger.info("subway multi: car %d %s -> %s", (tonumber(msg.car) or 0) + 1, tostring(result), nextStep)
      for _, item in ipairs(b.mbOther or {}) do
        if item.msg.type == "sw_car" then pendingCar = item.msg end
        if item.msg.type == "sw_end" then
          waiting = "end"
          train.endReason = item.msg.reason
        end
      end
      if nextStep == "lost" then return finish("lost") end
      if nextStep == "retire" then
        if isHost then lobby.net:broadcast({ type = "sw_end", reason = "retire" }) end
        return finish("retired")
      end
      if nextStep == "train" then
        if isHost then
          S.chooseTrainers(ctx, w)
          -- the leader decides whether the two ride on (opts.trains: a
          -- fixed number of trains, no question)
          if not opts.trains then waiting = "ask" return end
        end
      elseif nextStep == "car" and isHost then
        -- between cars: go on, rest or retire
        if opts.restAfter and train.cars >= opts.restAfter then
          waiting = "rest"
          return
        end
        if not opts.trains and not opts.autoTeam then waiting = "askCar" return end
      end
      waiting = waiting ~= "end" and waiting ~= "rest" and true or waiting
    end, tonumber(msg.car))
    if not battle then return finish("failed", why) end
  end

  local function hostCar(info)
    S.buildOpponents(ctx, w)
    local a, b = w.opponents[1], w.opponents[2]
    if not (a and b and #a.party > 0 and #b.party > 0) then return finish("failed", "no subway trainers") end
    local n = tonumber(S.score(game.save).play.car) or 0
    local msg = { type = "sw_car", car = train.battles, carIndex = n, trainers = w.trainers,
                  resume = train.resumed or nil,
                  seed = math.floor((os.time() % 100000) + train.battles * 7919 + (opts.seed or 0)) + 1,
                  foes = { { name = a.name, id = a.id, party = pack(a.party) },
                           { name = b.name, id = b.id, party = pack(b.party) } } }
    lobby.net:broadcast(msg)
    runCar(info, msg)
  end

  -- the pump between cars, from the lobby's own update (it is the top
  -- state again once a battle closes)
  local function rest()
    -- this save keeps the train; written now, as the cartridge's Rest
    local s = S.score(game.save)
    local trainers = {}
    for i = 1, 14 do trainers[i] = w.trainers[i] end
    s.friendRest = { mode = mode, car = tonumber(s.play.car) or 0, trainers = trainers }
    if game.writeSave then pcall(game.writeSave, game) end
    return finish("rested")
  end

  -- does this save hold a rested train of this line?
  local function restedHere()
    local r = S.score(game.save).friendRest
    if type(r) == "table" and tonumber(r.mode) == mode then
      return { car = tonumber(r.car) or 0, trainers = r.trainers }
    end
    return nil
  end

  local function sameRest(a, b)
    if not (a and b and a.car == b.car) then return false end
    for i = 1, 14 do
      if (a.trainers or {})[i] ~= (b.trainers or {})[i] then return false end
    end
    return true
  end

  local function tick()
    if finished or not w then return end
    if not waiting then return end
    if isHost then
      lobby.net:update()
      for _, item in ipairs(lobby.net:poll()) do
        if item.msg.type == "mb_gone" then return finish("failed", Strings("The link was\nlost.")) end
        if item.msg.type == "sw_hello" then train.peerHello = item.msg end
      end
      if waiting == "asking" then return end
      if waiting == "hello" then
        -- the friend's rested train, against this one
        local h = train.peerHello
        if not h then return end
        waiting = false
        if rested and h.rested and sameRest(rested, h.rested) then
          train.resumed = true
          w = resumeWork(lobby.startInfo)
        else
          S.chooseTrainers(ctx, w)
        end
        return hostCar(lobby.startInfo)
      end
      if waiting == "rest" then
        lobby.net:broadcast({ type = "sw_end", reason = "rest" })
        return rest()
      end
      if waiting == "askCar" then
        waiting = "asking"
        local TextBox = require("src.render.TextBox")
        local ChoiceBox = require("src.ui.ChoiceBox")
        game.stack:push(TextBox.new(game, Strings("Keep going to the\nnext car?"), function()
          game.stack:push(ChoiceBox.new(game, function(yes)
            if yes then
              waiting = true
              return
            end
            game.stack:push(TextBox.new(game, Strings("Rest, and carry on\nanother time?"), function()
              game.stack:push(ChoiceBox.new(game, function(restNow)
                waiting = restNow and "rest" or "retire"
              end))
            end))
          end))
        end))
        return
      end
      if waiting == "retire" then
        lobby.net:broadcast({ type = "sw_end", reason = "quit" })
        S.W[0x130](ctx, w)
        return finish("retired")
      end
      if waiting == "ask" then
        waiting = "asking"
        local TextBox = require("src.render.TextBox")
        local ChoiceBox = require("src.ui.ChoiceBox")
        game.stack:push(TextBox.new(game, Strings("The train is cleared!\nRide on with your\nfriend?"), function()
          game.stack:push(ChoiceBox.new(game, function(yes)
            if yes then
              waiting = true
            else
              lobby.net:broadcast({ type = "sw_end", reason = "retire" })
              finish("retired")
            end
          end))
        end))
        return
      end
      waiting = false
      return hostCar(lobby.startInfo)
    end
    lobby.net:update()
    for _, item in ipairs(lobby.net:poll()) do
      local m = item.msg
      if m.type == "sw_car" then pendingCar = m
      elseif m.type == "sw_end" then
        waiting = "end"
        train.endReason = m.reason
      elseif m.type == "mb_gone" and waiting ~= "end" then
        -- (the leader closes right after its last word: that is not a lost link)
        return finish("failed", Strings("The link was\nlost."))
      end
    end
    if waiting == "end" then
      if train.endReason == "rest" then return rest() end
      if train.endReason == "quit" then S.W[0x130](ctx, w) end
      return finish("retired")
    end
    if pendingCar then
      local m = pendingCar
      pendingCar, waiting = nil, false
      runCar(lobby.startInfo, m)
    end
  end

  local o = {}
  for k, v in pairs(opts) do o[k] = v end
  o.coop = { seats = {} }
  o.need = 2
  o.rules = BattleRules.multi(5, "subway")
  o.title = "MULTI TRAIN"
  o.onReady = function(lb, info)
    lobby = lb
    isHost = lb.isHost
    -- (read before the new work clears it)
    rested = restedHere()
    -- the friend's name and sprite, for the car
    local friend = info.seats[lb.seat == 0 and 2 or 0]
    car.friendName = friend and friend.name
    w = newWork(info, lb.seat)
    if isHost then
      waiting = "hello"
    else
      lb.net:send({ type = "sw_hello", rested = rested })
      waiting = true
    end
    -- the lobby's update drives the train between cars
    lb.isOpaque = false
    local baseDraw = lb.draw
    lb.draw = function(self)
      if self.stage ~= "after" then return baseDraw(self) end
    end
    local baseUpdate = lb.update
    lb.update = function(self, dt)
      if self:popIfDone() then return end
      if self.stage == "after" then
        local hold = train.hold
        if hold then
          hold.t = hold.t - (dt or 1 / 60)
          if hold.t <= 0 then
            train.hold = nil
            runCar(hold.info, hold.msg)
          end
          return
        end
        tick()
        return
      end
      return baseUpdate(self, dt)
    end
  end
  lobby = require("src.online.MultiLobby").open(game, session, o, function(result, why)
    if not finished and (result == "cancelled" or result == "failed") then
      finished = true
      if onDone then onDone({ result = result, why = why, mode = mode, bp = S.bp(game.save) }) end
    end
  end)
  return lobby
end

return SubwayMulti
