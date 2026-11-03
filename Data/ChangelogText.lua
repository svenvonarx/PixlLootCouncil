local _, PLC = ...

-- Generated from CHANGELOG.md by tools/make_changelog_lua.py. Edit the changelog, not this.
PLC.CHANGELOG_TEXT = [[
# Changelog

## Unreleased

- **The window you open or click comes to the front**, like windows on a desktop. Before, each
  window had a fixed place: Loot Response always covered the Loot Session window, which always
  covered Options, and Loot Trades covered everything. The game's confirmation pop-ups now always
  show above the addon's windows. Loot Timers stays below everything, out of the way.
- **A more compact Loot Response window.** Rows run edge to edge, so the countdown crosses the
  whole window, with a thin line between items. The icon, the buttons and the note are all one
  height. The note is a single line of up to 50 characters, and wider by default.
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
- The Loot Response window no longer has an empty strip under its last row.
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
