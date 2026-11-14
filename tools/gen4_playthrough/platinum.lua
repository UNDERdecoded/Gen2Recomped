-- PLATINUM'S STORY, AS BEATS (tools/gen4_playthrough/runner.lua).
--
-- Each beat names what the cartridge's own scripts must have done when it is
-- over -- the vars and flags pokeplatinum's scripts set -- so a beat fails
-- exactly where the port stops agreeing with the game. Run:
--
--   INSTALL=G:/Gen2Recomped/platinum VERSION=platinum MAP=T01R0202 X=4 Y=6 \
--     FACING=up PLAYTHROUGH=platinum TICKS=200000 love tools/gen4_hgss_overworld_harness

local B = {}

-- the bedroom's frame script: the TV's "Let's ask Prof. Rowan" notice
B[#B + 1] = { name = "bedroom",
  steps = { { "mash", 60 } },
  expect = function(r) return r:var(0x40F9) == 1 end, why = "0x40F9 = 1 (bedroom scene)" }

-- downstairs: Mom's scene (T01R0201 frame row 0x40A4 == 0 -> S0065)
B[#B + 1] = { name = "mom downstairs",
  steps = { { "warpto", "T01R0201" } },
  expect = function(r) return r:var(0x40A4) >= 1 end, why = "0x40A4 >= 1 (Mom's scene)" }

-- Barry's room (T01R0102 frame row 0x40A3 == 0 -> S000F): he rushes off to
-- the lake; flag 234, 0x40A3 = 1, 0x4070 = 2
B[#B + 1] = { name = "barry's room",
  steps = { { "warpto", "T01" }, { "warpto", "T01R0101" }, { "warpto", "T01R0102" } },
  expect = function(r) return r:var(0x40A3) == 1 and r:flag(234) end, why = "0x40A3 = 1, flag 234" }

-- Route 201: Barry stops the player (coord 1, 0x4086 == 0), then the lake
-- scene with Rowan and Dawn (S03DF: 0x4086 = 1)
B[#B + 1] = { name = "route 201 to the lake",
  steps = { { "warpto", "T01R0101" }, { "warpto", "T01" },
            { "teleport", "R201", 15, 28, "up" }, { "activecoord" },
            { "until", function(r) return r:var(0x4086) >= 1 end, 20000 } },
  expect = function(r) return r:var(0x4086) >= 1 end, why = "0x4086 >= 1 (the lake scene)" }

-- the briefcase (Route 201 person 12, S042F): the starter, the battle with Barry,
-- home to Mom (S0619: 0x4086 = 2, 0x40A4 = 3, warp), the Running Shoes
-- (T01R0201 frame row 0x40A4 == 3 -> S017D: 0x40A4 = 4)
B[#B + 1] = { name = "starter and running shoes",
  steps = { { "talkto", "briefcase" },
            { "until", function(r) return r:var(0x40A4) >= 4 end, 30000 } },
  expect = function(r) return #r:party() >= 1 and r:var(0x4086) >= 2 and r:var(0x40A4) >= 4 end,
  why = "a starter, 0x4086 >= 2, 0x40A4 >= 4 (shoes)" }

-- ---------------------------------------------------------------------------
-- THE REST OF THE STORY. Vars and flags are pokeplatinum's
-- (generated/vars_flags.txt, numbered as the enum counts them); scripts are
-- res/field/scripts/scripts_<map>.s and their init tables scripts_init_<map>.s.
-- Outdoor cells are local to the map (pret's global x/z minus the map's
-- chunk origin in matrix 0). Between story points the player is teleported;
-- the scenes themselves (coord triggers, frame scripts, talks) are real.

local function flag(id) return function(r) return r:flag(id) end end
local function varGe(id, v) return function(r) return r:var(id) >= v end end
local function badges(r)
  local n = 0
  for _, v in pairs((r.game.save or {}).badges or {}) do if v then n = n + 1 end end
  return n
end

-- RENEGADE PLATINUM (VERSION=renegadeplatinum) edits the story in places;
-- each beat that differs says so where it does. Retail's path is untouched.
local renegade = os.getenv("VERSION") == "renegadeplatinum"

