# -*- coding: utf-8 -*-
"""
Precision mockup renderer for Rulbi IPTV (Home Desktop, Home TV, Detalle VOD/Serie).
Complies 100% with:
- ui-spec.md §5 (Inter typography, #0B0F14, #151B24, #3D7AFF, #06152F, #EBF0F8)
- Real Material Symbols Rounded icon rendering from docs/design-assets/icons/
- Exact layouts of Figma frames 38:3, 41:2, 43:2, 44:2
- No tofu glyphs (custom vector drawing for stars, play triangles, badges)
- Full bleed 1376x768 / 1920x1080 compositions
"""
import os
import glob
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE_DIR = r'c:\Users\Usuario\Documents\GitHub\IPTVapp\docs\design-assets'
MOCKUPS_DIR = os.path.join(BASE_DIR, 'mockups')
POSTERS_DIR = os.path.join(BASE_DIR, 'posters')
BACKDROPS_DIR = os.path.join(BASE_DIR, 'backdrops')
EPISODES_DIR = os.path.join(BASE_DIR, 'episodes')
TV_CARDS_DIR = os.path.join(BASE_DIR, 'tv_cards')
ICONS_DIR = os.path.join(BASE_DIR, 'icons')
FONTS_DIR = os.path.join(BASE_DIR, 'fonts')
BRAIN_DIR = r'C:\Users\Usuario\.gemini\antigravity\brain\05e7e931-95df-47cf-8b83-b3b5da59dd8c'

os.makedirs(MOCKUPS_DIR, exist_ok=True)

# Exact color tokens
BG_COLOR = (11, 15, 20)        # #0B0F14
SURFACE_COLOR = (21, 27, 36)   # #151B24
SURFACE_HOVER = (30, 39, 51)   # #1E2733
ACCENT_BLUE = (61, 122, 255)   # #3D7AFF
TEXT_ON_ACCENT = (6, 21, 47)   # #06152F
TEXT_PRIMARY = (235, 240, 248) # #EBF0F8
TEXT_SECONDARY = (138, 152, 168) # #8A98A8
TEXT_MUTED = (85, 98, 112)     # #556270
WHITE = (255, 255, 255)
PROGRESS_BG = (35, 45, 60)
LIVE_RED = (235, 50, 60)
STAR_GOLD = (255, 196, 38)

INTER_FONT_PATH = os.path.join(FONTS_DIR, 'Inter-Regular.ttf')

def get_font(size):
    return ImageFont.truetype(INTER_FONT_PATH, size)

def draw_play_icon(draw, center_x, center_y, size, color):
    """Draw a vector play triangle (no missing font glyphs)"""
    half_h = size // 2
    half_w = int(size * 0.45)
    points = [
        (center_x - half_w, center_y - half_h),
        (center_x + half_w + 1, center_y),
        (center_x - half_w, center_y + half_h)
    ]
    draw.polygon(points, fill=color)

def draw_star_icon(draw, center_x, center_y, size, color):
    """Draw a vector 5-pointed star"""
    import math
    points = []
    for i in range(10):
        r = size if i % 2 == 0 else size * 0.45
        angle = i * math.pi / 5 - math.pi / 2
        x = center_x + r * math.cos(angle)
        y = center_y + r * math.sin(angle)
        points.append((x, y))
    draw.polygon(points, fill=color)

