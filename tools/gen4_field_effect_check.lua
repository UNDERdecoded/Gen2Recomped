-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- TWO INFINITE SCRIPT LOOPS, AND A COMMAND THE PORT ALREADY HAD.
--
-- Four rows had subjects naming the MAP THEY APPEAR ON rather than what they
-- do: "a Spear Pillar effect" (18C and 20D), "a Spear Pillar cue" (2FB), "an
-- Iron Island cue" (2B6). Named that way they read as unimplementable
-- set-pieces, and they were never even in the declined-subject census -- the
-- scan read `L.name =` and not `L["name"] =`, and all four use the bracket
-- form because their opcodes have no name. Pass 181 closed that; this is what
-- was behind it.
--
-- **18C is `MapObject_TryFace`.** `ScrCmd_18C` resolves a local id and calls
-- `ov5_021ECDFC(mapObj, dir)`, which is `MapObject_TryFace` plus a shadow
-- nudge for an object mid-jump -- "turn this object to face a direction".
-- `ScrCmd_FaceTargetObject` and `trainer_encounter.c` call the same function,
-- so the port already does this under another name. Fifteen sites.
--
-- **20D WAS A HANG.** `ov6_02243004` is a ten-mode switch over one overlay-6
-- field effect. Eight modes start or stop something and fall through to
-- `return 0`; exactly two -- 1 and 6 -- are completion polls reading a staged
-- animation's state counter:
--
--     case 1: if (ov6_0223E708(Unk)) { ov6_0223E700(Unk); return 1; } else return 0;
--     case 6: if (ov6_0223FCF4(Unk) == 6) { ov6_0223FCE0(Unk); return 1; } else return 0;
--
-- and the scripts poll them in a BACKWARDS JUMP. `g4_no_feature` writes 0, so
-- "not finished" was the permanent answer and the script span on the spot.
--
-- Section 2 does not take that on trust: it walks the cartridge, finds every
-- `20d` site, and asserts that each poll-mode site really is followed by a
-- compare-against-zero and a backwards `gotoif`. The hang is derived from the
-- ROM rather than from this comment.
--
-- THE REASON NOBODY LOOKED is worth keeping: the stub was RIGHT for eight of
-- the ten modes, because the cartridge writes 0 there too. A row that behaves
-- correctly almost everywhere is the hardest kind to doubt.
--
-- (Named for the mechanism, not the map: calling this file
-- gen4_spear_pillar_check.lua would have repeated in the check the
-- exact mistake the four rows it grades were suffering from.)
--
-- Run:  texlua tools/gen4_field_effect_check.lua <rom> [pokeplatinum] [cache dir]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local ROM   = arg and arg[1]
local PRET  = arg and arg[2]
local CACHE = arg and arg[3]

local fails, checks, reports, skips = 0, 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function skip(fmt, ...)
  skips = skips + 1
  io.write("SKIP: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  if not p then return nil end
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function loadTable(dir, name)
  if not dir then return nil end
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if not f then return nil end
  local okRun, t = pcall(f)
  return okRun and t or nil
end
local function code(src)
  if not src then return "" end
  return (src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " "))
end
local function cdefn(src, name)
  return src and src:match("[%w_%*%s]-" .. name .. "%s*%b()%s*\n{(.-)\n}")
end

local drawn = {}
love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end,
               newCanvas = function() return nil end,
               newImage = function() return nil end,
               setColor = function() end, rectangle = function() end,
               push = function() end, pop = function() end,
               setFont = function() end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
  image = { newImageData = function() return nil end },
  math = { random = math.random },
}

local GameVersion = require("src.core.GameVersion")
GameVersion.set("platinum")
local Commands = require("src.script.Commands")
local Gen4Commands = require("src.script.Gen4Commands")

ok(type(Commands.g4_field_effect) == "function",
   "g4_field_effect has no handler, so scrcmd 20D reaches nothing")
ok(type(Commands.g4_face_dir) == "function",
   "g4_face_dir has no handler, so scrcmd 18C reaches nothing")
