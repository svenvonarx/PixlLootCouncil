-- Run from the addon folder: luajit tests/changelog_test.lua
--
-- The changelog in Options: Data/ChangelogText.lua has to match CHANGELOG.md (run
-- tools/make_changelog_lua.py after editing it), and Data/Changelog.lua reads it.
local out = print
local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

local PLC = {}
assert(loadfile("Data/ChangelogText.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Data/Changelog.lua"))("PixlLootCouncil", PLC)
local file = assert(io.open("CHANGELOG.md", "rb")):read("*a"):gsub("\r\n", "\n")
check("CL1", PLC.CHANGELOG_TEXT == file, "the in-game copy matches CHANGELOG.md (if not: python3 tools/make_changelog_lua.py)")

local sample = [[
# Changelog

## 1.1.0

A short intro
that wraps.

- **Bold** start, with `code` and a | pipe
  continued here.
  - nested
- second

## 1.0.0

- first release
]]
local sections = PLC.Changelog.Parse(sample)
check("CL2", #sections == 2 and sections[1].title == "1.1.0" and sections[2].title == "1.0.0", "a section per version, skipping the file's own title")
local items = sections[1].items
check("CL3", #items == 4 and items[1].level == 0 and items[1].text == "A short intro that wraps.", "a paragraph's lines are joined")
check("CL4", items[2].level == 1 and items[2].text == "|cffffffffBold|r start, with code and a || pipe continued here.",
	"a bullet with its continuation, bold in white, code plain and a pipe made safe: " .. items[2].text)
check("CL5", items[3].level == 2 and items[3].text == "nested" and items[4].level == 1, "an indented bullet sits a level deeper")

local real = PLC.Changelog:Get()
local total = 0
for _, s in ipairs(real) do total = total + #s.items end
check("CL6", #real >= 4 and total > 30 and real[#real].title == "0.1.0-beta", "the real changelog reads, down to the first release")
local unbalanced = {}
for _, s in ipairs(real) do
	for _, i in ipairs(s.items) do
		local opens = select(2, i.text:gsub("|c", ""))
		local closes = select(2, i.text:gsub("|r", ""))
		if opens ~= closes or i.text:find("%*%*") then unbalanced[#unbalanced + 1] = i.text:sub(1, 40) end
	end
end
check("CL7", #unbalanced == 0, "every bold in it is closed " .. table.concat(unbalanced, "; "))

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
