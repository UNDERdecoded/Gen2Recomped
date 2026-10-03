-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE TIP, WALKED AGAINST THE CARTRIDGE'S OWN ARITHMETIC.
--
-- Six Emerald moves turn the battler's sprite on its side -- FURY_ATTACK,
-- DOUBLE_EDGE, PECK, LOW_KICK, SKULL_BASH, ARM_THRUST -- and until now the
-- port drew none of it, because the only rotation it could read was
-- WITHDRAW's, whose task has one hardcoded shape.  The cartridge's general
-- one is an ACCUMULATOR with three modes and two front doors, and
-- `RomExtractorGen3:tipOffsets` turns one script call into the angles it
-- would produce.  This is what says it produces the right ones.
--
-- THE REFERENCE IS NOT THIS FILE'S OPINION. `tools/gen3_tip_ref.lua` was
-- computed from pokeemerald's own two setups, the step they share, and the
-- cartridge's gSineTable, for the real arguments of all ten calls read out of
-- the ROM's script table.
--
-- ...AND IT CARRIES BOTH SIDES, each run through the C on its own.  The port
-- emits the player's track and mirrors it at draw time, so a reference that
-- mirrored too would only prove the port mirrors the way the reference does.
-- Section 4 draws the enemy's side and compares it against a track the
-- reference never mirrored.
--
-- Usage: texlua tools/gen3_tip_check.lua
--    or: python tools/run_lua_check.py tools/gen3_tip_check.lua

package.path = "./?.lua;" .. package.path

-- LuaJIT HAS `bit` and its own is the one to use; texlua has not got it.
-- Preloading unconditionally would shadow the real one under
-- run_lua_check.py, which runs this on LOVE's LuaJIT.
if not pcall(require, "bit") then
  package.preload["bit"] = function()
    local function tou32(v) return math.floor(v) % 4294967296 end
    local function op(a, b, f)
      a, b = tou32(a), tou32(b)
      local r, m = 0, 1
      for _ = 1, 32 do
        r = r + f(a % 2, b % 2) * m
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
      end
      return r
    end
    local M = {}
    function M.band(a, b, ...) local r = op(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end)
      for _, c in ipairs({...}) do r = M.band(r, c) end return r end
    function M.bor(a, b, ...) local r = op(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end)
      for _, c in ipairs({...}) do r = M.bor(r, c) end return r end
    function M.bxor(a, b, ...) local r = op(a, b, function(x, y) return (x ~= y) and 1 or 0 end)
      for _, c in ipairs({...}) do r = M.bxor(r, c) end return r end
    function M.bnot(a) return 4294967295 - tou32(a) end
    function M.lshift(a, n) return tou32(tou32(a) * 2 ^ n) end
    function M.rshift(a, n) return math.floor(tou32(a) / 2 ^ n) end
    function M.arshift(a, n) return M.rshift(a, n) end
    function M.tobit(a) local v = tou32(a) return v >= 2147483648 and v - 4294967296 or v end
    function M.tohex(a) return ("%08x"):format(tou32(a)) end
    return M
  end
end

