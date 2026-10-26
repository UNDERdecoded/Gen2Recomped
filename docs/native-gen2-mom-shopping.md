# Native GSC Mom accounts and purchases

The existing native banking screen changed a separate saving boolean, while
trainer rewards went entirely to the wallet. The cartridge's shopping tables
and notification scripts were not imported. This connects the banking choice,
native flags, trainer reward accounts, ROM purchase rows, original phone
programs, decoration ownership and raw-save state.

## Cartridge data and account state

`map_scripts.momShopping` contains the user's cartridge's random and ladder
lists. Each row is eight bytes: big-endian three-byte trigger and price, then
kind and item/DECO bytes. End symbols determine the count. The random threshold
increment is read from the native instruction operands that populate
`hMoneyTemp`; no retail catalogue, purchase dialogue or guessed hack layout is
bundled. Both original item/doll phone programs enter the shared script/text
importer. Invalid or incomplete bindings publish no partial lists and do not
partially enqueue programs. The new GSC cache marker requires reimport.

The native account fields are `g2MomMoney`, `g2MomSavingMode` and
`g2MomBankOpen`, alongside the existing boolean `g2MomSaving`. Saving bit zero
and the active bit agree with the same engine flags original scripts read.
The bank UI uses those shared fields; an imported active account is recognized
instead of silently opening a new account. Explicit start/stop choices select
SOME/none. Imported HALF/ALL settings retain their native low-bit meanings.

Trainer rewards deal four quarters between the accounts. SOME sends one,
HALF two and ALL four to Mom; an already maxed Mom account sends everything to
the wallet. Each account saturates independently, so near-cap overflow is not
redirected. Held-item reward modification happens before this split. Original
reward-text entry points select the current mode and receive the real player
name and full prize total. Other generations and unreviewed hacks retain their
existing reward paths, including Prism's separate bank.

## Purchase and phone lifecycle

`g2MomShopping` retains the native ladder index, selected random-row byte and
three-byte trigger balance. The current ladder row has priority whenever its
trigger is met. Otherwise the threshold advances to/past the balance and only
an exact landing selects a random row; that threshold is consumed even when a
full PC refuses delivery. A random purchase does not advance the ladder.

Items resolve by the current dataset's native index and enter the existing PC
store with the native stack/capacity rule. Dolls set the actual imported DECO
ownership event; they do not place themselves in the room. Successful delivery
precedes deduction and ladder advancement. No reception or an occupied native
reentry queue prevents a purchase before selection state changes. Missing
original phone programs do not grant an unannounced purchase.

The common native trainer-return path attempts the purchase once. Its original
phone program waits behind the trainer's queued post-battle script and UI
overlays, then enters the existing native FIFO with Mom's current contact ID.
Caller state, ring/hang-up audio, and receive-delay reset use the existing native call path.
Where the host exposes an incoming-call notification seam, it is also used. Repeated battle
callbacks cannot duplicate the purchase, and a pending call from another
save/dataset cannot execute in the current session. Link and Battle Tower
returns do not trigger shopping.

Raw SRAM conversion uses each GSC edition's actual WRAM-derived account,
mode, ladder, row-selection and threshold offsets. The account/threshold use
big-endian triples; surrounding mode bits and absent legacy template values
are retained. Unsupported layouts receive no guessed new offsets.

## Verification and limits

ROM-free tests exercise actual table/instruction readers, banking VM/UI,
trainer battle win, native world return, script FIFO, flags, capacity refusal,
threshold selection and SRAM conversion. Save addresses are independently
compared with the shipped GSC manifests. Synthetic cartridges, texts and
records are authored fixtures rather than retail data.

A private read-only Crystal probe independently compares every numeric byte
of both shopping lists, executes all ten original ladder phone notifications,
checks actual item and DECO ownership delivery, resolves native reward slots
and round-trips the account/progress fields. It uses controlled dataset and
font/render/audio IO, not a GPU acceptance or full natural-story playthrough.
Original ROM hashes are checked unchanged. No ROM/private mod/save data is
included in the contribution.

The legacy `src.core.gen2.MomShopping` facade, full legacy phone parity,
new GPU acceptance and a complete unchanged VASC playthrough remain open.
This source change does not refresh public preview assets.

Contract references: [native purchase routine](https://github.com/pret/pokecrystal/blob/master/engine/events/mom_phone.asm),
[native trainer reward split](https://github.com/pret/pokecrystal/blob/master/engine/battle/core.asm).
Original additions use the [Roxas2712 contribution permission](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md);
existing upstream and third-party rights remain unchanged.
