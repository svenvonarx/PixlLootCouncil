# FojjiCore Options Panel — UI/Styling Analysis

Source: `FojjiCore/Options.lua` (1383 lines, read in full), `FojjiCore/OptionsMenu.lua` (285 lines, read in full), `FojjiCore/Media.lua` (114 lines, read in full). All file:line references below are relative to the FojjiCore addon root:
`/run/media/pixl/Games/World of Warcraft/_anniversary_/Interface/AddOns/FojjiCore/`

## 1. UI toolkit

**Fully custom, raw Frame API.** No AceGUI/AceConfig anywhere. Every widget (button, checkbox, slider, dropdown, scrollbar, popup menu) is hand-built with `CreateFrame` + `CreateTexture`/`CreateFontString`, wrapped in small local factory functions defined at the top of `Options.lua`.

The only external libs touched are standard ones for non-visual purposes:
- `LibStub("LibDataBroker-1.1")`, `LibStub("LibDBIcon-1.0")` — minimap button (Options.lua:13-14)
- `LibStub("LibSharedMedia-3.0")` — font **list** source for the font picker, not for rendering the options UI itself (Options.lua:15, 647)

Key construction primitive (Options.lua:159-164):
```lua
local function createTexture(parent,layer,colorName,alpha)
    local texture = parent:CreateTexture(nil,layer)
    texture:SetColorTexture(color(colorName,alpha))
    themeTextures[texture] = { name = colorName, alpha = alpha }  -- registered for live re-theming
    return texture
end
```
Nearly all flat-color fills go through `createTexture`, which also registers the texture in a weak-keyed table (`themeTextures`) so that `applyTheme()` can retint every solid-color surface in the UI at once when the user switches theme presets (Options.lua:107-143). This "theme registry" pattern (also `themeFonts`, `themeGlows`) is the most notable reusable idea here — it makes a live, addon-wide re-skin trivial.

## 2. Panel structure

Root frame `FojjiCoreOptionsFrame` (Options.lua:782-797):
- `CreateFrame("Frame","FojjiCoreOptionsFrame",UIParent)`, `FrameStrata("DIALOG")`, `FrameLevel(100)`.
- Resizable: `SetResizable(true)`, `SetResizeBounds(760,540,1440,1080)`, default size 880×620 (`LAYOUT.width/height`, Options.lua:40-41).
- Movable by dragging anywhere on the frame body (`RegisterForDrag("LeftButton")`, drag handlers at Options.lua:793-795) — **no separate title-bar drag region**, the whole header frame is draggable implicitly since the parent frame itself has the drag scripts.
- Custom bottom-right resize grip using Blizzard's stock textures (Options.lua:798-803):
  `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up` / `...-Highlight` — the one place Blizzard art is reused instead of custom art.
- Registered into `UISpecialFrames` so Escape closes it (Options.lua:822).
- `SetScale(DB.optionsScale)` — user-adjustable UI scale stored in SavedVariables (60%–140% in the Appearance tab, Options.lua:1059-1069).

**Chrome layout** (Options.lua:818-913):
- Full-bleed background texture (`frame` color) + 1px hairline border via `createBorder` (see §3).
- **Header bar**, height 60 (`LAYOUT.headerHeight`), spans top, holds: metal background art, logo icon, colored title text, version text, an "atmosphere" glow overlay, a bottom edge-light strip, a tinted corner ornament, and a close button (top-right).
- 1px separator line between header and body (Options.lua:875-878).
- **Body** = sidebar (fixed width 164px, `LAYOUT.sidebarWidth`) + content panel (fills remainder), divided by a 1px vertical line (Options.lua:884-909).
- **Sidebar** = vertical nav list, grouped under small uppercase section headers ("RAID TOOLS", "FOJJI WEAKAURAS", "SETTINGS"), each group built by `addSidebarHeader`/`addTab` helpers (Options.lua:968-991). This is a **category sidebar**, not horizontal tabs.
- **Content panel**: subtle background, a large (180×180, alpha 0.018) ghost logo watermark bottom-right, a grain texture overlay, 1px accent-tinted bottom edge. Inside it sits a `content` frame padded 20px (`LAYOUT.contentPadding`) left/right, 24/26px top/bottom, which hosts one "page" per tab.
- **Pages**: each tab maps to its own full-size child frame (`pages[name]`) that is shown/hidden; only one visible at a time, switched via `selectTab()` (Options.lua:721-741) with a 0.12s alpha fade-in (`fadePage`, Options.lua:715-719, uses `UIFrameFadeIn`). No true scroll frame wraps the whole content area by default — `createScrollFrame` exists as a reusable helper (Options.lua:391-419) and is passed into the Speedrun sub-page builder for a scrollable region (Options.lua:997) but the standard tabs (TTS, Font, Appearance, About) just lay widgets out in a fixed frame.
- Each page gets a standard header via `createPageHeader` (Options.lua:383-389): large title text + a 1px separator line 40px below it.

