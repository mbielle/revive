#!/usr/bin/env python3
"""Adds a version to Revive's Sparkle appcast (newest first).

usage: update_appcast.py <appcast.xml> <version> <build> <download-url> '<sparkle:edSignature="…" length="…">' [notes.md]
"""
import datetime
import html
import os
import re
import sys

path, version, build, url, signature = sys.argv[1:6]
notes_path = sys.argv[6] if len(sys.argv) > 6 else ""

HEADER = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Revive</title>
    <link>https://github.com/mbielle/revive</link>
    <description>Updates for Revive, the free and open source Mac cleaner.</description>
    <language>en</language>
  </channel>
</rss>
"""


def markdown_to_html(text):
    """Enough Markdown for release notes: headings, bullet lists, bold and paragraphs."""
    out, in_list = [], False
    for line in text.splitlines():
        line = line.rstrip()
        bold = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", html.escape(line.lstrip("-# ").strip()))
        if line.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{bold}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if line.startswith("#"):
            out.append(f"<h3>{bold}</h3>")
        elif line:
            out.append(f"<p>{bold}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


notes = ""
if notes_path and os.path.exists(notes_path):
    notes = markdown_to_html(open(notes_path, encoding="utf-8").read())

attributes = dict(re.findall(r'([\w:]+)="([^"]*)"', signature))
if "sparkle:edSignature" not in attributes or "length" not in attributes:
    sys.exit(f"Unexpected sign_update output: {signature}")

date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
item = f"""    <item>
      <title>Revive {html.escape(version)}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{html.escape(url)}" sparkle:edSignature="{attributes['sparkle:edSignature']}" length="{attributes['length']}" type="application/octet-stream"/>
    </item>
"""

content = open(path, encoding="utf-8").read() if os.path.exists(path) else HEADER
# Replace an existing entry for the same build, then insert the new one first.
content = re.sub(rf"    <item>(?:(?!</item>).)*<sparkle:version>{re.escape(build)}</sparkle:version>.*?</item>\n", "", content, flags=re.S)
marker = "    <language>en</language>\n"
content = content.replace(marker, marker + item, 1)
open(path, "w", encoding="utf-8").write(content)
