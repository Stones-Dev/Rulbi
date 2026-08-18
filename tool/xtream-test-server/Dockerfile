# Servidor Xtream de pruebas (desarrollo) — ver README.md en este directorio.
#
# Imagen en dos etapas para que ffmpeg (~300 MB, y GPL — ver nota de licencia
# en el README) no acabe en la imagen final: solo se usa en build time para
# generar contenido sintético, nunca se ejecuta en el contenedor servido.
#
# Build context = raíz del repo (ver docker-compose.dev.yml) para poder
# copiar los pósters/tv_cards ya aprobados de docs/design-assets — así la
# verificación visual (S6.5) compara MediaCard contra el mismo arte que ya
# está fusionado en los frames canónicos de Figma, no contra el icono de
# fallback.

# --- Etapa 1: genera los ficheros de vídeo/audio/subtítulos sintéticos ---
FROM debian:bookworm-slim AS fixtures

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY tool/xtream-test-server/make-fixtures.sh .
RUN chmod +x make-fixtures.sh && ./make-fixtures.sh /media

# --- Etapa 2: solo el servidor Xtream + el contenido generado ---
FROM python:3.12-slim

# Versión fijada a propósito (T1.1 la usó para capturar los fixtures de
# packages/protocols/test/fixtures/xtream/dialect_o0zz/).
RUN pip install --no-cache-dir xtreamcodeserver==1.1.0

COPY --from=fixtures /media /media
COPY docs/design-assets/tv_cards /images/tv_cards
COPY docs/design-assets/posters /images/posters
COPY docs/design-assets/backdrops /images/backdrops
COPY docs/design-assets/episodes /images/episodes
COPY tool/xtream-test-server/serve.py /app/serve.py
WORKDIR /app

EXPOSE 8081 8082
CMD ["python", "serve.py"]
