"""Copies CHANGELOG.md into Data/ChangelogText.lua, for the changelog in Options: the game can't read
a .md file. Run it after editing the changelog; tests/changelog_test.lua fails until you do.
Usage: python3 tools/make_changelog_lua.py"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
text = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read().replace("\r\n", "\n")
level = 0
while "]" + "=" * level + "]" in text:
    level += 1
eq = "=" * level
out = (
    "local _, PLC = ...\n\n"
    "-- Generated from CHANGELOG.md by tools/make_changelog_lua.py. Edit the changelog, not this.\n"
    f"PLC.CHANGELOG_TEXT = [{eq}[\n{text}]{eq}]\n"
)
open(os.path.join(ROOT, "Data", "ChangelogText.lua"), "w", encoding="utf-8", newline="\n").write(out)
print("written: Data/ChangelogText.lua")
