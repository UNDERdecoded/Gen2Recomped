-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Runtime commands for the Gen2 script VM.
--
-- Gen2ScriptVM lowers ROM bytecode into ScriptRunner rows.  Most rows are
-- ordinary engine commands (show_text, set_flag, warp, ...); the handful that
-- have no Gen1 equivalent live here under a `g2_` prefix so they never collide
-- with the hand-ported vocabulary in data/scripts/.
--
-- The two that matter structurally are g2_call and g2_return: Gen2's `scall`
-- pushes a return address and `end` pops it, which ScriptRunner's flat program
-- counter has no notion of.  The compiler emits an explicit push/jump pair and
-- `end` becomes g2_return, so a script that is scall'd from three places still
-- exists once in the compiled row list.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen2Commands = {}

local function scriptVar(ctx)
  return ctx.g2Var or 0
end

-- A text const resolved to finished text, the way show_text would print it.
-- BattleState:say takes text that is already expanded, not a label.
local function resolvedText(ctx, textId)
  local data = ctx.game.data
  local text = data.text[textId]
  if not text and ctx.overworld then
    text = data:resolveText(ctx.overworld.map.def.label, textId)
  end
  text = text or textId
  if type(text) ~= "string" then return nil end
  return require("src.render.TextBox").substitute(ctx.game, text)
end

-- ---------------------------------------------------------------------------
-- control flow
-- ---------------------------------------------------------------------------

function Commands.g2_call(ctx, returnLabel)
  ctx.g2Stack = ctx.g2Stack or {}
  ctx.g2Stack[#ctx.g2Stack + 1] = returnLabel
end

function Commands.g2_return(ctx)
  local stack = ctx.g2Stack
  if stack and #stack > 0 then return table.remove(stack) end
  return "end"
end

-- Script_endifjustbattled: ends the script when it was re-entered straight
-- from a won battle rather than by talking to the trainer afterwards.
function Commands.g2_endifjustbattled(ctx)
  if ctx.justBattled then return "end" end
end

-- Script_checkjustbattled: the same re-entered-from-a-won-battle flag
-- g2_endifjustbattled reads, but as a branchable condition rather than an
-- early return.
function Commands.g2_check_just_battled(ctx)
  ctx.lastCheck = ctx.justBattled and true or false
  ctx.g2Var = ctx.lastCheck and 1 or 0
end

-- Script_variablesprite: wVariableSprites[slot] = sprite.  Object events whose
-- sprite byte is $F0 or more read the slot back, so any object already built
-- from that slot has to pick the new sheet up.
-- Named slots from SPRITE_VARS ($F0+); Copycat is $FB = slot 11
local VAR_SLOT_NAMES = {
  SPRITE_COPYCAT = 11,
  SPRITE_CONSOLE = 0,
  SPRITE_DOLL_1 = 1,
  SPRITE_DOLL_2 = 2,
  SPRITE_BIG_DOLL = 3,
  SPRITE_WEIRD_TREE = 4,
  SPRITE_OLIVINE_RIVAL = 5,
  SPRITE_AZALEA_ROCKET = 6,
  SPRITE_FUCHSIA_GYM_1 = 7,
  SPRITE_FUCHSIA_GYM_2 = 8,
  SPRITE_FUCHSIA_GYM_3 = 9,
  SPRITE_FUCHSIA_GYM_4 = 10,
  SPRITE_JANINE_IMPERSONATOR = 12,
}

-- Common target sprites by name → OverworldSprites index
-- (pret/pokegold constants/sprite_constants.asm)
local SPRITE_NAME_INDEX = {
  SPRITE_CHRIS = 1,
  SPRITE_CHRIS_BIKE = 2,
  SPRITE_GAMEBOY_KID = 3,
  SPRITE_SILVER = 4,
  SPRITE_COOLTRAINER_M = 0x23,
  SPRITE_COOLTRAINER_F = 0x24,
  SPRITE_BUG_CATCHER = 0x25,
  SPRITE_TWIN = 0x26,
  SPRITE_YOUNGSTER = 0x27,
  SPRITE_LASS = 0x28,
  SPRITE_TEACHER = 0x29,
  SPRITE_BEAUTY = 0x2A,
  SPRITE_ROCKER = 0x2C,
  SPRITE_POKEFAN_M = 0x2D,
  SPRITE_POKEFAN_F = 0x2E,
  SPRITE_GRAMPS = 0x2F,
  SPRITE_GRANNY = 0x30,
  SPRITE_ROCKET = 0x35,
  SPRITE_ROCKET_GIRL = 0x36,
  SPRITE_OFFICER = 0x43,
  SPRITE_SLOWPOKE = 0x45,
  SPRITE_GYM_GUIDE = 0x48,
  -- pokegold has no SPRITE_BUENA (she is Crystal-only), and $4A is BIKER.
  -- The Gold/Silver radio host wears the generic LASS sheet.
  SPRITE_BUENA = 0x28,
  -- $52, not $6D.  $6D is not a sprite constant at all; storing it in
  -- wVariableSprites is what left the revealed Sudowoodo as a placeholder.
  SPRITE_SUDOWOODO = 0x52,
  SPRITE_FRUIT_TREE = 0x5D,
}

local function resolveVarSlot(slot)
  if type(slot) == "number" then
    if slot >= 0xF0 then return slot - 0xF0 end
    return slot
  end
  if type(slot) == "string" then
    if VAR_SLOT_NAMES[slot] then return VAR_SLOT_NAMES[slot] end
    local n = tonumber(slot)
    if n then
      if n >= 0xF0 then return n - 0xF0 end
      return n
    end
    -- tonumber(nil, 16) raises; tonumber(nil) does not.  Test the match first.
    local tail = slot:match("^SPRITE_(%x+)$")
    local hex = tail and tonumber(tail, 16) or nil
    if hex and hex >= 0xF0 then return hex - 0xF0 end
  end
  return nil
end

local function resolveSpriteArg(sprite)
  if type(sprite) == "number" then return sprite end
  if type(sprite) == "string" then
    if SPRITE_NAME_INDEX[sprite] then return SPRITE_NAME_INDEX[sprite] end
    local n = tonumber(sprite)
    if n then return n end
    -- tonumber(nil, 16) raises; tonumber(nil) does not.  Test the match first.
    local tail = sprite:match("^SPRITE_(%x+)$")
    local hex = tail and tonumber(tail, 16) or nil
    if hex then return hex end
  end
  return sprite -- keep string name for NPC lookup
end

function Commands.g2_variablesprite(ctx, slot, sprite)
  slot = resolveVarSlot(slot)
  sprite = resolveSpriteArg(sprite)
  if not (ctx.save and slot ~= nil and sprite ~= nil) then return end
  ctx.save.gen2VarSprites = ctx.save.gen2VarSprites or {}
  ctx.save.gen2VarSprites[slot] = sprite
  local ow = ctx.overworld
  -- refreshVariableSprite is the whole job: it walks the NPC pool AND the live
  -- list and re-resolves every object bound to this slot.  A second loop used
  -- to sit here "to catch the rest", over `ow.map.npcs` -- a field that does
  -- not exist (NPCs live on the overworld as ow.npcs, never on the map), so it
  -- was dead from the day it was written and hid the fact that the real
  -- refresh only matched the SPRITE_VAR_nn spelling.
  if ow and ow.refreshVariableSprite then ow:refreshVariableSprite(slot) end
end

local COMPARE = {
  eq = function(a, b) return a == b end,
  ne = function(a, b) return a ~= b end,
  gt = function(a, b) return a > b end,
  lt = function(a, b) return a < b end,
}

function Commands.g2_compare(ctx, op, value)
  local fn = COMPARE[op]
  ctx.lastCheck = fn and fn(scriptVar(ctx), value or 0) or false
end

-- `iftrue` / `iffalse` do not read a comparison result in the ROM: they read
-- hScriptVar itself (`ldh a, [hScriptVar] / and a`).  The port models that
-- byte as ctx.g2Var and the branch as ctx.lastCheck, so every command that
-- WRITES the variable has to move the flag with it -- otherwise the branch
-- tests whatever the last checkevent left behind.  Prism's minecart NPC is
-- `writebyte 8 / .loop: playwaitsfx / addvar -1 / iftrue .loop`, a countdown
-- with nothing else in it to set a flag.
local function setScriptVar(ctx, value)
  value = value or 0
  ctx.g2Var = value
  ctx.lastCheck = value ~= 0
  return value
end
Gen2Commands.setScriptVar = setScriptVar

function Commands.g2_setvar(ctx, value)
  setScriptVar(ctx, value)
end

function Commands.g2_addvar(ctx, value)
  -- the ROM's `add [hl]` wraps in a byte
  setScriptVar(ctx, (scriptVar(ctx) + (value or 0)) % 256)
end

function Commands.g2_random(ctx, bound)
  setScriptVar(ctx, math.random(0, math.max((bound or 1) - 1, 0)))
end


-- Tiny persistent WRAM mirror. Keyed by the address the ROM used.
-- Only a handful of scripts need this (underground switches is the big one).
local function wram(ctx)
  local save = ctx.save
  if not save then return nil end
  save.g2Wram = save.g2Wram or {}
  return save.g2Wram
end

-- With no address, the halfword variable IS the address: Prism's
-- GetHalfwordVar returns hScriptHalfwordVar in hl, so `copyhalfwordvartovar`
-- is an indirect read of the byte it names (`writehalfword wFossilCaseCount /
-- copyhalfwordvartovar / sif >, FOSSIL_CASE_SIZE - 1`).
function Commands.g2_readmem(ctx, addr)
  local mem = wram(ctx)
  addr = addr or ctx.g2HalfwordVar
  setScriptVar(ctx, (mem and addr and mem[addr]) or 0)
end

function Commands.g2_writemem(ctx, addr)
  local mem = wram(ctx)
  addr = addr or ctx.g2HalfwordVar
  if mem and addr then mem[addr] = scriptVar(ctx) end
end

-- Script_comparevartobyte answers in the script variable itself, and the
-- values are NOT a sign: 0 is greater, 1 is less, 2 is equal (`cp [hl] /
-- ld a, 2 / jr z / sbc a`).
function Commands.g2_comparemem(ctx, addr)
  local mem = wram(ctx)
  local other = (mem and mem[addr]) or 0
  local v = scriptVar(ctx)
  -- and `sif true` after one tests the byte, not equality: 2 and 1 are both
  -- true, 0 (greater) is false
  setScriptVar(ctx, v == other and 2 or (v > other and 0 or 1))
end

-- Script_addbytetovar: the script variable plus the WRAM byte at an address.
function Commands.g2_addmem(ctx, addr)
  local mem = wram(ctx)
  setScriptVar(ctx, (scriptVar(ctx) + ((mem and mem[addr]) or 0)) % 256)
end

-- Script_multiplyvar: SimpleMultiply, except that `inc a / jr nz` makes an
-- operand of $ff two's-complement negate instead (`multiplyvar -1`, which is
-- how the mining script counts a step budget DOWN).
function Commands.g2_mulvar(ctx, by)
  by = tonumber(by) or 1
  if by == 0xFF or by == -1 then
    setScriptVar(ctx, (256 - scriptVar(ctx)) % 256)
  else
    setScriptVar(ctx, (scriptVar(ctx) * by) % 256)
  end
end

-- ---------------------------------------------------------------------------
-- Prism's script variable stack (ScriptVarStackOperation) and its second,
-- sixteen-bit variable (hScriptHalfwordVar).
--
-- The stack is how a Prism script holds a value across a `scall` or across
-- the arms of a conditional; the halfword is how it carries a pointer -- most
-- often a text pointer read out of a loaded array and handed to `jumptext -1`.
-- Both live for the length of one script run, exactly as the ROM's do: the
-- bytes are in WRAM the save never keeps.
-- ---------------------------------------------------------------------------
local function varStack(ctx)
  ctx.g2VarStack = ctx.g2VarStack or {}
  return ctx.g2VarStack
end

