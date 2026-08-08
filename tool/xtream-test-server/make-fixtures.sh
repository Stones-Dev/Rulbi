#!/usr/bin/env bash
# Genera el contenido sintético de prueba (ffmpeg) para el servidor Xtream
# de desarrollo. Nada de vídeo real de ningún proveedor (principio P4) — todo
# se sintetiza aquí en build time (testsrc2 + tonos senoidales) y no se
# comitea ningún binario resultante.
#
# El timecode transcurrido va quemado en la imagen (drawtext) para poder
# verificar un seek leyendo la pantalla, y cada pista de audio es un tono
# senoidal distinto para poder verificar el selector de pistas de oído.
set -euo pipefail

OUT_ROOT="${1:-/media}"
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

mkdir -p "$OUT_ROOT/vod" "$OUT_ROOT/series" "$OUT_ROOT/live"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

make_srt() {
  # make_srt <path> <duration_segundos> <texto>
  # Un único cue que cubre todo el vídeo — el enunciado solo pedía "texto
  # constante y distinto" por pista, no subtítulos temporizados.
  local path="$1" dur="$2" text="$3"
  local h=$((dur / 3600)) m=$(((dur % 3600) / 60)) s=$((dur % 60))
  printf '1\n00:00:00,000 --> %02d:%02d:%02d,000\n%s\n' "$h" "$m" "$s" "$text" > "$path"
}

burn_timecode() {
  # Filtro drawtext reutilizado por todos los vídeos.
  echo "drawtext=fontfile=${FONT}:timecode='00\:00\:00\:00':rate=25:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.6:x=(w-text_w)/2:y=h-140"
}

# --- Película VOD: 10 min, 3 pistas de audio, 2 de subtítulos (mp4/mov_text) ---
MOVIE_DUR=600
make_srt "$WORKDIR/sub_eng.srt" "$MOVIE_DUR" "SUB ENG"
make_srt "$WORKDIR/sub_spa.srt" "$MOVIE_DUR" "SUB SPA"
ffmpeg -y -loglevel error \
  -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=${MOVIE_DUR}" \
  -f lavfi -i "sine=frequency=440:duration=${MOVIE_DUR}" \
  -f lavfi -i "sine=frequency=880:duration=${MOVIE_DUR}" \
  -f lavfi -i "sine=frequency=220:duration=${MOVIE_DUR}" \
  -i "$WORKDIR/sub_eng.srt" -i "$WORKDIR/sub_spa.srt" \
  -filter_complex "[0:v]$(burn_timecode)[v]" \
  -map "[v]" -map 1:a -map 2:a -map 3:a -map 4 -map 5 \
  -c:v libx264 -g 50 -pix_fmt yuv420p -c:a aac -c:s mov_text \
  -metadata:s:a:0 language=eng -metadata:s:a:0 title=English \
  -metadata:s:a:1 language=spa -metadata:s:a:1 title=Español \
  -metadata:s:a:2 language=fra -metadata:s:a:2 title=Français \
  -metadata:s:s:0 language=eng -metadata:s:s:0 title="SUB ENG" \
  -metadata:s:s:1 language=spa -metadata:s:s:1 title="SUB SPA" \
  -movflags +faststart \
  -shortest "$OUT_ROOT/vod/movie.mp4"

# --- Episodios de serie: 5 min, 2 pistas de audio, 1 de subtítulos (mkv/srt) ---
EP_DUR=300
for season in 1 2; do
  for episode in 1 2; do
    tag=$(printf 'S%02dE%02d' "$season" "$episode")
    out="$OUT_ROOT/series/s$(printf '%02d' "$season")e$(printf '%02d' "$episode").mkv"
    make_srt "$WORKDIR/ep_sub.srt" "$EP_DUR" "SUB ENG $tag"
    ffmpeg -y -loglevel error \
      -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=${EP_DUR}" \
      -f lavfi -i "sine=frequency=440:duration=${EP_DUR}" \
      -f lavfi -i "sine=frequency=880:duration=${EP_DUR}" \
      -i "$WORKDIR/ep_sub.srt" \
      -filter_complex "[0:v]drawtext=fontfile=${FONT}:text='${tag}':fontsize=56:fontcolor=yellow:x=40:y=40,$(burn_timecode)[v]" \
      -map "[v]" -map 1:a -map 2:a -map 3 \
      -c:v libx264 -g 50 -pix_fmt yuv420p -c:a aac -c:s srt \
      -metadata:s:a:0 language=eng -metadata:s:a:0 title=English \
      -metadata:s:a:1 language=spa -metadata:s:a:1 title=Español \
      -metadata:s:s:0 language=eng -metadata:s:s:0 title="SUB ENG" \
      -shortest "$out"
  done
done

# --- Canal en directo: 2 min, 1 pista de audio, sin subtítulos (ts) ---
LIVE_DUR=120
ffmpeg -y -loglevel error \
  -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=${LIVE_DUR}" \
  -f lavfi -i "sine=frequency=660:duration=${LIVE_DUR}" \
  -filter_complex "[0:v]drawtext=fontfile=${FONT}:text='LIVE TEST':fontsize=56:fontcolor=red:x=40:y=40,$(burn_timecode)[v]" \
  -map "[v]" -map 1:a \
  -c:v libx264 -g 50 -pix_fmt yuv420p -c:a aac \
  -shortest -f mpegts "$OUT_ROOT/live/channel1.ts"

echo "Fixtures generadas en $OUT_ROOT"
