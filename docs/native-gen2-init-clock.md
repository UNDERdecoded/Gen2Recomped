# Native Gen2 initial clock and weekday selection

Gold, Silver and Crystal now open their native Oak speech with an
`init_clock` step. This opens `Gen2InitClock` before the professor's welcome
and music. The required hour and minute pickers wrap in both directions,
retain their selection after NO, read the complete time back, and commit to
the shared saved RTC only after the final acknowledgement. Completion resumes
the original Oak parent once. Other Gen2 introductions keep their existing
step list.

The native `SetDayOfWeek` special uses the same screen in day mode. It opens
on Sunday and remains suspended through selection and confirmation. NO
returns to the chosen value without writing the save or resuming the script;
YES writes through `Gen2Clock.setWeekday` and resumes the original runner once.

`src.ui.gen2.InitClock` resolves to this actual native screen. Its constructor
accepts mode, save, hour/minute/day, onDone and autoConfirm options. Common
hour/time/response formatting helpers use the native clock labels. Native
TextBox and ChoiceBox own text paging, typing and YES/NO input; the clock
screen owns picker state, transitions, save commitment and optional fades.

Dialogue is read from the active imported native text bank. Native wrapper
and underscore text spellings are supported; short engine prompts are used
only if an older cache lacks a line. No ROM dialogue, artwork, palette or
coordinate table is embedded in the implementation. The current panel layout
is engine-owned. This is not a claim of exact reference raster/layout helper
parity; the remaining reference drawing/metadata helpers and original clock
art require separate work.

ROM-free coverage exercises the actual native widgets and stack, wrapped
selection and NO retries, final acknowledgement, save-codec retention, the
real special compiler/ScriptRunner yield/resume, the real Oak step and loaded
native API1/2 clients. These tests do not establish fresh
GPU or complete natural new-game/story acceptance. Manual DST dialogs/checks,
SRAM RTC conversion, broader story/hardware acceptance and full VASC/Gen1
parity remain open. Private VASC code and protected Gen1/player instances are
unchanged.
