# Native phone list display hook

Gold, Silver and Crystal now dispatch `phone.contact_list(save, list)` when
the native Pokegear reads its contacts. The signature follows the read-only
Gen1 reference at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`,
`src/core/gen2/Phone.lua`: the save remains an opaque native handle and the
list is a detached array of ten numeric contact IDs, with zero for blanks.
Native API 1/2 share this signature. Other generations do not dispatch this
native Pokegear hook.

Mods can reorder or hide display rows and show contacts registered through
`phone_contacts`. A return value of the wrong type or length retains the
native display. Invalid, fractional, non-finite and unknown contact IDs
become blanks without shifting slots. Mutating the display list does not
register contacts, reorder the saved phone book or filter incoming callers.

Each displayed contact retains its actual physical slot. The native DELETE
action therefore removes the selected contact even after display reordering;
an injected non-member cannot delete an unrelated saved slot. Unsubscribing,
failed-entry rollback and loader teardown restore the native presentation.

Validation:focused checks use the actual Loader, content registry,
Pokegear contacts/input and incoming selector across all three editions and
two native API levels. They cover invalid returns, detached arrays,
saved-book isolation, reordered deletion, injected non-members, rollback and
other-generation dispatch isolation. This is synthetic behavioral
acceptance; no new hardware phone-call or original-story claim is made.

The complete legacy Phone facade, special-call/rematch contracts, authored
phone scripts/forward references and full story acceptance remain open.

Original contributions by Roxas2712; existing reference, upstream and
third-party rights and credits remain applicable. See the [specific PR contribution permission and credits](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md).
