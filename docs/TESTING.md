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
- `/plc` with no arguments opens the Loot Session window; `/plc help` prints the full command
  list (alphabetical).
- `/plc errors` lists any captured Lua errors with timestamps ("No errors recorded." on a clean
  install).

### 1.2 Roster (Stage 1)
- Solo, the Loot Session window's candidate grid shows just yourself, with your own class/role
  icon. Council membership follows the default `raidAssist` mode and your current
  group-leader/assistant/ML status.

### 1.3 Silent background loot collection (Stage 2, reworked for the bagged-item workflow)
Reworked after the second round of playtest feedback: the ML stays on Master Loot the whole raid
and silently self-loots every qualifying item the moment it drops (items are BoP-tradeable for
2h, so review/award happens later, not live at the corpse) — there is no more "vote live at this
corpse's loot window" flow.
- Set loot method to Master Loot (works solo, party of 1), enter any instance, loot a trash mob
  whose drop meets `profile.lootThreshold` (Rare+ by default). Confirm the item actually lands in **your own bags** with no window popping up at all — collection is
  deliberately silent (see `Loot/Detection.lua`'s `onLootReady`).
- Loot something *below* `profile.lootThreshold` (a gray/green): confirm it's left alone —
  normal Blizzard looting, untouched by the addon, not self-looted or tracked.
- `/plc` any time afterward shows it in the list with a Pending status, confirming
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
- `/plc` any time opens it — there's no more automatic popup on loot (that was pure
  spam across a multi-hour raid; see 1.3's rework note).
- `/plc additem 6948` adds one real test item (Hearthstone — always cached, so it resolves
  instantly with a real name/icon/link, not placeholder text) via `Session:AddManualItem`.
- Confirm the sidebar shows the item's icon with a hairline border, auto-selects it, and the
  content area on the right shows the item's name + a Remove button above the "N out of M have
  voted" line + the candidate/role/response/Award/Pre-Award grid.
- Hover the item name text at the top of the detail area: confirm the game's normal item tooltip
  appears, same as hovering the item link anywhere else. Switch to a different item (click
  another icon, or End/Start a session) and confirm the tooltip now shows for the newly-selected
  item, not the old one. Tooltip position (fixed this round): confirm the tooltip's own top-left
  corner lines up with the top-left of the text you're hovering — it previously anchored off the
  hovered frame's *right* edge, which put it in a visibly different spot than hovering a narrow
  sidebar icon would (see 1.6's tooltip check — same underlying fix, shared code).
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
  shows "Session started by <name>" (holder's own character name, no realm suffix — see the
  realm-display note below), and (with a second client, or `/plc additem` on the same one) that
  new icons keep showing up live if looted while reviewing is still in progress. End the session
  and confirm the "Session started by" label disappears again.
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
- Response column states (needs a second client or `/plc additem 6948` on one with yourself as the
  only "candidate" — see 2.7 for the full presence-timeout version): confirm it reads an actual
  response (BiS/Upgrade/etc.) once voted, "Waiting for response..." for a roster member who has
  the addon but hasn't voted, or "No addon detected" for one who's never checked in at all.
- **No realm in the candidate grid:** with a second client/character (so there's a real
  "Name-Realm" roster entry, not just your own unqualified name), confirm the candidate grid
  shows just the character name, no "-Realm" suffix — same for the "Awarded to"/"Pre-awarded to"
  tooltip lines on sidebar icons, and the "Session started by" header label (both this window's
  and, see 1.6, `UI/LootFrame.lua`'s own copy of it). This is display-only — comms/sync and
  Roster lookups still use the full "Name-Realm" internally, unaffected.
- **Role icon, class icon, note icon, iLvl/Diff, equipped-gear comparison:** the window's (now
  fixed, see 1.6's resize note) width fits all of these without clipping. Confirm each candidate
  row shows, left to right: a small role icon (Tank/Healer/DPS, hover it for a text tooltip
  naming the role —
  this replaced the old separate "DPS"/"Tank"/"Heal" text column entirely), a class icon
  color/shape-matching `RAID_CLASS_COLORS`, then the name — all three packed into one compact
  column sized for a WoW name's actual 12-character cap, not a guessed-wide one; a long name
  shouldn't look cramped or truncated against the icons next to it. Give one candidate a note
  (type something in `UI/LootFrame.lua`'s note field before responding): confirm
  a small "page" glyph appears next to their response text, and that hovering the response cell
  still shows the note text in a tooltip exactly as before — the glyph is purely a visibility aid,
  not a new interaction. Test gear sync: have both clients click Start Session (or join an
  already-active one), then confirm each candidate's row shows: an iLvl number and a colored Diff
  (green/+, red/-, white/0) for the slot the current item would fill, plus 1 or 2 small gear icons
  (2 for a ring/trinket/weapon test item — e.g. seed one via `/plc additem <a ring's itemID>` —
  1 for anything else) each showing that candidate's actually-equipped item, hoverable for its
  real tooltip. Before any gear sync has arrived for a candidate (e.g. right as a session starts,
  before the broadcast lands), confirm iLvl/Diff show "-" and the gear icons are simply absent,
  then confirm they fill in live within a second or two without needing to click anything —
  `Data/Gear.lua`'s `notifyVotingFrame` should re-render the grid the moment each `gear` message
  arrives. Switch to a different item in the sidebar and back: confirm the numbers update to
  match that item's own slot, not the previous item's.
- **Button/row spacing consistency:** with at least 2 candidates visible, confirm the horizontal
  gap between the Award and Pre-Award buttons looks the same size as the vertical gap between one
  row's buttons and the next row's — both are the same 6px value now (`BUTTON_GAP` in
  `UI/VotingFrame.lua`), rather than two unrelated numbers that happened to look mismatched next
  to each other.
- **One-handed weapon/offhand gear comparison (per-candidate, not per-item):** seed a one-handed
  weapon or offhand item (`/plc additem <itemID>`). For a candidate currently dual-wielding (or
  with a shield/offhand item equipped), confirm both gear-icon columns show something — their
  mainhand AND their offhand. For a candidate currently using a two-handed weapon, confirm only
  the first gear-icon column shows anything (their 2H weapon) and the second stays empty — there's
  no real offhand slot to compare for them. With two test candidates set up differently (one
  dual-wielding, one with a 2H weapon), confirm both show correctly on the SAME loot item at the
  same time — this is resolved per candidate, not once for the whole item.
- **Late-joiner gear sync:** with a session already active, join the group (or `/reload`) on the
  second client, then trigger a resync (`/plc sync` or just wait for the automatic one on
  join) — confirm that client's own gear eventually shows up in the OTHER client's candidate grid
  too, not just clients who were present at the original Start().

### 1.6 Candidate response window (whole-row timer background + new response set this round)
- `UI/LootFrame.lua` pops up for you as a candidate once a review session starts (`Session:Start`
  broadcasts the backlog), showing one row per item, same single-row-per-item layout as before:
  an icon, a compact countdown number, then 5 response buttons (BiS/Upgrade/PvP/OS/Pass by
  default — replacing the old Need/Greed/Pass set) with the note field right beside them on the
  *same* row (a stacked buttons-then-note layout was tried in an earlier pass and made every row
  far too tall — this round reverted to side-by-side). `/plc loot` reopens it manually (or prints that nothing is waiting). Row
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
- Note field — fixed size, capped length: confirm the note box is **the same height as the
  response buttons** next to it and **the same width as the full button row** — a fixed size
  that doesn't change when you resize the window (an in-between round made it dynamically resize
  per-window-width instead, which was reverted — the window's width is fixed now anyway, see
  1.6's resize note, so this no longer even comes up in practice). Confirm it shows "Optional
  Note..." as placeholder text (gray, cleared on real input). Type a long note (60+ characters):
  confirm the text wraps onto a second line
  and then **stops accepting more characters** once it's about full — it should NOT keep growing
  downward past the box's bottom border or past 2 lines; if you do manage to get a 3rd line's
  worth of text in, that's a bug (the box clips its own content as a backstop, but the character
  cap is what should actually prevent it in normal use). Vertical text alignment (fixed this
  round): with the note box empty (just the "Optional Note..." placeholder) or holding a single
  short line, confirm the text sits vertically centered in the box, level with the response
  buttons' own centered labels right next to it — it previously sat pinned near the box's top
  edge, which (even though the box's own border/frame was already the exact same height and
  position as the buttons) read as the whole field being misaligned with them.
- Scrollbar behavior (shared by every scrollable list in the addon — this window,
  `UI/SessionFrame.lua`'s icon sidebar, and the embedded candidate grid inside it): seed enough
  items that the list actually overflows and needs to scroll. Confirm the scrollbar thumb is
  fully visible **inside** the window's own border — it previously extended several pixels past
  the window's right edge, visible against the game world behind it. Confirm the thumb's position
  reflects where the list actually is **immediately**, without needing to click/drag it first (it
  previously stayed at a stale position after the list content changed size — e.g. after an item
  was added — until manually dragged). Confirm the scrollbar is **completely hidden** when the
  list fits without scrolling (e.g. only 1-2 items), not shown empty/inert. **Scroll with the
  mouse wheel** over the list (not by dragging the thumb): confirm the thumb moves to track the
  new position — it previously stayed frozen in place on wheel-scroll specifically (dragging the
  thumb directly worked fine; `UI/Widgets/DataTable.lua`'s own `OnVerticalScroll` handler was
  silently replacing the scrollbar widget's one that kept the thumb in sync, since
  `SetScript` replaces rather than stacks — fixed by hooking the underlying method instead of the
  script event, so the two no longer compete for the same slot).
- Item tooltips on hover: hover the icon in a row — confirm the game's normal item tooltip
  appears (name, stats, everything, the same as hovering it anywhere else), not just a name
  label. Hover the item name/link text next to it — same tooltip. Move off either and the
  tooltip disappears. Confirm the tooltip's own top-left corner lines up with the top-left of
  whichever you hovered, icon or text — both should land in the same relative spot rather than
  the text's (much wider) tooltip appearing in a visibly different place than the icon's.
- This window's title bar also shows "Session started by <name>" while a session is active (new
  this round, same label `UI/SessionFrame.lua` already shows, no realm suffix) — so a candidate
  deciding how to respond can see who's actually running the session, not just the holder. Hidden
  when there's no active session.
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
- Both windows are drag-resizable from a small corner grip, bottom-right (brightens to accent on
  hover) — but **width is now fixed** (changed this round: `UI/LootFrame.lua` locked at 700,
  `UI/SessionFrame.lua` at 630 — each window's own former minimum width, the narrowest that still
  fits its columns without clipping). Confirm dragging the grip diagonally changes the window's
  *height* but the *width* never moves at all, no matter how far sideways you drag — this is
  deliberate: both windows' columns are fixed-width with no reflow, so letting the width change
  never did anything but add or clip blank space on the right. Confirm height still resizes
  freely within its usual bounds, and that a taller `UI/SessionFrame.lua` still shows more item
  icons at once (the icon list is a real scrolling table, so it picks up the extra height).
  Grip glyph: confirm it still shows as a small triangular cluster of 6 dots (3 along the very
  corner, 2 one step in, 1 furthest) and brightens to accent together on hover.
- Every window's header (this one, Session, Options) now shows the brand logo to the left of the
  title, accent-tinted — confirm it re-tints live along with everything else when you change the
  accent color in Options → Appearance.
- Header title/subtitle sizing and alignment (all three windows — this one, Session, Options):
  confirm the white title text is noticeably bigger than before, and reads clearly larger than
  the gray "Session started by <name>" subtitle next to it (Options has no subtitle, just the
  bigger title). Confirm the logo, title, and subtitle all look vertically settled in the header
  bar, roughly centered top-to-bottom in the header strip — specifically: the subtitle shouldn't
  look like it's sitting lower than the title (it's anchored to the title's own baseline, not
  centered against its full bounding box), and the title itself shouldn't look like it's sitting
  a bit above center/too high in the bar (a small manual correction accounts for a FontString's
  "LEFT" anchor centering its full line box — ascent plus descent — rather than the actual
  rendered glyphs, which otherwise visibly reads as "too high" at this now-bigger size). This is
  a visual judgment call with no exact pixel target — if it still looks off after this round,
  say so and the offset can be tuned further.
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
  missed heartbeats, then confirm `/plc forceend` becomes available (no error print) and
  correctly force-ends the session for that client. Also confirm it correctly *refuses*
  (`SESSION_CANNOT_FORCE_END`) if attempted before the threshold has actually passed.
- **Resync:** have a candidate client join the group (or reload) *after* a session has already
  started with items in it. Confirm it auto-requests and receives a full sync within a couple of
  seconds (`/plc sync` to trigger manually) and
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

### 2.5 Bagged-item award flow: stage-everything + Award All as the one commit point
(Reworked again this round — there is no more instant-final Award path at all. Every row's
Award button, and the panel header's Disenchant button, only ever *stage* a pick
(`Session:SetPreAward`); nothing is broadcast, printed, or announced until the holder presses
**Award All**. There is no live loot slot by the time anyone's reviewing either way — a committed
Award still just means "record the decision and tell the holder who to trade it to," not
"transfer it directly.")
- Click Award on a candidate's row for a real (already-bagged) item. Confirm: no wire traffic, no
  chat print, no announcement — the button itself flips to "Staged" on the holder's client only,
  and the candidate clients see no change at all (staging is holder-local, never broadcast). The
  sidebar auto-advances to the next not-yet-finished item immediately.
- Re-click Award on a *different* candidate's row for the same item (navigate back to it first,
  or before it auto-advanced away — either way SetPreAward just overwrites the previous pick):
  confirm the first candidate's button reverts to plain "Award" and the second candidate's button
  now reads "Staged" — only one candidate is ever staged per item.
- Click Disenchant (the header control, next to "N out of M voted") on a different item: confirm
  it stages to the current Enchanter (see 2.8) without needing any candidate row clicked, the
  header button itself flips to "Staged", and the sidebar auto-advances the same way Award does.
- Auto-advance should skip only truly finished (awarded) items, not staged-but-uncommitted ones —
  stage two items in a row and confirm the second stage lands on the very next item, not one
  further down the list.
- Auto-advance should no-op (stay on the last item, not wrap or clear the selection) when staging
  the last item in the list.
- Press **Award All** once several items are staged (a mix of regular Award picks and at least
  one Disenchant): confirm every staged item commits in one pass, each over its own `award` comm
  with the right `reason`, and that:
  - A regular award prints `... awarded to ... -- trade it to them!` and (if
    `profile.announce.award` is on) announces with the winner's name.
  - A disenchant commit prints the disenchant instruction line instead, and announces with the
    item link only — **no winner name** — even though a real roster GUID (the Enchanter) is
    recorded underneath.
  - Both print/announce from the holder's client only; the candidate's client does neither.
  - An item that was never staged is left untouched (still "Pending").
- Attempt to Award All again, or stage-and-commit the same item twice: confirm the already-
  awarded item is simply skipped (not double-committed, not an error).
- The actual item transfer is still manual (holder trades it in-game, or hands it off for
  disenchanting) — confirm the addon does *not* attempt to open a trade window or otherwise touch
  the trade UI.
- A staged-but-never-committed pick (no Award All) does **not** survive End Session: confirm the
  item carries forward to the next Start() (it's not awarded, so it should), but its "Staged"
  state does not — the button should read "Award"/"Disenchant" again and the sidebar tooltip
  should show "Pending", not a leftover "Staged: ..." from the review pass that never actually
  committed it.
- Sidebar icon tooltip wording matches the reason: a committed disenchant reads "Disenchanted"
  (not "Awarded: PlayerName"), and a staged disenchant reads "Staged: Disenchant (EnchanterName)"
  (not "Staged: EnchanterName") — border colors stay the same success/accent as a regular
  award/stage, only the tooltip text branches.

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

### 2.8 Enchanter picker + profession sync (new this round, `Data/Professions.lua`)
- With no Enchanter manually picked yet, open the session window and confirm the dropdown shows
  the alphabetically-first roster member by short name (not full "Name-Realm"), computed live —
  adding/removing a raid member before picking should change the default shown.
- Pick a different roster member from the dropdown (holder's client): confirm it persists across
  `/reload` (saved like `owner`, not reset by Start()/End()) and across several Start/End cycles
  in the same raid night — it should *not* revert to the alphabetical default just because a new
  review pass started.
- Confirm the pick syncs to other clients via the `set_enchanter` comm: the other client's own
  dropdown should reflect the holder's choice without needing a manual resync.
- A non-holder client picking from the dropdown should be a silent no-op (`Session:SetEnchanter`
  is holder-only) — confirm nothing changes on any client when a candidate clicks an entry.
- Profession sync (solo-unverifiable beyond "no Lua error" — needs a second client actually
  trained in Enchanting): at session start (or a late joiner's sync), confirm the Enchanter
  dropdown's entry list is hard-filtered to candidates `Data/Professions.lua` currently shows as
  having Enchanting trained (`PLC.Professions.ENCHANTING_KEY`, matched against
  `GetSkillLineInfo`'s localized name via `L["PROFESSION_ENCHANTING"]` -- Classic/TBC Classic has
  no numeric skill-line ID API, see that file's own comments) — a candidate with a *different*
  primary profession (e.g. Tailoring) or none at all should never appear in the list.
- With nobody's Enchanting synced yet, the dropdown shows "No Enchanter known" rather than
  defaulting to anyone — and `Session:GetEnchanterGuid()` returns nil in that state, not a random
  roster member. Each client re-broadcasts its Enchanting skill whenever its
  skill lines change, so learning/leveling the profession updates the dropdown live.

### 2.9 Trade automation (new this round, `Loot/Trade.lua` + `UI/TradeFrame.lua`)
This is the one round whose core claim (auto-placing an item into a real trade window) genuinely
can't be confirmed by reading code — it needs two live clients actually trading. Watch for
`ADDON_ACTION_BLOCKED`/`ADDON_ACTION_FORBIDDEN` in `/plc errors` on any step below; that's the
addon's own existing taint capture, and the fastest signal if a protected-function assumption
(see `Loot/Trade.lua`'s own file comment) turns out wrong for this client.
- Press **Award All** with at least one staged item: confirm no local "trade it to them!" chat
  line appears anymore (removed this round) — only the raid-chat `AnnounceAward` line, same as
  before.
- The holder's **Loot Trades** window should pop open on its own right after Award All commits
  (no manual open needed), showing the awarded item(s) under "Items to hand out" with the
  winner's name and an "Awarded just now" timer that starts counting up.
- On the winner's own client, the same window should pop open independently, showing the item
  under "Items to collect" with the holder's name.
- Click **Trade** on the holder's row: confirm a real trade window opens with that candidate (if
  nearby) and the item is already sitting in a trade slot — nobody should need to drag it in
  manually. Click **Trade** on the *recipient's* row instead (holder not clicking first) and
  confirm the holder's own client still auto-places the item once the trade opens, since
  placement isn't gated on who initiated it.
- Click **Accept** on both sides manually (this part can never be automated — see the file
  comment) and confirm: the item row disappears from both the holder's and recipient's windows
  within a second or two of the trade closing, and once nothing's left in either section the
  window hides itself on both clients.
- Cancel a trade instead of accepting it: confirm the item stays listed as still needing to be
  traded on both sides (nothing gets marked complete just because a trade window opened and
  closed).
- Close the trade window manually while an item is still pending, then award a *different* item:
  confirm the window does **not** reopen just from a tick (unlike `UI/LootFrame.lua`, this one is
  meant to respect a manual close) — but a genuinely new item becoming pending while the window is
  still empty-and-hidden should still pop it open again. `/plc trades` always force-reopens it
  regardless (or prints that there is nothing to trade).
- On the recipient's row, click **Follow**: confirm it actually starts following the holder (same
  hardware-event requirement as Trade — must be a direct click, not something scheduled).
- A council member owed two different items by the same holder in the same review pass: confirm
  **Trade** places both into the same trade window (up to the game's own trade-slot limit), not
  just the first one.
- Known gap, not a bug to chase: a client that reconnects/resyncs *after* already having won
  something (rather than being online when the `award` command fired live) won't show it in
  "items to collect" — the full-session resync (`session_sync_data`) doesn't currently carry
  award/trade status, only the live `award` broadcast does. Pre-existing limitation, not
  introduced this round.

### 2.10 Loot history: filters, RCLootCouncil import, hover summaries (`Data/HistoryImport.lua`)
- **Filters:** `/plc history` → **Filter**. Lists only classes/responses present in the history.
  Picking a class shows only that class (several can be picked; "Show all classes" clears it);
  un-ticking a response hides it. The Filter label turns accent-colored while anything is
  filtered, the count updates, and **Export** only contains what the table shows. Filters survive
  `/reload`.
- **RC sync, in game (receiver doesn't need RC):** the RC user opens `/rc sync`, picks
  *Loot History* and your character, presses Sync. You get an accept popup → Accept → chat says
  it's receiving, then "Imported N new loot history entries from X". Declining shows RC's own
  "declined your sync request" message on the sender's side. Syncing again imports 0 (duplicates
  skipped by id). If RC is also enabled on *your* character, RC answers the request itself — then
  use Import → "Import from RCLootCouncil" afterwards.
- **Paste:** RC History → Export → *Player Export* → copy → PLC Import → paste → Import.
  A non-export string prints the "isn't a Player Export string" error and imports nothing.
- **Live mirroring:** in a group whose master looter (or leader) runs RC, every RC award appears
  in your `/plc history` as it happens. Option: General → "Store loot history from an
  RCLootCouncil master looter".
- **Hover:** in the Loot Session window, hover a candidate's name → their history totals per
  response plus their 6 most recent items, and a warning line if they already received the item
  being reviewed. Hover a sidebar item icon or the item name above the grid → who already
  received that item (newest first).
