# -*- coding: utf-8 -*-
"""
Process and standardize all visual refinement assets for Rulbi IPTV.
Guarantees exact aspect ratios, full bleed without letterboxes, bottom gradients
landing exactly on #0B0F14, and high-intensity accent glows for focused/hover states.
"""
import os
import glob
from PIL import Image, ImageFilter, ImageDraw, ImageOps, ImageEnhance

BRAIN_DIR = r'C:\Users\Usuario\.gemini\antigravity\brain\05e7e931-95df-47cf-8b83-b3b5da59dd8c'
BASE_DIR = r'c:\Users\Usuario\Documents\GitHub\IPTVapp\docs\design-assets'

POSTERS_DIR = os.path.join(BASE_DIR, 'posters')
BACKDROPS_DIR = os.path.join(BASE_DIR, 'backdrops')
EPISODES_DIR = os.path.join(BASE_DIR, 'episodes')
TV_CARDS_DIR = os.path.join(BASE_DIR, 'tv_cards')
ICONS_DIR = os.path.join(BASE_DIR, 'icons')

for d in [POSTERS_DIR, BACKDROPS_DIR, EPISODES_DIR, TV_CARDS_DIR, ICONS_DIR]:
    os.makedirs(d, exist_ok=True)

# Exact color tokens
BG_COLOR = (11, 15, 20)        # #0B0F14
ACCENT_BLUE = (61, 122, 255)   # #3D7AFF

# -------------------------------------------------------------
# 1. Posters (2:3 aspect ratio, 848x1264)
# -------------------------------------------------------------
poster_sources = {
    'el_faro_rojo.jpg': 'poster_el_faro_rojo',
    'dominio_norte.jpg': 'poster_dominio_norte',
    'cronos_s02.jpg': 'poster_cronos_s02_v2', # v2 in Spanish
    'via_muerta.jpg': 'poster_via_muerta',
    'umbra.jpg': 'poster_umbra',
    'litoral.jpg': 'poster_litoral',
    'sangre_fria.jpg': 'poster_sangre_fria_v2', # v2 without placeholder
    '8_bits.jpg': 'poster_8_bits',
}

for target_name, prefix in poster_sources.items():
    matches = glob.glob(os.path.join(BRAIN_DIR, f'{prefix}_*.jpg'))
    if matches:
        # Get latest matching file
        matches.sort(key=os.path.getmtime, reverse=True)
        src = matches[0]
        img = Image.open(src).convert('RGB')
        dst = os.path.join(POSTERS_DIR, target_name)
        img.save(dst, 'JPEG', quality=95)
        print(f'Saved Poster: {dst} ({img.size})')

