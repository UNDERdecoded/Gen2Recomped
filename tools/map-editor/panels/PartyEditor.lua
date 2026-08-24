-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- "What does this trainer fight with?"
--
-- WHY THIS EXISTS. Making an NPC a trainer used to mean picking a
-- `trainerClass` and a `trainerParty` -- an INDEX into the parties the
-- cartridge already shipped for that class. So every trainer the editor could
-- make was somebody else's six Pokemon, and there was no way to say "this one
-- has a level 12 Geodude and nothing else".
--
-- WHAT IT STORES is the engine's own party shape:
--
--     { { species = "SPECIES_074", level = 12, moves = { "MOVE_TACKLE" } }, ... }
--
-- which is what `BattleState.newTrainer` consumes, slot for slot. Storing the
-- engine's shape rather than a private editor one is deliberate: a translation
-- step between the two would be a second place for a team to be subtly wrong,
-- and the bug would show up in a battle rather than here.
--
-- THREE PANES, because the work has three parts and they are not sequential:
-- pick a species (left), see the team (middle), tune the one you clicked
-- (right). A wizard would make adding a sixth Pokemon a five-step trip.
--
-- OVER THE WHOLE WINDOW, painted after the frame, for the reason TilesetPrompt
-- is: Kit has no z-order, so "on top" and "drawn last" are the same sentence.

local okKit, KitModule = pcall(require, "Kit")
if not okKit then KitModule = nil end

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, green = { 120, 210, 130 },
  caption = { 160, 175, 205 }, text = { 226, 232, 245 },
}

local PartyEditor = {}

PartyEditor.MAX = 6

-- The stats a slot may pin. Left unset, `newTrainer` computes them from the
-- species and level the way the cartridge does -- which is what an author
-- wants almost always, so every one of these is optional and blank by default.
PartyEditor.STATS = { "hp", "attack", "defense", "speed", "spatk", "spdef" }

local function clamp(v, lo, hi)
  v = tonumber(v) or lo
  if v < lo then return lo end
  if v > hi then return hi end
  return math.floor(v)
end

-- ---------------------------------------------------------------------------
-- raising it
-- ---------------------------------------------------------------------------

function PartyEditor.open(S, obj)
  if not (S and obj) then return false end
  -- EDITED ON A COPY. A team half-built is not a team, and a reader who
  -- changes their mind should get the one they had -- so the working copy is
  -- committed on SAVE and dropped on cancel.
  -- SEEDED FROM THE CARTRIDGE WHEN THE AUTHOR HAS NOT BUILT ONE.
  --
  -- A trainer already in the game HAS a team -- six Pokemon with levels and
  -- movesets, sitting in `data.trainers[class].parties[index]` -- and opening
  -- this on them showed an empty box. So the only way to adjust one Pokemon on
  -- an existing trainer was to rebuild all six from memory, which is not
  -- editing, it is retyping.
  --
  -- Copied in rather than referenced: `data.trainers` is generated from the
  -- ROM and shared by every trainer of that class, so editing it in place
  -- would change every Youngster in Johto -- and be thrown away by the next
  -- import regardless.
  local source = obj.trainerTeam
  local fromCartridge = false
  if type(source) ~= "table" or #source == 0 then
    source = PartyEditor.cartridgeParty(S, obj)
    fromCartridge = source ~= nil
  end

  local team = {}
  for i, slot in ipairs(source or {}) do
    local copy = {}
    for k, v in pairs(slot) do
      if k == "moves" or k == "stats" or k == "dvs" then
        local t = {}
        for k2, v2 in pairs(v) do t[k2] = v2 end
        copy[k] = t
      else
        copy[k] = v
      end
    end
    team[i] = copy
  end
  S.partyAsk = { obj = obj, team = team, selected = team[1] and 1 or nil,
                 query = "", scroll = 0, fromCartridge = fromCartridge }
  return true
end

