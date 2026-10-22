-- Portable native audio cues, with pure data lookup and bounded waits.
local Version = require("src.core.GameVersion")
local A = {
  ARITY = {
    play_sound = 2,
    wait_sound = 1,
    play_music = 3,
    stop_music = 1,
    fade_music = 2,
    play_once = 2,
    play_default_music = 1,
  },
}
local function integer(v, max)
  return type(v) == "number" and v == v and v >= 0 and v <= max and v % 1 == 0
end
local function id(v)
  return type(v) == "string" and #v > 0 and #v <= 256 and not v:find("%c") or integer(v, 65535)
end
function A.syntax(verb, row, context)
  if (context.generation or Version.generation()) > 3 then
    return nil, "portable audio unavailable for this generation"
  end
  local minimum = (verb == "play_music" and 2 or verb == "fade_music" and 1) or A.ARITY[verb]
  if #row < minimum or #row > A.ARITY[verb] then
    return nil, "invalid command arity"
  end
  local out = { row[1], row[2] }
  if verb == "fade_music" then
    if row[2] ~= nil and not integer(row[2], 255) then
      return nil, "invalid music fade"
    end
  elseif verb == "play_sound" or verb == "play_music" or verb == "play_once" then
    if not id(row[2]) then
      return nil, "invalid audio id"
    end
  end
  if verb == "play_music" and row[3] ~= nil then
    if type(row[3]) ~= "table" or getmetatable(row[3]) ~= nil then
      return nil, "invalid music options"
    end
    out[3] = {}
    for k, v in pairs(row[3]) do
      if
        not (
          k == "keep" and type(v) == "boolean"
          or k == "reason" and type(v) == "string" and #v <= 256 and not v:find("%c")
        )
      then
        return nil, "invalid music option"
      end
      out[3][k] = v
    end
  end
  return out
end
function A.resolve(game, row)
  local verb, ref = row[1], row[2]
  if Version.generation() == 3 and verb == "play_music" and ref == 0 then
    return { stop = true }
  end
  local audio = game.data.audio or {}
  local sound = verb == "play_sound"
  local rows = sound and audio.sfx or audio.songs
  if rows and (type(rows[ref]) == "table" or type(rows[ref]) == "string") then
    return { key = ref, sound = sound }
  end
  if Version.generation() == 3 and (sound or verb == "play_music" or verb == "play_once") then
    if verb == "play_once" and ref == "Get_Item1" then
      local def = audio.sfx and audio.sfx.Get_Item1
      if type(def) == "table" then
        ref = def.song or def.m4a or ref
      end
    end
    local key, def = require("src.core.Sound").sequenceKey(game.data, ref)
    if key then
      return { key = key, sound = sound, sequence = sound }
    end
    if def then
      return nil, def
    end
  end
  return nil, "native audio unavailable: " .. tostring(row[2])
end
function A.prepare(game, rows)
  for i, row in ipairs(rows) do
    if row[1] == "play_sound" or row[1] == "play_music" or row[1] == "play_once" then
      local plan, why = A.resolve(game, row)
      if not plan then
        return nil, "row " .. i .. ": " .. why
      end
    end
  end
  return function(ctx, row, wait, alive)
    local verb = row[1]
    local Sound, Music = require("src.core.Sound"), require("src.core.Music")
    if verb == "stop_music" then
      Music.stop()
    elseif verb == "fade_music" then
      Music.fadeOut(row[2] or 10)
    elseif verb == "play_default_music" then
      local ow = ctx.overworld
      Music.playMap(game.data, ow.map.id, game.save.onBike, ow.player.surfing)
    elseif verb == "wait_sound" then
      local source = ctx.lastSfxSrc
      ctx.lastSfxSrc = nil
      local function busy()
        if Sound.anyPlaying("sfx") then
          return true
        end
        if not source then
          return false
        end
        local ok, value = pcall(function()
          return source:isPlaying()
        end)
        return ok and value == true
      end
      if busy() then
        wait(function()
          return not busy()
        end, 600, true)
      end
    else
      local plan, why = A.resolve(game, row)
      if not plan then
        error(why, 0)
      end
      if verb == "play_sound" then
        if plan.sequence then
          ctx.lastSfxSrc = Sound.playNamedEffect(game.data, plan.key)
        else
          ctx.lastSfxSrc = Sound.play(game.data, plan.key)
        end
      elseif verb == "play_music" then
        if plan.stop then
          Music.stop()
          return
        end
        Music.play(game.data, plan.key, nil, row[3])
        if alive() and row[3] and row[3].keep then
          ctx.overworld.keepMusicOnce = true
        end
      elseif Music.playOnce(game.data, plan.key) then
        wait(function()
          return Music.current() ~= plan.key or not Music.oneShotPlaying()
        end, 3600, false)
      end
    end
  end
end
return A
