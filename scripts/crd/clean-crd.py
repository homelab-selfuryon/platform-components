#!/usr/bin/env python3
"""Clean the output of `cue get crd` as described in .claude/skills/crd-generation.

Usage: clean-crd.py <file.cue>...   (rewrites the files in place)

Drops the import block and validators that used it, the `_embeddedResource` embedding and its
block, the top-level `status?` field (controller-owned) and the `...` in the trailing metadata.
"""
import re
import sys


def drop_block(lines, start):
    """Remove the brace-balanced block opening on lines[start] (and its leading comment)."""
    depth, end = 0, start
    for i in range(start, len(lines)):
        depth += lines[i].count("{") - lines[i].count("}")
        if depth <= 0 and i >= start:
            end = i
            break
    first = start
    while first > 0 and lines[first - 1].lstrip().startswith("//"):
        first -= 1
    if first > 0 and lines[first - 1].strip() == "":
        first -= 1
    del lines[first : end + 1]


def clean(text):
    text = re.sub(r"import \(.*?\)\n\n?", "", text, count=1, flags=re.S)
    text = re.sub(r"strings\.(Max|Min)Runes\(\d+\) & ", "", text)
    text = re.sub(r"list\.(Max|Min)Items\(\d+\) & ", "", text)
    text = re.sub(r"\btime\.Time\b", "string", text)
    lines = text.split("\n")
    # _embeddedResource: embedding line and the definition block
    lines = [l for l in lines if l.strip() != "_embeddedResource"]
    i = 0
    while i < len(lines):
        if lines[i].strip().startswith("_embeddedResource:"):
            drop_block(lines, i)
            continue
        i += 1
    # top-level status
    i = 0
    while i < len(lines):
        if re.match(r"^\tstatus\??: \{", lines[i]):
            drop_block(lines, i)
            continue
        i += 1
    out = "\n".join(lines)
    out = re.sub(r"(metadata!: \{[^{}]*?)\n\t*\.\.\.\n", r"\1\n", out)
    return out


for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as f:
        src = f.read()
    with open(path, "w", encoding="utf-8") as f:
        f.write(clean(src))
