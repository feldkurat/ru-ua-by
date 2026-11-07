#!/bin/bash
#
# Remove the "Russian-Ukrainian-Belarusian" XKB layout installed by install.sh.
#
# Only touches what install.sh created; if the rules files were backed up they
# are restored, otherwise the ruuaby entries are stripped out by pattern.

set -euo pipefail

LAYOUT=ruuaby
XKB_DIR=/usr/share/X11/xkb
RULES_DIR="$XKB_DIR/rules"
SYMBOLS_DEST="$XKB_DIR/symbols/$LAYOUT"
BACKUP_EXT=.ruuaby-backup

say()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

rewrite() {
    local f=$1 tmp
    tmp=$(mktemp)
    cat > "$tmp"
    cat "$tmp" > "$f"
    rm -f "$tmp"
}

unregister_xml() {
    local f=$1
    [ -f "$f" ] || return 0
    if [ -f "$f$BACKUP_EXT" ]; then
        cat "$f$BACKUP_EXT" > "$f"
        rm -f "$f$BACKUP_EXT"
        say "  $f: restored from backup"
        return 0
    fi
    if ! grep -q "<name>$LAYOUT</name>" "$f"; then
        say "  $f: nothing to remove"
        return 0
    fi
    # Drop the whole <layout>...</layout> block that contains <name>ruuaby</name>.
    awk -v layout="$LAYOUT" '
        /<layout>/ { buf = $0 "\n"; n = 1; next }
        n {
            buf = buf $0 "\n"
            if ($0 ~ "<name>" layout "</name>") hit = 1
            if ($0 ~ /<\/layout>/) {
                if (!hit) printf "%s", buf
                buf = ""; n = 0; hit = 0
            }
            next
        }
        { print }
    ' "$f" | rewrite "$f"
    say "  $f: ruuaby entry removed"
}

unregister_lst() {
    local f=$1
    [ -f "$f" ] || return 0
    if [ -f "$f$BACKUP_EXT" ]; then
        cat "$f$BACKUP_EXT" > "$f"
        rm -f "$f$BACKUP_EXT"
        say "  $f: restored from backup"
        return 0
    fi
    if ! grep -qE "^[[:space:]]+$LAYOUT[[:space:]]" "$f"; then
        say "  $f: nothing to remove"
        return 0
    fi
    grep -vE "^[[:space:]]+$LAYOUT[[:space:]]" "$f" | rewrite "$f"
    say "  $f: ruuaby entry removed"
}

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$(readlink -f -- "$0")" "$@"
fi

say "unregistering:"
unregister_xml "$RULES_DIR/evdev.xml"
unregister_lst "$RULES_DIR/evdev.lst"
unregister_xml "$RULES_DIR/base.xml"
unregister_lst "$RULES_DIR/base.lst"

if [ -f "$SYMBOLS_DEST" ]; then
    rm -f "$SYMBOLS_DEST"
    say "removed $SYMBOLS_DEST"
fi

rm -f /etc/apt/apt.conf.d/99-ruuaby-xkb

# The user's layout list is left alone on purpose - just point out the dangling
# reference, the same way the Windows uninstaller only removes what it knows.
user=${SUDO_USER:-}
if [ -n "$user" ] && [ "$user" != root ]; then
    home=$(getent passwd "$user" | cut -d: -f6)
    rc="$home/.config/kxkbrc"
    if [ -f "$rc" ] && grep -q "$LAYOUT" "$rc"; then
        say
        warn "$rc still lists '$LAYOUT'."
        if [ -f "$rc$BACKUP_EXT" ]; then
            say "         restore it with: cp '$rc$BACKUP_EXT' '$rc'"
        else
            say "         edit LayoutList to put 'ru' back, or fix it in"
            say "         System Settings > Input Devices > Keyboard > Layouts"
        fi
    fi
fi

say
say "done."
