# RCLootCouncil_Classic Architecture Analysis

Source analyzed: `/run/media/pixl/Games/World of Warcraft/_anniversary_/Interface/AddOns/RCLootCouncil_Classic` (197 files). All paths below are relative to this root unless noted.

## 1. High-level architecture

### Load order (from `RCLootCouncil_Classic.toc`)

```
RCLootCouncil\Patches\UiDropDownMenuTaintCommunities.lua   -- community-wide Blizzard taint patch, loads FIRST
RCLootCouncil\embeds.xml                                    -- all Ace3/third-party libs
RCLootCouncil\Locale\Locales.xml
RCLootCouncil\Core\GlobalUpdates.lua                         -- cross-version Blizzard API shims (C_Container, GetLootMethod, etc.)
RCLootCouncil\Core\Constants.lua
RCLootCouncil\Core\Defaults.lua
RCLootCouncil\Core\CoreEvents.lua
RCLootCouncil\Classes\Core.lua                                -- the DI/module system (addon.Init/addon.Require)
RCLootCouncil\Classes\Utils\Item.lua
RCLootCouncil\Classes\Lib\RxLua\embeds.xml
RCLootCouncil\Classes\Utils\TempTable.lua
RCLootCouncil\Classes\Utils\Log.lua
RCLootCouncil\Classes\Services\ErrorHandler.lua
RCLootCouncil\Classes\Utils\GroupLoot.lua
RCLootCouncil\Classes\Data\Player.lua
RCLootCouncil\Classes\Data\Council.lua
API\CommsRestrictions.lua                                     -- Classic override of the base restrictions service
RCLootCouncil\Classes\Services\Comms.lua
RCLootCouncil\Classes\Data\MLDB.lua
RCLootCouncil\core.lua                                         -- base addon (3312 lines)
RCLootCouncil\ml_core.lua                                      -- master-looter module (1785 lines)
RCLootCouncil\UI\UI.lua
RCLootCouncil\UI\Widgets\widgets.xml
RCLootCouncil\Modules\Modules.xml                              -- lootFrame, versionCheck, VotingFrame, sessionFrame, options, History/*, TradeUI, Sync
RCLootCouncil\Utils\BackwardsCompat.lua / Utils.lua / Dump.lua / EncounterJournalData.lua / tokenData.lua / ItemStorage.lua / transmog.lua / autopass.lua / popups.lua

## Classic Module  (layered ON TOP of everything above)
Locale\Locales.xml
Core\Module.lua
Core\Hooks.lua
Core\Autopass.lua
Core\Lists.lua
Core\BackwardsCompatibility.lua

## Overrides (layered ON TOP of the Classic Module)
API\RCLootCouncilUpdates.lua
API\ButtonGroupUpdates.lua
API\OptionsUpdates.lua
API\MLUpdates.lua
API\LootHistory.lua
API\VersionCheckUpdates.lua
API\GroupLootUpdates.lua
```

### "Classic Module" vs base "RCLootCouncil"

The directory literally contains **two addons stacked in one package**: `RCLootCouncil/` is a vendored copy of the retail addon's entire source tree (its own Core/, Classes/, Modules/, UI/, Utils/, Libs/, Locale/), and the top-level `Core/` + `API/` directories are a *second*, much smaller codebase ("the Classic Module", internally named `RCClassic`, see `Core/Module.lua:4-5`) that is `addon:NewModule("RCClassic", ...)` — an Ace3 submodule of the base addon.

This Classic Module does not call the base addon through a clean interface; it directly **monkey-patches it**:
- It mutates shared tables declared by the base addon, e.g. `addon.coreEvents["ENCOUNTER_LOOT_RECEIVED"] = nil` and `addon.defaults.profile.autoPassBoE = false` (`API/RCLootCouncilUpdates.lua:18-78`).
- It **overwrites functions wholesale** by re-declaring `function addon:FunctionName() ... end` in a file loaded after `core.lua`/`ml_core.lua` — because Lua just reassigns the table key, the new definition silently replaces the old one with no `super` call (e.g. `addon:IsCorrectVersion`, `addon:UpdatePlayersData`, `addon:Test`, `addon:GetML` in `API/RCLootCouncilUpdates.lua`; `MLModule:ShouldAutoAward`/`AutoAward`/`LootOpened` in `API/MLUpdates.lua`).
- Where it needs to call through to the original implementation it has to manually capture it first: `local orig_ShouldAutoAward = MLModule.ShouldAutoAward` (`API/MLUpdates.lua:16`) before overwriting.
- It uses Ace3's `SecureHook`/`RawHook`/`Hook` (via a small custom `Classic:DoHooks()` table-driven dispatcher, `Core/Hooks.lua`) for cases where it wants pre/post hooks instead of full replacement.

So the "Overrides" files are a **reactive compatibility shim layer**: the base `RCLootCouncil/` tree is written primarily for retail/modern WoW client APIs, and `API/*Updates.lua` exists specifically to patch over the differences for Classic/BCC/Wrath/MoP-Classic/Era clients (missing events like `ENCOUNTER_LOOT_RECEIVED` and `BONUS_ROLL_RESULT` pre-Mists, different Group Loot bitstatus targets, ElvUI/XLoot loot-button hooking quirks, etc.). Every overrides file begins with a comment like *"Fixed for retail RCLootCouncil function that doesn't function properly in Classic or otherwise needs editing"* (`API/RCLootCouncilUpdates.lua:2`, `API/MLUpdates.lua:2`).

