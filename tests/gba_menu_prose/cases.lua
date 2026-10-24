local C = {}
function C.run(root, backend, version, api, format)
  local F = dofile(root .. "/tests/gba_menu_prose/fixture.lua")
  local rows = {}
  for _, mode in ipairs({
    "no-mod",
    "all",
    "controls",
    "foreign",
    "cancel-only",
    "take-only",
    "empty",
    "remove",
    "rollback",
  }) do
    local f = F.new(root, backend, version, mode, api, format)
    f.T.eq(#f.result.errors > 0, mode == "rollback", "menu-prose load outcome " .. mode)
    local native = f.actions()
    for i, role in ipairs(F.roles) do
      local base = "BASE_" .. role[2]:gsub(" ", "_")
      local expected = base
      if
        mode == "all"
        or mode == "controls"
        or mode == "cancel-only" and role[1] == "cancel"
        or mode == "take-only" and role[1] == "takeItem"
      then
        expected = "MOD_" .. role[2]:gsub(" ", "_")
        if mode == "controls" and role[1] == "summary" then
          expected = "A\nB\n\nC\n\nD"
        end
      elseif mode == "empty" then
        expected = ""
      end
      -- A removed cartridge override delegates to the imported native base.
      f.T.eq(native[i], expected, version .. "/" .. mode .. "/" .. role[1])
    end
    local footer = f.footer()
    f.T.eq(
      footer,
      (mode == "all" or mode == "controls" or mode == "empty" or mode == "remove") and "MOD_FOOTER"
        or "CANCEL",
      "separate native cancel button"
    )
    local row = { mode = mode, actions = native, footer = footer }
    if version == "firered" then
      row.itemPc = f.itemPc()
      local changed = mode == "all" or mode == "controls" or mode == "empty" or mode == "remove"
      f.T.same(
        row.itemPc,
        changed and { "MOD_PC_TITLE", "MOD_PC_WITHDRAW", "MOD_PC_GIVE", "MOD_FOOTER", "MOD_FOOTER" }
          or { "WITHDRAW ITEM", "WITHDRAW", "GIVE", "CANCEL", "CANCEL" },
        "actual native item-PC title/submenu/cancel"
      )
    end
    if f.e then
      f.T.raises(function()
        f.e.api.content.rom_text:override("gText_Withdraw", "LATE")
      end, "frozen", "late mutation rejected")
    end
    rows[#rows + 1] = row
    f.close()
  end
  return rows
end
return C