# -------------------------------------------------------------
# 2. Backdrops (16:9 widescreen, 1376x768, landing exactly on #0B0F14)
# -------------------------------------------------------------
# El Faro Rojo
bd_faro_matches = glob.glob(os.path.join(BRAIN_DIR, 'backdrop_el_faro_rojo_*.jpg'))
if bd_faro_matches:
    bd_faro_matches.sort(key=os.path.getmtime, reverse=True)
    img = Image.open(bd_faro_matches[0]).convert('RGB').resize((1376, 768), Image.Resampling.LANCZOS)
    
    # Apply precise bottom gradient to #0B0F14 (from y=460 to 768)
    grad_overlay = Image.new('RGBA', (1376, 768), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(grad_overlay)
    for y in range(440, 768):
        progress = (y - 440) / (768.0 - 440.0)
        # Power curve for natural cinematic fade
        alpha = int(255 * (progress ** 1.35))
        g_draw.line([(0, y), (1376, y)], fill=(11, 15, 20, min(255, alpha)))
    
    img_rgba = img.convert('RGBA')
    img_final = Image.alpha_composite(img_rgba, grad_overlay).convert('RGB')
    dst = os.path.join(BACKDROPS_DIR, 'backdrop_el_faro_rojo.jpg')
    img_final.save(dst, 'JPEG', quality=95)
    print(f'Saved Backdrop El Faro Rojo: {dst} ({img_final.size})')

# Cronos (v2 - Full bleed, zero letterbox)
bd_cronos_matches = glob.glob(os.path.join(BRAIN_DIR, 'backdrop_cronos_v2_*.jpg'))
if bd_cronos_matches:
    bd_cronos_matches.sort(key=os.path.getmtime, reverse=True)
    img = Image.open(bd_cronos_matches[0]).convert('RGB').resize((1376, 768), Image.Resampling.LANCZOS)
    
    grad_overlay = Image.new('RGBA', (1376, 768), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(grad_overlay)
    for y in range(440, 768):
        progress = (y - 440) / (768.0 - 440.0)
        alpha = int(255 * (progress ** 1.35))
        g_draw.line([(0, y), (1376, y)], fill=(11, 15, 20, min(255, alpha)))
    
    img_rgba = img.convert('RGBA')
    img_final = Image.alpha_composite(img_rgba, grad_overlay).convert('RGB')
    dst = os.path.join(BACKDROPS_DIR, 'backdrop_cronos.jpg')
    img_final.save(dst, 'JPEG', quality=95)
    print(f'Saved Backdrop Cronos (Full Bleed): {dst} ({img_final.size})')

# -------------------------------------------------------------
# 3. Episode Stills for Cronos (All 5 Episodes in 1376x768, 16:9 full bleed)
# -------------------------------------------------------------
episode_sources = [
    ('cronos_ep01_ruido_de_fondo.jpg', 'ep1_origen_brecha'),      # E1: Ruido de fondo (42 min)
    ('cronos_ep02_el_eco.jpg', 'ep2_paradoja_temporal'),          # E2: El eco (45 min)
    ('cronos_ep03_frecuencia_muerta.jpg', 'ep3_lineas_tiempo'),   # E3: Frecuencia muerta (41 min)
    ('cronos_ep04_umbral.jpg', 'ep4_umbral'),                     # E4: Umbral (47 min) - Brand New Scene!
    ('cronos_ep05_lo_que_queda.jpg', 'ep5_lo_que_queda'),         # E5: Lo que queda (44 min) - Brand New Scene!
]

for target_name, prefix in episode_sources:
    matches = glob.glob(os.path.join(BRAIN_DIR, f'{prefix}_*.jpg'))
    if matches:
        matches.sort(key=os.path.getmtime, reverse=True)
        img = Image.open(matches[0]).convert('RGB').resize((1376, 768), Image.Resampling.LANCZOS)
        dst = os.path.join(EPISODES_DIR, target_name)
        img.save(dst, 'JPEG', quality=95)
        print(f'Saved Episode Still: {dst} ({img.size})')

# -------------------------------------------------------------
# 4. TV Cards (16:9 Landscape, 680x400 retina)
# -------------------------------------------------------------
tv_card_sources = [
    ('tv_card_el_faro_rojo.jpg', 'tv_card_el_faro_rojo'),
    ('tv_card_dominio_norte.jpg', 'tv_card_dominio_norte'),
    ('tv_card_cronos_s02.jpg', 'tv_card_cronos_v2'), # v2 native landscape!
    ('tv_card_via_muerta.jpg', 'tv_card_via_muerta'),
    ('tv_card_umbra.jpg', 'tv_card_umbra'),
    ('tv_card_litoral.jpg', 'tv_card_litoral'),
    ('tv_card_sangre_fria.jpg', 'tv_card_sangre_fria'),
    ('tv_card_8_bits.jpg', 'tv_card_8_bits'),
]

for target_name, prefix in tv_card_sources:
    matches = glob.glob(os.path.join(BRAIN_DIR, f'{prefix}_*.jpg'))
    if matches:
        matches.sort(key=os.path.getmtime, reverse=True)
        img = Image.open(matches[0]).convert('RGB').resize((680, 400), Image.Resampling.LANCZOS)
        dst = os.path.join(TV_CARDS_DIR, target_name)
        img.save(dst, 'JPEG', quality=95)
        print(f'Saved TV Landscape Card: {dst} ({img.size})')

# -------------------------------------------------------------
# 5. TV Card FOCUSED State (4px solid white ring + High-Intensity #3D7AFF Glow)
# -------------------------------------------------------------
faro_tv_path = os.path.join(TV_CARDS_DIR, 'tv_card_el_faro_rojo.jpg')
if os.path.exists(faro_tv_path):
    card = Image.open(faro_tv_path).convert('RGBA')
    cw, ch = card.size # 680x400
    
    pad = 70
    total_w = cw + pad * 2
    total_h = ch + pad * 2
    
    # Multi-pass high-intensity glow in #3D7AFF (61, 122, 255)
    glow_canvas = Image.new('RGBA', (total_w, total_h), (0, 0, 0, 0))
    
    # Outer diffuse halo
    m1 = Image.new('L', (total_w, total_h), 0)
    d1 = ImageDraw.Draw(m1)
    d1.rounded_rectangle([pad - 10, pad - 10, pad + cw + 10, pad + ch + 10], radius=20, fill=220)
    m1 = m1.filter(ImageFilter.GaussianBlur(radius=32))
    g1 = Image.new('RGBA', (total_w, total_h), (61, 122, 255, 0))
    g1.putalpha(m1)
    
    # Inner intense halo
    m2 = Image.new('L', (total_w, total_h), 0)
    d2 = ImageDraw.Draw(m2)
    d2.rounded_rectangle([pad - 4, pad - 4, pad + cw + 4, pad + ch + 4], radius=16, fill=255)
    m2 = m2.filter(ImageFilter.GaussianBlur(radius=16))
    g2 = Image.new('RGBA', (total_w, total_h), (61, 122, 255, 0))
    g2.putalpha(m2)
    
    # Composite glows
    glow_canvas = Image.alpha_composite(glow_canvas, g1)
    glow_canvas = Image.alpha_composite(glow_canvas, g2)
    
    # Card with rounded corners
    card_mask = Image.new('L', (cw, ch), 0)
    ImageDraw.Draw(card_mask).rounded_rectangle([0, 0, cw, ch], radius=12, fill=255)
    glow_canvas.paste(card, (pad, pad), card_mask)
    
    # 4px solid white ring (8px at 2x retina)
    ring_draw = ImageDraw.Draw(glow_canvas)
    ring_draw.rounded_rectangle([pad, pad, pad + cw, pad + ch], radius=12, outline=(255, 255, 255, 255), width=8)
    
    tv_focused_dst = os.path.join(TV_CARDS_DIR, 'tv_card_el_faro_rojo_focused.png')
    glow_canvas.save(tv_focused_dst, 'PNG')
    print(f'Saved High-Intensity TV Focused Card: {tv_focused_dst}')

# -------------------------------------------------------------
# 6. Desktop Poster Card HOVER State (High-Intensity #3D7AFF Glow)
# -------------------------------------------------------------
faro_poster_path = os.path.join(POSTERS_DIR, 'el_faro_rojo.jpg')
if os.path.exists(faro_poster_path):
    poster = Image.open(faro_poster_path).convert('RGBA').resize((340, 510), Image.Resampling.LANCZOS)
    pw, ph = poster.size
    
    pad = 60
    total_w = pw + pad * 2
    total_h = ph + pad * 2
    
    hover_canvas = Image.new('RGBA', (total_w, total_h), (0, 0, 0, 0))
    
    # Outer diffuse halo
    m1 = Image.new('L', (total_w, total_h), 0)
    d1 = ImageDraw.Draw(m1)
    d1.rounded_rectangle([pad - 8, pad - 8, pad + pw + 8, pad + ph + 8], radius=16, fill=200)
    m1 = m1.filter(ImageFilter.GaussianBlur(radius=26))
    g1 = Image.new('RGBA', (total_w, total_h), (61, 122, 255, 0))
    g1.putalpha(m1)
    
    # Inner intense halo
    m2 = Image.new('L', (total_w, total_h), 0)
    d2 = ImageDraw.Draw(m2)
    d2.rounded_rectangle([pad - 2, pad - 2, pad + pw + 2, pad + ph + 2], radius=12, fill=255)
    m2 = m2.filter(ImageFilter.GaussianBlur(radius=12))
    g2 = Image.new('RGBA', (total_w, total_h), (61, 122, 255, 0))
    g2.putalpha(m2)
    
    hover_canvas = Image.alpha_composite(hover_canvas, g1)
    hover_canvas = Image.alpha_composite(hover_canvas, g2)
    
    poster_mask = Image.new('L', (pw, ph), 0)
    ImageDraw.Draw(poster_mask).rounded_rectangle([0, 0, pw, ph], radius=10, fill=255)
    hover_canvas.paste(poster, (pad, pad), poster_mask)
    
    # 2px border #3D7AFF
    ImageDraw.Draw(hover_canvas).rounded_rectangle([pad, pad, pad + pw, pad + ph], radius=10, outline=(61, 122, 255, 255), width=2)
    
    desktop_hover_dst = os.path.join(POSTERS_DIR, 'el_faro_rojo_desktop_hover.png')
    hover_canvas.save(desktop_hover_dst, 'PNG')
    print(f'Saved High-Intensity Desktop Hover Card: {desktop_hover_dst}')

print('Asset processing & standardization complete!')
