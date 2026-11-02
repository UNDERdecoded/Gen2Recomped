-- src/script/Gen5Stadium.lua -- BIG STADIUM AND SMALL COURT, RUN.
--
-- Nimbasa's two sports venues (lobbies Z079 / Z084, the fields Z081-Z083
-- Big Stadium and Z086-Z087 Small Court) dress their athletes on every load
-- from the cartridge's table (/a/2/0/9, src/import/Gen5Facilities.lua ->
-- constants.gen5Stadium). The field's init script (each zone's entry 1)
-- does, with the commands below:
--
--   0x1F4 / 0x1F5        load / free the table (ov10 0x0215F2F0 / 0x0215F318)
--   0x25C <var x6>       six distinct visitors, rows 55..106 (0x0215F52C):
--                        drawn once, while all six vars are 0
--   0x1F6 <slot, obj, tier>        object `obj` fights as trainer t of row
--                                  (slot, tier): its script becomes 3000 + t
--                                  (ov10 0x0215F33C -> 0x02162788)
--   0x1F3 <slot, objA, objB, tier> a pair: objA 3000 + t, objB 5000 + t, the
--                                  double battle's two halves (0x0215F3A4)
--   0x1F7 <obj x3, row x3>         three visitors by row index, sprite and
--                                  script both (0x0215F424 -> 0x02162774 the
--                                  sprite, 0x02162788 the script)
--   0x1F8                          every row's trainer flag cleared -- the
--                                  lobby runs it once a day (flag 2745)
--
-- and from the lobby, the clock: 0x0CF <var> the weekday (0 Sunday; the RTC
-- record's +0x10, ov10 0x021690F0) picks the sport, 0x0D1 <hour, minute>
-- (+0x14 / +0x18, 0x02169100 / 0x02169110) whether a game is on.
--
-- A "script" here is what the object's template carries: the shared trainer
-- file (band 3000 / 5000, member 863) reads the trainer from the object's own
-- script id, which this port keeps on the def as `trainer = { id, battler }`
-- (Gen4Commands' trainerOnObject / trainerBattlerIndex). The template is
-- rewritten in place, as the cartridge rewrites its loaded copy, and the live
-- object rebuilt so its sprite and talk follow.
--
-- Loaded by Gen4ScriptVM (its last lines call `install` with the lowering
-- table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}

-- the lobby's once-a-day flag (Z079 / Z084: `if !flag 0xAB9 { 1F4 1F8 1F5;
-- setflag 0xAB9; vars 0x411F..0x4124 = 0 }`) -- a daily flag the cartridge
-- clears at midnight
M.DAILY_FLAG = 0xAB9
M.VISITOR_VARS = { 0x411F, 0x4120, 0x4121, 0x4122, 0x4123, 0x4124 }
-- ov10 0x0215A500: the trainer flag a row's trainer is beaten by
M.TRAINER_FLAG_BASE = 0x58C

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return G4().valueOf(ctx, n) end
local function setVar(ctx, n, v)
  n = tonumber(n)
  if n and n >= 0x4000 then G4().setVar(ctx.save, n, math.floor(tonumber(v) or 0) % 65536) end
end

function M.rec(data)
  local r = data and data.constants and data.constants.gen5Stadium
  return type(r) == "table" and r or nil
end

-- ov10 0x0215F608: the row whose slot and tier match (row 0 when none does)
function M.find(rec, slot, tier)
  for i = 0, (rec.count or 107) - 1 do
    local r = rec.rows[i]
    if r and r.slot == slot and r.tier == tier then return r, i end
  end
  return rec.rows[0], 0
end

-- ------------------------------------------------------------ the clock --

local function clock()
  local fake = os.getenv and os.getenv("BW_CLOCK")   -- "wday:hour:min" (harness)
  if fake then
    local w, h, m = fake:match("(%d+):(%d+):(%d+)")
    if w then return { wday = tonumber(w) + 1, hour = tonumber(h), min = tonumber(m) } end
  end
  return os.date("*t")
end
M.clock = clock

-- the cartridge clears its daily flags when the clock passes midnight; here
-- the venue's own flag is cleared the first time the lobby asks the clock on
-- a new day (an absolute day count, so a week away is still "a new day")
function M.dailyTick(ctx)
  local save = ctx.save
  if not save then return end
  local t = clock()
  local day = require("src.script.Gen4Daily").civilDay(t)
  save.gen5Facilities = save.gen5Facilities or {}
  local f = save.gen5Facilities
  if f.stadiumDay ~= day then
    if f.stadiumDay ~= nil then
      Commands.clear_flag(ctx, ("FLAG_G4_%04X"):format(M.DAILY_FLAG))
      Logger.info("bw stadium: a new day -- the venues' daily flag cleared")
    end
    f.stadiumDay = day
  end
end

-- ----------------------------------------------------------- the objects --

local function sheetFor(data, here, graphicsId)
  for _, o in ipairs(here and here.objects or {}) do
    if o.graphicsId == graphicsId and o.sprite then return o.sprite, o.spriteName end
  end
  for _, def in pairs(data and data.maps or {}) do
    for _, o in ipairs(type(def) == "table" and def.objects or {}) do
      if o.graphicsId == graphicsId and o.sprite then return o.sprite, o.spriteName end
    end
  end
  -- (an id no map places: the sprite table itself)
  return require("src.script.Gen4Commands").bwSpriteFromTable(data, graphicsId)
end

-- the template at position `slot` (0-based) of the loaded zone
local function template(ctx, slot)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  for i, o in ipairs(def and def.objects or {}) do
    if (o.index or i) == slot + 1 then return o, def end
  end
  return nil, def
end

-- the shared trainer file's label for trainer t (band 3000's member: every
-- trainer shares one script, so this is the label the object already wears)
local function trainerLabel(data, script)
  local VM = require("src.script.Gen4ScriptVM")
  local pool = VM.store and VM.store(data) or (data and data.map_scripts)
  local bandName = script >= 5000 and "double_battles" or "single_battles"
  local band = pool and pool.bands and pool.bands[bandName]
  local entry = script - (script >= 5000 and 5000 or 3000)
  return band and band.entries and band.entries[entry + 1] or nil
end

-- rewrite object `slot`'s template: script (a trainer's battle) and / or
-- graphics id, then rebuild the live object from it
function M.setObject(ctx, slot, script, graphicsId)
  local obj, here = template(ctx, slot)
  if not obj then return false end
  local data = ctx.game and ctx.game.data
  obj.gen5StadiumOriginal = obj.gen5StadiumOriginal or {
    script = obj.script, trainer = obj.trainer, graphicsId = obj.graphicsId,
    sprite = obj.sprite, spriteName = obj.spriteName, text = obj.text,
  }
  if script then
    obj.script = script
    if script >= 3000 and script < 7000 then
      local t = script - (script >= 5000 and 5000 or 3000)
      obj.trainer = { id = t, battler = script >= 5000 and 1 or 0 }
      obj.scriptBand = script >= 5000 and "double_battles" or "single_battles"
      local label = trainerLabel(data, script)
      if label then obj.text = label end
    end
  end
  if graphicsId and graphicsId ~= obj.graphicsId then
    local sprite, name = sheetFor(data, here, graphicsId)
    obj.graphicsId = graphicsId
    if sprite then obj.sprite, obj.spriteName, obj.noSprite = sprite, name, nil end
  end
  Logger.info("bw stadium: object %d -> script %s (trainer %s), sprite %s", slot, tostring(obj.script),
              tostring(obj.trainer and obj.trainer.id), tostring(obj.graphicsId))
  M.refresh(ctx, obj)
  return true
end

-- the live object, rebuilt from its rewritten template where it stands
function M.refresh(ctx, obj)
  local ow = ctx.overworld
  if not (ow and ow.npcs and ow.map) then return end
  local OW = require("src.world.OverworldController")
  local mapId = ow.map.id
  for i, npc in ipairs(ow.npcs) do
    if npc.def and npc.def.index == obj.index and npc.id == (mapId .. "_obj_" .. obj.index) then
      if ow.npcPool then ow.npcPool[npc.id] = nil end
      local ok, fresh = pcall(OW.pooledNPC, ow.npcPool or {}, ctx.game.data, mapId, obj)
      if ok and fresh and fresh ~= npc then
        fresh.cellX, fresh.cellY, fresh.px, fresh.py = npc.cellX, npc.cellY, npc.px, npc.py
        fresh.facing, fresh.hidden = npc.facing, npc.hidden
        ow.npcs[i] = fresh
        for j, e in ipairs(ow.entities or {}) do
          if e == npc then ow.entities[j] = fresh end
        end
      end
      return
    end
  end
end

-- ------------------------------------------------------------- commands --

function Commands.g5_stadium_load(ctx) local _ = ctx end   -- 0x1F4: the table is in constants
function Commands.g5_stadium_free(ctx)                    -- 0x1F5: and the objects shown as flagged
  local ow = ctx.overworld
  if ow and ow.syncObjectVisibility then pcall(ow.syncObjectVisibility, ow) end
end

-- 0x1F6 <slot, object, tier>
function Commands.g5_stadium_single(ctx, slot, object, tier)
  local rec = M.rec(ctx.game and ctx.game.data)
  if not rec then return end
  local row = M.find(rec, valueOf(ctx, slot), valueOf(ctx, tier))
  M.setObject(ctx, valueOf(ctx, object), rec.singleBase + row.trainer)
end

-- 0x1F3 <slot, objectA, objectB, tier>
function Commands.g5_stadium_double(ctx, slot, a, b, tier)
  local rec = M.rec(ctx.game and ctx.game.data)
  if not rec then return end
  local row = M.find(rec, valueOf(ctx, slot), valueOf(ctx, tier))
  M.setObject(ctx, valueOf(ctx, a), rec.singleBase + row.trainer)
  M.setObject(ctx, valueOf(ctx, b), rec.doubleBase + row.trainer)
end

-- 0x1F7 <obj, obj, obj, row, row, row>
function Commands.g5_stadium_visitors(ctx, o1, o2, o3, r1, r2, r3)
  local rec = M.rec(ctx.game and ctx.game.data)
  if not rec then return end
  local objs, rows = { o1, o2, o3 }, { r1, r2, r3 }
  for k = 1, 3 do
    local row = rec.rows[valueOf(ctx, rows[k])]
    if row then M.setObject(ctx, valueOf(ctx, objs[k]), rec.singleBase + row.trainer, row.sprite) end
  end
end

-- 0x1F8: every row's trainer beaten flag cleared
function Commands.g5_stadium_reset(ctx)
  local rec = M.rec(ctx.game and ctx.game.data)
  local flags = ctx.save and ctx.save.gen4TrainerFlags
  if not (rec and flags) then return end
  local n = 0
  for i = 0, (rec.count or 107) - 1 do
    local r = rec.rows[i]
    if r and flags[r.trainer] then flags[r.trainer] = nil n = n + 1 end
  end
  Logger.info("bw stadium: the day's athletes reset (%d had been beaten)", n)
end

-- 0x25C <var x6>: six distinct of the 52 visitor rows (ov10 0x0215F52C)
local function rand(n) return (love and love.math and love.math.random(0, n - 1)) or math.random(0, n - 1) end
function Commands.g5_stadium_draw(ctx, ...)
  local rec = M.rec(ctx.game and ctx.game.data)
  local first, count = rec and rec.visitorFirst or 0x37, rec and rec.visitorCount or 0x34
  local picked, vars = {}, { ... }
  for k = 0, 5 do
    local r = rand(count - k)
    local v = 0
    -- walk 0..count-1, skipping those taken, until r more are passed
    while true do
      local taken = false
      for _, p in ipairs(picked) do if p == v then taken = true end end
      if not taken then
        if r == 0 then break end
        r = r - 1
      end
      v = v + 1
    end
    picked[#picked + 1] = v
    setVar(ctx, vars[k + 1], v + first)
  end
end

-- 0x0CF <var>: the weekday, 0 Sunday
function Commands.g5_weekday(ctx, dest)
  M.dailyTick(ctx)
  setVar(ctx, dest, (clock().wday or 1) - 1)
end
-- 0x0D1 <hour var, minute var>
function Commands.g5_time(ctx, hourVar, minVar)
  local t = clock()
  setVar(ctx, hourVar, t.hour or 0)
  setVar(ctx, minVar, t.min or 0)
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwstadiumload = function(_, s) emit(s, { "g5_stadium_load" }) end
  L.bwstadiumfree = function(_, s) emit(s, { "g5_stadium_free" }) end
  L.bwstadiumsingle = function(ins, s) emit(s, { "g5_stadium_single", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwstadiumdouble = function(ins, s) emit(s, { "g5_stadium_double", ins.args[1], ins.args[2], ins.args[3], ins.args[4] }) end
  L.bwstadiumvisitors = function(ins, s)
    local a = ins.args
    emit(s, { "g5_stadium_visitors", a[1], a[2], a[3], a[4], a[5], a[6] })
  end
  L.bwstadiumreset = function(_, s) emit(s, { "g5_stadium_reset" }) end
  L.bwstadiumdraw = function(ins, s)
    local a = ins.args
    emit(s, { "g5_stadium_draw", a[1], a[2], a[3], a[4], a[5], a[6] })
  end
  L.bwweekday = function(ins, s) emit(s, { "g5_weekday", ins.args[1] }) end
  L.bwtime = function(ins, s) emit(s, { "g5_time", ins.args[1], ins.args[2] }) end
end

return M