**Architectural risk this creates:** any base-addon refactor can silently break an override that depends on the exact old function signature/behavior, and vice-versa — there is no versioned interface between the two layers, just load-order-dependent table mutation.

### Dependency-injection module system (`Classes/Core.lua`)

A tiny custom DI container, "inspired by TSM": `addon.Init(path)` registers a named module object (metatable with `OnInitialize`/`OnEnable`/`Initialize`/`Enable`/`Disable`), `addon.Require(path)` looks it up by string path (e.g. `"Data.Player"`, `"Services.Comms"`, `"Utils.Log"`). This is layered **underneath** Ace3's own `AceAddon:NewModule` system (used for `RCClassic`, `RCVotingFrame`, `RCLootCouncilML`, etc.) — so the codebase runs two different module/DI systems side by side (`RCLootCouncil/Classes/Core.lua`, `Core/Module.lua`).

## 2. Core data model (`RCLootCouncil/Classes/Data/`)

### `Player` (`Data/Player.lua`, 271 lines)
A lightweight value object + a global cache keyed by GUID, backed by `addon.db.global.playerCache` (persists across sessions). Fields: `guid, name ("Name-Realm"), class, realm, role, rank, enchanter, ilvl, specID, classColoredName, cache_time, isInGuild, isCouncil`.
- `Player:Get(input)` accepts a GUID or a unit name, resolves to a GUID via `UnitGUID`, then falls back to an internal name→GUID cache, then guild roster scan (`GetGuildRosterInfo`), and finally gives up with `ErrorHandler:ThrowSilentError` and returns a "nil player" (`private:GetNilPlayer`) — the whole codebase is written to tolerate "nil players" rather than crash (line 93-134, 264).
- Cache entries expire after `MAX_CACHE_TIME = 2 days` (line 11) **unless** `isCouncil == true`, in which case they never expire (line 225).
- `__eq` metamethod compares GUIDs, with a special case to refuse comparing "secret values" (new Midnight/retail anti-exploit API `issecretvalue`/`IsSecretValue`, stubbed out safely for Classic) — see line 77-88 and `ErrorHandler.lua:12`.

### `Council` (`Data/Council.lua`, 124 lines)
Just a `{ [guid] = Player }` map with `Get/Set/Add/Remove/Contains/GetNum`. `Council:Set()` clears the `isCouncil` flag on all cached players first, then re-marks the new set (`Player:ClearCouncilStatus`, line 31). `Council:Contains()` always returns `true` if the local player is the Master Looter or `addon.nnp` (no-no-prompt/standalone test mode) is set (line 68) — i.e., council membership checks are bypassed for the ML locally. `GetForTransmit`/`RestoreFromTransmit` convert to/from a comms-friendly `{ [strippedGUID] = true }` table via a `TempTable` pool.

### `MLDB` (Master-Loot DB, `Data/MLDB.lua`, 158 lines)
Holds the subset of ML's `profile` settings candidates need to know to behave correctly (self-vote, multi-vote, anonymous voting, button/response text+color overrides, timeout, autoGroupLoot, etc.). Two notable design choices:
- **Diffing against defaults**: `private:BuildMLDB()` only includes a response/button entry in the transmitted table if it *differs* from `addon.defaults.profile` (lines 101-158) — a bandwidth optimization, but it means a bug in the diff logic (comparing wrong defaults, e.g. after a Classic override changes `addon.defaults.profile.*`) can silently omit data that should have been sent.
- **Key minification**: a hand-maintained `replacements` table maps `"|1"`, `"|2"`, … to field names like `"selfVote"`, `"buttons"`, etc. (lines 18-37), to shrink wire payloads. It already carries a visible wart: `[magicKey .. "18"] = "requireNotes"` is commented `-- TODO: Duplicate entry, needs removal on patch (not backwards compatible)` (line 36) — i.e. a known bug that can't be fixed without breaking comms compatibility with older client versions still in the wild.

### Candidate/raid roster representation
Roster membership itself is **not** stored on `Council`/`Player` — it's tracked separately as a plain name-keyed table `addon.candidatesInGroup` (built by `RCLootCouncil:UpdateCandidatesInGroup()`, `core.lua:1587`) which is refreshed on roster events. `Council:GetCouncilInGroup()` (`Data/Council.lua:116-124`) intersects the persistent council set with this live roster table. This split (persistent identity cache vs. live roster table vs. per-session candidate/vote data inside `lootTable[session].candidates`, built in `VotingFrame.lua`) is the de-facto "3 sources of truth for who's present" pattern that contributes to raid-roster-change bugs (see §7).

## 3. Session lifecycle

### Loot interception
Two independent paths, both event-driven (not UI-frame hooking) at the core:

