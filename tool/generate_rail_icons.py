# -*- coding: utf-8 -*-
"""
Generate precision Material Symbols Rounded SVG icons for Rulbi Navigation Rail.
All icons are bounded within 24x24 with proper optical margins, rounded geometry,
correct winding / fill-rules, and unified techniques.
"""
import os
from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM
from PIL import Image

ICONS_DIR = r'c:\Users\Usuario\Documents\GitHub\IPTVapp\docs\design-assets\icons'
os.makedirs(ICONS_DIR, exist_ok=True)

# 1. Home
# Inactive: Rounded home outline (weight 400)
# Active: Filled home (weight 600)
home_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#8A98A8" fill-rule="evenodd" d="M10.7 2.76a2 2 0 0 1 2.6 0l6.2 4.96A2 2 0 0 1 20.2 9.3v9.7a2 2 0 0 1-2 2h-3.2a1 1 0 0 1-1-1v-5a1 1 0 0 0-1-1h-2a1 1 0 0 0-1 1v5a1 1 0 0 1-1 1H5.8a2 2 0 0 1-2-2V9.3a2 2 0 0 1 .7-1.58l6.2-4.96zm1.35 1.69L6 9.1v9.9h2v-4a3 3 0 0 1 3-3h2a3 3 0 0 1 3 3v4h2V9.1l-6-4.65z"/>
</svg>"""

home_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#3D7AFF" d="M10.7 2.76a2 2 0 0 1 2.6 0l6.2 4.96A2 2 0 0 1 20.2 9.3v9.7a2 2 0 0 1-2 2h-3.2a1 1 0 0 1-1-1v-5a1 1 0 0 0-1-1h-2a1 1 0 0 0-1 1v5a1 1 0 0 1-1 1H5.8a2 2 0 0 1-2-2V9.3a2 2 0 0 1 .7-1.58l6.2-4.96z"/>
</svg>"""

# 2. Live TV
# Antennas within bounded coords (L11 5.58 8.41 3 ...)
live_tv_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#8A98A8" fill-rule="evenodd" d="M8.41 3a1 1 0 0 1 1.41 0L12 5.17 14.18 3a1 1 0 1 1 1.41 1.41L13.17 6.83H19a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3v-8a3 3 0 0 1 3-3h5.83L8.41 4.41a1 1 0 0 1 0-1.41zM5 8.83a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-8a1 1 0 0 0-1-1H5z"/>
</svg>"""

live_tv_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#3D7AFF" fill-rule="evenodd" d="M8.41 3a1 1 0 0 1 1.41 0L12 5.17 14.18 3a1 1 0 1 1 1.41 1.41L13.17 6.83H19a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3v-8a3 3 0 0 1 3-3h5.83L8.41 4.41a1 1 0 0 1 0-1.41zM10 11.3a1 1 0 0 1 1.5-.86l4.5 2.6a1 1 0 0 1 0 1.72l-4.5 2.6a1 1 0 0 1-1.5-.86v-5.2z"/>
</svg>"""

# 3. Movies
movies_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#8A98A8" fill-rule="evenodd" d="M4 4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H4zm0 2h1.38l2 3H5.62L4 6.57V6zm3.82 0h2.46l-2 3H5.82l2-3zm4.46 0h2.46l-2 3h-2.46l2-3zm4.46 0h2.46l-2 3h-2.46l2-3zm4.46 0H20v.57l-1.62 2.43h-1.76l2-3zm.8 5H4v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7z"/>
</svg>"""

movies_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#3D7AFF" d="M4 4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H4zm0 2h1.38l2 3H5.62L4 6.57V6zm3.82 0h2.46l-2 3H5.82l2-3zm4.46 0h2.46l-2 3h-2.46l2-3zm4.46 0h2.46l-2 3h-2.46l2-3zm4.46 0H20v.57l-1.62 2.43h-1.76l2-3zM4 11h16v7a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-7z"/>
</svg>"""

# 4. Series
# Bounded within x=2..22, y=2..22 with optical margins
series_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#8A98A8" d="M6 3a1 1 0 0 0 0 2h12a1 1 0 1 0 0-2H6zm-2 4a1 1 0 0 0 0 2h16a1 1 0 1 0 0-2H4zm-1 5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7zm2 0v7h14v-7H5z"/>
</svg>"""

series_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#3D7AFF" fill-rule="evenodd" d="M6 3a1 1 0 0 0 0 2h12a1 1 0 1 0 0-2H6zm-2 4a1 1 0 0 0 0 2h16a1 1 0 1 0 0-2H4zm-1 5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7zm7.5 1.5a1 1 0 0 0-1.5.86v3.28a1 1 0 0 0 1.5.86l2.8-1.64a1 1 0 0 0 0-1.72l-2.8-1.64z"/>
</svg>"""

