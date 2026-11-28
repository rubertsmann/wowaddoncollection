# 024 Feedback tab and hidden debug tab: spec

- Status: done
- Created: 2026-11-23
- Target version: ProfessionShare 1.3.0 (protocol 2.5, schema 7)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Players send short feedback / feature requests / bug reports from a new "Feedback" tab; only the developer's client
fetches and lists them (with whisper and a private status), and the prod Debug tab stays hidden until `/ps debug`.

## Requirements
- R1: A "Feedback" tab (after Misc Items) has a type dropdown (Feedback, Feature request, Bug), a text box and a Send
  button. Choosing a type puts that type's template text into the box (only while the box is empty or still holds an
  unchanged template). Send is refused for empty text or an unchanged template. Fire and forget: no developer status
  for the sender. Under the box: a "My messages (n)" menu (own messages, newest first, each with a delivered/waiting
  icon), three icon counters (sent / delivered / waiting, explained in tooltips) and a short result of the last Send.
  "Delivered" = the developer's client asked for the record (only readers ask), stored on the sender's client only.
- R1c: The Feedback tab is shown only where a message can arrive: the developer's character is in my guild roster
  (`Feedback.ReaderInRoster`, the same name hash), or I am the developer, or this is a development build. While the
  roster is empty (before the first roster update) it stays hidden; when the developer leaves, an open Feedback tab
  closes. Hidden tab buttons leave no gap.
- R2: Sent messages live in the sender's own feedback record (newest 10 kept, text <= 300 bytes, valid UTF-8, no
  control characters, newlines become " / "). The record's revision rides in HELLO (`frev`); the record itself
  (WANTF / FEEDBACK) is pulled ONLY by the developer's client (or a development build). Every other client never pulls
  and never stores another member's feedback record, even one broadcast on GUILD.
- R3: The developer is recognised by the existing name hash (`Model.IsBuildViewer`, djb2 of the lower-case character
  name); no real name is in the repository.
- R4: On the developer's client the tab also shows a list of all received messages (newest first): type icon, sender,
  text, status icon, age. Selecting a row shows the full text; buttons: Whisper (the sender), and three status icon
  buttons Declined / Answered / Fixed (clicking the active one clears it). The status is stored only on that client.
- R5: Peer feedback text is escaped before display (`|` cannot form UI escape codes); invalid records are dropped whole.
- R6: The Debug tab button is hidden in the live build until `/ps debug` (which still prints the log lines) shows it for
  the session and opens the window on it. The development build always shows it.
- R7: Development build: a Debug-tab button "Fake feedback" adds three messages from a local-only fake member, so the
  developer list can be checked without a second player.
- R8: A Bug report carries a diagnostic snapshot taken when it is sent (checkbox "Attach diagnostic info", on by
  default for bugs, off for the other types): addon version / protocol / schema / locale / client build, sync state
  (active, queue, send failures, roster size, characters held), the newest ERROR/WARNING log lines and the last few log
  lines of any level. Capped at 1200 bytes, valid UTF-8; only the 3 newest messages of a record keep their snapshot.
  The developer sees it in the detail panel / tooltip.