1. **Own/Master loot** — `core.lua:OnEvent` (`Core/CoreEvents.lua` registers `LOOT_READY`, `LOOT_SLOT_CLEARED`, `LOOT_CLOSED`, `LOOT_OPENED` isn't in the base list — Classic's `ClassicModule:LootOpened` additionally hooks `LOOT_OPENED`/`LOOT_CLOSED` directly, `Core/Module.lua:56-57`). On `LOOT_READY` the addon builds its own `self.lootSlotInfo[i]` table by calling `GetLootSlotInfo`/`GetLootSlotLink`/`GetLootSourceInfo` per slot (`core.lua:1765-1799`; Classic rebuild variant in `Core/Module.lua:64-110`). This is clean/event-driven — no interaction with Blizzard's `LootFrame`.
2. **Group loot rolls (Need/Greed/Pass)** — `Utils/GroupLoot.lua` subscribes to `START_LOOT_ROLL` and computes a bitfield "status" (`GetStatus()`, lines 151-163) from 9 independent conditions (has mldb, autoGroupLoot enabled, handleLoot active, has valid ML, is ML, group size>1, guild-group-only setting, guild-group state, addon enabled). If the computed status satisfies `ShouldPassOnLoot`/`ShouldRollOnLoot` bitmask predicates, it calls `RollOnLoot()` → `RollOnLoot(rollID, rollType)` (the real Blizzard roll API) on a 0.05s delayed timer "in case other addons have modified the loot frame" (line 108-111), then **actively hides** Blizzard's `GroupLootFrameN` via `GroupLootContainer_RemoveFrame` (lines 249-274) — this is the one spot where the addon directly manipulates a live Blizzard frame object, albeit only to remove it from its container, not to click/hook it.

### Queueing for council decision (ML side, `ml_core.lua`)
`RCLootCouncilML:AddItem()` (line 119) builds a `lootTable` entry (bagged?, lootSlot, owner, boss, typeCode, instanceData snapshot, item info). If item info (`GetItemInfo`) isn't cached yet it retries via `ScheduleTimer` up to 20 times (~1s) before giving up (lines 162-175) — classic "item not cached on first loot" workaround. `ShowSessionFrame()` opens the ML's own `sessionFrame` UI to let the ML curate the list before starting.

### Session start / distribution to candidates
`RCLootCouncilML:StartSession()` (line 250) refuses to start until `Council:GetNum() > 0` (waiting for comms sync), then sends the loot table over comms (`"lootTable"` or `"lt_add"` for additions to an already-running session) and announces items in raid chat (`AnnounceItems`). On the candidate side, `RCLootCouncil:OnLootTableReceived` (`core.lua:3012`) rebuilds local item state and the candidate-facing `lootFrame` (`Modules/lootFrame.lua`) shows Need/Greed/Pass/custom-response buttons per item.

### Candidate response → vote
`LootFrame:OnRoll(entry, button)` (`Modules/lootFrame.lua:179`) sends the chosen response via `addon:SendResponse(...)` → `Comms:Send` with command `"response"` (`core.lua:1073-1094`), optionally attaching the candidate's two relevant equipped-gear item links + ilvl diff for council reference. On the ML/council side, `RCVotingFrame:OnResponseReceived` / `HandleVote` (`Modules/VotingFrame/VotingFrame.lua:414, 619`) record the response into the per-session candidate table that drives the voting-frame's `lib-st` table rows.

### Award + distribution
`RCLootCouncilML:Award(session, winner, response, reason, callback, ...)` (`ml_core.lua:899`) is the single funnel for all award paths (direct loot-window award, "award later"/bagged award, manually-added `/rc add` items, re-award/change-award). It:
1. Validates state (already awarded? bagged-but-no-winner? unlooted-but-bagged — treated as an addon bug and reported via `addon:SessionError`, line 918).
2. Calls `CanGiveLoot(slot, item, winner)` (line 667) which reimplements Blizzard's master-loot eligibility rules client-side (loot window open, slot not stale, not locked, inventory space, quality ≥ threshold, in-group, online, in-instance, BoP vs council-eligible) *before* calling the actual protected API, producing a rich `cause` string.
3. If eligible, calls `GiveLoot()` (line 744) which queues a `{slot, callback, args, timer}` entry and calls the real `GiveMasterLoot(slot, i)` Blizzard API, relying on a later `LOOT_SLOT_CLEARED` event (`RCLootCouncilML:OnLootSlotCleared`) or a `LOOT_TIMEOUT` timer to resolve the callback (success/`"timeout"`).
4. On success it calls `registerAndAnnounceAward` → `AnnounceAward` (chat announcement) and `TrackAndLogLoot` (history entry).

Trading is handled separately, not as part of `Award` — see §9.

## 4. Comms protocol (`RCLootCouncil/Classes/Services/Comms.lua`)

### Channels
- `"group"` target resolves at send-time to `INSTANCE_CHAT` (if in a party-sync/LFG group), else `RAID`, else `PARTY`, else falls back to `WHISPER` to self (`private:GetGroupChannel`, lines 264-274).
- `"guild"` → `GUILD` channel.
- A specific `Player` target → `WHISPER` if addressable, else re-wrapped as an `"xrealm"` pseudo-command sent over the group channel and unwrapped by the recipient only if they match the embedded target name (lines 182-200, 216-221) — this is how it delivers to a specific player when direct whisper addressing by cross-realm name isn't reliable.

