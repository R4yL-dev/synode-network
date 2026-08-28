#!/usr/bin/env bash
# Régénère les fichiers .woff2 servis au navigateur (public/assets/fonts/*/)
# à partir des .ttf sources (téléchargés depuis Google Fonts, gardés dans
# tools/fonts/, jamais servis).
#
# Pour chaque police, produit deux fichiers :
#   X-Variable.woff2       -> subset latin (léger, chargé sur toutes les pages)
#   X-Variable-full.woff2  -> police complète (chargée par le navigateur
#                             uniquement si un caractère hors latin est affiché,
#                             grâce à unicode-range dans le CSS)
#
# Usage : tools/build-fonts.sh
# Dépendances : python3 (un venv avec fonttools + brotli est créé dans tools/.venv)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tools/fonts"            # .ttf sources (non servis)
OUT="$ROOT/public/assets/fonts"    # .woff2 servis
VENV="$ROOT/tools/.venv"

# Plage de caractères conservée dans le subset "latin".
# Identique à ce que Google Fonts sert pour latin + latin-ext :
# ASCII, Latin-1 (accents), Latin étendu, ponctuation typographique,
# €, ™, flèches simples. Pour ajouter des caractères, étendre cette liste.
LATIN="U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0300-0301,U+0303-0304,U+0308-0309,U+0323,U+0329,U+2000-206F,U+20AC,U+2122,U+2190-2199,U+2212,U+2215,U+FEFF,U+FFFD"

if [ ! -x "$VENV/bin/python" ]; then
    echo "==> Création du venv dans $VENV"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q fonttools brotli
fi
PY="$VENV/bin/python"

# build <ttf source> <dossier de sortie> <nom de sortie sans extension> [axe=valeur à épingler ...]
build() {
    local src="$1" dir="$2" out="$3"; shift 3
    mkdir -p "$dir"
    local tmp; tmp="$(mktemp --suffix=.ttf)"

    if [ $# -gt 0 ]; then
        # Épingle des axes variables (ex. opsz=14) pour réduire la taille
        "$PY" - "$src" "$tmp" "$@" <<'EOF'
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
src, dst, *axes = sys.argv[1:]
pins = {k: float(v) for k, v in (a.split("=") for a in axes)}
instantiateVariableFont(TTFont(src), pins).save(dst)
EOF
    else
        cp "$src" "$tmp"
    fi

    # Police complète -> woff2 (compression seule, aucun glyphe retiré)
    "$PY" -m fontTools.subset "$tmp" --unicodes='*' --layout-features='*' \
        --flavor=woff2 --output-file="$dir/$out-full.woff2"

    # Subset latin -> woff2
    "$PY" -m fontTools.subset "$tmp" --unicodes="$LATIN" --layout-features='*' \
        --flavor=woff2 --output-file="$dir/$out.woff2"

    rm -f "$tmp"
    printf "%-28s latin: %4d Ko   full: %4d Ko\n" "$out" \
        $(( $(stat -c %s "$dir/$out.woff2") / 1024 )) \
        $(( $(stat -c %s "$dir/$out-full.woff2") / 1024 ))
}

echo "==> Génération des woff2"
build "$SRC/Inter-VariableFont_opsz,wght.ttf"        "$OUT/Inter"         Inter-Variable         opsz=14
build "$SRC/Inter-Italic-VariableFont_opsz,wght.ttf" "$OUT/Inter"         Inter-Italic-Variable  opsz=14
build "$SRC/SpaceGrotesk-VariableFont_wght.ttf"      "$OUT/Space_Grotesk" SpaceGrotesk-Variable
build "$SRC/FiraCode-VariableFont_wght.ttf"          "$OUT/Fira_Code"     FiraCode-Variable
echo "==> OK"
