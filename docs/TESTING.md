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

### 1.3 Silent background loot collection (Stage 2, reworked for the bagged-item workflow)
Reworked after the second round of playtest feedback: the ML stays on Master Loot the whole raid
and silently self-loots every qualifying item the moment it drops (items are BoP-tradeable for
2h, so review/award happens later, not live at the corpse) — there is no more "vote live at this
corpse's loot window" flow.
- Set loot method to Master Loot (works solo, party of 1), enter any instance, loot a trash mob
  whose drop meets `profile.lootThreshold` (Rare+ by default). `/plc debug` toggles verbose
  Detection logging (prints every detected slot regardless of quality); confirm separately that
  the item actually lands in **your own bags** with no window popping up at all — collection is
  deliberately silent (see `Loot/Detection.lua`'s `onLootReady`).
- Loot something *below* `profile.lootThreshold` (a gray/green): confirm it's left alone —
  normal Blizzard looting, untouched by the addon, not self-looted or tracked.
- `/plc sessionframe` any time afterward shows it in the list with a Pending status, confirming
  it was tracked even though no review session has been started yet.
- **Live update while inactive (fixed this round):** with `UI/SessionFrame.lua` already open and
  no review started yet, loot another qualifying item (or run `/plc additem`) *without* closing
  the window — confirm the new icon appears in the sidebar immediately, not just "No items yet"
  until you close and reopen it. This was broken: collection/manual-add only notified the UI
  when a review was already active, which is the *less* common state — most of a raid happens
  while silently collecting.
- There's no more standalone `/plc award` command — awarding now goes through the Award/
  Pre-Award buttons in the session window's embedded response grid, covered in 1.5 below.

### 1.4 Comms protocol (Stage 3, solo-checkable parts only)
- Nothing to click solo here — `Comms/Protocol.lua`'s envelope/version-gate logic and the full
  command round-trip can only be exercised with a second client (Part 2.1).

### 1.5 Session window: icon sidebar + embedded response grid (two-column sidebar this round)
`UI/SessionFrame.lua` is a narrow left-hand icon sidebar, **two icons per row** once there's more
than one item (driven directly by `PLC.Session.items` — items are already bagged by the time
anyone could react to them, see 1.3), plus a content area on the right. `UI/VotingFrame.lua` is
an embedded panel in that content area, not its own popup — click an icon, its full
candidate/response/Award/Pre-Award grid loads next to it, not below a row list anymore.
- `/plc sessionframe` any time opens it — there's no more automatic popup on loot (that was pure
  spam across a multi-hour raid; see 1.3's rework note).
- `/plc testdata` adds one real test item (Hearthstone, itemID 6948 — always cached, so it
  resolves instantly with a real name/icon/link, not placeholder text) via the same
  `Session:AddManualItem` path `/plc additem` uses, and opens the window.
- Confirm the sidebar shows the item's icon with a hairline border, auto-selects it, and the
  content area on the right shows the item's name + a Remove button above the "N out of M have
  voted" line + the candidate/role/response/Award/Pre-Award grid.
- Two-column layout, flush and tight (refined this round): with only one item total, confirm it
  renders as a single icon (no empty second slot look). Seed a second item (`/plc additem
  <itemID>`) and confirm the two icons sit side by side on the same row, flush against the left
  edge of the window (no left-edge gap above/beside the first icon) with only a small, tight gap
  between the two icons — a third item should start a new row below, not a third column.
  Adjacent rows should sit directly against each other too (no visible gap top/bottom around an
  icon) — if you still see a few px of padding on any edge of an icon, that's the bug this round
  specifically fixed (icons were being centered within slightly oversized cells instead of
  flush-anchored). Confirm clicking **either** icon in a two-icon row selects that specific
  item (not always the left one) — each icon is its own independent click target now, not a
  whole-row click.
- Hover an icon: confirm a tooltip shows the item name and its current status
  (Pending/Pre-awarded: X/Awarded: X/Expired). Seed a third test item and confirm its icon's
  border color differs once you pre-award or award it (accent for pre-awarded, a dimmer border
  for awarded, warning-red for expired) — this is the "visibly flagged" status the icons carry
  instead of inline text, since there's no room for that at sidebar width.
- Per-item deadline visual (now a bar under each icon instead of a faint row tint, since two
  icons can now share one row): confirm a short, solid-colored bar directly beneath each pending
  icon, full width at broadcast and shrinking to nothing as `profile.responseTimeoutSeconds` runs
  out, with the same accent→warning-red flip under 10s as the main response window. Confirm it's
  clearly visible (not faint) and independent per item — seed two items a few seconds apart and
  watch their bars empty at different rates, not in lockstep. **Confirm the bar visibly slides
  smoothly** rather than jumping in small steps (it now updates every frame via the icon's own
  OnUpdate, not just once a second off the ticker). Confirm it disappears once that item is
  awarded or pre-awarded, and that hovering a still-pending icon shows a tooltip line ("Time
  left: Ns") that also counts down live (still 1-second resolution, text doesn't need to be
  smooth) and is absent once awarded. Confirm adding a new item mid-review (via `/plc additem` or
  a live loot while Session is active) still works exactly as before — this round deliberately
  did **not** touch per-item deadlines or lock out adding items during a session.
- Selected-icon highlight: confirm the currently-selected icon shows a visible accent glow (not
  a whole-row tint anymore, since a row can hold a second, unrelated item) and that it moves to
  exactly the icon you clicked.
- With `Session.state` still `"inactive"` (haven't clicked Start yet), confirm the Remove button
  above the grid is visible for the selected item; click it, confirm the item's icon disappears
  from the sidebar and `PLC.Session.items` is actually empty.
- Click "Start Session": confirm Remove disappears (no wire command exists to retract an
  already-broadcast item), End Session and Award All buttons appear, the window's title bar now
  shows "Started by <name>" (holder's own character name, no realm suffix — see the realm-display
  note below), and (with a second client, or `/plc additem` on the same one) that new icons keep
  showing up live if looted while reviewing is still in progress. End the session and confirm
  "Started by" disappears again.
- Seed several test items and confirm the sidebar scrolls without leaking frames (watch
  `/framestack` row count across repeated adds — it should stay bounded, not grow unbounded).
- Click Award on a candidate in the response grid: confirm the item's icon border flips to a
  clearly visible **green** (not the dim gray it was before — that was nearly indistinguishable
  from a plain pending icon and, combined with the view auto-advancing away from the item you
  just awarded, made it look like clicking Award did nothing), a `[PixlLootCouncil] <item>
  awarded to <player> -- trade it to them!` line prints (this workflow doesn't auto-trade — see
  2.5), and selection auto-advances to the next pending icon. Hover the now-green icon: confirm
  the tooltip still correctly shows "Awarded to: <name>".
- Click Pre-Award instead on a different item/candidate: confirm that candidate's button reads
  "Staged" (accent-colored) and the item's icon border turns accent-colored — *without* printing
  anything or changing the item's real Awarded state yet. Click Award All: confirm every
  pre-awarded (not-yet-awarded) item commits in one pass, each printing its own trade
  instruction.
- Response column states (needs a second client or `/plc testdata` on one with yourself as the
  only "candidate" — see 2.7 for the full presence-timeout version): confirm it reads an actual
  response (BiS/Upgrade/etc.) once voted, "Waiting for response..." for a roster member who has
  the addon but hasn't voted, or "No addon detected" for one who's never checked in at all.
- **No realm in the candidate grid (new this round):** with a second client/character (so there's
  a real "Name-Realm" roster entry, not just your own unqualified name), confirm the candidate
  grid shows just the character name, no "-Realm" suffix — same for the "Awarded to"/"Pre-awarded
  to" tooltip lines on sidebar icons, and the new "Started by" header label. This is display-only
  — comms/sync and Roster lookups still use the full "Name-Realm" internally, unaffected.

### 1.6 Candidate response window (whole-row timer background + new response set this round)
- `UI/LootFrame.lua` pops up for you as a candidate once a review session starts (`Session:Start`
  broadcasts the backlog), showing one row per item, same single-row-per-item layout as before:
  an icon, a compact countdown number, then 5 response buttons (BiS/Upgrade/PvP/OS/Pass by
  default — replacing the old Need/Greed/Pass set) with the note field right beside them on the
  *same* row (a stacked buttons-then-note layout was tried in an earlier pass and made every row
  far too tall — this round reverted to side-by-side). `/plc lootframe` reopens it manually. Row
  height should look close to what it always was, not noticeably taller.
- The old per-item column with its own small progress bar is gone — the countdown is now a
  depleting **background across the whole row** (full-row tint at broadcast, shrinking
  right-to-left to nothing as `profile.responseTimeoutSeconds` runs out), with the standalone
  number column kept for precision. Confirm the row background visibly empties in step with the
  number. **Confirm the background slides smoothly** rather than jumping in small steps (it now
  updates every frame via the row's own OnUpdate, not just once a second). Confirm both the
  number's text color and the background tint flip from accent to warning-red together once
  under 10 seconds remain. Confirm it's still per-row/per-item — add a second item a few seconds
  after the first (mid-review item additions still work, see 1.5) and confirm its row counts down
  independently, not tied to the first item's or any shared clock.
- Dynamic button widths (new this round): confirm the 5 response buttons are no longer all the
  same fixed width — short labels like "OS" should hug their text with modest padding, while
  "Upgrade" is visibly wider to fit its longer label, and none of them look cramped or overly
  padded next to each other.
- Note field — fixed size, capped length (corrected this round): confirm the note box is **the
  same height as the response buttons** next to it and **the same width as the full button row**
  — a fixed size that does not change when you resize the window (an in-between round made it
  dynamically resize per-window-width instead, which this round reverted — the window itself
  defaults wider now specifically so this fixed-size row fits without spilling past the right
  edge; if you shrink the window a lot, the note box may extend past the edge, which is expected
  with a fixed-size row). Confirm it shows "Optional Note..." as placeholder text (gray, cleared
  on real input). Type a long note (60+ characters): confirm the text wraps onto a second line
  and then **stops accepting more characters** once it's about full — it should NOT keep growing
  downward past the box's bottom border or past 2 lines; if you do manage to get a 3rd line's
  worth of text in, that's a bug (the box clips its own content as a backstop, but the character
  cap is what should actually prevent it in normal use). Vertical text alignment (fixed this
  round): with the note box empty (just the "Optional Note..." placeholder) or holding a single
  short line, confirm the text sits vertically centered in the box, level with the response
  buttons' own centered labels right next to it — it previously sat pinned near the box's top
  edge, which (even though the box's own border/frame was already the exact same height and
  position as the buttons) read as the whole field being misaligned with them.
- Scrollbar behavior (reworked this round, shared by every scrollable list in the addon — this
  window, `UI/SessionFrame.lua`'s icon sidebar, and the embedded candidate grid inside it): seed
  enough items that the list actually overflows and needs to scroll. Confirm the scrollbar thumb
  is fully visible **inside** the window's own border — it previously extended several pixels
  past the window's right edge, visible against the game world behind it. Confirm the thumb's
  position reflects where the list actually is **immediately**, without needing to click/drag it
  first (it previously stayed at a stale position after the list content changed size — e.g.
  after an item was added — until manually dragged). Confirm the scrollbar is **completely
  hidden** when the list fits without scrolling (e.g. only 1-2 items), not shown empty/inert.
- Type something in an item's note field, then click a response button: the whole row disappears
  immediately (not a "you voted" label) — other items in the list are unaffected.
- Leave an item unanswered and watch it run out: once `profile.responseTimeoutSeconds` passes
  (stamped fresh the moment `Start()` broadcasts, not however long ago the item was actually
  bagged), that row disappears on its own (checked every second while the window is open) — and
  if that was the only pending item, the whole window auto-hides.
- Open this window with `UI/SessionFrame.lua` and `UI/OptionsFrame.lua` also open and
  overlapping — confirm the stacking order is always Options (bottom) → Session (middle) →
  this one (top), regardless of which was clicked or opened most recently (three separate
  frame-strata tiers now: "HIGH"/"DIALOG"/"FULLSCREEN_DIALOG" — this was the actual overlap bug,
  Options and Session used to share the same "DIALOG" tier with undefined relative order).
- Both windows are now drag-resizable from a small corner grip, bottom-right (brightens to accent
  on hover) — confirm dragging it resizes the window within sensible bounds (it can't shrink
  below a usable minimum), and that a taller `UI/SessionFrame.lua` actually shows more item icons
  at once (the icon list is a real scrolling table, so it picks up the extra height) — widening
  either window just adds blank space on the right, since column widths are still fixed for now.
- Every window's header (this one, Session, Options) now shows the brand logo to the left of the
  title, accent-tinted — confirm it re-tints live along with everything else when you change the
  accent color in Options → Appearance.
- Close button style (new this round, all three windows): confirm the header's close control is
  now a thin accent-colored "X" (two crossed hairlines) with no background square behind it,
  instead of the old solid-square button with a red "x" glyph — and that it still closes the
  window on click, and still flips to warning-red on hover.

### 1.7 Chat announcements (Stage 6, reworked after first playtest, solo-visible parts)
- With `profile.announce.sessionStart` on (default), starting a session should post **one**
  summary chat line ("Loot session started with N item(s)...") to your current channel (party/
  raid/instance — whatever applies; solo with no group, there's no channel and nothing posts,
  which is correct, not a bug) — not one line per item like the original implementation did
  before the first playtest flagged it as spammy.
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
- With both clients grouped and the addon loaded on both, trigger each of the 10 commands in turn
  (`session_start`/`item_add` via looting, `response` via Loot Frame clicks, `award` via the
  embedded response grid's Award button, `session_heartbeat` automatically every
  `sessionHeartbeatSeconds`, `session_end` via End Session, `session_force_end`/
  `session_sync_request`/`session_sync_data` via the debug commands below, `presence`
  automatically every 2 minutes per client) and confirm each one is received and applied
  correctly on the other side.
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
- **Uncached item on the receiving side (fixed this round):** the candidate needs to actually
  not have the item cached client-side yet for this to be meaningful — pick something they've
  genuinely never seen before (a rarer item works better than something common like Soul Shard,
  which may already be cached from a prior pickup). Confirm their Loot Frame/Session Frame show
  the real icon and name within a second or two, not a permanent "?" — `Data/Session.lua` now
  listens for `GET_ITEM_INFO_RECEIVED` and resolves it once Blizzard's own client actually has
  the data, instead of giving up after one failed lookup.

### 2.3 Embedded response grid live refresh + notes (Stages 4-5)
- With a real session item, have the council member select that item in their
  `UI/SessionFrame.lua` window (it's auto-selected if it's the only pending one), and have the
  candidate respond — with a note — on their Loot Frame.
- Confirm the council member's response grid updates that one row immediately, and that it's a
  targeted update, not a full redraw — watch that only the affected row's text changes (no
  visible flicker/rebuild of the whole table; if you want to confirm this at the code level
  rather than just visually, a temporary print inside `DataTable:SetRows` vs `RefreshRow` will
  show which path actually fired).
- Hover the response cell on the council member's side: confirm the note text shows in a tooltip
  (`GameTooltip`), and that a response with no note shows no tooltip at all.

### 2.4 Collection across the whole raid + response deadline (reworked for the bagged-item workflow)
- ML side: loot 2+ qualifying items across *different* corpses/trash packs over a few minutes
  (not all from one loot window), confirming each lands silently in your bags with no popup, no
  broadcast yet, and no comms traffic (check with a packet/throttle add-on or just confirm the
  candidate sees nothing in their Loot Frame during this phase).
- Still pre-Start(): remove one of the collected items via `UI/SessionFrame.lua`'s Remove button,
  confirm it never appears in the candidate's Loot Frame or in `PLC.Session.items` on either
  client once you do start.
- Click Start Session: confirm **all** remaining collected items broadcast at once (not just the
  most recently looted one) and the candidate's Loot Frame shows every one of them simultaneously
  with a *fresh* full countdown each — not an already-half-expired one, even for an item that was
  actually bagged several minutes before Start() was clicked.
- Response deadline, "takes the one from loot master": lower `profile.responseTimeoutSeconds` on
  the holder's client (Options → General) *before* clicking Start, confirm the candidate's
  countdown matches the holder's configured value (not whatever the candidate's own Options panel
  happens to say), and that the row disappears on its own once it expires, with the item's status
  on the ML's side showing "Expired" rather than "Pending" (Award still works on it regardless).
- Candidate side: click a response button, confirm the whole row vanishes immediately — a
  *different* item in the same session keeps its own live row, unaffected.

### 2.5 Bagged-item award flow + pre-award + Award All (reworked for the bagged-item workflow)
There is no live loot slot by the time anyone's reviewing — Award now means "record the decision
and tell the holder who to trade it to," not "transfer it directly" (no trade automation yet,
per the user's explicit choice — see the plan).
- Council member clicks Award on a real (already-bagged) item's row. Confirm: the item's status
  flips to "Awarded: PlayerName" on every client via the `award` comm (no full resync needed),
  and the holder's client alone prints the `... awarded to ... -- trade it to them!` instruction
  and posts the chat announcement (if `profile.announce.award` is on) — the candidate's client
  does neither.
- Attempt to Award the same item again (from either client): confirm it refuses cleanly
  (`SESSION_ALREADY_AWARDED`) rather than double-committing or erroring.
- Pre-award + Award All: Pre-Award two different items to two different candidates (confirm
  "Staged" shows locally on the holder's client only — the candidate clients should see no
  change at all, since pre-award is never broadcast), then click Award All. Confirm both commit
  in one pass, each with its own trade-instruction print and its own `award` comm, and that a
  third, un-staged item is left untouched (still "Pending").
- The actual item transfer is manual now (holder trades it in-game) — confirm the addon does
  *not* attempt to open a trade window or otherwise touch the trade UI; that's explicitly out of
  scope for this round.
- **Pre-award doesn't survive a review pass (fixed this round):** Pre-Award an item, then End
  Session *without* committing it (no Award All, no individual Award click) — confirm the item
  carries forward to the next Start() as expected (it's not awarded, so it should), but its
  "Staged" state does **not** — the button should read "Pre-Award" again and the top-list status
  should show "Pending", not a leftover "Staged"/"Pre-awarded: X" from the review pass that never
  actually committed it.

### 2.6 Chat announcements, exactly once (Stage 6, reworked after first playtest)
- With a real session and award happening, confirm the session-start summary line (one line
  total, regardless of item count — see 1.7) and the award chat line each appear **exactly once**
  in the group channel — from the holder's client only. The candidate's own client must never
  also post them (verify by having the candidate temporarily toggle `profile.announce.*` on with
  a session they're not holding — nothing should print from their side).
- Confirm the item link in the award chat message is clickable/shows a tooltip (standard WoW
  chat-link behavior — no extra code needed as long as a raw item link string was passed to
  `SendChatMessage`, which it is).

### 2.7 Addon-presence detection (new this round, `Data/Presence.lua`)
- **Grid refresh on presence arrival (fixed this round):** open the session window on one client
  *immediately* after reload, before the 2s-delayed first broadcast can possibly have landed from
  anyone — confirm that once presence pings do start arriving, rows that were showing "No addon
  detected" flip to "Waiting for response..." on their own, without needing to click away and
  reselect the item. This was broken: nothing ever told an already-rendered grid to re-check
  presence after the fact, so a row rendered too early stayed wrong forever.
- Reload one client, wait a few seconds (the first broadcast is delayed ~2s on purpose), then
  open the session window on the other client with a test item selected: confirm the just-reloaded
  player's response cell reads "Waiting for response..." quickly, not "No addon detected" —
  presence shouldn't take anywhere near the full 5-minute timeout to show up for someone who's
  actually there.
- Fully disconnect (not `/reload`) one client. On the other, confirm that player's row keeps
  reading "Waiting for response..." for a while (tolerating a couple of missed 120s re-broadcasts
  on purpose) and only flips to "No addon detected" once `PRESENCE_TIMEOUT` (5 minutes) of
  silence has actually passed — not instantly on disconnect.
- A third, genuinely addon-less raid member (if you have one to test with) should read "No addon
  detected" the entire time, never flipping to "Waiting for response...".