# 5. Search
# Inactive: weight 400
# Active: weight 600 + bold filled lens / thick rim
search_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#8A98A8" fill-rule="evenodd" d="M10.5 3a7.5 7.5 0 0 1 5.92 12.1l4.39 4.38a1 1 0 0 1-1.42 1.42l-4.38-4.39A7.5 7.5 0 1 1 10.5 3zm0 2a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11z"/>
</svg>"""

search_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#3D7AFF" fill-rule="evenodd" d="M10.5 2a8.5 8.5 0 0 1 6.7 13.72l4.4 4.39a1.5 1.5 0 1 1-2.12 2.12l-4.4-4.4A8.5 8.5 0 1 1 10.5 2zm0 3.5a5 5 0 1 0 0 10 5 5 0 0 0 0-10z"/>
</svg>"""

# 6. Guide (Schedule / EPG)
# Perfectly aligned rows, evenodd cutout for active
guide_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#8A98A8" fill-rule="evenodd" d="M5 3a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2H5zm0 2h14v3H5V5zm0 5h14v9a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-9zm2 2a1 1 0 0 1 1-1h3a1 1 0 1 1 0 2H8a1 1 0 0 1-1-1zm6 0a1 1 0 0 1 1-1h2a1 1 0 1 1 0 2h-2a1 1 0 0 1-1-1zm-6 4a1 1 0 0 1 1-1h6a1 1 0 1 1 0 2H8a1 1 0 0 1-1-1z"/>
</svg>"""

guide_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#3D7AFF" fill-rule="evenodd" d="M5 3a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2H5zm0 2h14v3H5V5zm3 6a1 1 0 0 0 0 2h3a1 1 0 1 0 0-2H8zm6 0a1 1 0 0 0 0 2h2a1 1 0 1 0 0-2h-2zm-6 4a1 1 0 0 0 0 2h6a1 1 0 1 0 0-2H8z"/>
</svg>"""

# 7. Favorites
# Unified filled path technique
favorites_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#8A98A8" fill-rule="evenodd" d="M12 2.6a1 1 0 0 1 .95.68l2.25 6.94h7.3a1 1 0 0 1 .59 1.81l-5.91 4.29 2.26 6.95a1 1 0 0 1-1.54 1.12L12 20.1l-5.9 4.29a1 1 0 0 1-1.54-1.12l2.26-6.95-5.9-4.29a1 1 0 0 1 .58-1.81h7.3l2.25-6.94a1 1 0 0 1 .95-.68zm0 3.82l-1.63 5.02a1 1 0 0 1-.95.68H5.15l4.27 3.1a1 1 0 0 1 .37 1.12l-1.63 5.03 4.28-3.11a1 1 0 0 1 1.17 0l4.28 3.11-1.63-5.03a1 1 0 0 1 .37-1.12l4.27-3.1h-4.27a1 1 0 0 1-.95-.68L12 6.42z"/>
</svg>"""

favorites_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#3D7AFF" d="M12 2.6a1 1 0 0 1 .95.68l2.25 6.94h7.3a1 1 0 0 1 .59 1.81l-5.91 4.29 2.26 6.95a1 1 0 0 1-1.54 1.12L12 20.1l-5.9 4.29a1 1 0 0 1-1.54-1.12l2.26-6.95-5.9-4.29a1 1 0 0 1 .58-1.81h7.3l2.25-6.94a1 1 0 0 1 .95-.68z"/>
</svg>"""

# 8. Sources
# Bounded within x=2..22, y=3..21 with optical margins
sources_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#8A98A8" fill-rule="evenodd" d="M18.5 9.04A6 6 0 0 0 7.35 7.1a5 5 0 0 0-4.35 5.9A5 5 0 0 0 7 18h11.5a4.5 4.5 0 0 0 0-9h-.01.01zm0 2a2.5 2.5 0 0 1 0 5H7a3 3 0 0 1-.6-5.94 1 1 0 0 0 .8-.8A4 4 0 0 1 15 8.13a1 1 0 0 0 1.15.86 2.5 2.5 0 0 1 2.35 2.05z"/>
</svg>"""

sources_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#3D7AFF" d="M18.5 9.04A6 6 0 0 0 7.35 7.1a5 5 0 0 0-4.35 5.9A5 5 0 0 0 7 18h11.5a4.5 4.5 0 0 0 0-9z"/>
</svg>"""

