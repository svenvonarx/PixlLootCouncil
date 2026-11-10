# PixlLootCouncil

A loot council addon for **World of Warcraft: TBC Anniversary Classic**. The master looter collects the
raid's loot as it drops, the council reviews everyone's interest in one window, and a single
**Award All** hands everything out. Trades are guided, and every award is kept in a loot history you
can browse and export.

> **Beta.** This is an early test version. Expect rough edges, and please report what you find (see
> [Reporting bugs](#reporting-bugs)).

## Features

### Sessions that reach everyone

Group messages in WoW only reach the people who are there to receive them. Whoever is on a loading
screen at that moment simply never gets them, and a session that's announced once can be missed
entirely. PixlLootCouncil doesn't rely on any single message arriving:

- The master looter checks in every few seconds with a short summary of the session. Anyone whose
  copy doesn't match, from a loading screen, a disconnect or a lost message, catches up by
  themselves, and answers the master looter missed are sent again.
- After every loading screen, not just a reload, the addon asks for the session straight away.
- A session that ended while someone was away ends for them too.
- If many people catch up at once, the master looter answers them all with one message.

You can zone out of the raid and travel while a session runs, and the window is there when you
arrive.

### For the master looter

- **Auto loot.** Open a corpse and the loot goes where it should. Items at or above your quality
  threshold (Epic by default) and all patterns go straight into your bags, and everything else can go
  to a mule, with fallback names if someone's bags are full. Add exceptions for single items, or turn
  it off under Options → Auto Loot. Hold Shift while opening loot to do that corpse by hand, or press
  it with the window open to take over from there. Your own Badge of Justice is looted for you and
  never goes up for review, as everyone loots their own.
- **Master looter list.** Choose who should run the loot, in order. When you switch the group to
  Master Loot, the first of them who's online in the group gets it, and the loot threshold can be set
  at the same moment. Changing either afterwards sticks.
- **Item rules.** Raid materials (Mark of the Illidari, Heart of Darkness, Primal Nether, Nether
  Vortex) and raw epic gems go to the master looter but never up for review, since raids keep them.
  Sunmote stays in the loot window for you to assign through Blizzard's list. Under Options → Auto
  Loot you can change any of these for yourself, or add your own; only what you change is saved, so
  defaults added in later versions still reach you. The defaults are in `Data/ExcludedItems.lua`.
- **Trade-time tracking.** Each item in your bags shows how long it can still be traded: soulbound
  loot has a 2-hour trade window, and BoE recipes from the raid have no limit. You get a chat reminder
  at 20 and 5 minutes, and expired items are flagged.
- **Loot Timers window.** Minimize the Loot Session window to a small list of what you've picked up
  for review, most urgent first, with each item's trade time left. It appears by itself when new loot
  reaches your bags.
- **Auto-start.** Collecting loot can start a session by itself a few seconds later.
- **Preview mode.** `/plc preview` or Options → Preview runs the whole workflow with your group on
  fictional items and trade timers. `/plc preview 40` does it with a raid night's worth of real Black
  Temple and Hyjal loot, to try a busy session. Nothing is saved to the history, and your real loot
  list comes back afterwards.

### For the council

- **One review window** with every candidate's response and note, equipped items, item level
  difference and role.
- A red **Has** next to anyone who has already received the item. Hover a name to see what that
  player has received, or the item to see who already got it.
- The session holder stages a pick per item: **Award** to a candidate, **Disenchant** to the raid's
  Enchanter, or **Banking** to keep it, which only records it. **Award All** commits everything at
  once, and the council sees staged picks live.
- **You decide who's on it**: the master looter always is, and you can add the raid leader and
  assistants, guild ranks, or individual names. Only the council sees responses, and only the session
  holder awards.

### For raiders

- A compact **Loot Response** window: one line per item, with a countdown across the row and an
  optional note. It's only as tall as the items need, up to the height you last dragged it to, and
  resizes in width: narrower, the item name gives way first. The master looter can change the
  buttons under Options → Responses, and everyone in the session sees the same set. Only items you
  can still get are shown: not ones whose trade time ran out.
- **Loot Trades** lists what you're owed. **Trade** opens the trade and places the items, **Follow**
  walks you to the other player, and items you disenchant yourself get a one-click **Disenchant**.

### Loot history

- Every award is recorded, browsable with date, name, class and response filters.
- Exports to TSV for Google Sheets and English Excel, or for International Excel.
- Shared with everyone in the group who has the addon, so the whole raid keeps the same record.
- **Share** sends the awards you handed out yourself, among what the window shows, to everyone online
  in your guild and group: for anyone who missed some. `/plc share` does the same for the last 7 days,
  `/plc share 2026/11/05` from that date on. Others only take awards the sender handed out, and skip
  what they already have.

### Everything else

- **Welcome window**: the first time, choose raider or loot master. Raiders are done in one click; a
  loot master imports from RCLootCouncil in one click, or picks the essentials. `/plc setup` shows it
  again.
- **Changelog** in Options, for what changed in each version.
- **Every client language**: English, German, Spanish, French, Italian, Portuguese, Russian, Korean and
  Simplified and Traditional Chinese.
- **Windows stack like on a desktop**: the one you open or click comes to the front, and the game's
  confirmation pop-ups and tooltips always show above them.
- **Themes, fonts and size**: eight themes under Options → Appearance, any font your addons have
  registered, and a Scale setting for how big the windows are. Drag the Loot Session window's corner
  sideways to make just that window bigger.
- **Version check**: Options → About lists the version everyone in your group runs. If yours is out of
  date you get a quiet reminder: one chat line a day, and one pop-up if you're a whole version behind,
  never in combat, an instance or a loot session.

## Requirements

- TBC Anniversary Classic.
- **Master Loot** for the full workflow (auto loot, sessions, trades).
- Raiders need the addon to respond to a session. People without it show as *No addon detected*.

## Getting started

### Master looter

1. Set the group's loot method to **Master Loot** and open corpses as usual. Qualifying items are
   handed to you automatically. Change who gets what under Options → Auto Loot, and the quality
   threshold under Options → General.
2. Type `/plc` to open the **Loot Session** window, then press **Start Session**. With auto-start on
   (the default), this happens by itself a few seconds after you collect loot.
3. For each item, click **Award** next to a candidate, **Disenchant**, or **Banking** for items you
   keep. This only *stages* the pick and moves on to the next item.
4. Press **Award All** when you're done. The awards are announced, recorded in the history, and the
   session ends.
5. In **Loot Trades**, click **Trade** next to each item (or open a trade with the winner) and confirm
   the trade.

### Council members

Open `/plc` during a session to see responses, notes and gear comparisons, and to follow the master
looter's staged picks. Awarded items stay listed with the votes they were awarded on, so you can look
back at who else wanted something. Who's on the council is set by the master looter under
**Options → Council**.

### Raiders

When a session starts, the **Loot Response** window opens. Pick a response for each item and add a
note if you like. Items your character can't use (another class's token, plate on a mage, a pattern
for a profession you don't have) get a Pass by themselves and don't show; Options → General turns
that off. It stays open until every item is answered or its time
runs out. Awarded items show up in **Loot Trades** with a **Trade** button.

If you pick Raider in the welcome window, you're in **raider mode**: when you're master looter, the
addon doesn't loot, collect or start sessions by itself, so you can run the loot by hand or with
another addon such as Gargul. Sessions someone else starts still open. `/plc raider` turns it on or
off.

## Slash commands

| Command | What it does |
|---|---|
| `/plc` | Open the Loot Session window |
| `/plc timers` | Show or hide the Loot Timers window |
| `/plc autoloot` | Turn auto loot on or off |
| `/plc raider` | Turn raider mode on or off: as master looter, leave the loot to you or another addon |
| `/plc preview [count]` | Start or stop a practice session with fictional loot, with that many items if given |
| `/plc about` | Show your version, your group's versions and the credits |
| `/plc loot` | Reopen the Loot Response window |
| `/plc trades` | Reopen the Loot Trades window |
| `/plc history` | Open the Loot History window |
| `/plc share [yyyy/mm/dd]` | Share the awards you handed out with your guild and group: the last 7 days, or from that date on |
| `/plc options` | Open the options |
| `/plc additem <link or ID>` | Add an item to the session by hand |
| `/plc sync` | Re-sync the current session from its holder |
| `/plc forceend` | End a session whose holder stopped responding |
| `/plc errors` | Show captured Lua errors (include these in bug reports) |
| `/plc setup` | Show the welcome window again |
| `/plc reset` | Delete all addon data, after a warning |
| `/plc help` | List all commands |

The Loot Session window also has buttons to open the other windows.

## Coming from RCLootCouncil

PixlLootCouncil is built on the idea of [RCLootCouncil](https://github.com/evil-morfar/RCLootCouncil2),
and it's designed so you can switch without losing anything.

### Bring your history

The welcome window, which opens the first time (or `/plc setup`), imports your history and the
settings you changed in RCLootCouncil that mean the same here, in one click: the council, guild
ranks, response buttons, time to respond, announcements and auto-start. It needs RCLootCouncil
enabled on that character. You can also import only the history: open `/plc history` and press
**Import**:

- If RCLootCouncil is installed on your character, **Import from RCLootCouncil** copies its history
  directly.
- Otherwise, ask the loot master to open `/rc sync`, choose *Loot History*, and pick you. You'll get an
  accept prompt.
- You can also paste an RCLootCouncil *Player Export*.

Importing twice is safe, as entries you already have are skipped. The history is stored in the same
format and exports use the same TSV layout, so spreadsheets built on RCLootCouncil exports keep
working.

### Raid with a master looter who still uses RCLootCouncil

You can disable RCLootCouncil and keep raiding. Their sessions open in your Loot Response window with
their buttons, timer and any note requirement, your answer goes back to them, and rolls work. If they
share awards with the raid, those land in your loot history too. Turn this off under Options → General.

If you keep RCLootCouncil enabled, it answers its own sessions and PixlLootCouncil stays out of the
way. The master looter should run loot with only one of the two.

What doesn't carry over to an RCLootCouncil master looter: you can't vote as a council member, as that
needs RCLootCouncil's voting window. There's no auto pass either, tier tokens show no gear comparison
on their side, and their `/rc version` lists you as not having RCLootCouncil.

## Known limitations

- Translations are machine-written, so some wording may be off. Corrections are welcome on GitHub.
- There's no council vote count: the session holder makes the call, and the history's vote count is
  always 0.

## Reporting bugs

Please open an issue on [GitHub](https://github.com/svenvonarx/PixlLootCouncil/issues) and include:

- what you did and what happened
- the output of `/plc errors`
- whether you were the master looter, a council member or a raider

## Credits and license

PixlLootCouncil is free software under the **GNU General Public License v3.0 or later**; see
[LICENSE](LICENSE).

- **[RCLootCouncil](https://github.com/evil-morfar/RCLootCouncil2)** (GPL-3.0) is where the idea comes
  from: a loot council run from one review window, with responses, notes and gear comparisons. For
  compatibility, the loot history format, the TSV export layout, the in-game sync and session protocol,
  and a few item helpers follow RCLootCouncil.
- Auto loot's idea of rules, fallback targets and Shift to skip is inspired by the PackMule module in
  [Gargul](https://www.curseforge.com/wow/addons/gargul). No Gargul code is used.
- Bundled libraries:
  - [Ace3](https://www.wowace.com/projects/ace3) (BSD-style license)
  - [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) (zlib license)
  - [LibSharedMedia-3.0](https://www.curseforge.com/wow/addons/libsharedmedia-3-0) (LGPL 2.1)
  - LibWindow-1.1 (public domain)
- Font: [Inter](https://rsms.me/inter/) by The Inter Project Authors, SIL Open Font License 1.1 (see
  `font/Inter-LICENSE.txt`).