love = love or {
  filesystem = { getInfo = function() return nil end,
                 read = function() return nil end },
  graphics = { getWidth = function() return 240 end,
               getHeight = function() return 160 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local okReq, Rom = pcall(require, "src.import.RomExtractorGen3")
ok(okReq and type(Rom) == "table",
   "src.import.RomExtractorGen3 did not load: %s", tostring(Rom))
local okAnim, Anim = pcall(require, "src.battle.Gen3MoveAnim")
ok(okAnim and type(Anim) == "table",
   "src.battle.Gen3MoveAnim did not load: %s", tostring(Anim))
if not (okReq and type(Rom) == "table" and okAnim and type(Anim) == "table") then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local REF = dofile("tools/gen3_tip_ref.lua")
ok(type(REF) == "table" and type(REF.calls) == "table",
   "the reference fixture did not load")
ok(type(REF.sine) == "table" and REF.sine[0] == 0 and REF.sine[64] == 256
     and REF.sine[128] == 0 and REF.sine[192] == -256,
   "the fixture's sine table is not the cartridge's shape")

-- ---------------------------------------------------------------------------
section("1. the decoder exists, and its pins are the cartridge's")
-- ---------------------------------------------------------------------------
ok(type(Rom.tipOffsets) == "function", "tipOffsets is missing")
ok(type(Rom.monTip) == "function", "monTip is missing")
local T = Rom.MON_TIP
ok(type(T) == "table", "MON_TIP is missing")
if type(T) == "table" then
  -- the two helpers the step calls; without both it is some other step
  ok(T.ROTSCALE == 0x0A71B4, "SetSpriteRotScale is %s", tostring(T.ROTSCALE))
  ok(T.YOFFSET == 0x0A73A0,
     "SetBattlerSpriteYOffsetFromRotation is %s", tostring(T.YOFFSET))
  ok(T.TURN == 65536, "a whole turn is %s, not 65536", tostring(T.TURN))
  ok(T.STEPS == 256, "the sine is %s steps, not 256", tostring(T.STEPS))
  ok(T.SHIFT == 8, "the lift is |c| >> 3, so the divisor is 8, not %s",
     tostring(T.SHIFT))
  -- the instructions, each a whole halfword at a fixed offset in the step
  local pins = {
    { "SCALE_MOV", 0x1A, 0x2280 }, { "SCALE_LSL", 0x1C, 0x0052 },
    { "DELTA", 0x10, 0x8A20 }, { "ANGLE", 0x12, 0x89E1 },
    { "ACCUM", 0x14, 0x1840 }, { "STORE", 0x16, 0x81E0 },
    { "SIDE", 0x26, 0x2216 }, { "TICK", 0x36, 0x3001 },
    { "LIMIT", 0x3E, 0x220C }, { "REVERSE", 0x52, 0x2802 },
  }
  for _, p in ipairs(pins) do
    local got = T[p[1]]
    ok(type(got) == "table" and got.at == p[2] and got.op == p[3],
       "MON_TIP.%s pins %s/%s, not +0x%02X/%04X", p[1],
       tostring(got and got.at), tostring(got and got.op), p[2], p[3])
  end
  -- the pool scan has to reach the installed step: the plain entry is 124
  -- halfwords long and keeps the pointer at the far end of it
  ok((T.POOL_SCAN or 0) >= 120,
     "a pool scan of %s never reaches the step the plain entry installs",
     tostring(T.POOL_SCAN))
end

-- The shape the decoder is pure over: the two addresses and the cartridge's
-- sine. Reading those off the ROM is monTip's job and is checked by the
-- import; this is the decode.
local SHAPE = { plain = 0x0D6134, restore = 0x0D622C, step = 0x0D6308,
                sine = REF.sine, turn = 65536, source = "check" }

-- ---------------------------------------------------------------------------
section("2. every real call, frame for frame")
-- ---------------------------------------------------------------------------
local calls, frames = 0, 0
for _, want in ipairs(REF.calls) do
  calls = calls + 1
  local restoring = want.variant == "restore"
  local got = Rom.tipOffsets(Rom, want.args, SHAPE, restoring)
  local label = ("%s {%s}"):format(want.move, table.concat(want.args, ", "))
  if not got then
    ok(false, "%s: the decoder refused its own arguments", label)
  else
    local bad = nil
    if #got.angles ~= #want.player.angles then
      bad = ("%d frames, not %d"):format(#got.angles, #want.player.angles)
    else
      for i = 1, #want.player.angles do
        frames = frames + 1
        if got.angles[i] ~= want.player.angles[i] then
          bad = ("frame %d turns to %d and the cartridge turns to %d")
                :format(i, got.angles[i], want.player.angles[i])
          break
        end
        if got.rises[i] ~= want.player.rises[i] then
          bad = ("frame %d lifts %d and the cartridge lifts %d")
                :format(i, got.rises[i], want.player.rises[i])
          break
        end
      end
    end
    ok(bad == nil, "%s: %s", label, tostring(bad))
  end
end
io.write(("  %d calls, %d frames compared\n"):format(calls, frames))
ok(calls == 10, "the reference carries %d calls, not the ten in the ROM", calls)
ok(frames >= 100, "only %d frame(s) compared", frames)

-- ---------------------------------------------------------------------------
section("3. the record says which battler, which side, and which lift")
-- ---------------------------------------------------------------------------
for _, want in ipairs(REF.calls) do
  local restoring = want.variant == "restore"
  local got = Rom.tipOffsets(Rom, want.args, SHAPE, restoring)
  local label = ("%s {%s}"):format(want.move, table.concat(want.args, ", "))
  if got then
    ok((got.target == true) == (want.args[3] == 1),
       "%s: argument two is %d and the record says target=%s",
       label, want.args[3], tostring(got.target))
    -- both entries negate on side, so both tracks are the player's
    ok(got.authoredForPlayer == true,
       "%s: the track is not marked as the player's", label)
    ok((got.risesOnEnemy == true) == (want.risesOnEnemy == true),
       "%s: risesOnEnemy is %s and the %s entry %s lift the far side",
       label, tostring(got.risesOnEnemy), want.variant,
       want.risesOnEnemy and "does" or "does not")
    ok(got.life == #got.angles, "%s: life is %s for a %d-frame track",
       label, tostring(got.life), #got.angles)
    ok(got.turn == 65536, "%s: a whole turn is %s", label, tostring(got.turn))
    ok(#got.rises == #got.angles,
       "%s: %d angles but %d lifts", label, #got.angles, #got.rises)
    ok(got.task == (restoring and SHAPE.restore or SHAPE.plain),
       "%s: the record names task %s", label, tostring(got.task))
    -- mode 2 goes out and comes home; the other two stay where they stopped
    if want.args[4] == 2 then
      ok(got.angles[#got.angles] == 0,
         "%s is a mode-2 tip and ends at %d rather than upright",
         label, got.angles[#got.angles])
      ok(got.life == want.args[1] * 2,
         "%s is a mode-2 tip over %d frames and lives %d, not %d",
         label, want.args[1], got.life, want.args[1] * 2)
    else
      ok(got.life == want.args[1],
         "%s lives %d frames, not the %d its script asks for",
         label, got.life, want.args[1])
    end
  end
end

-- ---------------------------------------------------------------------------
section("4. the renderer turns BOTH sides the way the cartridge does")
-- ---------------------------------------------------------------------------
-- The import emits the player's track only. What the enemy's sprite does is
-- this renderer's arithmetic, and the reference it is held to here was run
-- through pokeemerald's C for the enemy separately -- never mirrored off the
-- player's -- so agreeing with it is agreeing with the cartridge.
ok(type(Anim.rotateTrackAt) == "function", "rotateTrackAt is missing")
ok(type(Anim.monRotate) == "function", "monRotate is missing")
local TWOPI = 2 * math.pi
local drawn = 0
for _, want in ipairs(REF.calls) do
  local restoring = want.variant == "restore"
  local track = Rom.tipOffsets(Rom, want.args, SHAPE, restoring)
  local label = ("%s {%s}"):format(want.move, table.concat(want.args, ", "))
  if track then
    track.at = 0
    -- Both ways round: the player uses the move, then the enemy does. Each
    -- time, the sprite the task turns is `battler`, and which side that is
    -- flips with the attacker.
    for _, scene in ipairs({
      { attackerIsPlayer = true,  rotatedIsPlayer = (want.args[3] ~= 1) },
      { attackerIsPlayer = false, rotatedIsPlayer = (want.args[3] == 1) },
    }) do
      local inst = setmetatable({
        rotateTracks = { track },
        attackerIsPlayer = scene.attackerIsPlayer,
        frame = 0,
      }, { __index = Anim })
      local side = scene.rotatedIsPlayer and want.player or want.enemy
      local who = scene.rotatedIsPlayer and "the player's" or "the enemy's"
      local bad = nil
      for i = 1, #side.angles do
        inst.frame = i - 1
        local angle, rise = inst:monRotate(scene.rotatedIsPlayer)
        local wantAngle = side.angles[i] / 65536 * TWOPI
        if side.angles[i] == 0 then
          -- monRotate declines a zero angle, and BattleState requires that:
          -- an upright sprite is no rotation, not a rotation of nothing
          if angle ~= nil then
            bad = ("frame %d returns an angle for an upright sprite"):format(i)
          end
        elseif angle == nil then
          bad = ("frame %d draws nothing and the cartridge turns to %d")
                :format(i, side.angles[i])
        elseif math.abs(angle - wantAngle) > 1e-9 then
          bad = ("frame %d turns %.6f rad and the cartridge turns %.6f")
                :format(i, angle, wantAngle)
        elseif (rise or 0) ~= side.rises[i] then
          bad = ("frame %d lifts %s and the cartridge lifts %d")
                :format(i, tostring(rise), side.rises[i])
        end
        if bad then break end
        drawn = drawn + 1
      end
      ok(bad == nil, "%s on %s side: %s", label, who, tostring(bad))
    end
  end
end
io.write(("  %d drawn frames compared across both sides\n"):format(drawn))
ok(drawn >= 150, "only %d drawn frame(s) compared", drawn)

-- ---------------------------------------------------------------------------
section("5. a rotation does not travel down the offset channel")
-- ---------------------------------------------------------------------------
-- THE RECURRING BUG in this port is one thing spelled two ways in two files
-- that never meet. The sway and the ellipse ride in `shakes` because they ARE
-- offsets; an angle in there would slide the sprite sideways by the angle's
-- magnitude -- thousands of pixels -- and never turn it.
for _, want in ipairs(REF.calls) do
  local got = Rom.tipOffsets(Rom, want.args, SHAPE, want.variant == "restore")
  if got then
    ok(got.xs == nil and got.ys == nil,
       "%s carries xs/ys, which `shakeAt` would read as an offset", want.move)
  end
end
local animSrc = io.open("src/battle/Gen3MoveAnim.lua", "rb")
local animText = animSrc and animSrc:read("*a") or ""
if animSrc then animSrc:close() end
ok(#animText > 0, "src/battle/Gen3MoveAnim.lua could not be read")
local importSrc = io.open("src/import/RomExtractorGen3.lua", "rb")
local importText = importSrc and importSrc:read("*a") or ""
if importSrc then importSrc:close() end
ok(#importText > 0, "src/import/RomExtractorGen3.lua could not be read")
ok(not importText:find("record%.shakes%s*=%s*[^\n]*rotateTracks"),
   "the import files the tip tracks into `shakes`")

-- ---------------------------------------------------------------------------
section("6. every place that has to know about the track knows")
-- ---------------------------------------------------------------------------
-- A field written by the import and read nowhere is the failure this port has
-- already shipped once. These are the four places `rotate` is handled, and
-- the track has to be handled in all of them or it is decoded and discarded.
-- The gate is checked INSIDE `hasVisual` rather than anywhere in the file:
-- the per-move load mentions `anim.rotateTracks` too, so a file-wide search
-- for it passes with the gate ripped out -- which is the same one-thing-two-
-- places bug this section exists to catch, in the check itself.
local gate = animText:match("local function hasVisual%(anim%)(.-)\nend")
ok(gate ~= nil, "hasVisual is not in src/battle/Gen3MoveAnim.lua any more")
ok(gate ~= nil and gate:find("rotateTracks") ~= nil,
   "hasVisual does not gate on the tip track, so a move whose only visual is "
     .. "a rotation falls through to the bare sound")

local plumbing = {
  { "the per-move load",                     "self%.rotateTracks%s*=%s*anim%.rotateTracks" },
  { "the duration walk",                     "extendTask%(track" },
  { "the teardown",                          "self%.rotateTracks%s*=%s*nil" },
  { "the draw",                              "rotateTrackAt" },
}
for _, p in ipairs(plumbing) do
  ok(animText:find(p[2]) ~= nil,
     "%s does not mention the tip track (no match for `%s`)", p[1], p[2])
end
-- ...and the import has to emit it at all
ok(importText:find("record%.rotateTracks%s*=") ~= nil,
   "the import never writes rotateTracks onto a move's record")
ok(importText:find("function RomExtractorGen3:monTip") ~= nil,
   "the import has no monTip")
ok(importText:find("function RomExtractorGen3:tipOffsets") ~= nil,
   "the import has no tipOffsets")

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