**Navigation model**: sidebar button list, one active at a time, active state shown via a 3px-wide left-edge color bar (`indicator`) + a faint full-button background glow (`glow`, 10% accent alpha) + brighter label color; hover state (when not active) shows a very faint white glow (2.5% alpha) and lightens the label (Options.lua:924-964).

**Dropdowns** are not native Blizzard `UIDropDownMenu` — they're a fully custom popup list widget (`Addon.OptionsMenu`, OptionsMenu.lua) anchored under the invoking button, with its own scrollbar, hover highlight, selection mark, optional per-row "tag" label, and optional per-row remove/favorite "x" button. It closes on outside click via a full-screen invisible "catcher" button (OptionsMenu.lua:190-196) and auto-closes if its owner becomes invisible (OptionsMenu.lua:220-222). It supports flipping to open upward if there isn't enough room below (OptionsMenu.lua:256-260).

## 3. Visual styling specifics

### Color palette (Options.lua:17-37)
All colors are `{r,g,b}` floats 0–1, in a single `COLORS` table referenced everywhere by name via `color(name, alpha)` (Options.lua:154-157):

| name | RGB (0-1) | approx hex | use |
|---|---|---|---|
| accent | 0.40, 0.70, 1.00 | #66B3FF | primary brand/highlight (default "fojji" theme; overridden by theme picker) |
| title | 0.90, 0.94, 1.00 | #E6F0FF | page/header titles |
| frame | 0.018, 0.021, 0.026 | #050507 | outer window fill |
| header | 0.022, 0.026, 0.032 | #060709 | header bg tint base |
| sidebar | 0.025, 0.032, 0.040 | #06080A | sidebar fill |
| content | 0.035, 0.040, 0.048 | #090A0C | content panel fill |
| field | 0.024, 0.028, 0.034 | #060709 | input/dropdown/checkbox box fill |
| fieldHover | 0.044, 0.052, 0.064 | #0B0D10 | input hover fill |
| button | 0.052, 0.058, 0.068 | #0D0F11 | button fill |
| buttonHover | 0.075, 0.088, 0.105 | #131619 | button hover fill |
| border | 0.16, 0.18, 0.22 | #292E38 | default 1px border |
| borderDim | 0.13, 0.15, 0.18 | #21262E | subtler separators |
| text | 0.88, 0.89, 0.91 | #E0E3E8 | body text |
| dim | 0.50, 0.53, 0.57 | #80878F | secondary/hint text |
| tab | 0.61, 0.64, 0.68 | #9BA3AD | inactive sidebar label |
| tabHover | 0.88, 0.90, 0.92 | #E0E6EB | sidebar label hover |
| scroll | 0.08, 0.09, 0.11 | #15171C | scrollbar track |
| white | 1, 1, 1 | #FFFFFF | emphasis text |
| warning | 1.00, 0.25, 0.25 | #FF4040 | close button / error / favorites-missing text |

Title bar brand text uses inline color codes rather than the palette: `"|cff66b3ffFojji|cffff4444Core|r"` (Options.lua:837, 1234) — azure "Fojji" + red "Core".

**Theme system**: 4 presets (`THEME_ORDER`/`THEMES`, Options.lua:110-116) — Fojji/Azure `{0.40,0.70,1.00}`, Ember/Crimson `{1.00,0.30,0.26}` (default), Arcane/Violet `{0.70,0.48,1.00}`, Jade/Emerald `{0.20,0.88,0.66}`. `applyTheme(key)` (Options.lua:117-143) derives `frame/header/sidebar/content/border/borderDim/button/buttonHover` by mixing a small fraction of the theme's accent RGB into near-black base values (e.g. `frame = {0.015+r*0.014, 0.018+g*0.014, 0.026+b*0.014}`), giving each theme a consistent very-dark, slightly tinted background plus a bright accent. This is a clean formula worth porting: near-black bases + `base + accent*k` per channel for consistent low-saturation tinting across arbitrary accent colors.