### Message framing
Three Ace3-style "prefixes" registered in `Constants.lua:11`: `MAIN = "RCLC"`, `VERSION = "RCLCv"`, `SYNC = "RCLCs"`. Every send: `AceSerializer:Serialize(command, data)` → `LibDeflate:CompressDeflate` → `LibDeflate:EncodeForWoWAddonChannel` → `AceComm:SendCommMessage`. Receive path reverses this (`private.ReceiveComm`, line 203). Each `(prefix, command)` pair gets its own **RxLua `Subject`**, created lazily (`private:SubjectHelper`, line 286-292); `Comms:Subscribe(prefix, command, func)` is literally `subject:subscribe(func)`. This is the main (only heavily-used) application of RxLua in the codebase — essentially a typed pub/sub bus, not a reactive-operator pipeline (no `map`/`merge`/`combineLatest` chains found; only `first.lua`/`take.lua` operators exist in the vendored lib and are barely used elsewhere).

### Protocol-version compatibility
There is **no strict wire-protocol version negotiation / message schema versioning**. Compatibility is handled by:
- `versionCheck` module (`Modules/versionCheck.lua`) broadcasting the addon's semantic `addon.version` string (+ an optional test-build `tVersion`) over the `RCLCv` prefix and comparing via `addon.Utils:CheckOutdatedVersion` (`InitCoreVersionComms`, line 303-352) — this only *warns the user* ("you/they are outdated"), it does not gate whether old/new comms commands are understood.
- Forward/backward compatibility of the actual data payloads is maintained manually, field by field, by developers being careful never to remove a key outright (see the MLDB `"TODO: Duplicate entry, needs removal on patch (not backwards compatible)"` wart noted above) — i.e. compatibility is a *discipline*, not something enforced by the protocol.
- `API/VersionCheckUpdates.lua` is only 4 lines — Classic needed almost no override here, suggesting version-check itself is one of the more stable subsystems.

### Addon-restriction / combat queuing (`Services/CommsRestrictions.lua` + `API/CommsRestrictions.lua`)
Listens to `ADDON_RESTRICTION_STATE_CHANGED` (Encounter/Challenge-mode addon message restrictions) and tracks a bitmask of active restriction types; `CommsRestrictions:IsRestricted()` gates `Comms:SendComm` — normal sends are dropped with a warning while restricted, but calls made through `Comms:SendGuaranteed` (used for award-critical/state messages like `StartHostHandleLoot`) are instead serialized into a dedupe'd `queuedComms` list and flushed once restrictions lift (`Comms.lua:163-250`). **The Classic override (`API/CommsRestrictions.lua`) simply disables this entirely** (`IsRestricted()` always returns `false`, `OnEnable` is a no-op) — Classic-era content apparently never sets this restriction, so the whole queuing mechanism is dead code on Classic but still shipped.

### Sync (`Modules/Sync.lua`)
A user-facing, opt-in request/accept/decline/transfer protocol for syncing arbitrary addon state (e.g. history) between two players, distinct from the core ML↔candidate comms: `SendSyncRequest` → peer sees a `LibDialog` popup (`RCLOOTCOUNCIL_SYNC_REQUEST`, `Utils/popups.lua:38-52`) → `SyncAckReceived`/`SyncNackReceived`/`SyncDataReceived`. Not built on RxLua; straightforward Ace3 comm callbacks with progress reporting via `OnDataPartSent`.

## 5. UI composition

- **AceGUI-3.0** (full vendored copy incl. `AceGUI-3.0-SharedMediaWidgets`) is used for options and some auxiliary windows (Import/Export frames extend AceGUI containers, see `UI/Widgets/ExportFrame.lua`, `ImportFrame.lua`, `HugeExportFrame.lua`).
- **Custom widget framework** (`UI/UI.lua` + `UI/Widgets/*.lua`, registered via `widgets.xml`): a small `addon.UI:New(type, parent, ...)` factory with a `RegisterElement` registry, its own `Button`, `Icon`, `IconBordered`, `Text`, `Frame` widget types (`UI/Widgets/Button.lua`, `Frame.lua`, etc.) — i.e. the main gameplay frames (voting frame, session frame, loot frame, trade UI, version-check frame) are **not** AceGUI widgets but hand-rolled `CreateFrame`-based frames wrapped by this thin custom layer. `UI.lua` also owns combat-minimize/maximize logic for all registered frames (lines 47-76) and an escape-to-close registration helper (`RegisterForEscapeClose`, tied to `UISpecialFrames`).
- **lib-st** (`Libs/lib-st/Core.lua`, a ScrollingTable library) powers the tabular frames: the Voting Frame's main candidate/response grid (`VotingFrame.lua:1054 BuildSTCols/BuildSTRows`, with ~15 `SetCellXxx` column renderers for class icon, name, rank, role, response, ilvl, diff, gear, votes, vote buttons, note, roll), the Version Check frame's player list, the Trade UI's item list, and the Loot History frame.
- **LibWindow-1.1** handles frame position persistence/snapping (used by the main movable frames).
- **LibDialog-1.0/1.1** backs all confirm/decline popups (`Utils/popups.lua`): usage confirmation, sync requests, abort confirmation, trade-add-item prompts, award confirmation, etc.
- The candidate-side `LootFrame` (`Modules/lootFrame.lua`) uses an internal `EntryManager` to recycle per-item "entry" sub-frames (pooling pattern) rather than creating/destroying frames per item — a reasonably robust pattern.

## 6. Options/config system