-- A CHEAT, said as one (heartgold.lua's): the lead is rebuilt at level 75,
-- healed, with `move` first, so the runner's A-mashing (the first move, every
-- turn) wins the story battles. The story is under test here, not the battles.
--
-- RENEGADE turns several story fights into DOUBLE battles that refuse a
-- party of one (Floaroma Meadow's grunts: `getpartycount`, "you only have
-- one Pokémon?", pushed back), so there the cheat also keeps a second able
-- Pokémon behind the lead -- a copy of it -- when the party has only one.
-- And its trainers are far stronger (Maylene's gym: full level-35 teams with
-- coverage, no heal between the three fights), so there the lead is the
-- Mewtwo at 100 that retail only needs from Canalave on.
local function trainUpWith(move, level, species)
  if renegade then species, level = species or 150, math.max(level or 75, 100) end
  return function(r)
    local party = r:party()
    local lead = party[1]
    if not lead then return end
    local Pokemon = require("src.pokemon.Pokemon")
    local mon = Pokemon.new(r.game.data, species or lead.species, level or 75)
    mon.nickname, mon.otName, mon.otId = lead.nickname, lead.otName, lead.otId
    mon.moves = mon.moves or {}
    table.insert(mon.moves, 1, { id = move or 94, pp = 64 })
    while #mon.moves > 4 do table.remove(mon.moves) end
    party[1] = mon
    -- (rebuilt each time with the same first move, so a double battle's
    -- partner does not keep the last beat's -- Surf into Dry Skin)
    if renegade and (#party < 2 or party[2].species == mon.species) then
      local second = Pokemon.new(r.game.data, species or lead.species, level or 75)
      second.otName, second.otId = lead.otName, lead.otId
      second.moves = second.moves or {}
      table.insert(second.moves, 1, { id = move or 94, pp = 64 })
      while #second.moves > 4 do table.remove(second.moves) end
      party[2] = second
    end
  end
end
-- Surf by default: it hits both foes of a double battle (Floaroma Meadow's
-- grunts), and nothing early is immune to it (Stunky is to Psychic)
local trainUp = trainUpWith(57)
-- ...and from Canalave on the starter at 75 is not enough (Barry's five beat
-- a lone Turtwig at 75 with Surf): a Mewtwo at 100 leads instead
local function strong(move) return trainUpWith(move or 57, 100, 150) end
-- Psychic 94, Surf 57, Flamethrower 53, Crunch 242, Thunderbolt 85,
-- Earthquake 89, Ice Beam 58, Shadow Ball 247

-- ...and SIX DEEP, for the double battles (Spear Pillar's grunts need two
-- able Pokémon) and the League: six Mewtwo at 100 leading with `move`
local function fullTeam(move)
  return function(r)
    local party = r:party()
    local lead = party[1]
    local Pokemon = require("src.pokemon.Pokemon")
    for i = 1, 6 do
      local mon = Pokemon.new(r.game.data, 150, 100)
      if lead then mon.otName, mon.otId = lead.otName, lead.otId end
      mon.moves = mon.moves or {}
      table.insert(mon.moves, 1, { id = move, pp = 64 })
      while #mon.moves > 4 do table.remove(mon.moves) end
      party[i] = mon
    end
  end
end

-- HMs the story would have taught by now, given to the lead behind the move
-- its battles use (slot 1 is never touched): { [slot] = move id }
local function hmMoves(list)
  return function(r)
    local lead = r:party()[1]
    if not lead then return end
    lead.moves = lead.moves or {}
    for slot, id in pairs(list) do lead.moves[slot] = { id = id, pp = 20 } end
  end
end

-- WALKING A GYM BY A SEARCHED ROUTE (Canalave, Sunyshore, Victory Road): the
-- step kinds below, installed on the runner instance by a "do" step so the
-- runner itself is untouched.
--   { "route", parts }  one step at a time, each done once the player stands
--       on its cell and all is still (a ride, a battle on the way waited
--       out). `parts` are run-length strings ("U7L8": up 7, left 8) and
--       explicit { dir, x, z } steps for a step that ends somewhere else (a
--       platform ride). A trainer who walked up and stays where the battle
--       left them is gone round on the planner.
--   { "act", dir, x, z }   face dir, A (a field move's YES), until carried to
--       (x, z): Rock Climb, Surf, Waterfall
--   { "smash", dir, x, z } the rock at (x, z) broken (A, YES)
--   { "push", dir, x, z }  the boulder ahead pushed on to (x, z), Strength
--       called up first when it is not active
local ROUTE_DIRS = { U = { "up", 0, -1 }, D = { "down", 0, 1 }, L = { "left", -1, 0 }, R = { "right", 1, 0 } }
local function expandRoute(parts, x, z)
  local out = {}
  for _, p in ipairs(parts) do
    if type(p) == "table" then
      out[#out + 1] = p
      x, z = p[2], p[3]
    else
      for letter, n in p:gmatch("([UDLR])(%d*)") do
        local d = ROUTE_DIRS[letter]
        for _ = 1, tonumber(n) or 1 do
          x, z = x + d[2], z + d[3]
          out[#out + 1] = { d[1], x, z }
        end
      end
    end
  end
  return out
end
local function routeSteps() return { "do", function(r)
  if r.ptRoutes then return end
  r.ptRoutes = true
  local orig = r.runStep
  local function objAt(self, x, z)
    for _, n in ipairs(self.ow.npcs or {}) do
      if n.cellX == x and n.cellY == z and not n.hidden then return n end
    end
  end
  local function waitBusy(self)
    local busy, why = self:busy()
    if not busy then return false end
    -- let go once a step is under way: a key still held when it lands would
    -- start the next one before the ride / battle could
    self.held = nil
    if why ~= "moving" and why ~= "moves" then
      local _, key = self:busyInput()
      self.key = key
    end
    return true
  end
  r.runStep = function(self, s)
    local kind = s[1]
    if kind == "route" then
      if not s.list then s.list, s.i = expandRoute(s[2], self:pos()), 1 end
      local e = s.list[s.i]
      if not e then s.list = nil return true end
      if waitBusy(self) then return false end
      local x, y = self:pos()
      if x == e[2] and y == e[3] then
        s.i, s.t = s.i + 1, 0
        self.held = nil
        if not s.list[s.i] then s.list = nil return true end
        return false
      end
      s.t = (s.t or 0) + 1
      if s.t > 4000 then
        return nil, ("route step %d (%s to %d,%d) never arrived; at %d,%d"):format(s.i, e[1], e[2], e[3], x, y)
      end
      if s.t > 90 then
        local o = objAt(self, e[2], e[3])
        while o and not o.passable and s.list[s.i + 1] do
          s.i = s.i + 1
          e = s.list[s.i]
          o = objAt(self, e[2], e[3])
        end
        if self:walkTo(e[2], e[3]) == true then s.t = 0 end
        return false
      end
      self.held = e[1]
      return false
    end
    if kind == "act" or kind == "smash" or kind == "push" then
      if waitBusy(self) then return false end
      local x, y = self:pos()
      if kind == "act" and x == s[3] and y == s[4] then self.held = nil s.t = nil return true end
      if kind == "smash" and not objAt(self, s[3], s[4]) then self.held = nil s.t = nil return true end
      if kind == "push" then
        local o = objAt(self, s[3], s[4])
        if o and not o.moving then self.held = nil s.t = nil return true end
      end
      s.t = (s.t or 0) + 1
      if s.t > 6000 then return nil, ("%s %s at %d,%d never happened"):format(kind, s[2], s[3], s[4]) end
      if self.ow.player.facing ~= s[2] then self.held = s[2] return false end
      if kind == "push" and self.ow.strengthActive then self.held = s[2] return false end
      self.held = nil
      if (s.t % 20) == 0 then self.key = "a" end
      return false
    end
    return orig(self, s)
  end
end } end

-- the SET battle style for a beat (a player's own option: no "will you
-- switch?" offer between the gym's battles), and back after it
local function battleStyle(style) return { "do", function(r)
  local o = r.game.save.options or {}
  r.game.save.options = o
  if style then r.ptStyle = o.battleStyle o.battleStyle = style
  else o.battleStyle = r.ptStyle end
end } end

-- SANDGEM (scripts_sandgem_town.s): the counterpart's coord trigger at the
-- west edge (x 4, y 10..15 while VAR_SANDGEM_TOWN_STATE 0x4071 == 0) leads
-- the player into the lab (0x4071 = 1, Warp); the lab's frame table
-- (0x40A6 == 0) is Rowan's Pokédex scene: FLAG_HAS_POKEDEX 0x90,
-- VAR_SANDGEM_TOWN_LAB_STATE 0x40A6 = 1
B[#B + 1] = { name = "sandgem: rowan's pokedex",
  steps = { { "teleport", "T02", 7, 13, "left" }, { "activecoord" },
            { "until", function(r) return r:flag(0x90) and r:var(0x40A6) >= 1 end, 40000 } },
  expect = function(r) return r:flag(0x90) and r:var(0x40A6) >= 1 and r:var(0x4071) >= 1 end,
  why = "flag 0x90 (Pokédex), 0x40A6 >= 1, 0x4071 >= 1", expectBudget = 8000 }

-- out of the lab: Sandgem's frame table (0x4071 == 1, OnFrame_ExitLab) is
-- the counterpart's tour of the Pokémon Center and Mart: 0x4071 = 2
B[#B + 1] = { name = "sandgem: the tour",
  steps = { { "warpto", "T02" }, { "until", varGe(0x4071, 2), 30000 } },
  expect = varGe(0x4071, 2), why = "0x4071 >= 2 (the tour)" }

-- home (scripts_twinleaf_town_player_house_1f.s, Mom = person 0): with the
-- Pokédex she gives the Journal, Barry's mom comes in with the Parcel
-- (FLAG_RECEIVED_PARCEL 0x8F)
B[#B + 1] = { name = "the parcel",
  steps = { { "teleport", "T01R0201", 5, 6, "down" }, { "talk", 0 },
            { "until", flag(0x8F), 30000 } },
  expect = flag(0x8F), why = "flag 0x8F (Parcel)", expectBudget = 8000 }

-- Route 202 (coord 1, x 20 y 25..29 while VAR_ROUTE_202_STATE 0x4087 == 0,
-- FLAG_RECEIVED_PARCEL set): the catching tutorial, the Poké Balls (0x4087 = 1)
--
-- RENEGADE PLATINUM replaces the demo (`startcatchingtutorial`) with a REAL
-- trainer battle against the counterpart (trainers 928..933, level 9 with a
-- level-5 starter to meet it), so a lone starter loses and blacks out. The
-- lead is trained up first there, as every later beat does; retail keeps the
-- demo and no cheat.
local tutorialSteps = { { "teleport", "R202", 21, 27, "left" }, { "activecoord" },
                        { "until", varGe(0x4087, 1), 30000 } }
if renegade then table.insert(tutorialSteps, 1, { "do", trainUpWith(57) }) end
B[#B + 1] = { name = "route 202 catching tutorial",
  steps = tutorialSteps,
  expect = varGe(0x4087, 1), why = "0x4087 >= 1 (the tutorial)", expectBudget = 8000 }

-- JUBILIFE (scripts_jubilife_city.s). Coord 1 (45..48,60 while
-- VAR_JUBILIFE_CITY_STATE 0x4077 == 0): the counterpart meets the player and
-- Looker, 0x4077 = 1
B[#B + 1] = { name = "jubilife: looker",
  steps = { { "teleport", "C01", 46, 62, "up" }, { "activecoord" },
            { "until", varGe(0x4077, 1), 30000 } },
  expect = varGe(0x4077, 1), why = "0x4077 >= 1", expectBudget = 8000 }

-- the Trainers' School (C01R0701): Barry (person 1) takes the Parcel, gives
-- the Town Map: FLAG_TALKED_TO_TRAINERS_SCHOOL_RIVAL 0xF1,
-- VAR_POKETCH_CAMPAIGN_STATE 0x40E7 = 1 (the clowns appear)
B[#B + 1] = { name = "jubilife: the trainers' school",
  steps = { { "teleport", "C01", 40, 42, "up" }, { "warpto", "C01R0701" }, { "talk", 1 },
            { "until", flag(0xF1), 30000 } },
  expect = function(r) return r:flag(0xF1) and r:var(0x40E7) >= 1 end, why = "flag 0xF1, 0x40E7 >= 1",
  expectBudget = 8000 }

-- the Pokétch campaign: coord 5 (44..48,40 while 0x40E7 == 1) is the
-- president's pitch (0x40E7 = 2); the three clowns' quizzes (persons 24, 25,
-- 27; every answer is YES) give the coupons (0xED, 0xEE, 0xEF); the president
-- (person 23) then gives the Pokétch: FLAG_RECEIVED_POKETCH 0xF3, 0x4077 = 2
-- A WANDERER is talked to as a player would: walk up, press A, and when it
-- has wandered off in the meantime (the A fell on nothing -- no script ran),
-- walk up again. Up to `tries` times, then the flag must be set.
local function talkUntil(steps, id, done, tries)
  for _ = 1, tries or 6 do
    steps[#steps + 1] = { "talk", id, retarget = true, avoidTriggers = true, unless = done }
    steps[#steps + 1] = { "until", function(r)
      return done(r) or (r.stepT > 90 and not r:busy())
    end, 20000 }
    steps[#steps + 1] = { "do", function() end }
  end
  steps[#steps + 1] = { "until", done, 20000 }
end
local poketch = { { "warpto", "C01" }, { "walkto", 44, 42 },
                  -- by number: `activecoord` takes the first armed trigger in
                  -- the list, which is Looker's strip (coord 3, 0x4077 == 1) --
                  -- his "have you not obtained a Pokétch?" pushes back forever
                  { "coord", 5 }, { "until", varGe(0x40E7, 2), 20000 } }
-- RENEGADE PLATINUM removes the clowns' quizzes (persons 24, 25 are parked at
-- 0,0 with no script, 27 is another sprite): the president hands the Pokétch
-- over on his own after the pitch, so only he is talked to there
if not renegade then
  talkUntil(poketch, 24, flag(0xED))
  talkUntil(poketch, 25, flag(0xEE))
  talkUntil(poketch, 27, flag(0xEF))
end
talkUntil(poketch, 23, flag(0xF3))
B[#B + 1] = { name = "jubilife: the poketch",
  steps = poketch,
  expect = function(r) return r:flag(0xF3) and r:var(0x4077) >= 2 end, why = "flag 0xF3 (Pokétch), 0x4077 >= 2",
  expectBudget = 8000, budget = 120000 }

-- Route 203 (coord 1, x 4 y 21..24 while VAR_ROUTE_203_RIVAL_STATE 0x4088
-- == 0): Barry's battle, 0x4088 = 1
B[#B + 1] = { name = "route 203 rival",
  steps = { { "do", trainUp }, { "teleport", "R203", 2, 22, "right" }, { "activecoord" },
            { "until", varGe(0x4088, 1), 60000 } },
  expect = varGe(0x4088, 1), why = "0x4088 >= 1 (Barry beaten)", expectBudget = 8000 }

-- OREBURGH (scripts_oreburgh_city.s): coord 1 (10,12..15 while
-- VAR_OREBURGH_CITY_STATE 0x4079 == 0) is the youngster at the gate who
-- shows the way: 0x4079 = 1
B[#B + 1] = { name = "oreburgh: the youngster",
  steps = { { "teleport", "C03", 12, 13, "left" }, { "activecoord" },
            { "until", varGe(0x4079, 1), 30000 } },
  expect = varGe(0x4079, 1), why = "0x4079 >= 1", expectBudget = 8000 }

-- Oreburgh Mine B2F (D01R0102): Roark (person 0, between two Rock Smash
-- rocks) heads back to his gym: FLAG_ROARK_RETURNED_TO_OREBURGH_GYM 0x7A
B[#B + 1] = { name = "roark in the mine",
  steps = { { "teleport", "D01R0102", 15, 2, "down" }, { "talk", 0 },
            { "until", flag(0x7A), 30000 } },
  expect = flag(0x7A), why = "flag 0x7A (Roark back at his gym)", expectBudget = 8000 }

-- Oreburgh Gym (C03GYM0101): Roark (person 0), the Coal Badge, TM76
-- (FLAG_RECEIVED_ROARK_TM76 0x75); 0x4079 = 2, VAR_JUBILIFE_CITY_STATE = 3.
-- Rock types: Surf.
B[#B + 1] = { name = "roark",
  steps = { { "do", trainUpWith(57) }, { "teleport", "C03GYM0101", 5, 6, "up" }, { "talk", 0 },
            { "until", flag(0x75), 60000 } },
  expect = function(r) return r:flag(0x75) and r:var(0x4079) >= 2 end, why = "flag 0x75 (Coal Badge, TM76), 0x4079 >= 2",
  expectBudget = 12000 }

-- coord 2 (6,12..15 while 0x4079 == 2): Barry runs into the player on the
-- way out of town -- 0x4079 = 3
B[#B + 1] = { name = "oreburgh: barry",
  steps = { { "teleport", "C03", 8, 13, "left" }, { "activecoord" },
            { "until", varGe(0x4079, 3), 30000 } },
  expect = varGe(0x4079, 3), why = "0x4079 >= 3", expectBudget = 8000 }

-- Jubilife coord 2 (45..47,7 while 0x4077 == 3): Rowan and the counterpart
-- held up by two grunts -- the tag battle, 0x4077 = 4
B[#B + 1] = { name = "jubilife: the galactic grunts",
  steps = { { "do", trainUp }, { "teleport", "C01", 46, 10, "up" }, { "activecoord" },
            { "until", varGe(0x4077, 4), 60000 } },
  expect = varGe(0x4077, 4), why = "0x4077 >= 4 (the tag battle)", expectBudget = 8000 }

-- THE VALLEY WINDWORKS. Route 205 South's coord 1 (19,83..88 while
-- VAR_VALLEY_WINDWORKS_STATE 0x4089 == 0): the little girl whose papa is shut
-- in the Windworks, 0x4089 = 1 (and Floaroma's two grunts leave)
B[#B + 1] = { name = "route 205: the little girl",
  steps = { { "teleport", "R205A", 21, 84, "left" }, { "activecoord" },
            { "until", varGe(0x4089, 1), 30000 } },
  expect = varGe(0x4089, 1), why = "0x4089 >= 1", expectBudget = 8000 }

-- Floaroma Meadow (D13R0101) coord 1 (12..13,48 while
-- VAR_FLOAROMA_MEADOW_STATE 0x40E9 == 0): the two grunts' double battle,
-- the Works Key (FLAG_OBTAINED_FLOAROMA_MEADOW_WORKS_KEY 0x9F)
-- (RENEGADE's pair brings a Croagunk, whose Dry Skin drinks Surf, and Surf
-- also hits the partner in a double: Psychic there)
B[#B + 1] = { name = "floaroma meadow grunts",
  steps = { { "do", renegade and trainUpWith(94) or trainUp }, { "teleport", "D13R0101", 12, 52, "up" }, { "activecoord" },
            { "until", flag(0x9F), 60000 } },
  expect = function(r) return r:flag(0x9F) and r:var(0x40E9) >= 1 end, why = "flag 0x9F (Works Key), 0x40E9 >= 1",
  expectBudget = 8000 }

-- The Windworks' door (D02): the grunt (person 0) in front of it, beaten,
-- goes inside; the door (bg 2 at (19,14)) then takes the Works Key --
-- FLAG_UNLOCKED_VALLEY_WINDWORKS_DOOR 0x10F
B[#B + 1] = { name = "the windworks door",
  steps = { { "do", trainUp }, { "teleport", "D02", 19, 18, "up" }, { "talk", 0 },
            { "until", function(r) return r:personAt(0) == "absent" or r:personAt(0):find("hidden") end, 40000 },
            { "sign", 2 }, { "until", flag(0x10F), 8000 } },
  expect = flag(0x10F), why = "flag 0x10F (the door unlocked)", expectBudget = 8000 }

-- Inside (D02R0101): the frame table (VAR_VALLEY_WINDWORKS_TEAM_GALACTIC_STATE
-- 0x40CF == 0) sets 1, then coord 1 (19,6..7 while 0x40CF == 1) is Mars:
-- the battle, 0x40CF = 2, 0x4089 = 2
B[#B + 1] = { name = "mars at the windworks",
  steps = { { "do", trainUp }, { "warpto", "D02R0101" }, { "until", varGe(0x40CF, 1), 8000 },
            { "activecoord" }, { "until", varGe(0x4089, 2), 60000 } },
  expect = function(r) return r:var(0x4089) >= 2 and r:var(0x40CF) >= 2 end, why = "0x4089 >= 2, 0x40CF >= 2 (Mars beaten)",
  expectBudget = 12000 }

-- ETERNA FOREST (D03R0101; scripts_eterna_forest.s), in from Route 205's
-- north end. Coord 1 ((28..29,85) while VAR_ETERNA_FOREST_FOLLOWER_CHERYL_STATE
-- 0x40B1 == 0) is Cheryl joining as the partner (SetHasPartner, FOLLOW_PLAYER,
-- 0x40B1 = 1, FLAG_TALKED_TO_ETERNA_FOREST_CHERYL 0x8B); the forest walked with
-- her (its trainers fight two on two); coord 3 at the east exit ((82,34..39),
-- 0x40B1 == 1) is her Soothe Bell and goodbye: FLAG_TRAVELED_WITH_CHERYL 0xE3,
-- 0x40B1 = 2
B[#B + 1] = { name = "eterna forest: cheryl", budget = 120000,
  steps = { { "teleport", "R205A", 14, 7, "up" }, { "warpto", "D03R0101" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40B1) >= 1 and not r:busy() end, 20000 },
            { "coord", 3 }, { "until", varGe(0x40B1, 2), 30000 } },
  expect = function(r) return r:var(0x40B1) >= 2 and r:flag(0xE3) and r:flag(0x8B) end,
  why = "0x40B1 >= 2, flags 0xE3, 0x8B", expectBudget = 8000 }

-- ETERNA (scripts_eterna_city.s). Coord 1 (15,11..14 while
-- VAR_ETERNA_CITY_STATE 0x407A == 0): Barry, 0x407A = 1; coords 4/7 (while
-- 0x407A == 1): Cynthia gives HM01 Cut, 0x407A = 2
B[#B + 1] = { name = "eterna: barry",
  steps = { { "teleport", "C04", 17, 13, "left" }, { "activecoord" },
            { "until", varGe(0x407A, 1), 30000 } },
  expect = varGe(0x407A, 1), why = "0x407A >= 1", expectBudget = 8000 }
B[#B + 1] = { name = "eterna: cynthia's cut",
  steps = { { "activecoord" }, { "until", varGe(0x407A, 2), 30000 } },
  expect = varGe(0x407A, 2), why = "0x407A >= 2 (HM01)", expectBudget = 8000 }

-- Eterna Gym (C04GYM0101): Gardenia (person 1), the Forest Badge, TM86
-- (FLAG_RECEIVED_GARDENIA_TM86 0x74). Grass types: Flamethrower.
-- THE FLOWER CLOCK, WALKED (src/world/Gen4EternaGym.lua): from the door the
-- clock's hands wall everything but Lass Caroline (14,22); each trainer
-- beaten turns the clock (AdvanceEternaGymClock) and opens the next one's
-- way -- the hour hand jumped at (11,18), then at (6,13) (the right fountain
-- dry), then at (11,8) (the left one too) -- to Gardenia.
local function clockAt(n) return function(r) return r:var(0x404B) >= n and not r:busy() end end
B[#B + 1] = { name = "gardenia", budget = 60000,
  steps = { { "do", trainUpWith(53) }, { "teleport", "C04GYM0101", 11, 26, "up" },
            { "walkto", 13, 22 }, { "face", "right" }, { "press", "a" }, { "until", clockAt(1), 30000 },
            { "walkto", 11, 19 }, { "step", "up", 1 }, { "until", function(r) return not r:busy() end, 600 },
            { "walkto", 20, 18 }, { "face", "up" }, { "press", "a" }, { "until", clockAt(2), 30000 },
            { "walkto", 7, 13 }, { "step", "left", 1 }, { "until", function(r) return not r:busy() end, 600 },
            { "walkto", 2, 8 }, { "face", "up" }, { "press", "a" }, { "until", clockAt(3), 30000 },
            { "walkto", 11, 9 }, { "step", "up", 1 }, { "until", function(r) return not r:busy() end, 600 },
            { "walkto", 11, 4 }, { "face", "up" }, { "press", "a" },
            { "until", flag(0x74), 60000 } },
  expect = flag(0x74), why = "flag 0x74 (Forest Badge, TM86)", expectBudget = 12000 }

-- The Galactic building's 4F (C04R0204): Jupiter (person 0) --
-- FLAG_TEAM_GALACTIC_LEFT_ETERNA_BUILDING 0x81, 0x407A = 3
B[#B + 1] = { name = "jupiter in the eterna building",
  steps = { { "do", trainUp }, { "teleport", "C04R0204", 12, 7, "up" }, { "talk", 0 },
            { "until", flag(0x81), 60000 } },
  expect = function(r) return r:flag(0x81) and r:var(0x407A) >= 3 end, why = "flag 0x81, 0x407A >= 3",
  expectBudget = 12000 }

-- the Cycle Shop (C04R0101): the owner (person 0, back from the building)
-- gives the Bicycle (FLAG_RECEIVED_BICYCLE 0x82)
B[#B + 1] = { name = "the bicycle",
  steps = { { "teleport", "C04R0101", 3, 8, "up" }, { "talk", 0 },
            { "until", flag(0x82), 20000 } },
  expect = flag(0x82), why = "flag 0x82 (Bicycle)", expectBudget = 8000 }

-- Route 207 (coord 1, x 52 y 8..10 while VAR_ROUTE_207_COUNTERPART_TRIGGER_STATE
-- 0x408C == 0): the counterpart's Vs. Seeker, 0x408C = 1
B[#B + 1] = { name = "route 207: the vs. seeker",
  steps = { { "teleport", "R207", 49, 9, "right" }, { "activecoord" },
            { "until", varGe(0x408C, 1), 30000 } },
  expect = varGe(0x408C, 1), why = "0x408C >= 1", expectBudget = 8000 }

-- Mt. Coronet 1F South (D05R0101) coord 1 (14,23 while
-- VAR_MT_CORONET_1F_SOUTH_STATE 0x4096 == 0): Cyrus's speech, 0x4096 = 1
B[#B + 1] = { name = "cyrus at mt. coronet",
  steps = { { "teleport", "D05R0101", 14, 25, "up" }, { "activecoord" },
            { "until", varGe(0x4096, 1), 30000 } },
  expect = varGe(0x4096, 1), why = "0x4096 >= 1", expectBudget = 8000 }

-- HEARTHOME (scripts_hearthome_city.s). Coord 1 (13,53..57 while
-- VAR_HEARTHOME_CITY_STATE 0x40F6 == 0): the Buneary and Keira, 0x40F6 = 1
B[#B + 1] = { name = "hearthome: keira",
  steps = { { "teleport", "C05", 11, 55, "right" }, { "activecoord" },
            { "until", varGe(0x40F6, 1), 30000 } },
  expect = varGe(0x40F6, 1), why = "0x40F6 >= 1", expectBudget = 8000 }

-- the Contest Hall (C05R1101): its frame table (VAR_CONTEST_HALL_LOBBY_STATE
-- 0x40F7 == 0) is the counterpart's mother; then Fantina (person 10) goes
-- back to her gym -- FLAG_HIDE_HEARTHOME_CITY_GYM_GUIDE 0x18D (the guide in
-- front of the gym door steps away)
B[#B + 1] = { name = "hearthome: fantina at the contest hall",
  steps = { { "teleport", "C05", 31, 21, "up" }, { "warpto", "C05R1101" },
            { "until", varGe(0x40F7, 1), 30000 }, { "talk", 10 },
            { "until", flag(0x18D), 20000 } },
  expect = function(r) return r:flag(0x18D) and r:var(0x40F7) >= 1 end, why = "flag 0x18D, 0x40F7 >= 1",
  expectBudget = 8000 }

-- HEARTHOME GYM, WALKED (src/world/Gen4HearthomeGym.lua): each trainer room
-- is dealt afresh on entry -- one door of its row leads on, the others back
-- to the entrance, and the hint on the floor shows which. The player goes to
-- the hint and through the door it names (the one warp left leading on).
-- Then the leader room (C05GYM0104): Fantina (person 0), the Relic Badge,
-- TM65 (FLAG_RECEIVED_FANTINA_TM65 0x7D);
-- VAR_ROUTE_209_GATE_TO_HEARTHOME_CITY_STATE 0x407B = 1. Ghost types: Crunch.
local function hearthomeClue()
  local walk = { "walkto", 0, 0 }
  return { "do", function(r)
    local M = require("src.world.Gen4DynamicMapFeatures")
    local b = M.buffer(r.game.save, M.HEARTHOME_GYM)
    walk[2], walk[3] = b.clueX, b.clueZ
  end }, walk
end
local fantina = { { "do", trainUpWith(242) }, { "teleport", "C05GYM0101", 4, 7, "up" }, { "warpto", "C05GYM0102" } }
for _, s in ipairs({ hearthomeClue() }) do fantina[#fantina + 1] = s end
fantina[#fantina + 1] = { "warpto", "C05GYM0103" }
for _, s in ipairs({ hearthomeClue() }) do fantina[#fantina + 1] = s end
for _, s in ipairs({ { "warpto", "C05GYM0104" }, { "talk", 0 }, { "until", flag(0x7D), 60000 } }) do fantina[#fantina + 1] = s end
B[#B + 1] = { name = "fantina", budget = 60000,
  steps = fantina,
  expect = function(r) return r:flag(0x7D) and r:var(0x407B) >= 1 end, why = "flag 0x7D (Relic Badge, TM65), 0x407B >= 1",
  expectBudget = 12000 }

-- the Route 209 gate (C05R0601) coord 1 (5,5..9 while 0x407B == 1): Barry's
-- battle, 0x407B = 2
B[#B + 1] = { name = "route 209 gate: barry",
  steps = { { "do", trainUp }, { "teleport", "C05R0601", 2, 7, "right" }, { "activecoord" },
            { "until", varGe(0x407B, 2), 60000 } },
  expect = varGe(0x407B, 2), why = "0x407B >= 2 (Barry beaten)", expectBudget = 8000 }

-- Solaceon (T04) coord 1 (13..19,29 while VAR_SOLACEON_TOWN_STATE 0x4073 ==
-- 0): the counterpart, 0x4073 = 1
B[#B + 1] = { name = "solaceon: the counterpart",
  steps = { { "teleport", "T04", 16, 31, "up" }, { "activecoord" },
            { "until", varGe(0x4073, 1), 30000 } },
  expect = varGe(0x4073, 1), why = "0x4073 >= 1", expectBudget = 8000 }

-- VEILSTONE (scripts_veilstone_city.s). Coord 2 (9..12,40 while
-- VAR_VEILSTONE_CITY_CRASHER_WAKE_STATE 0x40F5 == 0): Wake and the
-- counterpart, 0x40F5 = 1
B[#B + 1] = { name = "veilstone: crasher wake",
  steps = { { "teleport", "C07", 10, 42, "up" }, { "coord", 2 },
            { "until", varGe(0x40F5, 1), 30000 } },
  expect = varGe(0x40F5, 1), why = "0x40F5 >= 1", expectBudget = 8000 }

-- VEILSTONE GYM, WALKED (src/world/Gen4VeilstoneGym.lua): the punching bags
-- are pushed (walked against) to knock the tire stacks over; these thirteen
-- pushes, from the door, open the way (an offline search over the gym's own
-- tables, the bag at each stand-point pushed the way given). Then Maylene
-- (person 0), the Cobble Badge, TM60 (FLAG_RECEIVED_MAYLENE_TM60 0x9D);
-- VAR_VEILSTONE_CITY_COUNTERPART_NEEDS_HELP_STATE 0x411A = 1. Fighting types:
-- Psychic.
local VEILSTONE_PUSHES = {
  { 14, 26, "right" }, { 20, 18, "up" }, { 17, 10, "left" }, { 14, 10, "left" }, { 8, 21, "up" },
  { 9, 17, "left" }, { 3, 16, "down" }, { 4, 23, "up" }, { 3, 9, "down" }, { 3, 12, "right" },
  { 2, 14, "right" }, { 7, 7, "right" }, { 10, 7, "right" }, { 12, 5 },
}
local maylene = { { "do", trainUpWith(94) }, { "teleport", "C07GYM0101", 12, 29, "up" } }
for _, m in ipairs(VEILSTONE_PUSHES) do
  maylene[#maylene + 1] = { "walkto", m[1], m[2] }
  if m[3] then
    maylene[#maylene + 1] = { "hold", m[3], 30, ["until"] = function(r) return r:busy() end }
    maylene[#maylene + 1] = { "until", function(r) return not r:busy() end, 3000 }
  end
end
maylene[#maylene + 1] = { "talk", 0 }
maylene[#maylene + 1] = { "until", flag(0x9D), 60000 }
B[#B + 1] = { name = "maylene", budget = 60000,
  steps = maylene,
  expect = function(r) return r:flag(0x9D) and r:var(0x411A) >= 1 end, why = "flag 0x9D (Cobble Badge, TM60), 0x411A >= 1",
  expectBudget = 12000 }

-- back out in Veilstone, the frame table (0x411A == 1) has the counterpart
-- call for help at the warehouse (0x411A = 2; she stands at (24,20)). Talked
-- to from the west (the script handles the player facing east, north or
-- south only) she joins the tag battle against the warehouse's two grunts;
-- Looker follows and the player is warped inside: the warehouse's frame
-- table (VAR_VEILSTONE_CITY_GALACTIC_WAREHOUSE_STATE 0x411F == 1) sets 2
-- (and VAR_PASTORIA_CITY_STATE 0x407C = 1)
-- Ice Beam, not Surf: the warehouse grunt's Croagunk has DRY SKIN (battle
-- parity pass, 2026-11-02 -- it absorbs Water now; a lone Turtwig surfing it
-- confused itself to death under Swagger)
B[#B + 1] = { name = "veilstone: the galactic warehouse",
  steps = { { "do", trainUpWith(58) }, { "warpto", "C07" }, { "until", varGe(0x411A, 2), 20000 },
            { "walkto", 23, 20 }, { "face", "right" }, { "press", "a" },
            { "until", varGe(0x411F, 2), 60000 } },
  expect = function(r) return r:var(0x411F) >= 2 and r:var(0x407C) >= 1 end, why = "0x411F >= 2, 0x407C >= 1",
  expectBudget = 12000 }

-- in the warehouse: HM02 Fly is the ball at (13,8) (person 1,
-- FLAG_OBTAINED_VEILSTONE_CITY_GALACTIC_WAREHOUSE_HM02 0x4E2)
B[#B + 1] = { name = "hm02 fly",
  steps = { { "talk", 1 }, { "until", flag(0x4E2), 8000 } },
  expect = flag(0x4E2), why = "flag 0x4E2 (HM02)" }

-- PASTORIA (scripts_pastoria_city.s). Coord 2 (13,28 while
-- VAR_PASTORIA_CITY_STATE 0x407C == 1), in front of the gym door: Barry's
-- battle, 0x407C = 2
--
-- RENEGADE PLATINUM puts the Gym Guide ON that cell (C06 person 29, shown
-- while flag 0xA08 is clear: "Wake ... was heading out west to Route 212")
-- and Crasher Wake on Route 212 south (R212B person 44): its coord trigger
-- ((10..13,5) while 0x406E == 0) is his song, he heads back, flag 0xA08 set
-- (the guide steps aside), 0x406E = 1. So he is met there first.
local pastoriaBarry = { { "do", trainUp }, { "teleport", "C06", 13, 30, "up" }, { "activecoord" },
                        { "until", varGe(0x407C, 2), 60000 } }
if renegade then
  for i, s in ipairs({ { "teleport", "R212B", 11, 7, "up" }, { "coord", 1 },
                       { "until", flag(0xA08), 20000 } }) do
    table.insert(pastoriaBarry, 1 + i, s)
  end
end
B[#B + 1] = { name = "pastoria: barry",
  steps = pastoriaBarry,
  expect = varGe(0x407C, 2), why = "0x407C >= 2 (Barry beaten)", expectBudget = 8000 }

-- PASTORIA GYM, WALKED (src/world/Gen4PastoriaGym.lua): the water floor
-- rises and falls with the button last stood on, and the H/M/L gates open at
-- one level each. The turns of the way an offline search found from the door,
-- a third number where a button is pressed (orange 0, green 32, blue 64).
-- Then Crasher Wake (person 0), the Fen Badge, TM55 (FLAG_RECEIVED_WAKE_TM55
-- 0x9C), 0x407C = 3. Water types: Thunderbolt.
local PASTORIA_WAY = {
  { 13, 26 }, { 5, 26 }, { 5, 34 }, { 3, 34, 0 }, { 3, 33 }, { 7, 33 }, { 7, 28 }, { 16, 28 },
  { 16, 22 }, { 13, 22 }, { 13, 9 }, { 17, 9, 32 }, { 17, 11 }, { 14, 11 }, { 14, 14 }, { 15, 14 },
  { 15, 15 }, { 16, 15 }, { 16, 20 }, { 5, 20 }, { 5, 24 }, { 9, 24, 64 }, { 6, 24 }, { 6, 34 },
  { 14, 34 }, { 14, 33 }, { 19, 33 }, { 19, 26 }, { 20, 26 }, { 20, 13 }, { 19, 13, 32 }, { 19, 16 },
  { 21, 16 }, { 21, 31 }, { 23, 31, 0 }, { 23, 7 }, { 7, 7 }, { 7, 16 }, { 5, 16 }, { 5, 9 },
  { 4, 9 }, { 4, 6 }, { 3, 6, 64 }, { 3, 9 }, { 13, 9 }, { 13, 5 },
}
-- (A TEST-BOT CHOICE: the lead kept its own species -- a level-80 Turtwig
-- (387, 185 HP) with Energy Ball -- and lost to Wake once the Gen 4 battle
-- parity landed. Ludicolo at 100, Energy Ball first: 4x on Quagsire, 2x on
-- Floatzel, neutral on Gyarados, and nothing of Wake's hits it hard)
local wake = { { "do", trainUpWith(412, 100, 272) }, { "teleport", "C06GYM0101", 13, 41, "up" } }
for _, m in ipairs(PASTORIA_WAY) do
  wake[#wake + 1] = { "walkto", m[1], m[2] }
  if m[3] then
    local level = m[3]
    wake[#wake + 1] = { "until", function(r)
      local p = r.ow.map.def.gen4DynamicPlate
      return not r:busy() and p ~= nil and p.height == level
    end, 3000 }
  end
end
wake[#wake + 1] = { "talk", 0 }
wake[#wake + 1] = { "until", flag(0x9C), 60000 }
B[#B + 1] = { name = "crasher wake", budget = 60000,
  steps = wake,
  expect = function(r) return r:flag(0x9C) and r:var(0x407C) >= 3 end, why = "flag 0x9C (Fen Badge, TM55), 0x407C >= 3",
  expectBudget = 12000 }

-- out of the gym: the frame table (0x407C == 3) is Barry and Wake (0x407C =
-- 4); coord 3 (34,10 while 0x407C == 4) is the Great Marsh "bomb" -- the
-- grunt runs east (FLAG_PASTORIA_CITY_GRUNT_M_MOVED_EAST 0x102, 0x407C = 5);
-- the grunt (person 21) then talked to leaves for Route 213
-- (FLAG_TALKED_TO_PASTORIA_CITY_GRUNT_M 0x103)
B[#B + 1] = { name = "pastoria: the grunt's bomb",
  steps = { { "warpto", "C06" }, { "until", varGe(0x407C, 4), 20000 },
            { "activecoord" }, { "until", flag(0x102), 30000 },
            { "talk", 21 }, { "until", flag(0x103), 20000 } },
  expect = function(r) return r:flag(0x103) and r:var(0x407C) >= 5 end, why = "flag 0x103, 0x407C >= 5",
  expectBudget = 8000 }

-- Route 213 (R213): the grunt (person 30, by the Pastoria gate first, then at
-- (43,33)) talked to twice -- FLAG_TALKED_TO_ROUTE_213_GRUNT_M 0x118, then
-- Looker's scene: FLAG_ROUTE_213_GRUNT_M_LEFT 0x104
B[#B + 1] = { name = "route 213: the grunt",
  steps = { { "teleport", "R213", 8, 12, "right" }, { "talk", 30 }, { "until", flag(0x118), 20000 },
            { "talk", 30, retarget = true }, { "until", flag(0x104), 30000 } },
  expect = flag(0x104), why = "flag 0x104 (the grunt left)", expectBudget = 8000 }

-- Valor Lakefront (L02): the grunt (person 5) runs north
-- (FLAG_TALKED_TO_VALOR_LAKEFRONT_GRUNT_M 0x106); talked to again he
-- battles, then Cynthia hands over the SecretPotion -- 0x407C = 6
-- Ice Beam: Galactic grunts' Croagunk have DRY SKIN (battle parity pass)
B[#B + 1] = { name = "valor lakefront: the secretpotion",
  steps = { { "do", trainUpWith(58) }, { "teleport", "L02", 47, 57, "up" }, { "talk", 5 },
            { "until", flag(0x106), 20000 }, { "talk", 5, retarget = true },
            { "until", varGe(0x407C, 6), 60000 } },
  expect = varGe(0x407C, 6), why = "0x407C >= 6 (SecretPotion)", expectBudget = 8000 }

-- Route 210 South (R210A): the Psyduck (persons 19, 26, 27, 28) take the
-- SecretPotion, Cynthia gives the Old Charm -- FLAG_USED_SECRETPOTION 0x107
B[#B + 1] = { name = "route 210: the psyduck",
  steps = { { "teleport", "R210A", 17, 46, "up" }, { "talkany", { 19, 26, 27, 28 } },
            { "until", flag(0x107), 30000 } },
  expect = flag(0x107), why = "flag 0x107 (the Psyduck cured)", expectBudget = 8000 }

-- CELESTIC (T05): the grunt (person 2) at the cave door, beaten; the elder
-- takes the Old Charm (FLAG_DELIVERED_OLD_CHARM 0xA6)
-- Ice Beam: Galactic grunts' Croagunk have DRY SKIN (battle parity pass)
B[#B + 1] = { name = "celestic: the grunt",
  steps = { { "do", trainUpWith(58) }, { "teleport", "T05", 15, 13, "up" }, { "talk", 2 },
            { "until", flag(0xA6), 60000 } },
  expect = flag(0xA6), why = "flag 0xA6 (Old Charm delivered)", expectBudget = 8000 }

-- the cave (T05R0501): the painting (bg 1 at (9,2)), the elder and Cyrus --
-- the battle, HM03 Surf; VAR_CELESTIC_TOWN_STATE 0x4074 = 1. Dark/Poison/
-- Flying: Thunderbolt -- on Mewtwo at 100: the starter at 75 lost this
-- battle on some runs (the lead fainted, the beat ran out of time).
B[#B + 1] = { name = "celestic: cyrus at the painting",
  steps = { { "do", strong(85) }, { "teleport", "T05R0501", 9, 5, "up" }, { "sign", 1 },
            { "until", varGe(0x4074, 1), 60000 } },
  expect = function(r) return r:var(0x4074) >= 1 and r:flag(0xA7) end, why = "0x4074 >= 1, flag 0xA7",
  expectBudget = 12000 }

-- out of the cave: Celestic's frame table (0x4074 == 1) is Cynthia's
-- send-off -- 0x4074 = 2 (Route 218's blockade leaves, 0x299)
B[#B + 1] = { name = "celestic: cynthia",
  steps = { { "warpto", "T05" }, { "until", varGe(0x4074, 2), 30000 } },
  expect = function(r) return r:var(0x4074) >= 2 and r:flag(0x299) end, why = "0x4074 >= 2, flag 0x299",
  expectBudget = 8000 }

-- CANALAVE. The gate (R218R0201) coord 1 (7,5..9 while
-- VAR_ROUTE_218_GATE_TO_CANALAVE_CITY_STATE 0x4105 == 0): the Pokédex
-- upgrade, 0x4105 = 1
--
-- RENEGADE PLATINUM drops the scientist and closes the gate: a thirsty
-- policeman (person 0) and a new coord trigger ((2,5..9) while 0x406C == 0)
-- that pushes the player back unless the bag holds the TEA (item 456, the
-- S.S. Ticket's slot); with it he drinks it and 0x406C = 1. The Tea is
-- Pal Park's (R221R0101, as his "take a look at that fancy Pal Park" says):
-- Prof. Oak (person 6) first (flag 0xA0B, he leaves), then Darach (person 5)
-- asks for a battle (trainer 969, six level-48s: Thunderbolt hits them all
-- at least neutrally) and Lady Caitlin hands over the Tea (flag 0xA0C).
if renegade then
  B[#B + 1] = { name = "pal park: the tea", budget = 90000,
    steps = { { "do", trainUpWith(85) }, { "teleport", "R221R0101", 7, 17, "up" },
              { "talk", 6 }, { "until", flag(0xA0B), 20000 },
              { "talk", 5 }, { "until", flag(0xA0C), 60000 } },
    expect = flag(0xA0C), why = "flag 0xA0C (Darach beaten, the Tea)", expectBudget = 8000 }
  B[#B + 1] = { name = "canalave gate: the policeman's tea",
    steps = { { "teleport", "R218R0201", 9, 7, "left" }, { "activecoord" },
              { "until", varGe(0x406C, 1), 30000 } },
    expect = varGe(0x406C, 1), why = "0x406C >= 1 (the Tea drunk, the gate open)", expectBudget = 8000 }
else
B[#B + 1] = { name = "canalave gate: the scientist",
  steps = { { "teleport", "R218R0201", 9, 7, "left" }, { "activecoord" },
            { "until", varGe(0x4105, 1), 30000 } },
  expect = varGe(0x4105, 1), why = "0x4105 >= 1", expectBudget = 8000 }
end

-- Canalave coord 1 (15,19..22 while VAR_CANALAVE_CITY_STATE 0x4078 == 0) on
-- the bridge: Barry's battle, 0x4078 = 1
B[#B + 1] = { name = "canalave: barry on the bridge",
  steps = { { "do", strong() }, { "teleport", "C02", 18, 20, "left" }, { "activecoord" },
            { "until", varGe(0x4078, 1), 60000 } },
  expect = varGe(0x4078, 1), why = "0x4078 >= 1 (Barry beaten)", expectBudget = 8000 }

-- Canalave Gym (C02GYM0101): Byron (person 4), the Mine Badge, TM91
-- (FLAG_RECEIVED_BYRON_TM91 0x92), 0x4078 = 2. Steel types: Earthquake.
-- THE PLATFORMS, RIDDEN (src/world/Gen4CanalaveGym.lua): an offline search
-- of the gym (the 24 platforms' bits, the four floors' collision tables)
-- gives 13 rides from the door to Byron on the fourth floor; walked here
-- step by step, each ride where the search put it. Psychic leads (Byron's
-- Bronzor floats over Earthquake).
local CANALAVE_ROUTE = { "U7L8U3R10U2R2UR3", { "right", 24, 13 }, "D2R5D6", { "down", 29, 22 }, "D4L3UL4U3",
  { "left", 21, 22 }, "L2", { "left", 11, 22 }, "L2UL7D5R2", { "right", 5, 26 }, "U2L3U", { "up", 2, 19 },
  "U7R2U8R5", { "right", 14, 4 }, "R4", { "right", 22, 4 }, "R2D2R2D9", { "down", 26, 22 }, "D2R3U",
  { "up", 29, 16 }, "U6", { "up", 29, 9 }, "U5L3DL3D4R", { "right", 25, 9 }, "L8", { "left", 16, 9 }, "U5" }
-- ...and back down to the door after the badge (the same search from Byron's
-- floor and the bits the climb left: five rides)
local CANALAVE_BACK = { "R2", { "right", 26, 4 }, "R2DRD", { "down", 29, 23 }, "D3L2", { "left", 5, 26 }, "L2ULU",
  { "up", 2, 12 }, "U3R4", { "right", 7, 9 }, "D17R9" }
B[#B + 1] = { name = "byron", budget = 60000,
  steps = { { "do", fullTeam(94) }, battleStyle("set"), routeSteps(), { "teleport", "C02GYM0101", 16, 26, "up" },
            { "route", CANALAVE_ROUTE }, { "face", "up" }, { "press", "a" },
            { "until", flag(0x92), 60000 }, { "route", CANALAVE_BACK }, battleStyle(nil) },
  expect = function(r) return r:flag(0x92) and r:var(0x4078) >= 2 end, why = "flag 0x92 (Mine Badge, TM91), 0x4078 >= 2",
  expectBudget = 12000 }

-- out of the gym: the frame table (0x4078 == 2) is Barry -- 0x4078 = 3,
-- VAR_CANALAVE_LIBRARY_STATE 0x40B2 = 1
B[#B + 1] = { name = "canalave: barry after byron",
  steps = { { "warpto", "C02" }, { "until", varGe(0x4078, 3), 30000 } },
  expect = function(r) return r:var(0x4078) >= 3 and r:var(0x40B2) >= 1 end, why = "0x4078 >= 3, 0x40B2 >= 1",
  expectBudget = 8000 }

-- Iron Island (D24): Riley (person 1) gives HM04 Strength and leaves
-- (FLAG_HIDE_IRON_ISLAND_RILEY 0x214) -- the library's Barry wants it
B[#B + 1] = { name = "iron island: riley",
  steps = { { "teleport", "D24", 21, 13, "up" }, { "talk", 1 },
            { "until", flag(0x214), 30000 } },
  expect = flag(0x214), why = "flag 0x214 (Riley gave HM04)", expectBudget = 8000 }

-- RENEGADE PLATINUM: Riley at the entrance BATTLES the player instead
-- (trainer 970) and keeps the HM. HM04 is his thanks after the tag battle
-- deep in the island (D24R0105, as retail's egg scene): coord 1 ((35,2..3)
-- while 0x4092 == 0) has him join as the partner (0x4092 = 1), coord 4
-- ((21,40..41) while 0x4092 == 1) is the two grunts (trainers 835, 836:
-- Golbat, Houndoom, Muk, Purugly, Toxicroak, Skuntank -- Thunderbolt), then
-- HM04 and 0x4092 = 2. (Coord 2, east of him at x 36, turns a partnered
-- player back, so the walk starts west of it.)
if renegade then
  B[#B + 1] = { name = "iron island: riley's tag battle", budget = 90000,
    steps = { { "do", trainUpWith(85) }, { "teleport", "D24R0105", 36, 3, "left" }, { "coord", 1 },
              { "until", function(r) return r:var(0x4092) >= 1 and not r:busy() end, 20000 },
              { "coord", 4 }, { "until", varGe(0x4092, 2), 60000 } },
    expect = varGe(0x4092, 2), why = "0x4092 >= 2 (the grunts beaten, HM04)", expectBudget = 8000 }
end

-- Barry at the library door (C02 person 18) lets the player by once HM04 is
-- in the bag and goes in (FLAG_HIDE_CANALAVE_CITY_RIVAL_LIBRARY 0x2CC); 3F's
-- frame table (0x40B2 == 1) is Rowan's story and the Lake Valor explosion:
-- FLAG_LAKE_VALOR_EXPLODED 0xA8, 0x40B2 = 2, 0x4078 = 4
B[#B + 1] = { name = "canalave library: the explosion",
  steps = { { "teleport", "C02", 5, 18, "up" }, { "talk", 18 }, { "until", flag(0x2CC), 20000 },
            { "teleport", "C02R0103", 11, 6, "down" },
            { "until", flag(0xA8), 40000 } },
  expect = function(r) return r:flag(0xA8) and r:var(0x40B2) >= 2 end, why = "flag 0xA8 (Lake Valor), 0x40B2 >= 2",
  expectBudget = 8000 }

-- back out: Canalave's frame table (0x4078 == 4) -- Rowan, the counterpart
-- and the sailor; 0x4078 = 5
B[#B + 1] = { name = "canalave: rowan's orders",
  steps = { { "teleport", "C02", 5, 16, "down" }, { "until", varGe(0x4078, 5), 30000 } },
  expect = varGe(0x4078, 5), why = "0x4078 >= 5", expectBudget = 8000 }

-- THE LAKES. Lake Valor, drained (D28R0101) -> Valor Cavern (D28R0103):
-- Saturn (person 1) -- FLAG_DEFEATED_COMMANDER_SATURN_VALOR_CAVERN 0x13E.
-- Golbat/Bronzor/Toxicroak: Psychic.
-- (RENEGADE's Toxicroak may roll DRY SKIN, which drinks the default Surf
-- for the whole battle: Psychic there, as the line above says)
B[#B + 1] = { name = "saturn at lake valor",
  steps = { { "do", strong(renegade and 94 or nil) }, { "teleport", "D28R0103", 14, 23, "up" }, { "talk", 1 },
            { "until", flag(0x13E), 60000 } },
  expect = flag(0x13E), why = "flag 0x13E (Saturn beaten)", expectBudget = 12000 }

-- Lake Verity (D27R0102): the frame table (VAR_LAKE_VERITY_PROF_ROWAN_STATE
-- 0x4097 == 0) is Rowan; Mars (person 7) -- FLAG_TEAM_GALACTIC_LEFT_LAKE_VERITY
-- 0xBA, VAR_LAKE_ACUITY_STATE 0x40D3 = 1
B[#B + 1] = { name = "mars at lake verity",
  steps = { { "do", strong() }, { "teleport", "D27R0102", 47, 54, "up" },
            { "until", varGe(0x4097, 1), 30000 }, { "talk", 7 },
            { "until", flag(0xBA), 60000 } },
  expect = function(r) return r:flag(0xBA) and r:var(0x40D3) >= 1 end, why = "flag 0xBA, 0x40D3 >= 1",
  expectBudget = 12000 }

-- SNOWPOINT GYM, WALKED (src/world/Gen4IceSlide.lua): the ice slides, the
-- ramps give speed and take it, a climb without speed slides back one tile,
-- and a slide with speed smashes the snowballs. Each move is one step in the
-- pad's direction and then hands off until the slide is over; the cell the
-- player should then be standing on is the move's own (an offline search of
-- the gym under the same rule).
-- Then Candice (person 0), the Icicle Badge, TM72 (FLAG_RECEIVED_CANDICE_TM72
-- 0x9E). Ice: Flamethrower.
local SNOWPOINT_MOVES = {
  { "up", 11, 26 }, { "left", 10, 26 }, { "left", 1, 26 }, { "up", 1, 8 },
  { "up", 1, 3 }, { "right", 5, 3 }, { "down", 5, 11 }, { "right", 16, 11 },
  { "left", 7, 11 }, { "down", 7, 14 }, { "right", 13, 14 }, { "right", 15, 14 },
  { "down", 15, 16 }, { "left", 9, 16 }, { "left", 7, 16 }, { "down", 7, 19 },
  { "left", 6, 19 }, { "left", 4, 19 }, { "down", 4, 22 }, { "left", 3, 22 },
  { "left", 2, 22 }, { "left", 1, 22 }, { "up", 1, 8 }, { "right", 19, 8 },
  { "left", 4, 8 }, { "down", 4, 22 }, { "right", 11, 22 }, { "up", 11, 20 },
  { "up", 11, 17 }, { "up", 11, 13 }, { "up", 11, 10 }, { "up", 11, 7 },
  { "up", 11, 5 },
}
local candice = { { "do", strong(53) }, { "teleport", "C09GYM0101", 11, 27, "up" } }
for _, m in ipairs(SNOWPOINT_MOVES) do
  candice[#candice + 1] = { "step", m[1], 1 }
  candice[#candice + 1] = { "until", function(r) return not r:busy() and not r.ow.iceSlide end, 4000 }
  candice[#candice + 1] = { "do", function(r)
    local x, y = r:pos()
    if x ~= m[2] or y ~= m[3] then r:say("  snowpoint: a slide ended at (%d,%d), not (%d,%d)", x, y, m[2], m[3]) end
  end }
end
candice[#candice + 1] = { "talk", 0 }
candice[#candice + 1] = { "until", flag(0x9E), 60000 }
B[#B + 1] = { name = "candice", budget = 60000,
  steps = candice,
  expect = flag(0x9E), why = "flag 0x9E (Icicle Badge, TM72)", expectBudget = 12000 }

-- Acuity Lakefront (L03) coord 1 (22..23,52 while VAR_ACUITY_LAKEFRONT_STATE
-- 0x4084 == 0): Barry on the way up, 0x4084 = 1; then up the Rock Climb wall
-- (22,46..49) -- A at its foot, YES -- into Lake Acuity (D29R0102), whose
-- frame table (VAR_LAKE_ACUITY_STATE 0x40D3 == 1) is Jupiter taking Uxie:
-- 0x40D3 = 2. A CHEAT, said as one: the run never fetches HM08, so the lead
-- is given Rock Climb in its last slot (the battles use the first).
B[#B + 1] = { name = "lake acuity: jupiter",
  steps = { { "teleport", "L03", 22, 54, "up" }, { "activecoord" }, { "until", varGe(0x4084, 1), 20000 },
            { "do", hmMoves({ [4] = 431 }) },
            { "walkto", 22, 50 }, { "face", "up" }, { "press", "a" }, { "mash", 120 },
            { "until", function(r) local _, y = r:pos() return y <= 45 and not r:busy() end, 3000 },
            { "warpto", "D29R0102" },
            { "until", varGe(0x40D3, 2), 40000 } },
  expect = varGe(0x40D3, 2), why = "0x40D3 >= 2 (Uxie taken)", expectBudget = 8000 }

-- THE GALACTIC HQ. Veilstone's grunt (person 23, shown once Uxie is taken)
-- drops the Storage Key and Looker asks the player in (YES):
-- FLAG_VEILSTONE_CITY_GRUNT_DROPPED_STORAGE_KEY 0x155,
-- VAR_VEILSTONE_CITY_GALACTIC_WAREHOUSE_STATE 0x411F = 3
B[#B + 1] = { name = "veilstone: the storage key",
  steps = { { "teleport", "C07", 47, 17, "right" }, { "talk", 23 },
            { "until", varGe(0x411F, 3), 40000 } },
  expect = function(r) return r:flag(0x155) and r:var(0x411F) >= 3 end, why = "flag 0x155, 0x411F >= 3",
  expectBudget = 8000 }

-- the warehouse (C07R0301) coord 1 (8..9,8 while 0x411F == 3): Looker opens
-- the HQ door -- FLAG_USED_STORAGE_KEY 0x10E, 0x411F = 4
B[#B + 1] = { name = "the galactic hq door",
  steps = { { "teleport", "C07R0301", 8, 10, "up" }, { "activecoord" },
            { "until", varGe(0x411F, 4), 30000 } },
  expect = function(r) return r:flag(0x10E) and r:var(0x411F) >= 4 end, why = "flag 0x10E, 0x411F >= 4",
  expectBudget = 8000 }

-- THE HQ, WALKED: from the warehouse into B2F, up through B1F to 1F, round
-- the warp panels ((39,3) -> (32,3), (36,8) -> (1,8); 2F's (1,3) -> (17,5))
-- and back down into B2F's key room for the Galactic Key (the ball, person
-- 5); the key on B2F's door (14,8) out of the key room, out through the
-- warehouse, in at the front door, the key on 1F's
-- locked door (22,18), the stairs (19,14) to 2F and (29,13) to the Hall.
-- The Hall (D26R0109) coord 1 (20,12..13 while VAR_GALACTIC_HQ_HALL_STATE
-- 0x408E == 0): Cyrus's speech, 0x408E = 1. The HQ's grunts are fought on
-- the way (the Mewtwo at 100 with Thunderbolt, as for Cyrus next).
B[#B + 1] = { name = "galactic hq: cyrus's speech", budget = 80000,
  steps = { { "do", strong(85) }, { "warpto", "D26R0106" }, { "warpto", "D26R0105" }, { "warpto", "D26R0101" },
            { "panel", 39, 3 }, { "panel", 36, 8 }, { "warpto", "D26R0102", 4, 3 }, { "panel", 1, 3 },
            { "warpto", "D26R0101", 24, 3 }, { "warpto", "D26R0106", 11, 3 },
            { "talk", 5 }, { "mash", 300 },
            -- the key room's only other way out is B2F's own locked door
            { "walkto", 14, 9 }, { "face", "up" }, { "press", "a" }, { "mash", 300 },
            { "warpto", "C07R0301" }, { "warpto", "C07" }, { "warpto", "D26R0101", 45, 13 },
            { "walkto", 22, 19 }, { "face", "up" }, { "press", "a" }, { "mash", 300 },
            { "warpto", "D26R0102", 19, 14 }, { "warpto", "D26R0109", 29, 13 },
            { "activecoord" },
            { "until", varGe(0x408E, 1), 30000 } },
  expect = varGe(0x408E, 1), why = "0x408E >= 1", expectBudget = 8000 }

-- 4F (D26R0104) coord 1 (8..9,11 while VAR_GALACTIC_HQ_4F_STATE 0x40D6 ==
-- 0): Cyrus's battle and the Master Ball, 0x40D6 = 1. Dark/Poison/Flying:
-- Thunderbolt.
B[#B + 1] = { name = "galactic hq: cyrus",
  steps = { { "do", strong(85) }, { "teleport", "D26R0104", 8, 13, "up" }, { "activecoord" },
            { "until", varGe(0x40D6, 1), 60000 } },
  expect = varGe(0x40D6, 1), why = "0x40D6 >= 1 (Cyrus beaten)", expectBudget = 12000 }

-- the Control Room (D26R0107): Saturn (person 0) --
-- FLAG_DEFEATED_GALACTIC_HQ_CONTROL_ROOM_SATURN 0xAD; then the button (bg 4
-- at (8,5), YES) frees the lake trio: FLAG_FREED_GALACTIC_HQ_POKEMON 0x97D,
-- VAR_MT_CORONET_2F_STATE 0x40A9 = 1
B[#B + 1] = { name = "galactic hq: saturn and the lake trio",
  steps = { { "do", strong(85) }, { "teleport", "D26R0107", 8, 12, "up" }, { "talk", 0 },
            { "until", flag(0xAD), 60000 }, { "sign", 4 },
            { "until", flag(0x97D), 30000 } },
  expect = function(r) return r:flag(0x97D) and r:var(0x40A9) >= 1 end, why = "flag 0x97D (the trio freed), 0x40A9 >= 1",
  expectBudget = 12000 }

-- MT. CORONET, CLIMBED, from the 1F South door to Spear Pillar: 2F's
-- Strength boulder (14,45) pushed down its column, Looker's scene (coord at
-- (11,24..26), VAR_MT_CORONET_2F_STATE 0x40A9 -> 2), the blasted cave
-- painting (7,23) up to (7,12), 3F, outside in the snow: Rock Climb up
-- (31,22..20), 4F's Rock Climb (7,16..13), outside north's sideways one
-- (44..40,22), 4F room 3, 5F, 6F. A CHEAT, said as one: the lead is given
-- Strength, Rock Smash and Rock Climb behind its first move.
-- SPEAR PILLAR (D05R0114). Coord 1 (31,48 while VAR_SPEAR_PILLAR_STATE
-- 0x4098 == 0): two grunts, a double battle (two able Pokémon needed),
-- 0x4098 = 1
local function climbTo(dir, done)
  return { "face", dir }, { "press", "a" }, { "mash", 120 },
         { "until", function(r) return done(r) and not r:busy() end, 3000 }
end
-- Ice Beam, not Surf: a grunt's Croagunk has DRY SKIN, which absorbs Water
-- (battle parity pass, 2026-11-02 -- before it Dry Skin did nothing), and in
-- their double a Surf only ever hit the other Mewtwo. Not Thunderbolt: the
-- climb is full of Graveler. Nothing on the way is immune to Ice. The whole
-- team: the grunts' double sends out the second Mewtwo too.
local coronet = { { "do", fullTeam(58) }, { "do", hmMoves({ [2] = 70, [3] = 249, [4] = 431 }) },
  { "teleport", "D05R0101", 25, 4, "up" }, { "warpto", "D05R0102" },
  { "walkto", 14, 44 }, { "hold", "down", 6 }, { "mash", 40 },
  { "until", function(r) return r.ow.strengthActive and not r:busy() end, 3000 },
  -- held again after anything that stops it (a wild battle mid-push ran a
  -- single hold out of time with the boulder two cells short)
  { "hold", "down", 900, ["until"] = function(r) local _, y = r:pos() return y >= 49 end },
  { "until", function(r) return not r:busy() end, 6000 },
  { "hold", "down", 900, ["until"] = function(r) local _, y = r:pos() return y >= 49 end },
  { "until", function(r) return not r:busy() end, 6000 },
  { "hold", "down", 900, ["until"] = function(r) local _, y = r:pos() return y >= 49 end },
  { "activecoord" }, { "until", varGe(0x40A9, 2), 20000 },
  { "panel", 7, 23 }, { "warpto", "D05R0103", 11, 4 }, { "warpto", "D05R0105" }, { "walkto", 31, 23 } }
-- RENEGADE PLATINUM takes 2F's boulder out (person 8 is gone): the column
-- is walked, nothing pushed
if renegade then
  -- steps 5..13: the walk up to it, the push and the three holds
  for _ = 5, 13 do table.remove(coronet, 5) end
  assert(coronet[5][1] == "activecoord")
end
for _, s in ipairs({ climbTo("up", function(r) local _, y = r:pos() return y <= 19 end) }) do coronet[#coronet + 1] = s end
for _, s in ipairs({ { "warpto", "D05R0106" }, { "walkto", 7, 17 } }) do coronet[#coronet + 1] = s end
for _, s in ipairs({ climbTo("up", function(r) local _, y = r:pos() return y <= 12 end) }) do coronet[#coronet + 1] = s end
for _, s in ipairs({ { "warpto", "D05R0104" }, { "walkto", 45, 22 } }) do coronet[#coronet + 1] = s end
for _, s in ipairs({ climbTo("left", function(r) local x = r:pos() return x <= 39 end) }) do coronet[#coronet + 1] = s end
for _, s in ipairs({ { "warpto", "D05R0107" }, { "warpto", "D05R0108" }, { "warpto", "D05R0109" },
                     -- Ice Beam: the double's Croagunk absorbs Surf (Dry Skin)
                     { "warpto", "D05R0114" }, { "do", fullTeam(58) }, { "walkto", 31, 51 }, { "activecoord" },
                     { "until", varGe(0x4098, 1), 60000 } }) do coronet[#coronet + 1] = s end
B[#B + 1] = { name = "spear pillar: the grunts", budget = 120000,
  steps = coronet,
  expect = varGe(0x4098, 1), why = "0x4098 >= 1", expectBudget = 12000 }

-- coord 2 (30..32,32 while 0x4098 == 1): Mars and Jupiter, a tag battle with
-- Barry; Cyrus summons Dialga and Palkia, Giratina tears the pillar:
-- 0x4098 = 3, FLAG_SPEAR_PILLAR_IS_DISTORTED 0x132,
-- VAR_SPEAR_PILLAR_DISTORTED_STATE 0x40C3 = 1, warp to D05R0115
B[#B + 1] = { name = "spear pillar: mars and jupiter",
  steps = { { "do", fullTeam(57) }, { "activecoord" },
            { "until", function(r) return r:var(0x4098) >= 3 and r:flag(0x132) end, 80000 } },
  expect = function(r) return r:var(0x4098) >= 3 and r:var(0x40C3) >= 1 end, why = "0x4098 >= 3, 0x40C3 >= 1",
  expectBudget = 12000, budget = 100000 }

-- the distorted pillar (D05R0115): the frame table (0x40C3 == 1) is Cynthia
-- (0x40C3 = 2); YES and she leads the way into the Distortion World
-- (D34R0101), whose frame table (VAR_DISTORTION_WORLD_PROGRESS 0x4055 == 0)
-- sets 1
B[#B + 1] = { name = "into the distortion world",
  steps = { { "until", function(r) return r:map() == "D34R0101" end, 40000 },
            { "until", varGe(0x4055, 1), 30000 } },
  expect = function(r) return r:map() == "D34R0101" and r:var(0x4055) >= 1 end, why = "in D34R0101, 0x4055 >= 1",
  expectBudget = 8000 }

-- THE DISTORTION WORLD (ov9_02249960.c; src/world/Gen4DistPlatforms.lua),
-- WALKED: 1F's arrival to Giratina's portal on real input. The floors are
-- crossed with the runner's `dwwalk` (tools/gen4_playthrough/dw_planner.lua:
-- the double jumps, the jump points onto walls and ceilings, the platforms'
-- own grids), and every story point is the cartridge's own -- the tile events
-- (HandleEventAt), the lifts, the rafts, the waterfall, the boulder puzzle,
-- the scripts. The way, with pret's numbers (sMapEvents*, world tiles; cells
-- are the floor's map cells):
--   1F    the slab (40,289,52): 0x4055 = 2; the lift at (19,44) to B1F
--   B1F   Cynthia's frame script (3), Mesprit's event (4); the lift (33,10)
--   B2F   rafts 1, 9, 10, 11, 12, 6 and platform 17 (events 1, 11, 13, 15,
--         17, 21, 9) over both levels to the lift's island; the lift (50,31)
--   B3F   Cyrus (65,193,41): 6; lift 4 (49,22) straight to B5F
--   B5F   Uxie's and Mesprit's boulders down their holes (Strength)
--   B4F   by lifts round to the east; Surf the pool, the east wall, the
--         ceiling; Surf again and ride the waterfall down (EVENT_CMD_CASCADE)
--   B5F   Azelf's boulder down its hole; Surf, ride the waterfall back up
--   B4F   back to the lift (38,36); B3F lift 4 again; B5F lift 2 (30,33)
--   B6F   the three boulders into their pits; Cynthia: 7; the lift (29,48)
--   B7F   the frame script (8), Cynthia and Cyrus (84..86,65,76): 9; Cyrus's
--         battle: 10; the teleport north of (89,65,57)
--   room  z 24, 23, 17, 14 (11, 12, 13); Giratina's battle (14); the portal
-- Two things the run's own state needs, said as such: the lead learns
-- Strength (HM04 is the player's since "iron island"; the six Mewtwo do not
-- know it), and the battle style is SET (a player's option: no "switch?"
-- offers for the runner's A to walk into a party menu).
local function dwBit(i)        -- a Distortion World puzzle flag is clear
  return function() return math.floor(require("src.world.Gen4DistPlatforms").puzzleFlags() / 2 ^ i) % 2 == 0 end
end
local function dwIdle() return { "until", function(r) return not r:busy() end, 20000 } end
local function notOn(id) return function(r) return r:map() ~= id end end
local function onMap(id) return function(r) return r:map() == id end end
local function npcAt(localId, x, y)
  return function(r)
    for _, n in ipairs(r.ow.npcs or {}) do
      local lid = n.localId or (n.def and n.def.localId)
      if lid == localId and not n.hidden and not n.moving and n.cellX == x and n.cellY == y then return true end
    end
    return false
  end
end
local DW = {}
local function dw(list) for _, s in ipairs(list) do DW[#DW + 1] = s end end
-- walk onto a tile event's tile and let it run (done once HandleEventAt has
-- started one: the event carries the player off the tile it was asked for)
local function dwEvent(goal)
  local mark = 0
  local function P() return require("src.world.Gen4DistPlatforms") end
  return { { "do", function()
             local Pl = P()
             if not Pl.ptCounted then
               Pl.ptCounted = true
               local orig = Pl.onPosition
               Pl.onPosition = function(...)
                 local ok = orig(...)
                 if ok then Pl.ptEvents = (Pl.ptEvents or 0) + 1 end
                 return ok
               end
             end
             mark = Pl.ptEvents or 0
           end },
           { "dwwalk", goal, done = function() return (P().ptEvents or 0) > mark end },
           { "until", function(r) return not r.ow.dwEvent and not r:busy() end, 6000 } }
end
local function lift(cell, from) return { { "dwwalk", { cell = cell }, done = notOn(from) }, { "until", notOn(from), 3000 } } end
local function surf(dir) return { { "hold", dir, 6 }, { "mash", 40 }, { "press", "a" }, { "mash", 240 } } end
-- Strength on the boulder ahead (A on the rhythm: the boulder's script,
-- YES, its lines -- unless this visit has it already)
local function arm(dir)
  return { { "hold", dir, 6 }, { "mash", 30 },
           { "until", function(r) return r.ow.strengthActive and not r:busy() end, 3000 } }
end
-- ...and push until the boulder's puzzle flag clears
local function push(dir, bit)
  local out = arm(dir)
  out[#out + 1] = { "hold", dir, 900, ["until"] = dwBit(bit) }
  out[#out + 1] = dwIdle()
  return out
end
dw({ { "do", function(r)
       local lead = r:party()[1]
       if lead and lead.moves and not (type(lead.moves[4]) == "table" and lead.moves[4].id == 70) then
         local mv = {}
         for k, v in pairs(type(lead.moves[4]) == "table" and lead.moves[4] or {}) do mv[k] = v end
         mv.id, mv.pp = 70, 15
         lead.moves[4] = mv
       end
       r.game.save.options = r.game.save.options or {}
       r.game.save.options.battleStyle = "set"
     end } })
-- 1F
dw({ { "dwwalk", { cell = { 19, 42 } } }, { "until", varGe(0x4055, 2), 6000 }, dwIdle() })
dw(lift({ 19, 44 }, "D34R0101"))
-- B1F
dw({ { "until", varGe(0x4055, 3), 6000 }, dwIdle() })
dw(lift({ 33, 10 }, "D34R0102"))
-- B2F
for _, g in ipairs({ { cell = { 18, 36 } }, { tile = { 35, 233, 15 } }, { tile = { 51, 233, 15 } }, { tile = { 65, 233, 17 } },
                     { tile = { 63, 233, 45 } }, { tile = { 49, 233, 36 } }, { cell = { 36, 31 } } }) do
  dw(dwEvent(g))
end
dw(lift({ 50, 31 }, "D34R0103"))
-- B3F
dw(dwEvent({ tile = { 65, 193, 41 } }))
dw({ { "until", varGe(0x4055, 6), 6000 }, dwIdle() })
dw(lift({ 49, 22 }, "D34R0104"))
-- B5F, the west: Uxie's boulder (local id 130, flag 2) and Mesprit's (128, flag 0)
dw({ { "dwwalk", { cell = { 29, 21 } } } }); dw(push("down", 2))
dw({ { "dwwalk", { cell = { 17, 34 } } } }); dw(push("right", 0))
-- round to B4F's east side
dw(lift({ 21, 43 }, "D34R0107")); dw(lift({ 22, 28 }, "D34R0105")); dw(lift({ 48, 49 }, "D34R0104"))
-- B4F: Surf, the wall, the ceiling, Surf, the waterfall down
dw({ { "dwwalk", { cell = { 35, 26 } } } }); dw(surf("up"))
dw({ { "dwwalk", { cell = { 40, 22 } } }, { "dwwalk", { tile = { 101, 170, 70 } } } }); dw(surf("up"))
dw({ { "dwwalk", { tile = { 104, 170, 77 } } }, { "hold", "right", 3000, ["until"] = onMap("D34R0107") },
     { "until", function(r) return not r.ow.dwCascade and not r:busy() end, 3000 } })
-- B5F, the east: Azelf's boulder (129, flag 1); back up the waterfall
dw({ { "dwwalk", { cell = { 42, 33 } } } }); dw(push("left", 1))
dw({ { "dwwalk", { cell = { 44, 33 } } } }); dw(surf("right"))
dw({ { "dwwalk", { cell = { 47, 43 } } }, { "hold", "right", 3000, ["until"] = onMap("D34R0105") },
     { "until", function(r) return not r.ow.dwCascade and not r:busy() end, 3000 },
     { "dwwalk", { tile = { 101, 170, 70 } } }, { "dwwalk", { cell = { 38, 22 } } } }); dw(surf("left"))
dw({ { "dwwalk", { cell = { 35, 26 } } } })
dw(lift({ 38, 36 }, "D34R0105")); dw(lift({ 49, 22 }, "D34R0104")); dw(lift({ 30, 33 }, "D34R0107"))
-- B6F: Uxie's pit (29,22), Azelf's (40,30), Mesprit's (12,29) -- the boulders'
-- outside flags 5, 4, 3 -- then Cynthia (local id 134 at 29,42)
dw({ { "dwwalk", { cell = { 30, 17 } } } }); dw(arm("down"))
dw({ { "hold", "down", 900, ["until"] = npcAt(130, 30, 22) }, dwIdle(),
     { "dwwalk", { cell = { 31, 22 } } }, { "hold", "left", 900, ["until"] = dwBit(5) }, dwIdle(),
     { "dwwalk", { cell = { 43, 29 } } }, { "hold", "left", 900, ["until"] = npcAt(129, 40, 29) }, dwIdle(),
     { "dwwalk", { cell = { 40, 28 } } }, { "hold", "down", 900, ["until"] = dwBit(4) }, dwIdle(),
     { "dwwalk", { cell = { 20, 30 } } }, { "hold", "left", 1500, ["until"] = npcAt(128, 12, 30) }, dwIdle(),
     { "dwwalk", { cell = { 12, 31 } } }, { "hold", "up", 900, ["until"] = dwBit(3) }, dwIdle(),
     { "dwwalk", { cell = { 29, 41 } } }, { "hold", "down", 6 }, { "mash", 30 }, { "press", "a" },
     { "until", varGe(0x4055, 7), 3000 }, dwIdle() })
dw(lift({ 29, 48 }, "D34R0108"))
-- B7F: Cynthia and Cyrus; Cyrus (local id 129 at 11,42); the teleport
dw({ { "until", varGe(0x4055, 8), 3000 }, dwIdle() })
dw(dwEvent({ cell = { 11, 44 } }))
dw({ { "until", varGe(0x4055, 9), 3000 }, dwIdle(),
     { "dwwalk", { cell = { 11, 43 } } }, { "hold", "up", 6 }, { "mash", 30 }, { "press", "a" },
     { "until", varGe(0x4055, 10), 30000 }, dwIdle(),
     { "dwwalk", { cell = { 15, 25 } } }, { "hold", "up", 3000, ["until"] = onMap("D34R0110") }, dwIdle() })
-- the Giratina room: its four tile events walked, Giratina's battle, the portal
dw({ { "dwwalk", { tile = { 15, 1, 24 } } }, dwIdle(), { "dwwalk", { tile = { 15, 1, 23 } } }, dwIdle(),
     { "dwwalk", { tile = { 15, 1, 17 } } }, dwIdle(), { "dwwalk", { tile = { 15, 1, 14 } } }, dwIdle(),
     { "until", varGe(0x4055, 13), 6000 }, dwIdle(),
     { "hold", "up", 6 }, { "mash", 30 }, { "press", "a" },
     { "until", varGe(0x4055, 14), 40000 }, dwIdle(),
     { "answers", { 1 } }, { "hold", "up", 6 }, { "mash", 30 }, { "press", "a" },
     { "until", onMap("D17R0101"), 6000 } })
-- ...and out at Sendoff Spring (D17R0101) with VAR_EXITED_DISTORTION_WORLD_STATE
-- 0x40AA = 1, whose frame table (0x40AA == 1) is Cynthia's scene: 0x40AA = 2,
-- VAR_SANDGEM_TOWN_LAB_STATE 0x40A6 = 2, FLAG_SPEAR_PILLAR_IS_DISTORTED 0x132
-- cleared
dw({ { "until", varGe(0x40AA, 2), 30000 } })
B[#B + 1] = { name = "the distortion world, walked to sendoff spring", steps = DW, budget = 250000,
  expect = function(r) return r:var(0x40AA) >= 2 and r:var(0x40A6) >= 2 and not r:flag(0x132) end,
  why = "0x40AA >= 2, 0x40A6 >= 2, flag 0x132 clear", expectBudget = 8000 }

-- Rowan's lab (T02R0101): the frame table (0x40A6 == 2,
-- OnFrame_ReturnedFromDistortionWorld): 0x40A6 = 3,
-- VAR_VALOR_LAKEFRONT_BLOCK_SUNYSHORE_STATE 0x4112 = 1 (the way to Sunyshore)
B[#B + 1] = { name = "sandgem lab: after the distortion world",
  steps = { { "teleport", "T02", 8, 12, "up" }, { "warpto", "T02R0101" },
            { "until", varGe(0x40A6, 3), 30000 } },
  expect = function(r) return r:var(0x40A6) >= 3 and r:var(0x4112) >= 1 end, why = "0x40A6 >= 3, 0x4112 >= 1",
  expectBudget = 8000 }

-- SUNYSHORE (scripts_sunyshore_city.s). In through the Route 222 gate
-- (R222R0301): the frame table (VAR_SUNYSHORE_CITY_STATE 0x407E == 0) is
-- Flint, who only goes on with the player at the gate's cells (0,54)/(0,55):
-- 0x407E = 1, Flint at the gym door
B[#B + 1] = { name = "sunyshore: flint",
  steps = { { "teleport", "R222R0301", 3, 7, "right" }, { "warpto", "C08" },
            { "until", varGe(0x407E, 1), 30000 } },
  expect = varGe(0x407E, 1), why = "0x407E >= 1", expectBudget = 8000 }

-- the Vista Lighthouse (C08R0801): Volkner (person 2) goes back to his gym
-- (FLAG_VOLKNER_RETURNED_TO_GYM 0x162); Flint (person 18) then steps away
-- from the door (FLAG_HIDE_SUNYSHORE_CITY_FLINT 0x239)
B[#B + 1] = { name = "sunyshore: volkner at the lighthouse",
  steps = { { "teleport", "C08R0801", 6, 5, "up" }, { "face", "up" }, { "press", "a" }, { "until", flag(0x162), 30000 },
            { "teleport", "C08", 13, 15, "up" }, { "talk", 18 }, { "until", flag(0x239), 30000 } },
  expect = function(r) return r:flag(0x162) and r:flag(0x239) end, why = "flags 0x162, 0x239", expectBudget = 8000 }

-- Sunyshore Gym's last room (C08GYM0103; reached through the gear rooms):
-- Volkner (person 0), the Beacon Badge, TM57 (FLAG_RECEIVED_VOLKNER_TM57
-- 0xB6), 0x407E = 2. Electric types: Earthquake.
-- THE GEARS, TURNED (src/world/Gen4SunyshoreGym.lua): each room walked by
-- an offline search under the gears' collision -- room 1 presses its east
-- and west hubs, room 2 its bottom hub three times and both top (reverse)
-- hubs, room 3 a bottom (double) hub twice -- in by the door, out by the far
-- one, to Volkner.
-- RENEGADE's Volkner leads two Rotom (Electric/Ghost, Levitate): Earthquake
-- never touches them, so there the team leads with Psychic (STAB, neutral
-- on his whole team and the gym's)
B[#B + 1] = { name = "volkner", budget = 60000,
  steps = { { "do", fullTeam(renegade and 94 or 89) }, battleStyle("set"), routeSteps(), { "teleport", "C08GYM0101", 8, 14, "up" },
            { "route", { "U6R5D3L5U3L5R5U5" } }, { "warpto", "C08GYM0102" },
            { "route", { "U5L3U3LRUDR5D7L8U4LU12R3DRD3R5D5R3DRU11L6" } }, { "warpto", "C08GYM0103" },
            { "route", { "U7R5D3L5U3L5D6L3U3LU17R9" } }, { "face", "up" }, { "press", "a" },
            { "until", flag(0xB6), 60000 }, battleStyle(nil) },
  expect = function(r) return r:flag(0xB6) and r:var(0x407E) >= 2 end, why = "flag 0xB6 (Beacon Badge, TM57), 0x407E >= 2",
  expectBudget = 12000 }

-- coord 1 (21..25,7 while 0x407E == 2): Barry and Jasmine, HM07 Waterfall
-- (FLAG_RECEIVED_SUNYSHORE_CITY_HM07 0x9A), 0x407E = 3
B[#B + 1] = { name = "sunyshore: jasmine's waterfall",
  steps = { { "teleport", "C08", 23, 9, "up" }, { "activecoord" },
            { "until", flag(0x9A), 30000 } },
  expect = function(r) return r:flag(0x9A) and r:var(0x407E) >= 3 end, why = "flag 0x9A (HM07), 0x407E >= 3",
  expectBudget = 8000 }

-- RENEGADE PLATINUM: Victory Road 1F's north part is held by a collector
-- (D09R0101 person 12 at (38,18), shown while flag 0xA12 is clear) and a
-- coord trigger across the column ((37..39,18) while 0x403E == 0) -- "you're
-- not quite ready yet. Have you been to Route 224?" -- and Route 224 is
-- open before the League: the counterpart (R224 person 23, by the stone
-- tablet) talks once (flag 0x8B5), then offers a battle (YES; trainers
-- 975..977 by the starter, six level-69s, Psychic hits them all), and on a
-- win leaves: flag 0xA12, 0x403E = 1.
if renegade then
  B[#B + 1] = { name = "route 224: the counterpart", budget = 90000,
    steps = { { "do", fullTeam(94) }, { "teleport", "R224", 44, 14, "up" },
              { "talk", 23 }, { "until", function(r) return r:flag(0x8B5) and not r:busy() end, 20000 },
              { "talk", 23 }, { "until", flag(0xA12), 60000 } },
    expect = function(r) return r:flag(0xA12) and r:var(0x403E) >= 1 end,
    why = "flag 0xA12, 0x403E >= 1 (the counterpart beaten on Route 224)", expectBudget = 8000 }
end

-- ROUTE 223, SURFED: from Sunyshore's north shore (21,1), three seas joined
-- by SHALLOW_WATER shoals -- ashore at (17,49), down the shoal to (10,49) and
-- Surf again, ashore on the west shoal (4,49), Surf from (5,40), the strip
-- (9,28..25), Surf on -- into the League's south water and up its waterfall
-- (Waterfall, (15,61) -> (15,59)), to Victory Road's door. The route's
-- swimmers are fought by the six Mewtwo leading with Psychic; CHEATS, said
-- as such: the lead is given Surf and Waterfall
-- in its last two slots, and a Max Repel's 250 steps keep the wild Pokemon
-- off (on a run with Surf first, one wild battle here felled three Mewtwo;
-- not looked into -- the battle is not what this beat tests). Victory Road
-- is walked (below), and the League's falls after it.
-- THE POKEMON LEAGUE. The north Pokémon Center (C10R0101) coord 1 (10..12,4
-- while VAR_RIVAL_BEAT_SUNYSHORE_GYM 0x40EF == 0): Barry's last battle,
-- 0x40EF = 1; the guard (person 0) at the door then steps aside:
-- FLAG_POKEMON_LEAGUE_DOOR_GUARD_MOVED_AWAY 0xAF
local function surfOn(dir)
  return { "face", dir }, { "press", "a" }, { "mash", 200 },
         { "until", function(r) return r.ow.player.surfing and not r:busy() end, 3000 }
end
local league = { { "do", fullTeam(94) }, { "do", hmMoves({ [3] = 57, [4] = 127 }) },
                 { "do", function(r) r.game.save.repelSteps = 250 end },
                 { "teleport", "C08", 21, 1, "left" } }
local function add(list) for _, s in ipairs(list) do league[#league + 1] = s end end
add({ surfOn("left") }); add({ { "walkedge", "up" }, { "swimto", 17, 50 }, { "step", "up", 1 }, { "walkto", 10, 49 } })
add({ surfOn("down") }); add({ { "swimto", 3, 49 }, { "step", "right", 1 }, { "walkto", 5, 40 } })
add({ surfOn("up") }); add({ { "swimto", 9, 29 }, { "step", "up", 1 }, { "walkto", 9, 25 } })
add({ surfOn("up") }); add({ { "swimto", 15, 0 }, { "walkedge", "up" }, { "swimto", 15, 61 } })
add({ { "face", "up" }, { "press", "a" }, { "mash", 200 },
      { "until", function(r) local _, y = r:pos() return y <= 59 and not r:busy() end, 4000 },
      { "walkto", 15, 56 }, { "warpto", "D09R0101" } })
-- VICTORY ROAD, WALKED: 1F's Rock Climb down, the stairs at (4,37); 2F's
-- Rock Smash rocks and Strength boulders (an offline search: three rocks,
-- six pushes) to the stairs at (23,26); 1F again, Rock Climb down to the
-- B1F stairs (42,41); B1F by Surf and the Waterfall to the stairs (3,22);
-- 1F's north part, Rock Climb up, the bridge, out at (34,6). The HMs ride on
-- the sixth and fifth Mewtwo; Ice Beam leads (Psychic Valencia's Absol is
-- immune to Psychic).
add({ { "do", fullTeam(58) }, { "do", function(r)
        local party = r:party()
        party[6].moves = { { id = 70, pp = 15 }, { id = 249, pp = 15 }, { id = 431, pp = 20 }, { id = 58, pp = 20 } }
        party[5].moves = { { id = 57, pp = 15 }, { id = 127, pp = 15 }, { id = 58, pp = 20 } }
        r.game.save.repelSteps = 250
      end }, battleStyle("set"), routeSteps(), { "walkto", 15, 77 },
      { "route", { "U15R16UR2U13R3" } }, { "act", "down", 36, 53 }, { "route", { "DL11D2L12U13L4U6L4" } },
      { "warpto", "D09R0102", 4, 37 } })
-- (RENEGADE PLATINUM clears 2F: every rock and boulder is parked at
-- (999,999), so the stairs are simply walked to)
if not renegade then
  add({ { "route", { "DL3DL" } }, { "smash", "down", 16, 19 }, { "route", { "D3RD6" } }, { "push", "down", 17, 29 },
      { "route", { "D" } }, { "push", "left", 15, 28 }, { "route", { "L" } }, { "push", "down", 16, 30 },
      { "route", { "DLD2L10" } }, { "push", "down", 5, 33 }, { "route", { "DL2D2R" } }, { "smash", "right", 5, 34 },
      { "route", { "R" } }, { "push", "up", 5, 32 }, { "route", { "UR4D2" } }, { "smash", "down", 9, 36 },
      { "route", { "D2R2UR10DR" } }, { "push", "right", 24, 37 }, { "route", { "RU7LU4" } } })
end
add({ { "warpto", "D09R0101", 23, 26 },
      { "route", { "DR15" } }, { "act", "down", 22, 53 }, { "route", { "L5U11R14UR10" } },
      { "warpto", "D09R0103", 42, 41 },
      { "route", { "UR11U3" } }, { "act", "up", 15, 34 }, { "route", { "U4R3U" } }, { "act", "up", 18, 28 },
      { "route", { "U6R2U8R4U3" } }, { "act", "up", 24, 9 }, { "route", { "U4L14" } }, { "act", "left", 9, 5 },
      { "route", { "L4D17L" } },
      { "warpto", "D09R0101", 3, 22 },
      { "route", { "L12D13R9" } }, { "act", "up", 38, 32 }, { "route", { "U26L3" } },
      { "warpto", "C10" },
      -- out at (21,38) below the League's falls: Surf from (15,28), up the
      -- Waterfall (row 25), across, ashore at (15,19) by the north Pokemon Center
      { "walkto", 15, 28 }, { "face", "up" }, { "press", "a" }, { "mash", 200 },
      { "until", function(r) return r.ow.player.surfing and not r:busy() end, 3000 },
      { "swimto", 15, 26 }, { "face", "up" }, { "press", "a" }, { "mash", 200 },
      { "until", function(r) local _, y = r:pos() return y <= 24 and not r:busy() end, 4000 },
      { "swimto", 15, 20 }, { "step", "up", 1 }, battleStyle(nil) })
-- (RENEGADE's Barry brings Azumarill, Breloom and Empoleon, who all resist
-- Surf: Psychic there)
add({ { "do", fullTeam(renegade and 94 or 57) }, { "warpto", "C10R0101" }, { "walkto", 11, 7 }, { "face", "up" }, { "activecoord" },

      { "until", varGe(0x40EF, 1), 60000 },
      { "talk", 0 }, { "until", flag(0xAF), 20000 } })
-- RENEGADE's Route 223 and Victory Road trainers (level 60-70 full teams,
-- one after another) wear the six Mewtwo down before Barry. The hack puts
-- nurses inside Victory Road for that; here the party is healed, a CHEAT
-- said as one, before every leg of the walk (each route / warp / field move)
if renegade then
  local heal = { "do", function(r)
    local Pokemon = require("src.pokemon.Pokemon")
    for _, mon in ipairs(r:party()) do Pokemon.heal(mon) end
  end }
  local out = {}
  for _, s in ipairs(league) do
    if s[1] == "route" or s[1] == "warpto" or s[1] == "act" then out[#out + 1] = heal end
    out[#out + 1] = s
  end
  league = out
end
B[#B + 1] = { name = "the league: barry", budget = renegade and 200000 or 100000,
  steps = league,
  expect = function(r) return r:var(0x40EF) >= 1 and r:flag(0xAF) end, why = "0x40EF >= 1, flag 0xAF",
  expectBudget = 12000 }

-- the Elite Four (C10R0103/0105/0107/0109): each room's member is person 0
-- at (8,5); FLAG_DEFEATED_AARON 0xB0, BERTHA 0xB1, FLINT 0xB2, LUCIAN 0xB3.
-- Six Mewtwo at 100, leading with Flamethrower for Aaron's bugs, Surf for
-- Bertha's ground and Flint's fire, Shadow Ball for Lucian's psychics.
-- WALKED, room to room, as a player goes: out of the previous room by the
-- door its member's win removed (RemoveObject LOCALID_EXIT_DOOR), up the
-- lift room between (C10R0102/0104/0106/0108: the coord at (4,11) is
-- TriggerPlatformLift), into the next room (its frame table walks the player
-- in and shuts the door behind)
local E4 = { { "aaron", "C10R0102", "C10R0103", 0xB0, 53 }, { "bertha", "C10R0104", "C10R0105", 0xB1, 57 },
             { "flint", "C10R0106", "C10R0107", 0xB2, 57 }, { "lucian", "C10R0108", "C10R0109", 0xB3, 247 } }
for _, e in ipairs(E4) do
  local f = e[4]
  B[#B + 1] = { name = "elite four " .. e[1],
    steps = { { "do", fullTeam(e[5]) }, { "warpto", e[2] }, { "coord", 1 },
              { "until", function(r) return not r:busy() end, 3000 },
              { "mash", 60 }, { "warpto", e[3] },
              { "until", function(r) return r:map() == e[3] and not r:busy() end, 6000 },
              { "talk", 0 }, { "until", flag(f), 60000 } },
    expect = flag(f), why = ("flag 0x%X"):format(f), expectBudget = 12000 }
end

-- the Champion's room (C10R0111): its frame table (VAR_MAP_LOCAL_0x03 == 0)
-- is Cynthia's battle -- FLAG_DEFEATED_CYNTHIA 0xB4 -- then the hallway and
-- the Hall of Fame (C10R0113): ClearGame sets FLAG_GAME_COMPLETED 0x964 and
-- the credits roll. Ice Beam for her Garchomp.
B[#B + 1] = { name = "champion cynthia",
  steps = { { "do", fullTeam(58) }, { "warpto", "C10R0110" }, { "coord", 1 },
            { "until", function(r) return not r:busy() end, 3000 }, { "mash", 60 },
            { "warpto", "C10R0111" },
            { "until", flag(0xB4), 80000 },
            { "until", flag(0x964), 120000 } },
  expect = function(r) return r:flag(0xB4) and r:flag(0x964) end, why = "flags 0xB4 (Cynthia), 0x964 (game completed)",
  expectBudget = 12000, budget = 220000, passBusy = true }

-- ---------------------------------------------------------------------------
-- AFTER THE CREDITS. ClearGame ends in OS_ResetSystem: the title, and a
-- CONTINUE that walks in at the special location (the house 2F, (4,6) facing
-- up; clear_game.c). Here the credits run to the title on A (they cannot be
-- skipped the first time), and the continue is Game:restoreSave on the save
-- the Hall of Fame wrote, as the title's CONTINUE does with the file.
local function onTitle(r)
  local top = r:top()
  return top ~= nil and top.screenId == "TitleState"
end
local function continueGame(r)
  local SaveData = require("src.core.SaveData")
  r.game:restoreSave(SaveData.decode(SaveData.encode(r.game.save)))
end

-- the house 1F's frame table (VAR_PLAYER_HOUSE_POSTGAME_STATE 0x410F == 1,
-- set by the Hall of Fame's script) is Mom's post-game scene:
-- 0x410F = 2 and FLAG_TALKED_TO_MOM_ABOUT_NATIONAL_DEX_PROGRESS 0x15D
B[#B + 1] = { name = "after the credits: home",
  steps = { { "until", onTitle, 60000 }, { "do", continueGame },
            { "until", function(r) return r:map() == "T01R0202" and not r:busy() end, 6000 },
            { "warpto", "T01R0201" },
            { "until", varGe(0x410F, 2), 6000 } },
  -- RENEGADE PLATINUM enables the National Dex in Rowan's first lab scene
  -- (GetSetNationalDexEnabled 1 there), so Mom takes the scene's other
  -- branch: FLAG_TALKED_TO_MOM_ABOUT_NATIONAL_DEX 0x15C, not 0x15D
  expect = function(r) return r:var(0x410F) >= 2 and r:flag(renegade and 0x15C or 0x15D) end,
  why = renegade and "0x410F >= 2, flag 0x15C (Mom's post-game scene, National Dex)"
    or "0x410F >= 2, flag 0x15D (Mom's post-game scene)", budget = 80000 }

-- A CHEAT, said as one: every Sinnoh Pokédex species marked seen (the
-- encounters are not under test here), which is what Rowan asks for
local function seeSinnohDex(r)
  local save = r.game.save
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  local orders = r.game.data.gen4_dex and r.game.data.gen4_dex.orders
  for _, id in ipairs(orders and orders.sinnoh or {}) do
    id = tonumber(id)
    if id and id > 0 then save.pokedex.seen[id] = true end
  end
end
-- a FLAG_DEFEATED_TRAINER_* (TRAINER_DEFEATED_FLAGS_START 0x550 + the trainer
-- id): the port keeps that bank as save.gen4TrainerFlags[id], which
-- Check/SetTrainerFlag and the trainers' sight read -- not save.flags
local function trainerFlag(flagId)
  return function(r)
    local t = (r.game.save or {}).gen4TrainerFlags or {}
    return t[flagId - 0x550] == true
  end
end
local function nationalDex(r) return ((r.game.save or {}).pokedex or {}).national == true end

-- Rowan's lab (T02R0101, Rowan person 0 at (7,14) since the Distortion World):
-- the local dex complete, his talk script rates it, Oak arrives and the
-- Pokédex gets its National mode (GetSetNationalDexEnabled 1), the Poké Radar
B[#B + 1] = { name = "sandgem lab: the national dex",
  steps = { { "do", seeSinnohDex }, { "teleport", "T02", 8, 12, "up" }, { "warpto", "T02R0101" },
            { "talk", 0 }, { "until", nationalDex, 30000 } },
  expect = nationalDex, why = "the National Dex", expectBudget = 8000 }

-- Snowpoint's harbour (C09): the S.S. Spiral's sailor (person 8) sails to the
-- Battle Zone once the game is completed -- Cynthia sees the player off the
-- first time (FLAG_SAILED_TO_BATTLE_ZONE 0x157) -- PlayBoatCutscene to the
-- Fight Area (C11)
B[#B + 1] = { name = "snowpoint: the s.s. spiral",
  steps = { { "teleport", "C09", 13, 53, "left" }, { "talk", 8 },
            { "until", function(r) return r:map() == "C11" end, 30000 } },
  expect = function(r) return r:flag(0x157) and r:map() == "C11" end, why = "flag 0x157, on C11",
  expectBudget = 8000 }

-- the Fight Area's frame table (VAR_FIGHT_AREA_STATE 0x4081 == 0): Barry, the
-- Tower Tycoon his father, Buck; the blockade lifts with the National Dex
-- (FLAG_HIDE_FIGHT_AREA_BLOCKADE 0x294); 0x4081 = 2
B[#B + 1] = { name = "fight area: barry and buck",
  steps = { { "until", varGe(0x4081, 2), 30000 } },
  expect = function(r) return r:var(0x4081) >= 2 and r:flag(0x294) end, why = "0x4081 >= 2, flag 0x294",
  expectBudget = 8000 }

-- ROUTE 227 (R227; scripts_route_227.s). Coord 1 ((2..3,50) while
-- VAR_ROUTE_227_WAKE_RIVAL_STATE 0x408B == 0): Crasher Wake and Barry, 0x408B = 1
B[#B + 1] = { name = "route 227: wake and barry",
  steps = { { "teleport", "R227", 3, 53, "up" }, { "coord", 1 },
            { "until", varGe(0x408B, 1), 20000 } },
  expect = varGe(0x408B, 1), why = "0x408B >= 1", expectBudget = 8000 }

-- coord 2 ((22,21) while VAR_ROUTE_227_BUCK_STATE 0x4119 == 0): Buck asks the
-- player to patrol Stark Mountain (YES), 0x4119 = 1
--
-- RENEGADE PLATINUM moves Buck (person 11) up to (22,1) and the trigger to
-- (22,2..4) while 0x403D == 0: he BATTLES the player (trainer 1023: Torkoal,
-- Shuckle, Umbreon, Dusknoir, Cloyster, Claydol -- Surf), heals the party
-- and leaves (flag 0xA18, 0x403D = 1). Retail's patrol question is left
-- unreferenced, so 0x4119 stays 0 there (nothing in the hack reads it).
-- His trigger also checks SIX FLAGS first and, short of any, sends the
-- player back south ("did you manage to beat all six of the Battle Zone
-- leaders? ... Nope"): the hack's Battle Zone leaders, one per route, each
-- talked to, YES, beaten for an unofficial badge. They come first, each
-- with the move that its team cannot shrug off.
if renegade then
  local LEADERS = {
    -- route, leader (person), stand at, flag, move: Heather's flyers
    -- (Thunderbolt), Wyver's dragons (Ice Beam), Slythe's poisons
    -- (Psychic), Shade's darks (Thunderbolt: nothing immune, unlike
    -- Psychic and Aura Sphere), Gene's normals (Aura Sphere), Luna's
    -- fairies (Flash Cannon; the hack's chart has Steel 2x on Fairy)
    { "R225", 31, 9, 81, 0x8C9, 85, "Heather (Wind)" },
    { "W226", 16, 44, 26, 0x8CA, 58, "Wyver (Fang)" },
    { "R227", 13, 12, 25, 0x8CB, 94, "Slythe (Acid)" },
    -- (Shade's only open side is the east one, (23,84): faced from there)
    { "R228", 27, 23, 84, 0x908, 85, "Shade (Shadow)", face = "left" },
    { "R229", 19, 59, 23, 0x909, 396, "Gene (General)" },
    { "W230", 19, 56, 16, 0x8CE, 430, "Luna (Moon)" },
  }
  for _, l in ipairs(LEADERS) do
    B[#B + 1] = { name = "battle zone: " .. l[7], budget = 60000,
      steps = { { "do", fullTeam(l[6]) }, { "teleport", l[1], l[3], l[4], l.face or "up" },
                l.face and { "press", "a" } or { "talk", l[2], retarget = true },
                { "until", flag(l[5]), 50000 } },
      expect = flag(l[5]), why = ("flag 0x%X (%s's badge)"):format(l[5], l[7]), expectBudget = 8000 }
  end
  B[#B + 1] = { name = "route 227: buck",
    steps = { { "do", fullTeam(57) }, { "teleport", "R227", 19, 7, "up" }, { "coord", 2 },
              { "until", varGe(0x403D, 1), 60000 } },
    expect = function(r) return r:var(0x403D) >= 1 and r:flag(0xA18) end, why = "0x403D >= 1, flag 0xA18 (Buck beaten)",
    expectBudget = 8000 }
else
B[#B + 1] = { name = "route 227: buck",
  steps = { { "teleport", "R227", 22, 24, "up" }, { "answers", { 1 } }, { "coord", 2 },
            { "until", varGe(0x4119, 1), 20000 } },
  expect = varGe(0x4119, 1), why = "0x4119 >= 1", expectBudget = 8000 }
end

-- STARK MOUNTAIN (D16): coord 1 ((16,11) while VAR_STARK_MOUNTAIN_OUTSIDE_STATE
-- 0x40A0 == 0): two grunts run inside, 0x40A0 = 1
B[#B + 1] = { name = "stark mountain: the grunts",
  steps = { { "teleport", "D16", 16, 14, "up" }, { "coord", 1 },
            { "until", varGe(0x40A0, 1), 20000 } },
  expect = varGe(0x40A0, 1), why = "0x40A0 >= 1", expectBudget = 8000 }

-- the first room's frame table (VAR_STARK_MOUNTAIN_ROOM_1_STATE 0x40AD == 0):
-- Mars, then Jupiter (FLAG_DEFEATED_TRAINER_COMMANDER_JUPITER_STARK_MOUNTAIN
-- 0x8EF), Charon leaves with them; 0x40AD = 1
-- (RENEGADE's Jupiter brings Sableye, immune to Psychic, and Skuntank:
-- Flamethrower there, which nothing on either team is immune to)
B[#B + 1] = { name = "stark mountain: mars and jupiter", budget = 60000,
  steps = { { "do", fullTeam(renegade and 53 or 94) }, { "warpto", "D16R0101" },
            { "until", varGe(0x40AD, 1), 50000 } },
  expect = function(r) return r:var(0x40AD) >= 1 and trainerFlag(0x8EF)(r) end,
  why = "0x40AD >= 1, trainer flag 0x8EF (Jupiter)",
  expectBudget = 8000 }

-- the second room (D16R0102): coord 1 ((42,69) while
-- VAR_STARK_MOUNTAIN_ROOM_2_FOLLOWER_BUCK_STATE 0x4094 == 0) is Buck joining as
-- the partner (0x4094 = 1, FLAG_TALKED_TO_STARK_MOUNTAIN_ROOM_2_BUCK 0xDD);
-- coord 3 at the far door ((47,3), 0x4094 == 1) is his "here we are", 0x4094 = 2
-- THE WAY UP, walked with Buck trailing (found by an offline search over the
-- room's collision): east round to row 15, Rock Smash the rock at (41,15)
-- from its east side, west and up the left corridor to row 3, down column 23
-- to row 12, the Strength boulder at (29,12) pushed east along row 12 to
-- (48,12), and up column 47 to the far door
local starkPushes = {}
for bx = 30, 48 do starkPushes[#starkPushes + 1] = { "push", "right", bx, 12 } end
local starkRoom2 = { routeSteps(), { "do", hmMoves({ [3] = 70, [4] = 249 }) },
  { "teleport", "D16R0102", 42, 72, "up" }, { "coord", 1 },
  { "until", function(r) return r:var(0x4094) >= 1 and not r:busy() end, 20000 },
  { "walkto", 42, 15 }, { "smash", "left", 41, 15 }, { "walkto", 28, 12 } }
for _, st in ipairs(starkPushes) do starkRoom2[#starkRoom2 + 1] = st end
-- RENEGADE PLATINUM parks the room's rocks and boulders at (999,999): the
-- far door is simply walked to
if renegade then
  for _ = 1, 3 + #starkPushes do table.remove(starkRoom2, 6) end
end
starkRoom2[#starkRoom2 + 1] = { "coord", 3 }
starkRoom2[#starkRoom2 + 1] = { "until", varGe(0x4094, 2), 20000 }
B[#B + 1] = { name = "stark mountain: buck follows", budget = 150000,
  steps = starkRoom2,
  expect = function(r) return r:var(0x4094) >= 2 and r:flag(0xDD) end, why = "0x4094 >= 2, flag 0xDD",
  expectBudget = 8000 }

-- the third room's frame table (VAR_STARK_MOUNTAIN_ROOM_3_STATE 0x409E == 0):
-- Charon takes the Magma Stone, Looker and the police arrest him
-- (FLAG_ARRESTED_CHARON_STARK_MOUNTAIN 0xD6), 0x409E = 1, the warp outside;
-- outside, the frame table (VAR_STARK_MOUNTAIN_OUTSIDE_STATE 0x40A0 == 2) is
-- Looker and Buck's goodbye, 0x40A0 = 3
B[#B + 1] = { name = "stark mountain: charon",
  steps = { { "warpto", "D16R0103" }, { "until", varGe(0x40A0, 3), 40000 } },
  expect = function(r) return r:flag(0xD6) and r:var(0x409E) >= 1 and r:var(0x40A0) >= 3 end,
  why = "flag 0xD6, 0x409E >= 1, 0x40A0 >= 3", expectBudget = 8000 }

-- the Survival Area (T06): Buck (person 8, back since Charon's arrest) stands
-- at the Battleground's door and goes in when talked to (SurvivalArea_Buck);
-- inside (T06R0101) he is person 1 (FLAG_HIDE_BATTLEGROUND_BUCK cleared by the
-- arrest too), and talking to him is FLAG_TALKED_TO_BATTLEGROUND_BUCK 0x125,
-- which wakes Heatran
--
-- RENEGADE PLATINUM fills the Battleground with the gym leaders (person 1
-- is Marley, Buck is person 5) and moves the flag to the door: the room's
-- frame table (0x40C1 == 0) has the receptionist (person 0) meet the player
-- and sets 0x125 itself, so nobody is talked to inside
local battleground = { { "teleport", "T06", 12, 21, "up" }, { "talk", 8 },
            { "until", function(r) return not r:busy() and r:personAt(8):find("shown") == nil end, 8000 },
            { "warpto", "T06R0101" }, { "talk", 1 },
            { "until", flag(0x125), 20000 } }
if renegade then table.remove(battleground, 5) end
B[#B + 1] = { name = "battleground: buck",
  steps = battleground,
  expect = flag(0x125), why = "flag 0x125", expectBudget = 8000 }

-- back in the third room (0x409E == 1, the game completed, the National Dex,
-- Buck talked to): Heatran (person 1, StartLegendaryBattle SPECIES_HEATRAN 50);
-- FLAG_BATTLED_STARK_MOUNTAIN_ROOM_3_HEATRAN 0xD7, 0x409E = 2
B[#B + 1] = { name = "stark mountain: heatran", budget = 60000,
  steps = { { "do", fullTeam(57) }, { "teleport", "D16R0103", 7, 15, "up" }, { "talk", 1 },
            { "until", function(r) return r:flag(0xD7) and r:var(0x409E) >= 2 and not r:busy() end, 50000 } },
  expect = function(r) return r:flag(0xD7) and r:var(0x409E) >= 2 end, why = "flag 0xD7, 0x409E >= 2",
  expectBudget = 8000 }

return B