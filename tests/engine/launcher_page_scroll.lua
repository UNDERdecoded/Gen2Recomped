-- Launcher page scroll (src/import/RomImporter.lua): the column under the tab
-- bar -- panel, updater banner, footer -- scrolls as one when the window is too
-- short to hold it.  Before this, a stacked single-column layout on a narrow
-- window ran under a footer pinned to the window bottom, and the part below the
-- fold could not be reached at all.  The arithmetic is pure, so pin it here
-- rather than in a screenshot.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local RomImporter = require("src.import.RomImporter")

local pageScrollFor = RomImporter.pageScrollFor

-- ------------------------------------------------------------- fits: inert
local paged, scroll, maxPage = pageScrollFor(400, 600, 0)
T.eq(paged, false, "a column shorter than the viewport does not scroll")
T.eq(maxPage, 0, "and has nowhere to scroll to")
T.eq(scroll, 0, "and sits at the top")

-- An exact fit is still not a scroll: one pixel of slack would show a thumb
-- for nothing and put the wheel on the page instead of the slot list.
paged, _, maxPage = pageScrollFor(600, 600, 0)
T.eq(paged, false, "a column exactly as tall as the viewport does not scroll")
T.eq(maxPage, 0, "an exact fit has no scroll extent")

-- --------------------------------------------------------- overflows: scrolls
paged, scroll, maxPage = pageScrollFor(900, 600, 0)
T.eq(paged, true, "a column taller than the viewport scrolls")
T.eq(maxPage, 300, "the extent is exactly the overflow")
T.eq(scroll, 0, "a fresh page starts at the top")

-- The bottom of the travel shows the footer: the whole overflow is reachable,
-- which is the point of the change (#footer under the fold).
_, scroll = pageScrollFor(900, 600, 300)
T.eq(scroll, 300, "the offset can reach the end of the column")
_, scroll = pageScrollFor(900, 600, 5000)
T.eq(scroll, 300, "an offset past the end clamps to it")
_, scroll = pageScrollFor(900, 600, -40)
T.eq(scroll, 0, "an offset above the top clamps to it")

-- ------------------------------------------------------- the window grows back
-- Resizing taller has to pull the page back down with it; leaving the offset
-- where it was would park the content above the viewport with no way back.
_, scroll, maxPage = pageScrollFor(900, 800, 300)
T.eq(maxPage, 100, "a taller window leaves less to scroll")
T.eq(scroll, 100, "and drags a deeper offset back to the new end")
paged, scroll = pageScrollFor(900, 900, 300)
T.eq(paged, false, "growing past the content stops the scrolling")
T.eq(scroll, 0, "and returns the page to the top")

-- ---------------------------------------------------------------- degenerate
-- draw() computes the viewport from the window height, so a window smaller than
-- the pinned header hands this a negative number; it must not become extra
-- travel.
_, _, maxPage = pageScrollFor(500, -120, 0)
T.eq(maxPage, 500, "a negative viewport counts as no room, not as more of it")
paged, scroll, maxPage = pageScrollFor(nil, nil, nil)
T.eq(paged, false, "a first frame with nothing measured yet does not scroll")
T.eq(scroll, 0, "and sits at the top")
T.eq(maxPage, 0, "with no extent")

T.finish("launcher page scroll")
