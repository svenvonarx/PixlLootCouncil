local _, PLC = ...

-- The changelog in Options (UI/OptionsFrame.lua), from CHANGELOG.md by way of
-- Data/ChangelogText.lua. Only the parts of Markdown the changelog uses: "## " headings, "- "
-- bullets (indented ones a level deeper), plain paragraphs, **bold** and `code`.
local Changelog = {}
PLC.Changelog = Changelog

local function inline(text)
	text = text:gsub("|", "||") -- a lone | would start an escape sequence in a font string
	text = text:gsub("%*%*(.-)%*%*", "|cffffffff%1|r")
	text = text:gsub("`(.-)`", "%1")
	return text
end

-- { { title = "0.4.0-beta", items = { { level = 0 for a paragraph, 1 or 2 for a bullet, text } } } }
function Changelog.Parse(text)
	local sections, section, item = {}, nil, nil
	for line in (text .. "\n"):gmatch("(.-)\r?\n") do
		local heading = line:match("^##%s+(.-)%s*$")
		if heading then
			section = { title = heading, items = {} }
			sections[#sections + 1] = section
			item = nil
		elseif section then
			local indent, bullet = line:match("^(%s*)[-*]%s+(.+)$")
			if bullet then
				item = { level = #indent >= 2 and 2 or 1, text = bullet }
				table.insert(section.items, item)
			elseif line:match("^%s*$") then
				item = nil
			elseif item then
				item.text = item.text .. " " .. line:match("^%s*(.-)%s*$")
			else
				item = { level = 0, text = line:match("^%s*(.-)%s*$") }
				table.insert(section.items, item)
			end
		end
	end
	for _, s in ipairs(sections) do
		for _, i in ipairs(s.items) do
			i.text = inline(i.text)
		end
	end
	return sections
end

function Changelog:Get()
	return Changelog.Parse(PLC.CHANGELOG_TEXT or "")
end
