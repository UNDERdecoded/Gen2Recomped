-- Admission and dispatch for native party, bag and dialogue screens.
-- No screen is loaded here: an already loaded native class must own the top.
local Commands = {}
local CLASSES = {
  PartyMenu = "party_gb",
  Gen3PartyMenu = "party_gba",
  Gen4PartyMenu = "party_ds",
  Gen3BagMenu = "bag_gba",
  Gen4BagMenu = "bag_ds",
  HgssBagMenu = "bag_hgss",
  Gen5BagMenu = "bag_bw",
  Gen4BattleBag = "battle_bag",
  Gen5BattleBag = "battle_bag",
  Gen3ItemMenu = "item_actions",
  ChoiceBox = "choice",
}
local function class(screen)
  local mt = getmetatable(screen)
  if mt == nil then
    return
  end
  if mt == package.loaded["src.render.TextBox"] then
    return "text"
  end
  for name, kind in pairs(CLASSES) do
    if mt == package.loaded["src.ui." .. name] then
      return kind
    end
  end
  if mt == package.loaded["src.ui.ListMenu"] and screen.publicUIKind == "bag" then
    return "bag_gb"
  end
  if mt == package.loaded["src.ui.Menu"] and screen.publicUIKind == "bag_actions" then
    return "bag_actions"
  end
end
local function row(out, value, ids, item)
  local i = #out.rows + 1
  local r = { index = i, enabled = true }
  if type(value) == "table" then
    r.label = type(value.label) == "string" and value.label or nil
    r.action = type(value.action) == "string" and value.action or nil
    if value.header then
      r.enabled = false
    end
    if value.close then
      r.action = "back"
    end
    if item then
      r.item = ids:read("items", value.id or value.value)
      r.count = type(value.qty) == "number" and value.qty or nil
      if not r.label and type(value.def) == "table" and type(value.def.name) == "string" then
        r.label = value.def.name
      end
    end
  elseif type(value) == "string" then
    r.action, r.label = value, value
  end
  out.rows[i] = r
  return r
