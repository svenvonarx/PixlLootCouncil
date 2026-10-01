# PixlLootCouncil — Project Specification

Status: **v1 — approved, scope decisions recorded in §9** · Target client: WoW Burning Crusade Classic Anniversary 2.5.5 (`## Interface: 20506`)

This document is the result of a full architectural analysis of `RCLootCouncil_Classic` (the addon whose functionality we are replicating) and `FojjiCore` (the addon whose options-panel look we are replicating). It defines what we build and, just as importantly, which specific patterns we deliberately avoid and why. Source analyses: `docs/analysis/rclootcouncil-architecture.md`, `docs/analysis/fojjicore-ui-style.md`.

---

## 1. Goal

Build a loot-council addon with the same day-to-day functionality as RCLootCouncil_Classic (master-looter-driven, council-voted loot distribution) that is **structurally resistant** to the two failure modes that make the original time-consuming to maintain and to use:

1. **Breakage on client/API changes** — RCLootCouncil_Classic ships a retail-targeted codebase plus a bolted-on "Classic Module" + "Overrides" layer that monkey-patches it function-by-function. Every Blizzard patch is a chance for an override to silently desync from the base function it patches.
2. **Taint / Blizzard-UI interaction bugs** — direct manipulation of `GroupLootFrame`, hooking other addons' loot buttons, and reliance on `UIDropDownMenu` (bad enough that the original vendors a community taint-patch *and* an alternative dropdown library).

We only ever target **one** client (2.5.5 / Interface 20506), so none of the multi-version layering that caused (1) is structurally necessary here at all.

## 2. Non-goals

- No multi-client support (no Classic Era / Wrath / retail compatibility layer). If BCC Anniversary ever moves to a new patch with a different Interface number, we bump the `.toc` and fix what breaks directly — we do not pre-build an abstraction for versions we don't run.
- No reproduction of RCLootCouncil's two-codebase-stacked structure, its custom `Init/Require` DI container running alongside AceAddon, or RxLua (used upstream only as a plain pub/sub bus — not worth a vendored reactive library).
- No hooking of Blizzard's `GroupLootFrame`/`LootFrame`, and no hooking other addons' loot buttons (the "ElvUI hack" pattern). We read loot state purely from events.
- No `UIDropDownMenu` / `MSA-DropDownMenu` anywhere.

## 3. Design principles

Derived directly from §7 and the "Rewrite recommendations" of the RCLootCouncil analysis:

| # | Principle | Why |
|---|---|---|
| 1 | Single addon, no base/override split | The split was the single largest fragility source in the source addon. |
| 2 | One source of truth for roster/council/candidate state | Source addon keeps 3 parallel tables (`Council` cache, `candidatesInGroup`, per-session `lootTable[session].candidates`) in sync by hand — a recurring bug category (ML/leader-change desync, "ranks showing up inconsistently"). |
| 3 | Event-driven loot detection only (`LOOT_READY`, `LOOT_SLOT_CLEARED`, `LOOT_CLOSED`, `START_LOOT_ROLL`) — never touch Blizzard's loot/roll frame objects | Already the dominant, *working* pattern upstream; we just don't regress from it the way the auto-pass-hide code does (`GroupLootContainer_RemoveFrame`). |
| 4 | Pre-validate every award client-side (`CanGiveLoot`-style check) before calling the protected `GiveMasterLoot` API | Proven defensive pattern upstream — keep it. |
| 5 | Own, custom-built dropdown/table/popup widgets — never `UIDropDownMenu` | Upstream had to vendor a taint patch *and* a dropdown replacement library to survive this. Avoid the class of bug entirely. |
| 6 | Version-gated wire protocol from message 1 | Upstream has a documented, permanently-unfixable duplicate-key bug in its MLDB wire format specifically because there's no version field to gate a breaking fix behind. |
| 7 | Built-in taint/error instrumentation from day one (`ADDON_ACTION_BLOCKED`/`ADDON_ACTION_FORBIDDEN` capture, global error handler) | Upstream only added this after being bitten repeatedly; building it first means we catch taint regressions in our own testing instead of from bug reports. |
| 8 | In-combat gating is structural, not a scattered manual `InCombatLockdown()` check per call site | Upstream gates per call site by hand, which is easy to miss on a new code path. We centralize "can we touch secure-adjacent UI right now" into the frame/session lifecycle itself. |
| 9 | A loot session's identity/ownership is sticky and **location-independent** — never reset by zoning, travel, group reformation, or the holder briefly losing Blizzard's "Master Looter" designation or disconnecting | User-reported pain point: upstream prompts "do you want this addon to handle loot?" on every raid entry, and a mis-click on that prompt while traveling mid-session breaks the active session. A session must persist purely on the holder's explicit "start" and "end" actions — never on ambient group/location state. See §5.3. |