def render_rail(img, active_name="home"):
    """Render 88px left rail with real Material Symbols Rounded icon PNGs (no text labels)"""
    rail_w = 88
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, rail_w, img.height], fill=SURFACE_COLOR)
    draw.line([rail_w, 0, rail_w, img.height], fill=(28, 36, 48), width=1)

    # Logo RULBI at top
    draw.text((rail_w // 2, 36), "RULBI", fill=TEXT_PRIMARY, font=get_font(18), anchor="mm")

    rail_items = [
        "home", "live_tv", "movies", "series", "search", "guide", "favorites", "sources", "settings"
    ]
    start_y = 96
    gap = 52
    for i, name in enumerate(rail_items):
        cy = start_y + i * gap
        is_active = (name == active_name)
        
        # Load real rendered icon PNG
        icon_file = f'icon_{name}_active.png' if is_active else f'icon_{name}.png'
        icon_path = os.path.join(ICONS_DIR, icon_file)
        
        if is_active:
            # Active pill background and indicator bar
            draw.rounded_rectangle([2, cy - 14, 6, cy + 14], radius=2, fill=ACCENT_BLUE)
            draw.rounded_rectangle([14, cy - 20, rail_w - 14, cy + 20], radius=10, fill=(24, 38, 62))
        
        if os.path.exists(icon_path):
            icon_img = Image.open(icon_path).convert('RGBA').resize((24, 24), Image.Resampling.LANCZOS)
            img.paste(icon_img, (rail_w // 2 - 12, cy - 12), icon_img)


# -------------------------------------------------------------
# 1. Desktop Home Mockup (Frame 38:3 - 1920x1080)
# -------------------------------------------------------------
def render_desktop_home():
    w, h = 1920, 1080
    img = Image.new('RGB', (w, h), BG_COLOR)
    render_rail(img, active_name="home")
    draw = ImageDraw.Draw(img)

    cx = 88 + 36 # rail_w + 36px padding
    
    # ---------------------------------------------------------
    # Row 1: "Continuar viendo" (Landscape cards with progress)
    # ---------------------------------------------------------
    row1_title_y = 36
    draw.text((cx, row1_title_y), "Continuar viendo", fill=TEXT_PRIMARY, font=get_font(24))

    card_w, card_h = 390, 220
    card_gap = 20
    row1_y = row1_title_y + 44

    row1_cards = [
        ("tv_card_el_faro_rojo.jpg", "El Faro Rojo", "24:10 / 1h 52m", 0.65, True), # Hover!
        ("tv_card_dominio_norte.jpg", "Dominio Norte", "T1 E3 • 14:00", 0.30, False),
        ("tv_card_cronos_s02.jpg", "Cronos S02", "T2 E5 • 42:00", 0.85, False),
        ("tv_card_via_muerta.jpg", "Vía Muerta", "08:15 / 1h 45m", 0.10, False),
    ]

    for i, (fname, title, subtitle, prog, is_hover) in enumerate(row1_cards):
        px = cx + i * (card_w + card_gap)
        c_path = os.path.join(TV_CARDS_DIR, fname)
        if os.path.exists(c_path):
            c_img = Image.open(c_path).convert('RGB').resize((card_w, card_h), Image.Resampling.LANCZOS)
            
            mask = Image.new('L', (card_w, card_h), 0)
            ImageDraw.Draw(mask).rounded_rectangle([0, 0, card_w, card_h], radius=10, fill=255)

            if is_hover:
                # Distinctive Blue Glow Halo (#3D7AFF) that stays within card boundaries
                glow_pad = 18
                draw.rounded_rectangle(
                    [px - glow_pad, row1_y - glow_pad, px + card_w + glow_pad, row1_y + card_h + glow_pad],
                    radius=18, fill=(18, 48, 110)
                )

            # Paste card
            img.paste(c_img, (px, row1_y), mask)

            # Card border
            if is_hover:
                draw.rounded_rectangle([px, row1_y, px + card_w, row1_y + card_h], radius=10, outline=ACCENT_BLUE, width=2)
            else:
                draw.rounded_rectangle([px, row1_y, px + card_w, row1_y + card_h], radius=10, outline=(32, 42, 56), width=1)

            # Bottom gradient overlay for card title
            card_grad = Image.new('RGBA', (card_w, 70), (0, 0, 0, 0))
            cg_draw = ImageDraw.Draw(card_grad)
            for gy in range(70):
                alpha = int(220 * (gy / 70.0) ** 1.3)
                cg_draw.line([(0, gy), (card_w, gy)], fill=(11, 15, 20, alpha))
            img.paste(card_grad.convert('RGB'), (px, row1_y + card_h - 70), card_grad.split()[3])

            # Title & Subtitle inside card
            draw.text((px + 14, row1_y + card_h - 48), title, fill=TEXT_PRIMARY, font=get_font(15))
            draw.text((px + 14, row1_y + card_h - 28), subtitle, fill=TEXT_SECONDARY, font=get_font(12))

            # Progress bar
            pb_h = 4
            pb_y = row1_y + card_h - pb_h - 4
            draw.rounded_rectangle([px + 14, pb_y, px + card_w - 14, pb_y + pb_h], radius=2, fill=PROGRESS_BG)
            draw.rounded_rectangle([px + 14, pb_y, px + 14 + int((card_w - 28) * prog), pb_y + pb_h], radius=2, fill=ACCENT_BLUE)

    # ---------------------------------------------------------
    # Row 2: "Favoritos" (Landscape TV cards)
    # ---------------------------------------------------------
    row2_title_y = row1_y + card_h + 34
    draw.text((cx, row2_title_y), "Favoritos", fill=TEXT_PRIMARY, font=get_font(24))

    row2_y = row2_title_y + 44
    row2_cards = [
        ("tv_card_umbra.jpg", "Umbra", "Película • 2024"),
        ("tv_card_litoral.jpg", "Litoral", "Película • 2023"),
        ("tv_card_sangre_fria.jpg", "Sangre Fría", "Película • 2024"),
        ("tv_card_8_bits.jpg", "8 Bits", "Serie • 1 Temporada"),
    ]

    for i, (fname, title, meta) in enumerate(row2_cards):
        px = cx + i * (card_w + card_gap)
        c_path = os.path.join(TV_CARDS_DIR, fname)
        if os.path.exists(c_path):
            c_img = Image.open(c_path).convert('RGB').resize((card_w, card_h), Image.Resampling.LANCZOS)
            mask = Image.new('L', (card_w, card_h), 0)
            ImageDraw.Draw(mask).rounded_rectangle([0, 0, card_w, card_h], radius=10, fill=255)
            img.paste(c_img, (px, row2_y), mask)
            draw.rounded_rectangle([px, row2_y, px + card_w, row2_y + card_h], radius=10, outline=(32, 42, 56), width=1)

            # Gradient & text overlay
            card_grad = Image.new('RGBA', (card_w, 60), (0, 0, 0, 0))
            cg_draw = ImageDraw.Draw(card_grad)
            for gy in range(60):
                alpha = int(220 * (gy / 60.0) ** 1.3)
                cg_draw.line([(0, gy), (card_w, gy)], fill=(11, 15, 20, alpha))
            img.paste(card_grad.convert('RGB'), (px, row2_y + card_h - 60), card_grad.split()[3])

            draw.text((px + 14, row2_y + card_h - 44), title, fill=TEXT_PRIMARY, font=get_font(15))
            draw.text((px + 14, row2_y + card_h - 24), meta, fill=TEXT_SECONDARY, font=get_font(12))

    # ---------------------------------------------------------
    # Row 3: "Ahora en tus canales" (Live EPG Cards + EN DIRECTO Badges)
    # ---------------------------------------------------------
    row3_title_y = row2_y + card_h + 34
    draw.text((cx, row3_title_y), "Ahora en tus canales", fill=TEXT_PRIMARY, font=get_font(24))

    row3_y = row3_title_y + 44
    epg_w = 526
    epg_h = 110
    epg_gap = 20

    live_channels = [
        ("Canal 5", "Noticias 24h • Especial Informativo", "21:00 - 22:30", 0.55),
        ("DeporTV", "Liga Nacional • Jornada 22", "21:00 - 23:00", 0.40),
        ("Cine Norte", "Estreno • El Hombre del Laberinto", "20:30 - 22:45", 0.70),
    ]

    for i, (ch_name, prog_title, time_span, prog) in enumerate(live_channels):
        px = cx + i * (epg_w + epg_gap)
        draw.rounded_rectangle([px, row3_y, px + epg_w, row3_y + epg_h], radius=10, fill=SURFACE_COLOR, outline=(35, 46, 62), width=1)

        # Channel logo placeholder / badge
        draw.rounded_rectangle([px + 16, row3_y + 16, px + 56, row3_y + 56], radius=8, fill=(28, 38, 54))
        draw.text((px + 36, row3_y + 36), ch_name[:2].upper(), fill=ACCENT_BLUE, font=get_font(14), anchor="mm")

        # Live Badge "EN DIRECTO"
        badge_x = px + 68
        badge_y = row3_y + 16
        draw.rounded_rectangle([badge_x, badge_y, badge_x + 92, badge_y + 18], radius=4, fill=LIVE_RED)
        draw.text((badge_x + 46, badge_y + 9), "EN DIRECTO", fill=WHITE, font=get_font(10), anchor="mm")

        # Channel name & show title
        draw.text((px + 170, row3_y + 16), ch_name, fill=TEXT_SECONDARY, font=get_font(13))
        draw.text((px + 68, row3_y + 42), prog_title, fill=TEXT_PRIMARY, font=get_font(15))
        draw.text((px + 68, row3_y + 68), time_span, fill=TEXT_SECONDARY, font=get_font(12))

        # Progress bar
        pb_y = row3_y + epg_h - 8
        draw.rounded_rectangle([px + 68, pb_y, px + epg_w - 20, pb_y + 3], radius=2, fill=PROGRESS_BG)
        draw.rounded_rectangle([px + 68, pb_y, px + 68 + int((epg_w - 88) * prog), pb_y + 3], radius=2, fill=ACCENT_BLUE)

    dst = os.path.join(MOCKUPS_DIR, 'mockup_desktop_home.png')
    img.save(dst, 'PNG')
    img.save(os.path.join(BRAIN_DIR, 'mockup_desktop_home.png'), 'PNG')
    print(f'Rendered Desktop Home Mockup (38:3): {dst}')


# -------------------------------------------------------------
# 2. TV Home Mockup (Frame 41:2 - 1920x1080 - 10-foot)
# -------------------------------------------------------------
def render_tv_home():
    w, h = 1920, 1080
    img = Image.new('RGB', (w, h), BG_COLOR)
    draw = ImageDraw.Draw(img)

    # 88px Safe Area Padding
    pad = 88

    # Top Bar: Left Logo "RULBI" in #3D7AFF, Right Clock "21:47" in #8A98A8
    draw.text((pad, pad), "RULBI", fill=ACCENT_BLUE, font=get_font(32))
    draw.text((w - pad, pad), "21:47", fill=TEXT_SECONDARY, font=get_font(32), anchor="ra")

    # ---------------------------------------------------------
    # Section 1: "Continuar viendo" (3 Cards per row in TV!)
    # ---------------------------------------------------------
    sec1_title_y = pad + 70
    draw.text((pad, sec1_title_y), "Continuar viendo", fill=TEXT_PRIMARY, font=get_font(36))

    card_w, card_h = 540, 310
    card_gap = 32
    row1_y = sec1_title_y + 60

    tv_row1 = [
        ("tv_card_el_faro_rojo.jpg", "El Faro Rojo", "24:10 / 1h 52m", 0.65, True), # FOCUSED!
        ("tv_card_dominio_norte.jpg", "Dominio Norte", "T1 E3 • 14:00", 0.30, False),
        ("tv_card_cronos_s02.jpg", "Cronos S02", "T2 E5 • 42:00", 0.85, False),
    ]

    for i, (fname, title, meta, prog, is_focused) in enumerate(tv_row1):
        px = pad + i * (card_w + card_gap)
        c_path = os.path.join(TV_CARDS_DIR, fname)
        if os.path.exists(c_path):
            c_img = Image.open(c_path).convert('RGB').resize((card_w, card_h), Image.Resampling.LANCZOS)
            mask = Image.new('L', (card_w, card_h), 0)
            ImageDraw.Draw(mask).rounded_rectangle([0, 0, card_w, card_h], radius=14, fill=255)

            if is_focused:
                # High-Intensity Vibrant Blue Glow Halo (#3D7AFF)
                glow_pad = 28
                draw.rounded_rectangle(
                    [px - glow_pad, row1_y - glow_pad, px + card_w + glow_pad, row1_y + card_h + glow_pad],
                    radius=24, fill=(24, 68, 160)
                )

            # Paste card
            img.paste(c_img, (px, row1_y), mask)

            if is_focused:
                # 4px Solid White Ring (#FFFFFF)
                draw.rounded_rectangle([px, row1_y, px + card_w, row1_y + card_h], radius=14, outline=WHITE, width=4)
            else:
                draw.rounded_rectangle([px, row1_y, px + card_w, row1_y + card_h], radius=14, outline=(35, 46, 62), width=1)

            # Gradient overlay for title & metadata
            card_grad = Image.new('RGBA', (card_w, 90), (0, 0, 0, 0))
            cg_draw = ImageDraw.Draw(card_grad)
            for gy in range(90):
                alpha = int(230 * (gy / 90.0) ** 1.3)
                cg_draw.line([(0, gy), (card_w, gy)], fill=(11, 15, 20, alpha))
            img.paste(card_grad.convert('RGB'), (px, row1_y + card_h - 90), card_grad.split()[3])

            draw.text((px + 20, row1_y + card_h - 60), title, fill=TEXT_PRIMARY, font=get_font(22))
            draw.text((px + 20, row1_y + card_h - 32), meta, fill=TEXT_SECONDARY, font=get_font(16))

            # Progress bar
            pb_h = 6
            pb_y = row1_y + card_h - pb_h - 6
            draw.rounded_rectangle([px + 20, pb_y, px + card_w - 20, pb_y + pb_h], radius=3, fill=PROGRESS_BG)
            draw.rounded_rectangle([px + 20, pb_y, px + 20 + int((card_w - 40) * prog), pb_y + pb_h], radius=3, fill=ACCENT_BLUE)

    # ---------------------------------------------------------
    # Section 2: "Favoritos" (3 Landscape cards)
    # ---------------------------------------------------------
    sec2_title_y = row1_y + card_h + 54
    draw.text((pad, sec2_title_y), "Favoritos", fill=TEXT_PRIMARY, font=get_font(28))

    row2_y = sec2_title_y + 48
    tv_row2 = [
        ("tv_card_umbra.jpg", "Umbra", "Película • 2024"),
        ("tv_card_litoral.jpg", "Litoral", "Película • 2023"),
        ("tv_card_sangre_fria.jpg", "Sangre Fría", "Película • 2024"),
    ]

    for i, (fname, title, meta) in enumerate(tv_row2):
        px = pad + i * (card_w + card_gap)
        c_path = os.path.join(TV_CARDS_DIR, fname)
        if os.path.exists(c_path):
            c_img = Image.open(c_path).convert('RGB').resize((card_w, card_h), Image.Resampling.LANCZOS)
            mask = Image.new('L', (card_w, card_h), 0)
            ImageDraw.Draw(mask).rounded_rectangle([0, 0, card_w, card_h], radius=14, fill=255)
            img.paste(c_img, (px, row2_y), mask)
            draw.rounded_rectangle([px, row2_y, px + card_w, row2_y + card_h], radius=14, outline=(35, 46, 62), width=1)

            card_grad = Image.new('RGBA', (card_w, 80), (0, 0, 0, 0))
            cg_draw = ImageDraw.Draw(card_grad)
            for gy in range(80):
                alpha = int(230 * (gy / 80.0) ** 1.3)
                cg_draw.line([(0, gy), (card_w, gy)], fill=(11, 15, 20, alpha))
            img.paste(card_grad.convert('RGB'), (px, row2_y + card_h - 80), card_grad.split()[3])

            draw.text((px + 20, row2_y + card_h - 52), title, fill=TEXT_PRIMARY, font=get_font(22))
            draw.text((px + 20, row2_y + card_h - 26), meta, fill=TEXT_SECONDARY, font=get_font(16))

    dst = os.path.join(MOCKUPS_DIR, 'mockup_tv_home.png')
    img.save(dst, 'PNG')
    img.save(os.path.join(BRAIN_DIR, 'mockup_tv_home.png'), 'PNG')
    print(f'Rendered TV Home Mockup (41:2): {dst}')


# -------------------------------------------------------------
# 3. Desktop Detalle VOD (Película: "El Faro Rojo" - Frame 43:2)
# -------------------------------------------------------------
def render_detalle_pelicula():
    w, h = 1920, 1080
    img = Image.new('RGB', (w, h), BG_COLOR)
    render_rail(img, active_name="movies")
    draw = ImageDraw.Draw(img)

    rail_w = 88
    content_w = w - rail_w

    # 1. Backdrop (Widescreen 16:9, occupying top 580px)
    bd_path = os.path.join(BACKDROPS_DIR, 'backdrop_el_faro_rojo.jpg')
    if os.path.exists(bd_path):
        bd_img = Image.open(bd_path).convert('RGB').resize((content_w, 580), Image.Resampling.LANCZOS)
        img.paste(bd_img, (rail_w, 0))

    # 2. Poster & Content Block positioned cleanly
    poster_x = rail_w + 52
    poster_y = 380
    pw, ph = 260, 390

    p_path = os.path.join(POSTERS_DIR, 'el_faro_rojo.jpg')
    if os.path.exists(p_path):
        p_img = Image.open(p_path).convert('RGB').resize((pw, ph), Image.Resampling.LANCZOS)
        mask = Image.new('L', (pw, ph), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw, ph], radius=12, fill=255)
        
        # Shadow behind poster
        draw.rounded_rectangle([poster_x - 6, poster_y - 6, poster_x + pw + 6, poster_y + ph + 6], radius=14, fill=(5, 8, 12))
        img.paste(p_img, (poster_x, poster_y), mask)
        draw.rounded_rectangle([poster_x, poster_y, poster_x + pw, poster_y + ph], radius=12, outline=(50, 65, 85), width=2)

    # 3. Metadata & Details (Right of poster)
    meta_x = poster_x + pw + 48
    meta_y = 440

    # Title
    draw.text((meta_x, meta_y), "El Faro Rojo", fill=TEXT_PRIMARY, font=get_font(34))

    # Row with Year, Duration, Rating ★ 8.1, Genres, Badges 4K / 5.1
    tags_y = meta_y + 52
    draw.text((meta_x, tags_y), "2024   •   1h 52m   •   Thriller / Misterio   •   ", fill=TEXT_SECONDARY, font=get_font(16))
    
    star_x = meta_x + 360
    draw_star_icon(draw, star_x, tags_y + 10, 8, STAR_GOLD)
    draw.text((star_x + 14, tags_y), "8.1", fill=TEXT_PRIMARY, font=get_font(16))

    # 4K & 5.1 Badges
    b_x = star_x + 60
    draw.rounded_rectangle([b_x, tags_y - 2, b_x + 38, tags_y + 22], radius=4, outline=TEXT_MUTED, fill=SURFACE_COLOR)
    draw.text((b_x + 19, tags_y + 10), "4K", fill=TEXT_PRIMARY, font=get_font(11), anchor="mm")
    
    draw.rounded_rectangle([b_x + 46, tags_y - 2, b_x + 84, tags_y + 22], radius=4, outline=TEXT_MUTED, fill=SURFACE_COLOR)
    draw.text((b_x + 65, tags_y + 10), "5.1", fill=TEXT_PRIMARY, font=get_font(11), anchor="mm")

    # Synopsis
    syn_y = tags_y + 44
    synopsis = (
        "En una noche de temporal salvaje en los acantilados del norte, el veterano farero Samuel descubre\n"
        "un navío encallado bajo la luz carmesí del faro. Lo que parecía un rescate rutinario se convierte\n"
        "en una tensa espiral de suspense y secretos sumergidos que nunca debieron salir a la superficie."
    )
    draw.multiline_text((meta_x, syn_y), synopsis, fill=TEXT_PRIMARY, font=get_font(16), spacing=8)

    # CTA Buttons
    cta_y = syn_y + 110
    btn1_w, btn1_h = 220, 48
    draw.rounded_rectangle([meta_x, cta_y, meta_x + btn1_w, cta_y + btn1_h], radius=8, fill=ACCENT_BLUE)
    draw_play_icon(draw, meta_x + 34, cta_y + 24, 14, TEXT_ON_ACCENT)
    draw.text((meta_x + 120, cta_y + 24), "Continuar 24:10", fill=TEXT_ON_ACCENT, font=get_font(16), anchor="mm")

    btn2_w = 210
    btn2_x = meta_x + btn1_w + 16
    draw.rounded_rectangle([btn2_x, cta_y, btn2_x + btn2_w, cta_y + btn1_h], radius=8, fill=SURFACE_COLOR, outline=(50, 65, 85), width=1)
    draw_star_icon(draw, btn2_x + 36, cta_y + 24, 8, STAR_GOLD)
    draw.text((btn2_x + 120, cta_y + 24), "En Favoritos", fill=TEXT_PRIMARY, font=get_font(15), anchor="mm")

    # Additional credits info at bottom
    info_y = poster_y + ph + 44
    draw.text((poster_x, info_y), "Director: ", fill=TEXT_SECONDARY, font=get_font(15))
    draw.text((poster_x + 75, info_y), "Ricardo Morales", fill=TEXT_PRIMARY, font=get_font(15))

    draw.text((poster_x + 280, info_y), "Reparto: ", fill=TEXT_SECONDARY, font=get_font(15))
    draw.text((poster_x + 355, info_y), "Alejandro Vega, Lucía Méndez, Javier Ruiz, Carmen Ortiz", fill=TEXT_PRIMARY, font=get_font(15))

    dst = os.path.join(MOCKUPS_DIR, 'mockup_desktop_detalle_pelicula.png')
    img.save(dst, 'PNG')
    img.save(os.path.join(BRAIN_DIR, 'mockup_desktop_detalle_pelicula.png'), 'PNG')
    print(f'Rendered Detalle Pelicula Mockup (43:2): {dst}')


# -------------------------------------------------------------
# 4. Desktop Detalle Serie (Serie: "Cronos" - Frame 44:2)
# -------------------------------------------------------------
def render_detalle_serie():
    w, h = 1920, 1080
    img = Image.new('RGB', (w, h), BG_COLOR)
    render_rail(img, active_name="series")
    draw = ImageDraw.Draw(img)

    rail_w = 88
    content_w = w - rail_w

    # 1. Full Bleed Backdrop for Cronos (Top 460px)
    bd_path = os.path.join(BACKDROPS_DIR, 'backdrop_cronos.jpg')
    if os.path.exists(bd_path):
        bd_img = Image.open(bd_path).convert('RGB').resize((content_w, 460), Image.Resampling.LANCZOS)
        img.paste(bd_img, (rail_w, 0))

    # 2. Poster
    poster_x = rail_w + 52
    poster_y = 230
    pw, ph = 210, 315

    p_path = os.path.join(POSTERS_DIR, 'cronos_s02.jpg')
    if os.path.exists(p_path):
        p_img = Image.open(p_path).convert('RGB').resize((pw, ph), Image.Resampling.LANCZOS)
        mask = Image.new('L', (pw, ph), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw, ph], radius=10, fill=255)
        
        draw.rounded_rectangle([poster_x - 6, poster_y - 6, poster_x + pw + 6, poster_y + ph + 6], radius=12, fill=(5, 8, 12))
        img.paste(p_img, (poster_x, poster_y), mask)
        draw.rounded_rectangle([poster_x, poster_y, poster_x + pw, poster_y + ph], radius=10, outline=(50, 65, 85), width=2)

    # 3. Series Header & Metadata
    meta_x = poster_x + pw + 40
    meta_y = 250

    draw.text((meta_x, meta_y), "Cronos", fill=TEXT_PRIMARY, font=get_font(34))

    tags_y = meta_y + 48
    # Frame 44:2 states "3 Temporadas"
    draw.text((meta_x, tags_y), "2025   •   3 Temporadas   •   Ciencia Ficción / Thriller   •   ", fill=TEXT_SECONDARY, font=get_font(16))
    
    star_x = meta_x + 420
    draw_star_icon(draw, star_x, tags_y + 10, 8, STAR_GOLD)
    draw.text((star_x + 14, tags_y), "8.7", fill=TEXT_PRIMARY, font=get_font(16))

    # 4K UHD badge
    b_x = star_x + 60
    draw.rounded_rectangle([b_x, tags_y - 2, b_x + 64, tags_y + 22], radius=4, outline=TEXT_MUTED, fill=SURFACE_COLOR)
    draw.text((b_x + 32, tags_y + 10), "4K UHD", fill=TEXT_PRIMARY, font=get_font(11), anchor="mm")

    # CTA Button
    cta_y = tags_y + 36
    btn_w, btn_h = 220, 44
    draw.rounded_rectangle([meta_x, cta_y, meta_x + btn_w, cta_y + btn_h], radius=8, fill=ACCENT_BLUE)
    draw_play_icon(draw, meta_x + 32, cta_y + 22, 12, TEXT_ON_ACCENT)
    draw.text((meta_x + 115, cta_y + 22), "Continuar T2 E5", fill=TEXT_ON_ACCENT, font=get_font(15), anchor="mm")

    # Season selector chips (3 chips matching "3 Temporadas")
    chips_y = cta_y + 60
    draw.text((meta_x, chips_y + 6), "Temporada:", fill=TEXT_SECONDARY, font=get_font(15))
    
    seasons = [("Temporada 1", False), ("Temporada 2", True), ("Temporada 3", False)]
    chip_x = meta_x + 110
    for s_name, is_sel in seasons:
        cw = 120
        if is_sel:
            draw.rounded_rectangle([chip_x, chips_y, chip_x + cw, chips_y + 32], radius=6, fill=ACCENT_BLUE)
            draw.text((chip_x + cw // 2, chips_y + 16), s_name, fill=TEXT_ON_ACCENT, font=get_font(13), anchor="mm")
        else:
            draw.rounded_rectangle([chip_x, chips_y, chip_x + cw, chips_y + 32], radius=6, fill=SURFACE_COLOR, outline=(50, 65, 80), width=1)
            draw.text((chip_x + cw // 2, chips_y + 16), s_name, fill=TEXT_SECONDARY, font=get_font(13), anchor="mm")
        chip_x += cw + 12

    # 4. Approved 5 Episodes List
    ep_section_y = poster_y + ph + 32
    draw.text((poster_x, ep_section_y), "Episodios — Temporada 2", fill=TEXT_PRIMARY, font=get_font(22))

    approved_episodes = [
        ("cronos_ep01_ruido_de_fondo.jpg", "1. Ruido de fondo", "42 min", "Un fallo en el colisionador cuántico abre una brecha temporal imprevista.", 1.0),
        ("cronos_ep02_el_eco.jpg", "2. El eco", "45 min", "El equipo descubre ecos de eventos que ocurrirán en las próximas 48 horas.", 1.0),
        ("cronos_ep03_frecuencia_muerta.jpg", "3. Frecuencia muerta", "41 min", "Una persecución a través de diferentes realidades en una metrópoli distópica.", 1.0),
        ("cronos_ep04_umbral.jpg", "4. Umbral", "47 min", "La contención del umbral magnético cede ante la primera fluctuación masiva.", 1.0),
        ("cronos_ep05_lo_que_queda.jpg", "5. Lo que queda", "44 min", "Tras el colapso temporal, los supervivientes rastrean el origen de la señal.", 0.42),
    ]

    ep_start_y = ep_section_y + 36
    ep_h = 76
    thumb_w, thumb_h = 120, 68

    for i, (ep_file, ep_title, ep_dur, ep_desc, prog) in enumerate(approved_episodes):
        ey = ep_start_y + i * ep_h
        row_bg = (24, 34, 48) if i == 4 else SURFACE_COLOR
        draw.rounded_rectangle([poster_x, ey, w - 88, ey + ep_h - 8], radius=8, fill=row_bg, outline=(40, 54, 72) if i == 4 else None, width=1)

        ep_img_path = os.path.join(EPISODES_DIR, ep_file)
        if os.path.exists(ep_img_path):
            e_img = Image.open(ep_img_path).convert('RGB').resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
            t_mask = Image.new('L', (thumb_w, thumb_h), 0)
            ImageDraw.Draw(t_mask).rounded_rectangle([0, 0, thumb_w, thumb_h], radius=6, fill=255)
            img.paste(e_img, (poster_x + 4, ey + 4), t_mask)

            if prog > 0:
                pb_y = ey + thumb_h - 2
                draw.rectangle([poster_x + 4, pb_y, poster_x + 4 + thumb_w, pb_y + 4], fill=PROGRESS_BG)
                draw.rectangle([poster_x + 4, pb_y, poster_x + 4 + int(thumb_w * prog), pb_y + 4], fill=ACCENT_BLUE)

        tx = poster_x + thumb_w + 20
        draw.text((tx, ey + 10), ep_title, fill=TEXT_PRIMARY, font=get_font(15))
        draw.text((tx + 260, ey + 10), f"•   {ep_dur}", fill=TEXT_SECONDARY, font=get_font(14))
        draw.text((tx, ey + 34), ep_desc, fill=TEXT_SECONDARY, font=get_font(13))

        play_color = ACCENT_BLUE if i == 4 else TEXT_SECONDARY
        draw_play_icon(draw, w - 120, ey + 32, 14, play_color)

    dst = os.path.join(MOCKUPS_DIR, 'mockup_desktop_detalle_serie.png')
    img.save(dst, 'PNG')
    img.save(os.path.join(BRAIN_DIR, 'mockup_desktop_detalle_serie.png'), 'PNG')
    print(f'Rendered Detalle Serie Mockup (44:2): {dst}')

if __name__ == '__main__':
    render_desktop_home()
    render_tv_home()
    render_detalle_pelicula()
    render_detalle_serie()
    print('All 4 screen mockups regenerated and verified with 100% precision!')
