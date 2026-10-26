-- Pure preflight for the bounded portable dialogue/control-flow language.
local Program = {}
local State = require("src.mods.ScriptState")
local Gifts = require("src.mods.ScriptGifts")
local Audio = require("src.mods.ScriptAudio")
local DialogueAudio = require("src.mods.ScriptDialogueAudio")
local Shops = require("src.mods.ScriptShops")
local Battles = require("src.mods.ScriptBattles")
local Travel = require("src.mods.ScriptTravel")
local Movement = require("src.mods.ScriptMovement")
local WorldEdits = require("src.mods.ScriptWorldEdits")
Program.MAX_ROWS, Program.MAX_STEPS, Program.SLICE = 1024, 65536, 128
local ARITY = {
  set_flag = 2,
  clear_flag = 2,
  check_flag = 2,
  wait_flag = 3,
  show_text = 2,
  ask = 2,
  choice = 3,
  wait = 2,
  label = 2,
  jump = 2,
  jump_if_true = 2,
  jump_if_false = 2,
  ["end"] = 1,
}
for verb, arity in pairs(State.ARITY) do
  ARITY[verb] = arity
end
for verb, arity in pairs(Gifts.ARITY) do
  ARITY[verb] = arity
end
for verb, arity in pairs(WorldEdits.ARITY) do
  ARITY[verb] = arity
end
for verb, arity in pairs(Movement.ARITY) do
  ARITY[verb] = arity
end
for verb, arity in pairs(Travel.ARITY) do
  ARITY[verb] = arity
end
for verb, arity in pairs(Battles.ARITY) do
  ARITY[verb] = arity
end
for verb, arity in pairs(Shops.ARITY) do
  ARITY[verb] = arity
end
for verb, arity in pairs(Audio.ARITY) do
  ARITY[verb] = arity
end
for verb, arity in pairs(DialogueAudio.ARITY) do
  ARITY[verb] = arity
end
local aliases = { text = "show_text", setflag = "set_flag", clearflag = "clear_flag" }
function Program.supports(verb)
  if type(verb) ~= "string" then
    return false
  end
  if
    (
      WorldEdits.ARITY[verb]
      or Movement.ARITY[verb]
      or Travel.ARITY[verb]
      or Battles.ARITY[verb]
      or Shops.ARITY[verb]
      or Audio.ARITY[verb]
      or DialogueAudio.ARITY[verb]
    ) and require("src.core.GameVersion").generation() > 3
  then
    return false
  end
  return ARITY[aliases[verb] or verb] ~= nil
end
local function integer(n, lo, hi)
  return type(n) == "number" and n == n and n % 1 == 0 and n >= lo and n <= hi
end
local function array(t, max)
  if type(t) ~= "table" or getmetatable(t) ~= nil then
    return nil
  end
  local n = 0
  for k in pairs(t) do
    if not integer(k, 1, max) then
      return nil
    end
    n = n + 1
  end
  for i = 1, n do
    if rawget(t, i) == nil then
      return nil
    end
  end
  return n
end
local function label(s)
  return type(s) == "string" and #s > 0 and #s <= 64 and s:match("^[%w_:%-]+$") ~= nil
end
local function text(value, max)
  if type(value) ~= "string" or #value > max or value:find("%z") then
    return false
  end
  local i = 1
  while i <= #value do
    local b = value:byte(i)
    local n = b < 128 and 1
      or b >= 194 and b <= 223 and 2
      or b >= 224 and b <= 239 and 3
      or b >= 240 and b <= 244 and 4
    if not n or i + n - 1 > #value then
      return false
    end
    for j = i + 1, i + n - 1 do
      local c = value:byte(j)
      if c < 128 or c > 191 then
        return false
      end
    end
    if n > 1 then
      local c = value:byte(i + 1)
      if b == 224 and c < 160 or b == 237 and c > 159 or b == 240 and c < 144 or b == 244 and c > 143 then
        return false
      end
    end
    i = i + n
  end
  return true
