# PixlLootCouncil — Testing Plan (Stages 0-8)

Covers everything built so far in one pass, instead of the per-stage checklists used while the
addon was first being built. Run Part 1 solo first (same client, same account, works anywhere);
Part 2 needs a second WoW client/account grouped with the first and only really makes sense in an
actual instance with Master Loot enabled. Each item names the slash command(s) involved and what
success looks like. `/console scriptErrors 1` first, so a Lua error shows as a visible toast
instead of being silently swallowed.

## Part 1 — Solo

### 1.1 Load & bootstrap (Stage 0)
- `/reload` with the addon enabled. No Lua error toast appears.
- `/plc` with no arguments prints the full command list (alphabetical).
- `/plc errortest` logs a test entry; `/plc errors` shows it with a timestamp.

### 1.2 Roster (Stage 1)
- `/plc roster` solo shows just yourself, with your own class/role/online=true, and
  `council=true` or `false` depending on the default `raidAssist` mode and your current
  group-leader/assistant/ML status.

### 1.3 Loot detection + award pre-validation (Stage 2)
- Set loot method to Master Loot (works solo, party of 1), enter any instance, loot a trash
  mob. `/plc debug` toggles verbose logging; with it on, `LOOT_READY` should print each detected
  slot's link/quality.
- There's no more standalone `/plc award` command (retired in Stage 4) — awarding now goes
  through `UI/VotingFrame.lua`'s real Award button, covered in 1.5 below.

### 1.4 Comms protocol (Stage 3, solo-checkable parts only)
- Nothing to click solo here — `Comms/Protocol.lua`'s envelope/version-gate logic and the full
  command round-trip can only be exercised with a second client (Part 2.1).

### 1.5 Voting Frame + DataTable (Stage 4)
- `/plc testdata` seeds one fake item (no live loot slot) and opens the Voting Frame.
- Confirm the table renders your own name/class color, role, and a "-" response, and that the
  Award button is present per row.
- Resize the window / add more fake rows if you want to confirm scrolling and row recycling
  don't leak frames (watch `/framestack` row count across repeated `/plc testdata` calls — it
  should stay bounded, not grow unbounded).
- Click Award on the fake row: since there's no live loot slot, it should fail cleanly with
  "This item has no live loot slot" rather than erroring.

### 1.6 Session curation UI (Stage 5, solo-visible parts)
- Open a loot window as master looter with no PixlLootCouncil session active yet —
  `UI/SessionFrame.lua` should pop up automatically showing the detected items, each with a
  Remove button.
- Click Remove on an item, confirm it disappears from the list.
- Click "Start Session" — the frame should switch to its active view (Pending/Awarded status
  per item, a Vote button per item that opens the Voting Frame for that item) and an End Session
  button.
- `/plc sessionframe` manually reopens it if you close it.
- `UI/LootFrame.lua` should also pop up for you as a candidate once the session starts, showing
  response buttons built from your configured responses (Need/Greed/Pass by default).
  `/plc lootframe` reopens it manually.
- Click a response button: it should immediately swap to "You voted: X" for that item only —
  other items in the list keep their own buttons active (no global lock).