## 4. Visual design system (from FojjiCore)

The entire addon UI — not just the options panel — adopts FojjiCore's look: fully custom `CreateFrame`-based widgets, no `BackdropTemplate`, no AceGUI, near-black flat-color fills with a single accent color, 1px hairline borders, one bundled font. This gives us a consistent, modern look across every window instead of mixing Blizzard-default chrome (AceConfigDialog, `lib-st`'s default skin, `LibDialog` popups) with a custom options panel.

### 4.1 Palette (ported from FojjiCore, to be re-tinted with our own accent)

| token | FojjiCore value | role |
|---|---|---|
| `accent` | `#66B3FF` (configurable via theme picker) | primary highlight / brand |
| `frame` | `#050507` | outer window fill |
| `header` | `#060709` | header bg base |
| `sidebar` | `#06080A` | sidebar fill |
| `content` | `#090A0C` | content panel fill |
| `field` / `fieldHover` | `#060709` / `#0B0D10` | inputs, dropdowns, checkboxes |
| `button` / `buttonHover` | `#0D0F11` / `#131619` | buttons |
| `border` / `borderDim` | `#292E38` / `#21262E` | hairline borders |
| `text` / `dim` | `#E0E3E8` / `#80878F` | body / secondary text |
| `warning` | `#FF4040` | close button, errors, pass/destructive actions |

**Decided accent: `#E8A33D`** (warm gold) — same dark-chrome system as FojjiCore, loot-flavored brand color instead of FojjiCore's azure, keeping the two addons visually distinct. Background shades (`frame`/`header`/`sidebar`/`content`/`border`/`button`) are derived from FojjiCore's `applyTheme()` formula (near-black base + small fraction of accent RGB mixed per channel) so the whole palette stays internally consistent without hand-tuning every token.

### 4.2 Construction primitives to port (pattern, not literal code)

A small local factory-function layer, no external UI dependency beyond a bundled font:
`createTexture`, `createArtwork`, `createText`, `createBorder` (4×1px strips, no backdrop template), `createButton`, `createCheckbox`, `createSlider`, `createDropdownButton` + a custom popup list module, `createScrollFrame`, `createPageHeader`, plus the **theme-registry** pattern (`themeTextures`/`themeFonts`/`themeGlows` weak tables + one `applyTheme()` call to retint everything live) if a theme/accent picker is wanted later.

### 4.3 Panel layout (reused for every PixlLootCouncil window)

Header bar (logo/title/version/close) → 1px separator → body. For multi-section windows (Options, History): fixed-width left sidebar with grouped nav buttons (not tabs) + content panel on the right, one child "page" per section, fade-switched. For single-purpose windows (Session frame, Voting frame): header + content, no sidebar.

### 4.4 Tabular data (Voting Frame, History, Version Check)

Upstream uses `lib-st` (ScrollingTable) skinned in the default WoW look. We build a **custom scrollable row-list widget** in the same dark theme (reusing `createScrollFrame`) rather than pulling in `lib-st`'s own skin, so these grids match the rest of the UI instead of looking like a bolted-on Blizzard table. This is new work (no direct upstream pattern to port) but is the single biggest piece needed to keep the "modern, consistent" look promise.

## 5. Architecture

