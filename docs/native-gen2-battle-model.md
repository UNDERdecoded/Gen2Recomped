# Live native Gen2 battle model

A Gen2 screen exposes actual current Pokemon, parties, save, catalog and outcome
through a live model view rather than treating the shared battler-wrapper screen
as that model. HP presentation remains on the existing native drain owner.
Pokemon picture captures use their real native slots, source image, crop, status
and effects without replacing a live rear sprite with its isolated front view.

Native model reader keys remain protected. Presentation consumers may attach and
release transient metadata on the view, without writing to commands or saves.

Independent checks on this PR composition pass: 366 live-model/HP/sprite-capture,
84 submenu-owner, 111 PACK and 9 FireRed checks (570 total). The new model test
fails before integration. These are ROM-free tests; no unchanged-consumer GPU,
release, full-PR or complete Gen1 parity acceptance is claimed. Existing engine
and Gen1 rights and attribution are retained.
