#!/usr/bin/env bash
# Genera poster.pdf a partir de poster.html (A1 vertical, 594 x 841 mm).
#
# Uso:
#   ./build.sh            # busca Chrome/Chromium automáticamente
#   CHROME=/ruta/chrome ./build.sh
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SALIDA="${AQUI}/poster.pdf"

NAVEGADOR="${CHROME:-}"
if [ -z "${NAVEGADOR}" ]; then
  for candidato in "${HOME}"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome \
                   "${HOME}"/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell; do
    if [ -x "${candidato}" ]; then NAVEGADOR="${candidato}"; break; fi
  done
fi
if [ -z "${NAVEGADOR}" ]; then
  for nombre in google-chrome google-chrome-stable chromium chromium-browser; do
    ruta="$(command -v "${nombre}" 2>/dev/null || true)"
    if [ -n "${ruta}" ]; then NAVEGADOR="${ruta}"; break; fi
  done
fi
if [ -z "${NAVEGADOR}" ]; then
  echo "No se encontró Chrome/Chromium. Instálalo o pasa CHROME=/ruta/al/binario." >&2
  exit 1
fi

echo "Navegador: ${NAVEGADOR}"
"${NAVEGADOR}" --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
  --virtual-time-budget=3000 --run-all-compositor-stages-before-draw \
  --print-to-pdf="${SALIDA}" "file://${AQUI}/poster.html" 2>&1 | tail -2

echo "Generado: ${SALIDA}"
if command -v pdfinfo >/dev/null; then
  pdfinfo "${SALIDA}" | grep -E "^Pages|^Page size"
fi
