#!/usr/bin/env python3
"""Writes index.html from index.template.html and img/channel.txt (made by glyphs.swift):
the glyph picture's rows for the canvas, and the same picture as text for a page without script."""
import json, os
here = os.path.dirname(os.path.abspath(__file__))
rows = open(os.path.join(here, 'img/channel.txt')).read().split()
text = 'labconnectedlaptop-01198.18.68.2gatedirect4mshandshake58sago10.99.0.0/16viagate'
k = 0
pre = []
for r in rows:
    line = ''
    for c in r:
        if c == '0':
            line += ' '
        else:
            line += text[k % len(text)]
            k += 1
    pre.append(line.rstrip())
page = open(os.path.join(here, 'index.template.html')).read()
page = page.replace('{{ROWS}}', json.dumps(rows)).replace('{{PRE}}', '\n'.join(pre))
open(os.path.join(here, 'index.html'), 'w').write(page)
