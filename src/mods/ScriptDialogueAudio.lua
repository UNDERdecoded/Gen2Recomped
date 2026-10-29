-- Deferred, owned dialogue cues. Native TextBox supplies its 600-frame gate.
local Audio = require("src.mods.ScriptAudio")
local Version = require("src.core.GameVersion")
local D = { ARITY = { play_cry = 3, text_sound = 2, engage_music = 2 } }
function D.syntax(verb, row, context)
  if (context.generation or Version.generation()) > 3 then
    return nil, "portable dialogue audio unavailable for this generation"
  end
  if #row < 2 or #row > D.ARITY[verb] then
    return nil, "invalid command arity"
  end
  if verb == "play_cry" then
    if
      type(row[2]) ~= "string"
      or not row[2]:match("^[A-Z][A-Z0-9_]*$")
      or #row[2] > 128
      or row[3] ~= nil and type(row[3]) ~= "boolean"
    then
      return nil, "invalid cry"
    end
    return { verb, row[2], row[3] }
  end
  local out, why = Audio.syntax(
    verb == "text_sound" and "play_sound" or "play_music",
    { verb == "text_sound" and "play_sound" or "play_music", row[2] },
    context
  )
  if not out then
    return nil, why
  end
  return { verb, row[2] }
end
function D.prepare(loader, game, rows)
  local ids = require("src.mods.UnifiedIds").new(loader)
  local function resolve(row)
    if row[1] ~= "play_cry" then
      return Audio.resolve(game, { row[1] == "text_sound" and "play_sound" or "play_music", row[2] })
    end
    local group, why = ids:resolve("pokemon", row[2])
    local mon = group and game.data.pokemon and game.data.pokemon[group.key]
    if not mon then
      return nil, why or "cry species unavailable"
    end
    local audio = game.data.audio or {}
    local def = audio.cries
      and (
        audio.cries[group.key]
        or type(group.key) == "number" and audio.cries[mon.translationSourceName or mon.name]
      )
    local pika = Version.get() == "yellow"
      and group.key == "PIKACHU"
      and type(audio.pikaCries) == "table"
      and audio.pikaCries[1]
    if type(def) ~= "table" and type(def) ~= "string" and not pika then
      return nil, "native cry unavailable: " .. row[2]
    end
    return { key = group.key, cry = true }
  end
  for i, row in ipairs(rows) do
    if D.ARITY[row[1]] then
      local plan, why = resolve(row)
      if not plan then
        return nil, "row " .. i .. ": " .. why
      end
    end
  end
  local function checked(row)
    local plan, why = resolve(row)
    if not plan then
      error(why, 0)
    end
    return plan
  end
  local function arm(ctx, row)
    checked(row)
    ctx.dialogueAudio = ctx.dialogueAudio or {}
    ctx.dialogueAudio[row[1]] = row
  end
  local function options(ctx, asking, alive)
    local cues = ctx.dialogueAudio
    ctx.dialogueAudio = nil
    if not cues then
      return nil
    end
    for _, row in pairs(cues) do
      checked(row)
    end
    local Sound, Music = require("src.core.Sound"), require("src.core.Music")
    local sources, started, engaged, waited = {}, false, false, 0
    -- Throw only after a callback entered alive: abort native update before it
    -- can pop a foreign overlay installed by a reentrant audio hook.
    local function stillAlive()
      if not alive() then
        error("dialogue audio owner retired", 0)
      end
    end
    local function busy()
      if not alive() then
        return false
      end
      local playing = false
      for _, src in ipairs(sources) do
        local ok, value = pcall(function()
          return src:isPlaying()
        end)
        stillAlive()
        playing = playing or ok and value == true
      end
      return playing
    end
    local function sound()
      if started or not alive() then
        return nil
      end
      started = true
      for _, verb in ipairs({ "play_cry", "text_sound" }) do
        if cues[verb] then
          local p = checked(cues[verb])
          local src
          if p.cry then
            src = Sound.playCry(game.data, p.key)
          elseif p.sequence then
            src = Sound.playNamedEffect(game.data, p.key)
          else
            src = Sound.play(game.data, p.key)
          end
          stillAlive()
          if src and p.sequence then
            Music.duckForFanfare(src)
            stillAlive()
          end
          if src then
            sources[#sources + 1] = src
          end
        end
      end
      return { isPlaying = busy }
    end
    local function tick()
      if engaged or not alive() then
        return
      end
      waited = waited + 1
      if busy() and waited < 600 then
        return
      end
      engaged = true
      if cues.engage_music then
        local p = checked(cues.engage_music)
        if p.stop then
          Music.stop()
        else
          Music.play(game.data, p.key)
        end
        stillAlive()
      end
    end
    local cry = cues.play_cry
    return {
      auto = { sound = sound, tick = tick, delay = 0, wait = asking or not cry or cry[3] == true },
    }
  end
  return { arm = arm, options = options }
end
return D