```
PixlLootCouncil/
  PixlLootCouncil.toc
  Core/
    Init.lua          -- AceAddon bootstrap, SavedVariables defaults
    Events.lua         -- central event dispatch
    ErrorHandler.lua    -- seterrorhandler + ADDON_ACTION_BLOCKED/FORBIDDEN capture (built first, see principle 7)
  Data/
    Roster.lua          -- SINGLE source of truth: group members, council flags, online/role/ilvl state
    Session.lua          -- current loot session state (items, per-item candidate responses)
    SavedVariablesSchema.lua
  Comms/
    Protocol.lua        -- versioned message envelope, prefix registration
    Sync.lua             -- AceComm+AceSerializer+LibDeflate send/receive pipeline
  Loot/
    Detection.lua        -- LOOT_READY/LOOT_SLOT_CLEARED/LOOT_CLOSED/START_LOOT_ROLL handlers only
    Award.lua              -- CanGiveLoot-style pre-validation + GiveMasterLoot funnel
    Trade.lua               -- event-driven trade confirmation (no trade-frame hooking)
  UI/
    Theme.lua             -- palette, fonts, theme-registry (ported FojjiCore pattern)
    Widgets/              -- createButton/createCheckbox/createSlider/createDropdown/createTable/...
    SessionFrame.lua        -- ML: curate & start a loot session
    VotingFrame.lua           -- ML/council: candidate response grid + award buttons
    LootFrame.lua              -- candidate: respond to active session
    HistoryFrame.lua            -- past awards
    OptionsFrame.lua             -- FojjiCore-style settings panel
  Locale/
    Locales.xml             -- loads all 11 locale files (ported from RCLootCouncil_Classic strings where UI text matches)
    enUS.lua / deDE.lua / esES.lua / esMX.lua / frFR.lua / itIT.lua / koKR.lua / ptBR.lua / ruRU.lua / zhCN.lua / zhTW.lua
```

No `Overrides/` directory, no second module system, no RxLua.

### 5.1 Session continuity & ownership

A session belongs to whoever started it (the "holder") from the moment they click Start until they explicitly end it — never until a zone change, group reform, or Blizzard's own Master Looter designation says otherwise. Concretely:

- **No reactive "handle loot?" prompt.** Starting a session is always an explicit action (clicking Start in the Session Frame). There is nothing to accidentally decline while traveling.
- **Session state is persisted** (AceDB, character-scoped) on the holder's own client, independent of comms — so a `/reload`, a full disconnect/reconnect, or a zone transfer never loses it locally.
- **Ownership vs. the Blizzard loot-method check are separate concerns.** Holding a PixlLootCouncil session never requires *currently* being the live Blizzard Master Looter — that real-time check only gates the one moment an actual award is attempted (`GiveMasterLoot` is a protected API that genuinely requires it). Everything else (curating, voting, discussing) works regardless of the holder's momentary Blizzard ML status.
- **Resync, not replay.** Because comms delivery is inherently tied to being in the same group/channel (a hard WoW engine constraint — this cannot be worked around), a candidate who was briefly out of range (traveling separately, reconnecting) requests a full state resync from the holder rather than relying on having received every incremental message.
- **Stuck-session escape hatch (decided, see §9):** the holder broadcasts a lightweight periodic heartbeat while a session is active. If a council member observes the holder's heartbeat go stale past a threshold, they can force-end the session from their own client — this is the only exception to single-owner ownership, and exists purely so a holder who disconnects for the night doesn't block the raid indefinitely.

### 5.2 Data model