end
function Commands.describe(game, screen, ids)
  local kind = class(screen)
  if not kind then
    return nil, "unsupported UI screen"
  end
  if screen.game ~= game then
    return nil, "UI does not belong to current Game"
  end
  local out = {
    kind = "party",
    rows = {},
    index = screen.index,
    canBack = true,
    canAdvance = false,
    canPocket = false,
    locked = false,
  }
  local refs = { screen = screen, stack = game.stack, states = game.stack.states, save = game.save }
  -- Keep callback and nested option identity private; no engine references escape.
  for key, value in pairs(screen) do
    if type(value) == "function" or type(value) == "table" then
      refs[key] = value
    end
  end
  local function rows(values, items)
    for i, value in ipairs(values or {}) do
      refs["row:" .. i] = value
      if type(value) == "table" then
        refs["callback:" .. i] = value.onSelect
      end
      row(out, value, ids, items)
    end
  end
  if kind:match("^party_") then
    local party = kind == "party_gb" and (screen.party or game.save.party) or screen:party()
    for i, mon in ipairs(party or {}) do
      refs["mon:" .. i] = mon
    end
    if screen.selectNotice then
      out.kind, out.canAdvance, out.canBack = "text", true, false
    elseif screen.submenu then
      out.kind = "party_actions"
      rows(
        kind == "party_gb" and screen.subItems or kind == "party_gba" and screen.submenu or screen:actions()
      )
      out.index = kind == "party_ds" and screen.submenu or screen.subIndex
    else
      for i, mon in ipairs(party or {}) do
        refs["mon:" .. i] = mon
        local r = row(out, {}, ids)
        r.partyIndex, r.species, r.label = i, ids:read("pokemon", mon.species), mon.nickname
        r.hp, r.maxHp = mon.hp, mon.stats and mon.stats.hp or mon.maxHp
      end
      if kind ~= "party_gb" then
        if kind == "party_ds" and screen.select then
          row(out, "confirm", ids)
        end
        row(out, "back", ids)
      end
    end
  elseif kind == "text" then
    out.kind, out.index, out.canBack = "text", nil, false
    out.canAdvance = (
      screen.waiting or (screen.done and not screen.auto and not screen.stay and not screen.choice)
    )
        and (screen.preWait or 0) <= 0
        and (screen.holdFrames or 0) <= 0
      or false
    out.locked = not out.canAdvance
  elseif kind == "choice" then
    out.kind = "choice"
    rows({ "yes", "no" })
    out.locked = screen.pending ~= nil
  elseif kind == "battle_bag" then
    out.kind, out.page = "bag", screen.screen
    local mem = screen.mem or screen.cur
    out.pocket = screen.pocket
    out.index = screen.cursor and screen.cursor.index
    if screen.message then
      out.kind, out.canAdvance, out.canBack = "text", true, false
    elseif screen.screen == "menu" then
      rows({ "pocket:1", "pocket:2", "pocket:3", "pocket:4", "last_item", "back" })
      out.rows[5].enabled = mem.lastItem ~= nil
    elseif screen.screen == "pocket" then
      for i = 1, 6 do
        local item = screen:itemAt(i)
        refs["row:" .. i] = item
        local r = row(out, item or {}, ids, true)
        r.enabled = item ~= nil
      end
      row(out, "previous_page", ids).enabled = (screen.pageCount[screen.pocket] or 0) > 0
      row(out, "next_page", ids).enabled = (screen.pageCount[screen.pocket] or 0) > 0
      row(out, "back", ids)
    else
      rows({ "use", "back" })
      out.rows[1].enabled = screen:itemAt((mem.positions[screen.pocket] or 0) + 1) ~= nil
    end
    out.locked = screen.press ~= nil
  elseif kind == "bag_actions" or kind == "item_actions" then
    out.kind = "bag_actions"
    rows(kind == "bag_actions" and screen.items or screen.entries)
    if kind == "item_actions" then
      for i, r in ipairs(out.rows) do
        r.enabled = screen:pickable(i)
        r.action = screen.entries[i].kind
      end
    else
      out.canBack = screen.cancelable
    end
  else
    out.kind = "bag"
    out.pocket = screen.pocket or screen.pocketIndex
    if screen.message or screen.resultMessage then
      out.kind, out.canAdvance, out.canBack = "text", true, false
    elseif screen.menu then
      out.kind, out.index = screen.menu.kind == "yesno" and "choice" or "bag_actions", screen.menu.index
      rows(screen.menu.rows)
    else
      rows(kind == "bag_gb" and screen.items or kind == "bag_hgss" and screen:items() or screen.rows, true)
      out.index = kind == "bag_hgss" and screen.page * 6 + screen.slot
        or kind == "bag_bw" and screen.cursor
        or screen.index
      out.canPocket = not screen.lockPocket
          and (kind == "bag_gb" and screen.onPocketSwitch ~= nil or kind ~= "bag_gb" and #(screen.pockets or {}) > 1)
        or false
    end
    out.locked = screen.trash ~= nil and not screen.menu
      or screen.moving ~= nil and screen.moving ~= false
      or false
  end
  local battle = screen.battle or screen.publicUIBattle
  if
    battle and (battle.demo or battle.dudeDemo or battle.pokedudeDemo or battle.spectating or battle.dead)
  then
    out.locked = true
  end
  if screen.heal or screen.noInput or screen.script or screen.closed then
    out.locked = true
  end
  if out.locked then
    out.canAdvance, out.canPocket, out.canBack = false, false, false
  end
  return out, refs, kind
end
local function press(screen, ds)
  local Sound = require("src.core.Sound")
  if ds then
    if Sound.playSe and screen.game.data then
      Sound.playSe(screen.game.data, "SEQ_SE_DP_SELECT")
    end
  elseif screen.game.data then
    Sound.play(screen.game.data, "Press_AB")
  end
end
function Commands.dispatch(screen, kind, view, intent)
  if intent.kind == "advance" then
    if kind == "text" then
      screen:advance()
    elseif screen.selectNotice then
      screen.selectNotice = nil
    else
      if screen.resultMessage then
        press(screen)
      end
      screen.message, screen.resultMessage = nil, nil
    end
  elseif kind == "text" then
    error("text only supports advance")
  elseif kind == "choice" then
    screen:choose(intent.kind == "back" and 2 or intent.index)
  elseif kind == "battle_bag" then
    if intent.kind == "select" then
      screen.cursor.index = intent.index
    end
    screen:pick(intent.kind == "back" and ({ menu = 6, pocket = 9, use = 2 })[screen.screen] or intent.index)
  elseif kind == "party_gb" then
    press(screen)
    if intent.kind == "back" then
      screen:cancel()
    else
      if screen.submenu then
        screen.subIndex = intent.index
      else
        screen.index = intent.index
      end
      screen:confirm()
    end
  elseif kind == "party_gba" or kind == "party_ds" then
    if intent.kind == "back" then
      if screen.submenu then
        if screen.itemMenu then
          screen.itemMenu, screen.submenu = nil, 1
        else
          screen.submenu = nil
        end
      else
        screen:cancel()
      end
    elseif screen.submenu then
      if kind == "party_ds" then
        screen.submenu = intent.index
        screen:runAction(screen:actions()[intent.index])
      else
        screen.subIndex = intent.index
        local r = screen.submenu[intent.index]
        screen:runAction(r.action, screen:party()[screen.index], r)
      end
    else
      screen.index = intent.index
      if kind == "party_gba" then
        screen:confirm()
      else
        screen:choose()
      end
    end
  elseif kind == "bag_actions" then
    if intent.kind == "back" then
      screen:cancel()
    else
      screen.index = intent.index
      screen:choose()
    end
  elseif kind == "item_actions" then
    press(screen)
    if intent.kind == "select" then
      screen.index = intent.index
    end
    screen:close(intent.kind == "back" and "cancel" or screen.entries[intent.index].kind)
  elseif screen.menu then
    if intent.kind == "back" then
      if kind == "bag_ds" then
        press(screen, true)
      end
      if screen.menu.kind == "yesno" then
        screen:resolveTrash(false)
      else
        screen.menu = nil
      end
    else
      screen.menu.index = intent.index
      if kind ~= "bag_ds" then
        screen:runMenuRow()
      else
        press(screen, true)
        if screen.menu.kind == "yesno" then
          screen:resolveTrash(intent.index == 1)
        else
          screen:runAction(screen.menu.rows[intent.index])
        end
      end
    end
  elseif intent.kind == "pocket" then
    if kind == "bag_gb" then
      screen.onPocketSwitch(screen, intent.direction)
    elseif kind == "bag_hgss" or kind == "bag_bw" then
      screen:setPocket((screen.pocket - 1 + intent.direction) % #screen.pockets + 1)
    else
      screen.pocketLit = nil
      screen:movePocket(intent.direction)
    end
  elseif intent.kind == "back" then
    if kind == "bag_gb" then
      screen:cancel()
    else
      if kind ~= "bag_gba" then
        press(screen, true)
      end
      screen:close()
    end
  else
    if kind == "bag_hgss" then
      screen.page, screen.slot = math.floor((intent.index - 1) / 6), (intent.index - 1) % 6 + 1
    elseif kind == "bag_bw" then
      screen.cursor = intent.index
      screen.top = math.max(0, intent.index - 6)
    else
      screen.index = intent.index
      if kind == "bag_ds" then
        screen:clampScroll()
      end
    end
    screen:choose()
  end
end
return Commands
