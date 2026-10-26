-- Real native screens, Loader facades and ROM-free generation fixtures.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local GameVersion = require("src.core.GameVersion")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Font = require("src.render.Font")
local Runtime = require("src.mods.Runtime")
local Json = require("src.link.Json")
local Intents = require("src.mods.BattleIntents")
local original = GameVersion.get()
local versions = GameVersion.ORDER
local function boot(version, apiLevel)
  GameVersion.set(version)
  local data = T.fixtures.fresh()
  local files = {}
  for _, id in ipairs({ "probe", "other" }) do
    files["mods/" .. id .. "/manifest.json"] =
      Json.encode({ id = id, name = id, version = "1.0.0", api = apiLevel or 2, entry = "main.lua" })
    files["mods/" .. id .. "/main.lua"] = [[return function(mod)
      assert(mod.ui:snapshot()==nil)
      assert(type(mod.ui.insertBefore)=="function")
      if mod.supports then
        assert(mod:supports("ui", "snapshot"))
        assert(mod:supports("ui", "submit"))
        assert(not mod:supports("ui", "unknown"))
      end
    end]]
  end
  local fs = {
    read = function(p)
      return files[p]
    end,
    load = function(p)
      return loadstring(files[p], p)
    end,
    getDirectoryItems = function(p)
      return p == "mods" and { "probe", "other" } or {}
    end,
    getInfo = function(p)
      if p == "mods" or p == "mods/probe" or p == "mods/other" then
        return { type = "directory" }
      end
      if files[p] then
        return { type = "file" }
      end
    end,
  }
  local loader = Loader.new({ fs = fs, dev = false })
  T.check(loader:load(data), "fixture mods load")
  local game = { data = data, stack = { states = {} }, save = SaveData.newGame() }
  loader.game = game
  Font.load(data)
  game.save.party = { Pokemon.new(data, "FIXMON_A", 20), Pokemon.new(data, "FIXMON_B", 12) }
  game.input = {
    wasPressed = function()
      return false
    end,
    isDown = function()
      return false
    end,
  }
  function game.stack:top()
    return self.states[#self.states]
  end
  function game.stack:push(state)
    self.states[#self.states + 1] = state
  end
  function game.stack:pop()
    return table.remove(self.states)
  end
  return loader.apis.probe.ui, game, loader.apis.other.ui, loader
end
local function button(game, screen, name)
  local old = game.input
  game.input = {
    wasPressed = function(_, key)
      return key == name
    end,
    isDown = function()
      return false
    end,
  }
  screen:update(1 / 60)
  game.input = old
end
local function submit(ui, id, kind, fields)
  local snap, err = ui:snapshot()
  assert(snap, err)
  local intent = { id = id, revision = snap.revision, kind = kind }
  for k, v in pairs(fields or {}) do
    intent[k] = v
  end
  return ui:submit(intent)
end
local partyClass = {
  red = "PartyMenu",
  crystal = "PartyMenu",
  emerald = "Gen3PartyMenu",
  platinum = "Gen4PartyMenu",
  heartgold = "Gen4PartyMenu",
  black = "Gen4PartyMenu",
}
local bagClass = {
  red = "BagMenu",
  crystal = "BagMenu",
  emerald = "Gen3BagMenu",
  platinum = "Gen4BagMenu",
  heartgold = "HgssBagMenu",
  black = "Gen5BagMenu",
}
for _, version in ipairs(versions) do
  local gen = GameVersion.VERSIONS[version].generation
  partyClass[version] = partyClass[version]
    or (gen <= 2 and "PartyMenu" or gen == 3 and "Gen3PartyMenu" or "Gen4PartyMenu")
  bagClass[version] = bagClass[version]
    or (
      gen <= 2 and "BagMenu"
      or gen == 3 and "Gen3BagMenu"
      or version == "soulsilver" and "HgssBagMenu"
      or gen == 5 and "Gen5BagMenu"
      or "Gen4BagMenu"
    )
  local ui, game, other = boot(version)
  local chosen, cancelled = 0, 0
  local screen = require("src.ui." .. partyClass[version]).new(game, {
    pickOnly = true,
    onSwitch = function(mon)
      T.eq(mon, game.save.party[2], "native picker target")
      chosen = chosen + 1
    end,
    onCancel = function()
      cancelled = cancelled + 1
    end,
  })
  game.stack:push(screen)
  local snap = assert(ui:snapshot())
  T.eq(snap.kind, "party", version .. " party recognized")
  T.eq(snap.rows[2].species, "FIXMON_B", "portable party ID")
  T.eq(ui:snapshot().revision, snap.revision, "unchanged read retains revision")
  snap.rows[1].hp = -999
  T.neq(game.save.party[1].hp, -999, "snapshot detached")
  local stale = other:snapshot()
  T.check(submit(ui, 1, "select", { index = 2 }), "native party selection accepted")
  T.eq(chosen, 1, "picker callback once")
  T.eq(#game.stack.states, 0, "picker popped")
  T.eq(
    other:submit({ id = 1, revision = stale.revision, kind = "back" }),
    nil,
    "other facade cannot use departed picker"
  )
  game.stack:push(require("src.ui." .. partyClass[version]).new(game, {
    onCancel = function()
      cancelled = cancelled + 1
    end,
  }))
  T.check(submit(ui, 2, "back"), "native party back")
  T.eq(cancelled, 1, "onCancel delivered")
  local bag = require("src.ui." .. bagClass[version]).new(game, {})
  game.stack:push(bag)
  local bagSnap = assert(ui:snapshot())
  T.eq(bagSnap.kind, "bag", version .. " bag recognized")
  if bagSnap.canPocket then
    T.check(submit(ui, 3, "pocket", { direction = 1 }), "native pocket switch")
  end
  T.check(submit(ui, 4, "back"), "native bag back")
  T.eq(#game.stack.states, 0, "bag popped")
end

-- Walk raw entries, preserving identity and cycles, to detect any gameplay
-- writes from observations and rejected requests (T.same is not cycle-safe).
local function freeze(root)
  local graph = {}
  local function visit(t)
    if type(t) ~= "table" or graph[t] then
      return
    end
    local entry = { mt = getmetatable(t), values = {} }
    graph[t] = entry
    for k, v in pairs(t) do
      entry.values[k] = v
      visit(k)
      visit(v)
    end
  end
  visit(root)
  return function(label)
    local same = true
    for t, entry in pairs(graph) do
      same = same and getmetatable(t) == entry.mt
      for k, v in pairs(entry.values) do
        same = same and rawget(t, k) == v
      end
      for k, v in pairs(t) do
        same = same and entry.values[k] == v
      end
    end
    T.check(same, label)
  end
end
local function refusal(ui, game, intent, message)
  local unchanged = freeze(game)
  local ok, err = ui:submit(intent)
  T.eq(ok, nil, message)
  T.check(type(err) == "string", message .. " explains refusal")
  unchanged(message .. " leaves game untouched")
  return err
end
for _, version in ipairs(versions) do
  -- Compare native A/B to the facade for each party submenu and its back path.
  local traces = {}
  for _, native in ipairs({ true, false }) do
    local ui, game = boot(version)
    local party = require("src.ui." .. partyClass[version]).new(game, {})
    game.stack:push(party)
    local unchanged = freeze(game)
    local snap = ui:snapshot()
    unchanged("party snapshot is observational")
    T.check(snap ~= nil, "native screen available")
    if native then
      button(game, party, "a")
    else
      T.check(submit(ui, 1, "select", { index = 1 }), "open party submenu")
    end
    local stableSubmenu = freeze(game)
    snap = ui:snapshot()
    stableSubmenu("submenu snapshot remains observational")
    T.eq(snap.kind, "party_actions", "party action rows offered")
    local swap
    for i, r in ipairs(snap.rows) do
      if r.action == "switch" or r.action == "switchOrder" then
        swap = i
      end
    end
    T.check(swap ~= nil, "native swap row exposed")
    if native then
      if GameVersion.VERSIONS[version].generation <= 3 then
        party.subIndex = swap
      else
        party.submenu = swap
      end
      button(game, party, "a")
      party.index = 2
      button(game, party, "a")
    else
      T.check(submit(ui, 2, "select", { index = swap }), "start swap")
      T.check(submit(ui, 3, "select", { index = 2 }), "finish swap")
    end
    traces[#traces + 1] = {
      first = game.save.party[1].species,
      second = game.save.party[2].species,
      depth = #game.stack.states,
      index = party.index,
      swapFrom = party.swapFrom,
      switchFrom = party.switchFrom,
    }
    if native then
      button(game, party, "b")
    else
      T.check(submit(ui, 4, "back"), "back after swap")
    end
    T.eq(#game.stack.states, 0, "native party cancellation")
  end
  T.same(traces[1], traces[2], version .. " swap matches native A/B")

  local ui, game, other, loader = boot(version)
  local party = require("src.ui." .. partyClass[version]).new(game, {})
  game.stack:push(party)
  local snap = ui:snapshot()
  for _, bad in ipairs({
    false,
    1,
    "select",
    {},
    { id = 1, revision = snap.revision, kind = "unknown" },
    { id = 1, revision = snap.revision, kind = "select", index = 0 },
    { id = 1, revision = snap.revision, kind = "select", index = 1.5 },
    { id = math.huge, revision = snap.revision, kind = "back" },
    { id = 1, revision = snap.revision, kind = "back", extra = true },
    setmetatable({ id = 1, revision = snap.revision, kind = "back" }, {}),
  }) do
    refusal(ui, game, bad, "invalid intent")
  end
  refusal(ui, game, { id = 1, revision = snap.revision, kind = "select", index = 999 }, "missing row")
  refusal(ui, game, { id = 1, revision = snap.revision, kind = "advance" }, "party cannot advance text")
  refusal(
    ui,
    game,
    { id = 1, revision = snap.revision, kind = "pocket", direction = 1 },
    "party has no pockets"
  )
  game.save.party[1].hp = game.save.party[1].hp - 1
  T.eq(
    refusal(ui, game, { id = 1, revision = snap.revision, kind = "back" }, "HP change stales snapshot"),
    "stale UI context",
    "stale reason"
  )
  snap = ui:snapshot()
  local replacement = {}
  for k, v in pairs(game.save.party[1]) do
    replacement[k] = v
  end
  game.save.party[1] = replacement
  refusal(
    ui,
    game,
    { id = 1, revision = snap.revision, kind = "back" },
    "identical replacement mon stales snapshot"
  )
  -- Different screen identity, even with identical values.
  snap = ui:snapshot()
  local replacementScreen = require("src.ui." .. partyClass[version]).new(game, {})
  game.stack.states[1] = replacementScreen
  refusal(ui, game, { id = 1, revision = snap.revision, kind = "back" }, "replacement screen stales snapshot")
  party = replacementScreen
  -- Whitelist native ownership; never infer an unrelated menu from its rows.
  game.stack:push({ game = game, kind = "party", items = { { label = "fake" } } })
  T.eq(ui:snapshot(), nil, "unrelated overlay unsupported")
  refusal(ui, game, { id = 1, revision = snap.revision, kind = "back" }, "covered native menu refused")
  game.stack:pop()
  for _, flag in ipairs({ "heal", "noInput", "script", "closed" }) do
    party[flag] = true
    snap = ui:snapshot()
    T.eq(snap.locked, true, flag .. " locks public UI")
    refusal(ui, game, { id = 1, revision = snap.revision, kind = "back" }, flag .. " blocks action")
    party[flag] = nil
  end
  -- Shared battle/UI guard, cross-mod epoch, consumed IDs and partial failures.
  snap = ui:snapshot()
  Intents.state(game).busy = true
  refusal(ui, game, { id = 1, revision = snap.revision, kind = "back" }, "in-progress battle/UI work blocked")
  T.eq(ui:snapshot().locked, true, "busy snapshot locked")
  Intents.state(game).busy = false
  snap = ui:snapshot()
  Intents.state(game).epoch = Intents.state(game).epoch + 1
  refusal(ui, game, { id = 1, revision = snap.revision, kind = "back" }, "battle work expires UI snapshot")
  local calls, during, observed = 0
  party.onCancel = function()
    calls = calls + 1
    game.stack:push(party) -- keep an identical screen for the epoch test
    during = other:snapshot()
    observed = other:submit({ id = 9, revision = during.revision, kind = "back" })
    error("native callback failure")
  end
  local otherSnap = other:snapshot()
  snap = ui:snapshot()
  Runtime.currentMod = "probe"
  local ok, err = ui:submit({ id = 10, revision = snap.revision, kind = "back" })
  T.eq(ok, nil, "partial native failure reported")
  T.check(err:find("intent consumed", 1, true) ~= nil, "partial failure consumes id")
  T.eq(Runtime.currentMod, "probe", "engine attribution restored after error")
  Runtime.currentMod = nil
  T.eq(calls, 1, "callback invoked once")
  T.eq(observed, nil, "callback cannot submit reentrantly")
  T.eq(during.locked, true, "snapshot during callback is locked")
  refusal(other, game, { id = 9, revision = otherSnap.revision, kind = "back" }, "other mod snapshot expired")
  refusal(other, game, { id = 9, revision = during.revision, kind = "back" }, "mid-callback snapshot expired")
  refusal(
    ui,
    game,
    { id = 10, revision = ui:snapshot().revision, kind = "back" },
    "failed native action cannot replay"
  )
  game.stack.states = { require("src.ui." .. partyClass[version]).new(game, {}) }
  T.check(submit(ui, 11, "back"), "guard released after failure")
  T.eq(loader.apis.probe.ui.insertBefore, require("src.ui.ModUI").insertBefore, "builder helpers retained")
  T.neq(ui, other, "per-mod facade identity")
end

local TextBox = require("src.render.TextBox")
local ChoiceBox = require("src.ui.ChoiceBox")
local function tickUntil(game, box, predicate)
  for _ = 1, 1000 do
    if predicate() then
      return
    end
    box:update(1 / 60)
  end
  error("native UI did not reach expected state")
end
for _, version in ipairs(versions) do
  local ui, game = boot(version)
  local done = 0
  local box = TextBox.new(game, "First\fSecond", function()
    done = done + 1
  end)
  game.stack:push(box)
  local snap = ui:snapshot()
  T.eq(snap.kind, "text", "text recognized")
  T.eq(snap.locked, true, "typing text locked")
  refusal(ui, game, { id = 1, revision = snap.revision, kind = "advance" }, "typing cannot be skipped")
  tickUntil(game, box, function()
    return box.waiting and (box.preWait or 0) <= 0
  end)
  T.check(submit(ui, 1, "advance"), "manual page advances")
  T.check((box.holdFrames or 0) > 0, "page clear hold preserved")
  snap = ui:snapshot()
  refusal(ui, game, { id = 2, revision = snap.revision, kind = "advance" }, "page hold cannot be skipped")
  tickUntil(game, box, function()
    return box.done
  end)
  T.check(submit(ui, 2, "advance"), "final text closes")
  T.eq(done, 1, "text callback once")
  T.eq(game.stack:top(), nil, "text popped")
  for _, opts in ipairs({ { auto = {} }, { stay = {} }, { choice = function() end } }) do
    box = TextBox.new(game, "Ready", nil, opts)
    game.stack:push(box)
    box.done = true
    snap = ui:snapshot()
    T.eq(snap.canAdvance, false, "automatic/stay/choice text not manually dismissed")
    refusal(ui, game, { id = 3, revision = snap.revision, kind = "advance" }, "script-owned text protected")
    game.stack:pop()
  end
  -- Native text -> choice -> delayed answer -> both boxes popped.
  local answers = {}
  box = TextBox.new(game, "Question?", nil, {
    defaultNo = true,
    choice = function(yes)
      answers[#answers + 1] = yes
    end,
  })
  game.stack:push(box)
  tickUntil(game, box, function()
    return box.done
  end)
  box:update(1 / 60)
  local choice = game.stack:top()
  T.eq(getmetatable(choice), ChoiceBox, "native choice appears")
  T.eq(ui:snapshot().index, 2, "default NO retained")
  T.check(submit(ui, 4, "select", { index = 1 }), "YES accepted")
  T.eq(#answers, 0, "answer callback waits for native hold")
  T.eq(#game.stack.states, 2, "both boxes retained during answer hold")
  snap = ui:snapshot()
  refusal(ui, game, { id = 5, revision = snap.revision, kind = "back" }, "pending answer locked")
  tickUntil(game, choice, function()
    return #answers == 1
  end)
  T.eq(answers[1], true, "YES delivered")
  T.eq(#game.stack.states, 0, "choice closes original text too")
  choice = ChoiceBox.new(game, function(yes)
    answers[#answers + 1] = yes
  end)
  game.stack:push(choice)
  T.check(submit(ui, 5, "back"), "B selects NO")
  T.eq(choice.index, 2, "NO cursor retained while pending")
  tickUntil(game, choice, function()
    return #answers == 2
  end)
  T.eq(answers[2], false, "NO delivered")
end

-- Pick an actual item through each native bag. API and physical A/B must
-- deliver the same callback and row, including HGSS pages and BW cursors.
for _, version in ipairs(versions) do
  local traces = {}
  for _, native in ipairs({ true, false }) do
    local ui, game = boot(version)
    game.data.items.POTION = {
      id = "POTION",
      name = "POTION",
      pocket = "ITEM",
      fieldPocket = 0,
      bwPocket = 0,
      fieldUse = 1,
      fieldUseFunc = 1,
      battlePocket = 4,
    }
    game.save.inventory, game.save.bagOrder = { POTION = 2 }, { "POTION" }
    local picked = {}
    local bag = require("src.ui." .. bagClass[version]).new(game, {
      pick = true,
      onPick = function(id)
        picked[#picked + 1] = id
      end,
    })
    game.stack:push(bag)
    local unchanged = freeze(game)
    local snap = ui:snapshot()
    unchanged("bag snapshot does not rebuild, sort or load graphics")
    local itemRow
    for i, row in ipairs(snap.rows) do
      if row.item == "POTION" then
        itemRow = i
      end
    end
    T.check(itemRow ~= nil, version .. " item exposed")
    if native then
      if bagClass[version] == "HgssBagMenu" then
        bag.page, bag.slot = math.floor((itemRow - 1) / 6), (itemRow - 1) % 6 + 1
      elseif bagClass[version] == "Gen5BagMenu" then
        bag.cursor = itemRow
      else
        bag.index = itemRow
        if bag.clampScroll then
          bag:clampScroll()
        end
      end
      button(game, bag, "a")
    else
      T.check(submit(ui, 1, "select", { index = itemRow }), "native bag selection accepted")
    end
    -- GB's bag has no generic pick option: it opens USE/GIVE/TOSS instead.
    local top = game.stack:top()
    if bagClass[version] == "BagMenu" then
      T.eq(ui:snapshot().kind, "bag_actions", "only factory-owned bag action menus offered")
      if native then
        button(game, top, "b")
      else
        T.check(submit(ui, 2, "back"), "back from native item submenu")
      end
    else
      T.same(picked, { "POTION" }, "native pick callback exactly once")
    end
    traces[#traces + 1] = { picked = picked, count = game.save.inventory.POTION, depth = #game.stack.states }
  end
  T.same(traces[1], traces[2], version .. " bag confirm matches native input")
end
-- Real medicine effect, target picker and HP animation through the public
-- boundary. The native flow owns consumption and its delayed completion.
for _, version in ipairs({ "red", "crystal", "emerald" }) do
  local ui, game = boot(version)
  game.data.items.POTION = { id = "POTION", name = "POTION", pocket = "ITEM" }
  game.save.inventory, game.save.bagOrder = { POTION = 2 }, { "POTION" }
  local mon = game.save.party[1]
  mon.hp = mon.stats.hp - 25
  local before = mon.hp
  local bag = require("src.ui." .. bagClass[version]).new(game, {})
  game.stack:push(bag)
  local snap = ui:snapshot()
  local slot
  for i, r in ipairs(snap.rows) do
    if r.item == "POTION" then
      slot = i
    end
  end
  T.check(submit(ui, 1, "select", { index = slot }), "select medicine")
  snap = ui:snapshot()
  if snap.kind == "bag_actions" then
    local use
    for i, r in ipairs(snap.rows) do
      if r.action == "use" or r.label == "USE" then
        use = i
      end
    end
    T.check(submit(ui, 2, "select", { index = use }), "native USE action")
  end
  local picker = game.stack:top()
  T.eq(ui:snapshot().kind, "party", "medicine opens native target picker")
  T.check(submit(ui, 3, "select", { index = 1 }), "select medicine target")
  T.eq(mon.hp, before + 20, "real native potion restores 20 HP")
  T.eq(game.save.inventory.POTION, 1, "real native potion consumes once")
  T.eq(picker.heal ~= nil, true, "native heal animation retained")
  snap = ui:snapshot()
  refusal(
    ui,
    game,
    { id = 4, revision = snap.revision, kind = "select", index = 1 },
    "cannot use again during HP fill"
  )
  tickUntil(game, picker, function()
    return picker.heal == nil
  end)
  local box = game.stack:top()
  T.eq(getmetatable(box), TextBox, "native result text appears after fill")
  tickUntil(game, box, function()
    return box.done
  end)
  T.check(submit(ui, 4, "advance"), "native medicine result dismissed")
  T.eq(game.save.inventory.POTION, 1, "result dismissal cannot consume again")
end
-- The GBA action grid keeps its blank cells and script input lock.
do
  local ui, game = boot("emerald")
  local chosen
  local menu = require("src.ui.Gen3ItemMenu").new(game, {
    entries = {
      { label = "USE", kind = "use" },
      { label = "", kind = "blank" },
      { label = "CANCEL", kind = "cancel" },
    },
    onPick = function(kind)
      chosen = kind
    end,
  })
  game.stack:push(menu)
  local snap = ui:snapshot()
  T.eq(snap.rows[2].enabled, false, "blank grid cell disabled")
  refusal(ui, game, { id = 1, revision = snap.revision, kind = "select", index = 2 }, "blank cell refused")
  T.check(submit(ui, 1, "select", { index = 1 }), "native item grid confirm")
  T.eq(chosen, "use", "native item action callback")
end
-- DS battle bags admit their native delayed press, never call its callback
-- early. Page slots, absent items and return buttons preserve native indices.
for _, version in ipairs({ "platinum", "heartgold", "black", "white" }) do
  local traces = {}
  for _, native in ipairs({ true, false }) do
    local ui, game = boot(version)
    game.data.items.POTION =
      { id = "POTION", name = "POTION", fieldPocket = 0, battlePocket = 4, battleMask = 4 }
    game.save.inventory, game.save.bagOrder = { POTION = 2 }, { "POTION" }
    local ds = GameVersion.VERSIONS[version].generation == 5 and "Gen5BattleBag" or "Gen4BattleBag"
    local bag = require("src.ui." .. ds).new(game, {})
    game.gen4CursorActive = true
    game.stack:push(bag)
    local snap = ui:snapshot()
    refusal(
      ui,
      game,
      { id = 1, revision = snap.revision, kind = "select", index = 5 },
      "unavailable last-used row"
    )
    local function select(id, index)
      if native then
        bag.cursor.index = index
        button(game, bag, "a")
      else
        T.check(submit(ui, id, "select", { index = index }), "battle bag native press admitted")
      end
      T.check(bag.press ~= nil, "native press pending")
      T.eq(ui:snapshot().locked, true, "pending press locks UI")
      tickUntil(game, bag, function()
        return bag.press == nil
      end)
    end
    select(1, 1)
    T.eq(bag.screen, "pocket", "native pocket opens after animation")
    snap = ui:snapshot()
    T.eq(snap.rows[1].item, "POTION", "native battle item row")
    refusal(
      ui,
      game,
      { id = 2, revision = snap.revision, kind = "select", index = 6 },
      "empty item slot refused"
    )
    select(2, 1)
    T.eq(bag.screen, "use", "native use question")
    select(3, 2)
    T.eq(bag.screen, "pocket", "use back returns to pocket")
    select(4, 9)
    T.eq(bag.screen, "menu", "pocket back returns to categories")
    if native then
      button(game, bag, "b")
    else
      T.check(submit(ui, 5, "back"), "battle bag cancel")
    end
    T.check(bag.press ~= nil, "cancel animation pending")
    tickUntil(game, bag, function()
      return bag.press == nil
    end)
    traces[#traces + 1] = {
      depth = #game.stack.states,
      count = game.save.inventory.POTION,
      page = bag.screen,
      closed = bag.closed,
    }
  end
  T.same(traces[1], traces[2], version .. " battle bag matches native A/B")
end

-- opts.auto/stay/choice govern the final page, not the manual paragraph
-- breaks before it. Do not strand a question that spans several pages.
for _, opts in ipairs({ { auto = {} }, { stay = {} }, { choice = function() end } }) do
  local ui, game = boot("crystal")
  local box = TextBox.new(game, "First\fLast", nil, opts)
  game.stack:push(box)
  tickUntil(game, box, function()
    return box.waiting and (box.preWait or 0) <= 0
  end)
  T.eq(ui:snapshot().canAdvance, true, "script tail still allows manual intermediate page")
  T.check(submit(ui, 1, "advance"), "intermediate question/automatic/stay page advances")
  tickUntil(game, box, function()
    return box.done
  end)
  T.eq(ui:snapshot().canAdvance, false, "final script-owned page stays protected")
end
-- Wrong Game, unknown overlays, script-owned bags and pending controllers.
do
  local ui, game = boot("platinum")
  local bag = require("src.ui.Gen4BagMenu").new(game, {})
  game.stack:push(bag)
  for _, key in ipairs({ "moving", "trash", "script", "noInput" }) do
    bag[key] = true
    local snap = ui:snapshot()
    T.eq(snap.locked, true, "busy bag locked")
    refusal(ui, game, { id = 1, revision = snap.revision, kind = "back" }, "busy bag refusal")
    bag[key] = nil
  end
  bag.battle = { demo = true }
  local snap = ui:snapshot()
  refusal(ui, game, { id = 1, revision = snap.revision, kind = "back" }, "battle tutorial owns bag")
  bag.battle = nil
  bag.game = {}
  T.eq(ui:snapshot(), nil, "wrong game screen unavailable")
end
-- Existing helpers remain usable with their original dot-call contract.
do
  local ui, _, other = boot("red")
  local rows = { { label = "a" }, { label = "c" } }
  ui.insertBefore(rows, "c", { label = "b" })
  T.eq(rows[2].label, "b", "legacy builder still works")
  T.eq(rawget(other, "snapshot") ~= nil, true, "each mod owns its facade methods")
end

-- API 1 gets the same additive surface without changing its content format.
for _, version in ipairs({ "red", "emerald", "black" }) do
  local ui, game, _, loader = boot(version, 1)
  game.stack:push(ChoiceBox.new(game, function() end))
  T.eq(ui:snapshot().kind, "choice", "API 1 UI reader")
  T.check(submit(ui, 1, "back"), "API 1 UI action")
  if loader.apis.probe.supports then
    T.eq(loader.apis.probe:supports("ui", "snapshot"), true, "optional reader capability")
    T.eq(loader.apis.probe:supports("ui", "submit"), true, "optional action capability")
    T.eq(loader.apis.probe:supports("ui", "unknown"), false, "unknown capability declined")
  end
end
-- A real battle opens its picker via mod.battle:submit. Targeting the picker
-- consumes the current UI context, then native callbacks resume the battle.
do
  local ui, game, _, loader = boot("crystal")
  local BattleState = require("src.battle.BattleState")
  local b = BattleState.newWild(game, "FIXMON_C", 10)
  b:syncSides()
  b.phase, b.queue, b.menuIndex = "menu", {}, 1
  game.stack:push(b)
  local api = loader.apis.probe.battle
  local snapshot = api:snapshot()
  T.check(
    api:submit({ id = 1, revision = snapshot.revision, kind = "menu", choice = "party" }),
    "battle opens native party UI"
  )
  for _ = 1, 100 do
    if game.stack:top() ~= b then
      break
    end
    b:updateQueue()
  end
  T.eq(ui:snapshot().kind, "party", "battle picker exposed by UI facade")
  local oldBattle = api:snapshot()
  T.check(submit(ui, 1, "select", { index = 2 }), "choose switching party slot")
  T.eq(ui:snapshot().kind, "party_actions", "native battle switch submenu")
  local switch
  for i, row in ipairs(ui:snapshot().rows) do
    if row.action == "battle_switch" then
      switch = i
    end
  end
  T.check(submit(ui, 2, "select", { index = switch }), "native switch callback dispatched")
  T.eq(game.stack:top(), b, "native battle resumes")
  T.check(#b.queue > 0, "native switch queues battle work")
  T.eq(
    api:submit({ id = 2, revision = oldBattle.revision, kind = "menu", choice = "fight" }),
    nil,
    "UI work expires battle context"
  )
end

-- Link/temporary party arrays can differ from save.party. Track the actual
-- native target, including changes made while its action submenu is open.
do
  local ui, game = boot("crystal")
  local copy = { Pokemon.new(game.data, "FIXMON_C", 15), Pokemon.new(game.data, "FIXMON_B", 12) }
  local party = require("src.ui.PartyMenu").new(game, { party = copy })
  game.stack:push(party)
  T.check(submit(ui, 1, "select", { index = 1 }), "open temporary party submenu")
  local snapshot = ui:snapshot()
  copy[1].hp = copy[1].hp - 1
  T.eq(
    refusal(
      ui,
      game,
      { id = 2, revision = snapshot.revision, kind = "back" },
      "temporary party HP invalidates submenu"
    ),
    "stale UI context",
    "actual native party tracked"
  )
  snapshot = ui:snapshot()
  local replacement = {}
  for k, v in pairs(copy[1]) do
    replacement[k] = v
  end
  copy[1] = replacement
  refusal(
    ui,
    game,
    { id = 2, revision = snapshot.revision, kind = "back" },
    "temporary party object identity tracked"
  )
end
GameVersion.set(original)
T.finish("UI actions")
