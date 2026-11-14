"""The colours the charts use for meaning. They match [theme] in app/.streamlit/config.toml.

One colour per idea, everywhere in the app: blue is a delivery that kept its promise, crimson is a late one. The set passed a
palette check (lightness band, chroma floor, colour-vision separation, contrast against the page).
"""

BLUE = "#2468A8"      # on time, and anything with no better claim
CRIMSON = "#C0283D"   # late, the problem
AMBER = "#B9861A"     # a third group when one is needed
TEAL = "#2A9D8F"      # a fourth
MUTED_BAR = "#B8C2CF"  # bars that are not the focus

ARRIVAL_DOMAIN = ["On time or early", "Late"]
ARRIVAL_RANGE = [BLUE, CRIMSON]
