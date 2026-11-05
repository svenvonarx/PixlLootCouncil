# PixlLootCouncil

**Loot council for TBC Anniversary Classic.** The master looter collects the raid's loot as it drops, the council reviews everyone's interest in one window, and a single click hands it all out. Trades are guided, and every award is kept in a loot history you can browse and export.

> **Beta.** This is an early test version. Please report what you find on [GitHub](https://github.com/svenvonarx/PixlLootCouncil/issues).

## Sessions that reach everyone

Group messages in WoW only reach whoever is there to receive them, so someone on a loading screen when a session starts can miss it entirely. PixlLootCouncil doesn't rely on any single message arriving: the master looter checks in every few seconds, and anyone who missed something, from a loading screen, a disconnect or a lost message, catches up by themselves within seconds. Answers that got lost are sent again. You can zone out and travel while a session runs, and the window is there when you arrive.

## For the master looter

- **Auto loot.** Open a corpse and the loot goes where it should, with no candidate list to click through. Send epics and patterns to yourself and everything else to a mule, with fallback names if someone's bags are full. Hold Shift to do a corpse by hand, or press it to take over halfway. Badges of Justice, which everyone loots for themselves, never go up for review.
- **Master looter list.** Choose who should run the loot, in order. Switch the group to Master Loot and the first of them who's online gets it. It can set the loot threshold at the same moment, and anything you change afterwards sticks.
- **Excluded items.** Raid materials like Mark of the Illidari stay in the window for you to assign yourself. Raw epic gems like Lionseye are auto looted but never go up for review.
- **Loot Timers.** A small list of everything waiting for review, most urgent first, with the 2-hour trade time left on each item, so nothing expires in your bags.
- **Preview mode.** Run the whole workflow with your group on fictional items before raid night. Nothing goes to the history, and your real loot list comes back afterwards.

## For the council

- **One review window.** See every candidate's response, note, equipped items and item level difference, sorted from BiS down to Pass. Anyone who already received the item is marked, and hovering a name shows what they've received.
- **Stage, then commit.** Pick a winner for each item, send it to the raid's Enchanter, or keep it as **Banking**, then hand everything out with **Award All**.
- **You decide who's on it**: raid leader and assistants, guild ranks, or individual names.

## For raiders

- A compact **Loot Response** window: one line per item, with a countdown across the row and an optional note. An item that dropped twice is one line, answered once. It's only as tall as the items need, and you can resize it to suit your screen.
- Your awards show up in **Loot Trades**, where **Trade** opens the trade and places the items and **Follow** walks you to the other player.
- The master looter can customize the response buttons, and everyone in the session sees the same ones.
- **Raider mode**: master looting for your own runs with another addon, such as Gargul? Pick Raider in the welcome window, or type `/plc raider`. As master looter, PixlLootCouncil then loots, collects and starts nothing by itself, and sessions others start still open.

## Loot history

- Every award is recorded, with date, name, class and response filters.
- Exports to TSV for Google Sheets and Excel.
- Shared with everyone in the group who has the addon. Missed some? The master looter presses **Share** (or types `/plc share`) and everyone online in the guild and group gets their awards.

## Also

- **Every client language**, translated throughout.
- **Windows that stack like on a desktop**: the one you open or click comes to the front.
- **Eight themes**, any font your addons have registered, and a Scale setting for the size of every window.
- **A quiet update reminder** when your version is out of date.

## Coming from RCLootCouncil

PixlLootCouncil is built on the idea of RCLootCouncil, and you can switch without losing anything:

- **One click on first launch.** The welcome window imports your loot history and the settings you changed in RCLootCouncil that work here too: council, response buttons, time to respond and announcements.
- **Bring your history.** Import it directly from RCLootCouncil, receive it in game from your loot master through `/rc sync`, or paste a Player Export. Spreadsheets built on its exports keep working.
- **Raid with a master looter who still uses it.** Raiders can disable RCLootCouncil: its sessions open in your Loot Response window with the same buttons, timer and note rules, your answer goes back, rolls work, and shared awards land in your history. Voting as a council member still needs RCLootCouncil.

## Getting started

The first time, a welcome window asks whether you're a raider or the loot master, and sets you up.

Master looter: set the group to **Master Loot** and open corpses as usual. Type `/plc` to open the Loot Session window, and **Options → Auto Loot** to choose who gets what.

Raiders: nothing to set up. When a session starts, the Loot Response window opens, and it stays until every item is answered or its time runs out.

Try it first: `/plc preview`

## Good to know

- Translations are machine-written, so corrections are welcome on GitHub.
- There's no council vote count: the session holder makes the final call.

## Credits

Inspired by [RCLootCouncil](https://github.com/evil-morfar/RCLootCouncil2), whose loot council idea this addon builds on, and whose history format it keeps for compatibility. Auto loot ideas come from Gargul's PackMule.

Free software under the GPL-3.0. The source is on [GitHub](https://github.com/svenvonarx/PixlLootCouncil).
