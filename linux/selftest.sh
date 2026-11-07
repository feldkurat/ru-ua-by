#!/bin/bash
#
# Check that the installed "Russian-Ukrainian-Belarusian" layout really
# produces the extra letters, apostrophes, currency signs, quotes and dashes on
# AltGr and AltGr+Shift.
#
# Runs two passes:
#   offline - compile /usr/share/X11/xkb/symbols/ruuaby and inspect the result
#   live    - apply the layout to the running X server, inspect what it loaded,
#             then put the previous layout back (skipped when there is no DISPLAY)

set -uo pipefail

LAYOUT=ruuaby
SYMBOLS=/usr/share/X11/xkb/symbols/$LAYOUT

# key  type                  base shift altgr altgr+shift
CASES="
AC02 FOUR_LEVEL_ALPHABETIC Cyrillic_yeru Cyrillic_YERU Ukrainian_i Ukrainian_I
AB05 FOUR_LEVEL_ALPHABETIC Cyrillic_i Cyrillic_I Ukrainian_i Ukrainian_I
AD09 FOUR_LEVEL_ALPHABETIC Cyrillic_shcha Cyrillic_SHCHA Byelorussian_shortu Byelorussian_SHORTU
AD12 FOUR_LEVEL_ALPHABETIC Cyrillic_hardsign Cyrillic_HARDSIGN Ukrainian_yi Ukrainian_YI
AC11 FOUR_LEVEL_ALPHABETIC Cyrillic_e Cyrillic_E Ukrainian_ie Ukrainian_IE
AD07 FOUR_LEVEL_ALPHABETIC Cyrillic_ghe Cyrillic_GHE Ukrainian_ghe_with_upturn Ukrainian_GHE_WITH_UPTURN
TLDE FOUR_LEVEL Cyrillic_io Cyrillic_IO apostrophe rightsinglequotemark
AE04 FOUR_LEVEL 4 semicolon U20B4 dollar
AE05 FOUR_LEVEL 5 percent U20BD EuroSign
AE09 FOUR_LEVEL 9 parenleft guillemotleft doublelowquotemark
AE10 FOUR_LEVEL 0 parenright guillemotright leftdoublequotemark
AE11 FOUR_LEVEL minus underscore endash emdash
"

failures=0

# Print "<type> <sym1> <sym2> <sym3> <sym4>" for one key of a keymap dump.
extract() {
    awk -v k="$2" '
        $0 ~ "key +<" k "> *{" { inkey = 1; type = ""; syms = "" }
        inkey && /type/ && type == "" {
            if (match($0, /"[^"]+"/)) type = substr($0, RSTART + 1, RLENGTH - 2)
        }
        inkey && /symbols\[Group1\]/ {
            line = $0
            sub(/.*\[/, "", line); sub(/\].*/, "", line)
            gsub(/[ \t]+/, "", line); gsub(/,/, " ", line)
            syms = line
        }
        inkey && /};/ { print type " " syms; exit }
    ' "$1"
}

check() {
    local dump=$1 label=$2 key type base shift altgr altgrshift got want
    printf '\n== %s ==\n' "$label"
    while read -r key type base shift altgr altgrshift; do
        [ -n "$key" ] || continue
        want="$type $base $shift $altgr $altgrshift"
        got=$(extract "$dump" "$key")
        if [ "$got" = "$want" ]; then
            printf '  PASS  %-5s %s\n' "$key" "$got"
        else
            printf '  FAIL  %-5s expected: %s\n' "$key" "$want"
            printf '              got:      %s\n' "${got:-<key not found>}"
            failures=$((failures + 1))
        fi
    done <<< "$CASES"
}

# ------------------------------------------------------------------- offline

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$SYMBOLS" ]; then
    echo "error: $SYMBOLS is not installed - run install.sh first" >&2
    exit 1
fi

printf 'xkb_keymap {\n  xkb_keycodes { include "evdev+aliases(qwerty)" };\n  xkb_types    { include "complete" };\n  xkb_compat   { include "complete" };\n  xkb_symbols  { include "pc+%s+inet(evdev)" };\n  xkb_geometry { include "pc(pc104)" };\n};\n' "$LAYOUT" \
    | xkbcomp -w 0 -o "$tmp/offline.xkm" - 2>"$tmp/offline.err"

if [ ! -s "$tmp/offline.xkm" ] || grep -q '^Error:' "$tmp/offline.err"; then
    echo "error: $SYMBOLS does not compile:" >&2
    sed 's/^/  /' "$tmp/offline.err" >&2
    exit 1
fi
xkbcomp -w 0 -xkb "$tmp/offline.xkm" "$tmp/offline.txt" 2>/dev/null
check "$tmp/offline.txt" "offline: compiled from $SYMBOLS"

# ---------------------------------------------------------------------- live

if [ -n "${DISPLAY:-}" ] && command -v setxkbmap >/dev/null; then
    saved=$(setxkbmap -query)
    restore=(-layout "$(printf '%s' "$saved" | sed -n 's/^layout: *//p')")
    v=$(printf '%s' "$saved" | sed -n 's/^variant: *//p')
    o=$(printf '%s' "$saved" | sed -n 's/^options: *//p')
    if [ -n "$v" ]; then restore+=(-variant "$v"); fi
    if [ -n "$o" ]; then restore+=(-option  "$o"); fi

    if setxkbmap -layout "$LAYOUT"; then
        xkbcomp -w 0 -xkb "$DISPLAY" "$tmp/live.txt" 2>/dev/null
        check "$tmp/live.txt" "live: loaded by the X server"
    else
        echo "error: the X server refused the layout" >&2
        failures=$((failures + 1))
    fi

    setxkbmap "${restore[@]}" || echo "warning: could not restore ${restore[*]}" >&2
    printf '\nrestored: %s\n' "$(setxkbmap -query | tr '\n' ' ')"
else
    printf '\n(no DISPLAY - live pass skipped)\n'
fi

# -------------------------------------------------------------------- verdict

printf '\n'
if [ "$failures" -eq 0 ]; then
    echo "all checks passed"
else
    echo "$failures check(s) failed"
fi
exit $((failures > 0))