### 1.7 Chat announcements (Stage 6, solo-visible parts)
- With `profile.announce.sessionStart` on (default), starting a session should post one chat
  line per item to your current channel (party/raid/instance — whatever applies; solo with no
  group, there's no channel and nothing posts, which is correct, not a bug).
- Full holder-vs-candidate "exactly once" verification needs Part 2.6.

### 1.8 Options panel (Stage 7)
- `/plc options` opens it. Sidebar: General / Responses / Council under "RAID TOOLS", Appearance
  under "SETTINGS".
- **Live-update check (no /reload needed):** toggle an announce checkbox, drag a slider, switch
  the Council mode dropdown, click the Appearance accent swatch and pick a new color — confirm
  each change is reflected immediately (the accent change should visibly re-tint every open
  PixlLootCouncil window, not just the Options panel itself).
- **Persistence check:** `/reload` and confirm your changes stuck (this only proves in-session
  persistence). Then fully log out and back in — this is the real test that AceDB actually wrote
  `WTF/Account/.../SavedVariables/PixlLootCouncilDB.lua` to disk, not just `/reload`'s in-memory
  carryover.

### 1.9 Locale load (Stage 8)
- `/reload` and confirm no Lua syntax/load errors from any of the 10 stub locale files
  (deDE/esES/esMX/frFR/itIT/koKR/ptBR/ruRU/zhCN/zhTW) — they're intentionally empty beyond the
  `NewLocale` call, relying on AceLocale's automatic fallback to enUS.
- Full visual verification of translated text isn't possible without a client actually set to
  that game locale (`/console Locale ...` requires that locale's client files, typically not
  present on a single-locale install) — out of scope for this cycle; only enUS needs real text
  right now (spec §7/§9).

## Part 2 — Two clients, grouped (second account/character required)

This is the first point nothing above can substitute for — comms only exist between two real
clients.

### 2.1 Comms round-trip + version gate (Stage 3)
- With both clients grouped and the addon loaded on both, trigger each of the 9 commands in turn
  (`session_start`/`item_add` via looting, `response` via Loot Frame clicks, `award` via Voting
  Frame, `session_heartbeat` automatically every `sessionHeartbeatSeconds`, `session_end` via
  End Session, `session_force_end`/`session_sync_request`/`session_sync_data` via the debug
  commands below) and confirm each one is received and applied correctly on the other side.
- **Version-gate test:** this requires temporarily hardcoding a decoy envelope with
  `v = Comms.Protocol.PROTOCOL_VERSION + 1` on one client (e.g. a throwaway `/run` call into
  `PLC.Comms.Protocol:Send`) and confirming the other client silently ignores it — one
  `COMMS_UNKNOWN_VERSION` print, not a parse error, and not applied to session state.

### 2.2 Session continuity (spec §5.1 — the user-specified requirement, test explicitly)
All three with the holder actually holding an active session with at least one item queued:
- **(a) Reload survives:** `/reload` on the holder's client. Confirm the session is restored
  unchanged (same items, same `sessionId`) and the heartbeat timer resumes — the other client
  should never see a gap longer than `sessionHeartbeatSeconds`.
- **(b) Travel doesn't reset it:** have the holder physically zone to a different
  instance/city/the world. Confirm the session is completely unaffected on both clients — no
  prompt, no reset, no desync.
- **(c) Disconnect triggers the escape hatch:** fully disconnect the holder's client (not just
  `/reload`). On the council-member client, wait past `profile.sessionForceEndMinutes` worth of
  missed heartbeats, then confirm `/plc session forceend` becomes available (no error print) and
  correctly force-ends the session for that client. Also confirm it correctly *refuses*
  (`SESSION_CANNOT_FORCE_END`) if attempted before the threshold has actually passed.
- **Resync:** have a candidate client join the group (or reload) *after* a session has already
  started with items in it. Confirm it auto-requests and receives a full sync within a couple of
  seconds (`/plc session sync` to trigger manually if you want to test the debug path too) and
  ends up with the identical item/response state the holder has — not just the messages sent
  since it joined.

### 2.3 Voting Frame live refresh (Stage 4)
- With a real active session item, open the Voting Frame on the council member's client (via
  `UI/SessionFrame.lua`'s Vote button), and have the candidate respond on their Loot Frame.
- Confirm the council member's Voting Frame updates that one row immediately, and that it's a
  targeted update, not a full redraw — watch that only the affected row's text changes (no
  visible flicker/rebuild of the whole table; if you want to confirm this at the code level
  rather than just visually, a temporary print inside `DataTable:SetRows` vs `RefreshRow` will
  show which path actually fired).

### 2.4 Session curation + no-double-vote (Stage 5)
- ML side: open a loot window with 2+ items, remove one via the Session Frame's curation list
  before clicking Start, confirm the removed item never appears in the candidate's Loot Frame or
  in `PLC.Session.items` on either client.
- Candidate side: click a response button, confirm it can't be clicked again (buttons are
  replaced with the "You voted: X" label) — but that a *different* item in the same session
  still has its own live buttons, unaffected.

### 2.5 Award flow end-to-end (Stages 2-6 together)
- Council member clicks Award on a real session item's row (with its loot window still open on
  the holder's client — see the note in `docs/SPECIFICATION.md`'s plan about award keying off
  the live Blizzard loot slot). Confirm: the item actually transfers, the holder's client shows
  `AWARD_SUCCESS`, the item's row shows "Awarded" status on both clients, and the `award` comm
  updates `PLC.Session.items[idx].awarded` on every client without a full resync.
- Close the loot window first, then attempt Award again on a *different* (not-yet-resolved) item
  whose underlying loot slot is now stale — confirm it fails cleanly with the existing
  `CanGiveLoot` rejection message rather than erroring.

### 2.6 Chat announcements, exactly once (Stage 6)
- With a real session and award happening, confirm the session-start and award chat lines each
  appear **exactly once** in the group channel — from the holder's client only. The candidate's
  own client must never also post them (verify by having the candidate temporarily toggle
  `profile.announce.*` on with a session they're not holding — nothing should print from their
  side).
- Confirm the item link in the posted chat message is clickable/shows a tooltip (standard WoW
  chat-link behavior — no extra code needed as long as a raw item link string was passed to
  `SendChatMessage`, which it is).
