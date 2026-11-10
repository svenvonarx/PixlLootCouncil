local _, PLC = ...

-- Generated from CHANGELOG.md by tools/make_changelog_lua.py. Edit the changelog, not this.
PLC.CHANGELOG_TEXT = [[
# Changelog

## Unreleased

Fixes and changes from the second raid night.

- **Fixed: minutes of delay after leaving a raid.** Everyone's loading screen ended at a different
  moment, and each asked to catch up. The master looter answered each with the whole session, at
  the server's 1 message a second, and new items (Gruul's loot), awards and the session's end waited
  behind all of it. Catch-ups, shared history and gear now go on their own channel and never hold
  up the session's own messages. Only one catch-up answer is sent at a time, for everyone who asked.
- **You can see it sending.** The Loot Session window shows when messages are still going out to the
  raid, and after Award All chat says once the raid has the awards. Stay online until it does.
- **Fixed: loot listed twice again**, as with Illidan and the Illidari Council, whose four corpses
  share one loot. Items lying in a corpse are matched by item, not by corpse. The list also never
  holds more copies of an item than your bags do: extra copies leave it, with a chat line. Auto
  loot gives the server more time to confirm a hand-out before calling it failed, and loot that
  reaches your bags some other way gets its boss instead of "Unknown" in the history.
- **Awarded items stay in the Loot Session window**, after the ones still to decide, with the votes
  they were awarded on, so you can look back at who else wanted a spare token. The winner's row says
  who got it. They stay until the master looter removes them: Remove All clears everything except
  what's awarded and not yet handed over.
- **Pass by itself on loot you can't use**, as RCLootCouncil does: another class's tokens, armor or
  weapons you can't use, patterns for a profession you don't have or already know, and caster
  weapons for warriors, rogues and hunters (or physical ones for priests, mages and warlocks). The
  council sees the Pass with a note saying why. Options → General turns it off.
- **Compact Loot Timers**, like Gargul's list: smaller rows, up to 16 before it scrolls.
- **`/plc preview 40`** starts a preview with a raid night's worth of real Black Temple and Hyjal
  loot, some of it twice, to try a busy session with the raid.

## 0.8.1-beta

More raid materials kept out of loot sessions, and every item rule yours to change.

- **Mark of the Illidari, Heart of Darkness, Primal Nether and Nether Vortex** are now handled like
  raw epic gems: auto looted to the master looter, never up for review. Sunmote still stays in the
  loot window.
- **Change the defaults for yourself.** Options → Auto Loot lists every item with a rule. Click one to
  change it, including to the new **Master looter, not reviewed**, then press Add. A default you
  changed is shown in color, and its x brings the default back. Only your changes are saved, so new
  defaults in later versions still reach every item you haven't changed.

## 0.8.0-beta

Fixes and changes from the first raid night. **Everyone in the raid needs this version**: Award All
now sends its results in a way older versions don't understand.

- **Fixed: Award All could lose awards.** Every award and its history entry went out as its own
  addon messages, and the server lets an addon send 10 at once, then 1 a second. So a big Award All
  took over a minute to send, with the session's end at the back. Council members kept seeing a
  running session, and logging off in that time lost the rest. Award All now sends everything in one
  message, followed by the session's end, which takes a moment. **Everyone needs this version** to
  see Award All's results.
- **Fixed: some award lines were missing from raid chat.** They were all sent at once, and the
  server dropped some. They now go out one a second.
- **Fixed: loot listed twice**, as happened with Illidan. When the server was slow to confirm a
  hand-out, the bag check had already listed the item, and the confirmation listed it again.
  Reopening a corpse could also list noted items again, because its loot slots are numbered anew.
- **Raw epic gems are auto looted again**, wherever review loot goes, but never go up for review.
  0.7.2 left them in the loot window instead.
- **Votes are sorted** in the Loot Session window: by answer, in the order of the buttons (BiS
  first), then those who haven't answered, with Pass last.
- **An item that dropped twice is answered once.** Its copies share one line in the Loot Response
  window, with a count on the icon. The master looter still awards each copy on its own.
- **Bigger windows**: everything is 25% bigger, and Options → Appearance → Scale sets the size from
  50% to 200%.
- **Loot Session window**: four item icons a row instead of two, so it isn't as tall. Drag its
  corner sideways to make the whole window bigger or smaller, and down for more items.
- **Fixed:** an error about an unknown event (`SKILLLINES_CHANGED`) at every login.
- **Share loot history**, for anyone who missed awards, such as the ones Award All lost. The
  **Share** button in Loot History sends the awards you handed out yourself, among the entries shown
  with your filters, to everyone online in your guild and group. `/plc share` does the same for the
  last 7 days, `/plc share 2026/11/05` from that date on. Others only take awards the sender handed
  out themselves, and skip any they already have, so sharing twice is fine.

## 0.7.4-beta

- **Fixed:** pasting a long text into Loot History's import box, such as RCLootCouncil's CSV export
  of a long history, froze the game for minutes or crashed it. The box now shows a short note saying
  how much was pasted, and Import still gets all of it.
- Pasting the wrong export now says which one to pick: Player Export, not CSV or TSV.

## 0.7.3-beta

- **Fixed:** importing a big loot history from RCLootCouncil could freeze the game for minutes, or
  crash it. Every entry was checked against all the entries stored for that player, so thousands
  under one name, such as a disenchanter's, took minutes. Importing tens of thousands of entries now
  takes a moment.

## 0.7.2-beta

Raw epic gems stay out of loot sessions, and stacked loot shows its real trade status.

- **Raw epic gems are excluded**: Crimson Spinel, Empyrean Sapphire, Lionseye, Shadowsong Amethyst,
  Pyrestone and Seaspray Emerald. Like Mark of the Illidari, they stay in the loot window for you to
  assign through Blizzard's list, and sessions don't review them. Gems already in your list leave it
  by themselves, with one chat line.
- **Fixed:** loot that stacks in the bags, such as a second gem or Nether Vortex, showed "No timer"
  instead of BoE or its trade time, and didn't leave the list when it left the bags. It now reads
  the stack's.

## 0.7.1-beta

Loot that's no longer in the master looter's bags stops showing up in loot sessions.

- **Fixed:** loot that left the master looter's bags without being awarded stayed in the loot session
  for good. For example, loot handed out with another addon, mailed or sold kept opening Loot Timers
  after every login. BoE items never ran out of trade time, so they never left. Now such an item
  leaves the session about 10 seconds after it's gone, with a chat line naming it. A session left
  with nothing to review ends. Items in the bank count as gone too.

## 0.7.0-beta

Raider mode, for when you're master looter but someone else's loot addon runs the loot.

- **Raider mode**, for anyone who's sometimes master looter but runs the loot by hand or with another
  addon such as Gargul. As master looter, PixlLootCouncil then doesn't loot, collect loot or start
  sessions by itself, and doesn't change who's master looter or the loot threshold. Loot sessions
  someone else starts still open as usual. Picking Raider in the welcome window turns it on, Loot
  Master turns it off, and `/plc raider` switches it any time. If you picked Raider before this
  update, type `/plc raider` once, because that choice wasn't saved.

## 0.6.2-beta

The Loot Response window stays open while items wait for your answer.

- The Loot Response window has no close button anymore, and Escape leaves it open. It came back
  within a second anyway while any item was waiting for an answer. It still goes by itself once
  every item is answered or its time runs out.

## 0.6.1-beta

Two fixes from testing: Shift stops auto loot reliably, and Badge of Justice stays out of loot sessions.

- **Fixed:** holding Shift while opening a corpse didn't always stop auto loot. The game can report
  the same loot window opening twice, and letting go of Shift before the second time started auto
  loot after all. Shift now counts for the whole window, and pressing it with the window already
  open stops auto loot there and leaves the rest to you.
- **Fixed:** Badge of Justice joined the Loot Session window. Everyone loots their own, so it's
  never reviewed now, and auto loot takes the master looter's own badge like any other player
  would. Badges collected before this update can be removed with Remove or Remove All.

## 0.6.0-beta

A cleaner, more compact Loot Response window that fits its items, windows that come to the front
when you click them, and fixes for items that stayed in the Loot Response window when they
shouldn't.

- **The window you open or click comes to the front**, like windows on a desktop. Before, each
  window had a fixed place: Loot Response always covered the Loot Session window, which always
  covered Options, and Loot Trades covered everything. The game's confirmation pop-ups now always
  show above the addon's windows. Loot Timers stays below everything, out of the way.
- **A more compact Loot Response window.** Rows run edge to edge, so the countdown crosses the
  whole window, with a thin line between items. The icon, the buttons and the note are all one
  height, and there's no empty strip under the last row. The note is a single line of up to 50
  characters, and wider by default.
- **The Loot Response window resizes in width.** Wider gives the note more room. Narrower cuts the
  item name short, then narrows the note, and finally hides the name; hovering the icon still shows
  the item.
- **The Loot Response window fits its items.** It's never taller than the items need, so there's no
  empty space and no scrollbar you don't need, and it can't be dragged taller than that. The
  height you drag it to is remembered: fewer items shrink it, more grow it back to that height,
  and only then does it scroll. It grows and shrinks at the bottom, in whole rows.
- **A tidier Loot Session window.** The item name, its trade time and the vote count sit level with
  the Banking and Disenchant buttons. Those buttons and the candidates' Award buttons end in line
  with the toolbar above. The item icons are a little bigger, with even space on both sides, and the
  window keeps the same margin all around. End Session moved to the bottom-right corner.
- **Fixed:** an item whose time ran out could stay in the Loot Response window, most often while
  you were typing a note. One error was enough to stop the window's countdown for good; now
  nothing stops it, and errors show in `/plc errors`. The same goes for every other repeating
  task, such as the master looter's check-ins.
- **Fixed:** the Loot Response window showed items nobody can get anymore, such as an item whose
  trade time ran out before the session. It now shows only items that are up for review, and an
  item goes from it as soon as its trade time runs out.
- **Fixed:** when an item went while you were typing its note, the cursor moved on to the next
  item, and a hidden note box could keep the keyboard.

## 0.5.0-beta

Loot sessions now reach everyone, wherever they are and whatever they missed, the addon speaks every
client language, and a welcome window sets new users up, including a one-click move from
RCLootCouncil.

- **Sessions reach everyone, wherever they are.** Anyone on a loading screen when a session starts,
  or who misses part of one for any other reason, catches up by themselves within seconds: right
  after the loading screen, and otherwise at the session's next check-ins. Answers the master looter
  missed are sent again by themselves, and a session that ended while someone was away ends for
  them too. When many people catch up at once, the master looter answers them all with one message.
  You no longer have to wait for the loot window before zoning out of the raid.
- The master looter checks in every 10 seconds instead of every 60, which is also how quickly
  anything missed gets repaired.
- **Welcome window**: the first time the addon loads, it asks whether you're a raider or the loot
  master. Raiders are done in one click. A loot master can import their loot history and the
  settings they changed in RCLootCouncil with one button, or pick the essentials: auto loot, the
  council, raid chat announcements and the time to respond. `/plc setup` or Options → About shows it
  again.
- **Every client language**: the addon is translated into German, Spanish, French, Italian, Portuguese,
  Russian, Korean and Simplified and Traditional Chinese, using Blizzard's own terms where they exist.
  The translations are machine-written, so corrections are welcome. It also works properly on those
  clients now: one-click Disenchant, finding the raid's Enchanter and trade timers relied on English,
  and Korean and Chinese clients use the game's font, because Inter doesn't have those characters.
- **Changelog** in Options, so you can see what changed in each version without leaving the game.
- **Reset all data** under Options → About (or `/plc reset`) deletes every setting and the whole loot
  history after a warning, then reloads.
- The Pixl Gold theme is now called Default.
- **Fixed** session messages going to a battleground's group instead of the raid for anyone who
  queued into one from the raid.
- **Fixed** catching up after a reload losing your items to collect in Loot Trades.

## 0.4.0-beta

The Loot Session window gets Banking and shows who already has an item, Options gets a full overhaul
with themes and selectable fonts, and the master looter can be set automatically from a list.

- **Banking**: next to Disenchant in the Loot Session window, for items you keep. It's recorded in the
  loot history as Banking, the same way RCLootCouncil records it, and nothing shows up in Loot Trades.
- **Already has it**: the Loot Session window marks everyone who has received the item you're
  reviewing with a red **Has** next to their name, from the loot history. Hovering the name says when.
  Banked and disenchanted items don't count, here or in the history tooltips.
- **Master looter list** (Options → Master Looter): when you switch the group to Master Loot, the first
  person on your list who's online in the group becomes master looter. Handing it to someone else
  afterwards sticks, and holding Shift skips it once. The same page can set the loot threshold at that
  moment too.
- **Themes**: Options → Appearance now has eight themes instead of an accent color: Pixl Gold, which is
  the look you already know, Sunwell, Fel, Zangarmarsh, Frost, Twilight, Arcane and Nether. Each has
  its own backgrounds, and they all keep the trade timers and Staged/Awarded easy to tell apart. A
  custom accent color isn't carried over.
- **Fonts**: the same page lets you pick any font registered with LibSharedMedia, shown in that font in
  the list. Inter stays the default, and other addons can now use it too.
- **Update notices**: if your version is out of date you get one chat line, at most once a day. If
  you're a whole version behind, you also get one pop-up, which waits until you're out of combat, out
  of instances and not in a loot session. You hear about new versions from your guild as well as your
  group, and it's remembered between logins. Options → About turns it off.
- **Options overhaul**: a selected menu entry now runs the full width of the menu, and the logo,
  section titles and icons share one left edge. Pages have more room, and General is split into Raid
  chat, RCLootCouncil, Loot and Timing. Auto Loot, Master Looter, Preview and About have their own
  icons.
- **Clearer settings**: every option has a tooltip explaining it, and labels use plain words. Minimum
  quality is a choice of names in the game's colors instead of a number, and sliders show their value
  with its unit, lined up on the right.
- **About page** (`/plc about`): your version, the version of everyone in your group, and the credits.
- **Addon list**: PixlLootCouncil now has its own icon, sits in the Loot category with Gargul and
  RCLootCouncil, and has a clearer description.
- The up and down buttons on the Responses and Master Looter pages are now proper matching arrows.
- **Fixed** the Stop Preview button in Options staying on Stop when a preview ended any other way, such
  as End Session in the Loot Session window.
- **Fixed** Award All opening an empty Loot Trades window when nothing was left to trade.
- **Fixed** long item names running into the vote count in the Loot Session window. Text in that row
  is cut short only where something else needs the room. Hovering shows the whole text, and an item's
  tooltip now includes its trade time. The vote count itself is shorter, as "25/25 voted".
- **Fixed** the Auto Loot exception list using the wrong row height.

## 0.3.0-beta

Raiders can now answer a master looter who runs RCLootCouncil without having RCLootCouncil installed.

- **RCLootCouncil sessions**: the master looter's items open in the Loot Response window, with their
  buttons (per item type too), timer and note requirements. Your answer goes back to the master
  looter, rolls work, and you don't show as offline or missing the addon in their window. If you join
  or reload mid-session you catch up automatically. While RCLootCouncil itself is running on your
  client this stays off, and Options → General turns it off by hand.
- **Fixed** loot history from an RCLootCouncil master looter being dropped unless they were also the
  group leader, because the loot method was compared with the wrong value. Awards they share now
  reach your history, and deletions follow.

## 0.2.0-beta

The master looter's loot window now hands out loot by itself, and there's a preview mode for
practicing the whole workflow with your group.

- **Loot Timers window**: the Loot Session window minimizes to a small list of picked-up items waiting
  for review, most urgent first, showing each item's remaining trade time. It appears by itself when
  new loot reaches the bags and remembers its position. `/plc timers` shows or hides it.
- Only epics, legendaries and patterns are collected by default, so raid materials such as Mark of the
  Illidari, Heart of Darkness and Sunmote stay out. The default quality threshold is now Epic, and
  patterns count at any quality from uncommon up.
- **Auto loot**: replaces the old self-looting, which went through the wrong game call. The master
  looter's loot window now hands items out by itself. Options → Auto Loot sets who gets review loot
  and other master loot (master looter, leave it, or players with fallbacks), with per-item exceptions,
  gold, and an option for world bosses. Failures name the reason, such as full bags, and each item is
  retried when the corpse is reopened. Hold Shift while opening loot to skip it. `/plc autoloot`
  toggles it.
- Only loot that actually reached the master looter joins a session now.
- **Excluded items**: a curated list (`Data/ExcludedItems.lua`) of raid materials that are never
  auto looted or reviewed, starting with Mark of the Illidari, Heart of Darkness, Sunmote and Primal
  Nether. They stay in the window to assign through Blizzard's list, and quest items do the same.
- **Preview mode**: `/plc preview` or Options → Preview runs the whole workflow in a group with
  fictional items and trade timers. Nothing is saved to the history, everyone's real state comes back
  afterwards, and trades use BoE items from the holder's bags as stand-ins.
- Raid announcements use the current chat API instead of a deprecated one.
- **Custom responses**: Options → Responses can rename, recolor, reorder, add (up to 7) and remove
  response buttons. The session holder's set goes to everyone in the session, including anyone who
  joins or reloads later. A running session keeps its buttons; edits apply to the next one.
- Players who join the group, log in or reload during a session now catch up automatically, and
  their windows update when they do.
- An item now counts as bagged as soon as it's found in the bags, however it got there.

## 0.1.0-beta

First public test version.

- **Loot collection**: the master looter silently collects qualifying loot into their bags. Trade-time
  tracking covers soulbound items (2-hour trade window) and BoE recipes from the raid, with chat
  reminders at 20 and 5 minutes left.
- **Loot Session window**:
  - council review with responses, notes, equipped items and item level differences
  - hover summaries of each player's loot history
  - staged picks with Disenchant routing to the raid's Enchanter
  - **Award All** to commit and end the session
  - **Remove All** to clear the list
- **Loot Response window** for raiders: BiS / Upgrade / PvP / OS / Pass plus a note.
- **Loot Trades window**: Trade auto-fills the awarded items, Follow, one-click Disenchant, trade time
  left, and double-click removal for stuck entries.
- **Council**:
  - the master looter is always on it, plus raid leader & assistants, guild ranks or manual names
  - only the council sees votes, and only the session holder awards
- **Loot history**:
  - stored in RCLootCouncil's format, with filters
  - TSV export for Google Sheets / English Excel and International Excel
  - import from RCLootCouncil via `/rc sync`, live mirroring, Player Export paste or local RC data
- **Auto-start** of sessions when the master looter collects loot.
]]
