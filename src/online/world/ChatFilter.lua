-- An optional chat filter for worlds (docs/online-design.md 2.8 "chat":
-- "profanity filter optional").  The HOST runs it on every line before it
-- forwards it, so a modified client cannot get around it.  On by default in
-- a PUBLIC world, off in a friends' world; WorldHost.filterChat overrides.
--
--   ChatFilter.censor(text) -> text with each offending word starred, changed
--   ChatFilter.contains(text) -> bool
--
-- WORD BY WORD, never across the line: each word is lower-cased, leetspeak
-- is read back to letters (4->a, 3->e, 0->o, $->s ...), letters tripled or
-- more collapse ("fuuuck"), and then the word must BE a listed word -- so
-- "Scunthorpe", "class", "Dickens" and "peacock" pass.  A short ROOTS list
-- (stems no ordinary English word contains) also matches inside a longer
-- word.
-- The word list is the one the legacy gen2online mod shipped
-- (mods/gen2recomped-online/other/profanity.lua).  Pure.

local ChatFilter = {}

ChatFilter.WORDS = {
  "ashole", "asshole", "assholes", "b1tch", "badass", "bastard", "bastards",
  "bitch", "bitchass", "bitches", "bitching", "blowjob", "boobs", "btch",
  "bullshit", "chink", "cock", "cocks", "cocksucker", "cum", "cumshot",
  "cunt", "cunts", "dick", "dickhead", "dicks", "dildo", "dumbass", "fag",
  "faggot", "faggots", "fags", "fak", "fatass", "fck", "fgt", "fuc", "fuck",
  "fucked", "fucker", "fuckhead", "fucking", "fuk", "gook", "handjob",
  "hentai", "jackass", "kike", "motherfucker", "n1gga", "n1gger", "nigga",
  "niggas", "niggaz", "nigger", "niggers", "nude", "nudes", "pedo",
  "pedophile", "penis", "porn", "porno", "prick", "pussies", "pussy", "pusy",
  "rape", "rapist", "retard", "retarded", "shit", "shithead", "shitting",
  "shitty", "shtt", "shyt", "slut", "sluts", "slutty", "spic", "tard",
  "tits", "titties", "tranny", "twat", "vagina", "wanker", "wetback", "whor",
  "whore", "whores",
}

ChatFilter.EXACT = { "ass", "asses", "damn", "dammit", "hell", "sex", "tit", "kys" }

-- matched inside a longer word too
ChatFilter.ROOTS = { "fuck", "shit", "bitch", "nigg", "fagg", "whore" }

local LIST = {}
for _, w in ipairs(ChatFilter.WORDS) do LIST[w] = true end
for _, w in ipairs(ChatFilter.EXACT) do LIST[w] = true end

local LEET = {
  ["@"] = "a", ["4"] = "a", ["8"] = "b", ["("] = "c", ["<"] = "c", ["3"] = "e",
  ["6"] = "g", ["9"] = "g", ["#"] = "h", ["1"] = "i", ["!"] = "i", ["|"] = "i",
  ["0"] = "o", ["5"] = "s", ["$"] = "s", ["7"] = "t", ["+"] = "t",
}

local function norm(word)
  local t = {}
  local lower = word:lower()
  for i = 1, #lower do
    local ch = lower:sub(i, i)
    t[#t + 1] = LEET[ch] or ch
  end
  local s = table.concat(t):gsub("[^%a]", "")
  -- a letter three or more times in a row counts once (Lua patterns cannot
  -- quantify a back-reference, so this walks the word)
  local out, last, run = {}, nil, 0
  for i = 1, #s do
    local ch = s:sub(i, i)
    if ch == last then run = run + 1 else last, run = ch, 1 end
    out[#out + 1] = ch
    if run == 3 then
      out[#out] = nil
      out[#out] = nil
    elseif run > 3 then
      out[#out] = nil
    end
  end
  return table.concat(out)
end
ChatFilter.normalize = norm

function ChatFilter.bad(word)
  local w = norm(word)
  if w == "" then return false end
  if LIST[w] then return true end
  -- a doubled letter collapsed once more ("fuuck" -> "fuck")
  local single = w:gsub("(%a)%1", "%1")
  if LIST[single] then return true end
  for _, r in ipairs(ChatFilter.ROOTS) do
    if w:find(r, 1, true) then return true end
  end
  return false
end

function ChatFilter.contains(text)
  for word in tostring(text or ""):gmatch("%S+") do
    if ChatFilter.bad(word) then return true end
  end
  return false
end

function ChatFilter.censor(text)
  text = tostring(text or "")
  local changed = false
  local out = text:gsub("%S+", function(word)
    if ChatFilter.bad(word) then
      changed = true
      return ("*"):rep(math.max(3, math.min(8, #word)))
    end
    return word
  end)
  return out, changed
end

return ChatFilter
