# Native incoming caller selection

The native incoming-call path now consumes one unsigned random byte for
ChooseRandomCaller, swaps its nibbles, masks to five bits and reduces it by
the eligible caller count. Previously it drew a uniform Lua list index,
which changed the native byte-to-contact mapping. Candidates retain saved
phone-slot order, independently of the display hook.

The timer expiry remains consumed before the coin flip; service and empty
book gates consume no caller-choice byte. A successful choice still compiles
and executes the selected contact's imported receive program and resets the
receive delay. The entrance gate leaves both the timer and RNG untouched.

The algorithm and gate order were compared with the read-only reference
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`,
`src/core/gen2/Phone.lua` (ChooseRandomCaller and CheckPhoneCall).
Synthetic tests exhaust all256 byte values for each book size1..10 against
an independent bitwise oracle and exercise actual native call selection,
Gen2ScriptVM and ScriptRunner in Gold/Silver/Crystal. This does not establish
complete radio/phone parity, a hardware call or original-story acceptance.

Original contributions by Roxas2712; existing reference, upstream and
third-party rights and credits remain applicable. See the [specific PR contribution permission and credits](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md).
