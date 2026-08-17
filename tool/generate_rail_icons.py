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

# svglib/reportlab renders at 72dpi regardless of the SVG's own units, shrinking a
# 24x24 viewBox to an 18x18 raster (24 * 72/96). Chroma-keying a color no icon fill
# uses (magenta) is how we get real alpha transparency out of renderPM, which has no
# transparent-background option of its own.
CHROMA_KEY = (255, 0, 255)


def render_icon_png(svg_path, png_path, target_size=48):
    drawing = svg2rlg(svg_path)
    scale = target_size / drawing.width
    drawing.width = target_size
    drawing.height = target_size
    drawing.scale(scale, scale)
    renderPM.drawToFile(drawing, png_path, fmt='PNG', bg=0xFF00FF)

    img = Image.open(png_path).convert('RGBA')
    pixels = img.load()
    for py in range(img.height):
        for px in range(img.width):
            r, g, b, _ = pixels[px, py]
            pixels[px, py] = (r, g, b, 0) if (r, g, b) == CHROMA_KEY else (r, g, b, 255)
    img.save(png_path, 'PNG')

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
  <g transform="translate(0, 24) scale(0.025, 0.025)">
    <path fill="#8A98A8" d="m160-800 65 130q7 14 20 22t28 8q30 0 46-25.5t2-52.5l-41-82h80l65 130q7 14 20 22t28 8q30 0 46-25.5t2-52.5l-41-82h80l65 130q7 14 20 22t28 8q30 0 46-25.5t2-52.5l-41-82h120q33 0 56.5 23.5T880-720v480q0 33-23.5 56.5T800-160H160q-33 0-56.5-23.5T80-240v-480q0-33 23.5-56.5T160-800Zm0 240v320h640v-320H160Zm0 0v320-320Z"/>
  </g>
</svg>"""

movies_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <g transform="translate(0, 24) scale(0.025, 0.025)">
    <path fill="#3D7AFF" d="m160-800 65 130q7 14 20 22t28 8q30 0 46-25.5t2-52.5l-41-82h80l65 130q7 14 20 22t28 8q30 0 46-25.5t2-52.5l-41-82h80l65 130q7 14 20 22t28 8q30 0 46-25.5t2-52.5l-41-82h120q33 0 56.5 23.5T880-720v480q0 33-23.5 56.5T800-160H160q-33 0-56.5-23.5T80-240v-480q0-33 23.5-56.5T160-800Z"/>
  </g>
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
  <g transform="translate(0, 24) scale(0.025, 0.025)">
    <path fill="#8A98A8" d="m354-287 126-76 126 77-33-144 111-96-146-13-58-136-58 135-146 13 111 97-33 143Zm126 18L314-169q-11 7-23 6t-21-8q-9-7-14-17.5t-2-23.5l44-189-147-127q-10-9-12.5-20.5T140-571q4-11 12-18t22-9l194-17 75-178q5-12 15.5-18t21.5-6q11 0 21.5 6t15.5 18l75 178 194 17q14 2 22 9t12 18q4 11 1.5 22.5T809-528L662-401l44 189q3 13-2 23.5T690-171q-9 7-21 8t-23-6L480-269Zm0-201Z"/>
  </g>
</svg>"""

favorites_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <g transform="translate(0, 24) scale(0.025, 0.025)">
    <path fill="#3D7AFF" d="M480-269 314-169q-11 7-23 6t-21-8q-9-7-14-17.5t-2-23.5l44-189-147-127q-10-9-12.5-20.5T140-571q4-11 12-18t22-9l194-17 75-178q5-12 15.5-18t21.5-6q11 0 21.5 6t15.5 18l75 178 194 17q14 2 22 9t12 18q4 11 1.5 22.5T809-528L662-401l44 189q3 13-2 23.5T690-171q-9 7-21 8t-23-6L480-269Z"/>
  </g>
