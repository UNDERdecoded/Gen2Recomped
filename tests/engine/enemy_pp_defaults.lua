package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, Save = require("src.core.GameVersion"), require("src.core.SaveData")
local Defaults = require("src.battle.RulesetDefaults")
local Fixture = dofile("tests/charge_required/fixture.lua")
local old = V.get()

T.eq(Save.defaultOptions().ruleset, false, "new settings select cartridge rules automatically")
T.eq(Save.mergeOptions({}).ruleset, false, "missing old preference becomes automatic")
for _, id in ipairs({ "gen1_faithful", "modern_clean", "custom_rules" }) do
  T.eq(Save.mergeOptions({ ruleset = id }).ruleset, id, "explicit persisted choice is preserved")
end
local fs = T.sdk.memfs({})
T.check(
  Save.saveOptions({ ruleset = "gen1_faithful", perGeneration = { [2] = { ruleset = false } } }, fs),
  "per-generation automatic preference saves"
)
T.eq(Save.optionsFor("gold", fs).ruleset, false, "generation override can opt out of shared explicit id")
T.eq(Save.optionsFor("red", fs).ruleset, "gen1_faithful", "automatic override does not leak to other games")
local live = Save.optionsFor("gold", fs)
live.ruleset = "modern_clean"
T.check(Save.saveOptions(live, fs, 2), "explicit generation preference saves")
T.eq(Save.optionsFor("gold", fs).ruleset, "modern_clean", "explicit choice survives reloading")
live = Save.optionsFor("gold", fs)
live.ruleset = false
T.check(Save.saveOptions(live, fs, 2), "return to automatic saves")
T.eq(Save.optionsFor("gold", fs).ruleset, false, "automatic survives reloading")
T.eq(Save.optionsFor("red", fs).ruleset, "gen1_faithful", "roundtrip preserves shared explicit choice")

local Convert = require("src.save_convert.SaveConvert")
for generation = 1, 5 do
  local imported = Convert.mergeDefaults({ player = { map = "TEST", x = 1, y = 2 } }, nil, generation)
  T.eq(imported.options.ruleset, false, "cartridge import skeleton follows native default")
  local explicit = Convert.mergeDefaults({
    player = { map = "TEST", x = 1, y = 2 },
    options = { ruleset = "custom_rules" },
  }, nil, generation)
  T.eq(explicit.options.ruleset, "custom_rules", "import merge keeps explicit decoded settings")
end

local faithful = require("src.battle.rulesets.gen1_faithful")
local finite = require("src.battle.rulesets.gen2_finite_pp")
T.eq(faithful.enemyUnlimitedPP, true, "Gen-1 source table keeps unlimited enemy PP")
T.eq(finite.enemyUnlimitedPP, false, "Gen-2 compatibility rules track PP")
for key, value in pairs(faithful) do
  if key ~= "name" and key ~= "enemyUnlimitedPP" then
    T.eq(finite[key], value, "PP correction preserves other previous host rules: " .. key)
  end
end

local wanted = { "gen1_faithful", "gen2_finite_pp", "gen3_emerald", "gen4_platinum" }
for _, version in ipairs(V.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2], true)
    if f.gen <= 4 then
      -- Both old missing preferences and newly persisted AUTO must reach the
      -- same real battle constructor, including without loader-populated data.
      for _, choice in ipairs({ {}, { ruleset = false } }) do
        f.game.save.options = choice
        local b = f.fresh("TACKLE", { enemy = true })
        T.eq(b.battle.ruleset.name, wanted[f.gen], "native battle uses version default: " .. version)
        if f.gen <= 3 then
          b.move.pp = 1
          b.use()
          T.eq(b.pp(), f.gen == 1 and 1 or 0, "native default enemy PP is generation-correct")
          local action = b.battle:enemyAction()
          T.eq(action.id, f.gen == 1 and f.ids.TACKLE or "STRUGGLE", "AI follows default PP policy")
        end
      end
      f.game.save.options = { ruleset = "gen1_faithful" }
      local b = f.fresh("TACKLE", { enemy = true })
      T.eq(b.battle.ruleset.name, "gen1_faithful", "explicit legacy choice remains effective")
      b.move.pp = 0
      b.use()
      T.eq(b.pp(), 0, "explicit unlimited rule does not spend PP")
      T.eq(b.battle:enemyAction().id, f.ids.TACKLE, "explicit unlimited rule permits dry enemy move")
      f.game.save.options = { ruleset = "modern_clean" }
      b = f.fresh("TACKLE", { enemy = true })
      T.eq(b.battle.ruleset.name, "modern_clean", "explicit alternative remains effective")
      b.move.pp = 1
      b.use()
      T.eq(b.pp(), 0, "explicit finite rule spends PP")
      T.eq(b.battle:enemyAction().id, "STRUGGLE", "explicit finite rule reaches Struggle")
      f.game.save.options = { ruleset = false }
      f.data.rulesets.CUSTOM_RULE = { name = "CUSTOM_RULE", enemyUnlimitedPP = true }
      f.data.constants.defaultRuleset = "CUSTOM_RULE"
      T.eq(f.fresh("TACKLE").battle.ruleset.name, "CUSTOM_RULE", "cartridge/mod named default wins")
      f.game.save.options.ruleset = "modern_clean"
      T.eq(f.fresh("TACKLE").battle.ruleset.name, "modern_clean", "explicit choice wins over mod default")
      f.game.save.options.ruleset = "missing_id"
      T.eq(
        f.fresh("TACKLE").battle.ruleset.name,
        "CUSTOM_RULE",
        "unknown saved id falls back to named default"
      )
      f.data.constants.defaultRuleset, f.data.rulesets = nil, nil
      f.game.save.options.ruleset = false
      T.eq(f.fresh("TACKLE").battle.ruleset.name, wanted[f.gen], "no-loader fallback includes native rules")
    end
    f.close()
  end
