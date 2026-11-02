# PixlLootCouncil

**Loot council for TBC Anniversary Classic.** The master looter collects the raid's loot as it drops, the council reviews everyone's interest in one window, and a single click hands it all out. Every award lands in a history that uses RCLootCouncil's format.

> **Beta.** This is an early test version. Please report what you find on [GitHub](https://github.com/svenvonarx/PixlLootCouncil/issues).

## Your master looter uses RCLootCouncil? You don't have to.

Raiders can drop RCLootCouncil and keep raiding with a loot master who still runs it. Their items open in your Loot Response window with their buttons, timer and note rules. Your answer goes back to them, rolls work, you catch up if you reload mid-session, and the awards they share land in your own loot history.

## For the master looter

- **Auto loot.** Open a corpse and the loot goes where it should, with no candidate list to click through. Send epics and patterns to yourself and everything else to a mule, with fallback names if someone's bags are full. Hold Shift to do a corpse by hand.
- **Excluded items.** Raid materials like Mark of the Illidari stay in the window for you to assign yourself.
- **Loot Timers.** A small list of everything waiting for review, most urgent first, with the 2-hour trade time left on each item, so nothing expires in your bags.
- **One review window.** See every candidate's response, note, equipped items and item level difference. Hover a name for what they've already received. Stage a pick for each item, then commit them all with **Award All**.
- **Guided trades.** Loot Trades lists what you owe and what you're owed. **Trade** opens the trade and places the items, and **Follow** walks you to the other player.
- **Preview mode.** Run the whole workflow with your group on fictional items before raid night. Nothing goes to the history, and your real loot list comes back afterwards.

## For raiders

- A clean **Loot Response** window with a countdown and an optional note.
- Your awards show up in **Loot Trades** with a Trade button.
- The master looter can customize the response buttons, and everyone in the session sees the same ones.

## Loot history

- Stored in RCLootCouncil's exact format, with date, name, class and response filters.
- Exports to TSV for Google Sheets and Excel, so spreadsheets built on RC exports keep working.
- Import your old history: RC's own `/rc sync`, a pasted Player Export, or directly from RC's saved data.

## Getting started

Master looter: set the group to **Master Loot** and open corpses as usual. Type `/plc` to open the Loot Session window, and **Options → Auto Loot** to choose who gets what.

Raiders: nothing to set up. When a session starts, the Loot Response window opens.

Try it first: `/plc preview`

## Good to know

- With an RCLootCouncil loot master you can respond and roll, but council members still need RC to vote.
- The interface is English only for now, and trade-time tracking needs the English client.
- There's no council vote count: the session holder makes the final call.

Free software under the GPL-3.0. The source is on [GitHub](https://github.com/svenvonarx/PixlLootCouncil).
