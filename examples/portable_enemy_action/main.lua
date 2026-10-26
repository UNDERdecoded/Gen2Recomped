return function(mod)
  local choice
  mod.hooks:wrap("battle.enemy_action", function(nextAction, ...)
    if choice then
      return choice(nextAction, ...)
    end
    return nextAction(...)
  end)
  mod.exports.choose = function(callback)
    choice = callback
  end
  mod.exports.api = mod
end