ok(type(Gen4Commands.getVar) == "function"
   and type(Gen4Commands.setVar) == "function",
   "Gen4Commands does not publish getVar/setVar, so every assertion below "
   .. "would read nil and pass for the wrong reason")

local DEST = 0x4000
local SEED = 0x5A5A   -- neither 1 nor 0: a var nobody wrote also reads 0, and
                      -- 0 is a legitimate answer for eight of the ten modes
local function freshCtx()
  local ctx = { save = {} }
  ctx.game = { save = ctx.save }
  Gen4Commands.setVar(ctx.save, DEST, SEED)
  return ctx
end
local function answered(ctx)
  local v = Gen4Commands.getVar(ctx.save, DEST)
  if v == SEED then return "nothing -- the var was never written" end
  return tostring(v)
end

-- ---------------------------------------------------------------------------
section("1. the ten modes, and the two that are polls")
-- ---------------------------------------------------------------------------
-- NEEDS NOTHING but the repository, so this check has something that can fail
-- with no cache, no pret and no cartridge.
local POLLS = { [1] = true, [6] = true }
do
  for mode = 0, 9 do
    local ctx = freshCtx()
    Commands.g4_field_effect(ctx, mode, DEST)
    local want = POLLS[mode] and 1 or 0
    ok(Gen4Commands.getVar(ctx.save, DEST) == want,
       "mode %d answered %s, not %d -- `ov6_02243004` returns 1 only from "
       .. "case 1 and case 6 and falls through to `return 0` everywhere else",
       mode, answered(ctx), want)
  end
  -- BOTH DIRECTIONS, which is the half an implementation can get wrong by
  -- answering 1 to everything: eight modes must still be 0, and a port that
  -- "fixed the hang" by always answering 1 would tell the Spear Pillar
  -- sequence that an effect it had only just started was already over.
  local ones, zeros = 0, 0
  for mode = 0, 9 do
    local ctx = freshCtx()
    Commands.g4_field_effect(ctx, mode, DEST)
    if Gen4Commands.getVar(ctx.save, DEST) == 1 then ones = ones + 1
    else zeros = zeros + 1 end
  end
  ok(ones == 2 and zeros == 8,
     "%d mode(s) answer 1 and %d answer 0; the cartridge has exactly two "
     .. "polls and eight starts/stops", ones, zeros)
  -- OUT OF RANGE. pret's `default:` is `GF_ASSERT(FALSE)`, so there is no
  -- behaviour to copy -- but it must not be a poll answer, and it must not
  -- raise.
  for _, mode in ipairs({ -1, 10, 255 }) do
    local ctx = freshCtx()
    local okCall = pcall(Commands.g4_field_effect, ctx, mode, DEST)
    ok(okCall, "mode %d raised; the cartridge asserts but does not crash the "
               .. "script VM", mode)
    ok(Gen4Commands.getVar(ctx.save, DEST) == 0,
       "mode %d answered %s; outside the switch the answer is 0", mode,
       answered(ctx))
  end
  -- THE MODE IS A LITERAL BYTE, not a var (`ScriptContext_ReadByte`). A
  -- handler that put it through `valueOf` would still pass every assertion
  -- above, because 0..9 resolve to themselves -- so this asserts the thing
  -- that would actually break: a var id must NOT be dereferenced into a mode.
  do
    local ctx = freshCtx()
    Gen4Commands.setVar(ctx.save, 0x4010, 1)   -- a var holding poll mode 1
    Commands.g4_field_effect(ctx, 0x4010, DEST)
    ok(Gen4Commands.getVar(ctx.save, DEST) == 0,
       "handing 0x4010 as the mode answered %s; the operand is a literal byte "
       .. "and 0x4010 is not a mode, so resolving it as a var would make the "
       .. "effect's identity depend on unrelated script state", answered(ctx))
  end
end

-- ---------------------------------------------------------------------------
section("2. the hang, derived from the cartridge rather than described")
-- ---------------------------------------------------------------------------
if not ROM then
  skip("no cartridge path, so the poll loops are not re-derived this run")
