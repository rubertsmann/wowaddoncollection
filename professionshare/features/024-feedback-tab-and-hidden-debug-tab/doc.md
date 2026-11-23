# 024 Feedback tab and hidden debug tab: documentation

## What it does
- **Feedback tab** (after Misc Items): players send feedback, a feature request or a bug report to the addon developer.
  Choosing a type puts a short template into the text box (bug: "What I did: / What happened: / What I expected:").
  Fire and forget: the sender never sees the developer's status. Under the box: "My messages (n)" (a menu of the own
  messages with a delivered/waiting icon) and three counters with icons: sent, delivered (the developer's client has
  picked them up), waiting. Hover them for the explanation.
- **Visibility:** the tab is shown only when the developer's character is in the player's guild roster (or on the
  developer's own character / a development build). Members of other guilds never see it.
- **Bug snapshot:** "Attach diagnostic info" (ticked for bugs, unticked for the other types) adds the addon version,
  protocol, schema, locale, client build, a sync-state line and the newest ERROR/WARNING plus the last few log lines,
  at most 1200 bytes. Log lines can name guild members; the tooltip says so.
- **Developer view:** on the developer's character (and in any development build) the tab also lists every received
  message, newest first: type icon, sender, text, "+" when a snapshot is attached, status icon, age. Select a row for
  the full text; buttons: Whisper (the sender), Diagnostic info (copy window with text + snapshot), and three status
  icons Declined / Answered / Fixed (click the active one to clear it). The status is stored only on that client.
- **Debug tab:** hidden in the live build until `/ps debug` (prints the log lines as before, then shows the tab and
  opens it, for this session). The development build always shows it, plus "Fake feedback" (`/psd fakefeedback`).

## How it works
- `Core/Data/Feedback.lua`: the record `{ name, rev, items = { { t, k, text, log? } } }` (newest 10 items, text <= 300
  bytes, at most 3 snapshots), `Add`, `Sanitize`, `Put` (stores another member's record only on a reader), `List`,
  statuses, `Snapshot`.
- `Core/Net/Sync.lua`: record kind `feedback` (`HELLO.frev`, `WANTF`/`FEEDBACK`); a non-reader treats every revision as
  held, so it never pulls. Protocol 2.5 (additive). Details: `docs/protocol.md` section 13.
- `Core/Data/Store.lua`: schema 7 (`feedback`, `feedbackState`, `feedbackDelivered`), kept by prune, version reset and `/ps clean`.
- Delivery: the record kind's `answer` marks every message in the answered record as delivered (`Feedback.MarkDelivered`);
  only readers request feedback records, so an answer means the developer's client asked.
- Reader check: `Model.IsBuildViewer` (djb2 hash of the lower-case character name; the name itself is not in the code).
- `UI/Window.lua`: the tab, `UI.SendFeedback`, `UI.ShowDebugTab`, the `/ps debug` wrapper.

## Limits and known issues
- No relay: a message arrives only when sender and developer are online at the same time (it waits in the sender's
  record, announced in every HELLO).
- Not secret: anyone could read the record off the wire with their own code (accepted by the user).
- Identity inside the own guild: the developer's character can be found by guild members who look for it. The name hash
  in the code is 32 bits, so checking every roster name against it takes seconds; the developer's client is the only one
  that asks for feedback records (`WANTF`), and a sender's network trace (`/ps debug`, Debug tab) shows who asked; the
  tab's visibility tells that the developer is in the guild. Only the character name is exposed, nothing outside the
  game, and nothing reaches other guilds.
- Members on 2.4 builds cannot send feedback; they ignore the new fields.

## Localization
All labels and templates through `Text[...]` with German translations; the stored type is a key (`feedback`, `feature`,
`bug`), the text is the player's own words.

## Verification
See [verify.md](verify.md).