function Commands.g2_pushvar(ctx)
  local st = varStack(ctx)
  st[#st + 1] = scriptVar(ctx)
end

function Commands.g2_popvar(ctx)
  local st = varStack(ctx)
  local n = #st
  -- The ROM decrements its stack pointer and reads what is there; an empty
  -- stack reads whatever WRAM held, which is 0 on a fresh boot.
  setScriptVar(ctx, n > 0 and table.remove(st) or 0)
end

function Commands.g2_peekvar(ctx)
  local st = varStack(ctx)
  setScriptVar(ctx, st[#st] or 0)
end

function Commands.g2_swapvar(ctx)
  local st = varStack(ctx)
  local n = #st
  local top = n > 0 and st[n] or 0
  if n > 0 then st[n] = scriptVar(ctx) end
  setScriptVar(ctx, top)
end

local function halfword(ctx)
  ctx.g2HalfwordStack = ctx.g2HalfwordStack or {}
  return ctx.g2HalfwordStack
end

function Commands.g2_sethalfword(ctx, value)
  ctx.g2HalfwordVar = tonumber(value) or 0
  ctx.g2HalfwordText = nil
end

function Commands.g2_pushhalfword(ctx)
  local st = halfword(ctx)
  st[#st + 1] = { ctx.g2HalfwordVar or 0, ctx.g2HalfwordText }
end

function Commands.g2_pophalfword(ctx)
  local st = halfword(ctx)
  local top = #st > 0 and table.remove(st) or nil
  ctx.g2HalfwordVar = top and top[1] or 0
  ctx.g2HalfwordText = top and top[2] or nil
end

function Commands.g2_peekhalfword(ctx)
  local st = halfword(ctx)
  local top = st[#st]
  ctx.g2HalfwordVar = top and top[1] or 0
  ctx.g2HalfwordText = top and top[2] or nil
end

-- Script_addhalfwordtovar / Script_addhalfwordvartovar: halfword = base +
-- the script variable, where base is the literal operand or the halfword
-- itself.  Both write the HALFWORD, not the variable.
function Commands.g2_addhalfword(ctx, base)
  base = tonumber(base) or ctx.g2HalfwordVar or 0
  ctx.g2HalfwordVar = (base + scriptVar(ctx)) % 65536
  ctx.g2HalfwordText = nil
end

-- Script_addhalfwordtohalfwordvar adds a literal to the halfword.
function Commands.g2_addhalfwordvalue(ctx, value)
  ctx.g2HalfwordVar = ((ctx.g2HalfwordVar or 0) + (tonumber(value) or 0)) % 65536
  ctx.g2HalfwordText = nil
end

-- Script_copybytetohalfwordvar reads a WRAM byte into the halfword.
function Commands.g2_readmem16(ctx, addr)
  local mem = wram(ctx)
  ctx.g2HalfwordVar = (mem and mem[addr]) or 0
  ctx.g2HalfwordText = nil
end

-- ---------------------------------------------------------------------------
-- Prism's script arrays (Script_loadarray / GetScriptArrayPointer).
--
--   loadarray <ptr>, <entry size>   base, entry size, current entry
--   readarray <i>                   var      = [base + size * entry + i]
--   readarrayhalfword <i>           halfword = word at the same place
--
-- The current entry comes from the script variable at loadarray time (`and a /
-- jr z, .singularArray / ldh a, [hScriptVar]` -- a size of zero pins it to 0),
-- which is what makes one array serve a whole family of cases.  The bytes
-- themselves were read out of the ROM during extraction; where the entries are
-- text pointers, the extractor also carries the label for each, so
-- `readarrayhalfword 0 / jumptext -1` prints a real line.
-- ---------------------------------------------------------------------------
function Commands.g2_loadarray(ctx, array)
  if type(array) ~= "table" then ctx.g2Array = nil return end
  local size = tonumber(array.size) or 0
  ctx.g2Array = array
  ctx.g2ArraySize = size
  -- a singular array (entry size 0) always reads from entry 0
  ctx.g2ArrayEntry = size > 0 and scriptVar(ctx) or 0
end

local function arrayIndex(ctx, index)
  local array = ctx.g2Array
  if type(array) ~= "table" then return nil end
  return array, (ctx.g2ArraySize or 0) * (ctx.g2ArrayEntry or 0)
    + (tonumber(index) or 0)
end

function Commands.g2_readarray(ctx, index)
  local array, at = arrayIndex(ctx, index)
  setScriptVar(ctx, array and array.bytes and array.bytes[at + 1] or 0)
end

function Commands.g2_readarrayhalfword(ctx, index)
  local array, at = arrayIndex(ctx, index)
  if not array then
    ctx.g2HalfwordVar, ctx.g2HalfwordText = 0, nil
    return
  end
  -- the ROM reads a halfword at a BYTE offset; every real use indexes on an
  -- even boundary, and an odd one still has to answer something
  local bytes = array.bytes or {}
  local lo, hi = bytes[at + 1] or 0, bytes[at + 2] or 0
  ctx.g2HalfwordVar = lo + hi * 256
  local texts = array.texts
  local slot = at % 2 == 0 and (at / 2) + 1 or nil
  ctx.g2HalfwordText = slot and texts and texts[slot] or nil
  if ctx.g2HalfwordText == false then ctx.g2HalfwordText = nil end
end

-- `jumptext -1` / `writetext -1`: the line is whichever one the halfword
-- variable names.  With no label resolved the box would come up empty, so say
-- nothing rather than opening one.
function Commands.g2_show_halfword_text(ctx)
  local id = ctx.g2HalfwordText
  if not id then return end
  return Commands.show_text(ctx, id)
end

-- Script_toggleevent: CHECK_FLAG, then SET or RESET the other way.
function Commands.g2_toggle_flag(ctx, name)
  if not name then return end
  local Flags = require("src.script.Flags")
  if Flags.get(ctx.save, name) then
    Flags.clear(ctx.save, name)
  else
    Flags.set(ctx.save, name)
  end
end

-- ---------------------------------------------------------------------------
-- String-buffer writers.
--
-- The ROM has three script-addressable buffers -- wStringBuffer3, 4 and 5
-- (constants/script_constants.asm: STRING_BUFFER_3/4/5, NUM_STRING_BUFFERS 3)
-- -- and GetStringBuffer picks between them from the buffer operand every
-- `get*name` command carries: 0 -> 3, 1 -> 4, 2 -> 5, anything else clamped
-- to 0 (engine/overworld/scripting.asm:1583).
--
-- This port kept ONE, which is fine right up until a single scene writes two
-- of them.  The phone does exactly that: the caller's name goes in 3, the
-- species RandomPhoneWildMon picks goes in 4, and the route goes in 5 -- and
-- collapsed onto one buffer the species won, so every landmark line in every
-- call read "Come pick it up on MAGIKARP."
--
-- So the slots exist now, and the commands that know which one they mean say
-- so.  Everything else still writes `game.stringBuffer`, which IS slot 3, and
-- a slot that was never written falls back to it -- so nothing that worked
-- before changes.
-- ---------------------------------------------------------------------------

-- The buffer operand as it appears in the script byte, per GetStringBuffer.
local function bufferSlot(operand)
  local n = tonumber(operand)
  if n == 1 then return 4 end
  if n == 2 then return 5 end
  return 3 -- STRING_BUFFER_3, and the clamp for anything out of range
end

-- Write one slot.  Slot 3 also updates the legacy single buffer, because that
-- is the one every other writer in the tree still uses.
local function setBuffer(game, slot, value)
  if value == nil then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[slot] = value
  if slot == 3 then game.stringBuffer = value end
end
Gen2Commands.setStringBuffer = setBuffer
Gen2Commands.bufferSlot = bufferSlot

-- Script_getmoney (25:$7583): the player's money, printed for the box that
-- follows.  Like every other get*, it ends in GetStringBuffer, so it names a
-- slot -- see the note by L.getnum in Gen2ScriptVM for what collapsing them
-- onto one buffer cost.
function Commands.g2_buffer_money(ctx, buffer)
  setBuffer(ctx.game, bufferSlot(buffer),
            tostring(math.floor(tonumber(ctx.save.money) or 0)))
end

-- Script_getcoins (25:$7598).
function Commands.g2_buffer_coins(ctx, buffer)
  setBuffer(ctx.game, bufferSlot(buffer),
            tostring(math.floor(tonumber(ctx.save.coins) or 0)))
end

-- Script_getnum (25:$75AD): wScriptVar as a decimal.
function Commands.g2_buffer_num(ctx, buffer)
  setBuffer(ctx.game, bufferSlot(buffer), tostring(math.floor(scriptVar(ctx))))
end

-- Script_getcurlandmarkname (25:$755B): the landmark the player is standing
-- in, by name.  The town map record is where the port keeps landmark names.
function Commands.g2_buffer_landmark(ctx, buffer)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  local landmark = def and def.landmark
  local town = ctx.game.data.field and ctx.game.data.field.townMap
  local entry = landmark and town and town.landmarks
    and (town.landmarks[landmark] or town.landmarks[tostring(landmark)])
  local name = entry and entry.name
  if type(name) == "string" then
    setBuffer(ctx.game, bufferSlot(buffer), (name:gsub("[\n\f\v]", " ")))
  end
end

-- `getlandmarkname buffer, landmark` ($A5, Script_getlandmarkname).  The
-- named landmark, not the one the player is standing in -- which is the whole
-- point on the phone, where the caller is ringing about somewhere else.
-- Same town-map record getcurlandmarkname reads.
function Commands.g2_buffer_landmark_name(ctx, landmark, buffer)
  local town = ctx.game.data.field and ctx.game.data.field.townMap
  local entry = landmark and town and town.landmarks
    and (town.landmarks[landmark] or town.landmarks[tostring(landmark)])
  local name = entry and entry.name
  if type(name) == "string" then
    setBuffer(ctx.game, bufferSlot(buffer), (name:gsub("[\n\f\v]", " ")))
  end
end

-- The roster row for one (trainer class, trainer id) pair.  The extractor
-- writes a scaffold placeholder for every unused class index, so prefer a row
-- that actually names the trainer asked for before falling back to the class.
local function trainerNameFor(data, group, id)
  local fallback
  for _, def in pairs(data and data.trainers or {}) do
    if type(def) == "table" and def.index == group then
      local named = def.partyNames and def.partyNames[id]
      if named then return named end
      fallback = fallback or def.name
    end
  end
  return fallback
end
Gen2Commands.trainerNameFor = trainerNameFor

-- `gettrainername buffer, group, id` ($43, Script_gettrainername -> the byte
-- order is group, id, buffer).  Every outgoing Pokegear call opens with one:
-- "Hello? It's <TRAINER>."  Unlowered, that name came out as whatever was
-- last left in the shared buffer -- usually a species from the previous call.
function Commands.g2_buffer_trainer_name(ctx, group, id, buffer)
  local name = trainerNameFor(ctx.game.data, group, id)
  if type(name) == "string" then
    setBuffer(ctx.game, bufferSlot(buffer), name)
  end
end

-- `verbosegiveitemvar item, var` ($9F): verbosegiveitem with the quantity
-- read out of a script variable.  Kurt is its only user in the game -- he
-- makes one ball per apricorn you handed over, and VAR_KURT_APRICORNS ($16)
-- is where SelectApricornForKurt left that count.
--
-- ITEM_FROM_MEM (item byte 0) takes the item id from wScriptVar instead, the
-- same escape `giveitem` uses.
function Commands.g2_verbose_give_item_var(ctx, item, var)
  if item == "ITEM_000" then
    item = string.format("ITEM_%03d", math.floor(scriptVar(ctx)) % 256)
  end
  local qty = Gen2Commands.scriptVarValue(ctx, var)
  return Commands.give_item(ctx, item, math.max(1, math.floor(qty or 1)))
end

-- The value of a script variable, for the handful of commands that read one
-- as data rather than branching on it.  Only the vars that can actually turn
-- up as a quantity are modelled; anything else answers 1, which is what the
-- operand would have been on a plain verbosegiveitem.
function Gen2Commands.scriptVarValue(ctx, var)
  if var == 0x16 then -- VAR_KURT_APRICORNS
    return tonumber(ctx.save.g2KurtApricorns) or 1
  end
  return 1
end

-- Script_loadmem (25:$7495): write an immediate byte to a WRAM address.  The
-- same address-keyed mirror readmem/writemem use -- keyed by the raw
-- address number exactly as they key it, so a script that pokes a byte here
-- and reads it back later still agrees with itself.
function Commands.g2_loadmem(ctx, address, value)
  local mem = wram(ctx)
  if not mem or type(address) ~= "number" then return end
  mem[address] = tonumber(value) or 0
end


-- ---------------------------------------------------------------------------
-- map scenes
--
-- A scene id is the ROM's per-map "which cutscene state am I in" byte
-- (wMapScenes).  Callbacks and coord events are gated on it, so it has to
-- persist in the save exactly like an event flag.
-- ---------------------------------------------------------------------------

local function sceneStore(ctx)
  ctx.save.g2Scenes = ctx.save.g2Scenes or {}
  return ctx.save.g2Scenes
end

-- Map registry keys are SNAKE_CASE from CamelCase labels (Route25 → ROUTE25).
-- ASM map constants keep an underscore before trailing digits (ROUTE_25).
-- setmapscene must write the same key onStep/getScene will read, or the
-- Cerulean Gym rocket arms a scene that Route 25 never sees.
local function mapKeyAliases(mapId)
  if type(mapId) ~= "string" or mapId == "" then return {} end
  local aliases = { mapId }
  local compact = mapId:gsub("_(%d+)$", "%1")
  if compact ~= mapId then aliases[#aliases + 1] = compact end
  local withUnderscore = mapId:match("^(.-)(%d+)$")
  if withUnderscore and not mapId:match("_%d+$") then
    aliases[#aliases + 1] = mapId:gsub("(%d+)$", "_%1")
  end
  return aliases
end

local function resolveMapKey(ctx, mapId)
  if type(mapId) == "number" then
    -- Extract failed to fold (group, number) → registry key.  Never fall back
    -- to the *current* map (that is how CeruleanGym's setmapscene ROUTE25 was
    -- written onto CERULEAN_GYM instead).
    return nil
  end
  if type(mapId) ~= "string" or mapId == "" then
    return ctx.overworld and ctx.overworld.map and ctx.overworld.map.id
  end
  local data = ctx.game and ctx.game.data
  local maps = data and data.maps
  for _, key in ipairs(mapKeyAliases(mapId)) do
    if maps and maps[key] then return key end
  end
  -- Prefer the compact form (ROUTE25) which matches scaffold registry keys.
  return mapKeyAliases(mapId)[1] and (mapId:gsub("_(%d+)$", "%1")) or mapId
end

local function sceneMapId(ctx, mapId)
  return resolveMapKey(ctx, mapId)
end

function Gen2Commands.getScene(save, mapId)
  local scenes = save.g2Scenes or {}
  if type(mapId) ~= "string" then return scenes[mapId] or 0 end
  for _, key in ipairs(mapKeyAliases(mapId)) do
    if scenes[key] ~= nil then return scenes[key] end
  end
  return 0
end

function Commands.g2_set_scene(ctx, mapId, scene)
  local id = sceneMapId(ctx, mapId)
  if not id then return end
  local store = sceneStore(ctx)
  local value = scene or 0
  -- Write every alias so older saves / mismatched keys still read correctly.
  for _, key in ipairs(mapKeyAliases(id)) do
    store[key] = value
  end
end

-- Script_checkscene (25:$75C2) calls GetCurrentMapSceneID and, when the map
-- has NO scene entry at all, writes $FF to wScriptVar -- not 0.  That matters
-- because `iftrue` reads wScriptVar directly, so "no scene" is TRUE in the ROM
-- and the guarded branch is taken.  Answering 0 here inverted every one of
-- those guards: a MAPCALLBACK that the ROM skips on a scene-less map ran
-- instead, which is how an NPC gets nudged one step every single time you
-- walk in and eventually ends up standing on the furniture.
--
-- field.mapSceneVars is the ROM's own MapScenes list, so "is this map in it"
-- is exactly GetCurrentMapSceneID's z flag.
local SCENE_NONE = 0xFF

local function mapHasScene(ctx, id)
  local data = ctx.game and ctx.game.data
  local vars = data and data.field and data.field.mapSceneVars
  -- no table (dataset predates it) -> assume the map does have a scene, which
  -- is the behaviour this port had before and is right for the maps that
  -- actually carry callbacks
  if type(vars) ~= "table" then return true end
  if id == nil then return false end
  for _, key in ipairs(mapKeyAliases(id)) do
    if vars[key] ~= nil then return true end
  end
  return false
end

function Commands.g2_check_scene(ctx, mapId)
  local id = sceneMapId(ctx, mapId)
  if not mapHasScene(ctx, id) then
    ctx.g2Var = SCENE_NONE
  else
    ctx.g2Var = id and Gen2Commands.getScene(ctx.save, id) or 0
  end
  ctx.lastCheck = ctx.g2Var ~= 0
end

-- ---------------------------------------------------------------------------
-- objects
--
-- appear/disappear carry BOTH halves of Gen2 visibility themselves: the live
-- object struct is deleted or restored now, and the object's own event flag
-- is set or cleared in the saved flag array (25:$72DD / 25:$72EE ->
-- ApplyEventActionAppearDisappear -> EventFlagAction).  Scripts therefore do
-- NOT pair them with a setevent, and anything that treats them as transient
-- loses the change the moment the player walks back in.
-- ---------------------------------------------------------------------------

-- Gen2 script object ids are not list positions.  Every map's object constants
-- are emitted with `const_def 2`, so the first object_event is id 2, and the
-- ids below that are engine slots: 0 is the player.  Translating an id back to
-- a 1-based index into map.def.objects is therefore `id - 1`, and an id of 0
-- has to be steered at the player instead of an NPC -- Elm's lab walks you to
-- the professor with `applymovement 0`, which silently did nothing while these
-- ids were treated as plain list positions.
local GEN2_FIRST_OBJECT_ID = 2

local function isPlayerId(index)
  return index == 0 or index == "player"
end

-- WHERE SCRIPT OBJECT IDS START IS A CARTRIDGE FACT.
--
-- Crystal's object_const_def opens at 2 -- id 0 is the player, id 2 the
-- first object_event -- and this port hardcoded that (`slot = index - 1`).
-- Polished Crystal numbers them 1:1 with wMapObjects: GetMapObject
-- (00:$1556) is `hl = wMapObjects + id * $0E`, wPlayerObject is slot 0 and
-- wMap1Object slot 1, so ID 1 IS THE FIRST OBJECT.  Read with Crystal's
-- bias, every applymovement/turnobject/moveobject landed one object EARLY:
-- New Bark's teacher (object 3) resolved to the still-hidden Lyra, so the
-- "don't leave town" scene printed its text and moved the player while the
-- lady never walked over; Elm's per-scene moveobject was rejected outright
-- (id 1 < first-id 2) and he stood at his object row's coordinates all
-- game; and Lyra's lab cutscene drove the wrong objects entirely.
--
-- field.objectScriptBase carries the importer's answer; absent, Crystal's
-- 2 stands.
local objectScriptBase = nil
local function objectSlot(ctx, index)
  if type(index) ~= "number" then return nil end
  if objectScriptBase == nil then
    local field = ctx and ctx.game and ctx.game.data and ctx.game.data.field
    objectScriptBase = tonumber(field and field.objectScriptBase)
      or GEN2_FIRST_OBJECT_ID
  end
  if index < objectScriptBase then return nil end
  return index - (objectScriptBase - 1)
end

-- the cached base belongs to one loaded game; a reload must re-read it
function Commands.g2ResetObjectBase()
  objectScriptBase = nil
end

local function objectByIndex(ctx, index)
  local slot = objectSlot(ctx, index)
  if not slot then return nil, nil end
  local ow = ctx.overworld
  if not ow or not ow.map or not ow.map.def then return nil, nil end
  local objects = ow.map.def.objects
  if type(objects) ~= "table" then return nil, nil end
  return objects[slot], ow.map.id, slot
end

-- LAST_TALKED ($fe): `disappear LAST_TALKED` is how RockSmashScript removes
-- the rock you just smashed and how a dozen NPCs walk off after their line.
-- It is not a list position, so objectSlot rejected it and the row silently
-- did nothing -- the smashed rock stayed put.
local GEN2_LAST_TALKED = 0xFE

function Commands.g2_object(ctx, index, visible)
  local obj, mapId
  if index == GEN2_LAST_TALKED or index == "last" then
    local npc = ctx.npc
    obj = npc and npc.def
    mapId = ctx.overworld and ctx.overworld.map and ctx.overworld.map.id
  else
    obj, mapId = objectByIndex(ctx, index)
  end
  if not obj or not mapId then return end
  local OverworldState = require("src.world.OverworldController")
  local name = OverworldState.objectToggleKey(obj)
  -- The PERSISTENT half, which this used to leave to a `setevent` the ROM
  -- does not require.  Script_disappear (25:$72EE) reads the object's event
  -- flag word out of its struct at offset $0C/$0D and, unless it is $FFFF,
  -- calls EventFlagAction with b=$01 -- a SET, against wEventFlags, which is
  -- saved.  Script_appear (25:$72DD) is the same call with b=$00, a CLEAR.
  -- So an object that carries a flag disappears for good, and CopScript
  -- (1E:$4F1A) ends `applymovement / disappear / setscene / end` with no
  -- setevent anywhere precisely because `disappear` already wrote it.
  --
  -- Treating both as session-only is what left the Elm's Lab officer walking
  -- down the room and standing there for ever, asking for the rival's name
  -- again on every re-entry, and what left the rival himself invisible after
  -- a script `appear`ed him: the flag the extractor recorded stayed set, and
  -- OverworldController's visibility check reads exactly that flag.
  --
  -- $FFFF means "no flag" and the ROM writes nothing -- those objects really
  -- are session-only (it deletes the live struct and the next map load
  -- rebuilds it), which is how the Battle Tower receptionist comes back to
  -- her desk.  The extractor drops the field entirely in that case, so the
  -- presence of obj.eventFlag IS the ROM's own test.
  if obj.eventFlag then
    ctx.save.flags = ctx.save.flags or {}
    ctx.save.flags[obj.eventFlag] = (not visible) and true or false
  end

  -- The transient half: the ROM's DeleteObjectStruct / UnmaskCopyMapObjectStruct
  -- takes effect on the spot, before any map reload.  Deliberately BELOW the
  -- flag write: the flag is what survives, and an object with no usable
  -- toggle key must not lose it just because the session half has nowhere to
  -- record itself.
  if not name then
    local ow0 = ctx.overworld
    if ow0 and ow0.syncObjectVisibility then
      -- Targeted: Script_appear / Script_disappear act on the ONE object they
      -- name.  A whole-map re-sync here re-derives every other object from its
      -- event flag, which silently deletes any live actor whose own flag a
      -- script has already set -- and nothing re-spawns it, because
      -- setevent/clearevent never touch live objects.  See
      -- OverworldState:syncObjectVisibility.
      pcall(function() ow0:syncObjectVisibility(obj) end)
    end
    return
  end
  local session = ctx.save.g2ObjectToggles
  if type(session) ~= "table" or session.mapId ~= mapId then
    session = { mapId = mapId }
    ctx.save.g2ObjectToggles = session
  end
  session[name] = visible and true or false
  local ow = ctx.overworld
  if ow and ow.syncObjectVisibility then
    pcall(function() ow:syncObjectVisibility(obj) end)
  end
end

-- WriteCmdQueue with a CMDQUEUE_STONETABLE entry: the map's cmdqueue
-- callback hands over the `stonetable <warp>, <object>, <script>` rows the
-- extractor resolved.  The ROM then polls them every frame from
-- CmdQueue_StoneTable; here the overworld checks them when a pushed boulder
-- comes to rest, so all this has to do is record them for the current map.
function Commands.g2_stonetable(ctx, rows)
  local ow = ctx.overworld
  if not (ow and ow.map) or type(rows) ~= "table" then return end
  ow.stoneTable = { mapId = ow.map.id, rows = rows }
end

-- CheckPartyMove (engine/overworld/overworld.asm): scan the party for the
-- move, leaving carry set when nobody has it.  HasRockSmash and friends
-- report that through wScriptVar as 1 = lacks, 0 = has, which the std script
-- then branches on -- so without this every `AskRockSmashScript` fell through
-- to the yes/no prompt whether or not the party could smash anything.
function Commands.g2_party_move(ctx, moveId)
  local ow = ctx.overworld
  local mon = ow and ow.partyKnows and ow:partyKnows(moveId) or nil
  ctx.g2FieldMon = mon
  ctx.g2Var = mon and 0 or 1
  ctx.lastCheck = mon ~= nil
end

-- TryStrengthOW: 1 = no STRENGTH mon or no PLAINBADGE (BouldersMayMoveText),
-- 2 = BIKEFLAGS_STRENGTH_ACTIVE already set (BouldersMoveText), 0 = ask.
function Commands.g2_try_strength(ctx)
  local ow = ctx.overworld
  local mon = ow and ow.partyKnows and ow:partyKnows("STRENGTH") or nil
  ctx.g2FieldMon = mon
  if not mon then
    ctx.g2Var = 1
  elseif ow.strengthActive then
    ctx.g2Var = 2
  else
    ctx.g2Var = 0
  end
  ctx.lastCheck = ctx.g2Var ~= 0
end

-- SetStrengthFlag: arms BIKEFLAGS_STRENGTH_ACTIVE, the sole gate
-- .CheckStrengthBoulder reads, and loads the mon's nickname for the text.
function Commands.g2_strength_on(ctx)
  local ow = ctx.overworld
  if ow then ow.strengthActive = true end
  Commands.g2_party_nickname(ctx)
end

-- GetPartyNickname: copies wCurPartyMon's nickname into wStringBuffer1, which
-- the following text_ram prints.
function Commands.g2_party_nickname(ctx)
  local mon = ctx.g2FieldMon
  if not mon then return end
  local def = ctx.game.data.pokemon[mon.species]
  ctx.game.stringBuffer = mon.nickname or (def and def.name) or mon.species
end

-- Movement is Gen2's second bytecode language: applymovement points at a list
-- of step/turn commands terminated by step_end.  Everything the overworld can
-- actually animate is a directional step or a head turn, so collapse the list
-- into runs of walk_npc / face_object and drop the presentation-only rows
-- (sliding flags, emotes, fixed facing).
local MOVEMENT_STEP = {
  slow_step = true, step = true, big_step = true, slow_slide_step = true,
  slide_step = true, fast_slide_step = true, slow_jump_step = true,
  jump_step = true, fast_jump_step = true,
  -- Polished's three extra step families (movement opcodes $5A-$65).  They
  -- differ only in speed and in the stairs animation, so as far as the walk
  -- is concerned they are ordinary steps -- but if they are not listed here
  -- they are not steps at all, and the object stands still through the whole
  -- movement.
  run_step = true, fast_step = true, stairs_step = true,
}
-- `turn_step` reads like a step but is not one: Movement_turn_step_down
-- (1:$538F) is byte-for-byte Movement_turn_head_down, and
-- ApplyMovementToFollower's `cp 8 / ret c` drops movement indices 0-7 --
-- turn_head AND turn_step -- precisely because neither moves the object.
-- Walking those rows is what sent the rival through the wall instead of
-- turning him back to the lab window.
local MOVEMENT_TURN = {
  turn_head = true, turn_in = true, turn_away = true,
  turn_step = true, turn_waterfall = true,
}

-- Commands.face turns the NPC being talked to; Gen2's object id 0 is the player.
local function facePlayer(ctx, dir)
  local player = ctx.overworld and ctx.overworld.player
  if player then player.facing = dir end
end

local function movementParts(name)
  local verb, dir = name:match("^(.-)_(down)$")
  if not verb then verb, dir = name:match("^(.-)_(up)$") end
  if not verb then verb, dir = name:match("^(.-)_(left)$") end
  if not verb then verb, dir = name:match("^(.-)_(right)$") end
  return verb, dir
end

-- Follow (StartFollow 1:$5779, ApplyMovementToFollower 1:$5457,
-- GetFollowerNextMovementIndex 1:$5485).  Every step the LEADER is given is
-- pushed onto wFollowMovementQueue, and the follower pops that queue one beat
-- later -- so the follower retraces the leader's exact path, always exactly
-- one tile behind.  It does NOT walk alongside in lockstep, which is what the
-- port did and what made the Cherrygrove guide's escort read wrong.
--
-- QueueFollowerFirstStep (2:$4A7A) seeds the queue with the single step that
-- closes the gap -- x is compared before y -- so the follower's opening move
-- is onto the tile the leader is vacating.  Turns are never queued
-- (ApplyMovementToFollower's `cp 8 / ret c` drops every movement index below
-- the step block), so only steps count here.
local function followerFirstStep(follower, leader)
  if leader.cellX < follower.cellX then return "left" end
  if leader.cellX > follower.cellX then return "right" end
  if leader.cellY < follower.cellY then return "up" end
  if leader.cellY > follower.cellY then return "down" end
  return nil
end

-- The whole follower run goes in up front: updateScriptMoves starts every
-- idle entity's next queued move on the same frame, so a sequence shifted by
-- one step keeps the pair exactly one tile apart without the script having to
-- interleave the two walks.
local function queueFollower(ow, follower, leader, dirs)
  local first = followerFirstStep(follower, leader)
  local steps = {}
  if first then steps[1] = first end
  -- ...then the leader's own steps, minus however many the seed consumed
  for i = 1, #dirs - #steps do steps[#steps + 1] = dirs[i] end

  local run, runDir = 0, nil
  for _, dir in ipairs(steps) do
    if runDir and runDir ~= dir then
      ow:scriptMove(follower, runDir, run)
      run = 0
    end
    runDir, run = dir, run + 1
  end
  if runDir and run > 0 then ow:scriptMove(follower, runDir, run) end
end

function Commands.g2_move(ctx, target, movementLabel)
  local data = ctx.game and ctx.game.data
  local store = data and data.map_scripts
  local rows = store and store.movements and store.movements[movementLabel]
  if not rows then return end

  local index
  if isPlayerId(target) then
    index = nil
  elseif type(target) == "number" then
    local _, _, slot = objectByIndex(ctx, target)
    if not slot then return end
    index = slot
  else
    local npc = ctx.npc
    index = npc and npc.def and npc.def.index or nil
  end

  local ow = ctx.overworld
  if ow and ctx.g2FollowLeader ~= nil and ctx.g2FollowLeader == target then
    local t = ctx.g2FollowTarget
    local follower
    if isPlayerId(t) then
      follower = ow.player
    elseif type(t) == "number" then
      local slot = objectSlot(ctx, t)
      follower = slot and ow:npcByIndex(slot) or nil
    end
    local leader = index and ow:npcByIndex(index) or ow.player
    if follower and leader then
      local dirs = {}
      for _, row in ipairs(rows) do
        local verb, dir = movementParts(row[1])
        if verb and dir and MOVEMENT_STEP[verb] then dirs[#dirs + 1] = dir end
      end
      queueFollower(ow, follower, leader, dirs)
    end
  end

  local pending, pendingDir = 0, nil
  -- movement_fix_facing pins the sprite's frame so a scripted walk keeps
  -- looking the way it started (the Ilex Forest bird, the gatehouse guards).
  -- The port has no per-step facing lock, so re-assert the pinned facing
  -- after each run of steps instead.
  local fixedFacing = nil
  local function entity()
    if index then return ow and ow:npcByIndex(index) end
    return ow and ow.player
  end
  local function flush()
    if pending > 0 and pendingDir then
      if index then
        Commands.move_npc(ctx, index, pendingDir, pending)
      else
        Commands.move_player(ctx, pendingDir, pending)
      end
      if fixedFacing then
        local e = entity()
        if e then e.facing = fixedFacing end
      end
    end
    pending, pendingDir = 0, nil
  end

  for _, row in ipairs(rows) do
    local verb, dir = movementParts(row[1])
    if verb and dir and MOVEMENT_STEP[verb] then
      if pendingDir and pendingDir ~= dir then flush() end
      pendingDir = dir
      pending = pending + 1
    elseif verb and dir and MOVEMENT_TURN[verb] then
      flush()
      if index then
        Commands.face_object(ctx, index, dir)
      else
        facePlayer(ctx, dir)
      end
    elseif row[1] == "tree_shake" or row[1] == "rock_smash" then
      flush()
      Commands.g2_shake(ctx, index)
    elseif row[1] == "fix_facing" then
      flush()
      local e = entity()
      fixedFacing = e and e.facing or nil
    elseif row[1] == "remove_fixed_facing" then
      flush()
      fixedFacing = nil
    elseif row[1] == "set_sliding" or row[1] == "remove_sliding" then
      -- movement_set_sliding drops the walk animation so the object glides,
      -- which is how the Ice Path boulders and the Kimono Girls move.
      flush()
      local e = entity()
      if e then e.sliding = row[1] == "set_sliding" or nil end
    else
      -- movement_step_sleep <n>: the extractor bakes the operand into the
      -- name, so the row carries no argument to read
      local sleep = tonumber(row[1]:match("^step_sleep_(%d+)$"))
      if sleep then
        flush()
        Commands.wait(ctx, sleep * 16)
      end
    end
  end
  flush()
end

-- The one movement row that animates without moving: the object rattles in
-- place and the script waits it out, like every other applymovement.
function Commands.g2_shake(ctx, index)
  local ow = ctx.overworld
  local npc = ow and index and ow:npcByIndex(index) or nil
  if not npc or not npc.shake then return end
  local runner = ctx.runner
  npc:shake(32, function() runner:resume() end)
  runner:yield()
end

local DIRS = { [0] = "down", "up", "left", "right" }

function Commands.g2_turn(ctx, index, facing)
  local dir = DIRS[facing or 0] or "down"
  if isPlayerId(index) then
    facePlayer(ctx, dir)
    return
  end
  local _, _, slot = objectByIndex(ctx, index)
  if slot then Commands.face_object(ctx, slot, dir) end
end

function Commands.g2_place(ctx, index, x, y)
  local obj, _, slot = objectByIndex(ctx, index)
  if obj then Commands.place_npc(ctx, slot, x, y) end
end

-- showemote emote, object, frames -- the alert bubble that fires just before
-- the Cherrygrove rival and the Route 29 catching tutorial run at you
local EMOTES = { [0] = "shock", "question", "happy", "sad", "heart", "bolt", "sleep", "fish" }

function Commands.g2_emote(ctx, index, emote, frames)
  local bubble = EMOTES[emote or 0] or "shock"
  local target = isPlayerId(index) and "player" or select(3, objectByIndex(ctx, index))
  if not target then return end
  Commands.emote(ctx, target, bubble, frames or 15)
end

-- `catchtutorial <battletype>` (Script_catchtutorial -> CatchTutorial,
-- engine/events/catch_tutorial.asm).  The Dude's demo on Route 29, in Gold,
-- Silver and Crystal alike -- and until now a documented no-op, so the scene
-- ran his dialogue with the battle itself simply missing.
--
-- The ROM: back up wPlayerName, write "DUDE" over it, load his one-ball bag,
-- start the battle the preceding `loadwildmon` set up (RATTATA, level 5), let
-- a canned joypad stream drive the menus, then put the real name back.  The
-- port already has all of this for Gen1's Viridian old man -- BattleState's
-- demo mode IS the simulated cursor, the one-entry bag and the throw that
-- cannot fail -- so this hands the same machinery the Gen2 trimmings.
function Commands.g2_catch_tutorial(ctx)
  local wild = ctx.g2Wild
  -- `loadwildmon` always precedes it; without one there is nothing to catch
  -- and the ROM would fight whatever wEnemyMon happened to hold, so skip.
  if not wild then
    Logger.warn("gen2 script: catchtutorial with no loadwildmon")
    return
  end
  ctx.g2Wild = nil
  local BattleState = require("src.battle.BattleState")
  local runner = ctx.runner
  local battle = BattleState.newWild(ctx.game, wild.species, wild.level)
  battle:makeDudeDemo()
  -- CatchTutorial swaps wPlayerName for the duration (the "DUDE used POKe
  -- BALL!" line reads it) and copies the real one back on the way out.  The
  -- demo prints its own name, so this only has to survive anything else that
  -- reads the player name mid-battle -- and it must be restored even if the
  -- battle ends by a path this function does not control.
  local player = ctx.game.save.player
  local realName = player and player.name
  if player then player.name = "DUDE" end
  battle.onFinish = function()
    if player then player.name = realName end
    runner:resume()
  end
  if ctx.overworld and ctx.overworld.pushBattle then
    ctx.overworld:pushBattle(battle)
  else
    ctx.game.stack:push(battle)
  end
  runner:yield()
end

-- ---------------------------------------------------------------------------
-- battles
-- ---------------------------------------------------------------------------

function Commands.g2_load_trainer(ctx, group, id)
  ctx.g2Trainer = { group = group, id = id }
  ctx.g2Wild = nil
end

function Commands.g2_load_wild(ctx, species, level)
  ctx.g2Wild = { species = species, level = level }
  ctx.g2Trainer = nil
end

function Commands.g2_winloss(ctx, winText, lossText)
  ctx.g2WinText, ctx.g2LossText = winText, lossText
end

-- wBattleResult -> wScriptVar, the way Script_startbattle leaves it
-- (`ld a, [wBattleResult] / and $3f / ld [wScriptVar], a`): WIN 0, LOSE 1,
-- DRAW 2.  DRAW is "nobody won" -- the player ran, or the wild mon fled.
-- Catching sets a HIGH bit of wBattleResult that `and $3f` strips, so a
-- caught mon still reads as a win.
Commands.G2_BATTLE_RESULT = { win = 0, caught = 0, lose = 1, run = 2 }

function Commands.g2_start_battle(ctx)
  local wild, trainer = ctx.g2Wild, ctx.g2Trainer
  local battleType = ctx.g2BattleType
  -- DoBattleTransitionAndInitBattleVariables clears wBattleType, so it only
  -- ever applies to the one battle the loadvar preceded
  ctx.g2BattleType = nil
  if wild then
    ctx.g2Wild = nil
    Commands.start_battle(ctx, "wild", wild.species, wild.level,
      { shiny = battleType == Commands.G2_BATTLETYPE_SHINY })
  elseif trainer then
    -- winlosstext's first pointer is the beaten trainer's own line, and
    -- TrainerBattleVictory prints it ON the battle screen just before
    -- MoneyForWinningText.  Leaving it to the trailing reloadmapafterbattle
    -- put the rival's "…Humph!" after the prize money and after the battle
    -- had already torn down.
    local won = ctx.g2WinText
    ctx.g2WinText = nil
    Commands.start_battle(ctx, "trainer", trainer.group, trainer.id,
      { endBattleText = won and resolvedText(ctx, won) or nil })
  else
    return
  end
  -- wBattleResult feeds wScriptVar, which is what the `ifequal $2` some
  -- scripts put after a startbattle branches on: 0 won, 1 lost, 2 drew.
  ctx.g2Var = Commands.G2_BATTLE_RESULT[ctx.lastBattleResult] or 0
  -- ...and `iftrue`/`iffalse` read the SAME wScriptVar, so after a Gen2
  -- startbattle they mean "did NOT win", not "won".  Commands.start_battle
  -- left lastCheck set the Gen 1 way (`result == "win"`), which is exactly
  -- inverted: the Mahogany hideout Electrodes (RocketElectrode1-3,
  -- 45:$4DB9/$4DE4/$4E0F) are `startbattle` + `iftrue .done` + `disappear`,
  -- so running away made them vanish and beating them left them standing.
  ctx.lastCheck = ctx.g2Var ~= 0
  -- A loss whites the player out to a Pokemon Center, so the rest of the
  -- script -- the win text, the badge, the TM -- must never run.  Running
  -- from or catching a scripted wild mon still continues it.
  if ctx.lastBattleResult == "lose" then return "end" end
end

-- `reloadmapafterbattle` (Script_reloadmapafterbattle, 25:$70CE).  Its FIRST
-- act is to read wBattleResult, and on LOSE it does not come back to the
-- script at all: `ScriptJump Script_BattleWhiteout`, which whites the player
-- out and ends with `endall`.  Everything the script had queued behind the
-- battle is abandoned.
--
-- The port only ever printed the win text here, so a lost trainer battle fell
-- straight through into the victory half of its own script.  The Elite Four is
-- where that shows: losing to Will ran `setevent EVENT_BEAT_ELITE_4_WILL`,
-- printed his defeat speech and opened the exit door, all while the blackout
-- warp was still in flight -- so the player ended up back in the room they had
-- just lost in, with the E4 member marked beaten.  That is the "blacking out
-- in the Elite Four respawns you there" report.
--
-- OverworldState:afterBattle has already done the whiteout itself (heal, halve
-- the money, warp to the spawn) by the time this runs, so the only thing
-- missing was stopping the script.  Returning a program counter past the end
-- is how the port spells `endall`.
--
-- Scripts that are ALLOWED to lose never reach here: BATTLETYPE_CANLOSE
-- battles (the Cherrygrove rival) are followed by `reloadmap`, not
-- `reloadmapafterbattle`, and branch on the result themselves.  The canLose
-- guard is belt and braces for a mod that pairs them anyway.
function Commands.g2_after_battle(ctx)
  if ctx.lastBattleResult == "lose" and not ctx.lastBattleCanLose then
    return math.huge
  end
  if ctx.g2WinText then Commands.show_text(ctx, ctx.g2WinText) end
end

-- ---------------------------------------------------------------------------
-- odds and ends
-- ---------------------------------------------------------------------------

function Commands.g2_warp(ctx, mapId, x, y, facing)
  if type(mapId) ~= "string" or mapId == "" then return end
  Commands.warp(ctx, mapId, x, y, facing)
end

-- `blackoutmod <map>`: the blackout spawn.  GetWhiteoutSpawn resolves the
-- named map through SpawnPoints (map_scripts.spawns.points) for the arrival
-- cell, so a map with no spawn row leaves the old point standing rather than
-- stranding the player on coordinates the ROM never had.
function Commands.g2_blackout_point(ctx, mapId)
  if type(mapId) ~= "string" or mapId == "" then return end
  local pool = ctx.game.data.map_scripts
  local point = pool and pool.spawns and pool.spawns.points
                and pool.spawns.points[mapId]
  if not point then
    Logger.warn("gen2 script: no spawn point for %s", mapId)
    return
  end
  ctx.save.lastHeal = { map = mapId, x = point.x, y = point.y }
end

-- yesorno reuses the box the preceding writetext opened; the compiler hands
-- us that text const so the prompt reads the same as the ROM's
-- textId is nil when the prompt was printed from inside a `scall`, which the
-- lowering cannot fold.  Script_yesorno opens the menu over whatever box is
-- already up, so fall back to the last text this script actually showed.
function Commands.g2_yesno(ctx, textId)
  -- ask() parks the runner and writes the answer to ctx.lastCheck itself
  Commands.ask(ctx, textId or ctx.g2LastText)
end

-- `cry <species>`: PlayMonCry, standalone.  Unlike Gen1's play_cry this
-- must not arm the next text box (see Gen2ScriptVM's L.cry).
function Commands.g2_cry(ctx, species)
  require("src.core.Sound").playCry(ctx.game.data, species)
end

-- `pokepic <species>` / `closepokepic` (Script_pokepic -> Pokepic, 09:$44E3).
-- The framed front pic Elm's starter balls show before the yes/no prompt.
--
-- pokepic does NOT block: the ROM keeps executing under the open box, and
-- the very next command is the mon's cry.  The box therefore ticks the
-- runner from its own update (src/ui/PicBox.lua) and the wait happens at
-- closepokepic instead -- which is exactly where the ROM's `waitbutton`
-- sits, and which this port lowers away because show_text normally owns
-- that wait.
function Commands.g2_pokepic(ctx, species)
  local ow = ctx.overworld
  if not (ow and ctx.game) then return end
  -- `pokepic 0` reads wScriptVar instead of a literal
  if species == nil and type(ctx.g2Var) == "number" and ctx.g2Var > 0 then
    species = string.format("SPECIES_%03d", ctx.g2Var)
  end
  if not species then return end
  local path, trueColor =
    require("src.pokemon.Sprites").path(ctx.game.data, species, "front",
                                        { kind = "pokepic" })
  if not path then return end
  -- a script that opens two in a row (none in the ROM, but a mod may)
  if ow.pokepicBox then ow.pokepicBox:remove() end
  -- _CGB_Pokepic (02:$5499) gives the pic the mon's OWN palette instead of
  -- the map's, so the colours are baked here rather than left to the
  -- overworld zone pass -- which is what made the starters come out green.
  -- The forced-mono COLORS modes have no palette to bake (BattleState:
  -- picImage takes the same branch), so those keep the plain grays.
  local PaletteFX = require("src.render.PaletteFX")
  local mono = PaletteFX.mode == "og" or PaletteFX.mode == "og_inv"
               or PaletteFX.mode == "classic"
  local colors = (not (trueColor or mono))
    and PaletteFX.monPal(ctx.game.data, species) or nil
  local box = require("src.ui.PicBox").new(ctx.game, {
    path = path, colors = colors, trueColor = trueColor,
    passive = true, overworld = ow,
  })
  ow.pokepicBox = box
  ctx.game.stack:push(box)
end

function Commands.g2_close_pokepic(ctx)
  local ow = ctx.overworld
  local box = ow and ow.pokepicBox
  if not box then return end
  ow.pokepicBox = nil
  local runner = ctx.runner
  if not runner then
    box:remove()
    return
  end
  box:arm(function() runner:resume() end)
  runner:yield()
end

-- `pokemart MARTTYPE_*, MART_*`: the item list lives in map_scripts.marts,
-- read straight out of the ROM's Marts pointer table.
function Commands.g2_mart(ctx, index)
  local pool = ctx.game.data.map_scripts
  local stock = pool and pool.marts and pool.marts[index]
  if type(stock) ~= "table" or #stock == 0 then
    Logger.warn("gen2 script: no mart %s", tostring(index))
    return
  end
  local runner = ctx.runner
  local Screens = require("src.ui.Screens")
  Screens.push(ctx.game, "ShopMenu", stock, function() runner:resume() end)
  runner:yield()
end

-- checktime's operand is the MORN/DAY/NITE bitmask the overworld already
-- filters time-restricted objects with.
local TOD_BITS = { MORNING = 1, MORN = 1, DAY = 2, NIGHT = 4, NITE = 4 }

function Commands.g2_checktime(ctx, mask)
  local ow = ctx.overworld
  local tod = ow and ow.timeOfDay and ow:timeOfDay() or "DAY"
  local bit = TOD_BITS[tod] or TOD_BITS.DAY
  ctx.lastCheck = math.floor((mask or 0) / bit) % 2 == 1
end

function Commands.g2_false(ctx)
  ctx.lastCheck = false
end

-- ---------------------------------------------------------------------------
-- money, bag and party predicates
-- ---------------------------------------------------------------------------

-- CheckMoney writes wScriptVar, not the carry: 0 richer, 1 exact, 2 short.
-- Every caller branches with `ifequal 2`, so lastCheck alone is not enough.
function Commands.g2_check_money(ctx, amount)
  local have = ctx.save.money or 0
  amount = amount or 0
  ctx.g2Var = have > amount and 0 or (have == amount and 1 or 2)
  ctx.lastCheck = have >= amount
end

function Commands.g2_pocket_full(ctx)
  local Bag = require("src.inventory.Bag")
  -- In Gen2, pocketisfull checks the current item's pocket, not total bag
  -- capacity (GetPocketCapacity 03:$528E).  Without per-item context here,
  -- approximate by checking whether ANY non-TM/HM pocket has 20 items.
  -- give_item's Bag.add enforces the real per-pocket limit.
  local save = ctx.save
  local data = ctx.game and ctx.game.data or nil
  local full = Bag.pocketSlots(save, "ITEM",     data) >= 20
            or Bag.pocketSlots(save, "BALL",     data) >= 20
            or Bag.pocketSlots(save, "KEY_ITEM", data) >= 20
  ctx.g2Var = full and 1 or 0
  ctx.lastCheck = full
end

-- `giveitem item, qty` (ReceiveItem) is SILENT: it fills the bag and sets the
-- carry, nothing else.  The jingle and the "received" line belong to whoever
-- called it -- `jumpstd receiveitemstd` before it, or `verbosegiveitem`
-- instead of it.  Routing this to Gen1's give_item played a second fanfare
-- over the script's own `playsound` and opened a box the ROM never shows
-- (MrPokemon's MYSTERY EGG, Elm's aide and her POKe BALLs).
function Commands.g2_giveitem(ctx, itemId, count)
  local game = ctx.game
  local ok = require("src.inventory.Bag").add(
    ctx.save, itemId, count or 1, game.data)
  if ok then Commands.g2_getitemname(ctx, itemId) end
  ctx.lastCheck = ok and true or false
end

-- GetItemName / GetPokemonName copy a name into a string buffer that a later
-- writetext splices back out ("{RAM:wStringBuffer1}").  The port keeps one
-- buffer, so the buffer index operand is dropped.  Left unlowered these lines
-- printed whatever was named last, several scenes ago.
function Commands.g2_getitemname(ctx, itemId, buffer)
  local def = ctx.game.data.items[itemId]
  setBuffer(ctx.game, bufferSlot(buffer), def and def.name or itemId)
end

function Commands.g2_getmonname(ctx, species, buffer)
  local def = ctx.game.data.pokemon[species]
  setBuffer(ctx.game, bufferSlot(buffer), def and def.name or species)
end

-- GetString is the same idea for a name that is neither an item nor a species
-- -- "EXPN CARD", "RADIO CARD", "GEAR", "EGG", "COIN".  The extractor resolves
-- the pointer to the literal, so there is nothing to look up here.
function Commands.g2_getstring(ctx, text, buffer)
  if type(text) ~= "string" or text == "" then return end
  setBuffer(ctx.game, bufferSlot(buffer), text)
end

function Commands.g2_check_poke(ctx, species)
  for _, mon in ipairs(ctx.save.party or {}) do
    if mon.species == species then
      ctx.lastCheck = true
      ctx.g2Var = 1
      return
    end
  end
  ctx.lastCheck = false
  ctx.g2Var = 0
end

-- `giveegg species, level`: GiveEgg adds a party member whose is_egg bit is
-- set and whose hatch counter rides in the happiness byte.  The counter comes
-- from the species' own egg cycles (base_stats byte 16), so ELM's TOGEPI EGG
-- takes its ROM-accurate ten cycles rather than a flat five.
function Commands.g2_give_egg(ctx, species, level)
  local Party = require("src.pokemon.Party")
  local Pokemon = require("src.pokemon.Pokemon")
  local DayCare = require("src.pokemon.DayCare")
  local mon = Pokemon.new(ctx.game.data, species, level or 5)
  mon.isEgg = true
  mon.nickname = "EGG"
  mon.eggSteps = DayCare.eggSteps(ctx.game.data, species)
  ctx.lastCheck = Party.add(ctx.save.party, mon) and true or false
  ctx.g2Var = ctx.lastCheck and 0 or 1
end

-- ---------------------------------------------------------------------------
-- POKéGEAR phone book (wPhoneList)
-- ---------------------------------------------------------------------------

local function phoneList(save)
  save.g2Phone = save.g2Phone or {}
  return save.g2Phone
end

function Gen2Commands.phoneList(save)
  return phoneList(save)
end

-- GetCallerName (36:$439D) prints the trainer's own name for any contact with
-- a nonzero trainer class and otherwise indexes NonTrainerCallerNames with the
-- contact id -- MOM, BIKE SHOP, BILL, PROF.ELM.  The extractor stores the
-- class/id pair rather than a baked string, so resolve it against the trainer
-- roster here and the two can never drift apart.
local function phoneContact(data, id)
  local pool = data and data.map_scripts
  local entry = pool and pool.phone and pool.phone[id]
  return type(entry) == "table" and entry or nil
end
Gen2Commands.phoneContact = phoneContact

-- The trainer roster row a trainer contact names.  The roster carries a
-- scaffold placeholder for every unused class index, so prefer the one that
-- actually has a roster of named trainers.
local function phoneTrainerDef(data, entry)
  if not (entry and entry.class) then return nil end
  local best
  for _, def in pairs(data.trainers or {}) do
    if type(def) == "table" and def.index == entry.class then
      if def.partyNames and def.partyNames[entry.trainer] then return def end
      best = best or def
    end
  end
  return best
end

function Gen2Commands.phoneName(data, id)
  local entry = phoneContact(data, id)
  if not entry then return nil end
  if entry.name then return entry.name end
  local best = phoneTrainerDef(data, entry)
  if not best then return nil end
  local names = best.partyNames
  return (names and names[entry.trainer]) or best.name, best.name
end

-- The row's second `dba` is the script PhoneCall (36:$4298) runs when the
-- player rings the contact; the first is the one they run when they ring in.
-- Both are walked into map_scripts.scripts by the extractor, so hand back the
-- decoded rows rather than a label the caller would have to resolve itself.
--
-- Through Gen2ScriptVM.compile, not straight out of the pool: map_scripts
-- holds ROM opcodes (`writetext`, `checkevent`, `sjump`), and ScriptRunner
-- only speaks the lowered rows -- handing it the raw list makes every command
-- an "unknown command (skipped)" warning and the call plays as nothing at all.
local function phoneScript(data, id, field)
  local pool = data and data.map_scripts
  local entry = pool and pool.phone and pool.phone[id]
  local label = type(entry) == "table" and entry[field] or nil
  if not label then return nil end
  return require("src.script.Gen2ScriptVM").compile(data, label)
end

function Gen2Commands.phoneCallScript(data, id)
  return phoneScript(data, id, "call")
end

function Gen2Commands.phoneReceiveScript(data, id)
  return phoneScript(data, id, "receive")
end

-- ---------------------------------------------------------------------------
-- Incoming calls (CheckPhoneCall, 36:$4074)
--
-- The overworld step loop rolls for one every step the player is NOT standing
-- on a warp tile.  In order:
--
--   CheckReceiveCallTimer (04:$5401)  -- enough in-game minutes since the last
--       call.  The wait is 20 minutes for the first one and then 10, 5 and 3
--       (NextCallReceiveDelay.ReceiveCallDelays, 04:$53FD), stepping down each
--       time a call lands and never going below 3.
--   Random / and $7F / cp b        -- exactly a one in two coin flip
--   GetMapPhoneService (00:$2D05)  -- the high nibble of the map header's
--       palette byte; nonzero means no signal (caves, most interiors)
--   GetAvailableCallers (36:$40DE) -- every registered contact whose OWN
--       time-of-day mask covers now and who is not on the player's map
--   ChooseRandomCaller (36:$40BF)  -- uniform over that sample
--
-- None of this existed: phoneReceiveScript had no caller at all, so the
-- thirty-odd trainers who take your number never rang once.
-- ---------------------------------------------------------------------------

-- MORN/DAY/NITE, the bits GetPhoneServiceTimeOfDayByte ANDs against the
-- contact's mask.  Contacts with mask 0 -- MOM, ELM, BILL, the BIKE SHOP --
-- can never be sampled, which is the ROM's way of saying they only ever ring
-- through specialphonecall.
local GEN2_TOD_BIT = { MORNING = 1, MORN = 1, DAY = 2, NITE = 4, NIGHT = 4 }

-- ReceiveCallDelays, in in-game minutes, indexed by how many calls have
-- landed already (capped at the last row).
local GEN2_CALL_DELAYS = { 20, 10, 5, 3 }

function Gen2Commands.phoneCallDelay(save)
  local cycles = tonumber(save and save.g2CallCycles) or 0
  return GEN2_CALL_DELAYS[math.min(cycles, #GEN2_CALL_DELAYS - 1) + 1]
end

-- The sample GetAvailableCallers builds, in PHONE_* order.
function Gen2Commands.availableCallers(data, save, mapDef, tod)
  local bit = GEN2_TOD_BIT[tod] or 2
  local out = {}
  local group = mapDef and tonumber(mapDef.group)
  local number = mapDef and tonumber(mapDef.number)
  for id, registered in pairs(phoneList(save)) do
    if registered and type(id) == "number" then
      local entry = phoneContact(data, id)
      local mask = entry and tonumber(entry.receiveTime) or 0
      -- `and [hl]` on the mask, then the map compare
      if entry and entry.receive and mask % (bit * 2) >= bit
         and not (group and entry.group == group and entry.number == number) then
        out[#out + 1] = id
      end
    end
  end
  table.sort(out)
  return out
end

-- Returns the caller id and its compiled receive script, or nil.  `minutes` is
-- the play clock in minutes, which stands in for the ROM's day/hour/minute
-- countdown; `entrance` is CheckStandingOnEntrance.
function Gen2Commands.rollIncomingCall(data, save, mapDef, tod, minutes, entrance)
  if entrance then return nil end
  local last = tonumber(save.g2LastCallMinute)
  if last == nil then
    -- InitCallReceiveDelay at the start of the file: the first call is a full
    -- delay away, not immediate
    save.g2LastCallMinute = minutes
    return nil
  end
  local waited = minutes - last
  -- the clock can wrap or be edited backwards; treat that as "wait again"
  if waited < 0 then
    save.g2LastCallMinute = minutes
    return nil
  end
  if waited < Gen2Commands.phoneCallDelay(save) then return nil end

  -- CheckReceiveCallTimer (04:$5401) consumes the expiry HERE, before any
  -- other gate:
  --
  --     call CheckReceiveCallDelay
  --     ret nc                       ; not expired yet -- nothing changes
  --     ld hl, wTimeCyclesSinceLastCall
  --     ld a, [hl] / cp 3 / jr nc, .ok / inc [hl]
  -- .ok call NextCallReceiveDelay    ; RESTART the timer, call or no call
  --     scf
  --
  -- The delay is an EDGE, not a level.  Only recording the time when a call
  -- actually landed left `waited >= delay` true forever after the first
  -- expiry, so the 50% flip below was re-rolled on EVERY STEP -- a call
  -- within a step or two of the timer coming due, which is the "they ring
  -- constantly" report.  Consume it up front and a failed flip costs a whole
  -- further delay, exactly as on hardware.
  save.g2CallCycles = math.min((tonumber(save.g2CallCycles) or 0) + 1,
                               #GEN2_CALL_DELAYS - 1)
  save.g2LastCallMinute = minutes

  -- `Random / ld b, a / and $7f / cp b` is true only when bit 7 is clear
  if math.random(0, 255) >= 128 then return nil end
  -- GetMapPhoneService: the palette byte's high nibble, nonzero = no service
  local palette = mapDef and tonumber(mapDef.mapPalette) or 0
  if math.floor(palette / 16) % 16 ~= 0 then return nil end
  local callers = Gen2Commands.availableCallers(data, save, mapDef, tod)
  if #callers == 0 then return nil end
  local id = callers[math.random(#callers)]
  local script = Gen2Commands.phoneReceiveScript(data, id)
  if not script then return nil end
  -- InitCallReceiveDelay at the tail of Script_ReceivePhoneCall (36:$42B7):
  -- a call that actually lands puts the cycle counter back to ZERO, i.e. the
  -- next wait is the full 20 minutes again.  The port had this inverted --
  -- it incremented here and never reset -- so after three calls the delay was
  -- pinned at its 3-minute floor for the rest of the save.  The 10/5/3 rows
  -- are for a player who stands in one place long enough to miss several
  -- windows in a row, not a reward for answering the phone.
  Gen2Commands.resetCallDelay(save, minutes)
  return id, script
end

-- InitCallReceiveDelay (04:$53F9).  Also called from StartMap
-- (engine/overworld/events.asm:106), so walking through any door resets the
-- wait to a full 20 minutes -- which is most of why calls are rare in normal
-- play and why the port felt relentless without it.
function Gen2Commands.resetCallDelay(save, minutes)
  if not save then return end
  save.g2CallCycles = 0
  if minutes then save.g2LastCallMinute = minutes end
end

-- RandomPhoneMon (0A:$6567) and RandomPhoneWildMon (0A:$651F) are the two
-- specials every trainer phone script opens with: the first names a mon out of
-- the CALLER'S OWN party ("my {mon} is doing great"), the second one out of
-- the grass table of the caller's map at the current time of day ("I saw a
-- {mon} on {route}").  Both leave the name in a string buffer that the line
-- then splices back in as {RAM:wStringBuffer4}.  Unimplemented, every one of
-- those lines printed the raw token or whatever the buffer last held.
local function callerMapDef(data, entry)
  if not (entry and entry.group and entry.number) then return nil end
  for _, def in pairs(data.maps or {}) do
    if type(def) == "table" and def.group == entry.group
       and def.number == entry.number then
      return def
    end
  end
  return nil
end

local function speciesName(data, species)
  local def = species and (data.pokemon or {})[species]
  return (def and def.name) or (species and tostring(species)) or "POKéMON"
end

-- `sdefer <script>`: park it and carry on.  The overworld runs it on a later
-- frame, once the transition has finished and this script is done -- the same
-- FIFO a warp cutscene uses.  Compiled here rather than at lowering time so
-- the deferred script stays a script of its own instead of being spliced into
-- the caller's row list.
function Commands.g2_sdefer(ctx, label)
  local ow = ctx.overworld
  if not (ow and ow.queueScript and type(label) == "string") then return end
  local ok, rows = pcall(require("src.script.Gen2ScriptVM").compile,
                         ctx.game.data, label)
  if not (ok and type(rows) == "table" and rows[1]) then return end
  ow:queueScript(rows, { mapId = ow.map and ow.map.id })
end

-- ---------------------------------------------------------------------------
-- `special BankOfMom` (5:$6218)
--
-- MomScript's banking branch is `setevent $40 / special BankOfMom /
-- waitbutton / closetext / end`.  There is no writetext in it: the whole
-- conversation is that special, a jumptable over CheckIfBankInitialized,
-- IsThisAboutYourMoney, StopOrStartSavingMoney, StoreMoney, TakeMoney and
-- their four refusals.  With no handler the branch ran silently, which is why
-- Mom said nothing at all once the talk unlocked after the first badge.
--
-- wMomSavingMoney bit 7 is "the bank exists"; bit 0 is "she is putting money
-- aside for you".  Both live on the save here.
-- ---------------------------------------------------------------------------

local GEN2_MONEY_MAX = 999999

local function momLine(ctx, key, fallback)
  local bank = (ctx.game.data.field or {}).gen2MomBank or {}
  return bank[key] or fallback
end

local function momSay(ctx, key, fallback, subs)
  local text = momLine(ctx, key, fallback)
  if text then Commands.show_text(ctx, text, subs) end
end

local function momAmount(ctx, max, onPicked)
  local runner = ctx.runner
  local picked
  require("src.ui.Screens").push(ctx.game, "MoneyEntry", {
    max = max,
    onDone = function(value) picked = value runner:resume() end,
  })
  runner:yield()
  onPicked(picked)
end

function Commands.g2_bank_of_mom(ctx)
  local save = ctx.save
  -- CheckIfBankInitialized: the first visit opens the account and asks
  if save.g2MomBankOpen == nil then
    save.g2MomBankOpen = true
    Commands.ask(ctx, momLine(ctx, "saveMoney",
      "Should I save money for you?"))
    if ctx.lastCheck then
      save.g2MomSaving = true
      return momSay(ctx, "startSavingMoney", "OK, I'll save your money.")
    end
    save.g2MomSaving = false
    return momSay(ctx, "justDoWhatYouCan", "Just do what you can.")
  end

  Commands.ask(ctx, momLine(ctx, "isThisAboutYourMoney",
    "Is this about your money?"))
  if not ctx.lastCheck then return end

  save.g2MomMoney = math.max(0, math.floor(tonumber(save.g2MomMoney) or 0))
  momSay(ctx, "whatDoYouWantToDo", "What do you want to do?")

  local game, runner = ctx.game, ctx.runner
  local choice = 0
  local rows = {
    "SAVE MONEY", "TAKE MONEY",
    save.g2MomSaving and "STOP SAVING" or "START SAVING",
    "CANCEL",
  }
  local items = {}
  for index, label in ipairs(rows) do
    items[index] = {
      label = label,
      onSelect = function() choice = index runner:resume() end,
    }
  end
  game.stack:push(require("src.ui.Menu").new(game, items, {
    onCancel = function() runner:resume() end,
  }))
  runner:yield()

  if choice == 1 then
    local wallet = math.floor(tonumber(save.money) or 0)
    local room = GEN2_MONEY_MAX - save.g2MomMoney
    if wallet <= 0 then
      return momSay(ctx, "insufficientFundsInWallet", "You have no money.")
    end
    if room <= 0 then
      return momSay(ctx, "notEnoughRoomInBank", "I can't hold any more.")
    end
    momSay(ctx, "storeMoney", "How much do you want to store?")
    momAmount(ctx, math.min(wallet, room), function(amount)
      if not amount or amount <= 0 then return end
      save.money = wallet - amount
      save.g2MomMoney = save.g2MomMoney + amount
      ctx.game.stringBuffer = tostring(amount)
      momSay(ctx, "storedMoney", "Stored ¥" .. amount .. ".")
    end)
  elseif choice == 2 then
    local bank = save.g2MomMoney
    local room = GEN2_MONEY_MAX - math.floor(tonumber(save.money) or 0)
    if bank <= 0 then
      return momSay(ctx, "haventSavedThatMuch", "I haven't saved that much.")
    end
    if room <= 0 then
      return momSay(ctx, "notEnoughRoomInWallet", "You can't carry any more.")
    end
    momSay(ctx, "takeMoney", "How much do you want to take?")
    momAmount(ctx, math.min(bank, room), function(amount)
      if not amount or amount <= 0 then return end
      save.g2MomMoney = bank - amount
      save.money = math.floor(tonumber(save.money) or 0) + amount
      ctx.game.stringBuffer = tostring(amount)
      momSay(ctx, "takenMoney", "Took ¥" .. amount .. ".")
    end)
  elseif choice == 3 then
    save.g2MomSaving = not save.g2MomSaving
    if save.g2MomSaving then
      momSay(ctx, "startSavingMoney", "OK, I'll save your money.")
    else
      momSay(ctx, "justDoWhatYouCan", "Just do what you can.")
    end
  end
end

-- `special FindPartyMonThatSpeciesYourTrainerID`: is the party carrying a mon
-- of wScriptVar's species that the player raised themselves -- their own OT
-- name and ID -- rather than one that was traded in?
--
-- ElmEggHatchedScript is nothing but this, twice: `setval TOGEPI / special /
-- iftrue ShowElmTogepiScript / setval TOGETIC / special / iftrue ...`.  With
-- no handler it always answered no, so walking into the lab with the hatched
-- TOGEPI got Elm's old "how is the EGG doing" line for the rest of the game.
function Commands.g2_find_party_species_own(ctx)
  local want = string.format("SPECIES_%03d", math.floor(scriptVar(ctx)) % 256)
  local player = ctx.save.player or {}
  local found = false
  for _, mon in ipairs(ctx.save.party or {}) do
    -- an EGG does not count: the ROM reads the species out of the party slot
    -- and an egg's slot species is the hatchling's, so the check has to skip it
    if mon.species == want and not mon.isEgg then
      local ownName = mon.ot == nil or mon.ot == player.name
      local ownId = mon.otId == nil or mon.otId == player.id
      if ownName and ownId then found = true break end
    end
  end
  ctx.g2Var = found and 1 or 0
  ctx.lastCheck = found
end

-- `special GiveOddEgg` (7E:$74B6): roll a 16-bit Random against
-- OddEggProbabilities -- fourteen cumulative thresholds out of $FFFF -- and
-- hand over that record as an EGG.  Seven species, each listed twice, and the
-- second of every pair carries the shiny DV pair, which is why the Odd Egg is
-- worth collecting at all.
function Commands.g2_give_odd_egg(ctx)
  local data = ctx.game.data
  local def = (data.field or {}).gen2OddEggs
  local eggs = def and def.eggs
  if not (eggs and eggs[1]) then return end
  local roll = math.random(0, 0xFFFF)
  local pick = #eggs
  for i, threshold in ipairs(def.probabilities or {}) do
    if roll <= (tonumber(threshold) or 0xFFFF) then pick = i break end
  end
  local row = eggs[pick] or eggs[1]
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(data, row.species, row.level or 5)
  if type(row.dvs) == "table" and row.dvs[1] and row.dvs[2] then
    local one, two = row.dvs[1], row.dvs[2]
    local atk, dfn = math.floor(one / 16) % 16, one % 16
    local spd, spc = math.floor(two / 16) % 16, two % 16
    mon.dvs = {
      attack = atk, defense = dfn, speed = spd, special = spc,
      hp = (atk % 2) * 8 + (dfn % 2) * 4 + (spd % 2) * 2 + (spc % 2),
    }
    pcall(function()
      mon.stats = require("src.pokemon.Stats")
        .calc(data.pokemon[row.species], mon.level, mon.dvs, mon.statExp)
      mon.hp = mon.stats.hp
    end)
  end
  if row.moves then
    mon.moves = {}
    for _, id in ipairs(row.moves) do
      local md = data.moves[id]
      mon.moves[#mon.moves + 1] = { id = id, pp = md and md.pp or 0 }
    end
  end
  -- `item` is the field the bag, every menu and the exp-share check read;
  -- `heldItem` was written here and by nothing else, so a scripted gift's
  -- held item was invisible to the entire game.
  if row.item then mon.item = row.item end
  mon.happiness = row.happiness or 20
  mon.isEgg = true
  mon.nickname = "EGG"
  mon.eggSteps = require("src.pokemon.DayCare").eggSteps(data, row.species)
  local Party = require("src.pokemon.Party")
  ctx.lastCheck = Party.add(ctx.save.party, mon) and true or false
  ctx.g2Var = ctx.lastCheck and 0 or 1
end

-- The Ruins of Alph chamber walls that a SCRIPT opens.  Both are run by the
-- chamber's own scene script on entry; the wall word is the instruction and
-- these are what notice it has been followed.  See src/script/RuinsOfAlph.lua
-- for the other two, whose trigger is an item and so is called from the item
-- code instead.
function Commands.g2_hooh_chamber(ctx)
  require("src.script.RuinsOfAlph").hoOhChamber(ctx.game)
end

function Commands.g2_omanyte_chamber(ctx)
  require("src.script.RuinsOfAlph").omanyteChamber(ctx.game)
end

-- `special DisplayUnownWords` (22:$6E68): the word the wall's `setval` chose,
-- drawn as 2x2 blocks of the chamber's own tileset, held until A or B.
function Commands.g2_unown_wall(ctx)
  local runner = ctx.runner
  require("src.ui.Screens").push(ctx.game, "UnownWall", {
    word = scriptVar(ctx),
    onDone = function() runner:resume() end,
  })
  runner:yield()
end

function Commands.g2_random_phone_mon(ctx)
  local data = ctx.game.data
  local entry = phoneContact(data, tonumber(ctx.save.g2CurCaller))
  local def = entry and phoneTrainerDef(data, entry)
  local party = def and def.parties and def.parties[entry.trainer or 1]
  if party and #party > 0 then
    -- RandomPhoneMon (0A:$6567) copies into wStringBuffer4 explicitly
    -- (`ld de, wStringBuffer4 / CopyBytes`, engine/overworld/wildmons.asm),
    -- which is the buffer the "my <mon> is doing great" lines splice.
    setBuffer(ctx.game, 4, speciesName(data, party[math.random(#party)].species))
  end
end

function Commands.g2_random_phone_wild_mon(ctx)
  local data = ctx.game.data
  local entry = phoneContact(data, tonumber(ctx.save.g2CurCaller))
  local mapDef = entry and callerMapDef(data, entry)
  local enc = mapDef and (data.encounters or {})[mapDef.id]
  local ow = ctx.overworld
  local band = enc and enc.grass
    and require("src.world.Encounter").atTime(enc.grass,
          (ow and ow.timeOfDay and ow:timeOfDay()) or "DAY")
  local slots = band and band.slots
  -- `Random / and 3`: only the first FOUR rows of the time band are sampled
  if slots and #slots > 0 then
    local row = slots[math.random(math.min(4, #slots))]
    -- wStringBuffer4, same as RandomPhoneMon above
    if row then setBuffer(ctx.game, 4, speciesName(data, row.species)) end
  end
end

-- RandomUnseenWildMon (0A:$65A0): the third phone-caller special, and the one
-- that was still missing.  It picks one of the three RAREST grass slots on the
-- caller's own route and, if the player has never SEEN that species, has the
-- caller tell them about it -- which is how the phone points you at Yanma,
-- Dunsparce and the rest.
--
-- The answer is inverted from the usual sense: 0 means "I just told you about
-- one" and 1 means "nothing rare to mention", and the caller's script picks
-- which line to close on from that.  Falling through to g2_special answered
-- false, which is 0, so every caller claimed to have described a mon and then
-- printed an empty name.
--
-- Faithful to the cartridge's own quirk: the rare pick is compared against
-- only the FOUR commonest slots, so a species that also appears in slot 5 or 6
-- still counts as rare.
function Commands.g2_random_unseen_wild_mon(ctx)
  local data = ctx.game.data
  local function nothing()
    ctx.g2Var, ctx.lastCheck = 1, true
  end
  local entry = phoneContact(data, tonumber(ctx.save.g2CurCaller))
  local mapDef = entry and callerMapDef(data, entry)
  local enc = mapDef and (data.encounters or {})[mapDef.id]
  local ow = ctx.overworld
  local band = enc and enc.grass
    and require("src.world.Encounter").atTime(enc.grass,
          (ow and ow.timeOfDay and ow:timeOfDay()) or "DAY")
  local slots = band and band.slots
  if not (slots and #slots >= 5) then return nothing() end
  -- `ld bc, 5 + 4 * 2` walks to the fifth row, then `Random / and 3` (re-rolled
  -- on 0) picks one of the three behind it
  local row = slots[#slots - math.random(0, 2)]
  local species = row and row.species
  if not species then return nothing() end
  for index = 1, math.min(4, #slots) do
    if slots[index] and slots[index].species == species then return nothing() end
  end
  local dex = ctx.save.pokedex
  if dex and dex.seen and dex.seen[species] then return nothing() end
  setBuffer(ctx.game, 4, speciesName(data, species))
  ctx.g2Var, ctx.lastCheck = 0, false
end

-- ---------------------------------------------------------------------------
-- specialphonecall
--
-- Script_specialphonecall just parks the SPECIALCALL_* id in
-- wSpecialPhoneCallID; CheckSpecialPhoneCall (36:$413E) runs off the overworld
-- step loop and only rings once the row's condition holds -- which for the
-- post-Falkner egg call is SpecialCallOnlyWhenOutside, so Elm waits until you
-- are back on the town map.  Mirror that with a pending id on the save and a
-- poll in OverworldState:update rather than firing inside the gym script.
-- ---------------------------------------------------------------------------

function Commands.g2_special_call(ctx, id)
  if type(id) ~= "number" then return end
  -- SPECIALCALL_NONE cancels whatever was armed, and it is how the caller
  -- script itself signs off, so it clears the in-flight id too
  ctx.save.g2SpecialCall = id ~= 0 and id or nil
  if id == 0 then ctx.save.g2SpecialCallActive = nil end
end

-- wSpecialPhoneCallID stays set while the caller script runs -- that is how
-- ElmPhoneCallerScript's `readvar 20` knows which of its five lines to say.
-- checkSpecialPhoneCall disarms g2SpecialCall as it fires so the poll cannot
-- ring twice, so the id it fired lives on here until the script signs off.
-- DOWN/UP/LEFT/RIGHT, the order _GetVarAction.PlayerFacing produces:
-- `ld a, [wPlayerDirection] / and $0c / rrca / rrca`.
local GEN2_FACING = { down = 0, up = 1, left = 2, right = 3 }

local function countKeys(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- _GetVarAction.VarActionTable (01:$4671), the twenty-seven rows `readvar`
-- indexes.  Rows 12/13/15/18/19 are plain wram reads and 23 is wCurCaller --
-- all of them phone-script territory, and all of them answered 0 before, which
-- is why MomPhoneLandmark (2F:$4EB7) took its `readvar 15 / ifequal 1` route
-- branch inside a building and every shared trainer phone script fell out the
-- bottom of its `readvar 23 / ifequal <PHONE_*>` ladder onto the wrong line.
local GEN2_TOD_VALUE = { MORNING = 0, MORN = 0, DAY = 1, NITE = 2, NIGHT = 2 }

function Commands.g2_readvar(ctx, var)
  if var == 1 then
    ctx.g2Var = #(ctx.save.party or {})
  elseif var == 20 then
    ctx.g2Var = ctx.save.g2SpecialCallActive or ctx.save.g2SpecialCall or 0
  elseif var == 23 then
    -- wCurCaller: the PHONE_* id of whoever is on the line.  Both directions
    -- set it (the POKeGEAR when the player rings out, checkPhoneCall when a
    -- contact rings in), and it is nil off a call, which reads as 0 -- the
    -- same "no caller" the ROM's cleared byte gives.
    ctx.g2Var = tonumber(ctx.save.g2CurCaller) or 0
  elseif var == 4 then
    -- wTimeOfDay: MORN 0, DAY 1, NITE 2
    local ow = ctx.overworld
    local tod = ow and ow.timeOfDay and ow:timeOfDay()
    ctx.g2Var = GEN2_TOD_VALUE[tod] or 1
  elseif var == 12 or var == 13 then
    -- wMapGroup / wMapNumber, which MomPhoneInTown branches on by town
    local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
    ctx.g2Var = tonumber(def and (var == 12 and def.group or def.number)) or 0
  elseif var == 15 then
    -- wEnvironment (the map header's environment byte: 1 TOWN, 2 ROUTE,
    -- 3 INDOOR, 4 CAVE, 5 ENVIRONMENT_5, 6 GATE, 7 DUNGEON)
    local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
    ctx.g2Var = tonumber(def and def.environment) or 0
  elseif var == 18 or var == 19 then
    -- wXCoord / wYCoord: the player's cell within the map, 0-based, the same
    -- frame the warp_event and object_event tables are stored in.
    local player = ctx.overworld and ctx.overworld.player
    local cell = player and (var == 18 and player.cellX or player.cellY)
    ctx.g2Var = tonumber(cell) or 0
  elseif var == 9 then
    local player = ctx.overworld and ctx.overworld.player
    ctx.g2Var = GEN2_FACING[player and player.facing] or 0
  elseif var == 5 then
    ctx.g2Var = countKeys(ctx.save.pokedex and ctx.save.pokedex.owned)
  elseif var == 6 then
    ctx.g2Var = countKeys(ctx.save.pokedex and ctx.save.pokedex.seen)
  elseif var == 10 then
    ctx.g2Var = tonumber(os.date("%H")) or 0
  elseif var == 11 then
    -- g2DayOffset is what mom's SetDayOfWeek picker answered, as a shift off
    -- the host day, so Arthur still shows up on a real Thursday.
    ctx.g2Var = ((tonumber(os.date("%w")) or 0)
      + (ctx.save.g2DayOffset or 0)) % 7
  elseif var == 16 then
    -- BoxFreeSpace: the port never fills a box, so every script that
    -- branches on "is the box full" must take the not-full path
    ctx.g2Var = 20
  elseif var == 17 then
    -- wBugContestMinsRemaining.  StartBugContestTimer writes 20 minutes / 0
    -- seconds and the timer counts down, so this is the WHOLE minutes left --
    -- which is why the gate officer's line is `readvar VAR_CONTESTMINUTES /
    -- addval 1`, rounding 19:37 up to "20 minutes".  Unhandled it fell through
    -- to 0 and he told everyone they had one minute left, however long they
    -- had just walked in.
    local BugContest = require("src.world.BugContest")
    ctx.g2Var = math.floor(BugContest.secondsLeft(ctx.save) / 60)
  elseif var == 7 then
    -- CountBadges (03:$41BE) is `ld hl, wBadges / ld b, 2 / CountSetBits`,
    -- i.e. both badge bytes.  This used to walk a `save.badges` table that
    -- nothing ever writes -- Gen2 gyms run `setflag ENGINE_<X>BADGE`, which
    -- Flags puts in save.flags under the badge id -- so it always answered 0.
    -- MahoganyGymPryceScript is `readvar 7 / scall MahoganyGymActivateRockets`
    -- (`ifequal 7 -> RadioTowerRocketsScript`), so a stuck 0 meant beating
    -- Pryce never armed Elm's takeover call (specialphonecall 4) nor set
    -- ENGINE_ROCKETS_IN_RADIO_TOWER -- the Goldenrod Rocket event never began.
    ctx.g2Var = require("src.inventory.Badges")
                  .count(ctx.game and ctx.game.data, ctx.save)
  elseif var == 24 then
    -- wBlueCardBalance: Buena's Blue Card, one point a night, capped at 30
    ctx.g2Var = ctx.save.g2BlueCard or 0
  elseif var == 26 then
    -- wKenjiBreakTimer: days until the Route 39 trainer takes his break,
    -- sampled by `special SampleKenjiBreakCountdown`
    ctx.g2Var = ctx.save.g2KenjiBreak or 0
  elseif var == 14 then
    -- UnownCaught (engine/events/unown_walls.asm): how many distinct UNOWN
    -- letters are in the dex.  The port has no per-letter model, so a caught
    -- UNOWN counts once -- enough for the Ruins researcher's `ifgreater 2`
    -- to stay shut until the player has actually been catching them.
    local dex = ctx.save.pokedex
    local owned = dex and dex.unownForms
    local n = 0
    for _ in pairs(owned or {}) do n = n + 1 end
    ctx.g2Var = n
  else
    ctx.g2Var = 0
  end
  ctx.lastCheck = (ctx.g2Var or 0) ~= 0
end

-- `writevar <var>`: the script variable back into the stored byte.  Only the
-- vars Gen2ScriptVM's WRITEBACK_VARS lists reach here.
function Commands.g2_writevar(ctx, var)
  local value = math.floor(scriptVar(ctx)) % 256
  if var == 24 then
    ctx.save.g2BlueCard = value
  elseif var == 26 then
    ctx.save.g2KenjiBreak = value
  end
end

-- `loadvar 3, n` writes wBattleType ($D119).  BATTLETYPE_SHINY is 7; the
-- byte is consumed by the next startbattle and cleared with the rest of the
-- battle variables afterwards, so it is deliberately NOT saved.
Commands.G2_BATTLETYPE_SHINY = 7

function Commands.g2_loadvar(ctx, var, value)
  if var == 3 then ctx.g2BattleType = tonumber(value) or 0 end
end

-- Returns the caller's PHONE_* id and the decoded script for the armed call,
-- or nil when nothing is pending or its condition has not come round yet.
function Gen2Commands.pendingSpecialCall(data, save, outside)
  local id = save and save.g2SpecialCall
  if type(id) ~= "number" then return nil end
  local pool = data and data.map_scripts
  local row = pool and pool.specialCalls and pool.specialCalls[id]
  if type(row) ~= "table" then return nil end
  if row.outside and not outside then return nil end
  local script = row.script
    and require("src.script.Gen2ScriptVM").compile(data, row.script) or nil
  if not script then return nil end
  return row.caller, script
end

-- wPhoneList is TEN bytes (_CheckCellNum walks `ld b, $0A`), and
-- Phone_FindOpenSlot (36:$402D) fails when none of them is free.  That cap is
-- the whole point of the ".PhoneFull" branch every phone trainer carries -- an
-- uncapped list can never reach it.
local GEN2_PHONE_SLOTS = 10

local function phoneListCount(save)
  local n = 0
  for _, registered in pairs(phoneList(save)) do
    if registered then n = n + 1 end
  end
  return n
end

-- AddPhoneNumber (36:$4000): carry means "not added" -- either the id is
-- already in the list or there is no free slot.
local function addPhoneNumber(save, id)
  local list = phoneList(save)
  if list[id] then return false end
  if phoneListCount(save) >= GEN2_PHONE_SLOTS then return false end
  list[id] = true
  return true
end

function Commands.g2_cellnum(ctx, id, add)
  if type(id) ~= "number" then return end
  if add then
    ctx.lastCheck = addPhoneNumber(ctx.save, id)
  else
    local list = phoneList(ctx.save)
    ctx.lastCheck = list[id] == true
    list[id] = nil
  end
end

function Commands.g2_check_cellnum(ctx, id)
  ctx.lastCheck = phoneList(ctx.save)[id] == true
  ctx.g2Var = ctx.lastCheck and 1 or 0
end

-- Script_askforphonenumber (25:$70BE), read straight off the cartridge:
--
--   YesNoBox / jr c, .refused        ; NO
--   GetScriptByte / farcall AddPhoneNumber
--   jr c, .phonefull                 ; already listed, or no free slot
--   xor a / jr .done                 ; 0 = number saved
--   .phonefull: ld a, 1
--   .refused:   ld a, 2
--   .done: ld [wScriptVar], a
--
-- So it is **1 = list full, 2 = declined** -- the opposite way round from what
-- this used to write.  Every phone trainer branches `ifequal 1 .PhoneFull /
-- ifequal 2 .Declined`, so turning a trainer down ran the "your POKeGEAR is
-- full" line instead of the polite one, and the number was never saved.
--
-- The prompt rides the box the preceding writetext already opened, exactly
-- like yesorno.
function Commands.g2_ask_cellnum(ctx, id, textId)
  if type(id) ~= "number" then
    ctx.g2Var = 1
    return
  end
  Commands.ask(ctx, textId or ctx.g2LastText)
  if not ctx.lastCheck then
    ctx.g2Var = 2
    return
  end
  if addPhoneNumber(ctx.save, id) then
    ctx.g2Var = 0
  else
    ctx.g2Var = 1
  end
end

-- ---------------------------------------------------------------------------
-- follow / stopfollow
--
-- `follow leader, follower` (Script_follow -> StartFollow, b = leader,
-- c = follower) only records the pair; the walking itself happens on the
-- leader's next applymovement, in g2_move above.
-- ---------------------------------------------------------------------------

function Commands.g2_follow(ctx, leader, follower)
  if leader == nil then
    ctx.g2FollowLeader, ctx.g2FollowTarget = nil, nil
    return
  end
  ctx.g2FollowLeader, ctx.g2FollowTarget = leader, follower
end

-- specials and std scripts are engine calls; the port implements the ones it
-- needs elsewhere, so log the rest once rather than aborting the script
local warned = {}
local function warnOnce(kind, id)
  local key = kind .. tostring(id)
  if warned[key] then return end
  warned[key] = true
  Logger.warn("gen2 script: unhandled %s %s", kind, tostring(id))
end

function Commands.g2_special(ctx, id)
  warnOnce("special", id)
  ctx.lastCheck = false
end

-- `special HealMachineAnim` ($3D).  PokecenterNurseScript runs the machine
-- itself and HealParty ($1B) only touches party data, so with this special
-- dropped the Gen2 nurse healed in silence with no balls and no jingle.
--
-- The nurse stops the map theme with `playmusic MUSIC_NONE` one command
-- earlier, so stopping again is a no-op that only keeps this correct for a
-- caller that does not.  The jingle restores the map theme when it ends,
-- which is why the RestartMapMusic ($3C) that follows is a VM no-op --
-- honouring it would cut the jingle off after the nurse's `pause 30`.
function Commands.g2_heal_machine_anim(ctx)
  local ow = ctx.overworld
  local runner = ctx.runner
  if not (ow and runner and ow.player) then return end
  require("src.core.Music").stop()
  ow.healAnim = {
    balls = #ctx.save.party,
    lit = 0,
    timer = 0,
    visible = true,
    px = ow.player.cellX * 16,
    py = ow.player.cellY * 16,
    onDone = function() runner:resume() end,
  }
  runner:yield()
end

-- `special InitialSetDSTFlag` ($6C) / `InitialClearDSTFlag` ($6D): mom's clock
-- talk.  Each records wDST and prints its own first box, and Gen2ScriptVM
-- emits the second one so the script's following `yesorno` confirms THAT --
-- stubbed, the yesorno re-asked "Is it DAYLIGHT SAVING TIME?" instead.
-- Nothing reads save.g2DST yet; DSTChecks is not ported.
function Commands.g2_set_dst(ctx)
  ctx.save.g2DST = true
  Commands.show_text(ctx, "InitialSetDSTFlag.Text")
end

function Commands.g2_clear_dst(ctx)
  ctx.save.g2DST = nil
  Commands.show_text(ctx, "InitialClearDSTFlag.Text")
end

-- The ROM spins these with the d-pad on a graphical clock-set background;
-- a list menu is the port's equivalent and needs no ROM tiles.  The names
-- are engine text, not ROM strings: SetDayOfWeek.WeekdayStrings is raw
-- charmap data, and the extractor only harvests symbols matching "Text".
local WEEKDAYS = {
  "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY",
}

-- `special SetDayOfWeek` ($25), the day picker in mom's clock talk.  The GB
-- has to ask because its RTC has no idea what day it started on; here
-- readvar 11 reads the host clock, which already knows.  So the answer is
-- kept as an OFFSET from the host day rather than as the day itself: the
-- cursor opens on today, a truthful answer stores 0 and changes nothing, and
-- either way the day still rolls over at real midnight instead of freezing.
function Commands.g2_set_day_of_week(ctx)
  local game, runner = ctx.game, ctx.runner
  local host = tonumber(os.date("%w")) or 0
  local picked
  repeat
    Commands.show_text(ctx, "SetDayOfWeek.OakTimeWhatDayIsItText")
    local items = {}
    for index, day in ipairs(WEEKDAYS) do
      items[index] = {
        label = Strings(day),
        onSelect = function() picked = index - 1 runner:resume() end,
      }
    end
    -- no cancel: the ROM's loop watches A only, and onCancel is the only
    -- other path back to runner:resume()
    local menu = require("src.ui.Menu").new(game, items, { cancelable = false })
    menu.index = host + 1
    menu:clampScroll()
    game.stack:push(menu)
    runner:yield()
    Commands.ask(ctx, Strings(WEEKDAYS[picked + 1])
      .. resolvedText(ctx, "SetDayOfWeek.OakTimeIsItText"))
  until ctx.lastCheck
  ctx.save.g2DayOffset = (picked - host) % 7
end

-- UnownPuzzle (SpecialsPointers row 41).  The chamber scripts run
-- `setval <picture>` first, so the picture rides in on wScriptVar, and the
-- caller branches on `iftrue` -- i.e. on ctx.lastCheck -- to open the wall.
function Commands.g2_unown_puzzle(ctx)
  local game = ctx.game
  local runner = ctx.runner
  if not (game and game.stack and runner) then
    ctx.lastCheck = false
    return
  end
  local picture = scriptVar(ctx)
  local UnownPuzzle = require("src.ui.UnownPuzzle")
  game.stack:push(UnownPuzzle.new(game, picture, function(solved)
    ctx.lastCheck = solved and true or false
    runner:resume()
  end))
  runner:yield()
end

-- StdScripts fallback when the extracted body was not linked into the IR
-- pool.  Index 0 is PokecenterNurseScript — without this, every Center nurse
-- that still lowers to g2_std is a silent no-op.
local STD_POKECENTER_NURSE = 0

function Commands.g2_std(ctx, id)
  local index = tonumber(id) or id
  if index == STD_POKECENTER_NURSE or index == "pokecenternurse"
      or index == "POKECENTER_NURSE" then
    -- Inline PokecenterNurseScript: welcome → yes/no → heal + machine → bye.
    local t = ctx.game.data and ctx.game.data.text or {}
    local bye = t._PokemonCenterFarewellText
      or "We hope to see\nyou again!"
    local hello = t._PokemonCenterWelcomeText
      or "Welcome to our\nPOKéMON CENTER!"
    if not ctx.save.usedPokecenter then
      ctx.save.usedPokecenter = true
      hello = hello .. "\f"
        .. (t._ShallWeHealYourPokemonText or "Shall we heal your\nPOKéMON?")
    end
    Commands.ask(ctx, hello)
    if not ctx.lastCheck then
      Commands.show_text(ctx, bye)
      return
    end
    local need = t._NeedYourPokemonText or "OK. We'll need\nyour POKéMON."
    Commands.show_text(ctx, need)
    Commands.g2_heal_party(ctx)
    -- Record the blackout/heal point so Escape Rope / white-out work.
    local ow = ctx.overworld
    if ow and ow.map and ow.player then
      ctx.save.lastHeal = {
        map = ow.map.id,
        x = ow.player.cellX,
        y = ow.player.cellY,
        outdoor = ow.lastOutdoor and {
          id = ow.lastOutdoor.id, x = ow.lastOutdoor.x, y = ow.lastOutdoor.y,
        } or nil,
      }
    end
    Commands.g2_heal_machine_anim(ctx)
    local fit = t._PokemonFightingFitText
      or "Your POKéMON are\nfighting fit!"
    Commands.show_text(ctx, fit)
    Commands.show_text(ctx, bye)
    return
  end
  warnOnce("std script", id)
end

-- ---------------------------------------------------------------------------
-- Kurt's apricorns (SelectApricornForKurt)
--
-- The special opens the ITEM pocket filtered to apricorns, removes the one
-- you pick from the bag itself, and leaves its item id in wScriptVar for the
-- run of `ifequal` rows that decide which ball Kurt starts on.
-- ---------------------------------------------------------------------------

-- RED, BLU, BLK, WHT, PNK, GRN, YLW -- the same ids Kurt1 `checkitem`s before
-- it bothers to ask
local APRICORNS = { 85, 89, 92, 93, 97, 99, 101 }

function Commands.g2_select_apricorn(ctx)
  local game, runner, save = ctx.game, ctx.runner, ctx.save
  local Bag = require("src.inventory.Bag")
  local Menu = require("src.ui.Menu")
  local picked, held, items = 0, 0, {}
  -- SelectApricornForKurt zeroes wKurtApricornQuantity on entry, so a
  -- cancelled pick cannot leave the previous count standing.
  save.g2KurtApricorns = 0
  for _, id in ipairs(APRICORNS) do
    local key = string.format("ITEM_%03d", id)
    local qty = save.inventory and save.inventory[key] or 0
    if qty > 0 then
      local def = game.data.items and game.data.items[key]
      items[#items + 1] = {
        label = string.format("%s x%d", (def and def.name) or key, qty),
        onSelect = function() picked, held = id, qty runner:resume() end,
      }
    end
  end
  if #items == 0 then
    ctx.g2Var, ctx.lastCheck = 0, false
    return
  end
  game.stack:push(Menu.new(game, items, {
    onCancel = function() runner:resume() end,
  }))
  runner:yield()
  if picked == 0 then
    ctx.g2Var, ctx.lastCheck = 0, false
    return
  end

  -- "How many should I make?" -- Kurt_SelectQuantity (engine/events/kurt.asm)
  -- loads wItemQuantity with how many of that apricorn you HAVE and lets you
  -- scroll 1..that, then Kurt_GiveUpSelectedQuantityOfSelectedApricorn takes
  -- exactly that many and the count goes into wKurtApricornQuantity --
  -- VAR_KURT_APRICORNS, which the `verbosegiveitemvar` on the collection
  -- branch reads back to decide how many balls to hand over.
  --
  -- Taking one apricorn and never writing that var is what left the var at 0
  -- and, with verbosegiveitemvar unlowered as well, Kurt holding a ball he
  -- could never give.
  local count = 1
  if held > 1 then
    local rows = {}
    for n = 1, held do
      rows[#rows + 1] = {
        label = string.format("x%d", n),
        onSelect = function() count = n runner:resume() end,
      }
    end
    game.stack:push(Menu.new(game, rows, {
      -- backing out of the quantity box returns to the apricorn list on
      -- hardware; one apricorn is the closest single-step equivalent here
      onCancel = function() count = 1 runner:resume() end,
    }))
    runner:yield()
  end
  count = math.max(1, math.min(count, held))
  Bag.remove(save, string.format("ITEM_%03d", picked), count)
  save.g2KurtApricorns = count
  ctx.g2Var, ctx.lastCheck = picked, true
end

-- ---------------------------------------------------------------------------
-- Mania's SHUCKIE (GiveShuckle 01:$73E1, ReturnShuckie 01:$7452)
--
-- Not a `givepoke`: the special stamps a fixed OT ("MANIA", ID $0206),
-- nickname and held BERRY, and ReturnShuckie recognises its own mon by
-- exactly that stamp -- species, OT id AND OT name all have to match or the
-- player is told they don't have it.
-- ---------------------------------------------------------------------------

local SHUCKIE_OT, SHUCKIE_OT_ID = "MANIA", 0x0206

-- ---------------------------------------------------------------------------
-- PRISM'S NOBU'S AGGRON -- SpecialGiveNobusAggron / SpecialReturnNobusAggron
-- (engine/specials2.asm).  Structurally Crystal's Shuckie: a trainer lends the
-- player a mon and later asks for it back, and the return refuses unless the
-- one handed over is the very mon they gave.  The numbers are Prism's own,
-- read off the routine: AGGRON at level 40 holding a Metal Coat, OT "Nobu"
-- (female), OT ID 518, nicknamed "Aggron".
local NOBU_OT, NOBU_OT_ID = "Nobu", 518

function Commands.g2_give_nobus_aggron(ctx)
  local Party = require("src.pokemon.Party")
  if #ctx.save.party >= Party.MAX then
    ctx.g2Var, ctx.lastCheck = 0, false
    return
  end
  local mon = require("src.pokemon.Pokemon").new(ctx.game.data, "SPECIES_045", 40)
  mon.nickname = "Aggron"
  mon.ot, mon.otId, mon.traded = NOBU_OT, NOBU_OT_ID, true
  mon.item = "ITEM_143"  -- METAL_COAT
  -- CheckForSpecialGiftMon (engine/billspc.asm) tests for an "F" byte written
  -- past the OT name's terminator -- the marker SpecialGiveNobusAggron sets on
  -- the mon it lends.  It is what stops the player depositing or handing over
  -- a borrowed mon, so it has to be recorded, not just implied by the OT.
  mon.giftMon = true
  Party.add(ctx.save.party, mon)
  ctx.g2Var, ctx.lastCheck = 1, true
end

-- The return's answers are Prism's, and they are NOT Shuckie's: 1 backed out
-- of the party menu, 0 handed over the wrong mon, 3 it is the only one still
-- standing, 2 gave it back.  Crystal's version adds a happiness test at 3 --
-- Prism has none, so borrowing Shuckie's codes here would have had Nobu
-- refuse his own Aggron whenever the player had raised it.
function Commands.g2_return_nobus_aggron(ctx)
  local game, runner = ctx.game, ctx.runner
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()
  local function result(n) ctx.g2Var, ctx.lastCheck = n, n ~= 0 end
  if not picked then return result(1) end
  if picked.species ~= "SPECIES_045" or picked.otId ~= NOBU_OT_ID
     or picked.ot ~= NOBU_OT then
    return result(0)
  end
  local Party = require("src.pokemon.Party")
  local othersHealthy = false
  for _, mon in ipairs(ctx.save.party) do
    if mon ~= picked and not Party.isEgg(mon) and (mon.hp or 0) > 0 then
      othersHealthy = true
    end
  end
  if not othersHealthy then return result(3) end
  for i, mon in ipairs(ctx.save.party) do
    if mon == picked then table.remove(ctx.save.party, i) break end
  end
  result(2)
end

-- `SpecialSeenMon` (engine/specials.asm): `hScriptVar - 1` into SetSeenMon.
-- The variable holds a 1-based species number, so a script can mark a mon
-- seen without the player having met it -- which is how Prism's dex-hint NPCs
-- work.  Unlowered they marked nothing and the entry stayed blank.
-- `Special_SelectMonFromParty` (engine/specials.asm): opens the party menu and
-- answers with the chosen mon.  Three outcomes, and the script branches on all
-- three -- 0 backed out, $FF picked a mon the game will not let go of (the
-- CheckForSpecialGiftMon test above), otherwise the species number itself,
-- with its name left in the string buffer for the line that follows.
function Commands.g2_select_mon_from_party(ctx)
  local game, runner = ctx.game, ctx.runner
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()
  if not picked then
    ctx.g2Var, ctx.lastCheck = 0, false
    return
  end
  if picked.giftMon then
    ctx.g2Var, ctx.lastCheck = 0xFF, true
    return
  end
  local index = tonumber(tostring(picked.species or ""):match("(%d+)$")) or 0
  ctx.g2Var, ctx.lastCheck = index, index ~= 0
  -- the name the following text splices in
  ctx.g2MonName = picked.nickname or picked.species
end


function Commands.g2_seen_mon(ctx)
  local n = ctx.g2Var or 0
  if n < 1 then return end
  local dex = ctx.save.pokedex
  if dex and dex.seen then dex.seen[string.format("SPECIES_%03d", n)] = true end
end

-- `GetFirstPokemonHappiness` (engine/happiness.asm): walks past EGGs to the
-- first real party mon and answers its happiness byte.  Scripts branch on the
-- value, so leaving it to g2_special -- which answers a flat false -- took the
-- unhappy arm every time.
function Commands.g2_first_happiness(ctx)
  local Party = require("src.pokemon.Party")
  for _, mon in ipairs(ctx.save.party or {}) do
    if not Party.isEgg(mon) then
      ctx.g2Var = mon.happiness or 0
      ctx.lastCheck = ctx.g2Var ~= 0
      return
    end
  end
  ctx.g2Var, ctx.lastCheck = 0, false
end


function Commands.g2_give_shuckle(ctx)
  local Party = require("src.pokemon.Party")
  if #ctx.save.party >= Party.MAX then
    ctx.g2Var, ctx.lastCheck = 0, false
    return
  end
  local mon = require("src.pokemon.Pokemon").new(ctx.game.data, "SPECIES_213", 15)
  mon.nickname = "SHUCKIE"
  mon.ot, mon.otId, mon.traded = SHUCKIE_OT, SHUCKIE_OT_ID, true
  mon.item = "ITEM_173" -- BERRY
  Party.add(ctx.save.party, mon)
  -- $D968 bit 5, the flag ManiaScript's `checkflag 84` reads to decide
  -- whether he is willing to ask for it back yet
  require("src.script.Flags").set(ctx.save, "FLAG_G2_0084")
  ctx.g2Var, ctx.lastCheck = 1, true
end

-- ---------------------------------------------------------------------------
-- `trade <NPCTRADE_*>` -- the seven in-game trades (NPCTrade, 3F:$4BA8)
--
-- The routine in order, which is the order below:
--
--   Trade_GetDialog                     -- which of the four dialog sets
--   TradeFlagAction b=2 (FLAG_TEST)     -- already traded -> the "after" line
--   PrintTradeText 0 + YesNoBox         -- the offer; NO -> the "declined" line
--   ChooseMonToTrade                    -- backing out is also "declined"
--   cp wCurPartySpecies                 -- wrong species -> the "wrong" line
--   CheckTradeGender                    -- wrong gender  -> the "wrong" line
--   TradeFlagAction b=1 (FLAG_SET)      -- once only, before the swap
--   NPCTradeCableText / DoNPCTrade / the trade animation / TradedForText
--   PrintTradeText 3                    -- the thanks
--
-- GetTradeMonNames (3F:$4E1B) fills the buffers the lines splice: the mon the
-- NPC hands over goes in wStringBuffer2 and the one the player gives goes in
-- wMonOrItemNameBuffer, with a gender symbol appended to wStringBuffer1.
-- ---------------------------------------------------------------------------

local GEN2_TRADE_GENDER = { [1] = "male", [2] = "female" }

function Commands.g2_trade(ctx, index)
  local game, runner = ctx.game, ctx.runner
  local data = game.data
  local def = (data.field or {}).gen2Trades
  local trade = def and def.trades and def.trades[(tonumber(index) or 0) + 1]
  if not trade then
    Logger.warn("g2_trade: no trade %s", tostring(index))
    return
  end
  local texts = def.texts or {}
  local set = (tonumber(trade.dialog) or 0) + 1

  local function nameOf(species)
    local mon = species and (data.pokemon or {})[species]
    return (mon and mon.name) or tostring(species)
  end
  local giveName, getName = nameOf(trade.give), nameOf(trade.get)
  -- the gender symbol GetTradeMonNames appends to wStringBuffer1
  local mark = ({ male = "♂", female = "♀" })[GEN2_TRADE_GENDER[trade.gender]]
  -- The three buffers GetTradeMonNames fills, by the token the extractor
  -- actually emits.  gen2RamName has no symbol for any of these addresses, so
  -- decodeGen2TextAt falls back to the bare hex -- "{RAM:D073}", not
  -- "{RAM:wStringBuffer1}" -- which is why every one of these lines came out
  -- with a blank where the species name belongs ("Want to trade it for my ?").
  -- Both spellings are listed so the substitution survives the day a symbol
  -- for them turns up in the manifest.
  --
  --   D073 wStringBuffer1        the mon the player hands over, + gender mark
  --   D050 wMonOrItemNameBuffer  the same mon, without the mark
  --   D086 wStringBuffer2        the mon the NPC hands back
  local subs = {
    ["RAM:D073"] = giveName .. (mark or ""),
    ["RAM:wStringBuffer1"] = giveName .. (mark or ""),
    ["RAM:D050"] = giveName,
    ["RAM:wMonOrItemNameBuffer"] = giveName,
    ["RAM:D086"] = getName,
    ["RAM:wStringBuffer2"] = getName,
  }
  local function line(kind)
    local rows = texts[kind]
    return type(rows) == "table" and rows[set] or nil
  end
  local function say(kind, fallback)
    local text = line(kind) or fallback
    if text then Commands.show_text(ctx, text, subs) end
  end

  -- wTradeFlags, one bit per trade: each of the seven happens exactly once
  ctx.save.g2Trades = ctx.save.g2Trades or {}
  local done = ctx.save.g2Trades
  if done[tonumber(index) or -1] then
    return say("afterTrade", Strings("How is my old %s?", giveName))
  end

  local offer = line("offer")
  if offer then
    Commands.ask(ctx, offer, subs)
  else
    Commands.ask(ctx, Strings("I'll trade my %s\nfor your %s. OK?", getName, giveName), subs)
  end
  if not ctx.lastCheck then
    return say("declined", Strings("You don't want to\ntrade? Aww…"))
  end

  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()
  if not picked then
    return say("declined", Strings("You don't want to\ntrade? Aww…"))
  end
  if picked.species ~= trade.give then
    return say("wrongMon", Strings("Huh? That's not\n%s.", giveName))
  end
  -- CheckTradeGender (3F:$4C23): only DORIS the DODRIO asks, and she asks for
  -- a female DRAGONAIR.  Gender is read off the mon the same way the summary
  -- screen reads it, from the attack DV against the species' gender ratio.
  local want = GEN2_TRADE_GENDER[trade.gender]
  if want then
    local have = require("src.pokemon.DayCare").gender(data, picked)
    if have ~= want then
      return say("wrongMon", Strings("Huh? That's not\n%s.", giveName))
    end
  end

  local party = ctx.save.party
  local slot
  for i, mon in ipairs(party) do
    if mon == picked then slot = i break end
  end
  if not slot then return end

  done[tonumber(index)] = true
  if texts.cable then Commands.show_text(ctx, texts.cable, subs) end

  -- DoNPCTrade: the received mon is built from the table's own nickname, DVs,
  -- OT name and OT ID, and keeps the sent mon's level (ComputeNPCTrademonStats
  -- recalculates its stats from those DVs at that level).
  local Pokemon = require("src.pokemon.Pokemon")
  local sent = party[slot]
  local newMon = Pokemon.new(data, trade.get, sent.level)
  if trade.nickname and trade.nickname ~= "" then
    newMon.nickname = trade.nickname
  end
  -- The table's two DV bytes are the usual packed nibble pairs -- attack and
  -- defense in the first, speed and special in the second -- and the HP DV is
  -- the four low bits, exactly as Stats.randomDVs derives it.
  if type(trade.dvs) == "table" and trade.dvs[1] and trade.dvs[2] then
    local one, two = trade.dvs[1], trade.dvs[2]
    local atk, dfn = math.floor(one / 16) % 16, one % 16
    local spd, spc = math.floor(two / 16) % 16, two % 16
    local dvs = {
      attack = atk, defense = dfn, speed = spd, special = spc,
      hp = (atk % 2) * 8 + (dfn % 2) * 4 + (spd % 2) * 2 + (spc % 2),
    }
    newMon.dvs = dvs
    pcall(function()
      local speciesDef = data.pokemon[trade.get]
      newMon.stats = require("src.pokemon.Stats")
        .calc(speciesDef, newMon.level, dvs, newMon.statExp)
      newMon.hp = newMon.stats.hp
    end)
  end
  newMon.traded = true      -- boosted exp, and the Name Rater refuses it
  newMon.ot = (trade.ot ~= "" and trade.ot) or "TRAINER"
  newMon.otId = tonumber(trade.otId) or 0
  -- The npctrade row's item byte: every one of these mons arrives HOLDING
  -- something (a GOLD BERRY, a METAL COAT, ...), which the extractor was not
  -- reading at all -- so they all came over empty-handed.
  if trade.item then newMon.item = trade.item end
  table.remove(party, slot)
  table.insert(party, newMon)
  local dex = ctx.save.pokedex
  if dex then
    dex.seen[trade.get] = true
    dex.owned[trade.get] = true
  end

  require("src.ui.Screens").push(game, "TradeAnim", {
    sent = sent, received = newMon,
    enemyName = newMon.ot,
    playerOt = ctx.save.player.name,
    playerOtId = sent.otId or ctx.save.player.id,
    enemyOtId = newMon.otId,
    onDone = function() runner:resume() end,
  })
  runner:yield()

  require("src.core.Sound").play(data, "Get_Key_Item")
  if texts.tradedFor then Commands.show_text(ctx, texts.tradedFor, subs) end
  require("src.core.Music").restoreMap(data)   -- RestartMapMusic
  say("thanks", Strings("Yay! I got myself\n%s!", getName))
end

-- wScriptVar: 0 that isn't my mon, 1 you backed out, 2 handed back,
-- 3 it likes you too much to leave (happiness >= 150), 4 it is the only
-- thing you have left to battle with (CheckCurPartyMonFainted).
function Commands.g2_return_shuckie(ctx)
  local game, runner = ctx.game, ctx.runner
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()

  local function result(n)
    ctx.g2Var, ctx.lastCheck = n, n ~= 0
  end
  if not picked then return result(1) end
  if picked.species ~= "SPECIES_213" or picked.otId ~= SHUCKIE_OT_ID
     or picked.ot ~= SHUCKIE_OT then
    return result(0)
  end
  local Party = require("src.pokemon.Party")
  local othersHealthy = false
  for _, mon in ipairs(ctx.save.party) do
    if mon ~= picked and not Party.isEgg(mon) and (mon.hp or 0) > 0 then
      othersHealthy = true
    end
  end
  if not othersHealthy then return result(4) end
  if (picked.happiness or 0) >= 150 then return result(3) end
  for i, mon in ipairs(ctx.save.party) do
    if mon == picked then table.remove(ctx.save.party, i) break end
  end
  result(2)
end

-- ---------------------------------------------------------------------------
-- audio
--
-- The importer keys audio.musicIndex/sfxIndex by the ROM row a MUSIC_* or
-- SFX_* constant names, so a script operand is a direct lookup.  Row 0 of the
-- Music table is Music_Nothing, i.e. MUSIC_NONE: silence.
-- ---------------------------------------------------------------------------

local function audioName(ctx, table_, id)
  local data = ctx.game and ctx.game.data
  local index = data and data.audio and data.audio[table_]
  return index and index[tostring(id)] or nil
end

function Commands.g2_music(ctx, id)
  local Music = require("src.core.Music")
  if id == 0 then return Music.stop() end
  local song = audioName(ctx, "musicIndex", id)
  if not song then return warnOnce("music", id) end
  Music.play(ctx.game.data, song, nil, { reason = "script" })
end

function Commands.g2_sfx(ctx, id)
  local name = audioName(ctx, "sfxIndex", id)
  if not name then return warnOnce("sfx", id) end
  require("src.core.Sound").play(ctx.game.data, name)
end

function Commands.g2_sfx_name(ctx, name)
  if ctx.game then require("src.core.Sound").play(ctx.game.data, name) end
end

function Commands.g2_mapmusic(ctx)
  local ow = ctx.overworld
  local game = ctx.game
  if not game then return end
  require("src.core.Music").playMap(game.data, ow and ow.map and ow.map.id,
    game.save and game.save.onBike,
    ow and ow.player and ow.player.surfing)
end

-- `special RestartMapMusic` ($3C).  A one-shot jingle restores the map theme
-- itself when it ends, so restarting under the Pokecenter heal fanfare would
-- cut it off; MeetMomScript's trailing call follows a plain `playmusic` and
-- does need it.
function Commands.g2_restart_map_music(ctx)
  if require("src.core.Music").oneShotPlaying() then return end
  Commands.g2_mapmusic(ctx)
end

-- `musicfadeout MUSIC, frames`: the ROM fades the current song out over
-- `frames` and queues the new one; the port fades and starts it, since
-- Music.fadeOut stops the source when it reaches silence.
function Commands.g2_musicfade(ctx, id, frames)
  local Music = require("src.core.Music")
  Music.fadeOut(frames)
  if id and id ~= 0 then
    local song = audioName(ctx, "musicIndex", id)
    if song then Music.play(ctx.game.data, song, nil, { reason = "script" }) end
  end
end

function Commands.g2_keepmusic(ctx)
  local ow = ctx.overworld
  if ow then ow.keepMusicOnce = true end
end

function Commands.g2_nop() end

-- ---------------------------------------------------------------------------
-- world / bookkeeping opcodes
-- ---------------------------------------------------------------------------

-- FruitTreeScript (17:$4000).  GetFruitTreeItem indexes FruitTreeItems by
-- wCurFruitTree - 1; GetFruitTreeFlag remembers the pick so the tree is bare
-- until the next daily reset.
function Commands.g2_fruittree(ctx, tree)
  local game = ctx.game
  local save = ctx.save
  local t = game.data.text
  save.g2FruitTrees = save.g2FruitTrees or {}
  local itemId = ((game.data.field or {}).gen2FruitTrees or {})[tree]
  -- CheckFruitTree: a picked tree (or one the table has no row for) is just
  -- scenery until TryResetFruitTrees clears the flags
  if save.g2FruitTrees[tree] or not itemId then
    return Commands.show_text(ctx,
      t._FruitBearingTreeText or "It's a fruit-\nbearing tree.")
  end
  local def = game.data.items[itemId]
  local name = def and def.name or itemId
  -- GetFruitTreeItem -> CopyToStringBuffer runs BEFORE the first box, and
  -- both ROM texts splice the name in themselves ("{RAM:wStringBuffer3}").
  -- Appending it again printed the previous gift's name plus this one.
  setBuffer(game, 3, name)
  Commands.show_text(
  ctx,
  t._HeyItsFruitText and "_HeyItsFruitText"
    or ("Hey! It's\n" .. name .. "!"),
  { RAM = name }
  )
  if not require("src.inventory.Bag").add(save, itemId, 1, game.data) then
    -- .packisfull: the fruit stays on the tree, so the flag is NOT set
    return Commands.show_text(ctx,
      t._FruitPackIsFullText or "But the PACK is\nfull…")
  end
  save.g2FruitTrees[tree] = true
  ctx.textOpts = ctx.textOpts or {}
  ctx.textOpts.auto = {
    sound = function() return require("src.core.Sound").play(game.data, "Get_Item1") end,
    wait = true,
  }
  Commands.show_text(
  ctx,
  t._ObtainedFruitText and "_ObtainedFruitText"
    or ("Obtained\n" .. name .. "!"),
  { RAM = name }
  )
end

-- refreshmap / reloadmap / newloadmap / reanchormap: redraw the loaded map.
function Commands.g2_refreshmap(ctx)
  local ow = ctx.overworld
  if ow and ow.map and ow.map.renderer then ow.map.renderer:rebuild() end
  Commands.reload_map_objects(ctx)
end

-- warpcheck re-tests the tile the player is standing on, so a floor a script
-- just opened swallows them immediately instead of on the next step.
function Commands.g2_warpcheck(ctx)
  local ow = ctx.overworld
  if not (ow and ow.map and ow.player and ow.refreshStandingOnWarp) then return end
  ow:refreshStandingOnWarp()
  local warp = ow.map:warpAtCell(ow.player.cellX, ow.player.cellY)
  -- Script_warpcheck is `call WarpCheck / ret nc / farcall EnableEvents`:
  -- WarpCheck tests the standing tile and makes no exception for doorways.
  -- Excluding doors here is why the scientist's escort walked you onto the
  -- lab's door tile and stopped -- you had to step off and back on for the
  -- ordinary walk-into-a-door path to fire.
  if warp and ow.map:isWarpTileCell(ow.player.cellX, ow.player.cellY) then
    -- warpAtCell hands back the { index, def } record, not the warp itself.
    -- Passing the record straight to takeWarp left warpDef.destMap nil, and
    -- Warp.resolve's unknown-map fallback dropped the player on warp 1 of the
    -- last outdoor map -- which is why solving a Ruins of Alph puzzle spat you
    -- out at the ruins entrance instead of dropping you into the inner chamber.
    ow:takeWarp(warp.def)
  end
end

-- earthquake <duration>: the screen shake the Rocket hideout and the
-- Sudowoodo route use as punctuation.
function Commands.g2_earthquake(ctx, duration)
  local ow = ctx.overworld
  if ow then ow.quakeFrames = duration or 32 end
end

-- setlasttalked retargets applymovementlasttalked / faceplayer at an object
-- the player never spoke to.
function Commands.g2_setlasttalked(ctx, index)
  local ow = ctx.overworld
  if not ow then return end
  local slot = objectSlot(ctx, index)
  local npc = slot and ow:npcByIndex(slot) or nil
  if npc then ctx.npc = npc end
end

-- The COIN CASE balance lives in save.coins -- the same field the COIN CASE
-- item and the slot machine screen read.  Gen2 used to keep its own g2Coins,
-- so the Game Corner paid into a balance the prize counters could not see.
local function coins(save)
  if save.g2Coins and not save.coins then save.coins = save.g2Coins end
  return save.coins or 0
end

-- `checkcoins` runs the SAME comparison as `checkmoney`: Script_checkcoins
-- (25:$7895) falls straight through into CompareMoneyAction (25:$784F), which
-- writes wScriptVar 0 when the player has more, 1 on exactly equal and **2**
-- when they are short.  This wrote 0 or 1, so `ifequal 2` -- the only branch
-- either Game Corner prize counter takes when you cannot afford the prize --
-- never matched, and the TM and POKeMON vendors handed the prize over for
-- free however few coins you had.
function Commands.g2_check_coins(ctx, amount)
  local have = coins(ctx.save)
  amount = amount or 0
  ctx.g2Var = have > amount and 0 or (have == amount and 1 or 2)
  ctx.lastCheck = have >= amount
end

function Commands.g2_give_coins(ctx, amount)
  local save = ctx.save
  save.coins = math.max(0, math.min(9999, coins(save) + (amount or 0)))
  save.g2Coins = nil
end

-- `special DisplayCoinCaseBalance` / `DisplayMoneyAndCoinBalance`: the ROM
-- opens a corner window over the vendor's menu.  There is no such window
-- here, so this only has to leave the balance where the menu can show it.
function Commands.g2_show_coins(ctx)
  ctx.game.coinDisplay = coins(ctx.save)
end

-- The port has no swarm table; record the request so a save that already
-- triggered one keeps reporting it rather than silently losing it.
function Commands.g2_swarm(ctx, kind, mapId)
  ctx.save.g2Swarm = { kind = kind, map = mapId }
end

-- `special NameRival` (SpecialsPointers row $24).  ResetWRAM's
-- InitializeNPCNames seeds wRivalName with "???" -- the name the Cherrygrove
-- rival's own line spells out -- and the Elm's Lab officer scene
-- (opentext / writetext / promptbutton / special NameRival) is where the
-- player finally types it.  Left a stub, the prompt never appeared, so the
-- name stayed whatever the save started with.
function Commands.g2_name_rival(ctx)
  local game, runner = ctx.game, ctx.runner
  local boot = game.data.field and game.data.field.boot
  local presets = boot and boot.namePresets and boot.namePresets.rival
  game.stack:push(require("src.ui.NamingScreen").new(game, {
    title = Strings("RIVAL'S NAME?"),
    maxLen = 7, -- PLAYER_NAME_LENGTH - 1
    -- NamingScreen_InitNameEntry opens the grid blank and confirming nothing
    -- would leave the name empty, so fall back to the canonical one
    default = (presets and presets[1]) or "SILVER",
    onDone = function(name)
      if name and name ~= "" then
        game.save.player = game.save.player or {}
        game.save.player.rival = name
      end
      runner:resume()
    end,
  }))
  runner:yield()
end

-- `special NameRater` (_NameRater, 3E:$77F7).  The whole conversation lives
-- inside the special, so leaving it a warn-once stub is why the NAME RATER
-- stood there silently: the surrounding script is opentext/special/closetext
-- and nothing else.
function Commands.g2_name_rater(ctx)
  local game, save = ctx.game, ctx.save
  local t = game.data.text
  local runner = ctx.runner
  local Party = require("src.pokemon.Party")
  local function nickOf(mon)
    return mon.nickname or (game.data.pokemon[mon.species] or {}).name
           or mon.species
  end

  Commands.ask(ctx, t._NameRaterHelloText or "Would you like me\nto rate names?")
  if not ctx.lastCheck then
    return Commands.show_text(ctx, t._NameRaterComeAgainText
      or "OK, then. Come\nagain sometime.")
  end

  Commands.show_text(ctx, t._NameRaterWhichMonText
    or "Which POKéMON's\nnickname should I\vrate for you?")
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()
  if not picked then
    return Commands.show_text(ctx, t._NameRaterComeAgainText
      or "OK, then. Come\nagain sometime.")
  end
  if Party.isEgg(picked) then
    return Commands.show_text(ctx, t._NameRaterEggText
      or "Whoa… That's just\nan EGG.")
  end

  game.stringBuffer = nickOf(picked)
  -- .traded: a mon whose OT is not the player can't be renamed, and the rater
  -- covers for himself by declaring the name it already has perfect
  local ot = picked.otName or picked.ot
  if ot and ot ~= (save.player and save.player.name) then
    return Commands.show_text(ctx, t._NameRaterPerfectNameText
      or "Hm… {RAM:wStringBuffer1}?\nWhat a great name!")
  end
  Commands.ask(ctx, t._NameRaterBetterNameText
    or "Hm… {RAM:wStringBuffer1}? A better name?")
  if not ctx.lastCheck then
    return Commands.show_text(ctx, t._NameRaterComeAgainText
      or "OK, then. Come\nagain sometime.")
  end

  Commands.show_text(ctx, t._NameRaterWhatNameText
    or "All right. What\nname should we\vgive it, then?")
  local chosen
  game.stack:push(require("src.ui.NamingScreen").new(game, {
    title = Strings("%s's NICKNAME?", nickOf(picked)),
    maxLen = 10,
    default = nickOf(picked),
    onDone = function(name) chosen = name runner:resume() end,
  }))
  runner:yield()

  -- .samename: the rater still congratulates himself when the new name is
  -- the one it already had
  if not chosen or chosen == "" or chosen == nickOf(picked) then
    game.stringBuffer = nickOf(picked)
    return Commands.show_text(ctx, t._NameRaterSameNameText
      or "It might look the\nsame as before,\fbut this new name\nis much better!")
  end
  picked.nickname = chosen
  game.stringBuffer = chosen
  Commands.show_text(ctx, t._NameRaterNamedText
    or "All right. This\nPOKéMON is now\vnamed {RAM:wStringBuffer1}.")
  Commands.show_text(ctx, t._NameRaterFinishedText
    or "That's a better\nname than before!\fWell done!")
end

-- ---------------------------------------------------------------------------
-- DAY-CARE (engine/events/daycare.asm)
--
-- The Route 34 DAY-CARE is driven entirely from specials: the MAN inside is
-- `special DayCareMan` (SpecialsPointers row $1E), the LADY `special
-- DayCareLady` ($1F), the MAN OUTSIDE $20, and the two mons in the yard $44 /
-- $45.  All five were warn-once stubs, so every one of those NPCs opened a
-- text box and immediately closed it again -- the day-care did nothing at all.
--
-- The conversation is the ROM's: intro -> pick -> deposit, or grown-report ->
-- fee -> hand back.  wDayCareMonBoxLevel (slot.depositLevel) is the fee
-- baseline and has to survive a declined retrieve, and the banked step exp is
-- only cashed in when the mon actually leaves.
-- ---------------------------------------------------------------------------

-- Methods rather than chunk locals: this file is close to Lua's
-- 200-locals-per-chunk ceiling (see FLOOR_NAMES below).
function Gen2Commands.dayCareName(game, mon)
  local def = game.data.pokemon[mon.species]
  return mon.nickname or (def and def.name) or mon.species
end

function Gen2Commands.dayCareDeposit(ctx, which, introText, leftText)
  local game, save, runner = ctx.game, ctx.save, ctx.runner
  local t = game.data.text
  local Party = require("src.pokemon.Party")
  local DayCare = require("src.pokemon.DayCare")

  Commands.ask(ctx, introText)
  if not ctx.lastCheck then
    return Commands.show_text(ctx, t._ComeAgainText or "Come again.")
  end
  -- .only_one: the last party member can never be boarded
  if #save.party < 2 then
    return Commands.show_text(ctx, t._OnlyOneMonText
      or "Oh? But you have\njust one #MON.")
  end

  Commands.show_text(ctx, t._WhatShouldIRaiseText
    or "What should I\nraise for you?")
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()
  if not picked then
    return Commands.show_text(ctx, t._ComeAgainText or "Come again.")
  end
  if Party.isEgg(picked) then
    return Commands.show_text(ctx, t._CantAcceptEggText
      or "Sorry, but I can't\naccept an EGG.")
  end
  if picked.mail then
    return Commands.show_text(ctx, t._RemoveMailText
      or "Remove the MAIL\nfrom that #MON.")
  end
  -- .last_healthy: boarding the only mon that can still battle is refused
  local healthy = 0
  for _, mon in ipairs(save.party) do
    if not Party.isEgg(mon) and (mon.hp or 0) > 0 then healthy = healthy + 1 end
  end
  if healthy <= 1 and (picked.hp or 0) > 0 and not Party.isEgg(picked) then
    return Commands.show_text(ctx, t._LastHealthyMonText
      or "That's your last\nhealthy #MON.")
  end

  for i, mon in ipairs(save.party) do
    if mon == picked then table.remove(save.party, i) break end
  end
  DayCare.deposit(save, which, picked)
  game.stringBuffer = Gen2Commands.dayCareName(game, picked)
  Commands.show_text(ctx, t._IllRaiseYourMonText
    or "Fine, I'll raise\nyour #MON.")
  Commands.show_text(ctx, leftText, { RAM = game.stringBuffer })
end

function Gen2Commands.dayCareWithdraw(ctx, which)
  local game, save = ctx.game, ctx.save
  local t = game.data.text
  local Party = require("src.pokemon.Party")
  local Stats = require("src.pokemon.Stats")
  local Growth = require("src.pokemon.Growth")
  local Pokemon = require("src.pokemon.Pokemon")
  local DayCare = require("src.pokemon.DayCare")

  local slot = DayCare.slot(save, which)
  local mon = slot.mon
  local def = game.data.pokemon[mon.species]
  local startLevel = slot.depositLevel or mon.level
  local newLevel, exp = DayCare.pendingLevel(game.data, slot)
  if newLevel >= 100 and def then
    exp = Growth.expForLevel(def.growthRate, 100)
  end
  local levelsGrown = math.max(0, newLevel - startLevel)
  local fee = 100 + levelsGrown * 100
  local name = Gen2Commands.dayCareName(game, mon)
  game.stringBuffer = name

  if levelsGrown > 0 then
    Commands.show_text(ctx, t._YourMonHasGrownText
      or "Your #MON has\ngrown a lot!\fBy level, it's\ngrown by {NUM:wDayCareNumLevelsGrown}!",
      { RAM = name, NUM = tostring(levelsGrown) })
    Commands.show_text(ctx, t._AreWeGeniusesText
      or "Aren't we\ngeniuses?")
  else
    Commands.show_text(ctx, t._BackAlreadyText
      or "Back already?\nYour #MON needs\nmore time with me.",
      { RAM = name })
  end

  Commands.ask(ctx, Strings("That'll be \194\165%d.\nOK?", fee))
  if not ctx.lastCheck then
    return Commands.show_text(ctx, t._OhFineThenText or "Oh, fine then.")
  end
  if #save.party >= Party.MAX then
    return Commands.show_text(ctx, t._HaveNoRoomText
      or "You have no room\nfor it.")
  end
  if (save.money or 0) < fee then
    return Commands.show_text(ctx, t._NotEnoughMoneyText
      or "You don't have\nenough money.")
  end

  save.money = save.money - fee
  DayCare.withdraw(save, which)
  mon.exp = exp
  mon.level = newLevel
  if def then
    mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
    mon.hp = math.min(mon.hp or mon.stats.hp, mon.stats.hp)
    -- WriteMonMoves with wLearningMovesFromDayCare: the levels it grew
    -- through are taught in order, oldest move pushed out first
    Pokemon.learnMovesFromDayCare(game.data, mon, def, startLevel, newLevel)
  end
  table.insert(save.party, mon)
  Commands.show_text(ctx, t._PerfectHeresYourMonText
    or "Perfect! Here's\nyour #MON!")
  Commands.show_text(ctx, t._GotBackMonText
    or "{PLAYER} got\n{RAM:wStringBuffer} back!", { RAM = name })
end

-- `special DayCareMan` ($1E) -- wBreedMon1, the pen on the left.
function Commands.g2_daycare_man(ctx)
  local DayCare = require("src.pokemon.DayCare")
  local t = ctx.game.data.text
  if DayCare.mon(ctx.save, DayCare.MAN) then
    return Gen2Commands.dayCareWithdraw(ctx, DayCare.MAN)
  end
  local intro = DayCare.introduce(ctx.save, DayCare.MAN)
    and (t._DayCareManIntroEggText or t._DayCareManIntroText)
    or t._DayCareManIntroText
  return Gen2Commands.dayCareDeposit(ctx, DayCare.MAN,
    intro or "I'm the DAY-CARE\nMAN. Want me to\nraise a #MON?",
    t._LeftWithDayCareManText
      or "{RAM:wStringBuffer} was left with\nthe DAY-CARE MAN.")
end

-- `special DayCareLady` ($1F) -- wBreedMon2, the pen on the right.
function Commands.g2_daycare_lady(ctx)
  local DayCare = require("src.pokemon.DayCare")
  local t = ctx.game.data.text
  if DayCare.mon(ctx.save, DayCare.LADY) then
    return Gen2Commands.dayCareWithdraw(ctx, DayCare.LADY)
  end
  local intro = DayCare.introduce(ctx.save, DayCare.LADY)
    and (t._DayCareLadyIntroEggText or t._DayCareLadyIntroText)
    or t._DayCareLadyIntroText
  return Gen2Commands.dayCareDeposit(ctx, DayCare.LADY,
    intro or "I'm the DAY-CARE\nLADY. Want me to\nraise a #MON?",
    t._LeftWithDayCareLadyText
      or "{RAM:wStringBuffer} was left with\nthe DAY-CARE LADY.")
end

-- `special DayCareManOutside` ($20) -- the handover.  DayCareStep already
-- parked the EGG in save.daycare.breed.egg; this is only the conversation.
--
-- DayCareManScript_Outside branches on what the special leaves in wScriptVar,
-- so this has to answer in the ROM's currency (05:$6B8C):
--
--   .PartyFull -> 1   the man stays put, come back with room
--   accepted   -> 0   \  both fall into `clearflag ENGINE_DAY_CARE_MAN_HAS_EGG`
--   .Declined  -> 0   /  and the applymovement that walks him back inside
--
-- Without it ctx.g2Var kept whatever the last opcode had left, so the walk --
-- and with it the `disappear` that hands Route 34 back to the empty state --
-- was a coin toss.  Declining really does throw the EGG away: the ROM only
-- ever holds one in wEggMon and the script clears the flag either way.
function Commands.g2_daycare_outside(ctx)
  local game, save = ctx.game, ctx.save
  local t = game.data.text
  local Party = require("src.pokemon.Party")
  local DayCare = require("src.pokemon.DayCare")
  local breed = DayCare.store(save, false)
  local egg = breed and breed.egg
  ctx.g2Var = 1
  if not egg then
    return Commands.show_text(ctx, t._DayCareManOutsideNotYetText
      or t["DayCareManOutside.NotYetText"]
      or "Ah, it's you!\nYour #MON aren't\nlooking after an\nEGG yet.")
  end
  Commands.ask(ctx, t._FoundAnEggText
    or "Ah, it's you!\nWe were raising\nyour #MON, and\fmy goodness, we\nfound an EGG!\fDo you want it?")
  if not ctx.lastCheck then
    breed.egg = nil
    DayCare.syncFlags(save)
    ctx.g2Var = 0
    return Commands.show_text(ctx, t._IllKeepItThanksText
      or "Well then, I'll\nkeep it. Thanks!")
  end
  if #save.party >= Party.MAX then
    return Commands.show_text(ctx, t._NoRoomForEggText
      or "You have no room\nin your party.")
  end
  breed.egg = nil
  DayCare.syncFlags(save)
  Party.add(save.party, egg)
  ctx.g2Var = 0
  Commands.show_text(ctx, t._ReceivedEggText or "{PLAYER} received\nthe EGG!")
  Commands.show_text(ctx, t._TakeGoodCareOfEggText
    or "Take good care of\nit!")
end

-- `special DayCareMon1/2` ($44/$45) -- the two mons wandering the yard.  The
-- object's sprite byte is $E0/$E1 (SPRITE_MON_BREED_1/2); talking to one
-- plays its cry and names it, and the keeper's read on the pair rides along
-- as DayCareMonCompatibilityText.
function Gen2Commands.dayCareYardMon(ctx, which)
  local game = ctx.game
  local t = game.data.text
  local DayCare = require("src.pokemon.DayCare")
  local mon = DayCare.mon(ctx.save, which)
  if not mon then
    ctx.lastCheck = false
    return
  end
  local name = Gen2Commands.dayCareName(game, mon)
  game.stringBuffer = name
  ctx.pendingCry = mon.species
  Commands.show_text(ctx, t.Text_BreedHuh or t._BreedHuhText or "Huh?",
    { RAM = name })
  local tiers = {
    [0] = t._BreedNoInterestText,
    [1] = t._BreedShowsInterestText,
    [2] = t._BreedAppearsToCareForText,
    [3] = t._BreedFriendlyText or t._BreedAppearsToCareForText,
    [4] = t._BreedBrimmingWithEnergyText,
  }
  local tier = DayCare.compatibility(game.data, ctx.save)
  if DayCare.pair(game.data, ctx.save) and tiers[tier] then
    Commands.show_text(ctx, tiers[tier])
  end
  ctx.lastCheck = true
end

function Commands.g2_daycare_mon1(ctx)
  return Gen2Commands.dayCareYardMon(ctx, 1)
end

function Commands.g2_daycare_mon2(ctx)
  return Gen2Commands.dayCareYardMon(ctx, 2)
end

-- ---------------------------------------------------------------------------
-- elevators and script menus
-- ---------------------------------------------------------------------------

-- ElevatorFloorNames (04:$7945), indexed by the floor byte in the elevator's
-- data block.  A class field rather than a chunk local: this file is close to
-- Lua's 200-locals-per-chunk ceiling.
Gen2Commands.FLOOR_NAMES = {
  [0] = "B4F", "B3F", "B2F", "B1F", "1F", "2F", "3F", "4F", "5F", "6F",
  "7F", "8F", "9F", "10F", "11F", "ROOF",
}

-- `elevator <ptr>`: the extractor resolves the pointer into the floor list
-- (db floor, db warp, db group, db number per row).  Without a lowering the
-- opcode compiled to nothing at all, which is why the panel did nothing: the
-- car's two door tiles are LAST_WARP, so cancelling the (never shown) menu
-- always dropped the player back on the floor they got in from.
--
-- Elevator_GoToFloor copies the chosen row straight into wBackupWarpNumber /
-- wBackupMapGroup / wBackupMapNumber -- the very store LAST_WARP reads -- so
-- re-pointing backupWarp is the whole of the ROM's behaviour.
function Commands.g2_elevator(ctx, floors)
  local game, runner = ctx.game, ctx.runner
  ctx.lastCheck = false
  if type(floors) ~= "table" or #floors == 0 then
    Logger.warn("gen2 script: elevator with no floor data")
    return
  end
  -- Elevator.FindCurrentFloor skips the row whose map is the one we are on
  local ow = ctx.overworld
  local here = ow and ow.backupWarp and ow.backupWarp.id
  local chosen
  local items = {}
  for _, floor in ipairs(floors) do
    if floor.map and floor.map ~= here then
      items[#items + 1] = {
        label = Gen2Commands.FLOOR_NAMES[floor.floor] or tostring(floor.floor),
        onSelect = function() chosen = floor runner:resume() end,
      }
    end
  end
  if #items == 0 then return end

  Commands.show_text(ctx, (game.data.text or {})._AskFloorElevatorText
    or Strings("Which floor?"))
  game.stack:push(require("src.ui.Menu").new(game, items, {
    onCancel = function() runner:resume() end,
  }))
  runner:yield()
  if not chosen then return end

  local def = game.data.maps[chosen.map]
  local warp = def and def.warps and def.warps[chosen.warp]
  if not warp then
    Logger.warn("gen2 script: elevator warp %s#%s missing",
                tostring(chosen.map), tostring(chosen.warp))
    return
  end
  local backup = { id = chosen.map, x = warp.x, y = warp.y }
  if ow then ow.backupWarp = backup end
  ctx.save.backupWarp = backup
  ctx.lastCheck = true
end

-- `loadmenu <ptr>` arms a MenuHeader; the extractor already turned it into
-- the list of MenuData labels.  `verticalmenu` runs it and writes the 1-based
-- choice into the script var (0 = cancelled), which is what the Game Corner
-- prize counters branch on with `ifequal 1/2/3`.  Both were unlowered, so the
-- vendors printed their greeting and then stood there.
function Commands.g2_loadmenu(ctx, menu)
  if type(menu) ~= "table" or #menu == 0 then
    ctx.g2Menu = nil
    Logger.warn("gen2 script: loadmenu header was not resolved")
    return
  end
  ctx.g2Menu = menu
end

function Commands.g2_verticalmenu(ctx)
  local menu = ctx.g2Menu
  ctx.g2Menu = nil
  if not menu then
    ctx.g2Var, ctx.lastCheck = 0, false
    return
  end
  local game, runner = ctx.game, ctx.runner
  local picked = 0
  local items = {}
  for index, label in ipairs(menu) do
    items[index] = {
      label = label,
      onSelect = function() picked = index runner:resume() end,
    }
  end
  game.stack:push(require("src.ui.Menu").new(game, items, {
    onCancel = function() runner:resume() end,
  }))
  runner:yield()
  ctx.g2Var = picked
  ctx.lastCheck = picked ~= 0
end

-- `special SlotMachine`: the `setval 0/1` ahead of it marks the one machine
-- Slots_InitBias makes generous.  Nothing follows in the script but
-- closetext/end, so this does not have to yield.
function Commands.g2_slots(ctx)
  require("src.ui.Screens").push(ctx.game, "Gen2Slots", scriptVar(ctx) == 1)
end

-- `special CardFlip`: takes no argument, and like the slots nothing follows it
-- in the script but closetext/end, so it does not have to yield.
function Commands.g2_card_flip(ctx)
  require("src.ui.Screens").push(ctx.game, "Gen2CardFlip")
end

-- ---------------------------------------------------------------------------
-- Kanto post-game specials
--
-- Gen2ScriptVM maps these SPECIALSPointers indices to g2_* names. Without
-- implementations ScriptRunner hits "unknown command" and aborts mid-script
-- (Bill's grandpa, Move Deleter, Magnet Train, lottery, Snorlax, Copycat).
-- ---------------------------------------------------------------------------

local function pickPartyMon(ctx)
  local game, runner = ctx.game, ctx.runner
  if not (game and runner) then return nil end
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()
  return picked
end

local function speciesNumber(mon)
  if not mon then return 0 end
  if type(mon.species) == "number" then return mon.species end
  local n = tostring(mon.species or ""):match("(%d+)$")
  return tonumber(n) or 0
end

-- `special BillsGrandfather` ($4C).  Party menu; wScriptVar = species id.
function Commands.g2_bills_grandfather(ctx)
  local picked = pickPartyMon(ctx)
  if not picked then
    ctx.g2Var = 0
    ctx.lastCheck = false
    return
  end
  ctx.g2Var = speciesNumber(picked)
  ctx.lastCheck = ctx.g2Var ~= 0
end

-- `special MoveDeletion` ($21).  Pick mon, pick move slot, clear it.
function Commands.g2_move_deleter(ctx)
  local game = ctx.game
  -- Gold/Silver Move Deleter opens with a prompt before the party menu.
  Commands.show_text(ctx, "Which POKéMON should\nforget a move?")
  local picked = pickPartyMon(ctx)
  if not picked then
    ctx.g2Var = 0
    ctx.lastCheck = false
    return
  end
  local moves = picked.moves or {}
  if #moves <= 1 then
    Commands.show_text(ctx, "This POKéMON knows\nonly one move.")
    ctx.g2Var = 0
    ctx.lastCheck = false
    return
  end
  local labels = {}
  for i, m in ipairs(moves) do
    local name = (type(m) == "table" and (m.name or m.id)) or tostring(m)
    local def = game.data.moves and game.data.moves[name]
    labels[i] = (def and def.name) or name
  end
  local runner = ctx.runner
  local slot = 0
  local items = {}
  for i, label in ipairs(labels) do
    items[i] = {
      label = label,
      onSelect = function() slot = i runner:resume() end,
    }
  end
  game.stack:push(require("src.ui.Menu").new(game, items, {
    onCancel = function() runner:resume() end,
  }))
  runner:yield()
  if slot < 1 or slot > #moves then
    ctx.g2Var = 0
    ctx.lastCheck = false
    return
  end
  local forgotten = labels[slot] or "a move"
  table.remove(moves, slot)
  picked.moves = moves
  Commands.show_text(ctx, (picked.nickname or "POKéMON") .. " forgot\n" .. tostring(forgotten) .. "!")
  ctx.g2Var = 1
  ctx.lastCheck = true
end

-- Gen2 bag keys are ITEM_%03d after extract; scripts also check named ids.
-- pret item_constants: PASS $86, POKE_FLUTE $38, MACHINE_PART $80, LOST_ITEM $82.
local function inventoryHas(save, data, candidates)
  local inv = save and save.inventory or {}
  for _, id in ipairs(candidates) do
    local qty = inv[id]
    if type(qty) == "number" and qty > 0 then return true end
    if qty == true then return true end
  end
  if data and data.items then
    for _, id in ipairs(candidates) do
      local entry = data.items[id]
      if entry and entry.key then
        local qty = inv[entry.key]
        if type(qty) == "number" and qty > 0 then return true end
      end
      -- match by ROM name / key field pointing back at ITEM_nnn
      for key, qty in pairs(inv) do
        if type(qty) == "number" and qty > 0 and type(key) == "string" then
          local e = data.items[key]
          if e and (e.key == id or e.name == id or key == id) then return true end
        end
      end
    end
  end
  return false
end

-- `special MagnetTrain` ($23).  Officer scripts already checkitem PASS and
-- EVENT_RESTORED_POWER_TO_KANTO; this special only runs the ride.
function Commands.g2_magnet_train(ctx)
  local save, data = ctx.save, ctx.game and ctx.game.data
  -- PASS = item constant $86 → ITEM_134
  local hasPass = inventoryHas(save, data, {
    "PASS", "ITEM_PASS", "ITEM_134", "ITEM_086",
  })
  if not hasPass then
    ctx.g2Var = 0
    ctx.lastCheck = false
    return
  end
  local ow = ctx.overworld
  local mapId = tostring(ow and ow.map and ow.map.id or "")
  -- Prefer exact station map keys from the Gen2 scaffold registry.
  local dest
  if mapId:find("GOLDENROD") then
    dest = {
      map = data and data.maps and data.maps.SAFFRON_MAGNET_TRAIN_STATION
        and "SAFFRON_MAGNET_TRAIN_STATION"
        or (data and data.maps and data.maps.SAFFRON_TRAIN_STATION
          and "SAFFRON_TRAIN_STATION" or "SAFFRON_MAGNET_TRAIN_STATION"),
      x = 6, y = 5,
    }
  else
    dest = {
      map = data and data.maps and data.maps.GOLDENROD_MAGNET_TRAIN_STATION
        and "GOLDENROD_MAGNET_TRAIN_STATION"
        or "GOLDENROD_MAGNET_TRAIN_STATION",
      x = 6, y = 5,
    }
  end
  Commands.g2_warp(ctx, dest.map, dest.x, dest.y, "down")
  ctx.g2Var = 1
  ctx.lastCheck = true
end

-- `special SnorlaxAwake` ($5F).  ROM checks wMapMusic == MUSIC_POKE_FLUTE_CHANNEL.
-- That channel is only unlocked with the EXPN Card from Lavender Radio Tower
-- (ENGINE_EXPN_CARD / event flag row $03).  Gen2 has no usable Poké Flute item
-- in normal play; matching ITEM_056 as "flute" was a false positive.
function Commands.g2_snorlax_awake(ctx)
  local save = ctx.save
  local flags = save.flags or {}
  local Gen2Flags = require("src.script.Gen2Flags")
  local expnKey = Gen2Flags.engineFlag(3) -- EVENT_GOT_EXPN_CARD
  local hasExpn = flags[expnKey] == true
    or flags.EVENT_GOT_EXPN_CARD == true
    or flags.ENGINE_EXPN_CARD == true
  ctx.lastCheck = hasExpn and true or false
  ctx.g2Var = hasExpn and 1 or 0
end

-- ---------------------------------------------------------------------------
-- Radio lucky-number show (specials $51-$54)
--
-- wLuckyIDNumber is a 16-bit value printed as five decimal digits with leading
-- zeros (00000-65535).  ResetLuckyNumberShowFlag regenerates it for the day;
-- CheckForLuckyNumberWinners scores party OT IDs by trailing-digit matches.
-- ---------------------------------------------------------------------------

local function luckyDigits(n)
  n = math.floor(tonumber(n) or 0) % 65536
  return string.format("%05d", n)
end

local function ensureLuckyNumber(save)
  if type(save.g2LuckyNumber) == "number" then return save.g2LuckyNumber end
  if type(save.g2LuckyNumber) == "string" and save.g2LuckyNumber:match("^%d+$") then
    save.g2LuckyNumber = tonumber(save.g2LuckyNumber) % 65536
    return save.g2LuckyNumber
  end
  -- Prefer LOVE's random if present; otherwise math.random.
  local r = (love and love.math and love.math.random) or math.random
  save.g2LuckyNumber = r(0, 65535)
  return save.g2LuckyNumber
end

local function monOtId(mon)
  if not mon then return nil end
  local id = mon.otId or mon.otID or mon.trainerId or mon.id
  if type(id) == "string" then
    id = tonumber(id:match("(%d+)"))
  end
  if type(id) ~= "number" then return nil end
  return math.floor(id) % 65536
end

-- Trailing digit matches between lucky ID and mon OT ID → prize tier.
-- ROM: 5 match → 1, 3-4 → 2, 2 → 3, else 0 (lower number = better).
local function luckyMatchTier(lucky, otId)
  local a, b = luckyDigits(lucky), luckyDigits(otId)
  local matches = 0
  for i = 5, 1, -1 do
    if a:sub(i, i) == b:sub(i, i) then
      matches = matches + 1
    else
      break
    end
  end
  if matches == 5 then return 1 end
  if matches >= 3 then return 2 end
  if matches == 2 then return 3 end
  return 0
end

-- CheckForLuckyNumberWinners ($51): scan party for best matching OT ID.
function Commands.g2_lucky_winners(ctx)
  local save = ctx.save
  local lucky = ensureLuckyNumber(save)
  local best = 0
  local bestName
  for _, mon in ipairs(save.party or {}) do
    local species = mon.species
    if species and tostring(species):upper() ~= "EGG" then
      local ot = monOtId(mon)
      if ot then
        local tier = luckyMatchTier(lucky, ot)
        if tier > 0 and (best == 0 or tier < best) then
          best = tier
          local def = ctx.game.data.pokemon and ctx.game.data.pokemon[species]
          bestName = (mon.nickname and mon.nickname ~= "" and mon.nickname)
            or (def and def.name) or tostring(species)
        end
      end
    end
  end
  if best > 0 then
    ctx.game.stringBuffer = bestName or "POKéMON"
  end
  ctx.g2Var = best
  ctx.lastCheck = best > 0
end

-- CheckLuckyNumberShowFlag ($52): has the player already heard today's show?
function Commands.g2_lucky_check_flag(ctx)
  local Gen2Flags = require("src.script.Gen2Flags")
  local flags = ctx.save.flags or {}
  local key = Gen2Flags.engineFlag(77) -- ENGINE_LUCKY_NUMBER_SHOW
  local set = flags[key] == true or flags.ENGINE_LUCKY_NUMBER_SHOW == true
  ctx.lastCheck = set and true or false
  ctx.g2Var = set and 1 or 0
end

-- ResetLuckyNumberShowFlag ($53): clear "already heard" and roll a new ID.
function Commands.g2_lucky_reset(ctx)
  local Gen2Flags = require("src.script.Gen2Flags")
  ctx.save.flags = ctx.save.flags or {}
  ctx.save.flags[Gen2Flags.engineFlag(77)] = nil
  ctx.save.flags.ENGINE_LUCKY_NUMBER_SHOW = nil
  local r = (love and love.math and love.math.random) or math.random
  ctx.save.g2LuckyNumber = r(0, 65535)
  ctx.g2Var = 0
end

-- PrintTodaysLuckyNumber ($54): five digits, leading zeros (e.g. 00421).
function Commands.g2_lucky_print(ctx)
  local n = ensureLuckyNumber(ctx.save)
  local digits = luckyDigits(n)
  ctx.game.stringBuffer = digits
  -- Scripts usually print via text that reads the string buffer; also show a
  -- direct line so a bare special still displays the number.
  Commands.show_text(ctx, "Today's lucky number is\n" .. digits .. "!")
end

function Commands.g2_heal_party(ctx)
  local Pokemon = require("src.pokemon.Pokemon")
  for _, mon in ipairs(ctx.save.party or {}) do
    if Pokemon.heal then
      Pokemon.heal(mon)
    else
      mon.hp = mon.maxHp or mon.hp
      mon.status = nil
      if mon.moves then
        for _, mv in ipairs(mon.moves) do
          if mv and mv.maxPp then mv.pp = mv.maxPp end
        end
      end
    end
  end
  -- Always refresh the blackout/heal point when the nurse heals so Escape
  -- Rope / white-out work even if the script's blackoutmod row was skipped.
  local ow = ctx.overworld
  if ow and ow.map and ow.player then
    ctx.save.lastHeal = {
      map = ow.map.id,
      x = ow.player.cellX,
      y = ow.player.cellY,
      outdoor = ow.lastOutdoor and {
        id = ow.lastOutdoor.id, x = ow.lastOutdoor.x, y = ow.lastOutdoor.y,
      } or nil,
    }
  end
  ctx.lastCheck = true
end

-- (The old do-nothing g2_bank_of_mom stub used to sit here.  It was defined
-- AFTER the real handler further up this file, so it silently overwrote it on
-- the Commands table and Mom went on saying nothing even once the banking
-- conversation was implemented.)

function Commands.g2_town_map(ctx)
  require("src.ui.Screens").push(ctx.game, "TownMap")
end

function Commands.g2_map_radio(ctx)
  ctx.lastCheck = true
end

function Commands.g2_check_pokerus(ctx)
  ctx.g2Var = 0
  ctx.lastCheck = false
end

function Commands.g2_place_money_top_right(ctx) end

function Commands.g2_haircut_older(ctx)
  ctx.g2Var = 0
  ctx.lastCheck = true
end
Commands.g2_haircut_younger = Commands.g2_haircut_older
Commands.g2_daisys_grooming = Commands.g2_haircut_older

function Commands.g2_oaks_pc(ctx)
  Commands.show_text(ctx, "PROF.OAK's PC\naccessed.")
end

function Commands.g2_trainer_house(ctx)
  ctx.lastCheck = true
end

function Commands.g2_photo_studio(ctx)
  ctx.lastCheck = true
end

-- RoamMaps adjacency from pret data/wild/roammon_maps.asm.
local ROAM_MAPS = {
  ROUTE_29 = { "ROUTE_30", "ROUTE_46" },
  ROUTE_30 = { "ROUTE_29", "ROUTE_31" },
  ROUTE_31 = { "ROUTE_30", "ROUTE_32", "ROUTE_36" },
  ROUTE_32 = { "ROUTE_36", "ROUTE_31", "ROUTE_33" },
  ROUTE_33 = { "ROUTE_32", "ROUTE_34" },
  ROUTE_34 = { "ROUTE_33", "ROUTE_35" },
  ROUTE_35 = { "ROUTE_34", "ROUTE_36" },
  ROUTE_36 = { "ROUTE_35", "ROUTE_31", "ROUTE_32", "ROUTE_37" },
  ROUTE_37 = { "ROUTE_36", "ROUTE_38", "ROUTE_42" },
  ROUTE_38 = { "ROUTE_37", "ROUTE_39", "ROUTE_42" },
  ROUTE_39 = { "ROUTE_38" },
  ROUTE_42 = { "ROUTE_43", "ROUTE_44", "ROUTE_37", "ROUTE_38" },
  ROUTE_43 = { "ROUTE_42", "ROUTE_44" },
  ROUTE_44 = { "ROUTE_42", "ROUTE_43", "ROUTE_45" },
  ROUTE_45 = { "ROUTE_44", "ROUTE_46" },
  ROUTE_46 = { "ROUTE_45", "ROUTE_29" },
}

-- InitRoamMons, read off both cartridges (crystal 0A:$62A0, gold 0A:$67D7).
-- Every roamer is level $28 = 40 and starts with 0 HP recorded.
--
-- SUICUNE ONLY ROAMS IN GOLD AND SILVER.  Crystal's InitRoamMons writes two
-- slots and stops -- its Suicune is the scripted Kimono/Tin Tower chain, not a
-- roamer -- and Crystal's FindNest correspondingly has RoamMon1 and RoamMon2
-- where Gold's has three.  Spawning it here put a third beast on the Pokegear
-- map that the cartridge never has.
local ROAM_START = {
  RAIKOU  = "ROUTE_42",   -- group 2, map 5
  ENTEI   = "ROUTE_37",   -- group 10, map 4
  SUICUNE = "ROUTE_38",   -- group 1, map 12 -- Gold/Silver only
}

local function roamsInThisVersion(name)
  if name ~= "SUICUNE" then return true end
  return not require("src.core.GameVersion").isCrystal()
end

local ROAM_SPECIES_ID = {
  RAIKOU  = "SPECIES_243",
  ENTEI   = "SPECIES_244",
  SUICUNE = "SPECIES_245",
}

local LANDMARK_BY_MAP = {
  ROUTE_29 = 0x02, ROUTE_30 = 0x04, ROUTE_31 = 0x05,
  ROUTE_32 = 0x08, ROUTE_33 = 0x0b, ROUTE_34 = 0x0f,
  ROUTE_35 = 0x12, ROUTE_36 = 0x14, ROUTE_37 = 0x15,
  ROUTE_38 = 0x19, ROUTE_39 = 0x1a, ROUTE_42 = 0x21,
  ROUTE_43 = 0x24, ROUTE_44 = 0x26, ROUTE_45 = 0x2a,
  ROUTE_46 = 0x2c,
}

local function normalizeMapId(mapId)
  if not mapId then return nil end
  local s = tostring(mapId)
  if ROAM_MAPS[s] then return s end
  -- ROUTE37 / Route37 -> ROUTE_37
  local u = s:upper():gsub("%s+", "_")
  if ROAM_MAPS[u] then return u end
  local with = u:gsub("^(ROUTE)(%d+)$", "%1_%2")
  if ROAM_MAPS[with] then return with end
  return s
end

local function mapToLandmark(game, mapId)
  mapId = normalizeMapId(mapId)
  if not mapId then return nil end
  if LANDMARK_BY_MAP[mapId] then return LANDMARK_BY_MAP[mapId] end
  if not game then return nil end
  local maps = (game.data and game.data.maps) or {}
  local def = maps[mapId] or maps[mapId:gsub("_", "")]
  if def and tonumber(def.landmark) then return tonumber(def.landmark) end
  return nil
end

-- ONLY called by special $68 (Burned Tower release).  Sets g2RoamReleased so
-- the pokegear map shows the dogs.  Do NOT call this from daily/menu open.
function Commands.g2_init_roam_mons(ctx)
  ctx.save.g2RoamReleased = true
  ctx.save.g2Roam = {}
  for name, startMap in pairs(ROAM_START) do
    if roamsInThisVersion(name) then
      ctx.save.g2Roam[name] = {
        mapId = startMap,
        speciesId = ROAM_SPECIES_ID[name],
        landmark = mapToLandmark(ctx.game, startMap) or LANDMARK_BY_MAP[startMap],
        active = true,
        -- InitRoamMons: `ld a, 40 / ld [wRoamMon1Level], a` for every beast,
        -- and `xor a / ld [wRoamMon1HP], a` -- 0 meaning "generate new
        -- stats", i.e. a beast nobody has wounded yet. Both are read by
        -- RoamMons when one actually steps out, so a slot without them is a
        -- marker on the Pokegear and nothing more.
        level = 40,
        hp = 0,
      }
    end
  end
end

-- ---------------------------------------------------------------------------
-- Crystal: the GS BALL
--
-- On a real cartridge EVENT_GOT_GS_BALL_FROM_GOLDENROD_POKEMON_CENTER was set
-- by the mobile / Mystery Gift distribution, which no longer exists -- so the
-- whole Celebi chain (Kurt examines the ball, the Ilex Forest shrine grows
-- restless, Celebi appears) was unreachable in ordinary play.  Beating the
-- Elite Four unlocks it here instead.
--
-- Nothing is granted directly.  The whole chain -- the receptionist walking
-- over, Kurt taking the ball, the shrine going restless, Celebi -- is in
-- Crystal's own extracted scripts and runs itself as soon as the ONE thing
-- the cartridge got from the outside world says yes.
--
-- That one thing is `setval BATTLETOWERACTION_GSBALL / special
-- BattleTowerAction / ifequal GS_BALL_AVAILABLE` at the top of
-- GoldenrodPokecenter1F_GSBallScene{Left,Right}.  So the unlock belongs
-- there, in the special's answer -- see BATTLE_TOWER_ACTIONS[0x0B].
--
-- What was here before set EVENT_GOT_GS_BALL_FROM_GOLDENROD_POKEMON_CENTER
-- outright, which is precisely backwards: that flag means "the receptionist
-- has ALREADY handed it over", and the scene's second line is
-- `checkevent <it> / iftrue .cancel`.  Pre-setting it made the scene abort on
-- its first branch every time -- the attendant never appeared, the item was
-- never given, and EVENT_CAN_GIVE_GS_BALL_TO_KURT (which only that scene
-- sets) stayed clear, so Kurt had nothing to react to either.  It also named
-- the wrong event: EVENT_G2_0487 is a hole in Crystal's table, not the GS
-- BALL flag, which is 832.  And nothing ever called it.
local GS_BALL_FLAGS = {
  beatEliteFour = "EVENT_G2_0068",  -- EVENT_BEAT_ELITE_FOUR
  gotGsBall     = "EVENT_G2_0832",  -- ..._FROM_GOLDENROD_POKEMON_CENTER
  canGiveToKurt = "EVENT_G2_0190",  -- EVENT_CAN_GIVE_GS_BALL_TO_KURT
}
Gen2Commands.GS_BALL_FLAGS = GS_BALL_FLAGS

-- Is the GS BALL on offer right now?  On a cartridge this was the mobile /
-- Mystery Gift distribution answering GS_BALL_AVAILABLE; here it is beating
-- the Elite Four.  Once the receptionist has handed it over her scene must
-- stop offering, which is the same test the ROM makes one line later -- doing
-- it here as well keeps the answer honest for anything else that asks.
function Gen2Commands.gsBallAvailable(save)
  if not require("src.core.GameVersion").isCrystal() then return false end
  if type(save) ~= "table" then return false end
  local flags = save.flags
  if type(flags) ~= "table" then return false end
  if not flags[GS_BALL_FLAGS.beatEliteFour] then return false end
  if flags[GS_BALL_FLAGS.gotGsBall] then return false end
  return true
end

-- Refresh landmarks for already-released beasts (menu open / map load).
-- Never spawns dogs before Burned Tower.
function Commands.g2_ensure_roam_landmarks(ctx)
  -- Migrate saves that already had dogs from the old auto-spawn path
  if not ctx.save.g2RoamReleased then
    if type(ctx.save.g2Roam) == "table" and next(ctx.save.g2Roam) then
      ctx.save.g2RoamReleased = true
    else
      return
    end
  end
  local roam = ctx.save.g2Roam
  if type(roam) ~= "table" then return end
  for name, info in pairs(roam) do
    -- Retire a beast this version does not roam.  A Crystal save released
    -- before the version check existed has a Suicune slot in it, and it would
    -- otherwise keep drawing on the Pokegear and Fly maps forever.
    if not roamsInThisVersion(name) then
      roam[name] = nil
    elseif type(info) == "table" and info.mapId then
      info.speciesId = info.speciesId or ROAM_SPECIES_ID[name]
      -- Saves released before the beasts could actually be MET have a slot
      -- with no level and no HP in it. Fill those in rather than leaving a
      -- beast that cannot be turned into an encounter.
      info.level = tonumber(info.level) or 40
      info.hp = tonumber(info.hp) or 0
      info.landmark = mapToLandmark(ctx.game, info.mapId)
        or LANDMARK_BY_MAP[normalizeMapId(info.mapId)]
        or info.landmark
    end
  end
end

-- pret UpdateRoamMons: hop each active beast to a connected route.
-- Called on every overworld map enter AFTER the beasts have been released.
function Commands.g2_update_roam_positions(ctx)
  if not ctx.save.g2RoamReleased then return end
  local roam = ctx.save.g2Roam
  if type(roam) ~= "table" then return end

  local r = (love and love.math and love.math.random) or math.random
  local curMap = ctx.game and ctx.game.overworld and ctx.game.overworld.map
    and ctx.game.overworld.map.id
  local lastMap = ctx.save.g2RoamLastMap

  -- Always refresh landmarks
  Commands.g2_ensure_roam_landmarks(ctx)

  -- Only hop when the player moved to a different map
  if curMap and curMap == lastMap then return end
  ctx.save.g2RoamLastMap = curMap

  for name, info in pairs(roam) do
    if type(info) == "table" and info.active ~= false then
      local cur = normalizeMapId(info.mapId) or ROAM_START[name]
      local neighbors = ROAM_MAPS[cur]
      local dest
      if neighbors and #neighbors > 0 then
        -- pret: 1/32 chance fully random, else pick a neighbor
        if r(0, 31) == 0 then
          local keys = {}
          for k in pairs(ROAM_MAPS) do keys[#keys + 1] = k end
          dest = keys[r(1, #keys)]
        else
          dest = neighbors[r(1, #neighbors)]
        end
      end
      -- UpdateRoamMons.Update rejects the map the PLAYER just came from and
      -- rerolls, so a beast never hops onto the route behind you.
      if dest and dest == normalizeMapId(lastMap) then dest = nil end
      if dest then
        info.mapId = dest
        info.landmark = LANDMARK_BY_MAP[dest] or mapToLandmark(ctx.game, dest)
      end
    end
  end
end

-- Both roamer helpers are called from OUTSIDE the script VM -- setMap and
-- TownMap.new -- via `require("src.script.Gen2Commands")`, and that returns
-- THIS table, not the shared `Commands` registry the script handlers above are
-- defined on.  Without these two lines both lookups are nil, the pcall wrapped
-- around each call site swallows the "attempt to call a nil value" that
-- follows, and the beasts never move at all: a released save keeps Raikou,
-- Entei and Suicune on their InitRoamMons start maps forever, and
-- save.g2RoamLastMap is never even written.  That was true on all three
-- versions.
Gen2Commands.g2_update_roam_positions = Commands.g2_update_roam_positions
Gen2Commands.g2_ensure_roam_landmarks = Commands.g2_ensure_roam_landmarks

-- ---------------------------------------------------------------------------
-- Bug Catching Contest
--
-- The gate's own extracted scripts drive all of this; these are the
-- SpecialsPointers rows they call.  Everything they need is in
-- field.gen2BugContest, read off the cartridge by
-- RomExtractorGen2:gen2BugContest.

-- GiveParkBalls (04:$75DB) clears the caught mon, sets 20 Park Balls and falls
-- into StartBugContestTimer, so this is where a run actually begins.
function Commands.g2_bug_contest_start(ctx)
  require("src.world.BugContest").start(ctx.game)
end

-- ContestDropOffMons (04:$7A12): only the lead competes; the rest of the party
-- waits at the gate until ContestReturnMons hands it back.
--
-- IT ANSWERS.  The routine opens with
--
--     ld hl, wPartyMon1HP / ld a, [hli] / or [hl] / jr z, .fainted
--     ...
--     xor a / ld [wScriptVar], a / ret
--   .fainted
--     ld a, $1 / ld [wScriptVar], a / ret
--
-- and Route36NationalParkGate does `special ContestDropOffMons / iftrue
-- .FirstMonIsFainted` on the very next line.  Answering nothing left the
-- `iftrue` reading the result of the `yesorno` immediately before it -- which
-- is TRUE whenever the player agrees to enter -- so the officer said "The
-- first #MON in your party can't battle." to everyone, healthy lead or not,
-- and the contest could never be joined.
--
-- 1 means fainted, and in that case NOTHING is dropped off: the ROM returns
-- before it masks the party.
function Commands.g2_bug_contest_drop_off(ctx)
  local fainted = require("src.world.BugContest").holdParty(ctx.save)
  setScriptVar(ctx, fainted and 1 or 0)
end

-- ContestReturnMons (contest_2.asm:99) hands the held party back AND NOTHING
-- ELSE.  It is not the end of the run: two lines later
-- BugContestResults_DidNotLeaveMons runs `special CheckPartyFullAfterContest`,
-- which is what actually consumes the caught mon.
--
-- This used to call finish() AND clear() as well, which wiped `caught` and
-- `scores` before that point.  Three of the reported symptoms came out of
-- those two extra lines: the caught mon vanished instead of joining the party,
-- judging scored an empty catch so the prize was ALWAYS the consolation BERRY,
-- and -- because the results script only reaches this special when the player
-- left mons behind -- a player who entered with a single Pokemon never cleared
-- the run at all.
--
-- It is also the wrong place to end a run for a plainer reason: the script
-- BRANCHES around it.  `checkevent EVENT_LEFT_MONS_WITH_CONTEST_OFFICER /
-- iffalse BugContestResults_DidNotLeaveMons` skips it entirely for a one-mon
-- party, which is what "it takes my Pokemon and doesn't give them back, or
-- doesn't take them at all, it seems back and forth" was.
function Commands.g2_bug_contest_return(ctx)
  require("src.world.BugContest").returnParty(ctx.save)
end

-- CheckPartyFullAfterContest (engine/pokemon/caught_data.asm:1).  THE LAST
-- special the results script runs, and the one that was missing entirely --
-- Gen2ScriptVM maps it to this name, no handler answered to it, and
-- ScriptRunner logs "unknown command" and skips the row.  That is why the
-- Pokemon you spent the whole contest catching was never yours: nothing ever
-- put it in the party.
--
-- The ROM's three answers, which the very next `ifequal` pair tests:
--     BUGCONTEST_CAUGHT_MON 0  -- it joined the party
--     BUGCONTEST_BOXED_MON  1  -- the party was full, so it went to a box
--                                 (the ROM reports this even when the box is
--                                 full too and the mon is lost -- .BoxFull
--                                 falls through into the same tail)
--     BUGCONTEST_NO_CATCH   2  -- nothing was caught
-- Only 1 prints "your party is full" text, so a skipped special left that
-- `ifequal` reading a stale answer and the script could miss its
-- `setscene NOOP` -- which is what let the officer ask "are you finished?"
-- again, and hand over another prize, on every single map load.
--
-- The caught mon is stamped with the player as OT and National Park as the
-- catch location, like SetCaughtData does.  The ROM also offers a nickname
-- here (GiveANickname_YesNo); the port does not yet, and the mon arrives under
-- its species name.
function Commands.g2_contest_party_full(ctx)
  local BugContest = require("src.world.BugContest")
  local save = ctx.save
  local mon = BugContest.takeCaught(save)
  -- End the run HERE, not in ContestReturnMons: this row runs on every path
  -- through the results script, so it is the one place a one-mon party and a
  -- full one agree on.  clear() hands back anything still held.
  BugContest.clear(save)
  if not mon then
    setScriptVar(ctx, 2)                    -- BUGCONTEST_NO_CATCH
    return
  end
  local player = save.player or {}
  mon.ot = mon.ot or player.name
  mon.otId = mon.otId or player.id
  mon.caughtLocation = mon.caughtLocation or "NATIONAL_PARK"
  save.party = save.party or {}
  if require("src.pokemon.Party").add(save.party, mon) then
    setScriptVar(ctx, 0)                    -- BUGCONTEST_CAUGHT_MON
    return
  end
  pcall(function() require("src.pokemon.Boxes").deposit(save, mon) end)
  setScriptVar(ctx, 1)                      -- BUGCONTEST_BOXED_MON
end

-- SelectRandomBugContestContestants (engine/events/bug_contest/contest_2.asm:1)
-- picks WHO YOU ARE COMPETING AGAINST, and it does it with event flags:
--
--     ld c, NUM_BUG_CONTESTANTS      ; clear all ten first
--     .loop1  EventFlagAction RESET_FLAG
--     ld c, 5                        ; then set five at random
--     .loop2  Random, rejected at >= 250, / 25 -> 0..9
--             already set? roll again.  otherwise SET_FLAG.
--
-- "Set the flag. This will cause that sprite to not be visible in the contest"
-- is the ROM's own comment, so the FIVE IT LEAVES CLEAR are your rivals -- in
-- the park, and again at the gate afterwards, where
-- BugContestResults_CopyContestantsToResults and the officer's .CopyContestants
-- `appear` exactly the ones whose A flag is clear.
--
-- The port only re-rolled the AI SCORES and never touched the flags. Meanwhile
-- BugContestResults_CleanUp ends every run by SETTING all twenty of them, so
-- after the first contest every contestant was permanently hidden: nobody in
-- the park, and nobody standing around at the results.
--
-- The flag ids come off the cartridge (field.gen2BugContest.contestantFlags,
-- from BugCatchingContestantEventFlagTable).  They must: pokecrystal numbers
-- EVENT_BUG_CATCHING_CONTESTANT_1A at 1146 and pokegold at 1121, and the port
-- keys event flags by that raw number.
local BUG_CONTESTANTS_IN_PARK = 5

function Commands.g2_bug_contest_select(ctx)
  local BugContest = require("src.world.BugContest")
  local state = BugContest.state(ctx.save)
  if state then state.scores = BugContest.rollContestants(ctx.game) end

  local field = ctx.game.data and ctx.game.data.field
  local def = field and field.gen2BugContest
  local ids = def and def.contestantFlags
  if type(ids) ~= "table" or #ids == 0 then
    Logger.warn("bug contest: no contestant flag table; the entrants cannot "
                .. "be picked (re-import to pick them up)")
    return
  end
  local Gen2Flags = require("src.script.Gen2Flags")
  local flags = ctx.save.flags or {}
  ctx.save.flags = flags
  -- .loop1: every one of them starts visible
  for _, id in ipairs(ids) do
    flags[Gen2Flags.eventFlag(id)] = nil
  end
  -- .loop2: hide five, re-rolling a duplicate exactly as the ROM does
  local hidden, guard = 0, 0
  while hidden < math.min(BUG_CONTESTANTS_IN_PARK, #ids) and guard < 500 do
    guard = guard + 1
    local pick = math.random(1, #ids)
    local key = Gen2Flags.eventFlag(ids[pick])
    if not flags[key] then
      flags[key] = true
      hidden = hidden + 1
    end
  end
end

-- The deferred half of a Gen2 map's onEnter: run the scene script wMapScenes
-- names for this map, NOW -- after the map's MAPCALLBACK_NEWMAP callbacks have
-- had their turn in the pending-script queue and had their chance to
-- `setscene`.  See the note in Gen2ScriptVM's contributionFor for why the
-- lookup cannot happen at onEnter time.
function Commands.g2_run_map_scene(ctx, mapId)
  local ow = ctx.overworld
  if not (ow and type(mapId) == "string") then return end
  require("src.script.Gen2ScriptVM").runMapScene(ctx.game, ow, mapId)
end

-- BugContestJudging (03:$434A) ranks the player against the field and leaves
-- the placing where the BugContestResults_* scripts can branch on it.  It also
-- sets the script variable, which is what `ifequal` in those scripts tests:
-- 1/2/3 for a placing and 0 for nothing.
function Commands.g2_bug_contest_judging(ctx)
  local BugContest = require("src.world.BugContest")
  local placing = BugContest.judge(ctx.game)
  -- BugContestResultsScript opens with `clearflag ENGINE_BUG_CONTEST_TIMER`,
  -- one line above the text that leads into this special, so by the time the
  -- judge speaks the RUN is over even though the results are not: no clock, no
  -- Park Balls, no contest encounter table and no contest panel in the START
  -- menu.  finish() is exactly those surfaces and nothing else -- the placing,
  -- the caught mon and the held party all survive it, because the prize branch
  -- and CheckPartyFullAfterContest still have to read them.
  BugContest.finish(ctx.game)
  setScriptVar(ctx, placing or 0)
end

function Commands.g2_diploma(ctx)
  require("src.ui.Screens").push(ctx.game, "Diploma")
end
Commands.g2_print_diploma = Commands.g2_diploma

function Commands.g2_unown_printer(ctx)
  ctx.lastCheck = true
end

-- Copycat `special LoadUsedSpritesGFX` ($5D)
function Commands.g2_load_used_sprites(ctx)
  local ow = ctx.overworld
  if not (ow and ow.map and ow.map.npcs) then return end
  for _, npc in pairs(ow.map.npcs) do
    if npc.refreshSprite then npc:refreshSprite(ctx.game.data) end
  end
end

-- ---------------------------------------------------------------------------
-- Battle Tower  (Crystal only)
--
-- BattleTower1F, BattleTowerHallway, BattleTowerElevator and
-- BattleTowerBattleRoom already carry their extracted ROM bytecode, so this is
-- only the SpecialsPointers rows that bytecode calls.  The order of events --
-- the receptionist's menu, the quick save, the level pick, the lift, the seven
-- battles, the prize -- is the cartridge script's, not this file's.
--
-- Everything read off the cartridge is in field.gen2BattleTower
-- (RomExtractorGen2:gen2BattleTower); the run state and the rules are
-- src/world/BattleTower.lua.  On Gold and Silver the record is nil, and every
-- handler here answers 0 and stops, which is what those carts do too: they
-- have no tower and no scripts that call any of this.
-- ---------------------------------------------------------------------------

local function towerAnswer(ctx, value)
  ctx.g2Var = value or 0
  ctx.lastCheck = (value or 0) ~= 0
end

-- A blocking menu that answers a row number (0 on B), for the two the tower
-- puts up.  g2_verticalmenu covers the three-row one, but the level picker can
-- be eleven rows and needs the box options, so both go through this.
local function towerMenu(ctx, rows, opts)
  local game, runner = ctx.game, ctx.runner
  local picked = 0
  local items = {}
  for index, label in ipairs(rows) do
    items[index] = {
      label = label,
      onSelect = function() picked = index runner:resume() end,
    }
  end
  local options = { onCancel = function() runner:resume() end }
  for key, value in pairs(opts or {}) do options[key] = value end
  game.stack:push(require("src.ui.Menu").new(game, items, options))
  runner:yield()
  return picked
end

-- BattleTower_GiveReward (5C:$46EE): the bag can take the prize when the item
-- pocket has room for a new stack, or already holds fewer than 95 of it.
local function towerRewardFits(ctx, itemId)
  local save = ctx.save
  local have = save.inventory and save.inventory[itemId]
  if have then return have < 95 end
  return require("src.inventory.Bag").pocketSlots(save, "ITEM", ctx.game.data) < 20
end

-- constants/battle_tower_constants.asm: the answer CheckGSBall gives when the
-- ball is on offer.  Named rather than inlined because the receptionist's
-- script compares against it literally (`ifequal GS_BALL_AVAILABLE`).
local GS_BALL_AVAILABLE = 0x0B

-- BattleTowerAction (5C:$4687) is one special with a jumptable on wScriptVar,
-- so `setval N / special BattleTowerAction` is really N different calls.  The
-- numbers are the cartridge's; the eighteen the tower's scripts actually use
-- are the ones implemented here, and the mobile-only rows answer 0 the way an
-- unlinked cartridge does.
local BATTLE_TOWER_ACTIONS = {
  -- CheckExplanationRead: (sBattleTowerSaveFileFlags & 2), so 2 or 0
  [0x00] = function(ctx, s) towerAnswer(ctx, s.explained and 2 or 0) end,
  [0x01] = function(_, s) s.explained = true end,
  [0x02] = function(ctx, s) towerAnswer(ctx, s.challenge or 0) end,
  -- SetBattleTowerChallengeState: 1 quick saved mid-challenge, 0 cancelled,
  -- 3 challenge won and the prize is owed, 4 prize collected
  [0x03] = function(_, s) s.challenge = 1 end,
  [0x04] = function(_, s) s.challenge = 0 end,
  -- BattleTowerAction_06 zeroes the beaten count and the two day counters the
  -- week-long challenge expiry uses
  [0x06] = function(ctx, s)
    s.beaten, s.opponent = 0, nil
    require("src.world.BattleTower").syncBeaten(ctx.save)
  end,
  -- Save/LoadBattleTowerLevelGroup move the group between SRAM and WRAM; the
  -- port keeps one copy, so both are already done
  [0x07] = function() end,
  [0x08] = function() end,
  -- CheckSaveFileExistsAndIsYours: the port only ever loads the player's own
  -- save, so this is the "yes" branch
  [0x09] = function(ctx) towerAnswer(ctx, 1) end,
  [0x0A] = function() end,           -- restores music volume
  -- CheckGSBall: the cartridge asked the mobile adapter and answered
  -- GS_BALL_AVAILABLE ($0b) once the distribution had run.  There is no
  -- adapter here, so beating the Elite Four is the trigger instead.  Saying
  -- $0b is the whole unlock: GoldenrodPokecenter1F_GSBallScene{Left,Right}
  -- take it from there, and so do Kurt and the Ilex Forest shrine.
  [0x0B] = function(ctx)
    towerAnswer(ctx, Gen2Commands.gsBallAvailable(ctx.save)
      and GS_BALL_AVAILABLE or 0)
  end,
  [0x11] = function() end,           -- mobile bookkeeping byte
  [0x1A] = function(ctx)
    require("src.world.BattleTower").resetTrainers(ctx.game)
  end,
  -- BattleTower_GiveReward leaves the item id in wScriptVar for the
  -- `getitemname` and `giveitem` that follow, or $12 when the bag is full.
  -- The item is NOT handed over here -- the script's own giveitem does that.
  [0x1B] = function(ctx, s)
    local BattleTower = require("src.world.BattleTower")
    local def = BattleTower.data(ctx.game)
    local item = s.reward or BattleTower.rollReward(ctx.game)
    if not item then return towerAnswer(ctx, def and def.rewardBagFull or 18) end
    if not towerRewardFits(ctx, item) then
      return towerAnswer(ctx, def and def.rewardBagFull or 18)
    end
    towerAnswer(ctx, tonumber(tostring(item):match("(%d+)$")) or 0)
  end,
  [0x1C] = function(_, s) s.challenge = 3 end,
  [0x1D] = function(_, s) s.challenge = 4 end,
  [0x1E] = function(ctx)
    require("src.world.BattleTower").rollReward(ctx.game)
  end,
  [0x1F] = function() end,           -- SaveOptions
}

function Commands.g2_battle_tower_action(ctx)
  local BattleTower = require("src.world.BattleTower")
  -- BATTLETOWERACTION_GSBALL is the one row that is not about the tower at
  -- all -- it is the Goldenrod receptionist asking whether the distribution
  -- has run -- so it must answer on a save that has never been near the
  -- tower, which is every save that has just cleared the Elite Four.
  if scriptVar(ctx) == 0x0B then
    return towerAnswer(ctx, Gen2Commands.gsBallAvailable(ctx.save)
      and GS_BALL_AVAILABLE or 0)
  end
  if not BattleTower.available(ctx.game) then return towerAnswer(ctx, 0) end
  local state = BattleTower.state(ctx.save)
  if not state then return towerAnswer(ctx, 0) end
  local action = BATTLE_TOWER_ACTIONS[scriptVar(ctx)]
  if not action then
    -- a mobile-only row: the cartridge's own answer with no link cable is 0
    return towerAnswer(ctx, 0)
  end
  action(ctx, state)
end

-- `special TryQuickSave`: the box the script already printed asked; this is
-- the write.  wScriptVar is 1 when the save happened.
function Commands.g2_try_quick_save(ctx)
  local ok = pcall(function() ctx.game:writeSave() end)
  if ok then require("src.core.Sound").play(ctx.game.data, "Save") end
  towerAnswer(ctx, ok and 1 or 0)
end

-- `special Reset`: the tower's "save and come back later" exit power-cycles
-- the cartridge.  Returning "end" stops the script the way the reset does.
function Commands.g2_soft_reset(ctx)
  -- the challenge state the two actions just before this set has to survive
  -- the trip back to the title, the same way the cartridge's SRAM does
  pcall(function() ctx.game:writeSave() end)
  ctx.game:returnToTitle()
  return "end"
end

-- Menu_ChallengeExplanationCancel (5F:$5224): CHALLENGE / EXPLANATION /
-- CANCEL.  wScriptVar is the row, and the routine presets 4 so backing out
-- with B lands past every `ifequal`.
function Commands.g2_battle_tower_challenge_menu(ctx)
  local BattleTower = require("src.world.BattleTower")
  local def = BattleTower.data(ctx.game)
  local rows = (def and def.menu) or { "CHALLENGE", "EXPLANATION", "CANCEL" }
  Commands.g2_loadmenu(ctx, rows)
  Commands.g2_verticalmenu(ctx)
  if (ctx.g2Var or 0) == 0 then towerAnswer(ctx, 4) end
end

-- `special CheckForBattleTowerRules` (5C:$4BD3 -> 22:$7201).  Four party
-- checks; every failing one prints its own line, then "Please return when
-- you're ready."  wScriptVar is 1 when anything failed, which is what the
-- receptionist's `ifnotequal 0` sends back to the menu.
function Commands.g2_battle_tower_check_rules(ctx)
  local BattleTower = require("src.world.BattleTower")
  local def = BattleTower.data(ctx.game)
  local failed = BattleTower.checkRules(ctx.game)
  if #failed == 0 then return towerAnswer(ctx, 0) end
  local texts = (def and def.ruleTexts) or {}
  -- the routine fills wStringBuffer1 with "3" before it starts, which is the
  -- "3" in "The 3 #MON must all be different kinds."
  ctx.game.stringBuffer = "3"
  if texts[1] and texts[1] ~= "" then Commands.show_text(ctx, texts[1]) end
  for _, rule in ipairs(failed) do
    local line = texts[rule + 1]
    if line and line ~= "" then
      ctx.game.stringBuffer = "3"
      Commands.show_text(ctx, line)
    end
  end
  if def and def.notReadyText and def.notReadyText ~= "" then
    Commands.show_text(ctx, def.notReadyText)
  end
  towerAnswer(ctx, 1)
end

-- `special BattleTowerRoomMenu` (5C:$4190 -> 46:$4021).  Pick a level, then
-- BattleTower_LevelCheck and BattleTower_UbersCheck before it is accepted.
-- wScriptVar answers 0 to proceed and 10 to go back to the receptionist; the
-- ROM's other answers are mobile errors this port cannot reach.
function Commands.g2_battle_tower_room_menu(ctx)
  local BattleTower = require("src.world.BattleTower")
  local def = BattleTower.data(ctx.game)
  local state = BattleTower.state(ctx.save)
  if not (def and state) then return towerAnswer(ctx, 10) end
  local count = BattleTower.levelChoices(ctx.game)
  while true do
    local rows = {}
    for index = 1, count do
      rows[index] = (def.levelLabels and def.levelLabels[index])
        or ("L." .. tostring(index * 10))
    end
    rows[#rows + 1] = def.cancelLabel or "CANCEL"
    -- eleven rows after the Hall of Fame, which is why this one is built here
    -- rather than through g2_verticalmenu: that helper's double-spaced box
    -- would be 24 tiles tall on an 18 tile screen.  The ROM's own pick-level
    -- box is single spaced too (MenuHeader_119cf7).
    local picked = towerMenu(ctx, rows, { rowStep = 1, tw = 8, maxVisible = 11 })
    if picked == 0 or picked > count then return towerAnswer(ctx, 10) end
    local over = BattleTower.levelCheck(ctx.game, picked)
    local uber = not over and BattleTower.uberCheck(ctx.game, picked)
    if not (over or uber) then
      state.group = picked
      return towerAnswer(ctx, 0)
    end
    -- BattleTowerRoomMenu_PartyMonTopsThisLevelMessage /
    -- _UberRestrictionMessage: the offending mon is named, then the level
    -- menu comes straight back up.
    local mon = over or uber
    local monDef = mon and ctx.game.data.pokemon[mon.species]
    local name = (monDef and monDef.name) or tostring(mon and mon.species or "")
    ctx.game.stringBuffer = name
    Commands.show_text(ctx, over
      and Strings("%s is above the\nlevel limit.", name)
      or Strings("%s may not enter\nbelow L.70.", name))
  end
end

-- `special LoadOpponentTrainerAndPokemonWithOTSprite` (5C:$4B44): rolls the
-- next trainer and their three mons, and puts that trainer class's overworld
-- sheet on the battle room object the preceding `setval` names.
function Commands.g2_battle_tower_load_opponent(ctx)
  local BattleTower = require("src.world.BattleTower")
  local opponent = BattleTower.rollOpponent(ctx.game)
  if not opponent then return towerAnswer(ctx, 0) end
  local obj, _, slot = objectByIndex(ctx, scriptVar(ctx))
  if obj and opponent.sprite then
    obj.sprite = opponent.sprite
    local ow = ctx.overworld
    local npc = slot and ow and ow.npcByIndex and ow:npcByIndex(slot) or nil
    if npc and npc.refreshSprite then npc:refreshSprite(ctx.game.data) end
  end
  towerAnswer(ctx, 0)
end

-- `battletowertext <slot>`: the opponent's own line.
function Commands.g2_battle_tower_text(ctx, slot)
  local line = require("src.world.BattleTower").line(ctx.game, slot or 1)
  if line and line ~= "" then Commands.show_text(ctx, line) end
end

-- `special BattleTowerBattle` (5C:$4249 -> RunBattleTowerTrainer).  One
-- battle against the generated opponent.  wScriptVar is wBattleResult the same
-- way a scripted `startbattle` leaves it -- 0 won, nonzero did not -- and the
-- beaten count the battle room reads back with `readmem` moves here.
function Commands.g2_battle_tower_battle(ctx)
  local BattleTower = require("src.world.BattleTower")
  local state = BattleTower.state(ctx.save)
  local opponent = state and state.opponent
  if not opponent then return towerAnswer(ctx, 1) end
  local BattleState = require("src.battle.BattleState")
  local runner = ctx.runner
  local battle = BattleState.newBattleTowerTrainer(ctx.game, opponent)
  -- BATTLETYPE_CANLOSE.  Losing here is not a blackout: the ROM hands control
  -- straight back to Script_BattleRoom, whose `ifnotequal 0
  -- Script_FailedBattleTowerChallenge` runs `warpfacing 1, BATTLE_TOWER_1F,
  -- 7, 7` and prints "Thanks for visiting!".  Blacking out first sent the
  -- player to the last POKeCENTER, and then the script's own warpfacing
  -- yanked them back to the tower a second later.
  battle.canLose = true
  battle.onFinish = function(result)
    ctx.lastBattleResult = result
    if result == "win" then
      BattleTower.recordWin(ctx.game)
    else
      BattleTower.recordLoss(ctx.game)
      -- the challenge is over; the script's own `ifnotequal 0` walks the
      -- player back to the lobby and cancels it
      state.challenge = 0
    end
    if ctx.overworld then
      -- same split Commands.start_battle makes: a win keeps the evolution
      -- screen behind the rest of the script (here, the whole run of seven),
      -- a loss runs straight away because the script is about to end
      if result == "win" then
        ctx.afterScript = ctx.afterScript or {}
        table.insert(ctx.afterScript, function()
          ctx.overworld:afterBattle(result, battle)
        end)
      else
        ctx.overworld:afterBattle(result, battle)
      end
    end
    runner:resume()
  end
  if ctx.overworld and ctx.overworld.pushBattle then
    ctx.overworld:pushBattle(battle)
  else
    ctx.game.stack:push(battle)
  end
  runner:yield()
  towerAnswer(ctx, ctx.lastBattleResult == "win" and 0 or 1)
end

-- BattleTowerHallwayChooseBattleRoomScript.asm_load_battle_room (27:$75CB):
-- the chosen level group, which the ifequal chain after it turns into which
-- door the receptionist walks the player to.
function Commands.g2_battle_tower_room_index(ctx)
  local state = require("src.world.BattleTower").state(ctx.save)
  towerAnswer(ctx, state and state.group or 1)
end

-- ITEM_FROM_MEM forms of giveitem / getitemname (Gen2ScriptVM lowers the $FF
-- and $00 operands to these).  The Battle Tower's prize is the only user.
local function itemFromVar(ctx)
  return string.format("ITEM_%03d", math.floor(scriptVar(ctx)) % 256)
end

function Commands.g2_giveitem_var(ctx, count)
  Commands.g2_giveitem(ctx, itemFromVar(ctx), count)
end

function Commands.g2_getitemname_var(ctx, buffer)
  Commands.g2_getitemname(ctx, itemFromVar(ctx), buffer)
end

return Gen2Commands
