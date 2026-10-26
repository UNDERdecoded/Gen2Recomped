local M = {}
function M.run(root, backend, version)
  return dofile(root .. "/tests/enemy_actions/battle_effect_presentation.lua").run(root, backend, version, {
    names = { "SUBSTITUTE_FADE" },
    kinds = { "ordinary", "substitute", "lowered-substitute", "hidden", "hidden-mon", "no-substitute" },
  })
end
return M
