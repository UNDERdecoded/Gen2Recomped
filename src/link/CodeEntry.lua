-- Shared 6-slot room-code entry widget: the digit-scrub interaction
-- LinkState's own `ipDigits`/`addrPos` already uses for IP entry, over the
-- Crockford-32-style alphabet pokeserver room/tournament codes are drawn
-- from (23456789ABCDEFGHJKMNPQRSTUVWXYZ -- no 0/O/1/I/L, so a code read
-- aloud or handwritten never has to be checked twice).

local CodeEntry = {}

CodeEntry.CHARSET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
CodeEntry.LENGTH = 6

function CodeEntry.new()
  local chars = {}
  for i = 1, CodeEntry.LENGTH do chars[i] = 1 end -- index into CHARSET, 1-based
  return { chars = chars, pos = 1 }
end

local N = #CodeEntry.CHARSET

function CodeEntry.up(state)
  state.chars[state.pos] = state.chars[state.pos] % N + 1
end

function CodeEntry.down(state)
  state.chars[state.pos] = (state.chars[state.pos] - 2) % N + 1
end

function CodeEntry.left(state)
  state.pos = math.max(1, state.pos - 1)
end

function CodeEntry.right(state)
  state.pos = math.min(CodeEntry.LENGTH, state.pos + 1)
end

function CodeEntry.text(state)
  local out = {}
  for i = 1, CodeEntry.LENGTH do
    out[i] = CodeEntry.CHARSET:sub(state.chars[i], state.chars[i])
  end
  return table.concat(out)
end

return CodeEntry