-- The party this object's trainer actually fights with in the cartridge, or
-- nil. Shaped exactly like the slots this editor stores, because it IS that
-- shape -- `BattleState.newTrainer` reads both through the same code.
function PartyEditor.cartridgeParty(S, obj)
  if not (S and S.data and obj and obj.trainerClass) then return nil end
  local row = S.data.trainers and S.data.trainers[obj.trainerClass]
  if type(row) ~= "table" or type(row.parties) ~= "table" then return nil end
  local party = row.parties[tonumber(obj.trainerParty) or 1]
  if type(party) ~= "table" or #party == 0 then return nil end
  return party
end

function PartyEditor.close(S)
  if S then
    S.partyAsk = nil
    if KitModule and KitModule.forgetModal then
      KitModule.forgetModal("party-edit")
    end
  end
end

function PartyEditor.commit(S, writeField)
  local ask = S and S.partyAsk
  if not ask then return false end
  -- An empty team is stored as ABSENT, not as an empty list: `engageTrainer`
  -- tests `#trainerTeam > 0` to decide whether the author meant to override
  -- the cartridge party, and an empty array would read as "yes, with nobody".
  -- AND EMPTY SUB-TABLES ARE PRUNED, for the same reason the team itself is.
  -- `newTrainer` branches on the PRESENCE of `moves` and `stats`, not on their
  -- contents: an empty moves table hands the battler a Pokemon with no attacks
  -- at all, and an empty stats table replaces a computed stat block with
  -- nothing. Absent is the value that means "work it out".
  for _, slot in ipairs(ask.team) do
    if type(slot.moves) == "table" and #slot.moves == 0 then slot.moves = nil end
    if type(slot.stats) == "table" and next(slot.stats) == nil then
      slot.stats = nil
    end
  end
  local value = (#ask.team > 0) and ask.team or nil
  writeField(S, ask.obj, "trainerTeam", value)
  return true
end

-- ---------------------------------------------------------------------------
-- drawing it
-- ---------------------------------------------------------------------------

local function speciesList(S, query)
  local all = (S.cat and S.cat.species) or {}
  if not query or query == "" then return all end
  local out = {}
  local q = query:lower()
  local Catalog = nil
  do local ok, C = pcall(require, "Catalog"); if ok then Catalog = C end end
  for _, id in ipairs(all) do
    local label = Catalog and Catalog.speciesLabel
      and Catalog.speciesLabel(S.data, id) or id
    if tostring(id):lower():find(q, 1, true)
       or tostring(label):lower():find(q, 1, true) then
      out[#out + 1] = id
    end
  end
  return out
end

local function speciesLabel(S, id)
  local ok, Catalog = pcall(require, "Catalog")
  if ok and Catalog.speciesLabel then
    local okL, label = pcall(Catalog.speciesLabel, S.data, id)
    if okL and label then return label end
  end
  return tostring(id)
end

function PartyEditor.draw(S, Kit, writeField)
  local ask = S and S.partyAsk
  if not ask then return false end

  local s = Kit.scale
  local winW, winH = love.graphics.getDimensions()
  local pad = 14 * s
  local pw = math.min(760 * s, winW - 40 * s)
  local ph = math.min(520 * s, winH - 40 * s)
  local x = math.floor((winW - pw) / 2)
  local y = math.floor((winH - ph) / 2)

  -- The guard runs BEFORE any widget of this dialog is drawn: `Kit.tapAway`
  -- swallows the click on the frame the dialog goes up, and it can only do
  -- that for widgets drawn after it.
  local tappedAway = Kit.tapAway("party-edit", x, y, pw, ph)

  love.graphics.setColor(0.03, 0.04, 0.11, 0.62)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", x, y, pw, ph, 10 * s, 10 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(x, y, pw, ph)

  Kit.caption(x + pad, y + pad, "TRAINER PARTY")
  local headY = y + pad + Kit.textHeight("caption") + 6 * s
  Kit.text("small", string.format("%s  -  %d of %d",
    tostring(ask.obj.trainerName or ask.obj.trainerClass or "this trainer"),
    #ask.team, PartyEditor.MAX), x + pad, headY, PAL.muted)

  -- WHOSE TEAM THIS IS, said before anything is changed.
  --
  -- A cartridge team shown in an editable box looks like a team the author
  -- already owns, and the difference matters: saving takes a copy and stops
  -- following the cartridge, so a later ROM re-import will not update it. That
  -- is the right behaviour -- it is their team now -- but it is not something
  -- to discover.
  if ask.fromCartridge then
    Kit.text("small",
      "loaded from the cartridge - saving takes a copy and this trainer "
      .. "stops following it", x + pad, headY + 15 * s, PAL.yellow)
  end
  local bodyY = headY + (ask.fromCartridge and 34 or 20) * s
  local bodyH = ph - (bodyY - y) - pad - 40 * s
  local sideW = 190 * s
  local editW = 230 * s
  local midX = x + pad + sideW + pad
  local midW = pw - 2 * pad - sideW - editW - 2 * pad

  -- ------------------------------------------------------- the species list
  Kit.text("small", "ADD A POKEMON", x + pad, bodyY, PAL.caption)
  local listY = bodyY + 16 * s
  ask.query = Kit.textfield("party-q", x + pad, listY, sideW, 26 * s,
                            ask.query or "", "search...")
  listY = listY + 32 * s
  local list = speciesList(S, ask.query)
  local rowH = 22 * s
  local perPage = math.max(1, math.floor((bodyY + bodyH - listY) / rowH))
  ask.scroll = math.max(0, math.min(ask.scroll or 0,
                                    math.max(0, #list - perPage)))
  Kit.pushClip(x + pad, listY, sideW, bodyY + bodyH - listY)
  for i = ask.scroll + 1, math.min(#list, ask.scroll + perPage) do
    local id = list[i]
    local ry = listY + (i - ask.scroll - 1) * rowH
    local full = #ask.team >= PartyEditor.MAX
    if Kit.button(x + pad, ry, sideW, rowH - 2 * s,
                  Kit.ellipsize("small", speciesLabel(S, id), sideW - 14 * s),
                  { font = "small", enabled = not full }) then
      -- LEVEL 5 AND NO MOVES: the engine fills the moveset from the species'
      -- own learnset when a slot names none, which is what the cartridge's own
      -- trainers do. Inventing four moves here would be inventing them.
      ask.team[#ask.team + 1] = { species = id, level = 5 }
      ask.selected = #ask.team
    end
  end
  Kit.popClip()
  if #list > perPage then
    ask.scroll = Kit.scroll(x + pad, listY, sideW, bodyY + bodyH - listY,
                            ask.scroll, #list, perPage) or ask.scroll
  end

  -- ------------------------------------------------------------- the team
  Kit.text("small", "THE TEAM", midX, bodyY, PAL.caption)
  local tileH = 44 * s
  local ty = bodyY + 16 * s
  for i = 1, PartyEditor.MAX do
    local slot = ask.team[i]
    local on = (ask.selected == i)
    local ry = ty + (i - 1) * (tileH + 6 * s)
    if slot then
      if Kit.press(midX, ry, midW - 28 * s, tileH) then ask.selected = i end
      Kit.row(midX, ry, midW - 28 * s, tileH, on)
      Kit.text("body", Kit.ellipsize("body", speciesLabel(S, slot.species),
                                     midW - 56 * s), midX + 8 * s, ry + 6 * s)
      local bits = { "Lv " .. tostring(slot.level or 5) }
      if slot.moves and #slot.moves > 0 then
        bits[#bits + 1] = #slot.moves .. " move"
          .. (#slot.moves == 1 and "" or "s")
      else
        bits[#bits + 1] = "learnset moves"
      end
      if slot.stats then bits[#bits + 1] = "pinned stats" end
      Kit.text("small", table.concat(bits, "  -  "), midX + 8 * s,
               ry + 24 * s, PAL.muted)
      if Kit.button(midX + midW - 24 * s, ry, 22 * s, tileH, "x",
                    { font = "small", radius = 5 * s }) then
        table.remove(ask.team, i)
        if ask.selected and ask.selected > #ask.team then
          ask.selected = #ask.team > 0 and #ask.team or nil
        end
        break
      end
    else
      -- The empty slots are DRAWN. Six tiles with two filled says "four more
      -- fit"; two tiles and nothing else says nothing at all.
      Kit.emptyBox(midX, ry, midW - 28 * s, tileH, "empty")
    end
  end

  -- --------------------------------------------------------- the one slot
  local ex = x + pw - pad - editW
  local slot = ask.selected and ask.team[ask.selected] or nil
  Kit.text("small", "THIS POKEMON", ex, bodyY, PAL.caption)
  local ey = bodyY + 16 * s
  if not slot then
    Kit.text("small", "pick one from the team", ex, ey, PAL.muted)
  else
    local fieldH = 26 * s
    local labelW = 70 * s

    Kit.text("small", "LEVEL", ex, ey + 6 * s, PAL.muted)
    if Kit.stepper(ex + labelW, ey, 26 * s, fieldH, "-") then
      slot.level = clamp((slot.level or 5) - 1, 1, 100)
    end
    Kit.textCenter("body", tostring(slot.level or 5), ex + labelW + 26 * s,
                   ey + 6 * s, 44 * s)
    if Kit.stepper(ex + labelW + 70 * s, ey, 26 * s, fieldH, "+") then
      slot.level = clamp((slot.level or 5) + 1, 1, 100)
    end
    ey = ey + fieldH + 10 * s

    -- MOVES: up to four, each picked from the move list rather than typed.
    -- A misspelled move id is not a move with a wrong name, it is a crash the
    -- moment the battle starts -- the same reasoning the item field follows.
    Kit.text("small", "MOVES", ex, ey, PAL.muted)
    ey = ey + 16 * s
    -- READ THROUGH A LOCAL, never `slot.moves = slot.moves or {}`.
    --
    -- That assignment leaves an EMPTY moves table on a slot the author never
    -- touched -- and an empty table is not the same as absent. `newTrainer`
    -- tests `if slot.moves then` and, finding one, hands the battler a set
    -- with nothing in it: a Pokemon that cannot attack. Absent means "fill it
    -- from the learnset", which is what the cartridge's own trainers do.
    local moves = slot.moves or {}
    for i = 1, 4 do
      local id = moves[i]
      if Kit.button(ex, ey, editW - 28 * s, fieldH - 2 * s,
                    Kit.ellipsize("small", id and tostring(id) or "(learnset)",
                                  editW - 44 * s), { font = "small" }) then
        S.partyMovePick = { slot = slot, index = i }
      end
      if id and Kit.button(ex + editW - 24 * s, ey, 22 * s, fieldH - 2 * s,
                           "x", { font = "small", radius = 5 * s }) then
        table.remove(moves, i)
        slot.moves = (#moves > 0) and moves or nil
        break
      end
      ey = ey + fieldH + 2 * s
    end
    ey = ey + 6 * s

    -- STATS: blank means "work it out", which is what an author wants nearly
    -- always. Pinning one is for the fight that has to go a particular way.
    Kit.text("small", "STATS  (blank = from level)", ex, ey, PAL.muted)
    ey = ey + 16 * s
    for _, key in ipairs(PartyEditor.STATS) do
      Kit.text("small", key:upper(), ex, ey + 5 * s, PAL.muted)
      local cur = slot.stats and slot.stats[key]
      local out = Kit.textfield("party-stat-" .. key, ex + labelW, ey,
                                editW - labelW - 4 * s, fieldH - 4 * s,
                                cur and tostring(cur) or "", "auto")
      if out ~= (cur and tostring(cur) or "") then
        local n = tonumber(out)
        slot.stats = slot.stats or {}
        if n then
          slot.stats[key] = clamp(n, 1, 999)
        else
          slot.stats[key] = nil
          if next(slot.stats) == nil then slot.stats = nil end
        end
      end
      ey = ey + fieldH
    end
  end

  -- ------------------------------------------------------------- answers
  local by = y + ph - pad - 32 * s
  local halfW = (pw - 2 * pad - 8 * s) / 2
  local result = nil
  if Kit.button(x + pad, by, halfW, 32 * s, "SAVE THIS TEAM",
                { font = "small", kind = "accent" }) then
    result = "save"
  end
  if Kit.button(x + pad + halfW + 8 * s, by, halfW, 32 * s, "CANCEL",
                { font = "small" }) then
    result = "cancel"
  end
  -- A tap outside is a cancel: it is the only answer that changes nothing.
  if not result and tappedAway then result = "cancel" end

  -- ------------------------------------------------------- the move picker
  --
  -- Drawn LAST and inside this modal rather than as a second one: it is a
  -- choice made about a slot in the team behind it, and a separate dialog
  -- stacked on a dialog is two tap-away guards to get right for one list.
  if S.partyMovePick then
    local mx = x + pad
    local my = bodyY
    local mw = pw - 2 * pad
    local mh = bodyH
    love.graphics.setColor(0.03, 0.04, 0.11, 0.92)
    love.graphics.rectangle("fill", mx, my, mw, mh, 8 * s, 8 * s)
    love.graphics.setColor(1, 1, 1, 1)
    Kit.card(mx, my, mw, mh)
    Kit.caption(mx + 10 * s, my + 8 * s, "PICK A MOVE")
    local qy = my + 8 * s + Kit.textHeight("caption") + 6 * s
    ask.moveQuery = Kit.textfield("party-move-q", mx + 10 * s, qy,
                                  mw - 20 * s, 26 * s, ask.moveQuery or "",
                                  "search moves...")
    local ly = qy + 32 * s
    local moves = {}
    do
      local all = (S.cat and S.cat.moves) or {}
      local q = (ask.moveQuery or ""):lower()
      for _, id in ipairs(all) do
        if q == "" or tostring(id):lower():find(q, 1, true) then
          moves[#moves + 1] = id
        end
      end
    end
    local mrowH = 22 * s
    local mper = math.max(1, math.floor((my + mh - ly - 34 * s) / mrowH))
    ask.moveScroll = math.max(0, math.min(ask.moveScroll or 0,
                                          math.max(0, #moves - mper)))
    Kit.pushClip(mx, ly, mw, my + mh - ly - 34 * s)
    for i = ask.moveScroll + 1, math.min(#moves, ask.moveScroll + mper) do
      local id = moves[i]
      if Kit.button(mx + 10 * s, ly + (i - ask.moveScroll - 1) * mrowH,
                    mw - 20 * s, mrowH - 2 * s,
                    Kit.ellipsize("small", tostring(id), mw - 40 * s),
                    { font = "small" }) then
        local pick = S.partyMovePick
        pick.slot.moves = pick.slot.moves or {}
        pick.slot.moves[pick.index] = id
        -- Kept dense: a gap in the middle of a moveset is not a thing the
        -- engine has a meaning for, so a move set into slot 3 with 1 and 2
        -- empty closes up.
        local dense = {}
        for _, m in ipairs(pick.slot.moves) do dense[#dense + 1] = m end
        pick.slot.moves = dense
        S.partyMovePick = nil
      end
    end
    Kit.popClip()
    if #moves > mper then
      ask.moveScroll = Kit.scroll(mx + 10 * s, ly, mw - 20 * s,
                                  my + mh - ly - 34 * s, ask.moveScroll,
                                  #moves, mper) or ask.moveScroll
    end
    if Kit.button(mx + 10 * s, my + mh - 30 * s, mw - 20 * s, 26 * s,
                  "CANCEL", { font = "small" }) then
      S.partyMovePick = nil
    end
    -- The buttons underneath must not answer while this is up.
    return true
  end

  if result == "save" then
    PartyEditor.commit(S, writeField)
    PartyEditor.close(S)
  elseif result then
    PartyEditor.close(S)
  end
  return true
end

function PartyEditor.keypressed(S, key)
  if not (S and S.partyAsk) then return false end
  if key == "escape" then
    -- Escape closes the picker first, then the dialog: one press, one layer.
    if S.partyMovePick then
      S.partyMovePick = nil
    else
      PartyEditor.close(S)
    end
    return true
  end
  return true      -- a modal swallows the rest
end

return PartyEditor
