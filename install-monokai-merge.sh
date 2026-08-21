#!/usr/bin/env bash
#
# Applies the Monokai Pro theme to an unregistered Sublime Merge on Linux, including the
# three surfaces that no theme rule reaches on its own.
#
# Sublime Merge gates the "theme" setting behind a licence, so the active theme is always
# named "Merge", which is the LIGHT theme. Loose files under
# <data-dir>/Packages/<PackageName>/ replace same-named resources inside the shipped
# .sublime-package archives, and that is NOT gated. This script exploits that.
#
# Three surfaces need special handling because Sublime Merge draws their layer0 itself,
# from the light companion colour scheme, ignoring every theme rule:
#     header                          -> the app bar / toolbar
#     details_panel                   -> the right-hand pane behind the diffs
#     commit_dialog_summary_container  -> the commit dialog pane
# For the first two the fix is to tint their linear_container_control child, which covers
# the same rectangle and does obey the theme.
#
# Idempotent. Re-run after a Sublime Merge upgrade: two of the files it writes are
# extracted from the installed version's own package.
#
# Requires: bash, awk, sed, and either unzip or python3. git is needed only on first run,

set -euo pipefail

VARIANT="Monokai Plus"
MERGE_DIR=""
DATA_DIR=""
UNINSTALL=0
UPSTREAM_URL="https://github.com/bitsper2nd/merge-monokai-theme.git"

usage() {
    cat <<'EOF'
Usage: install-monokai-merge.sh [options]

  --variant NAME     Monokai filter to use (default: "Monokai Plus").
                     e.g. "Monokai Plus (Octagon)", "Monokai Plus (Machine)"
  --merge-dir PATH   Sublime Merge install dir (contains Packages/Theme - Merge.sublime-package)
  --data-dir PATH    Sublime Merge data dir   (contains Packages/)
  --uninstall        Remove every file this script creates
  -h, --help         Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --variant)   VARIANT="${2:?--variant needs a value}"; shift 2 ;;
        --merge-dir) MERGE_DIR="${2:?--merge-dir needs a value}"; shift 2 ;;
        --data-dir)  DATA_DIR="${2:?--data-dir needs a value}"; shift 2 ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

step() { printf '  %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- locate dirs
if [ -z "$DATA_DIR" ]; then
    config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    for candidate in "$config_home/sublime-merge" "$config_home/sublime_merge" \
                     "$HOME/.var/app/com.sublimemerge.App/config/sublime-merge"; do
        if [ -d "$candidate" ]; then DATA_DIR="$candidate"; break; fi
    done
    # nothing found: use the conventional location and create it
    DATA_DIR="${DATA_DIR:-$config_home/sublime-merge}"
fi

if [ -z "$MERGE_DIR" ]; then
    for candidate in /opt/sublime_merge /usr/lib/sublime-merge /usr/share/sublime-merge \
                     /var/lib/flatpak/app/com.sublimemerge.App/current/active/files/sublime_merge; do
        if [ -f "$candidate/Packages/Theme - Merge.sublime-package" ]; then
            MERGE_DIR="$candidate"; break
        fi
    done
fi

[ -n "$MERGE_DIR" ] || die "could not find the Sublime Merge install. Pass --merge-dir PATH
       (looking for PATH/Packages/Theme - Merge.sublime-package)"

PKG="$MERGE_DIR/Packages/Theme - Merge.sublime-package"
[ -f "$PKG" ] || die "not found: $PKG"

PACKAGES="$DATA_DIR/Packages"
THEME_DIR="$PACKAGES/Theme - Merge"
USER_DIR="$PACKAGES/User"
CLONE_DIR="$PACKAGES/Monokai Theme"
SCHEME_NAME="$VARIANT Merge.sublime-color-scheme"

# ---------------------------------------------------------------- uninstall
if [ "$UNINSTALL" -eq 1 ]; then
    for f in \
        "$THEME_DIR/Merge.sublime-theme" \
        "$THEME_DIR/Merge Base.sublime-theme" \
        "$THEME_DIR/Merge Dark Base.sublime-theme" \
        "$THEME_DIR/Widget - Merge.hidden-color-scheme" \
        "$THEME_DIR/Widget - Merge.sublime-settings" \
        "$USER_DIR/$SCHEME_NAME" \
        "$USER_DIR/Diff.sublime-settings" \
        "$USER_DIR/Diff - Merge.sublime-settings" \
        "$USER_DIR/File Mode - Merge.sublime-settings" \
        "$USER_DIR/Git Output - Merge.sublime-settings" \
        "$USER_DIR/Commit Message - Merge.sublime-settings" \
        "$USER_DIR/Commit Message (Read Only) - Merge.sublime-settings"
    do
        if [ -e "$f" ]; then rm -f -- "$f"; step "removed $(basename "$f")"; fi
    done
    printf '\nUninstalled. Restart Sublime Merge.\n'
    printf "('Monokai Theme' clone and Preferences.sublime-settings left alone.)\n"
    exit 0
fi

command -v awk >/dev/null 2>&1 || die "'awk' is required but not installed"
command -v sed >/dev/null 2>&1 || die "'sed' is required but not installed"

# Extraction needs either unzip or python3; prefer unzip when both are present.
if command -v unzip >/dev/null 2>&1; then
    extract() { unzip -p "$1" "$2"; }
elif command -v python3 >/dev/null 2>&1; then
    extract() { python3 -c 'import sys,zipfile
sys.stdout.buffer.write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))' "$1" "$2"; }
else
    die "either 'unzip' or 'python3' is required to read the .sublime-package archive"
