-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- The script attached to a map object: a list of `{ "command", args... }` rows.
--
-- That IS the format -- `ScriptRunner` walks exactly this, with `{"label", name}`
-- rows as jump targets and `jump` / `jump_if_true` / `jump_if_false` naming a
-- label. So the editor edits rows directly rather than inventing a language
-- that would then need compiling: there is nothing between what is on screen
-- and what runs.
--
-- IT VALIDATES WITH THE ENGINE'S OWN VALIDATOR. `ScriptRunner.validate` already
-- reports unknown commands, duplicate labels, malformed rows and jumps to
-- missing labels. Writing a second opinion here would drift from the first, and
-- the drift would show up as a script the editor called fine and the game
-- refused -- so this calls that one and prints what it says.
--
-- A row's arguments are typed on the way IN, not stored as text: `"5"` and `5`
-- are different things to a command handler, and a script that only works
-- because the handler happened to be tolerant is a trap for the next command
-- that is not. Numbers become numbers, `true`/`false` become booleans, anything
-- else stays a string.

local MapEdits = require("tools.map-editor.MapEdits")

local Scripts = {}

local function store(S)
  if not S.mapEdits then S.mapEdits = (MapEdits.load()) end
  return S.mapEdits
end

local function game(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring(S.version or v or "unknown")
end

-- Every command the engine can actually run. Offering a name nothing
-- implements would produce a script that saves, loads, validates as text and
-- then does nothing at the one moment it matters.
local function commandNames(S)
  if S.scrCommands then return S.scrCommands end
  local out = {}
  local ok, Commands = pcall(require, "src.script.Gen2Commands")
  if ok and type(Commands) == "table" then
    for name in pairs(Commands) do
      if type(name) == "string" and type(Commands[name]) == "function" then
        out[#out + 1] = name
      end
    end
  end
  table.sort(out)
  -- `label` is not a command -- ScriptRunner handles it itself -- but it is a
  -- row the player needs to be able to add, so it is offered alongside them.
  table.insert(out, 1, "label")
  S.scrCommands = out
  return out
end

local function typed(text)
  if text == "true" then return true end
  if text == "false" then return false end
  local n = tonumber(text)
  if n ~= nil then return n end
  return text
end

local function argText(v)
  if v == nil then return "" end
  return tostring(v)
end

local function rowText(row)
  local parts = { tostring(row[1] or "?") }
  for i = 2, #row do parts[#parts + 1] = argText(row[i]) end
  return table.concat(parts, "  ")
end

-- The object the OBJECTS tab has selected. Sharing that selection rather than
-- having a second list is what makes the two tabs feel like one editor.
local function selectedObject(S)
  local def = S.data and S.data.maps and S.data.maps[S.mapId]
  local objs = (def and def.objects) or {}
  return objs[S.objSelected or 0]
end

local function writeScript(S, obj, rows)
  obj.script = rows
  local st, g = store(S), game(S)
  if obj.added then
    local m = MapEdits.bucket(st, g, S.mapId, true)
    local slot = m.added and m.added[obj.editorSlot]
    if slot then slot.script = rows end
  else
    MapEdits.setObject(st, g, S.mapId, obj.index, { script = rows })
  end
  S.mapEditsDirty = true
end

function Scripts.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad, gap = 16 * s, 20 * s

  if not S.mapId then
    Kit.emptyBox(x, y, w, h, "Pick a map on the MAPS tab first.")
    return
  end
  local obj = selectedObject(S)
  if not obj then
    Kit.emptyBox(x, y, w, h,
      "Select an object on the OBJECTS tab, then write its script here.")
    return
  end

  local rows = obj.script
  if type(rows) ~= "table" then rows = {} end

  local sideW = math.max(220 * s, math.min(300 * s, w * 0.3))
  local listX, listW = x, w - sideW - gap
  local sideX = x + listW + gap

  -- --------------------------------------------------------------- rows
  Kit.card(listX, y, listW, h)
  Kit.caption(listX + pad, y + pad,
    string.format("SCRIPT - object #%s", tostring(obj.index or "?")))
  local top = y + pad + Kit.textHeight("caption") + 10 * s
  local rowH = 30 * s
  local addH = 32 * s
  local listBottom = y + h - pad - addH - 8 * s
  local perPage = math.max(1, math.floor((listBottom - top) / rowH))
  S.scrScroll = math.max(0, math.min(S.scrScroll or 0,
                                     math.max(0, #rows - perPage)))

  if #rows == 0 then
    Kit.text("body", "No script. Plain dialogue on the OBJECTS tab is",
             listX + pad, top)
    Kit.text("body", "enough for most NPCs; this is for the rest.",
             listX + pad, top + 18 * s)
  end

  for r = 1, math.min(perPage, #rows - S.scrScroll) do
    local i = r + S.scrScroll
    local ry = top + (r - 1) * rowH
    local selected = S.scrSelected == i
    if Kit.press(listX + pad, ry, listW - 2 * pad, rowH - 4 * s) then
      S.scrSelected = i
    end
    Kit.row(listX + pad, ry, listW - 2 * pad, rowH - 4 * s, selected)
    Kit.text("small", string.format("%2d", i), listX + pad + 6 * s, ry + 7 * s)
    Kit.text("body", rowText(rows[i]), listX + pad + 34 * s, ry + 6 * s)
  end

  local third = (listW - 2 * pad - 16 * s) / 3
  local ay = y + h - pad - addH
  if Kit.button(listX + pad, ay, third, addH, "+ ROW") then
    rows[#rows + 1] = { "label", "step" .. tostring(#rows + 1) }
    writeScript(S, obj, rows)
    S.scrSelected = #rows
  end
  if S.scrSelected and rows[S.scrSelected] then
    if Kit.button(listX + pad + third + 8 * s, ay, third, addH, "MOVE UP")
       and S.scrSelected > 1 then
      rows[S.scrSelected], rows[S.scrSelected - 1] =
        rows[S.scrSelected - 1], rows[S.scrSelected]
      S.scrSelected = S.scrSelected - 1
      writeScript(S, obj, rows)
    end
    if Kit.button(listX + pad + 2 * (third + 8 * s), ay, third, addH, "DELETE") then
      table.remove(rows, S.scrSelected)
      S.scrSelected = rows[S.scrSelected] and S.scrSelected or nil
      writeScript(S, obj, rows)
    end
  end

  -- ------------------------------------------------------------ the row
  Kit.card(sideX, y, sideW, h)
  local row = rows[S.scrSelected or 0]
  if not row then
    Kit.emptyBox(sideX + pad, y + pad, sideW - 2 * pad, h - 2 * pad,
                 "Select a row.")
    return
  end

  local fy = y + pad
  Kit.caption(sideX + pad, fy, "ROW " .. tostring(S.scrSelected))
  fy = fy + Kit.textHeight("caption") + 10 * s
  local fieldH = 30 * s
  local inner = sideW - 2 * pad

  if Kit.button(sideX + pad, fy, inner, fieldH, tostring(row[1] or "?")) then
    S.scrCmdOpen = not S.scrCmdOpen
    S.scrCmdQuery = ""
  end
  fy = fy + fieldH + 6 * s
  if S.scrCmdOpen then
    S.scrCmdQuery = Kit.textfield("scr-cmd", sideX + pad, fy, inner, fieldH,
                                  S.scrCmdQuery or "", "search commands...")
    fy = fy + fieldH + 4 * s
    local shown = 0
    for _, name in ipairs(commandNames(S)) do
      if (S.scrCmdQuery or "") == ""
         or name:lower():find((S.scrCmdQuery or ""):lower(), 1, true) then
        shown = shown + 1
        if shown <= 7 then
          if Kit.button(sideX + pad, fy, inner, fieldH - 4 * s, name) then
            row[1] = name
            writeScript(S, obj, rows)
            S.scrCmdOpen = false
          end
          fy = fy + fieldH - 2 * s
        end
      end
    end
    if shown == 0 then
      Kit.text("small", "no command matches", sideX + pad, fy)
      fy = fy + 16 * s
    elseif shown > 7 then
      Kit.text("small", string.format("%d more - keep typing", shown - 7),
               sideX + pad, fy)
      fy = fy + 16 * s
    end
  end

  -- Arguments. Four slots is enough for every lowered command in the engine
  -- and keeps the panel a fixed height; a row needing more is a sign the
  -- command wants a table argument rather than a fifth field.
  for a = 2, 5 do
    Kit.text("small", "arg " .. (a - 1), sideX + pad, fy + 8 * s)
    local was = argText(row[a])
    local got = Kit.textfield("scr-arg" .. a, sideX + pad + 52 * s, fy,
                              inner - 52 * s, fieldH, was, "")
    if got ~= was then
      row[a] = (got == "") and nil or typed(got)
      writeScript(S, obj, rows)
    end
    fy = fy + fieldH + 6 * s
  end

  local actH = 34 * s
  local ay2 = y + h - pad - actH
  local halfW = (inner - 8 * s) / 2
  if Kit.button(sideX + pad, ay2, halfW, actH, "VALIDATE") then
    local ok, problems = pcall(function()
      return require("src.script.ScriptRunner").validate(rows)
    end)
    problems = (ok and problems) or {}
    S.scrProblems = problems
    S.scrNotice = (#problems == 0) and "no problems"
      or string.format("%d problem(s)", #problems)
  end
  if Kit.button(sideX + pad + halfW + 8 * s, ay2, halfW, actH, "SAVE") then
    local ok, err = MapEdits.save(store(S))
    S.mapEditsDirty = not ok or nil
    S.scrNotice = ok and "saved" or ("save failed: " .. tostring(err))
  end

  -- The validator's own words, not a summary of them: it names the row and the
  -- reason, and paraphrasing would lose both.
  local py = ay2 - 18 * s
  for i = math.min(#(S.scrProblems or {}), 4), 1, -1 do
    Kit.text("small", tostring(S.scrProblems[i]), sideX + pad, py)
    py = py - 15 * s
  end
  if S.scrNotice then Kit.text("small", S.scrNotice, sideX + pad, py) end
end

function Scripts.wheelmoved(S, dy)
  S.scrScroll = math.max(0, (S.scrScroll or 0) - (dy or 0))
end

function Scripts.keypressed(S, key)
  if key == "delete" and S.scrSelected then
    local obj = selectedObject(S)
    if obj and type(obj.script) == "table" then
      table.remove(obj.script, S.scrSelected)
      writeScript(S, obj, obj.script)
      S.scrSelected = nil
    end
  end
end

return Scripts
