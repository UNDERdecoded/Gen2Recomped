# Choice policy scoped to native move resolution

The typed battle state's `interactiveChoices` observation reads the actual
native preference. Boolean/nil overrides are admitted only inside that exact
live native move invocation. They live in the existing coroutine scope registry,
never on the persistent battle or as a raw view extension. Called native moves
borrow their visible ancestor's policy; a nested override retires with its own
scope. A suspended child cannot lend its policy to the caller or a sibling, or
write it into a later invocation. Error paths restore the registry's local head.

The fork's existing Gen3BatonPass owner consults this scoped policy at its current
native selection branch. Ordinary native preference, explicit native chooser,
link-request ownership, authored effect composition, switch/HP/item scheduling
and PP spending stay with their existing owners. No party-choice interpreter,
new coroutine runner or persistent preference is introduced.

Qualification on fork main `73b2c0f8`: frozen `b5adb2acd0` passes175 selected CPU
groups, including the final production scope code, native Baton Pass UI/link/
composition/packet checks and full five-edition HP/PP/every-RNG/frame/phase
no-op traces. The final focused fixture splits the original140-check combined
case into101 dynamic-scope checks plus65 native choice/called-move checks.
The added called-move cases retain all native effect records in their fixture;
earlier malformed partial-registry failures remain recorded. No production
change was made to bypass those fixture failures.

Older-public component `64205537`, composition `d2ff81f538`, passes65 groups
including the same101 dynamic-scope checks. That older base does not contain the
fork's Gen3BatonPass owner. This public foundation therefore offers the typed
policy and native-owner query seam, without claiming that missing consumer's
selection behavior. Its complete native-owner integration remains separate
work; newer native controller bodies are not overlaid for qualification.
The native predecessor fails the new scope fixture (including missing policy
accessors and accepted persistent writes); the exact test hash is in its receipt.

Unchanged OASC109 `bddb5181`, Ruby `a64d1f90d9`, earlier frozen `2b1dd03c76`:
trainer entry, paper/native/terrarium/native/paper, move swap/cancel, actual RAGE
PP20 to19 / enemyHP66 to58 / playerHP63 to52, dex retirement and clean teardown
pass with no loader errors. That GPU run predates the final called-move policy
inheritance adjustment. It qualifies the option ownership/render path, not
Action Card, contact timing, all terrain or stable FPS. Hosted CI is separate.

QA uses only owned profiles/copies and the20GiB free floor. Player profiles and
private mod bytes remain untouched. Contact continuation is still pending.