### Fonts
- Single custom font file used for *all* UI text: `Interface\AddOns\FojjiCore\font\Numen.ttf` (Options.lua:9, OptionsMenu.lua:9).
- `createText` (Options.lua:176-183) sizes it as `math.max(9, floor(size*0.8+0.5))` — i.e. requested sizes are scaled down ~20% before `SetFont`, with no outline flag (empty string `""` for the 3rd `SetFont` arg — no outline/shadow).
- OptionsMenu.lua's `SetFont` helper (line 18-20) falls back to `STANDARD_TEXT_FONT` if `Numen.ttf` fails to load, as a safety net.
- A second bundled font exists but is **not used by the options UI**: `Interface\AddOns\FojjiCore\font\FojjiArcade.ttf`, registered only in LibSharedMedia (Media.lua:4) for user-selectable WeakAuras text fonts (the addon's actual "Fonts" feature, unrelated to options-panel chrome).
- Font sizes used in options code: title 20-22, section labels 13, body/buttons/dropdown text 11-12, hints/dim text 10, sidebar group headers 10.

### Borders / backdrops
No Blizzard `BackdropTemplate`/`SetBackdrop` anywhere — borders are hand-built from 4 separate 1px flat-color textures via `createBorder` (Options.lua:185-212):
```lua
local function createBorder(parent,colorName,alpha,inset)
    inset = inset or 0
    colorName = colorName or "border"
    local border = {}
    border.top = createTexture(parent,"BORDER",colorName,alpha)
    border.top:SetPoint("TOPLEFT",inset,-inset)
    border.top:SetPoint("TOPRIGHT",-inset,-inset)
    border.top:SetHeight(1)
    -- ...bottom/left/right mirror this, each a 1px-thick texture spanning that edge
    return border
end
```
Produces a plain hairline rectangle; `setBorderColor` (Options.lua:214-218) retints all 4 strips at once (used heavily for hover states — borders flash to `accent` color on mouseover). This 4-texture-strip border is the core reusable "panel border" primitive and trivially portable to any new addon (no backdrop XML template needed, no edge-texture tiling math).

### Background/decorative art textures (TGA files, see §5 for full paths)
- `header-metal.tga` (2048×256) — header background art, applied as a stretched `createArtwork` texture (Options.lua:829).
- `header-light.tga` (2048×256) — "atmosphere" overlay on header, tinted with accent color via `tinted=true` flag → registered in `themeGlows` so theme switches recolor it with `SetVertexColor` (Options.lua:843, 166-174).
- `header-edge.tga` (2048×64) — bottom edge-light strip under header, 16px tall, accent-tinted (Options.lua:845-846).
- `panel-corner.tga` (128×128) — small 24×24 corner ornament, accent-tinted, alpha 0.5, top-left of header (Options.lua:847-848).
- `panel-grain.tga` (1024×1024) — subtle grain/noise overlay stretched across the whole content panel, untinted (Options.lua:898).
- `close-cross.tga` (32×32) — close button icon, 22×22, vertex-colored manually (not via theme registry) to a fixed reddish tone `(.9,.43,.40)` normally / `(1,.8,.75)` on hover (Options.lua:857-862).
- `glow-blob.tga` (256×256) — present in `textures/UI/` but **not referenced** in Options.lua/OptionsMenu.lua; likely used by the Speedrun timer display itself, not the options panel. Skippable for options-UI purposes.

`createArtwork` helper (Options.lua:166-174):
```lua
local function createArtwork(parent, asset, layer, tinted)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
    texture:SetTexture("Interface\\AddOns\\FojjiCore\\textures\\UI\\"..asset)
    if tinted then
        texture:SetVertexColor(color("accent"))
        themeGlows[texture] = true   -- re-tinted on theme change
    end
    return texture
end
```

### Widget-specific styling

**Button** (`createButton`, Options.lua:260-283): flat `button` color fill + 1px border, centered label text, size `(width, 28)` (`LAYOUT.buttonHeight`). Hover: bg → `buttonHover`, border → `accent` at 0.75 alpha. No pressed/down-state texture — only Enter/Leave scripts, no OnMouseDown visual.

**Checkbox** (`createCheckbox`, Options.lua:285-336): custom 16×16 box (not a Blizzard CheckButton template) — `field`-colored background + border, a solid `accent`-colored fill texture (inset 3px) shown/hidden via `SetShown` to represent the check mark (no checkmark glyph/texture, just a filled accent square). Label to the right (+9px gap). Hover: border → `accent` @0.85, label → white.

**Slider** (`createSlider`, Options.lua:338-377): real `CreateFrame("Slider")`, horizontal, track is a 4px-tall `scroll`-colored bar, thumb is a 12×20 solid `accent`-colored texture (`SetThumbTexture`). Min/max value labels below track ends, live value label to the right of the track. No fill/progress bar distinct from the track — just background bar + draggable thumb.

**Dropdown button** (`createDropdownButton`, Options.lua:421-450): same visual language as text fields — `field` bg + border, left-justified text, right-aligned "v" glyph (not a texture arrow) in muted gray `(0.65,0.68,0.72)`. Hover: bg → `fieldHover`, border → `accent` @0.70.

**Dropdown popup menu** (OptionsMenu.lua): background = `header` color @0.98 alpha; 1px border on all 4 edges in `accent` @0.7; row height 22px; row hover highlight = `accent` @0.16 alpha full-row texture; selected-row indicator = a 2px-wide solid `accent` strip on the row's left edge (`row.mark`); optional per-row "tag" pill text in `dim` color; optional per-row remove ("x") or favorite ("FAV") button that turns `warning`-red on hover; custom 3px-wide scrollbar/thumb in `accent`@0.75 over a `scroll`-colored track, shown only when content overflows `maxRows`. Opens below its owner by default, flips above if insufficient space (`openUp` option or automatic room-check).

**Close button** (Options.lua:850-868): 30×30, bg `(.08,.035,.04,.65)` (dark red-black) with a `warning`-colored border @0.24 alpha, `close-cross.tga` icon vertex-colored dusty red. Hover: bg brightens to `(.24,.035,.045,.95)`, border → `warning`@0.7, icon → light pink `(1,.8,.75)`. This is the one place styling deviates from the shared palette/theme system (hardcoded reds instead of `COLORS.warning` consistently, though close to it).

**No gradient textures or drop-shadow effects** beyond the flat-color/tint layering described above (the "glow" on hover is just a flat-alpha texture, not a radial gradient asset).

## 4. Reusable construction patterns

All defined as local functions in `Options.lua` (lines noted); these are the actual "widget factory" layer and the most directly portable part of this codebase:

```lua
color(name, alpha)                                  -- Options.lua:154-157  palette lookup -> r,g,b,a
createTexture(parent, layer, colorName, alpha)       -- Options.lua:159-164  flat color texture, theme-registered
createArtwork(parent, asset, layer, tinted)          -- Options.lua:166-174  loads textures/UI/<asset>, optional accent tint
createText(parent, text, size, colorName)            -- Options.lua:176-183  Numen.ttf fontstring, theme-registered color
createBorder(parent, colorName, alpha, inset)         -- Options.lua:185-212  4-texture hairline border, returns {top,bottom,left,right}
setBorderColor(border, colorName, alpha)              -- Options.lua:214-218  retint all 4 border strips
anchorBelow(object, previous, gap)                    -- Options.lua:220-223  vertical stacking helper (TOPLEFT->BOTTOMLEFT)
applyDefaults(target, defaults)                       -- Options.lua:225-234  recursive SavedVariables defaults merge
createSeparator(parent, y)                            -- Options.lua:252-258  1px horizontal rule
createButton(parent, text, width)                     -- Options.lua:260-283  styled button w/ hover
createCheckbox(parent, text, onChanged)               -- Options.lua:285-336  styled checkbox w/ SetChecked/GetChecked
createSlider(parent, labelText, minValue, maxValue, step)  -- Options.lua:338-377  labeled slider w/ min/max/value text
createSectionLabel(parent, text)                      -- Options.lua:379-381  13px white label (thin wrapper on createText)
createPageHeader(parent, title)                       -- Options.lua:383-389  20px title + separator 40px below
createScrollFrame(parent)                             -- Options.lua:391-419  ScrollFrame + custom vertical scrollbar
createDropdownButton(parent)                          -- Options.lua:421-450  styled field-like button w/ "v" arrow
createDropdownMenu(button, entries)                   -- Options.lua:452-463  wraps Addon.OptionsMenu.Open with entry mapping
applyTheme(key)                                       -- Options.lua:117-143  recomputes COLORS + retints all registered textures/fonts
```

Theme-registry pattern worth highlighting for porting: `createTexture`/`createText`/`createArtwork(tinted=true)` all register themselves into weak-keyed tables (`themeTextures`, `themeFonts`, `themeGlows`) keyed by the actual texture/fontstring object. `applyTheme()` then iterates those tables and calls `SetColorTexture`/`SetTextColor`/`SetVertexColor` on every live widget, giving a one-call global re-skin with no need to track widget references elsewhere. Any new options panel that wants theme switching should copy this registry approach rather than re-deriving colors per-widget.

`Addon.OptionsMenu` (OptionsMenu.lua) is a fully self-contained, addon-API-style popup menu module (`Open(owner, entries, opts)` / `Close()` / `IsOpen(owner)` / `Refresh()`) independent of the rest of Options.lua except for pulling colors via `Addon.GetColor`. It's directly copy-portable as a generic "styled dropdown list" component for a new addon — it only assumes a global `Addon.GetColor(name)` returning r,g,b (Options.lua:149-152 is the counterpart) and a `FONT` path constant.

## 5. Texture inventory (exact paths used by Options.lua/OptionsMenu.lua)

All under `FojjiCore/textures/UI/` (root-relative: `Interface\AddOns\FojjiCore\textures\UI\<file>`):

| file | dims | slot / purpose | referenced at |
|---|---|---|---|
| `header-metal.tga` | 2048×256 | header background art | Options.lua:829 |
| `header-light.tga` | 2048×256 | header atmosphere/glow overlay (accent-tinted) | Options.lua:843 |
| `header-edge.tga` | 2048×64 | header bottom edge-light strip (accent-tinted) | Options.lua:845 |
| `panel-corner.tga` | 128×128 | header top-left corner ornament (accent-tinted, 50% alpha) | Options.lua:847 |
| `panel-grain.tga` | 1024×1024 | content-panel noise/grain overlay | Options.lua:898 |
| `close-cross.tga` | 32×32 | close button icon | Options.lua:857 |

Not from `textures/UI/` but also referenced by Options.lua:
- `Interface\AddOns\FojjiCore\textures\FojjiIcons\F_icon_lightblue` (Options.lua:8, `ICON` constant) — used as: minimap launcher icon, header logo (44×44), content-panel watermark (180×180 @ alpha 0.018), About-page logo (68×68). This is the addon's brand mark; a new addon would substitute its own logo here.
- Blizzard stock textures (not FojjiCore assets): `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up` / `UI-ChatIM-SizeGrabber-Highlight` (Options.lua:802-803) — resize grip icon.

Present in `textures/UI/` but **not referenced** by the options code (used elsewhere, e.g. the speedrun timer display — skip for options-panel porting purposes):
- `glow-blob.tga` (256×256)

"Texture slots" summary for re-skinning: **header-bg**, **header-glow-overlay** (tintable), **header-bottom-edge** (tintable), **corner-ornament** (tintable), **content-grain-overlay**, **close-icon**, **brand-logo**. Everything else (panel fills, borders, checkbox fill, slider thumb, dropdown arrow, scrollbar, hover highlights) is pure flat-color `SetColorTexture`/font glyphs — no texture art needed at all for those.

## 6. Font inventory

Both under `FojjiCore/font/`:
- `Numen.ttf` — `Interface\AddOns\FojjiCore\font\Numen.ttf` — **the only font actually used to render the options panel** (titles, labels, buttons, dropdowns, menu rows). Hardcoded path constant `FONT` in both Options.lua:9 and OptionsMenu.lua:9 (not loaded via LibSharedMedia for the panel chrome itself, even though LSM is used elsewhere to let end users pick fonts for their WeakAuras auras).
- `FojjiArcade.ttf` — `Interface\AddOns\FojjiCore\font\FojjiArcade.ttf` — registered with LibSharedMedia (Media.lua:4) for the addon's WeakAuras-font-patching feature; **not used anywhere in the options panel UI itself**.

LibSharedMedia (`LibStub("LibSharedMedia-3.0")`) is used in Options.lua only to populate the "Font" picker dropdown list on the Fonts tab (`getFonts()`, Options.lua:644-656) — i.e. to list fonts the user can apply to their *WeakAuras auras*, not to theme the options panel chrome, which always renders in Numen.ttf regardless of SharedMedia state.

## Practical porting takeaways for PixlLootCouncil

1. Skip AceGUI entirely; a hand-rolled factory-function layer (`createTexture`/`createText`/`createBorder`/`createButton`/etc., all ~5-30 lines) reproduces this look with no external dependency beyond the font file.
2. The whole look is dominated by near-black flat-color fills + a single accent color + 1px hairline borders; only ~6 small texture files (header art, grain, corner, close icon) carry any actual "art," everything else is `SetColorTexture`.
3. The theme-registry retint pattern (`themeTextures`/`themeFonts`/`themeGlows` weak tables + `applyTheme()`) is the cleanest piece to copy if a "theme picker" / accent-color picker is wanted later.
4. The custom dropdown-menu module (`OptionsMenu.lua`) is self-contained and could be copied near-verbatim (swap `Addon.GetColor`/`FONT` for the new addon's equivalents) to get a native WoW `UIDropDownMenu` replacement with the same look.
5. Sidebar category navigation (not top tabs) with grouped section headers is the layout backbone — straightforward to replicate: fixed-width left frame, vertical list of buttons, indicator bar + background glow for active state.
