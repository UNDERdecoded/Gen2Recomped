# Native GBA Substitute presentation

This controller accompanies native Mirror Move received-history support.
Gen1 remains a clean read-only reference at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.

## Implemented

Surviving move-animation rows receive their native Substitute-to-Pokemon and
Pokemon-to-Substitute commands. Each called move owns its own animation group.
Ordinary multi-hit moves lower once and restore only when the native last-hit
command is reached; early termination does not invent a restore command.

The actual battle queue executes the offscreen exchange controller, including
five-pixel movement ticks, the separate exchange tick and the return trip.
Presentation is independent of gameplay Substitute HP. Animation options retain
the Transform/Substitute exceptions. Skipped commands add no waiting tick.
The renderer's sprite selection and native OAM Y consult that presentation;
queue completion clears its transient state. Legacy battles retain their path.

## Controller evidence and retained failures

- The first 1,920 complete Mirror Move observations now match unchanged Gen1,
  including all previously differing 144 animation command streams.
- The native sequencer/VM and actual host queue agree on all 360 controller
  inputs and all 5,240 observed ticks. Both versions cover all six single/double
  battler slots, animation options, ordinary/Transform/Substitute contexts,
  lowering, restoration, missing protection and broken protection.
- Controller inputs use owned native-shaped animation pack and move records.
  Restoration preparation executes the preceding move through the native VM
  before observation begins at the actual restoration command. No Source
  functions are replaced. CPU graphics doubles launch no game or GPU preview.
- The expanded multi-hit contract retains all existing state, events and RNG,
  and adds the complete move/general animation stream. All 11,520 actions
  execute; at this earlier checkpoint **1,344 observations differed** in animation commands:
  Substitute fade, Focus Band and poison presentation. Those differences and
  every failed/superseded fixture report remain in local ignored QA output.

Native doll import/drawing and all three general/status controllers are now
implemented. The final complete matrix passes 32 workers / 14,816 paired
observations, including every earlier differing animation stream. Full evidence
and scope are recorded in `native-gen3-mirror-move.md`. CPU draw/state checks
are not final GPU scene acceptance.

Reproduce the complete paired CPU contracts with:

```sh
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --mode substitute_multi_hit --mode substitute_presentation \
  --mode mirror_move --mode mirror_move_content --mode mirror_move_chained \
  --report /path/to/new-report.json
```

Local raw observations: `tmp/substitute-presentation-qa/`.

The frozen `63084eca` full run passes 156/167 engine suites, SDK 3/3 and B30.
Its exact FAIL-line Counter adds two queue-hole crashes to the inherited 25
lines. The follow-up preserves every sparse queue row/hole, avoids grouping
unprotected users, and passes the controller, Follow Me and move-used PP suites.
The failed full run remains retained. Runtime `729c07fa` passes the repeated
full gate at 158/167 engine suites, SDK 3/3 and B30. Its exact anchored FAIL-line
Counter equals fresh #258: the same 25 inherited lines, with no additions or
removals.
