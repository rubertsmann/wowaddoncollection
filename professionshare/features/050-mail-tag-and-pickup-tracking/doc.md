# Mail tag and pickup tracking

Status: done | Since version: 1.8.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Queued mails carry a short order tag in the subject. When the recipient takes the items out of such a mail, their
client writes the pickup into the order: the requester picking up the crafted item closes the order as done; a crafter
picking up the reagents adds a history row. The sender gets order news that the mail was picked up.

## How to use
Nothing to do: send queued mails as before and take the items out as usual (any way of taking them counts).
Dev build: `/psd fake pickup` simulates someone picking up a mail of yours; `/psd fake openorder [recipeID] [qty]` makes an
open order from a fake member for a recipe you know (prints its mail tags).

## How it works
- Tag: `MailQueue.Tag(orderID, kind)`, six characters, at the end of the subject (`MailQueue.TaggedSubject`).
- `Core/Game/MailReceiver.lua` reads the inbox on every update; `TakeInboxItem` / `AutoLootMailItem` mark a tag as
  being taken (15 s); what a marked tag lost between two readings is the pickup (`MailQueue.Pickups`).
- `MailQueue.ApplyPickup` checks the role, records `rcv` on the order and closes it for the crafted item.
- Data and messages: `docs/protocol.md` section 20.

## Localization
New labels through `Text` (deDE). The tag is language-free.

## Limits and known issues
- Only mails sent through the queue carry the tag.
- A take that fails (bags full) followed within 15 s by returning the mail would count as a pickup (rare).
- The inbox API on Forever is not verified yet (see verify.md).
