"""MoonOps canonical palette, generated from tokens.css.

Single source of truth for any Python script that renders a branded MoonOps
asset. Import these constants instead of hardcoding hex values, so every
generated asset stays aligned with the design system (tokens.css / palette.json).

Do not edit these values by hand: tokens.css is authoritative: update it there,
then mirror the change into palette.json and this file.
"""

INK = "#0d162a"
CARD = "#16224a"
CREAM = "#f6f0eb"
STEEL = "#92a2c4"
PURPLE = "#b95cff"
PURPLE_BRIGHT = "#c879ff"
GREEN = "#4aff9e"
AMBER = "#ffc86b"
ROSE = "#ff6b8a"
GOLD = "#d8c074"       # the channel crescent only (lab hero crescent, its nav moon, og-lab card); never portfolio pages
TEXT_LEAD = "#cdd6e8"  # subtitle / lead lines on gradient pages, between steel and cream

FONT_DISPLAY = "Poppins"
FONT_MONO = "JetBrains Mono"
