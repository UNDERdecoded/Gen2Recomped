return function(mod)
  mod.exports.executed = true
  mod.exports.payload = assert(mod:read("payload.txt"))
  mod.content.items:patch("FIX_POTION", { price = 271 })
end
