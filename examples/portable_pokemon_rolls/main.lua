local mod = ...
local e = mod.exports
e.api, e.mode, e.calls, e.observations = mod, mod:read("case.txt") or "force", {}, {}
local supported = mod.supports and mod:supports("hooks", "shiny.roll")
  or (not mod.supports and (mod.generation == 2 or mod.generation == 3))
e.available = supported == true
if not supported then
  return
end
local function observe(name, ctx)
  e.calls[name] = (e.calls[name] or 0) + 1
  e.observations[name] = {
    species = ctx.species,
    defId = ctx.def and ctx.def.id,
    level = ctx.level,
    ratio = ctx.ratio,
    personality = ctx.personality,
    ivs = ctx.ivs and {
      hp = true,
      atk = ctx.ivs.atk ~= nil,
      def = ctx.ivs.def ~= nil,
      spe = ctx.ivs.spe ~= nil,
      spa = ctx.ivs.spa ~= nil,
      spd = ctx.ivs.spd ~= nil,
    },
    dvs = ctx.dvs and {
      attack = ctx.dvs.attack,
      defense = ctx.dvs.defense,
      speed = ctx.dvs.speed,
      special = ctx.dvs.special,
    },
  }
end
local function wrap(name)
  return mod.hooks:wrap(name, function(next, ctx)
    observe(name, ctx)
    local shiny = name == "shiny.roll"
    if e.mode == "force" then
      if shiny then
        return true
      else
        return "female"
      end
    end
    if e.mode == "suppress" then
      if shiny then
        return false
      else
        return "male"
      end
    end
    if e.mode == "nil" then
      return nil
    end
    if e.mode == "invalid" then
      if shiny then
        return 0
      else
        return "invalid"
      end
    end
    if e.mode == "error_before" then
      error("intentional roll failure before next")
    end
    if e.mode == "invalid_threshold" and not shiny then
      ctx.def.genderRatio = 254
      return "invalid"
    end
    if e.mode == "ratio_only" then
      ctx.ratio = 254
    end
    if e.mode == "new_threshold" and not shiny then
      local replaced = {}
      for k, v in pairs(ctx) do
        replaced[k] = v
      end
      replaced.def = { genderRatio = 254 }
      return next(replaced)
    end
    if e.mode == "iv_edit" and ctx.ivs then
      ctx.ivs.hp = 31
    end
    if e.mode == "replacement" then
      local replaced = {}
      for k, v in pairs(ctx) do
        replaced[k] = v
      end
      if ctx.dvs then
        replaced.dvs = { attack = 2, defense = 10, speed = 10, special = 10 }
      else
        replaced.personality = 0
        if shiny then
          replaced.otId, replaced.otSecretId = 0, 0
        end
      end
      return next(replaced)
    end
    if e.mode == "steer" then
      if ctx.dvs then
        ctx.dvs.attack, ctx.dvs.defense, ctx.dvs.speed, ctx.dvs.special = 2, 10, 10, 10
      elseif shiny then
        ctx.personality, ctx.otId, ctx.otSecretId = 0, 0, 0
      else
        ctx.personality = 0
      end
    elseif e.mode == "threshold" and not shiny then
      ctx.def.genderRatio = 254
    end
    local result = next(ctx)
    if e.mode == "error_after" then
      error("intentional roll failure after next")
    end
    return result
  end)
end
e.stopShiny, e.stopGender = wrap("shiny.roll"), wrap("gender.roll")