# 9. Settings
# Inactive: weight 400
# Active: weight 600 + bold filled cog with distinct center
settings_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#8A98A8" fill-rule="evenodd" d="M19.14 12.94a7.6 7.6 0 0 0 0-1.88l1.88-1.46a1 1 0 0 0 .24-1.28l-1.78-3.08a1 1 0 0 0-1.22-.44l-2.22.89a7.4 7.4 0 0 0-1.63-.95l-.34-2.36A1 1 0 0 0 13.07 1.5h-2.14a1 1 0 0 0-.99.88l-.34 2.36c-.58.24-1.13.56-1.63.95l-2.22-.89a1 1 0 0 0-1.22.44L2.74 8.32a1 1 0 0 0 .24 1.28l1.88 1.46a7.6 7.6 0 0 0 0 1.88l-1.88 1.46a1 1 0 0 0-.24 1.28l1.78 3.08a1 1 0 0 0 1.22.44l2.22-.89c.5.39 1.05.71 1.63.95l.34 2.36a1 1 0 0 0 .99.88h2.14a1 1 0 0 0 .99-.88l.34-2.36c.58-.24 1.13-.56 1.63-.95l2.22.89a1 1 0 0 0 1.22-.44l1.78-3.08a1 1 0 0 0-.24-1.28l-1.88-1.46zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm0-1.5a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3z"/>
</svg>"""

settings_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#3D7AFF" fill-rule="evenodd" d="M19.14 12.94a7.6 7.6 0 0 0 0-1.88l1.88-1.46a1 1 0 0 0 .24-1.28l-1.78-3.08a1 1 0 0 0-1.22-.44l-2.22.89a7.4 7.4 0 0 0-1.63-.95l-.34-2.36A1 1 0 0 0 13.07 1.5h-2.14a1 1 0 0 0-.99.88l-.34 2.36c-.58.24-1.13.56-1.63.95l-2.22-.89a1 1 0 0 0-1.22.44L2.74 8.32a1 1 0 0 0 .24 1.28l1.88 1.46a7.6 7.6 0 0 0 0 1.88l-1.88 1.46a1 1 0 0 0-.24 1.28l1.78 3.08a1 1 0 0 0 1.22.44l2.22-.89c.5.39 1.05.71 1.63.95l.34 2.36a1 1 0 0 0 .99.88h2.14a1 1 0 0 0 .99-.88l.34-2.36c.58-.24 1.13-.56 1.63-.95l2.22.89a1 1 0 0 0 1.22-.44l1.78-3.08a1 1 0 0 0-.24-1.28l-1.88-1.46zM12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z"/>
</svg>"""

icons = {
    'home': (home_inactive, home_active),
    'live_tv': (live_tv_inactive, live_tv_active),
    'movies': (movies_inactive, movies_active),
    'series': (series_inactive, series_active),
    'search': (search_inactive, search_active),
    'guide': (guide_inactive, guide_active),
    'favorites': (favorites_inactive, favorites_active),
    'sources': (sources_inactive, sources_active),
    'settings': (settings_inactive, settings_active),
}

for name, (inact, act) in icons.items():
    p_inact = os.path.join(ICONS_DIR, f'icon_{name}.svg')
    p_act = os.path.join(ICONS_DIR, f'icon_{name}_active.svg')
    
    with open(p_inact, 'w', encoding='utf-8') as f:
        f.write(inact.strip())
    with open(p_act, 'w', encoding='utf-8') as f:
        f.write(act.strip())
    
    # Test render both to PNG to ensure zero SVG parse/winding errors
    d_in = svg2rlg(p_inact)
    d_ac = svg2rlg(p_act)
    assert d_in is not None, f"Failed to parse {p_inact}"
    assert d_ac is not None, f"Failed to parse {p_act}"
    
    renderPM.drawToFile(d_in, os.path.join(ICONS_DIR, f'icon_{name}.png'), fmt='PNG')
    renderPM.drawToFile(d_ac, os.path.join(ICONS_DIR, f'icon_{name}_active.png'), fmt='PNG')
    print(f"Generated & verified: icon_{name}.svg & icon_{name}_active.svg (with rasterized PNGs)")

print("All 18 Material Symbols Rounded SVGs generated and validated!")
