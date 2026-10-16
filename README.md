# PixlLootCouncil

A loot council addon for **World of Warcraft: TBC Anniversary Classic**. The master looter collects the
raid's loot as it drops, the council reviews everyone's interest in one window, and a single
**Award All** hands everything out. Trades are guided, and every award lands in a loot history that
uses RCLootCouncil's format.

> **Beta.** This is an early test version. Expect rough edges, and please report what you find (see
> [Reporting bugs](#reporting-bugs)).

## Features

- **Silent loot collection.** As master looter you just loot. Items at or above your quality
  threshold go straight into your bags, with no popups mid-pull.
- **Trade-time tracking.** Each bagged item shows how long it can still be traded: soulbound loot
  has a 2-hour trade window, and BoE recipes from the raid have no limit. You get a chat reminder at
  20 and 5 minutes, and expired items are flagged.
- **Loot Response window** for raiders: BiS / Upgrade / PvP / OS / Pass plus an optional note, with
  a countdown.
- **Loot Session window** for the council:
  - every candidate's response and note, equipped items, item level difference and role
  - hover a name to see what that player has received; hover an item to see who already got it
  - the session holder stages a pick per item (or **Disenchant** to the raid's Enchanter), then
    commits everything with **Award All**
  - the council sees staged picks live
- **Loot Trades window** listing what you still have to hand out or collect, with trade time left:
  - **Trade** opens a trade and puts the awarded items in for you; you still click the trade
    window's Trade button
  - **Follow** walks you to the other player
  - one-click **Disenchant** for items you disenchant yourself
- **Loot history**:
  - stored in RCLootCouncil's exact format, browsable with date, name, class and response filters
  - exports to *TSV (Google Sheets & English Excel)* and *TSV (International Excel)*, so existing
    RC spreadsheets keep working
- **Import from RCLootCouncil**:
  - receive a loot master's history in game via RC's own `/rc sync`
  - record an RC master looter's awards live during raids
  - paste RC's *Player Export*
- **Council you control**:
  - the master looter is always on it; add raid leader & assistants, guild ranks, or individual names
  - only the council sees votes, and only the session holder can award
- **Auto-start**: collecting loot as master looter can start a session by itself.

## Requirements

- TBC Anniversary Classic.
- **Master Loot** for the full workflow (collection, sessions, trades).
- Raiders need the addon to respond to a session. People without it show as *No addon detected*.

## Getting started

### Master looter

1. Set the group's loot method to **Master Loot** and loot as usual. Qualifying items are collected
   into your bags. Change the quality threshold under Options → General.
2. Type `/plc` to open the **Loot Session** window, then press **Start Session**. With auto-start on
   (the default), this happens by itself a few seconds after you collect loot.
3. For each item, click **Award** next to a candidate, or **Disenchant**. This only *stages* the pick
   and moves on to the next item.
4. Press **Award All** when you're done. The awards are announced, recorded in the history, and the
   session ends.
5. In **Loot Trades**, click **Trade** next to each item (or open a trade with the winner) and confirm
   the trade.

### Council members

Open `/plc` during a session to see responses, notes and gear comparisons, and to follow the master
looter's staged picks. Who's on the council is set by the master looter under **Options → Council**.

### Raiders

When a session starts, the **Loot Response** window opens. Pick a response for each item and add a
note if you like. Awarded items show up in **Loot Trades** with a **Trade** button.

## Slash commands

| Command | What it does |
|---|---|
| `/plc` | Open the Loot Session window |
| `/plc loot` | Reopen the Loot Response window |
| `/plc trades` | Reopen the Loot Trades window |
| `/plc history` | Open the Loot History window |
| `/plc options` | Open the options |
| `/plc additem <link or ID>` | Add an item to the session by hand |
| `/plc sync` | Re-sync the current session from its holder |
| `/plc forceend` | End a session whose holder stopped responding |
| `/plc errors` | Show captured Lua errors (include these in bug reports) |
| `/plc help` | List all commands |

The Loot Session window also has buttons to open the other windows.

## Coming from RCLootCouncil

- **History**: open `/plc history` → **Import**.
  - If RCLootCouncil is installed on your character, **Import from RCLootCouncil** copies its history
    directly.
  - Otherwise, ask the loot master to open `/rc sync`, choose *Loot History*, and pick you. You'll get
    an accept prompt.
  - You can also paste an RC *Player Export*.
  - Importing twice is safe; duplicates are skipped.
- **Exports** use RC's TSV layout, so spreadsheets built on RC exports keep working.
- **Running both**: raiders can keep RCLootCouncil installed. The master looter should use only one of
  the two addons to run loot.

## Known limitations

- Trade-time tracking reads the item tooltip and currently understands the **English** client only.
- The interface is English only; translations are welcome.
- History `votes` is always 0, because PixlLootCouncil has no council vote count.

## Reporting bugs

Please open an issue on [GitHub](https://github.com/svenvonarx/PixlLootCouncil/issues) and include:

- what you did and what happened
- the output of `/plc errors`
- whether you were the master looter, a council member or a raider

## Credits and license

PixlLootCouncil is free software under the **GNU General Public License v3.0 or later**; see
[LICENSE](LICENSE).

- The loot history format, the TSV export layout, the in-game sync protocol and a few item helpers
  follow [RCLootCouncil](https://github.com/evil-morfar/RCLootCouncil2) (GPL-3.0) for compatibility.
- Bundled libraries:
  - [Ace3](https://www.wowace.com/projects/ace3) (BSD-style license)
  - [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) (zlib license)
  - LibWindow-1.1 (public domain)
- Font: [Inter](https://rsms.me/inter/) by The Inter Project Authors, SIL Open Font License 1.1 (see
  `font/Inter-LICENSE.txt`).