fi

step "install dir: $MERGE_DIR"
step "data dir:    $DATA_DIR"
mkdir -p -- "$THEME_DIR" "$USER_DIR"

# ------------------------------------------- 1. upstream Monokai theme source
if [ -d "$CLONE_DIR/common" ]; then
    step "upstream Monokai clone already present"
else
    command -v git >/dev/null 2>&1 || die "'git' is required to fetch the upstream theme.
       Alternatively clone it yourself to: $CLONE_DIR"
    step "cloning $UPSTREAM_URL"
    git clone --quiet --depth 1 "$UPSTREAM_URL" "$CLONE_DIR"
fi
UPSTREAM_THEME="$CLONE_DIR/common/$VARIANT.hidden-theme"
UPSTREAM_SCHEME="$CLONE_DIR/Plus - Monokai/$VARIANT.sublime-color-scheme"
[ -f "$UPSTREAM_THEME" ]  || die "upstream theme missing: $UPSTREAM_THEME (check --variant)"
[ -f "$UPSTREAM_SCHEME" ] || die "upstream scheme missing: $UPSTREAM_SCHEME (check --variant)"

# --------------------- 2. extract the shipped themes under non-clashing names
# The shipped LIGHT theme (Merge.sublime-theme) is the root of the inheritance chain.
# Our override takes over that name, so the original is re-hosted as "Merge Base".
extract "$PKG" "Merge.sublime-theme" > "$THEME_DIR/Merge Base.sublime-theme"
extract "$PKG" "Merge Dark.sublime-theme" \
    | sed 's/"extends"[[:space:]]*:[[:space:]]*"Merge\.sublime-theme"/"extends": "Merge Base.sublime-theme"/' \
    > "$THEME_DIR/Merge Dark Base.sublime-theme"
[ -s "$THEME_DIR/Merge Base.sublime-theme" ] || die "failed to extract Merge.sublime-theme from the package"
step "extracted Merge Base + Merge Dark Base from the installed package"

