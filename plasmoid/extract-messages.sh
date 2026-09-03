#!/bin/sh
# Re-extract translatable strings from the QML sources into po/*.pot,
# then merge the changes into the existing translations.
#
# Run this whenever you add, remove, or reword an i18n() string.
set -e

DOMAIN="plasma_applet_org.vrgb.keyboard"
BASE="$(cd "$(dirname "$0")" && pwd)"
POT="$BASE/po/$DOMAIN.pot"

mkdir -p "$BASE/po"

# -C -kde is the KDE extraction mode; it understands the i18n* call family and
# parses QML well enough since the call syntax matches C++.
xgettext --from-code=UTF-8 -C -kde \
    -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
    --package-name="VRGB Keyboard Lighting" \
    --msgid-bugs-address="https://github.com/vrgb-dev/vrgb/issues" \
    -o "$POT" \
    "$BASE"/package/contents/ui/*.qml

echo "Wrote ${POT#"$BASE"/}"

for po in "$BASE"/po/*.po; do
    [ -e "$po" ] || continue
    msgmerge --quiet --update --backup=none "$po" "$POT"
    echo "Merged into ${po#"$BASE"/}"
done

echo
echo "Next: translate any new strings in po/*.po, then run ./build-translations.sh"
