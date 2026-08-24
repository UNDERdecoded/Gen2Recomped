-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Events: the things that HAPPEN on a map, built out of parts rather than typed.
--
-- WHY THIS EXISTS WHEN THERE IS ALREADY A SCRIPT EDITOR. The SCRIPTS tool edits
-- the engine's rows directly -- `{ "show_text", "..." }`, `{ "jump_if_false",
-- "skip" }` -- and that is the right tool for somebody who already knows the
-- command set and wants exactly one thing. It is the wrong tool for "a guard
-- stops you crossing the bridge until you have the badge", which is nine rows,
-- two labels and a jump, and every one of them has to be right or the guard
-- walks through a wall or the text never closes.
--
-- So this is a layer of BEATS -- say this, walk there, set that flag, only if
-- this one is set -- and a lowering from beats to the engine's own rows. There
-- is no new runtime: `ScriptRunner` walks the output exactly as it walks a
-- hand-written script, `ScriptRunner.validate` checks it, and anything this
-- cannot express is still reachable by dropping to the SCRIPTS tool. A beat
-- that lowered to something the engine could not run would be worse than no
-- beat at all, so every one of them maps to a command in `src/script/Commands`
-- and nothing here invents an opcode.
--
-- WHERE AN EVENT LIVES. Two places, and they are different questions:
--
--   * ON A CELL ("step" trigger) -- the event tile. It is not a tile: nothing
--     about the ground changes, exactly as a warp changes nothing about the
--     square it sits on. It is a coordinate the step handler checks.
--   * ON AN OBJECT ("talk" trigger) -- what an NPC does when you talk to them,
--     which is the object's `script` field and already had a home.
--
-- FLAGS ARE JUST NAMES. `Flags.set(save, name)` takes any string and
-- `save.flags` is a plain table, so `house_unlock_door` needs nothing from the
-- engine to exist -- it exists the moment something sets it. What the editor
-- adds is a REGISTRY: a list of the names this project has invented, so the
-- second event can pick the flag the first one sets from a list instead of the
-- author having to remember how they spelled it. A misspelled flag is the
-- worst bug this system can produce, because both halves work perfectly and
-- the door simply never opens.

local MapEdits = require("tools.map-editor.MapEdits")

local MapEvents = {}

-- ---------------------------------------------------------------------------
-- the flag registry
-- ---------------------------------------------------------------------------

function MapEvents.gameOf(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring((S and S.version) or v or "unknown")
end

local function store(S)
  if not S.mapEdits then S.mapEdits = (MapEdits.load()) end
  return S.mapEdits
end

-- Names are normalised on the way in: a flag is a key in a table, so
-- `House Door` and `house_door` are two flags that look like one, and the
-- moment they diverge the door stops opening for reasons nothing on screen
-- explains.
function MapEvents.normalise(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil end
  name = name:gsub("%s+", "_"):gsub("[^%w_]", "")
  return name:upper()
end

-- WHAT A FLAG IS CALLED, as opposed to what it is stored as.
--
-- The extractor names every cartridge flag `EVENT_G2_%04d` -- a bit index in
-- wEventFlags -- because that is what the scripts and the imported saves have
-- to agree on. It is also completely opaque: a list of `EVENT_G2_1600`,
-- `EVENT_G2_1601` tells the author nothing about which one is the Azalea gym
-- badge, so choosing a flag to gate a door on is guesswork.
--
-- `Gen2Flags.EVENT_FLAG_NAMES` is pret's own `event_flags.asm` -- 1369 named
-- bits -- and the save editor already labels with it. Same table here: the
-- NAME is shown, the id is what gets stored, so nothing downstream changes.
function MapEvents.flagLabel(name)
  local ok, Gen2Flags = pcall(require, "src.script.Gen2Flags")
  if ok and type(Gen2Flags) == "table" and Gen2Flags.eventFlagDisplay then
    local okD, pretty = pcall(Gen2Flags.eventFlagDisplay, name)
    if okD and type(pretty) == "string" then return pretty end
  end
  return name
end

-- Both spellings match a search, because the reader may know either: the name
-- if they are thinking about the story, the number if they are reading a
-- script that names it.
function MapEvents.flagMatches(name, query)
  if not query or query == "" then return true end
  query = query:lower()
  return tostring(name):lower():find(query, 1, true) ~= nil
      or MapEvents.flagLabel(name):lower():find(query, 1, true) ~= nil
end

function MapEvents.flags(S)
  return MapEdits.flags(store(S), MapEvents.gameOf(S))
end

-- Every flag this project could mean: the ones invented here, plus the ones
-- the cartridge's own events already use. The second half matters -- gating a
-- new event on EVENT_GOT_A_POKEMON_FROM_ELM is a perfectly ordinary thing to
-- want, and it is not a name anybody would type correctly from memory.
function MapEvents.knownFlags(S, limit)
  local seen, out = {}, {}
  for _, name in ipairs(MapEvents.flags(S)) do
    if not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  local n = 0
  for _, def in pairs((S.data and S.data.maps) or {}) do
    for _, obj in ipairs(def.objects or {}) do
      local f = obj.eventFlag
      if type(f) == "string" and f ~= "" and not seen[f] then
        seen[f] = true
        out[#out + 1] = f
        n = n + 1
        if limit and n >= limit then break end
      end
    end
  end
  table.sort(out)
  return out
end

-- WHAT IS ALREADY ON THIS MAP, which is not nothing.
--
-- The list showed only what the editor had made, so on Azalea Town -- a map
-- with a dozen scripted objects and its own step triggers -- it said "no
-- events on this map yet". That is true of the editor's store and false of
-- the map, and the reader is looking at the map.
--
-- READ-ONLY, and marked as such. These are the cartridge's own scripts: ROM
-- bytecode reached through a label, compiled by `Gen2ScriptVM` at run time.
-- There is no way back from that to a list of beats -- the beats are an
-- authoring idea and the bytecode never had them -- so offering an Edit button
-- would be offering something that cannot work. What they ARE good for is
-- knowing they are there: where the existing triggers sit, which objects
-- already do something, and which flag each one turns on.
function MapEvents.cartridgeEvents(S, mapId)
  mapId = mapId or (S and S.mapId)
  local out = {}
  local def = S and S.data and S.data.maps and S.data.maps[mapId or ""]
  if not def then return out end

  -- The step triggers the extractor read out of the map header.
  local pool = S.data and S.data.map_scripts
  local entry = pool and (pool[mapId] or (pool.maps and pool.maps[mapId]))
  for _, c in ipairs((type(entry) == "table" and entry.coords) or {}) do
    if c.x and c.y then
      out[#out + 1] = { kind = "coord", x = c.x, y = c.y,
                        scene = c.scene, script = c.script,
                        name = string.format("step trigger at %d,%d",
                                             c.x, c.y) }
    end
  end

  -- And the objects that do something: a script, a line of dialogue, or a
  -- spawn flag. An NPC who only stands there is not an event.
  for _, obj in ipairs(def.objects or {}) do
    local what = nil
    if type(obj.script) == "table" and #obj.script > 0 then
      what = "script"
    elseif obj.text and obj.text ~= "" then
      what = "talks"
    elseif obj.trainerClass then
      what = "trainer"
    end
    if what or (obj.eventFlag and obj.eventFlag ~= "") then
      out[#out + 1] = {
        kind = "object", object = obj.index, x = obj.x, y = obj.y,
        flag = obj.eventFlag, what = what,
        name = string.format("%s #%s", obj.name or obj.sprite or "object",
                             tostring(obj.index or "?")),
      }
    end
  end
  return out
end

function MapEvents.addFlag(S, name)
  name = MapEvents.normalise(name)
  if not name then return nil, "give the flag a name" end
  local ok, why = MapEdits.addFlag(store(S), MapEvents.gameOf(S), name)
  if not ok then return nil, why end
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return name
end

function MapEvents.removeFlag(S, name)
  MapEdits.removeFlag(store(S), MapEvents.gameOf(S), name)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return true
end

-- ---------------------------------------------------------------------------
-- the beats
-- ---------------------------------------------------------------------------

-- EVERY BEAT NAMES A REAL COMMAND. The `lower` function is the whole contract:
-- given the beat's fields it returns rows `ScriptRunner` can walk. `args`
-- describes the fields for the panel so the form is generated from the same
-- table the lowering reads -- one place to change when a beat gains a field,
-- rather than a form and a lowering that drift apart.
--
-- `kind` values are stored, so they are permanent: renaming one orphans every
-- event that used it.
MapEvents.BEATS = {
  {
    kind = "say", label = "SAY", blurb = "show a line of text",
    args = { { key = "text", kind = "text", label = "TEXT",
               placeholder = "what they say..." } },
    lower = function(b) return { { "show_text", tostring(b.text or "") } } end,
  },
  {
    kind = "ask", label = "ASK", blurb = "a yes/no question; later beats "
      .. "run only on yes",
    args = { { key = "text", kind = "text", label = "TEXT",
               placeholder = "ask something..." } },
    -- The rest of the event becomes the YES branch. That is the useful
    -- reading by a distance -- "do you want it?" then the giving -- and the NO
    -- branch is an event of its own gated the other way if anybody needs one.
    lower = function(b, ctx)
      return { { "ask", tostring(b.text or "") },
               { "jump_if_false", ctx.endLabel } }
    end,
  },
  {
    kind = "face", label = "FACE ME", blurb = "the object turns to the player",
    args = {},
    lower = function() return { { "face_player" } } end,
  },
  {
    kind = "emote", label = "EMOTE", blurb = "the ! bubble over someone",
    args = { { key = "who", kind = "object", label = "WHO" },
             { key = "bubble", kind = "choice", label = "BUBBLE",
               options = { "shock", "question", "happy", "sad", "heart",
                           "sleep" } } },
    lower = function(b)
      return { { "emote", b.who or "player", b.bubble or "shock" } }
    end,
  },
  {
    kind = "walk_npc", label = "NPC WALKS", blurb = "one object, a path",
    args = { { key = "who", kind = "object", label = "WHO" },
             { key = "path", kind = "path", label = "PATH" } },
    lower = function(b)
      local dirs = MapEvents.parsePath(b.path)
      if #dirs == 0 then return {} end
      return { { "walk_npc", b.who or 1, dirs } }
    end,
  },
  {
    kind = "walk_player", label = "PLAYER WALKS", blurb = "push the player "
      .. "along a path",
    args = { { key = "path", kind = "path", label = "PATH" } },
    lower = function(b)
      local dirs = MapEvents.parsePath(b.path)
      if #dirs == 0 then return {} end
      return { { "walk_npc", "player", dirs } }
    end,
  },
  {
    kind = "block", label = "BLOCK THE WAY",
    blurb = "turn, speak, and push the player back",
    -- THE ONE THE WHOLE FEATURE WAS ASKED FOR, and it is three beats that are
    -- always used together and always in this order: an NPC who speaks after
    -- pushing you back reads as a bug, and one who pushes without turning
    -- reads as a shove from behind.
    args = { { key = "text", kind = "text", label = "TEXT",
               placeholder = "you can't go through..." },
             { key = "path", kind = "path", label = "PUSH BACK",
               placeholder = "d d" } },
    lower = function(b)
      local rows = { { "face_player" } }
      if b.text and b.text ~= "" then
        rows[#rows + 1] = { "show_text", tostring(b.text) }
      end
      local dirs = MapEvents.parsePath(b.path)
      if #dirs > 0 then rows[#rows + 1] = { "walk_npc", "player", dirs } end
      return rows
    end,
  },
  {
    kind = "follow", label = "COME WITH ME",
    blurb = "an object walks to a cell",
    args = { { key = "who", kind = "object", label = "WHO" },
             { key = "x", kind = "number", label = "TO X" },
             { key = "y", kind = "number", label = "TO Y" } },
    lower = function(b)
      return { { "move_npc_to", b.who or 1, tonumber(b.x) or 0,
                 tonumber(b.y) or 0 } }
    end,
  },
  {
    kind = "set_flag", label = "SET FLAG", blurb = "mark something done",
    args = { { key = "flag", kind = "flag", label = "FLAG" } },
    lower = function(b)
      if not b.flag or b.flag == "" then return {} end
      return { { "set_flag", b.flag } }
    end,
  },
  {
    kind = "clear_flag", label = "CLEAR FLAG", blurb = "mark it undone again",
    args = { { key = "flag", kind = "flag", label = "FLAG" } },
    lower = function(b)
      if not b.flag or b.flag == "" then return {} end
      return { { "clear_flag", b.flag } }
    end,
  },
  {
    kind = "hide", label = "REMOVE AN NPC",
    blurb = "take an object off the map",
    args = { { key = "who", kind = "objectName", label = "WHO" } },
    lower = function(b, ctx)
      if not b.who or b.who == "" then return {} end
      return { { "hide_object", ctx.mapId, b.who },
               { "reload_map_objects" } }
    end,
  },
  {
    kind = "show", label = "PUT AN NPC BACK", blurb = "the other way round",
    args = { { key = "who", kind = "objectName", label = "WHO" } },
    lower = function(b, ctx)
      if not b.who or b.who == "" then return {} end
      return { { "show_object", ctx.mapId, b.who },
               { "reload_map_objects" } }
    end,
  },
  {
    kind = "give", label = "GIVE AN ITEM", blurb = "and say so",
    args = { { key = "item", kind = "item", label = "ITEM" },
             { key = "count", kind = "number", label = "HOW MANY" },
             { key = "text", kind = "text", label = "TEXT",
               placeholder = "got it!" } },
    lower = function(b)
      if not b.item or b.item == "" then return {} end
      return { { "give_item", b.item, tonumber(b.count) or 1,
                 (b.text ~= "" and b.text) or nil } }
    end,
  },
  {
    kind = "battle", label = "WILD BATTLE",
    blurb = "fight it where it stands - Lugia, Ho-Oh, Snorlax, the Lapras",
    -- THE STATIONARY LEGENDARY, and the engine already has the whole of it.
    --
    -- `Commands.static_battle` is what Lugia, Ho-Oh, the Snorlax and the
    -- Union Cave Lapras run: a wild battle against one specific species at
    -- one specific level, and then -- on anything that is not a loss -- it
    -- sets a flag and takes the object off the map. That last part is why it
    -- is not just `start_battle`: a legendary you beat and then walk back
    -- into is not a legendary, and doing the removal by hand means an author
    -- who forgets it has made exactly that.
    --
    -- The flag is what makes it stay gone across a save, so it is offered
    -- from the registry like every other. Leave it empty and the object
    -- comes back on the next map load, which is the Sudowoodo behaviour --
    -- also a real thing somebody might want.
    args = { { key = "species", kind = "species", label = "SPECIES" },
             { key = "level", kind = "number", label = "LEVEL" },
             { key = "flag", kind = "flag", label = "BEATEN FLAG" } },
    lower = function(b)
      if not b.species or b.species == "" then return {} end
      return { { "static_battle", b.species,
                 math.max(1, math.min(100, tonumber(b.level) or 40)),
                 (b.flag ~= "" and b.flag) or nil } }
    end,
  },
  {
    kind = "trainer", label = "TRAINER BATTLE",
    blurb = "a person who fights you when you talk to them",
    args = { { key = "class", kind = "line", label = "CLASS",
               placeholder = "OPP_YOUNGSTER" },
             { key = "party", kind = "number", label = "WHICH" },
             { key = "flag", kind = "flag", label = "BEATEN FLAG" } },
    lower = function(b)
      if not b.class or b.class == "" then return {} end
      local rows = { { "start_battle", "trainer", b.class,
                       tonumber(b.party) or 1 } }
      if b.flag and b.flag ~= "" then
        rows[#rows + 1] = { "set_flag", b.flag }
      end
      return rows
    end,
  },
  {
    kind = "sound", label = "PLAY A SOUND", blurb = "a jingle or an effect",
    args = { { key = "sound", kind = "line", label = "SOUND",
               placeholder = "SFX_..." } },
    lower = function(b)
      if not b.sound or b.sound == "" then return {} end
      return { { "play_sound", b.sound } }
    end,
  },
  {
    kind = "wait", label = "WAIT", blurb = "a pause, in frames",
    args = { { key = "frames", kind = "number", label = "FRAMES" } },
    lower = function(b)
      return { { "wait", math.max(1, tonumber(b.frames) or 30) } }
    end,
  },
  {
    kind = "warp", label = "SEND THEM SOMEWHERE",
    blurb = "move the player to another map",
    args = { { key = "map", kind = "map", label = "MAP" },
             { key = "x", kind = "number", label = "X" },
             { key = "y", kind = "number", label = "Y" } },
    lower = function(b)
      if not b.map or b.map == "" then return {} end
      return { { "warp", b.map, tonumber(b.x) or 0, tonumber(b.y) or 0 } }
    end,
  },
  {
    kind = "block_art", label = "CHANGE THE GROUND",
    blurb = "swap a block -- an opened door, a moved boulder",
    args = { { key = "bx", kind = "number", label = "BLOCK X" },
             { key = "by", kind = "number", label = "BLOCK Y" },
             { key = "block", kind = "number", label = "BLOCK ID" } },
    lower = function(b)
      return { { "replace_block", tonumber(b.bx) or 0, tonumber(b.by) or 0,
                 tonumber(b.block) or 0 } }
    end,
  },
}

function MapEvents.beatFor(kind)
  for _, b in ipairs(MapEvents.BEATS) do
    if b.kind == kind then return b end
  end
  return nil
end

-- A PATH IS TYPED THE WAY IT IS READ. "up up left" and "uul" are the same
-- thing and both are quicker than four dropdowns; the engine wants a list of
-- direction names, so this is where the one becomes the other. Unknown
-- characters are skipped rather than refused -- a stray comma or space in the
-- middle of a path is not worth an error message.
MapEvents.DIRS = { u = "up", d = "down", l = "left", r = "right" }

function MapEvents.parsePath(text)
  local out = {}
  for word in tostring(text or ""):lower():gmatch("%a+") do
    if MapEvents.DIRS[word] then
      out[#out + 1] = MapEvents.DIRS[word]
    elseif word == "up" or word == "down" or word == "left"
        or word == "right" then
      out[#out + 1] = word
    else
      for ch in word:gmatch(".") do
        if MapEvents.DIRS[ch] then out[#out + 1] = MapEvents.DIRS[ch] end
      end
    end
  end
  return out
end

function MapEvents.pathText(dirs)
  local out = {}
  for _, d in ipairs(dirs or {}) do out[#out + 1] = d end
  return table.concat(out, " ")
end

-- ---------------------------------------------------------------------------
-- lowering an event to rows
-- ---------------------------------------------------------------------------

-- THE SHAPE OF EVERY LOWERED EVENT, and it is the same shape every time:
--
--   check_flag <required>          -- one per condition
--   jump_if_false  ev_end
--   ...
--   check_flag <own flag>          -- only when `once`
--   jump_if_true   ev_end
--   <the beats>
--   set_flag <own flag>            -- only when `once` or a flag is named
--   label ev_end
--
-- ONE EXIT LABEL, not a jump per condition to a label per condition: a script
-- with four ways out is four things to get right, and every condition here
-- means the same thing -- do not run.
--
-- THE `once` GATE IS THE EVENT'S OWN FLAG. An event tile with no memory fires
-- every time the player steps on it, which for "the rival stops you at the
-- gate" is the rival stopping you forever. So `once` is on by default for a
-- step event and the flag is the record of it having happened -- the same
-- mechanism the author uses for everything else, rather than a second one.
function MapEvents.lower(ev, mapId)
  if type(ev) ~= "table" then return {}, "no event" end
  local rows = {}
  local endLabel = "ev_end"
  local ctx = { mapId = mapId or ev.mapId, endLabel = endLabel }

  for _, cond in ipairs(ev.requires or {}) do
    if cond.flag and cond.flag ~= "" then
      rows[#rows + 1] = { "check_flag", cond.flag }
      -- `state == false` means "only when it is NOT set", which is how a
      -- blocking NPC disappears: the block event requires the door flag to be
      -- unset, and setting it is what turns the event off.
      rows[#rows + 1] = { (cond.state == false) and "jump_if_true"
                          or "jump_if_false", endLabel }
    end
  end

  local ownFlag = ev.flag
  if ev.once and ownFlag and ownFlag ~= "" then
    rows[#rows + 1] = { "check_flag", ownFlag }
    rows[#rows + 1] = { "jump_if_true", endLabel }
  end

  for _, beat in ipairs(ev.beats or {}) do
    local spec = MapEvents.beatFor(beat.kind)
    if spec and spec.lower then
      local ok, out = pcall(spec.lower, beat, ctx)
      if ok and type(out) == "table" then
        for _, row in ipairs(out) do rows[#rows + 1] = row end
      end
    end
  end

  if ownFlag and ownFlag ~= "" then
    rows[#rows + 1] = { "set_flag", ownFlag }
  end
  rows[#rows + 1] = { "label", endLabel }
  return rows
end

-- What the engine's OWN validator says about the rows this produced.
--
-- Not a second opinion: `ScriptRunner.validate` is what the game runs against,
-- and an editor that passed a script the game refuses is worse than one that
-- does not check at all, because it moves the discovery to the one moment it
-- cannot be fixed.
function MapEvents.validate(ev, mapId)
  local rows = MapEvents.lower(ev, mapId)
  local ok, Runner = pcall(require, "src.script.ScriptRunner")
  if not (ok and type(Runner) == "table" and Runner.validate) then
    return true, nil, rows
  end
  local okV, problems = pcall(Runner.validate, rows)
  if not okV then return true, nil, rows end
  if type(problems) == "table" and #problems > 0 then
    return false, problems, rows
  end
  return true, nil, rows
end

-- ---------------------------------------------------------------------------
-- the events of a map
-- ---------------------------------------------------------------------------

function MapEvents.list(S, mapId)
  return MapEdits.events(store(S), MapEvents.gameOf(S), mapId or S.mapId)
end

function MapEvents.get(S, mapId, id)
  for _, ev in ipairs(MapEvents.list(S, mapId)) do
    if ev.id == id then return ev end
  end
  return nil
end

-- A new event, at a cell or on an object.
function MapEvents.create(S, spec)
  spec = spec or {}
  local mapId = spec.mapId or S.mapId
  if not mapId then return nil, "no map open" end
  local ev = {
    id = MapEdits.newEventId(store(S), MapEvents.gameOf(S), mapId),
    name = spec.name or "New event",
    trigger = spec.trigger or "step",
    x = spec.x, y = spec.y,
    object = spec.object,
    -- ON BY DEFAULT FOR A STEP EVENT: see the note above `lower`. A talk event
    -- repeating is ordinary -- you can talk to somebody twice -- so it is off
    -- there.
    once = (spec.once ~= nil) and spec.once or (spec.trigger ~= "talk"),
    flag = spec.flag,
    requires = {},
    beats = {},
  }
  MapEvents.save(S, mapId, ev)
  return ev
end

function MapEvents.save(S, mapId, ev)
  MapEdits.setEvent(store(S), MapEvents.gameOf(S), mapId or S.mapId, ev.id, ev)
  MapEvents.publish(S, mapId or S.mapId)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return true
end

function MapEvents.delete(S, mapId, id)
  MapEdits.setEvent(store(S), MapEvents.gameOf(S), mapId or S.mapId, id, nil)
  MapEvents.publish(S, mapId or S.mapId)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return true
end

-- LAY THE LOWERED EVENTS ONTO THE LIVE DEF, so the running game has them on
-- the next step rather than after a reload.
--
-- `def.events` is what the step handler reads; a "talk" event goes onto its
-- object's `script` instead, because that is the field the talk path already
-- reads and adding a second one would mean two places that can disagree about
-- what an NPC says.
function MapEvents.publish(S, mapId)
  mapId = mapId or S.mapId
  local def = S.data and S.data.maps and S.data.maps[mapId or ""]
  if not def then return false end
  local steps = {}
  for _, ev in ipairs(MapEvents.list(S, mapId)) do
    if ev.trigger == "talk" and ev.object then
      for _, obj in ipairs(def.objects or {}) do
        if obj.index == ev.object then
          obj.script = MapEvents.lower(ev, mapId)
        end
      end
    elseif ev.x and ev.y then
      steps[#steps + 1] = {
        x = ev.x, y = ev.y, id = ev.id, name = ev.name,
        -- CARRIED ONTO THE DEF, because the engine cannot ask the editor.
        --
        -- An ordinary authored event runs AFTER the cartridge's own hooks --
        -- they own their squares, and an authored trigger that could eat one
        -- would make a map the player walks into and cannot leave. `replaces`
        -- is the author saying, per event, that this one is meant to stand in
        -- for the scene already on that square. Opt-in per event, so the
        -- default ordering is unchanged.
        replaces = ev.replaces or nil,
        script = MapEvents.lower(ev, mapId),
      }
    end
  end
  def.events = (#steps > 0) and steps or nil
  pcall(function() require("src.world.MapLoader").evict(mapId) end)
  return true
end

-- TAKE OVER one of the cartridge's own events.
--
-- WHY THIS IS NOT "EDIT". A cartridge event is ROM bytecode reached through a
-- label; there is no way back from that to a list of beats, so a panel that
-- offered to edit one would be offering something that cannot work. What CAN
-- be done is to stand in front of it: an authored event at the same trigger,
-- marked `replaces`, which the engine runs instead.
--
-- The two triggers get there by different roads, and only one needs the flag:
--
--   talk   `publish` already writes the authored script onto the object's own
--          `script` field, which is the field the talk path reads. The
--          cartridge's dialogue is replaced by construction.
--   step   the ported hooks run first and own the square, so nothing short of
--          an explicit opt-in should displace them. That is what `replaces`
--          is, and it is why it is per event rather than a mode.
--
-- SEEDED WITH WHAT IS KNOWN, and nothing invented: the trigger, the position
-- or object, and the flag the cartridge event was gated on where it had one.
-- The beats start empty, because the original's are not readable and a made-up
-- approximation of them would be worse than a blank page -- the author would
-- be editing a guess while believing it was the scene.
function MapEvents.adopt(S, mapId, cart)
  if type(cart) ~= "table" then return nil, "nothing to take over" end
  mapId = mapId or S.mapId
  if not mapId then return nil, "no map open" end

  -- ALREADY TAKEN OVER? Answer with the existing one rather than minting a
  -- second event on the same trigger: two authored events on one square is a
  -- race the author cannot see and cannot resolve.
  for _, ev in ipairs(MapEvents.list(S, mapId)) do
    if cart.kind == "coord" and ev.x == cart.x and ev.y == cart.y then
      return ev, "already taken over"
    end
    if cart.kind == "object" and ev.trigger == "talk"
       and ev.object == cart.object then
      return ev, "already taken over"
    end
  end

  local spec
  if cart.kind == "coord" then
    spec = { mapId = mapId, trigger = "step", x = cart.x, y = cart.y,
             name = string.format("Step trigger %d,%d", cart.x or 0, cart.y or 0) }
  else
    spec = { mapId = mapId, trigger = "talk", object = cart.object,
             name = tostring(cart.name or "Object") }
  end
  spec.flag = (cart.flag ~= "" and cart.flag) or nil

  local ev, why = MapEvents.create(S, spec)
  if not ev then return nil, why end
  -- Only a STEP event needs it; see above.
  if cart.kind == "coord" then
    ev.replaces = true
    MapEvents.save(S, mapId, ev)
  end
  return ev
end

-- WHAT A FLAG ACTUALLY DOES.
--
-- THERE ARE NO RULES ON A FLAG ITSELF. `setevent`/`clearevent` lower to
-- `set_flag`/`clear_flag` (Gen2ScriptVM), and those write a bit and return --
-- see Commands.set_flag. The cartridge has no on-set hook, no trigger table,
-- nothing that runs because a flag changed. A flag is a bit in the save.
--
-- Everything a flag "does" is done by its READERS, and there are four kinds:
--
--   object   an object_event carrying `eventFlag` is HIDDEN while the flag is
--            set (OverworldController.objectVisible: `visible = not
--            flags[eventFlag]`). This is the inversion that catches people --
--            setting the flag REMOVES the NPC, it does not spawn them.
--   door     a door row with `event` (or every flag in `events`) swaps its
--            block when the flag is set: this is "unlock the door".
--   event    an authored event that SETS it, CLEARS it, or waits on it.
--   trainer  a trainer header's `event`, marked when that trainer is beaten.
--
-- So the useful question in an editor is not "what rule does this flag carry"
-- -- it carries none -- but "who is watching it", which is what this answers.
-- Scoped to the open map, because that is the map whose objects and doors the
-- reader can actually see and change.
function MapEvents.flagUses(S, flag, mapId)
  local out = { objects = {}, doors = {}, events = {}, trainers = {} }
  if not (S and flag and flag ~= "") then return out end
  mapId = mapId or S.mapId
  local def = S.data and S.data.maps and S.data.maps[mapId or ""]
  if not def then return out end

  for _, obj in ipairs(def.objects or {}) do
    if obj.eventFlag == flag then
      out.objects[#out.objects + 1] = obj
    end
  end

  for _, door in ipairs(def.doors or {}) do
    if door.event == flag then
      out.doors[#out.doors + 1] = door
    elseif type(door.events) == "table" then
      for _, e in ipairs(door.events) do
        if e == flag then out.doors[#out.doors + 1] = door break end
      end
    end
  end

  for _, ev in ipairs(MapEvents.list(S, mapId)) do
    local how = nil
    if ev.flag == flag then how = "sets" end
    for _, cond in ipairs(ev.requires or {}) do
      if cond.flag == flag then
        how = how and (how .. " and waits on") or "waits on"
      end
    end
    for _, beat in ipairs(ev.beats or {}) do
      if beat.flag == flag then
        if beat.kind == "clear_flag" then
          how = how and (how .. " and clears") or "clears"
        elseif beat.kind == "set_flag" then
          how = how and (how .. " and sets") or "sets"
        end
      end
    end
    if how then out.events[#out.events + 1] = { event = ev, how = how } end
  end

  -- Trainer headers are keyed by the extractor's map LABEL, not the editor's
  -- map id -- see panels/Objects.lua's cartridgeSight for the same trap.
  local label = def.label
  local headers = label and S.data.trainer_headers
    and S.data.trainer_headers[label]
  for index, header in pairs(headers or {}) do
    if header.event == flag then
      out.trainers[#out.trainers + 1] = { index = index, header = header }
    end
  end
  return out
end

-- EVERY FLAG'S WATCHERS, EVERYWHERE, IN ONE PASS.
--
-- WHY THIS REPLACED THE PER-FLAG SCAN. `knownFlags` gathers its list by
-- walking EVERY map in the game, and `flagUses` answered for the OPEN one --
-- so a list of six hundred world-wide flags was being answered map-locally,
-- and almost every row said "nothing watches this yet". That statement was
-- true of the open map and false of the game, which is the worst kind of
-- wrong: it reads as a finished answer.
--
-- Asking `flagUses` per flag would have been maps x flags, which is minutes.
-- Bucketing by flag in ONE walk is maps, which is the same walk `knownFlags`
-- already does on every draw -- so the complete answer costs less than the
-- partial one did.
--
-- Cached against the edit stamp: the store changes when anything is edited,
-- and the index is derived from the store and the map table together.
function MapEvents.flagIndex(S)
  if not (S and S.data and type(S.data.maps) == "table") then return {} end
  local stamp = tostring(S.mapEditsStamp or 0)
  if S._flagIndexAt == stamp and S._flagIndex then return S._flagIndex end

  local index = {}
  local function bucket(flag, mapId)
    if type(flag) ~= "string" or flag == "" then return nil end
    local row = index[flag]
    if not row then
      row = { total = 0, maps = {}, byMap = {} }
      index[flag] = row
    end
    local m = row.byMap[mapId]
    if not m then
      m = { id = mapId, objects = {}, doors = {}, events = {}, trainers = {},
            n = 0 }
      row.byMap[mapId] = m
      row.maps[#row.maps + 1] = m
    end
    return row, m
  end

  for mapId, def in pairs(S.data.maps) do
    for _, obj in ipairs(def.objects or {}) do
      local row, m = bucket(obj.eventFlag, mapId)
      if row then
        m.objects[#m.objects + 1] = obj
        m.n = m.n + 1
        row.total = row.total + 1
      end
    end
    for _, door in ipairs(def.doors or {}) do
      local flags = door.events
      if type(flags) ~= "table" then flags = door.event and { door.event } or {} end
      for _, f in ipairs(flags) do
        local row, m = bucket(f, mapId)
        if row then
          m.doors[#m.doors + 1] = door
          m.n = m.n + 1
          row.total = row.total + 1
        end
      end
    end
    -- Trainer headers are keyed by the extractor's map LABEL, not the map id.
    local headers = def.label and S.data.trainer_headers
      and S.data.trainer_headers[def.label]
    for objIndex, header in pairs(headers or {}) do
      local row, m = bucket(header.event, mapId)
      if row then
        m.trainers[#m.trainers + 1] = { index = objIndex, header = header }
        m.n = m.n + 1
        row.total = row.total + 1
      end
    end
    -- ...and the editor's own events for this map.
    for _, ev in ipairs(MapEvents.list(S, mapId)) do
      local hows = {}
      if ev.flag then hows[ev.flag] = "sets" end
      for _, cond in ipairs(ev.requires or {}) do
        if cond.flag then
          hows[cond.flag] = hows[cond.flag]
            and (hows[cond.flag] .. " and waits on") or "waits on"
        end
      end
      for _, beat in ipairs(ev.beats or {}) do
        if beat.flag and (beat.kind == "set_flag" or beat.kind == "clear_flag")
        then
          local verb = (beat.kind == "clear_flag") and "clears" or "sets"
          hows[beat.flag] = hows[beat.flag]
            and (hows[beat.flag] .. " and " .. verb) or verb
        end
      end
      for flag, how in pairs(hows) do
        local row, m = bucket(flag, mapId)
        if row then
          m.events[#m.events + 1] = { event = ev, how = how }
          m.n = m.n + 1
          row.total = row.total + 1
        end
      end
    end
  end

  for _, row in pairs(index) do
    table.sort(row.maps, function(a, b) return a.id < b.id end)
  end
  S._flagIndex, S._flagIndexAt = index, stamp
  return index
end

-- One flag's row out of the index, always a table so callers need no guard.
function MapEvents.flagWatchers(S, flag)
  local row = MapEvents.flagIndex(S)[flag]
  return row or { total = 0, maps = {}, byMap = {} }
end

-- A one-line summary of the above, for a list row.
function MapEvents.flagSummary(uses)
  local bits = {}
  local function add(n, one, many)
    if n > 0 then bits[#bits + 1] = n .. " " .. (n == 1 and one or many) end
  end
  add(#uses.objects, "object", "objects")
  add(#uses.doors, "door", "doors")
  add(#uses.events, "event", "events")
  add(#uses.trainers, "trainer", "trainers")
  if #bits == 0 then return "nothing watches this yet" end
  return table.concat(bits, ", ")
end

-- The event on a cell, for the overlay and for the picker.
function MapEvents.atCell(S, cx, cy, mapId)
  for _, ev in ipairs(MapEvents.list(S, mapId)) do
    if ev.x == cx and ev.y == cy then return ev end
  end
  return nil
end

return MapEvents