end

V.set("gold")
local f = Fixture.new(".", "gen2", "gold", 3, "unified", true)
local Options = require("src.ui.OptionsMenu")
f.game.save.options = Save.defaultOptions()
local menu = Options.new(f.game)
local row
for _, candidate in ipairs(menu.rows) do
  if candidate.id == "ruleset" then
    row = candidate
  end
end
T.eq(row.value(f.game), "AUTO", "options show automatic rather than a misleading explicit id")
f.game.save.options.ruleset = nil
T.eq(row.value(f.game), "AUTO", "old missing preference shows automatic too")
f.game.save.options.ruleset = false
local hidden = { name = "hidden", hidden = true }
f.data.rulesets.HIDDEN = hidden
f.data.rulesets.auto = { name = "mod_auto", enemyUnlimitedPP = true }
f.game.save.options.ruleset = "auto"
T.eq(f.fresh("TACKLE").battle.ruleset.name, "mod_auto", "mod id auto is not reserved by the preference")
f.game.save.options.ruleset = false
local seen = {}
for _ = 1, 30 do
  row.step(f.game, 1)
  seen[f.game.save.options.ruleset] = true
  if f.game.save.options.ruleset == false then
    break
  end
end
T.eq(seen.HIDDEN, nil, "hidden mod rules are skipped")
T.eq(seen.gen2_finite_pp, true, "new compatibility rule is selectable")
T.eq(seen.auto, true, "mod id auto remains selectable")
T.eq(seen.gen1_faithful, true, "legacy explicit rule remains selectable")
T.eq(row.value(f.game), "AUTO", "full cycle returns to automatic")
row.step(f.game, -1)
T.check(f.game.save.options.ruleset ~= false, "left from automatic wraps to explicit rule")
row.step(f.game, 1)
T.eq(f.game.save.options.ruleset, false, "right returns to automatic")
f.close()

-- Native defaults must also apply after a brand-new save, not just synthetic
-- options = {}. Isolate the installation filesystem; no real options are read.
local previousFs = love.filesystem
love.filesystem = T.sdk.memfs({})
Save.forgetDataDir()
local save = Save.newGame({ version = "gold" })
T.eq(save.options.ruleset, false, "new save does not mask native default")
love.filesystem = previousFs
Save.forgetDataDir()
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local shared = Fixture.new(".", "gen2", version, 3, "unified", false, false, "portable_enemy_pp")
  dofile("tests/enemy_pp/cases.lua").run(shared)
  shared.close()
  for _, failing in ipairs({ false, true }) do
    local baseline =
      Fixture.new(".", "gen2", version, 3, "unified", not failing, failing, "portable_enemy_pp")
    if failing then
      T.check(#baseline.result.errors > 0, "intentional PP consumer entry failure is recorded")
    else
      T.eq(baseline.result.loader.exports.portable_enemy_pp, nil, "genuine no-mod PP consumer is absent")
    end
    for _, link in ipairs(require("src.mods.Runtime").hooks.chains["battle.enemy_action"] or {}) do
      T.check(link.owner ~= "portable_enemy_pp", "failed/no-mod consumer owns no AI wrappers")
    end
    local b = baseline.fresh("TACKLE", { enemy = true })
    b.move.pp = 1
    b.use()
    T.eq(b.pp(), 0, "no-mod/rollback native enemy spends last PP")
    T.eq(b.battle:enemyAction().id, "STRUGGLE", "no-mod/rollback retains real AI fallback")
    baseline.close()
  end
end
V.set(old)
T.finish("native automatic rulesets and finite enemy PP")