else
  local Script = require("src.import.Gen4Script")
  local NdsRom = require("src.import.NdsRom")
  local Narc   = require("src.import.NarcArchive")
  local rom = NdsRom.open(ROM)
  ok(rom ~= nil, "could not open %s", tostring(ROM))
  local arc = rom and Narc.parse(rom:read("/fielddata/script/scr_seq.narc"))
  ok(arc ~= nil, "no /fielddata/script/scr_seq.narc in the cartridge")
  if arc then
    -- every distinct `20d` site, with the three instructions after it
    local sites, seenSite = {}, {}
    for m = 0, arc.count - 1 do
      local bytes = arc:get(m)
      if bytes and #bytes >= 6 then
        local queue, seen = {}, {}
        for _, at in ipairs(Script.entries(bytes)) do
          if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
        end
        local i = 1
        while i <= #queue do
          local at = queue[i]; i = i + 1
          local ins = Script.decode(bytes, at)
          for k, op in ipairs(ins) do
            if op.target and not seen[op.target] then
              seen[op.target] = true; queue[#queue + 1] = op.target
            end
            if op.name == "20d" then
              local key = m .. ":" .. tostring(op.at)
              if not seenSite[key] then
                seenSite[key] = true
                sites[#sites + 1] = { band = m, at = op.at,
                                      mode = (op.args or {})[1],
                                      a = ins[k + 1], b = ins[k + 2] }
              end
            end
          end
        end
      end
    end
    -- A FLOOR ON THE SEARCH ITSELF, because a decoder change that stopped
    -- finding `20d` would make every assertion below vacuous and report clean.
    ok(#sites == 4,
       "found %d distinct 20D site(s); the cartridge has four -- band 236 "
       .. "modes 0 and 1, band 237 modes 4 and 6", #sites)
    local polls, loops = 0, 0
    for _, s in ipairs(sites) do
      if POLLS[s.mode] then
        polls = polls + 1
        -- the shape that makes a 0 fatal: compare the destination against 0,
        -- then jump BACKWARDS if it matched
        local cmp = s.a and s.a.name
        local jmp = s.b
        -- The jump target is the `20d` ITSELF, not merely some earlier
        -- address: 20D is 5 bytes, the compare 6 and the gotoif 7, and the
        -- operand is -18, so target = at + 11 + 7 - 18 = at. Asserting
        -- equality rather than "backwards" is the stronger statement, and it
        -- is the one that says this is a poll loop rather than a jump that
        -- happens to go up.
        local back = jmp and jmp.target and jmp.target == s.at
        ok(cmp == "comparevartovalue" and (s.a.args or {})[2] == 0,
           "band %d's poll (mode %d) is not followed by a compare against 0 "
           .. "(found %s); if the shape has changed, re-read why mode %d "
           .. "must answer 1", s.band, s.mode, tostring(cmp), s.mode)
        ok(jmp and jmp.name == "gotoif" and back,
           "band %d's poll (mode %d) is not followed by a gotoif back to the "
           .. "poll itself (found %s -> %s, poll at %s), so this check can no "
           .. "longer show that answering 0 loops for ever", s.band, s.mode,
           tostring(jmp and jmp.name), tostring(jmp and jmp.target),
           tostring(s.at))
        if back then loops = loops + 1 end
      end
    end
    ok(polls == 2,
       "%d of the four 20D sites use a poll mode; the cartridge uses mode 1 "
       .. "once and mode 6 once", polls)
    ok(loops == 2,
       "%d poll site(s) are jumped back to by their own gotoif; both are, and "
       .. "that is why the "
       .. "old `g4_no_feature` lowering was a hang rather than a cosmetic gap",
       loops)
    report("4 20D sites: %s", (function()
      local t = {}
      for _, s in ipairs(sites) do
        t[#t + 1] = ("band %d mode %s%s"):format(s.band, tostring(s.mode),
                                                 POLLS[s.mode] and " (poll)" or "")
      end
      table.sort(t)
      return table.concat(t, ", ")
    end)())
    -- AND THE SAME WALK CONFIRMS 18C's REACH, so section 3's claim about
    -- fifteen sites is measured and not remembered.
    local faceSites, faceDirs, facePlayer = 0, {}, 0
    for m = 0, arc.count - 1 do
      local bytes = arc:get(m)
      if bytes and #bytes >= 6 then
        local queue, seen, counted = {}, {}, {}
        for _, at in ipairs(Script.entries(bytes)) do
          if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
        end
        local i = 1
        while i <= #queue do
          local at = queue[i]; i = i + 1
          for _, op in ipairs(Script.decode(bytes, at)) do
            if op.target and not seen[op.target] then
              seen[op.target] = true; queue[#queue + 1] = op.target
            end
            if op.name == "18c" and op.at and not counted[op.at] then
              counted[op.at] = true
              faceSites = faceSites + 1
              faceDirs[(op.args or {})[2]] = true
              if (op.args or {})[1] == 0xFF then facePlayer = facePlayer + 1 end
            end
          end
        end
      end
    end
    ok(faceSites == 15, "found %d distinct 18C site(s), not 15", faceSites)
    local dirs = 0
    for _ in pairs(faceDirs) do dirs = dirs + 1 end
    ok(dirs == 4,
       "18C's sites use %d distinct direction(s); all four of DIR_NORTH, "
       .. "SOUTH, WEST and EAST appear, so none of the four mappings is "
       .. "untravelled", dirs)
    ok(facePlayer > 0,
       "no 18C site names LOCALID_PLAYER (0xFF), so the player arm of "
       .. "`objectById` is never exercised by this command")
    report("15 18C sites, %d of them on LOCALID_PLAYER, all four directions "
           .. "used", facePlayer)
  end
end

-- ---------------------------------------------------------------------------
section("3. facing, through the resolver the rest of the port uses")
-- ---------------------------------------------------------------------------
do
  -- DIR_NORTH 0, DIR_SOUTH 1, DIR_WEST 2, DIR_EAST 3 (include/constants/
  -- map_object.h), which is the same table `Commands.g4_player_dir` already
  -- reads the other way round.
  local WANT = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
  for n, name in pairs(WANT) do
    local player = { facing = "down" }
    local npc = { facing = "down" }
    local ctx = { save = {} }
    ctx.overworld = { player = player, entities = { [3] = npc } }
    ctx.game = { save = ctx.save }
    Commands.g4_face_dir(ctx, 0xFF, n)
    ok(player.facing == name,
       "direction %d turned the player %s, not %s", n, tostring(player.facing),
       name)
  end
  -- AND IT MUST BE THE TABLE, not a second copy of it: the port's own
  -- `g4_player_dir` reads a facing name back out as a number, so round-tripping
  -- through both is the assertion that the two agree. A hand-typed inverse
  -- that disagreed on one entry would pass the four assertions above only if
  -- it were wrong in the same way twice.
  for n = 0, 3 do
    local player = { facing = "down" }
    local ctx = { save = {}, overworld = { player = player, entities = {} } }
    ctx.game = { save = ctx.save }
    Commands.g4_face_dir(ctx, 0xFF, n)
    Commands.g4_player_dir(ctx, DEST)
    ok(Gen4Commands.getVar(ctx.save, DEST) == n,
       "turning the player to %d and reading the direction back gave %s; the "
       .. "two directions of one mapping disagree", n,
       tostring(Gen4Commands.getVar(ctx.save, DEST)))
  end
  -- A BAD DIRECTION must leave the object alone rather than blanking it.
  do
    local player = { facing = "left" }
    local ctx = { save = {}, overworld = { player = player, entities = {} } }
    ctx.game = { save = ctx.save }
    local okCall = pcall(Commands.g4_face_dir, ctx, 0xFF, 9)
    ok(okCall, "direction 9 raised")
    ok(player.facing == "left",
       "direction 9 left the player facing %s; an out-of-range direction must "
       .. "not blank a facing", tostring(player.facing))
  end
  -- AN ABSENT OBJECT must be survivable: the cartridge GF_ASSERTs, which is
  -- not a behaviour to copy, but a mod or a mid-cutscene removal must not take
  -- the script down.
  do
    local ctx = { save = {}, overworld = { player = nil, entities = {} } }
    ctx.game = { save = ctx.save }
    ok(pcall(Commands.g4_face_dir, ctx, 7, 0),
       "facing a local id with no object raised")
  end
  -- AND A REAL LOCAL ID, so the player arm is not the only one tested.
  do
    local npc = { facing = "down" }
    local ctx = { save = {}, overworld = { player = { facing = "down" },
                                           entities = { npc } } }
    ctx.game = { save = ctx.save }
    npc.localId = 0
    Commands.g4_face_dir(ctx, 0, 3)
    ok(npc.facing == "right",
       "a local id turned the object to %s, not right -- only the "
       .. "LOCALID_PLAYER arm works", tostring(npc.facing))
  end
end

-- ---------------------------------------------------------------------------
section("4. the lowerings, and the two that are argued rather than deferred")
-- ---------------------------------------------------------------------------
do
  local src = code(slurp("src/script/Gen4ScriptVM.lua")
                     or slurp("../src/script/Gen4ScriptVM.lua"))
  ok(src ~= "", "could not read Gen4ScriptVM.lua, so section 4 graded nothing")
  local function row(name)
    return src:match('L%["' .. name .. '"%]%s*=%s*function.-\nend')
  end
  for name, verb in pairs({ ["18c"] = "g4_face_dir",
                            ["20d"] = "g4_field_effect" }) do
    local body = row(name)
    ok(body ~= nil, "`scrcmd %s` has no bracket-form lowering", name)
    if body then
      ok(body:find(verb, 1, true) ~= nil,
         "`scrcmd %s` does not lower onto %s", name, verb)
      ok(body:find("g4_no_feature") == nil and body:find("g4_noop") == nil,
         "`scrcmd %s` is still on a stub verb -- and for 20D that is an "
         .. "infinite loop, not a cosmetic gap", name)
      -- OPERAND ORDER, which the handler tests cannot see. Both commands take
      -- their operands in the order the cartridge reads them, and for 20D the
      -- first is the mode and the second the destination: swapped, the mode
      -- would be a var id and every poll would answer 0 again.
      local order = {}
      for n in body:gmatch("ins%.args%[(%d)%]") do order[#order + 1] = n end
      ok(table.concat(order, ",") == "1,2",
         "`scrcmd %s` forwards operands [%s], not [1,2]", name,
         table.concat(order, ","))
    end
  end
  -- THE TWO THAT STAY. A no-op is only honest while its reason is written
  -- down, so these assert the SUBJECT names the mechanism and not the map:
  -- "an Iron Island cue" is what hid scrcmd 2B6 for eleven passes.
  for name, want in pairs({ ["2b6"] = "solidity",
                            ["2fb"] = "child application" }) do
    local body = row(name)
    ok(body ~= nil, "`scrcmd %s` has no lowering", name)
    if body then
      ok(body:find("g4_noop", 1, true) ~= nil,
         "`scrcmd %s` is no longer a no-op; if it was implemented, this "
         .. "assertion is what needs rewriting", name)
      ok(body:find(want, 1, true) ~= nil,
         "`scrcmd %s`'s subject does not mention %q, so the census will rank "
         .. "it by where it appears rather than by what it does", name, want)
    end
  end
  -- AND NO ROW ANYWHERE STILL NAMES A MAP AS ITS SUBJECT for these four.
  ok(src:find("Spear Pillar effect") == nil
     and src:find("Spear Pillar cue") == nil
     and src:find("Iron Island cue") == nil,
     "a row still carries one of the map-named subjects; the census ranks on "
     .. "that prose, so the rename is the fix and not the comment above it")
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