Single `Roster` object per raid/party, rebuilt on roster-change events, holding: GUID, name, class, role, online state, council flag, ilvl/gear snapshot (only what's needed for the voting grid "diff" columns). `Session` references `Roster` entries by GUID rather than keeping its own copy of player identity — eliminates the 3-parallel-tables problem from §3 principle 2. Per §5.1, `Session` also carries `owner = {guid, name}`, a unique `sessionId`, and `lastHolderSeenAt`, and is persisted in `PixlLootCouncilDB` (character-scoped) rather than being a purely in-memory table.

### 5.3 Comms protocol

Keep the proven low-level pipeline (`AceSerializer:Serialize` → `LibDeflate:CompressDeflate` → `EncodeForWoWAddonChannel` → `AceComm:SendCommMessage`), but wrap every payload in an envelope: `{ v = PROTOCOL_VERSION, cmd = "...", data = {...} }`. Receivers reject/ignore (with a one-time warning) any message whose `v` is higher than they understand, instead of attempting to parse a shape they don't recognize. This is what upstream is missing (§3 principle 6).

Beyond the core item/response/award flow, the command set includes what §5.1's continuity model needs: holder → group `session_heartbeat` (periodic while active), holder → group `session_end` (graceful), council-member → group `session_force_end` (stale-heartbeat escape hatch), and a `session_sync_request` / `session_sync_data` pair so a client that missed messages catches up via a full-state resync instead of replaying history.

## 6. Library dependencies

| Keep | Drop | Build custom instead |
|---|---|---|
| AceAddon-3.0, AceEvent-3.0, AceComm-3.0 + ChatThrottleLib, AceSerializer-3.0 + LibDeflate, AceDB-3.0 (+ profile switching), AceTimer-3.0, AceBucket-3.0, AceConsole-3.0 | AceGUI-3.0 (+SharedMediaWidgets), AceConfig-3.0/Dialog/Registry, `lib-st`, LibDialog-1.0, MSA-DropDownMenu-1.0, RxLua, the custom `Init/Require` DI layer | Options panel (FojjiCore-style), confirm/decline popups, dropdown menu, scrollable data table, frame position persistence (LibWindow is tiny enough we may still just vendor it rather than reinvent — low risk either way) |

Rationale: the Ace3 *infrastructure* libs (events/comm/serialization/db/timers) are solid, low-risk, and not where upstream's problems come from (§8 of the architecture analysis) — reinventing them would add risk for no benefit. Everything we drop is either a **UI skin** we're replacing with the FojjiCore-derived design system, or a dependency (RxLua, the second DI container) upstream itself only used narrowly enough that it added maintenance surface without real benefit.

## 7. Feature scope (phased — decided)

**Phase 1 — core loop (first working build):** loot detection, session start/curation (ML), candidate response UI (Need/Greed/Pass + configurable custom responses), voting grid, award with pre-validation, basic chat announcements, FojjiCore-styled options panel for the above, and all 11 locales for whatever UI strings exist at that point. No trade-window automation, no history frame, no cross-officer sync yet.

**Phase 2:** trade-window integration (event-driven confirm/track, no frame hooking), "award later"/bagged-item handling, loot history frame + persistent history SavedVariables.

**Phase 3:** cross-council sync (history sync between officers), import/export, response button-group customization (weapon/token/recipe-specific response sets), multi-vote / anonymous-vote options.

Locale files are maintained alongside every phase (new strings added to all 11 files as features land), rather than being a separate later phase.

## 8. SavedVariables (draft)

- `PixlLootCouncilDB` — AceDB object: `global` (error log, player cache), `profile` (all user-configurable behavior, response sets, button config, theme/accent choice), `char` (the active session, if this character currently holds one — see §5.1).
- `PixlLootCouncilHistoryDB` — separate AceDB instance, `factionrealm`-scoped, award history only (mirrors upstream's rationale for keeping history in its own SavedVariables file — it can get large and doesn't belong in the per-profile settings blob).

## 9. Decisions log

| Decision | Outcome |
|---|---|
| Accent color | `#E8A33D` warm gold — same FojjiCore-derived chrome, distinct brand color |
| Phase 1 scope | Core loop only (detection → session → voting → award); trade/history/sync deferred to Phases 2–3 |
| Localization | Port all 11 RCLootCouncil_Classic locales from the start, maintained alongside every phase |
| Stuck-session recovery | Any council member can force-end a session whose holder's heartbeat has gone stale (see §5.1) — prevents an indefinitely blocked raid while normal travel/reload/brief disconnects never trigger it |
