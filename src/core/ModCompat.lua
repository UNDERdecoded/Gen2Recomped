-- Module-name aliases for mods written against the Gold port's layout.
--
-- The Gen 2 mod ecosystem grew up around a build that splits its engine by
-- generation -- `src.world.gen2.Player`, `src.ui.gen2.StartMenu`,
-- `src.core.gen2.Boxes` -- while this engine keeps ONE module per concept and
-- lets the Gen 1 and Gen 2 paths share it.  Same class, same contract,
-- different spelling.
--
-- With no translation a mod like STADIUM2_OVERWORLD_MODELS loads, registers
-- its options and its render pipelines, and then reports
--
--   Gold/Silver voxel renderer provider failed:
--     module 'src.world.gen2.Player' not found
--
-- and draws nothing at all -- which reads to a player as "the mod is broken",
-- when every part of it that this engine can actually satisfy is fine.
--
-- ------- what is and is not in here
--
-- ONLY pairs where the two names denote the same thing.  A guess that resolves
-- is worse than a require that fails: the mod guards every one of these with
-- pcall and degrades cleanly when one is absent (that is how a feature this
-- engine has no equivalent for is supposed to switch itself off), whereas a
-- wrong target hands it a table with the wrong contract and the failure moves
-- somewhere far away from the cause.
--
-- Deliberately ABSENT, because this engine has no equivalent module and the
-- honest answer is "not found":
--
--   src.world.gen2.FieldMoves   field-move entry points live in
--                               src/script/* and the fieldmove.eligibility
--                               hook, not one module
--   src.world.gen2.Follower     PikachuFollower is Yellow's, not a general
--                               party follower
--   src.ui.gen2.Chrome          no shared window-chrome module
--   src.ui.gen2.SaveMenu        the save flow is part of StartMenu here
--   src.ui.gen2.BattleAnimView  Gen2AnimPlayer is a player, not a view
--   src.battle.UIVisibility     no equivalent
--   src.ui.PartyPanel           no equivalent
--
-- Each of those turns one optional feature off in the mod and says so in the
-- log, which is the outcome we want.

local Logger = require("src.core.Logger")

local ModCompat = {}

ModCompat.ALIASES = {
  -- the overworld: the player class the voxel renderers pose every frame,
  -- the state that owns the map, and the tile/collision tables
  ["src.world.gen2.Player"] = "src.world.Player",
  ["src.world.gen2.World"] = "src.world.OverworldController",
  ["src.world.gen2.Map"] = "src.world.Map",
  ["src.world.gen2.Permissions"] = "src.world.Collision",
  ["src.world.gen2.Palettes"] = "src.render.PaletteFX",

  -- save-side data
  ["src.core.gen2.Boxes"] = "src.pokemon.Boxes",
  ["src.core.gen2.BugContest"] = "src.world.BugContest",
  ["src.core.gen2.ItemEffects"] = "src.inventory.ItemEffects",
  ["src.core.gen2.Save"] = "src.core.SaveData",

  -- battle
  ["src.battle.gen2.Catching"] = "src.battle.Catching",
  ["src.battle.gen2.Mon"] = "src.pokemon.Pokemon",
  ["src.ui.gen2.BattleState"] = "src.battle.BattleState",

  -- menus.  The Gold port names two of these differently rather than
  -- namespacing them, so both spellings land on the one implementation.
  ["src.ui.gen2.StartMenu"] = "src.ui.StartMenu",
  ["src.ui.gen2.OptionsMenu"] = "src.ui.OptionsMenu",
  ["src.ui.gen2.PartyMenu"] = "src.ui.PartyMenu",
  ["src.ui.gen2.PokedexMenu"] = "src.ui.PokedexMenu",
  ["src.ui.gen2.SummaryMenu"] = "src.ui.SummaryMenu",
  ["src.ui.gen2.TrainerCard"] = "src.ui.TrainerCard",
  ["src.ui.gen2.Pokegear"] = "src.ui.PokegearMenu",
  ["src.ui.gen2.PackMenu"] = "src.ui.BagMenu",
  ["src.menu.PartyMenu"] = "src.ui.PartyMenu",
  ["src.ui.PartyScreen"] = "src.ui.PartyMenu",
  ["src.ui.party.PartyScreen"] = "src.ui.PartyMenu",

  -- the Gold port splits its Game class per generation; this one does not
  ["src.core.Game2"] = "src.core.Game",
  ["src.render.GbcPalette"] = "src.render.GBCFX",
}

local seen = {}
local installed = false

-- Resolve one alias.  Returns the module, or nil plus a reason -- the reason
-- matters because "the target is missing too" is a build problem, not a mod
-- problem, and should not be reported as an unknown module.
function ModCompat.resolve(name)
  local target = ModCompat.ALIASES[name]
  if not target then return nil, nil end
  local ok, value = pcall(require, target)
  if not ok then return nil, tostring(value) end
  if not seen[name] then
    seen[name] = true
    Logger.info("mod compat: %s -> %s", name, target)
  end
  return value
end

-- A package searcher rather than a require wrapper: the aliased name has to
-- work from anywhere, including inside an engine module a mod has already
-- patched, and it has to populate package.loaded so BOTH spellings end up
-- holding the SAME table.  A mod that adds a method to
-- src.world.gen2.Player is adding it to src.world.Player, which is the whole
-- point -- the engine has to see the patch.
function ModCompat.install()
  if installed then return false end
  local loaders = package.loaders or package.searchers
  if type(loaders) ~= "table" then return false end
  loaders[#loaders + 1] = function(name)
    if not ModCompat.ALIASES[name] then
      -- the standard "not found" contract: a string the require error joins
      return "\n\tno mod-compat alias for '" .. tostring(name) .. "'"
    end
    return function()
      local value, why = ModCompat.resolve(name)
      if value == nil then
        error(("mod-compat alias %s -> %s failed: %s")
          :format(name, ModCompat.ALIASES[name], tostring(why)), 0)
      end
      return value
    end
  end
  installed = true
  return true
end

function ModCompat._resetForTests()
  installed = false
  seen = {}
end

return ModCompat