## Non-goals
- No reply channel inside the addon, no status visible to the sender, no relay through other members (a message
  arrives when sender and developer are online at the same time; it waits in the sender's record until then).
- Not a security boundary: anyone could read the record off the wire with their own code; the user accepted that.

## Design
- `Core/Data/Feedback.lua` (new, pure): TYPES, MAXIMUM_ITEMS = 10, MAXIMUM_TEXT_BYTES = 300, IsReader(name),
  CleanText, Sanitize, Get/Put (Put refuses unless the reader), Add(myName, type, text, now) -> ok|refusal,
  SanitizePersisted, List() (rows over every held record, newest first), GetStatus/SetStatus (local state), Counts.
- `Core/Data/Store.lua`: SCHEMA 7, tables `feedback` (records) and `feedbackState` (developer's statuses);
  MIGRATIONS[6] additive; SanitizePersisted; canonical names; not wiped by ResetPeerData / Prune (the developer keeps
  messages of members who left); wiped by Clean except my own record.
- `Core/Net/Sync.lua`: record kind `feedback` (helloField `frev`, WANTF/FEEDBACK); heldRevision = math.huge for a
  non-reader (never pulls); store via Feedback.Put. `Core/Base/Init.lua`: PROTOCOL_MINOR 5.
- `Core/Game/Events.lua`: FEEDBACK_CHANGED -> RequestHelloSoon.
- `UI/Window.lua`: Feedback tab, hidden Debug tab button, `UI.ShowDebugTab`. `Core/Net/Communication.lua` (or
  Window): `/ps debug` wraps the library command. `UI/DevProbe.lua`: AddFakeFeedback, `/ps fakefeedback`.
- Locales: enUS keys, deDE translations.
- Message shape: HELLO.frev (optional), WANTF {names, via?}, FEEDBACK {feedback = {name, rev, items = {{t, k, text, log?}}}}.
- Bug snapshot: `Feedback.Snapshot(context)` (pure; context gathered in Window from addon.VERSION, Communication, Store, db.debug).

## Tasks
- [x] T1 (M): Feedback.lua + Store schema 7 + sync kind + protocol 2.5. Verify: `tests/test_feedback.lua`.
- [x] T2 (M): Feedback tab UI (form, developer list, status buttons, whisper). Verify: `tests/test_load.lua` (tab builds, send, list).
- [x] T3 (S): Debug tab hidden in live until `/ps debug`. Verify: `tests/test_load.lua`.
- [x] T4 (S): dev "Fake feedback" button. Verify: `tests/test_load.lua` / test_feedback.
- [x] T4b (S): bug snapshot (R8). Verify: `tests/test_feedback.lua` (cap, error lines first, UTF-8).
- [x] T5 (S): docs (README, CHANGELOG, protocol.md, status.md, doc.md, verify.md).

## Review Focus (failure modes a happy-path test would miss)
1. RF1: a non-developer receives a FEEDBACK broadcast on GUILD (pull retry) -> not stored. Pinned: test_feedback.
2. RF2: hostile record (11 items, 5 KB text, `|T` codes, bad type, non-UTF-8) -> dropped whole / escaped on display. Pinned: test_feedback.
3. RF3: an old peer (2.4) gets HELLO.frev / WANTF -> ignores the field, drops the unknown type; no error. Pinned: lib behaviour (unknown types dropped), test_feedback.
4. RF4: the 11th message drops the oldest, rev still grows; the developer's status of a dropped message is harmless. Pinned: test_feedback.
5. RF5: the Debug tab hidden while windowState.tab == "debug" was saved -> window opens on Recipes. Pinned: test_load.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: additive minor 2.4 -> 2.5 (new optional HELLO field and two message types; old peers ignore them).
- [x] Stored data: SCHEMA 6 -> 7, additive migration (two new tables).
- [x] Trust model: allow-list Sanitize, owner-only authorship (library check), text escaped on display.
- [x] Localization: only the type key is stored/sent; the text is the player's own words; templates via Text.
- [x] Load order: Feedback.lua after Access.lua, before Sync.lua (both TOCs).
- [x] Packaging: new file under Core/, included as before; features/ stays ignored.
- [x] Tests: tests/test_feedback.lua, test_load additions.
- [x] Docs: README, CHANGELOG, docs/protocol.md, docs/status.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-23: User: feedback visible only to their character if possible; others spotting it in data is acceptable; fire and forget; Debug tab in prod only after `/ps debug`; layout and icons left to Claude.
- 2026-11-23: Developer recognised by the existing name hash (Model.IsBuildViewer): keeps the real name out of the repo (rule: no real character names in files).
- 2026-11-23: Only the developer's client pulls feedback records (heldRevision = math.huge elsewhere). The engine has no relay, so storing it on every client would not help delivery and would spread the text.
- 2026-11-23: Status (declined/answered/fixed) stored only on the developer's client; the sender never sees it.
- 2026-11-23: User (mid-build): bug reports should include debug logs. Snapshot of version, sync state and the newest error/warning + recent log lines, 1200-byte cap, opt-out checkbox (log lines can name other members).
- 2026-11-23: User: replace the long status text with a menu and icons showing how many were sent successfully. Delivery is known locally: answering a WANTF means a reader asked (feedbackDelivered, schema 7, not sent anywhere). The long explanation moved into a tooltip.
- 2026-11-23: User asked whether the implementation can "doxx" them and to hide the feedback menu when not in the same guild. Answer recorded in log.md (exposure is inside the own guild only, character name only; the hash is reversible against a roster; a reader's WANTF shows the sender in the trace). Tab hidden unless the developer is in the roster.
- 2026-11-23: `/ps debug` unlocks the Debug tab for the session only (not saved).

## Open questions
- none
