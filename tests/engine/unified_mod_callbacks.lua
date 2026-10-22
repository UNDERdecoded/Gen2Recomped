package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Loader = require("src.mods.Loader")
local Manifest = require("src.mods.Manifest")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Catalog = require("tests.modkit.catalog")
local C = require("src.mods.UnifiedCallbacks")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, love }
love = nil
local function manifest(format, api)
  return {
    id = "probe",
    name = "Probe",
    version = "1.0.0",
    entry = "main.lua",
    api = api or 2,
    callback_format = format,
  }
end
T.eq(Manifest.validate(manifest()).callback_format, "native", "existing manifests keep native callbacks")
T.eq(Manifest.validate(manifest("unified")).callback_format, "unified", "opt-in accepted")
T.raises(function()
  Manifest.validate(manifest("unified", 1))
end, "requires mod API 2", "unified requires API 2")
T.raises(function()
  Manifest.validate(manifest("other"))
end, "callback_format", "unknown format rejected")
for _, invalid in ipairs({ false, 42, {} }) do
  T.raises(function()
    Manifest.validate(manifest(invalid))
  end, "callback_format", "malformed format rejected")
end
local function set(names)
  local out = {}
  for _, n in ipairs(names) do
    out[n] = true
  end
  return out
end
T.same(C.hooks, set(Catalog.hooks()), "every native hook has an explicit boundary decision")
T.same(C.events, set(Catalog.events()), "every native event has an explicit boundary decision")
local function boot(version, format, entry)
  Version.set(version)
  local numeric = Version.generation() >= 4
  local a, b, m, n, item =
    numeric and 501 or "ALPHA",
    numeric and 502 or "BETA",
    numeric and 601 or "TACKLE",
    numeric and 602 or "EMBER",
    numeric and 701 or "POTION"
  local data = {
    pokemon = {
      [a] = {
        id = a,
        name = "Alpha",
        baseStats = { hp = 40, attack = 45, defense = 40, speed = 30, special = 35 },
        types = {
          "NORMAL",
        },
      },
      [b] = { id = b, name = "Beta", baseStats = { hp = 50 }, types = { "NORMAL" } },
    },
    moves = {
      [m] = { id = m, name = "Tackle", pp = 35, power = 40 },
      [n] = {
        id = n,
        name = "Ember",
        pp = 25,
        power = 40,
      },
    },
    items = { [item] = { id = item, name = "Potion" } },
    trainers = {},
    encounters = {},
  }
  if numeric then
    data.pokemon.SPECIES_501 = data.pokemon[a]
    data.moves.MOVE_601 = data.moves[m]
  end
  local json = require("src.link.Json")
  local files = {
    ["mods/probe/manifest.json"] = json.encode(manifest(format)),
    ["mods/probe/main.lua"] = entry or "return function(mod) mod.exports.api=mod end",
  }
  local fs = {
    read = function(p)
      return files[p]
    end,
    load = function(p)
      return loadstring(files[p], p)
    end,
    getInfo = function(p)
      if p == "mods" or p == "mods/probe" then
        return { type = "directory" }
      end
      if files[p] then
        return { type = "file" }
      end
    end,
    getDirectoryItems = function(p)
      return p == "mods" and { "probe" } or {}
    end,
  }
  local loader = Loader.new({ fs = fs, dev = false })
  loader._game = function()
    error("callback opt-in must not construct Game")
  end
  local loaded = loader:load(data)
  if not entry then
    assert(loaded)
    assert(loader.apis.probe, tostring(loader.errors.probe))
  end
  return loader.apis.probe, loader, data, { a, b, m, n, item }
end
local function mon(ids)
  return {
    species = ids[1],
    item = ids[5],
    level = 10,
    hp = 25,
    status = "PSN",
    stats = { hp = 40, attack = 21, defense = 22, speed = 23, special = 24, spatk = 24, spdef = 25 },
    moves = { { id = ids[3], pp = 12 } },
    ivs = { hp = 17 },
    personality = 123,
    custom = { keep = true },
  }