end
function Program.compile(raw, context)
  context = context or {}
  local n = array(raw, Program.MAX_ROWS)
  if not n then
    return nil, "script must be a dense plain array of at most 1024 rows"
  end
  local rows, labels, bytes = {}, {}, 0
  local function fail(i, message)
    return nil, "row " .. i .. ": " .. message
  end
  for i = 1, n do
    local source, count = raw[i], array(raw[i], 5)
    if not count or count == 0 then
      return fail(i, "expected a dense plain command row")
    end
    local verb = aliases[source[1]] or source[1]
    if type(verb) ~= "string" or not ARITY[verb] then
      return fail(i, "unsupported portable command")
    end
    if
      not State.ARITY[verb]
      and not Gifts.ARITY[verb]
      and not WorldEdits.ARITY[verb]
      and not Movement.ARITY[verb]
      and not Travel.ARITY[verb]
      and not Battles.ARITY[verb]
      and not Shops.ARITY[verb]
      and not Audio.ARITY[verb]
      and not DialogueAudio.ARITY[verb]
      and (count > ARITY[verb] or count < ((verb == "choice" or verb == "wait_flag") and 2 or ARITY[verb]))
    then
      return fail(i, "invalid command arity")
    end
    local row = { verb, source[2] }
    if DialogueAudio.ARITY[verb] then
      local value, reason = DialogueAudio.syntax(verb, source, context)
      if not value then
        return fail(i, reason)
      end
      row = value
    elseif Audio.ARITY[verb] then
      local value, reason = Audio.syntax(verb, source, context)
      if not value then
        return fail(i, reason)
      end
      row = value
    elseif Shops.ARITY[verb] then
      local value, reason = Shops.syntax(verb, source, context)
      if not value then
        return fail(i, reason)
      end
      row = value
    elseif Battles.ARITY[verb] then
      local value, reason = Battles.syntax(verb, source, context)
      if not value then
        return fail(i, reason)
      end
      row = value
    elseif Travel.ARITY[verb] then
      local value, reason = Travel.syntax(verb, source, context)
      if not value then
        return fail(i, reason)
      end
      row = value
    elseif Movement.ARITY[verb] then
      local value, reason = Movement.syntax(verb, source, context)
      if not value then
        return fail(i, reason)
      end
      row = value
    elseif WorldEdits.ARITY[verb] then
      local value, reason = WorldEdits.syntax(verb, source, context)
      if not value then
        return fail(i, reason)
      end
      row = value
    elseif Gifts.ARITY[verb] then
      local value, reason = Gifts.syntax(verb, source)
      if not value then
        return fail(i, reason)
      end
      row = value
      for _, index in ipairs({ 4, 5 }) do
        if type(row[index]) == "string" then
          if not text(row[index], 4096) then
            return fail(i, "gift text must be valid UTF-8 without NUL")
          end
          bytes = bytes + #row[index]
        end
      end
    elseif State.ARITY[verb] then
      local value, reason = State.syntax(verb, source)
      if not value then
        return fail(i, reason)
      end
      row = value
    elseif verb == "set_flag" or verb == "clear_flag" or verb == "check_flag" or verb == "wait_flag" then
      local Version = require("src.core.GameVersion")
      local address, reason = require("src.mods.Api3Flags").address(
        context.owner or "",
        context.generation or Version.generation(),
        context.version or Version.get(),
        source[2]
      )
      if not address then
        return fail(i, reason)
      end
      if verb == "wait_flag" then
        if source[3] ~= nil and not integer(source[3], 0, 36000) then
          return fail(i, "invalid flag timeout")
        end
        row[3] = source[3]
      end
    elseif verb == "show_text" or verb == "ask" then
      if not text(source[2], 4096) then
        return fail(i, "text must be valid UTF-8 without NUL, at most 4096 bytes")
      end
      bytes = bytes + #source[2]
    elseif verb == "choice" then
      local size = array(source[2], 16)
      if not size or size == 0 then
        return fail(i, "choice needs 1-16 labels")
      end
      row[2] = {}
      for j = 1, size do
        local value = source[2][j]
        if not text(value, 128) or #value == 0 then
          return fail(i, "invalid choice label")
        end
        row[2][j], bytes = value, bytes + #value
      end
      local opts = source[3]
      row[3] = { default = 1, cancel = size }
      if opts ~= nil then
        if type(opts) ~= "table" or getmetatable(opts) ~= nil then
          return fail(i, "choice options must be a plain table")
        end
        for key, value in pairs(opts) do
          if (key ~= "default" and key ~= "cancel") or not integer(value, 1, size) then
            return fail(i, "invalid choice option")
          end
          row[3][key] = value
        end
      end
    elseif verb == "wait" then
      if not integer(source[2], 0, 36000) then
        return fail(i, "wait must be 0-36000 native logic frames")
      end
    elseif verb == "label" then
      if not label(source[2]) or source[2] == "end" or labels[source[2]] then
        return fail(i, "invalid or duplicate label")
      end
      labels[source[2]] = i
    elseif verb ~= "end" then
      if not label(source[2]) and not integer(source[2], 1, n) then
        return fail(i, "invalid jump target")
      end
    end
    if bytes > 131072 then
      return fail(i, "script text exceeds 128 KiB")
    end
    rows[i] = row
  end
  for i, row in ipairs(rows) do
    if row[1] == "jump" or row[1] == "jump_if_true" or row[1] == "jump_if_false" then
      local target = row[2]
      if type(target) == "string" then
        if target == "end" then
          row[2] = n + 1
        elseif labels[target] then
          row[2] = labels[target]
        else
          return fail(i, "jump to missing label")
        end
      end
    end
  end
  return rows
end
return Program