- Standard **AceConfig-3.0 / AceConfigDialog-3.0 / AceConfigRegistry-3.0** usage (`Modules/options.lua`, 2337 lines) with the conventional `get`/`set` closures reading/writing `addon.db.profile` (helper `DBGet`/`DBSet` at the top of the file, lines 11-18) and `addon:ConfigTableChanged(key)` as a generic change-notification hook (fans out to e.g. MLDB rebuild). Button-group option pages are **generated dynamically** per response/button-group key via `createNewButtonSet(path, name, order)` (line 24) rather than declared statically — this is how the extensible "response button groups" feature (Weapon/Token/Recipe/etc., driven by `addon.OPT_MORE_BUTTONS_VALUES` in `Constants.lua:37-62` and `RESPONSE_CODE_GENERATORS` predicate list, `Constants.lua:131-213`) is implemented.
- `API/OptionsUpdates.lua` (332 lines) and `API/ButtonGroupUpdates.lua` (17 lines) patch/extend this for Classic (e.g. removing transmog options pre-Cata, removing Mists-only reputation auto-award toggles).
- **`Defaults.lua`** (`Core/Defaults.lua`, 279 lines) defines `addon.responses` (default response texts/colors/sort order, keyed by button-group type, with a `["*"]["*"]` AceDB-style wildcard fallback entry) and `addon.defaults` with two top-level AceDB scopes:
  - `global`: `logMaxEntries`, `log` (debug ring buffer), `verTestCandidates`, `errors` (ErrorHandler's persisted error log), `cache` (relog/reload state cache — see `core.lua:1700-1712`), plus `playerCache` (added dynamically by `Data/Player.lua`).
  - `profile`: the bulk of user-configurable behavior — response/frame/history toggles, ML usage-prompt state machine (`usage = {never, gl, ask_gl, state}` for Classic; retail variant adds `ml/ask_ml/leader/ask_leader`), auto-loot/auto-pass/auto-award settings, `baggedItems`/`itemStorage` (persisted "award later" state), `enabledButtons`/`buttons`/`responses` (per-group button config), `awardText`/`awardReasons`, `alwaysAutoAwardItems`, `ignoredItems`.
- **SavedVariables**: `RCLootCouncilDB` (the AceDB object described above — global+profile scopes, keyed by character/realm/profile per AceDB-3.0 convention) and `RCLootCouncilLootDB` (separate AceDB instance for the loot **history**, `factionrealm`-scoped per `RCLootCouncil:GetHistoryDB()` → `self.lootDB.factionrealm`, `core.lua:2202`), declared in the `.toc`'s `## SavedVariables:` line.

## 7. Fragility root causes

This is the section most directly relevant to the rewrite. Evidence gathered from `Changelog.md`/`Changes.md`, inline comments (`HACK`/`FIXME`/`REVIEW`/`TODO`), and the structure of the `API/*Updates.lua` "Overrides" files.

### 7.1 The "Overrides" layer is a standing admission of fragility
`API/RCLootCouncilUpdates.lua`, `MLUpdates.lua`, `OptionsUpdates.lua`, `GroupLootUpdates.lua`, `ButtonGroupUpdates.lua`, `LootHistory.lua`, `VersionCheckUpdates.lua` collectively exist **only** to patch the base retail addon's behavior for Classic clients — new Blizzard API differences (missing globals/events pre-Mists, enum differences, `GetLootMethod` string-vs-enum return changes handled in `Core/GlobalUpdates.lua`), and other per-client quirks. Every Blizzard client patch that changes a global function signature, removes/renames an event, or changes loot API semantics is a candidate to break one of these overrides or the underlying base function it patches — and because overrides patch by **wholesale function reassignment** rather than composition, a change to the base function's signature silently desyncs the override (no compiler/type check will catch it; it just misbehaves or errors at runtime).

### 7.2 Monkey-patching without a stable extension API
There is no formal "hook point" API between the base addon and Classic layer — Classic reaches in and overwrites `addon:X`, `MLModule:X`, mutates `addon.coreEvents`, `addon.defaults.profile.*`, `addon.INVTYPE_Slots`, etc. directly (`API/RCLootCouncilUpdates.lua:18-78`). This means:
- Load order is load-bearing and invisible from any single file — you must read the `.toc` to know which definition "wins."
- Overridden functions that need to call the "real" original logic must manually snapshot it first (`local orig_ShouldAutoAward = MLModule.ShouldAutoAward`, `API/MLUpdates.lua:16-17`) — easy to forget, and there's no way to chain more than one override onto the same function.

### 7.3 Blizzard-UI interaction surface (taint risk)
- `Utils/GroupLoot.lua:249-274` directly calls `GroupLootContainer_RemoveFrame(_G.GroupLootContainer, frame)` on Blizzard's live `GroupLootFrame1..4` objects to hide the default roll popup after auto-rolling. Manipulating Blizzard's secure/protected frame tree from addon code is a classic taint vector even when read-only-ish.
- `API/MLUpdates.lua:177-219` hooks `LootButton{i}:OnClick` (and conditionally `XLootButton{i}`, `XLootFrameButton{i}`, `ElvLootSlot{i}` for third-party loot addon compatibility) via `self:HookScript(...)`/`IsHooked` for "alt-click looting" — hooking other addons' click handlers for compatibility is inherently brittle (breaks whenever XLoot/ElvUI change their button naming/structure) and is explicitly flagged as an "ElvUI hack" in-line (`button.slot = button:GetID() -- ElvUI hack`, line 201).
- `RCLootCouncil/Patches/UiDropDownMenuTaintCommunities.lua` is loaded **first**, before anything else — it's the well-known community-shared `hooksecurefunc("UIDropDownMenu_InitializeHelper", ...)` patch that works around a long-standing Blizzard taint bug in `UIDropDownMenu` triggered by any addon opening a dropdown after Blizzard Communities UI touches the same global. Its presence signals the author has been bitten by this class of bug badly enough to vendor a dedicated fix-it patch rather than simply avoiding `UIDropDownMenu`/`MSA-DropDownMenu` (which is also vendored as a dropdown alternative in `Libs/MSA-DropDownMenu-1.0/`).
- `ErrorHandler.lua:20-23` specifically listens for `ADDON_ACTION_BLOCKED` and `ADDON_ACTION_FORBIDDEN` events and routes them into the same error log as Lua errors — strong direct evidence that taint/protected-action failures are a recurring, expected failure mode the authors had to build permanent instrumentation for (`RCLootCouncil/Classes/Services/ErrorHandler.lua:21-23, 29-33`).

### 7.4 Loot/trade/item-cache races are a chronic bug category
Changelog entries repeatedly reference this exact class of bug:
- *"Fixed error involving Session Data frame and auto hiding in combat."*, *"Fixed issue causing BoE items not to always be sent."*, *"Trading should be more stable (#281)"* (`Changes.md:11-14`, v1.5.1).
- *"Added better recovery from desync issues."* (v1.4.2), *"Fixed issue in v1.4.2 causing gear and other comms not to be received."* (v1.4.3) — a fix for a previous fix, indicating the comms reliability work is iterative/reactive rather than solved structurally.
- *"Hopefully fixed changing group leader invalidading the registered ML."*, *"Fixed caching issue that deleted things such as guild ranks causing them to show up inconsistently."* (v1.1.1/v1.1.4) — roster/leadership-change edge cases recur because ML/council/roster state is tracked in multiple places (`addon.masterLooter`, `Council`, `addon.candidatesInGroup`) that must all be kept in sync by hand.
- The item-info-not-cached-yet retry loop in `ml_core.lua:AddItem` (up to 20 retries @ 0.05s) and the analogous retry in `core.lua:LOOT_READY` handling (`core.lua:1792-1797`) exist because `GetItemInfo`/tooltip data is asynchronous and not guaranteed ready when loot first opens — a source of "it works most of the time" timing bugs.

### 7.5 Backward-compatibility debt accumulates in the wire format
The MLDB key-minification table (`Data/MLDB.lua:18-37`) has a dangling duplicate entry explicitly marked as unfixable without breaking old clients (`-- TODO: Duplicate entry, needs removal on patch (not backwards compatible)`, line 36) — a direct example of technical debt that is structurally impossible to clean up because there's no protocol-version gate to make the change safe.

### 7.6 Two parallel module/DI systems
Running both the custom `addon.Init/Require` DI container (`Classes/Core.lua`) and Ace3's `AceAddon:NewModule` simultaneously (`Core/Module.lua`) adds conceptual overhead with no apparent technical necessity — new contributors have to learn and distinguish both "`addon.Require "Data.Player"`" and "`addon:GetModule("RCClassic")`" idioms, increasing the chance of using the wrong one or duplicating responsibility.

### 7.7 In-combat gating is manual, not structural
Session start explicitly checks `InCombatLockdown()` and several bypass conditions by hand (`Core/Module.lua:128`: `if not InCombatLockdown() or (db.autoStart and db.awardLater and Council:Contains(...)) or db.skipCombatLockdown then ML:LootOpened() else addon:Print(...) end`) rather than the frame lifecycle structurally preventing protected actions during combat — another spot where a missed edge case (a new code path that creates/shows secure-adjacent UI without this check) could re-trigger taint.

## 8. External library dependencies (`RCLootCouncil/Libs/`)

| Library | Depth of use | Rewrite note |
|---|---|---|
| **AceAddon-3.0** | Core addon object, all modules (`RCLootCouncilML`, `RCVotingFrame`, `RCClassic`, etc.) via `NewModule`/`NewAddon` | Hard to avoid cheaply; gives OnInitialize/OnEnable lifecycle and module registry for free. |
| **AceEvent-3.0** | Pervasive (`RegisterEvent` everywhere) | Could be replaced by a thin custom event bus, but little benefit — this is the least fragile Ace3 piece. |
| **AceComm-3.0** + **ChatThrottleLib** | Core of `Comms.lua`; all addon messaging | Throttling or you will drop/flood comms — keep equivalent. |
| **AceSerializer-3.0** + **LibDeflate** | Every comm message (serialize → deflate → WoW-addon-channel-safe encode) | Standard, low risk; keep. |
| **AceConfig-3.0 / AceConfigDialog-3.0 / AceConfigRegistry-3.0 / AceConfigCmd-3.0** | All of `options.lua` (2337 lines) + dynamically generated per-button-group pages | Heavy but standard; a from-scratch options UI would be a large and unnecessary undertaking. |
| **AceGUI-3.0 (+SharedMediaWidgets)** | Options dialog, Import/Export/HugeExport frames only | **Not** used for the main gameplay frames (those are hand-rolled). A rewrite could scope AceGUI to options-only or replace it with a smaller declarative layer if the options surface is simplified. |
| **AceDB-3.0 / AceDBOptions-3.0** | `RCLootCouncilDB` (settings) + `RCLootCouncilLootDB` (history), profile switching UI | Keep — profile management (per-char/shared profiles) is genuinely useful and non-trivial to reimplement. |
| **AceHook-3.0** | `SecureHook`/`RawHook`/`Hook` used by the Classic override layer (`Core/Hooks.lua`) and the ElvUI/XLoot loot-button hook | Minimize usage in the rewrite — see §7.3; each hook is a fragility point. |
| **AceTimer-3.0 / AceBucket-3.0** | Retry loops, throttled council-send, debounced roster updates | Keep, standard. |
| **AceLocale-3.0** | All user-facing strings, 11 locale files | Keep if localization matters; otherwise could be dropped for a smaller/rewrite-scoped string table. |
| **AceConsole-3.0** | `/rc` slash command parsing (`core.lua:ChatCommand`) | Keep or trivially reimplement — small usage. |
| **CallbackHandler-1.0** | Dependency of AceEvent/AceComm | Transitive; no decision needed. |
| **lib-st (ScrollingTable)** | Voting Frame grid, Version Check frame, Trade UI list, History frame | Core to the "spreadsheet-like" voting UI; worth keeping or finding an equally light table-widget replacement — reimplementing a scrolling, sortable, column-API'd table from scratch is a significant undertaking (`VotingFrame/ColumnAPI.lua` is a whole file dedicated to it). |
| **LibWindow-1.1** | Frame position/scale persistence for movable frames | Small, keep or trivially reimplement (just `SetPoint`+saved coords). |
| **LibDialog-1.0** | All confirm/decline popups (usage prompt, sync request, abort, trade-add-item, award confirm) | Small, keep. |
| **LibSharedMedia-3.0** | Font/texture/sound options via AceGUI-SharedMediaWidgets | Only matters if cosmetic customization is retained. |
| **MSA-DropDownMenu-1.0** | Vendored as an alternative to Blizzard's taint-prone `UIDropDownMenu` | **Validates** the "avoid Blizzard's UIDropDownMenu" recommendation below — the existing project already maintains a non-Blizzard dropdown implementation for exactly this reason. |
| **RxLua (vendored subset: Observable, Observer, Subject, BehaviorSubject, Subscription, `first`/`take` operators)** | Used narrowly as a typed pub/sub bus: `Comms` (per prefix+command Subject), `GroupLoot.OnLootRoll`, `Log.OnLog`, `CommsRestrictions.OnAddonRestrictionChanged`, `SlashCommands` | **Not** used for actual reactive composition/operator chaining anywhere found — no `map`/`filter`/`merge`/`combineLatest` usage outside the library's own test/operator files. A rewrite could drop the full RxLua dependency in favor of a ~50-line custom `Signal`/`Subject` pub-sub type and lose nothing functionally, significantly shrinking a whole vendored subsystem. |

## 9. Item/tooltip/trade integration

- **Item info**: `RCLootCouncilML:GetItemInfo(item)` (`ml_core.lua:87`) wraps `C_Item.GetItemInfo`/related calls and is the single place item metadata (ilvl, equip loc, type/subtype, quality, token-slot, relic type) is resolved for a loot entry; call sites retry via `ScheduleTimer` if the item isn't in the local cache yet (see §7.4). `Classes/Utils/Item.lua` provides lower-level item-string/item-link parsing (`GetItemIDFromLink`, `UncleanItemString`, `GetItemStringFromLink`, `GetItemTextWithIcon`).
- **Tooltip scanning**: `addon:GetTooltipLines(item)` / `GetCorruptionFromTooltip` (`core.lua:1364, 1411`) and a tooltip-based "special effect" detector in the response-code-generator pipeline (`Constants.lua:185-202`, uses `C_TooltipInfo.GetHyperlink` + a line-matching helper `addon.Utils:FindInTooltip` against known `ITEM_SPELL_TRIGGER_*` global strings) rather than the older `GameTooltip:SetHyperlink` + manual `GameTooltipTextLeftN:GetText()` scraping pattern — i.e. it already uses the newer, less fragile `C_TooltipInfo` API.
- **Token/EncounterJournal data**: `Utils/tokenData.lua` and `Utils/EncounterJournalData.lua` are large static data tables (hand-maintained per-tier mappings of armor tokens → gear slots, and boss→encounter IDs) used to resolve "what gear does this token become" and boss identity for history/announcements — these are inherently **content-patch-fragile**: every new raid tier requires a data-file update (seen as recurring in Changelog: *"Fixed issues storing instance data for the history"*, v1.3.0).
- **Trade window integration** (`Modules/TradeUI.lua`): Reads the Blizzard trade frame's recipient name via `_G.TradeFrameRecipientNameText:GetText()` (line 259) — a direct read of a Blizzard UI text object's rendered value, defended with an `IsSecretValue` check for the newer anti-exploit "secret value" mechanism. On `TRADE_SHOW` it optionally auto-populates the trade window with owed items (`AddAwardedInBagsToTradeWindow`, gated by `db.autoTrade`, else a `LibDialog` confirm prompt) by calling `addItemToTradeWindow(tradeBtn, Item)` which presumably invokes `PickupContainerItem`+`ClickTradeButton`-style protected calls (not shown in excerpt but implied by the pattern) — any direct manipulation of the real trade UI's buttons is another taint-adjacent surface, mitigated here by gating behind explicit user opt-in (`autoTrade`) and a confirmation dialog by default.
- Trade completion is confirmed via `UI_INFO_MESSAGE` matching `LE_GAME_ERR_TRADE_COMPLETE` plus a locally-tracked `tradeItems` list built from `GetTradePlayerItemLink` during `TRADE_ACCEPT_UPDATE` (lines 304-350) — an event-driven, non-hooking approach to detecting "did the trade actually happen," which is appropriately defensive (it cross-checks the trade recipient against the expected winner and reports `trade_WrongWinner` over comms if someone trades the item to the wrong person).

## Rewrite recommendations

1. **Don't split the codebase into a "base" addon plus a reactive "Classic override" layer that monkey-patches it by function reassignment.** This was the single largest source of structural fragility found (§7.1–7.2): every client API change is a silent landmine because there's no compiler/runtime check that an override still matches the function it's patching, and there's no formal extension point — just load-order-dependent table mutation. Since PixlLootCouncil only targets one client (TBC Anniversary 2.5.5 / Interface 20506), **there is no need for this layering at all** — write directly against the one API surface you support, and isolate any future multi-client differences (if ever needed) behind small, explicitly-named capability-check functions (`CanGroupLoot()`, `HasBonusRollEvent()`) rather than wholesale file-load overrides.

2. **Never hook or directly manipulate Blizzard's live loot/roll UI frames.** Use your own frame fed purely by `LOOT_READY`/`LOOT_SLOT_CLEARED`/`LOOT_CLOSED`/`START_LOOT_ROLL` events (the pattern the base addon itself mostly follows, §3) instead of touching `GroupLootFrame1-4`/`GroupLootContainer` (§7.3) or hooking other addons' loot buttons for "alt-click" compatibility (`API/MLUpdates.lua:177-219`) — that compatibility shim is inherently a maintenance trap tied to third-party addons' internal frame names.

3. **Avoid Blizzard's `UIDropDownMenu` entirely** for any dropdown UI; the existing addon already had to vendor both a community taint-patch (`UiDropDownMenuTaintCommunities.lua`) *and* an alternative dropdown library (`MSA-DropDownMenu-1.0`) to work around it. Build dropdowns as plain custom frames from day one.

4. **Build a single, explicit source of truth for roster/council state**, not three (persistent `Council` cache + live `candidatesInGroup` name table + per-session `lootTable[session].candidates`). Several recurring changelog bugs (ML/leader-change desync, candidates "showing up inconsistently") trace back to keeping parallel state tables in sync by hand (§7.4). A single roster-state object with one update path, consumed everywhere else, removes a whole bug category.

5. **Version-gate the wire protocol from the start.** The existing comms format has at least one dangling, unfixable-without-breaking-compat bug (duplicate MLDB key mapping, §7.5) because there's no protocol version field gating payload shape. Include an explicit protocol version in the handshake/first message and make breaking-format changes conditional on it, so cleanup is possible later without stranding old clients in a broken state.

6. **Keep the event-driven, own-frame approach that already works well**: `LOOT_READY`-driven loot scanning, `CanGiveLoot`-style pre-validation before calling protected `GiveMasterLoot`, and `UI_INFO_MESSAGE`/`TRADE_ACCEPT_UPDATE`-driven trade confirmation (rather than hooking the trade UI) are all appropriately defensive, taint-safe patterns already present in the codebase (§3, §9) — carry these forward rather than reinventing them.

7. **Build first-class error/taint instrumentation from day one**, the way `ErrorHandler.lua` does (global `seterrorhandler` wrapping + `ADDON_ACTION_BLOCKED`/`ADDON_ACTION_FORBIDDEN` event capture, §7.3) — this is cheap, and it's exactly the signal you need to catch taint regressions in testing before they reach users, rather than relying on bug reports.

8. **Drop RxLua as a full vendored dependency.** It is used only as a typed pub/sub bus (`Subject`/`BehaviorSubject`, no operator chaining found anywhere in actual addon code, §8) — a ~50-line custom event-emitter type covers 100% of the observed usage and removes an entire vendored library plus its operator/subscription machinery.

9. **Consider trimming AceGUI-3.0 scope.** It's only used for the options panel and import/export dialogs, not the core gameplay frames (§5, §8) — if the options surface is simplified in the rewrite, a lighter declarative options layer (or Blizzard's native Settings API, available on this client version) could replace it; keep `lib-st`-equivalent tabular widget functionality since the voting/history/version-check grids genuinely need it.

10. **Keep AceDB-3.0/AceComm-3.0/AceSerializer-3.0/LibDeflate** as-is — these are solid, low-risk, and reimplementing them would add risk for no architectural benefit. The value of this rewrite is in *structure* (module layering, state ownership, taint surface) not in replacing well-understood low-level libraries.
