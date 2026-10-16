# Changelog

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