end
for _, version in ipairs(Version.ORDER) do
  local api, loader, data, ids = boot(version, "unified")
  local label = version .. ": "
  T.eq(api.callbackFormat, "unified", label .. "format exposed before Game construction")
  local raw = mon(ids)
  if Version.generation() == 1 then
    raw.stats.spatk = nil
    raw.stats.spdef = nil
  end
  local unchanged = require("src.mods.Merge").deepCopy(raw)
  local noop = api.hooks:wrap("battle.damage", function(next)
    return next()
  end)
  loader.hooks:call("battle.damage", function()
    return 5
  end, { user = { mon = raw } })
  T.same(raw, unchanged, label .. "no-op unified callback leaves native record exactly unchanged")
  T.eq(raw.isEgg, nil, label .. "false view flag does not materialize native field")
  noop()
  local originalStats, originalMoves, originalSlot = raw.stats, raw.moves, raw.moves[1]
  local battler =
    { mon = raw, isPlayer = true, curStats = raw.stats, curMoves = raw.moves, stages = { attack = 0 } }
  local battle = { tag = "native handle" }
  local count = 0
  local off = api.hooks:wrap("battle.damage", function(next, ctx)
    T.eq(ctx.battle, battle, label .. "battle stays native")
    T.eq(ctx.user.mon, ctx.target.mon, label .. "shared mon preserves public alias")
    T.eq(ctx.user.mon.species, "ALPHA", label .. "canonical species")
    T.eq(ctx.user.mon.item, "POTION", label .. "canonical held item")
    T.eq(ctx.user.mon.moves[1].id, "TACKLE", label .. "canonical moves")
    T.eq(ctx.user.mon.status, "poison", label .. "canonical status")
    T.eq(ctx.user.mon.maxHp, 40, label .. "maxHp reads stats.hp")
    T.eq(ctx.user.mon.stats.specialAttack, 24, label .. "canonical special attack")
    ctx.user.mon.hp = 24
    ctx.user.mon.status = "burn"
    ctx.user.mon.nickname = "Test"
    ctx.user.mon.stats.attack = 26
    ctx.user.mon.moves[1].id = "EMBER"
    ctx.user.mon.moves[1].pp = 20
    local n, hole, last = next()
    T.eq(ctx.user.mon.hp, 19, label .. "native downstream changes refreshed")
    T.eq(select("#", next()), 3, label .. "cached next retains nil holes")
    ctx.user.mon.hp = 18
    return n + 1, hole, last
  end)
  local n, hole, last = loader.hooks:call("battle.damage", function(ctx)
    count = count + 1
    T.eq(ctx.user, battler, label .. "native battler identity restored")
    T.eq(ctx.user.mon, raw, label .. "native mon identity restored")
    T.eq(raw.hp, 24, label .. "pre-next mutation committed")
    T.eq(raw.status, "BRN", label .. "status written in native vocabulary")
    T.eq(raw.moves[1].id, ids[4], label .. "move ID restored for host")
    raw.hp = 19
    return 5, nil, "tail"
  end, { battle = battle, user = battler, target = battler, move = data.moves[ids[3]] })
  T.eq(n, 6, label .. "scalar result postprocessing")
  T.eq(last, "tail", label .. "result tail preserved")
  T.eq(hole, nil, label .. "nil preserved")
  T.eq(count, 1, label .. "vanilla runs once")
  T.eq(raw.hp, 18, label .. "post-next edit committed")
  T.eq(raw.stats, originalStats, label .. "stats table identity preserved")
  T.eq(raw.moves, originalMoves, label .. "moves list identity preserved")
  T.eq(raw.moves[1], originalSlot, label .. "move slot identity preserved")
  T.eq(raw.personality, 123, label .. "hidden personality retained")
  T.eq(raw.ivs.hp, 17, label .. "hidden IVs retained")
  off()

  -- Mutations across separate bound records preflight as one transaction.
  local other = mon(ids)
  off = api.hooks:wrap("battle.damage", function(_, ctx)
    ctx.user.mon.hp = 4
    ctx.target.mon.level = 101
    return 99
  end)
  count = 0
  T.eq(
    loader.hooks:call("battle.damage", function()
      count = count + 1
      return 3
    end, { user = battler, target = { mon = other } }),
    3,
    label .. "invalid edit skips wrapper"
  )
  T.eq(raw.hp, 18, label .. "earlier record edit rolled back")
  T.eq(other.level, 10, label .. "invalid record unchanged")
  T.eq(count, 1, label .. "failure before next falls through once")
  off()
  off = api.hooks:wrap("battle.damage", function(next, ctx)
    local n = next()
    ctx.user.mon.hp = -1
    return n + 20
  end)
  count = 0
  T.eq(
    loader.hooks:call("battle.damage", function()
      count = count + 1
      raw.hp = 16
      return 7
    end, { user = battler }),
    7,
    label .. "bad post-next edit keeps downstream result"
  )
  T.eq(raw.hp, 16, label .. "downstream mutation retained")
  T.eq(count, 1, label .. "bad post-next never retries")
  off()
  off = api.hooks:wrap("battle.damage", function(next, ctx)
    next()
    ctx.user.mon.hp = 2
    error("after next")
  end)
  T.eq(
    loader.hooks:call("battle.damage", function()
      return 8
    end, { user = battler }),
    8,
    label .. "throw after next preserves result"
  )
  T.eq(raw.hp, 16, label .. "throw after next discards late edits")
  off()

  local sentinel = { error = "vanilla" }
  off = api.hooks:wrap("battle.damage", function(next)
    pcall(next)
    pcall(next)
    return 999
  end)
  count = 0
  local ok, err = pcall(function()
    loader.hooks:call("battle.damage", function()
      count = count + 1
      error(sentinel)
    end, { user = battler })
  end)
  T.check(not ok and err == sentinel, label .. "vanilla error identity survives swallowed next failure")
  T.eq(count, 1, label .. "throwing vanilla never replayed")
  off()
  off = api.hooks:wrap("battle.damage", function(next)
    pcall(next)
    return 999
  end)
  local savedMoves = raw.moves
  local okBroken, errBroken = pcall(function()
    loader.hooks:call("battle.damage", function()
      raw.moves = 42 -- a failed native operation can leave an unreadable record
      error(sentinel)
    end, { user = battler })
  end)
  T.check(not okBroken and errBroken == sentinel, label .. "refresh cannot mask a native error")
  raw.moves = savedMoves
  off()

  -- Event records are detached. The native handles deliberately remain handles.
  local seen = 0
  off = api.events:once("battle.exp_gained", function(payload)
    seen = seen + 1
    T.eq(payload.mon.species, "ALPHA", label .. "event mon normalized")
    payload.mon.hp = 1
    payload.mon.native.ivs.hp = 1
  end)
  loader.events:emit("battle.exp_gained", { mon = raw, battle = battle, gained = 20 })
  loader.events:emit("battle.exp_gained", { mon = raw, battle = battle, gained = 20 })
  T.eq(seen, 1, label .. "once retained")
  T.eq(raw.hp, 16, label .. "event mutation detached")
  T.eq(raw.ivs.hp, 17, label .. "native diagnostic snapshot detached")
  off()
  local gift = { species = ids[1], level = 5, ctx = { opaque = true } }
  off = api.events:on("pokemon.before_give", function(p)
    p.species = "BETA"
    p.level = 15
    p.nickname = "Gift"
  end)
  loader.events:emit("pokemon.before_give", gift)
  T.eq(gift.species, ids[2], label .. "gift ID restored")
  T.eq(gift.level, 15, label .. "gift level committed")
  T.eq(gift.nickname, "Gift", label .. "gift nickname committed")
  off()
  off = api.events:on("pokemon.before_give", function(p)
    p.species = "ALPHA"
    p.level = 101
  end)
  loader.events:emit("pokemon.before_give", gift)
  T.eq(gift.species, ids[2], label .. "invalid gift atomic species")
  T.eq(gift.level, 15, label .. "invalid gift atomic level")
  off()

  off = api.hooks:wrap("battle.turn_order", function(next, p, pm, e, em, ctx)
    T.eq(pm.id, "TACKLE", label .. "move definition canonical ID")
    T.eq(next(), p, label .. "native result maps to original public battler")
    return e
  end)
  local enemy = { mon = other, isPlayer = false }
  T.eq(
    loader.hooks:call("battle.turn_order", function(p)
      return p
    end, battler, data.moves[ids[3]], enemy, data.moves[ids[4]], {}),
    enemy,
    label .. "selected battler restores identity"
  )
  off()
  off = api.hooks:wrap("encounter.species", function(next, enc)
    enc.species = "BETA"
    enc.level = 20
    return next()
  end)
  local encounter = { species = ids[1], level = 10, form = 2 }
  T.eq(
    loader.hooks:call("encounter.species", function(enc)
      return enc
    end, encounter, {}),
    encounter,
    label .. "encounter identity retained"
  )
  T.eq(encounter.species, ids[2], label .. "encounter species converted")
  T.eq(encounter.form, 2, label .. "encounter hidden field retained")
  off()
  off = api.hooks:wrap("trainer.party", function(next, cl, index, party)
    T.eq(party[1].species, "ALPHA", label .. "trainer slot canonical species")
    T.eq(party[1].moves[1], "TACKLE", label .. "trainer slot moves are IDs")
    party[1].species = "BETA"
    party[1].moves = { "EMBER" }
    party[1].level = 20
    return next()
  end)
  local party = { { species = ids[1], level = 10, moves = { ids[3] }, dvs = { attack = 15 } } }
  T.eq(
    loader.hooks:call("trainer.party", function(_, _, p)
      return p
    end, "CLASS", 1, party),
    party,
    label .. "trainer party native identity"
  )
  T.eq(party[1].species, ids[2], label .. "trainer species restored")
  T.eq(party[1].moves[1], ids[4], label .. "trainer move restored")
  T.eq(party[1].dvs.attack, 15, label .. "trainer hidden DVs retained")
  off()

  count = 0
  off = api.hooks:wrap("battle.exp_award", function(_, ctx)
    local p = ctx.alive[1]
    p.hp = 15
    ctx.applyShare(p, 2, false)
    T.eq(p.level, 11, label .. "applyShare refreshes public mon")
    p.hp = 14
  end)
  loader.hooks:call("battle.exp_award", function()
    error("wrapper replaces vanilla")
  end, {
    battle = battle,
    alive = { raw },
    applyShare = function(p, divisor, announce)
      count = count + 1
      T.eq(p, raw, label .. "helper gets native identity")
      T.eq(p.hp, 15, label .. "helper sees pending edits")
      T.eq(divisor, 2, label .. "helper scalar args")
      T.eq(announce, false, label .. "helper false arg")
      p.level = 11
    end,
  })
  T.eq(count, 1, label .. "helper called once")
  T.eq(raw.hp, 14, label .. "helper postprocessing committed")
  off()

  off = api.hooks:wrap("fieldmove.eligibility", function(next, id)
    T.eq(id, "TACKLE", label .. "field move argument normalized")
    local p = next()
    T.eq(p.species, "ALPHA", label .. "field move result normalized")
    return p
  end)
  T.eq(
    loader.hooks:call("fieldmove.eligibility", function(id)
      T.eq(id, ids[3], label .. "field move argument restored")
      return raw
    end, ids[3], {}),
    raw,
    label .. "field move mon result identity restored"
  )
  off()
  off = api.hooks:wrap("battle.enemy_action", function(next)
    local action = next()
    T.eq(action.id, "TACKLE", label .. "enemy action normalized")
    action.id = "EMBER"
    return action
  end)
  local action = { id = ids[3], index = 1 }
  T.eq(
    loader.hooks:call("battle.enemy_action", function()
      return action
    end, battle, battler),
    action,
    label .. "enemy action identity restored"
  )
  T.eq(action.id, ids[4], label .. "enemy action ID restored")
  off()
  off = api.hooks:wrap("encounter.roll", function()
    return { species = "BETA", level = 30 }
  end)
  local enc = loader.hooks:call("encounter.roll", function()
    error("suppressed")
  end, nil, {})
  T.eq(enc.species, ids[2], label .. "new encounter result native species")
  T.eq(enc.level, 30, label .. "new encounter level")
  off()
  off = api.hooks:wrap("encounter.roll", function()
    return { species = "MISSING", level = 30 }
  end)
  T.eq(
    loader.hooks:call("encounter.roll", function()
      return "fallback"
    end, nil, {}),
    "fallback",
    label .. "unknown species rejected"
  )
  off()
  off = api.hooks:wrap("battle.damage", function(_, ctx)
    ctx.move.power = 999
    return 88
  end)
  T.eq(
    loader.hooks:call("battle.damage", function()
      return 4
    end, { move = data.moves[ids[3]] }),
    4,
    label .. "definition mutation rejected"
  )
  T.eq(data.moves[ids[3]].power, 40, label .. "definition unchanged")
  off()
  off = api.hooks:wrap("battle.damage", function(next, ctx)
    ctx.user.mon.maxHp = 50
    ctx.user.mon.stats.specialAttack = 28
    next()
    return 0
  end)
  loader.hooks:call("battle.damage", function()
    T.eq(raw.stats.hp, 50, label .. "maxHp writes native stats.hp")
    T.eq(raw.stats.special, 28, label .. "special alias kept")
    T.eq(
      Version.generation() == 1 and raw.stats.special or raw.stats.spatk,
      28,
      label .. "split special stat writes correctly"
    )
  end, { user = battler })
  off()
  off = api.hooks:wrap("battle.damage", function(_, ctx)
    ctx.user.mon.native.ivs.hp = 9
    ctx.user.mon.hp = 2
    return 88
  end)
  T.eq(
    loader.hooks:call("battle.damage", function()
      return 3
    end, { user = battler }),
    3,
    label .. "native snapshot mutation rejected"
  )
  T.eq(raw.hp, 14, label .. "snapshot rejection atomic")
  off()
  local nativeCalls = 0
  local undoNative = loader.hooks:wrap("battle.damage", function(next, ctx)
    nativeCalls = nativeCalls + 1
    T.eq(ctx.user, battler, label .. "native mod sees native battler")
    return next()
  end, -5, "native")
  off = api.hooks:wrap("battle.damage", function(next, ctx)
    -- Explicit argument packs accept bound records inside a bound context.
    ctx.extra = 123
    return next(ctx)
  end, 5)
  loader.hooks:call("battle.damage", function(ctx)
    T.eq(ctx.extra, 123, label .. "explicit next args committed")
  end, { user = battler })
  T.eq(nativeCalls, 1, label .. "mixed native/unified chain")
  off()
  undoNative()
  local order = {}
  local a = api.events:on("battle.started", function()
    order[#order + 1] = "low"
  end, -1)
  local b = api.events:on("battle.started", function()
    order[#order + 1] = "high"
  end, 1)
  loader.events:emit("battle.started", {})
  T.same(order, { "high", "low" }, label .. "event priority retained")
  a()
  b()
  local actionView
  off = api.events:on("battle.turn_started", function(p)
    actionView = p.playerAction
  end)
  loader.events:emit("battle.turn_started", { playerAction = { id = ids[3], index = 1 } })
  T.eq(actionView.id, "TACKLE", label .. "turn event action ID normalized")
  off()

  off = api.hooks:wrap("battle.damage", function(_, ctx)
    ctx.user.mon.moves = { [2] = { id = "TACKLE", pp = 1, ppUps = 0 } }
    ctx.user.mon.hp = 1
    return 99
  end)
  T.eq(
    loader.hooks:call("battle.damage", function()
      return 2
    end, { user = battler }),
    2,
    label .. "sparse move list rejected"
  )
  T.eq(raw.hp, 14, label .. "sparse move list fails atomically")
  off()
  local retainedNext, retainedShare
  off = api.hooks:wrap("battle.exp_award", function(next, ctx)
    retainedNext = next
    retainedShare = ctx.applyShare
  end)
  loader.hooks:call("battle.exp_award", function()
    error("must not run")
  end, {
    alive = { raw },
    applyShare = function()
      error("must not run")
    end,
  })
  T.raises(function()
    retainedNext()
  end, "only valid during", label .. "retained next cannot run after callback")
  T.raises(function()
    retainedShare(raw)
  end, "bound Pokemon", label .. "helper rejects native mon")
  off()
  local heldMon
  off = api.hooks:wrap("battle.exp_award", function(_, ctx)
    heldMon = ctx.alive[1]
    retainedShare = ctx.applyShare
  end)
  loader.hooks:call("battle.exp_award", function() end, {
    alive = { raw },
    applyShare = function()
      error("must not run")
    end,
  })
  T.raises(function()
    retainedShare(heldMon)
  end, "closed", label .. "retained helper cannot write after callback")
  off()

  local custom = { mon = raw }
  local got
  off = api.events:on("mod.other.ready", function(p)
    got = p
  end)
  loader.events:emit("mod.other.ready", custom)
  T.eq(got, custom, label .. "custom payload identity untouched")
  off()
  T.raises(function()
    api.events:emit("mod.other.ready", {})
  end, "only emit", label .. "cannot spoof other mod")
  T.raises(function()
    api.events:emit("mod.probe.", {})
  end, "only emit", label .. "empty custom suffix rejected")
  T.raises(function()
    api.hooks:wrap("invented.hook", function() end)
  end, "unknown unified", label .. "unknown hook rejected")
  T.raises(function()
    api.events:on("invented.event", function() end)
  end, "unknown unified", label .. "unknown event rejected")
end
-- The native path must not install any wrapper or copy its payloads.
local api, loader = boot("crystal")
T.eq(api.callbackFormat, "native", "default API native")
local raw = { mon = { species = 42 } }
api.events:on("custom.engine", function(p)
  T.eq(p, raw, "native event identity unchanged")
end)
loader.events:emit("custom.engine", raw)
api.hooks:wrap("custom.hook", function(next, ctx)
  T.eq(ctx, raw, "native hook identity unchanged")
  return next()
end)
T.eq(
  loader.hooks:call("custom.hook", function(ctx)
    return ctx
  end, raw),
  raw,
  "native result identity unchanged"
)
-- Entry rollback removes unified subscriptions using the same native owner.
local _, failed = boot(
  "crystal",
  "unified",
  [[return function(mod)
  mod.events:on('battle.started',function() end)
  mod.hooks:wrap('battle.damage',function() end)
  error('rollback probe')
end]]
)
T.check(#failed.errors > 0, "failed entry attributed")
T.check(
  not failed.events.listeners["battle.started"] or #failed.events.listeners["battle.started"] == 0,
  "failed entry event removed"
)
T.check(
  not failed.hooks.chains["battle.damage"] or #failed.hooks.chains["battle.damage"] == 0,
  "failed entry hook removed"
)
Version.set(saved[1])
Runtime.install(saved[2], saved[3], saved[4])
love = saved[5]
T.finish()
