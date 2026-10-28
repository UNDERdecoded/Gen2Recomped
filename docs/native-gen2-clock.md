# Shared native Gen2 RTC

The Pokégear previously displayed elapsed play time while world palettes,
object time masks and script variables used the host clock. The native
`Gen2Clock` now provides the same saved RTC-base reads to these consumers,
and the native happiness evolution gate.
The existing `src.core.gen2.Clock` name resolves to this native module.
`world.hour()`, `world.minute()` and `world.weekday()` read that same save.

`setTime(save, hour, minute)` anchors the chosen minute, current game
weekday and calendar date to elapsed RTC seconds. Hours, weekdays and daily
calendar identity cross the same in-game midnight, including after a saved
session has been closed for days. Automatic host DST and time-zone changes do
not add another hour to a clock the player already set. Explicit system clock
adjustments still affect the host RTC; this is not a monotonic stopwatch.

The legacy `rtc.startMinute`, `rtc.startDay` and `g2DayOffset` projections are
retained for older readers. New writes also store `anchorTime`, `anchorMinute`,
`anchorDay` and `anchorDate` in the same `save.rtc` record. Consumers should use
the native setters/readers instead of mutating these projections directly.
`setWeekday` edits the current game weekday without changing elapsed calendar
age. Editing time reanchors the clock without resetting its current date.

Old saves without the elapsed anchor retain their original host-hour and
weekday-offset semantics, including their old midnight relationship, until
the clock is explicitly set. Read calls never create or migrate clock data.
Invalid/non-finite writes are rejected. The normal native save codec retains
both formats; elapsed play time is separate.

`calendarDate(save, now)` and `dateKey(save, now)` give native daily and weekly
services the calendar belonging to that RTC. Daily flags/fruit use and the
lottery now expire on game midnight and the selected game Friday instead of
an unrelated host-calendar boundary. The optional timestamp on clock reads
uses the same snapshot for minute, weekday and calendar queries.

World palettes, object-load period bits and `VAR_HOUR` share the saved hour;
the normal object-load freeze still applies. An explicit palette-query hour
retains precedence. The existing `world.tod` hook remains a presentation
override and does not rewrite the saved RTC. A raw scene-clock query uses
the current native save, independently of a room's forced palette.
`PokegearMenu:clockParts()` exposes hour/minute/one-based UI weekday from
the live native world or shared saved clock. The built-in card and external
presenters use this same getter, retaining authored card-clock overrides.
This prevents an external presenter from showing its fallback zero clock
while the internal RTC and built-in text are already correct.
AUTO neighbours share the effective clock presentation while the entered
map also follows AUTO. From a pinned room/cave, an AUTO neighbour instead
uses the saved RTC; that room's unused world-TOD hook is not a neighbour
palette override. This keeps explicit native/external hour queries aligned.

`clock.day_changed` is produced by actual weekday reads, including the live
world clock poll. It reports `day`, `previous` and `reason` (`rollover` or
`set`). A save's first observation is silent. Observations are per save,
reentrant-safe, subscription-aware and retired on mod/edition reload. An
observed offline whole week still produces one change, even when the weekday
number is the same; its calendar date is different.
Native API 1/2 use the existing event dispatch boundary. The native GSC
producer remains generation-scoped.

The clock card, native script readers, evolution time gate and world methods
are exercised directly in synthetic engine tests, including minute wrap,
weekly rollover, save roundtrip, RTC-versus-play-time display, the native callback
path and actual mod loading. Graphics IO alone is replaced for the clock
card. These checks do not establish a complete original-story clock-setting
sequence, manual DST-setting/check dialogs, battery-backed SRAM RTC
conversion, all daily services or fresh GPU acceptance for this change.
Automatic host DST isolation is covered; the original story clock-setting
screen now has a native implementation described in
[native-gen2-init-clock.md](native-gen2-init-clock.md); fresh original-story/GPU
acceptance and the remaining manual DST lifecycle are separately gated.

The public contract is compared with the read-only Gen1Recomp reference;
the implementation is native fork code. No VASC implementation, private
assets, game text or ROM-derived clock data is included.