# ------- 3. colour scheme with LITERAL globals
# Sublime Merge does not follow var() indirection when deriving theme colours, so every
# value in "globals" is resolved to a literal here. This is what fixes the light chrome.
RESOLVER='
function resolve(v,   guard, key, name, val) {
    guard = 0
    while (guard++ < 64 && match(v, /var\([A-Za-z0-9_-]+\)/)) {
        name = substr(v, RSTART, RLENGTH)
        key  = substr(name, 5, length(name) - 5)
        if (key in VARS) { val = VARS[key] } else { val = "\001" key "\002" }
        v = substr(v, 1, RSTART - 1) val substr(v, RSTART + RLENGTH)
    }
    gsub(/\001/, "var(", v); gsub(/\002/, ")", v)
    return v
}
{ line[NR] = $0 }
/"variables"/ { if (!vi) vi = NR }
/"globals"/   { if (!gi) gi = NR }
/"rules"/     { if (!ri && gi) ri = NR }
END {
    if (!vi || !gi || !ri) { print "SCHEME_LAYOUT_UNEXPECTED" > "/dev/stderr"; exit 1 }
    for (i = vi + 1; i < gi; i++)
        if (match(line[i], /"[A-Za-z0-9_-]+"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            s = substr(line[i], RSTART, RLENGTH)
            split(s, parts, /"[[:space:]]*:[[:space:]]*"/)
            k = parts[1]; gsub(/"/, "", k)
            v = parts[2]; gsub(/"$/, "", v)
            VARS[k] = v
        }
    for (i = 1; i <= NR; i++) {
        out = line[i]
        if (i > gi && i < ri && match(out, /("[A-Za-z0-9_]+"[[:space:]]*:[[:space:]]*")[^"]*(")/)) {
            head = substr(out, 1, RSTART - 1)
            body = substr(out, RSTART, RLENGTH)
            tail = substr(out, RSTART + RLENGTH)
            split(body, p, /"[[:space:]]*:[[:space:]]*"/)
            key = p[1]; gsub(/"/, "", key)
            val = p[2]; sub(/"$/, "", val)
            out = head "\"" key "\": \"" resolve(val) "\"" tail
        }
        if (MODE == "scheme") print out
    }
    if (MODE == "vars") {
        print "background=" resolve("var(background)")
        print "foreground=" resolve("var(foreground)")
        print "selection="  resolve("var(selection)")
        print "comment="    resolve("var(comment)")
    }
}
'
awk -v MODE=scheme "$RESOLVER" "$UPSTREAM_SCHEME" \
    | sed "0,/\"name\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/s//\"name\": \"$VARIANT Merge\"/" \
    > "$USER_DIR/$SCHEME_NAME"
[ -s "$USER_DIR/$SCHEME_NAME" ] || die "failed to generate the colour scheme"

# Pull the four resolved colours back out for the theme rules and widget palette.
# Read them rather than eval them: values like "hsl(285, 5%, 17%)" contain parentheses
# and spaces, which eval would try to interpret as shell syntax.
RESOLVED_VARS="$(awk -v MODE=vars "$RESOLVER" "$UPSTREAM_SCHEME")"
pick() { printf '%s\n' "$RESOLVED_VARS" | sed -n "s/^$1=//p" | head -n1; }
RESOLVED_background="$(pick background)"
RESOLVED_foreground="$(pick foreground)"
RESOLVED_selection="$(pick selection)"
RESOLVED_comment="$(pick comment)"
: "${RESOLVED_background:?could not resolve the scheme background}"
step "generated '$SCHEME_NAME' (background $RESOLVED_background)"

# ------------------------ 4. the Monokai theme itself, plus the three fixes
awk -v BG="$RESOLVED_background" '
# No interval expressions like {0,4}: mawk (Debian default awk) does not support them.
# The last whitespace-only-then-"]" line in the file is the rules array terminator.
{ line[NR] = $0; if ($0 ~ /^[[:space:]]*\][[:space:]]*$/) close_at = NR }
END {
    if (!close_at) { print "RULES_TERMINATOR_NOT_FOUND" > "/dev/stderr"; exit 1 }
    prev = close_at - 1
    while (prev > 1 && line[prev] ~ /^[[:space:]]*$/) prev--
    for (i = 1; i <= NR; i++) {
        if (i == close_at) {
            print "        // Sublime Merge draws header.layer0 and details_panel.layer0 itself, from"
            print "        // the light companion colour scheme, ignoring every theme rule. Their"
            print "        // linear_container_control child covers the same rect and does obey the theme."
            printf "        { \"class\": \"linear_container_control\", \"parents\": [{\"class\": \"details_panel\"}], \"layer0.tint\": \"%s\", \"layer0.opacity\": 1.0 },\n", BG
            printf "        { \"class\": \"linear_container_control\", \"parents\": [{\"class\": \"header\"}], \"layer0.tint\": \"%s\", \"layer0.opacity\": 1.0 },\n", BG
            print "        // without this, header content_margin leaves a 2px light line top and bottom"
            print "        { \"class\": \"header\", \"content_margin\": 0 },"
            printf "        { \"class\": \"commit_dialog_summary_container\", \"layer0.tint\": \"%s\", \"layer0.opacity\": 1.0 }\n", BG
        }
        if (i == prev && line[i] !~ /,[[:space:]]*$/) { sub(/[[:space:]]*$/, "", line[i]); print line[i] "," }
        else print line[i]
    }
}' "$UPSTREAM_THEME" \
    | sed 's/"extends"[[:space:]]*:[[:space:]]*"Merge\.sublime-theme"/"extends": "Merge Dark Base.sublime-theme"/' \
    > "$THEME_DIR/.Merge.sublime-theme.tmp"

# validate before putting a possibly broken theme in place
if command -v python3 >/dev/null 2>&1; then
    python3 - "$THEME_DIR/.Merge.sublime-theme.tmp" <<'PY' || die "generated theme is not valid JSON"
import json, re, sys
text = open(sys.argv[1], encoding='utf-8').read()
text = re.sub(r'//[^\n]*', '', text)          # theme files allow // comments
text = re.sub(r',(\s*[}\]])', r'\1', text)    # ... and trailing commas
json.loads(text)
PY
    step "theme JSON validated"
else
    step "python3 not found: skipping JSON validation"
fi
mv -f -- "$THEME_DIR/.Merge.sublime-theme.tmp" "$THEME_DIR/Merge.sublime-theme"
step "wrote Merge.sublime-theme (Monokai + the three surface fixes)"

# ------------------------------------------------- 5. widget palette + bindings
cat > "$THEME_DIR/Widget - Merge.hidden-color-scheme" <<EOF
{
	"name": "Sublime Merge Widgets",
	"globals":
	{
		"foreground": "$RESOLVED_foreground",
		"background": "$RESOLVED_background",
		"caret": "$RESOLVED_foreground",
		"line_highlight": "$RESOLVED_selection",
		"selection": "$RESOLVED_selection",
		"selection_border": "$RESOLVED_comment",
		"inactive_selection": "$RESOLVED_selection"
	},
	"rules": []
}
EOF
cat > "$THEME_DIR/Widget - Merge.sublime-settings" <<'EOF'
{
	"color_scheme": "Widget - Merge.hidden-color-scheme",
	"draw_shadows": false
}
EOF

# Merge binds each view type as "<Type> - <ThemeName>.sublime-settings"; the un-suffixed
# Diff.sublime-settings is what the theme docs name as the source of theme colours.
for n in "Diff" "Diff - Merge" "File Mode - Merge" "Git Output - Merge"; do
    printf '{\n\t"color_scheme": "%s"\n}\n' "$SCHEME_NAME" > "$USER_DIR/$n.sublime-settings"
done
for n in "Commit Message - Merge" "Commit Message (Read Only) - Merge"; do
    printf '{\n\t"color_scheme": "%s",\n\t"syntax": "Packages/Git Formats/Git Commit.sublime-syntax"\n}\n' \
        "$SCHEME_NAME" > "$USER_DIR/$n.sublime-settings"
done
step "bound 6 view types plus the widget palette"

# ---------------------------------------------- 6. global colour scheme preference
PREFS="$USER_DIR/Preferences.sublime-settings"
if [ ! -f "$PREFS" ]; then
    printf '{\n\t"color_scheme": "%s"\n}\n' "$SCHEME_NAME" > "$PREFS"
    step "created Preferences.sublime-settings"
elif grep -q '"color_scheme"' "$PREFS"; then
    cp -- "$PREFS" "$PREFS.bak"
    sed -i "s|\"color_scheme\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"color_scheme\": \"$SCHEME_NAME\"|" "$PREFS"
    step "updated color_scheme in Preferences.sublime-settings (backup: Preferences.sublime-settings.bak)"
else
    cp -- "$PREFS" "$PREFS.bak"
    awk -v s="$SCHEME_NAME" 'NR==1 && /^[[:space:]]*\{/ { print; printf "\t\"color_scheme\": \"%s\",\n", s; next } { print }' \
        "$PREFS.bak" > "$PREFS"
    step "added color_scheme to Preferences.sublime-settings (backup: Preferences.sublime-settings.bak)"
fi

printf '\nDone. Restart Sublime Merge.\n'
printf 'Re-run after a Sublime Merge upgrade: two files are extracted from the installed package.\n'
