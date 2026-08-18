-- A pipeline with no stored preference must keep the level it has.
--
-- applyOptions wiped `levels` and read every id out of the saved bucket with
-- `or 0`, so a pipeline the player had never touched was forced OFF -- even
-- one a mod had switched on for itself at registration, which is the only way
-- a mod can ship a pipeline enabled by default.
--
-- STADIUM2_OVERWORLD_MODELS drives its entire wild-Pokemon AI from a
-- pipeline's `present` callback, and `present` only runs while the level is
-- above zero.  So its Pokemon spawned, never ticked, never moved, never made
-- contact and never started a battle -- with nothing in any log, because
-- nothing had failed.
love = require("tests.love_stub")
package.path = "./?.lua;./?/init.lua;" .. package.path

local pass, fail = 0, 0
local function check(name, got, want)
  if got == want then pass = pass + 1
  else fail = fail + 1 print(("  FAIL %-56s got %s want %s")
    :format(name, tostring(got), tostring(want))) end
end

local Pipelines = require("src.render.Pipelines")

local DEFS = {
  -- the mod's AI driver: present-only, no stored preference, on by default
  owwild_behavior_tick = { label = "WILDS AI", levels = { "OFF", "ON" },
                           priority = 1, present = function(c) return c end },
  -- a world pipeline the player HAS configured
  voxel = { label = "VOXEL", levels = { "OFF", "15", "35", "50" },
            priority = 20, drawWorld = function() return nil end },
  -- a post-process the player switched off on purpose
  tiltshift = { label = "TILT SHIFT", levels = { "OFF", "1", "2", "3" },
                priority = 10, present = function(c) return c end },
}
Pipelines.install({ render_pipelines = DEFS })

-- ------- the exact reproduction
do
  Pipelines.reset()
  -- the mod switches its own pipeline on when it registers
  Pipelines.setLevel("owwild_behavior_tick", 1)
  check("the mod turned it on", Pipelines.level("owwild_behavior_tick"), 1)
  -- ...then the engine restores the player's saved options, which have never
  -- heard of it (this is the user's real options.lua bucket)
  Pipelines.applyOptions({ pipelines = { voxel = 4, tiltshift = 3,
                                         stadium2_battle_clock = 0 } })
  check("and it survives the restore", Pipelines.level("owwild_behavior_tick"), 1)
  check("so its present callback can run",
        Pipelines.eligible("owwild_behavior_tick"), true)
end

-- ------- a stored preference still wins outright, either way
do
  Pipelines.reset()
  Pipelines.setLevel("owwild_behavior_tick", 1)
  Pipelines.applyOptions({ pipelines = { owwild_behavior_tick = 0 } })
  check("an explicit OFF is honoured", Pipelines.level("owwild_behavior_tick"), 0)
  check("and it is not eligible", Pipelines.eligible("owwild_behavior_tick"), false)

  Pipelines.reset()
  Pipelines.applyOptions({ pipelines = { tiltshift = 3 } })
  check("an explicit level is restored", Pipelines.level("tiltshift"), 3)
end

-- ------- nothing set anywhere is still OFF
do
  Pipelines.reset()
  Pipelines.applyOptions({ pipelines = {} })
  check("no mod default, no stored value -> off",
        Pipelines.level("owwild_behavior_tick"), 0)
  Pipelines.reset()
  Pipelines.applyOptions(nil)
  check("a missing options table is survivable",
        Pipelines.level("owwild_behavior_tick"), 0)
end

-- ------- the world-pipeline rules are untouched
do
  Pipelines.reset()
  Pipelines.applyOptions({ pipelines = { voxel = 3 } })
  check("a stored world level restores", Pipelines.level("voxel"), 3)
  check("clamped to the ladder", Pipelines.maxLevel("voxel"), 3)
  Pipelines.reset()
  Pipelines.applyOptions({ pipelines = { voxel = 99 } })
  check("an out-of-range level is clamped", Pipelines.level("voxel"), 3)
  Pipelines.reset()
  Pipelines.applyOptions({ pipelines = { voxel = -5 } })
  check("a negative level floors at off", Pipelines.level("voxel"), 0)
end

-- ------- a live level cannot smuggle a SECOND world pipeline on
do
  -- a FRESH defs table: list() memoizes on the table's identity, so mutating
  -- the one already installed would be served from the cache
  local defs2 = {}
  for k, v in pairs(DEFS) do defs2[k] = v end
  defs2.stadium2_gold_voxel = { label = "STADIUM 2 VOXEL WORLD",
    levels = { "OFF", "ON" }, priority = 1100,
    drawWorld = function() return nil end }
  Pipelines.install({ render_pipelines = defs2 })
  Pipelines.setLevel("stadium2_gold_voxel", 1)
  Pipelines.applyOptions({ pipelines = { voxel = 3 } })
  local a = Pipelines.level("stadium2_gold_voxel")
  local b = Pipelines.level("voxel")
  check("only one world pipeline ends up on", (a > 0 and b > 0), false)
  check("and the higher priority one keeps it", a, 1)
  Pipelines.install({ render_pipelines = DEFS })
end

-- ------- syncOptions still writes every live level back
do
  Pipelines.reset()
  Pipelines.setLevel("owwild_behavior_tick", 1)
  local opts = { pipelines = {} }
  Pipelines.syncOptions(opts)
  check("the level is persisted once written",
        opts.pipelines.owwild_behavior_tick, 1)
end

print(("pipeline defaults: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
