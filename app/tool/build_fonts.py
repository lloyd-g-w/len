#!/usr/bin/env python3
"""Builds the bundled fonts (app/assets/fonts) from Google Fonts.

Downloads the variable fonts (SIL Open Font License 1.1) from the
google/fonts repository, cuts static instances and subsets them to the
scripts Len is meant for (Latin, Greek, Cyrillic, punctuation, arrows, list
glyphs), so the app stays small and every platform renders - and wraps -
text with the same glyphs:
- the UI face, Sofia Sans (Regular, Medium, SemiBold, Bold; docs/DESIGN.md);
- the text-box fonts, Inter, Lora, JetBrains Mono and Caveat (Regular /
  Bold / Italic), also embedded in PDF export.

Usage (from the repo root; optionally only the named families, e.g. Caveat):
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

# github.com/<org>/<repo>/raw/<ref>/<path> (raw.githubusercontent.com may not resolve).
BASE = "https://github.com/google/fonts/raw/main/ofl/"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts")

TEXT_WEIGHTS = {"Regular": 400, "Bold": 700}
UI_WEIGHTS = {"Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700}

# family dir in google/fonts, output family file prefix, sources, extra axes
# (and the weights to cut, if not TEXT_WEIGHTS)
FAMILIES = [
    ("sofiasans", "SofiaSans", {"": "SofiaSans[wght].ttf"}, {}, UI_WEIGHTS),
    ("inter", "Inter", {"": "Inter[opsz,wght].ttf", "Italic": "Inter-Italic[opsz,wght].ttf"},
     {"opsz": 14}),
    ("lora", "Lora", {"": "Lora[wght].ttf", "Italic": "Lora-Italic[wght].ttf"}, {}),
    ("jetbrainsmono", "JetBrainsMono",
     {"": "JetBrainsMono[wght].ttf", "Italic": "JetBrainsMono-Italic[wght].ttf"}, {}),
    ("caveat", "Caveat", {"": "Caveat[wght].ttf"}, {}),
]

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
    for folder, prefix, sources, axes, *weights in FAMILIES:
        weights = weights[0] if weights else TEXT_WEIGHTS
        if only and prefix not in only:
            continue
        with open(os.path.join(OUT, f"{prefix}-OFL.txt"), "wb") as f:
            f.write(fetch(f"{folder}/OFL.txt"))
        for style, source in sources.items():
            data = fetch(f"{folder}/{source}".replace("[", "%5B").replace("]", "%5D"))
            for weight_name, weight in weights.items():
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
                # Keep tabular figures (AppTheme.tabularFigures) and
                # case-sensitive forms, which the default set drops.
                options.layout_features += ["tnum", "case"]
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