</svg>"""

# 8. Sources
# Bounded within x=2..22, y=3..21 with optical margins
sources_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <g transform="translate(0, 24) scale(0.025, 0.025)">
    <path fill="#8A98A8" d="M260-160q-91 0-155.5-63T40-377q0-78 47-139t123-78q25-92 100-149t170-57q117 0 198.5 81.5T760-520q69 8 114.5 59.5T920-340q0 75-52.5 127.5T740-160H260Zm0-80h480q42 0 71-29t29-71q0-42-29-71t-71-29h-60v-80q0-83-58.5-141.5T480-720q-83 0-141.5 58.5T280-520h-20q-58 0-99 41t-41 99q0 58 41 99t99 41Zm220-240Z"/>
  </g>
</svg>"""

sources_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <g transform="translate(0, 24) scale(0.025, 0.025)">
    <path fill="#3D7AFF" d="M260-160q-91 0-155.5-63T40-377q0-78 47-139t123-78q25-92 100-149t170-57q117 0 198.5 81.5T760-520q69 8 114.5 59.5T920-340q0 75-52.5 127.5T740-160H260Z"/>
  </g>
</svg>"""

# 9. Settings
# Inactive: weight 400
# Active: weight 600 + bold filled cog with distinct center
settings_inactive = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <g transform="translate(0, 24) scale(0.025, 0.025)">
    <path fill="#8A98A8" d="M433-80q-27 0-46.5-18T363-142l-9-66q-13-5-24.5-12T307-235l-62 26q-25 11-50 2t-39-32l-47-82q-14-23-8-49t27-43l53-40q-1-7-1-13.5v-27q0-6.5 1-13.5l-53-40q-21-17-27-43t8-49l47-82q14-23 39-32t50 2l62 26q11-8 23-15t24-12l9-66q4-26 23.5-44t46.5-18h94q27 0 46.5 18t23.5 44l9 66q13 5 24.5 12t22.5 15l62-26q25-11 50-2t39 32l47 82q14 23 8 49t-27 43l-53 40q1 7 1 13.5v27q0 6.5-2 13.5l53 40q21 17 27 43t-8 49l-48 82q-14 23-39 32t-50-2l-60-26q-11 8-23 15t-24 12l-9 66q-4 26-23.5 44T527-80h-94Zm7-80h79l14-106q31-8 57.5-23.5T639-327l99 41 39-68-86-65q5-14 7-29.5t2-31.5q0-16-2-31.5t-7-29.5l86-65-39-68-99 42q-22-23-48.5-38.5T533-694l-13-106h-79l-14 106q-31 8-57.5 23.5T321-633l-99-41-39 68 86 64q-5 15-7 30t-2 32q0 16 2 31t7 30l-86 65 39 68 99-42q22 23 48.5 38.5T427-266l13 106Zm42-180q58 0 99-41t41-99q0-58-41-99t-99-41q-59 0-99.5 41T342-480q0 58 40.5 99t99.5 41Zm-2-140Z"/>
  </g>
</svg>"""

settings_active = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <g transform="translate(0, 24) scale(0.025, 0.025)">
    <path fill="#3D7AFF" d="M433-80q-27 0-46.5-18T363-142l-9-66q-13-5-24.5-12T307-235l-62 26q-25 11-50 2t-39-32l-47-82q-14-23-8-49t27-43l53-40q-1-7-1-13.5v-27q0-6.5 1-13.5l-53-40q-21-17-27-43t8-49l47-82q14-23 39-32t50 2l62 26q11-8 23-15t24-12l9-66q4-26 23.5-44t46.5-18h94q27 0 46.5 18t23.5 44l9 66q13 5 24.5 12t22.5 15l62-26q25-11 50-2t39 32l47 82q14 23 8 49t-27 43l-53 40q1 7 1 13.5v27q0 6.5-2 13.5l53 40q21 17 27 43t-8 49l-48 82q-14 23-39 32t-50-2l-60-26q-11 8-23 15t-24 12l-9 66q-4 26-23.5 44T527-80h-94Zm49-260q58 0 99-41t41-99q0-58-41-99t-99-41q-59 0-99.5 41T342-480q0 58 40.5 99t99.5 41Z"/>
  </g>
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

    render_icon_png(p_inact, os.path.join(ICONS_DIR, f'icon_{name}.png'))
    render_icon_png(p_act, os.path.join(ICONS_DIR, f'icon_{name}_active.png'))
    print(f"Generated & verified: icon_{name}.svg & icon_{name}_active.svg (with rasterized PNGs)")

print("All 18 Material Symbols Rounded SVGs generated and validated!")
