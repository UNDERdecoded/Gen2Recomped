-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Owned, minimal SDAT/SSEQ/SBNK/SWAR bytes, with all three voice kinds.
return function(format, looping)
  local b = {}
  for n = 1, 2048 do
    b[n] = 0
  end
  local function byte(at, n)
    b[at + 1] = n % 256
  end
  local function word(at, n, size)
    for i = 0, (size or 4) - 1 do
      byte(at + i, n)
      n = math.floor(n / 256)
    end
  end
  local function text(at, s)
    for n = 1, #s do
      byte(at + n - 1, s:byte(n))
    end
  end
  text(0, "SDAT")
  word(24, 64)
  word(32, 512)
  word(40, 1024)
  word(64 + 8, 48)
  word(64 + 16, 64)
  word(64 + 20, 80)
  for _, r in ipairs({ { 112, 128 }, { 128, 144 }, { 144, 160 } }) do
    word(r[1], 1)
    word(r[1] + 4, r[2])
  end
  word(192, 0, 2)
  word(196, 0, 2)
  byte(198, 127)
  word(208, 1, 2)
  word(212, 0, 2)
  word(214, 65535, 2)
  word(216, 65535, 2)
  word(218, 65535, 2)
  word(224, 2, 2)
  local events =
    { 199, 0, 129, 0, 225, 120, 0, 176, 0, 3, 0, 60, 120, 40, 129, 1, 64, 110, 20, 129, 2, 67, 100, 10, 128, 50, 177, 0, 2, 0 }
  if looping then
    events[#events + 1] = 148
    events[#events + 1] = 0
    events[#events + 1] = 0
    events[#events + 1] = 0
  else
    events[#events + 1] = 255
  end
  text(1024, "SSEQ")
  word(1024 + 24, 28)
  for n, v in ipairs(events) do
    byte(1024 + 28 + n - 1, v)
  end
  text(1200, "SBNK")
  word(1200 + 56, 3)
  for i = 0, 2 do
    byte(1200 + 60 + i * 4, i + 1)
    word(1200 + 61 + i * 4, 80 + i * 10, 2)
    local at = 1200 + 80 + i * 10
    word(at, i == 0 and 0 or 3, 2)
    word(at + 2, 0, 2)
    byte(at + 4, 60)
    byte(at + 9, 64)
  end
  text(1400, "SWAR")
  word(1400 + 56, 1)
  word(1400 + 60, 64)
  local at = 1464
  byte(at, format or 0)
  byte(at + 1, 1)
  word(at + 2, 16384, 2)
  word(at + 6, 1, 2)
  word(at + 8, 31)
  for n = 0, 127 do
    byte(at + 12 + n, math.floor(math.sin(n * 0.17) * 100))
  end
  if format == 2 then
    word(at + 12, 0, 2)
    word(at + 14, 0, 2)
  end
  for i, r in ipairs({ { 1024, 28 + #events }, { 1200, 128 }, { 1400, 204 } }) do
    word(512 + 12 + (i - 1) * 16, r[1])
    word(512 + 16 + (i - 1) * 16, r[2])
  end
  local out = {}
  for n = 1, #b do
    out[n] = string.char(b[n])
  end
  return table.concat(out)
end
