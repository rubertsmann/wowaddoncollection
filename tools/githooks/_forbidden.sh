# Shared by the hooks in this folder. The patterns live in .git/info/forbidden-words (never committed, never pushed):
# one case-insensitive extended regex per line; blank lines and lines starting with # are ignored.
# Enable once per clone: git config core.hooksPath tools/githooks
FORBIDDEN_FILE="$(git rev-parse --git-common-dir)/info/forbidden-words"
FORBIDDEN_ACTIVE="$FORBIDDEN_FILE.active"

# Prepares the pattern list. Fails closed: exits the hook with 1 when the list does not compile, so a broken
# pattern can never let a leak through; returns 1 (skip the check) only when there is no list at all.
forbidden_patterns() {
    [ -f "$FORBIDDEN_FILE" ] || { echo "warning: $FORBIDDEN_FILE missing, identity check skipped" >&2; return 1; }
    grep -v -E '^[[:space:]]*(#|$)' "$FORBIDDEN_FILE" | tr -d '\r' > "$FORBIDDEN_ACTIVE"
    [ -s "$FORBIDDEN_ACTIVE" ] || return 1
    echo | grep -i -E -f "$FORBIDDEN_ACTIVE" > /dev/null 2>&1
    if [ $? -eq 2 ]; then
        echo "error: a pattern in $FORBIDDEN_FILE is not a valid regex; commit/push blocked:" >&2
        echo | grep -i -E -f "$FORBIDDEN_ACTIVE" >&2
        exit 1
    fi
}

# Prints the lines of stdin that match a forbidden pattern (with line numbers).
forbidden_matches() {
    grep -n -i -E -f "$FORBIDDEN_ACTIVE"
}

# The email of an identity, with a GitHub noreply address (which carries the public handle) blanked out.
email_only() {
    sed -E 's/^.*<([^>]*)>.*$/\1/; s/^[0-9]+\+[^@]+@users\.noreply\.github\.com$//; s/^noreply@users\.noreply\.github\.com$//'
}
