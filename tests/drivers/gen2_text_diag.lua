-- Driver: does a Gen2 dialogue box actually stop at its page breaks?
--
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_text_diag.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local Commands = require("src.script.Commands")

  U.newGame(game)
  U.wait(30)

  local sample = game.data.text.TEXT_S41_5624
  U.log("sample", (tostring(sample):gsub("\n", "<n>"):gsub("\v", "<CONT>")
    :gsub("\f", "<PARA>")))

  -- straight construction: does paginate see the breaks?
  local box = TextBox.new(game, sample, function() U.log("box onDone") end)
  U.log("pages", tostring(#box.pages))
  for i, page in ipairs(box.pages) do
    U.log("  page " .. i, table.concat(page, " | "))
  end

  -- push it and let it run with NO input at all
  game.stack:push(box)
  local sawWait, frames = false, 0
  for i = 1, 900 do
    frames = i
    if game.stack:top() ~= box then break end
    if box.waiting then sawWait = true end
    U.wait(1)
  end
  U.log("no-input result: waited=" .. tostring(sawWait)
    .. " stillUp=" .. tostring(game.stack:top() == box)
    .. " pageIndex=" .. tostring(box.pageIndex)
    .. " frames=" .. frames)
  while game.stack:top() ~= game.overworld do game.stack:pop() end
  U.wait(5)

  -- and through the script path, which is how the game shows it
  local ow = game.overworld
  local rows = require("src.script.Gen2ScriptVM").compile(game.data, "S41_41E1")
  if rows then
    game.save.g2SpecialCallActive = 3
    ow.runner:run(rows)
    local sawBox, boxPages = false, 0
    for _ = 1, 600 do
      local top = game.stack:top()
      if getmetatable(top) == TextBox then
        sawBox = true
        boxPages = #top.pages
        U.log("script box: pages=" .. boxPages
          .. " waiting=" .. tostring(top.waiting)
          .. " done=" .. tostring(top.done))
        break
      end
      U.wait(1)
    end
    U.log("script pushed a box", tostring(sawBox))
    for _ = 1, 600 do
      if not ow.runner:isRunning() then break end
      U.wait(1)
    end
    U.log("runner finished without input", tostring(not ow.runner:isRunning()))
  end

  U.log("done")
  love.event.quit()
end
