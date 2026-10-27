# Native Gen2 battle item presentation ownership

BattlePack must close before constructing a party-item target. Leaving it
underneath the picker makes a resolved presentation see the PACK's boolean
battle flag where the native battle model should be. The Gen2 controller now
closes the actual PACK first and lends its real battle context to the picker.
Cancellation queues a new native PACK, restoring its session pocket/cursor
without consuming inventory, PP or a turn.

Successful medicine and no-effect refusals now use the existing native battle
text queue. A standalone field TextBox has no battlefield composition owner
and produced a white backing over the decorated battle. Effects still run
through BagMenu's existing item-use dispatch; success delegates to itemUsed
once, while refusal queues text without a native enemy action. Other
cartridges keep their existing field-text path.

The updated native PACK regression fails 35 assertions on the preceding
implementation and passes 191 after the change. Live native model, submenu, summary and FireRed
regressions also pass on this independently adapted upstream-PR composition
(976 checks together). These ROM-free source/input
checks do not establish unchanged-client GPU, full Gen1 visual/story parity
or final package acceptance. Native party-result animation/timing and broader
item-family presentation remain subject to reference acceptance.
