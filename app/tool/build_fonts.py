#!/usr/bin/env python3
"""Builds the bundled text-box fonts (app/assets/fonts) from Google Fonts.

Downloads the variable fonts (SIL Open Font License 1.1) from the
google/fonts repository, cuts static Regular / Bold (/ Italic) instances
and subsets them to the scripts Len's text boxes are meant for (Latin,
Greek, Cyrillic, punctuation, arrows, list glyphs), so the app stays small
and every platform renders - and wraps - text boxes with the same glyphs.

Usage (from the repo root; optionally only the named families, e.g. Kalam):
  nix shell --impure --expr 'with import (builtins.getFlake "nixpkgs") {};
    python3.withPackages (p: [p.fonttools])' -c python3 app/tool/build_fonts.py [Prefix ...]
"""
import io
import os
import sys
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

BASE = "https://raw.githubusercontent.com/google/fonts/main/ofl/"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts")

# family dir in google/fonts, output family file prefix, sources, extra axes
FAMILIES = [
    ("inter", "Inter", {"": "Inter[opsz,wght].ttf", "Italic": "Inter-Italic[opsz,wght].ttf"},
     {"opsz": 14}),
    ("lora", "Lora", {"": "Lora[wght].ttf", "Italic": "Lora-Italic[wght].ttf"}, {}),
    ("jetbrainsmono", "JetBrainsMono",
     {"": "JetBrainsMono[wght].ttf", "Italic": "JetBrainsMono-Italic[wght].ttf"}, {}),
    ("caveat", "Caveat", {"": "Caveat[wght].ttf"}, {}),
    ("nunito", "Nunito", {"": "Nunito[wght].ttf", "Italic": "Nunito-Italic[wght].ttf"}, {}),
    # Static fonts: one file per weight.
    ("kalam", "Kalam", {"": {"Regular": "Kalam-Regular.ttf", "Bold": "Kalam-Bold.ttf"}}, {}),
]
WEIGHTS = {"Regular": 400, "Bold": 700}

UNICODES = (
    "U+0000-024F,U+0250-02FF,U+0300-036F,U+0370-03FF,U+0400-04FF,U+1E00-1EFF,"
    "U+2000-206F,U+20A0-20CF,U+2100-214F,U+2150-218F,U+2190-21FF,U+2200-22FF,"
    "U+25A0-25FF,U+2610-2612,U+2713-2714,U+FB00-FB06"
)


def fetch(path):
    with urllib.request.urlopen(BASE + path) as r:
        return r.read()


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for folder, prefix, sources, axes in FAMILIES:
        if only and prefix not in only:
            continue
        with open(os.path.join(OUT, f"{prefix}-OFL.txt"), "wb") as f:
            f.write(fetch(f"{folder}/OFL.txt"))
        for style, source in sources.items():
            if isinstance(source, str):
                data = fetch(f"{folder}/{source}".replace("[", "%5B").replace("]", "%5D"))
            for weight_name, weight in WEIGHTS.items():
                if isinstance(source, dict):
                    static = TTFont(io.BytesIO(fetch(f"{folder}/{source[weight_name]}")))
                else:
                    font = TTFont(io.BytesIO(data))
                    static = instancer.instantiateVariableFont(
                        font, {"wght": weight, **axes}, updateFontNames=True
                    )
                options = subset.Options()
                options.name_IDs = ["*"]
                options.name_languages = ["*"]
                options.notdef_outline = True
                options.glyph_names = False
                options.hinting = False  # Flutter does not hint; smaller files.
                sub = subset.Subsetter(options)
                sub.populate(unicodes=subset.parse_unicodes(UNICODES))
                sub.subset(static)
                name = weight_name if not style else (
                    style if weight_name == "Regular" else weight_name + style)
                path = os.path.join(OUT, f"{prefix}-{name}.ttf")
                static.save(path)
                print(path, os.path.getsize(path))


if __name__ == "__main__":
    main()
