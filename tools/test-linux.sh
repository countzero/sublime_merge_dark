#!/usr/bin/env bash
# Functional test of install-monokai-merge.sh against a synthetic Linux install.
set -uo pipefail

# Repository root, derived from this script's own location so the test always exercises
# the installer sitting next to it rather than a copy somewhere else.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A real Sublime Merge installation is needed for the .sublime-package and, optionally, an
# existing upstream clone to avoid hitting the network. Override either for your own host.
: "${SM_PACKAGE:=/mnt/c/Program Files/Sublime Merge/Packages/Theme - Merge.sublime-package}"
: "${SM_CLONE:=$HOME/.config/sublime-merge/Packages/Monokai Theme}"
WINPKG="$SM_PACKAGE"
WINCLONE="$SM_CLONE"
ROOT=/tmp/smtest

echo '=== 1. syntax check ==='
bash -n "$SRC/install-monokai-merge.sh" && echo '  bash -n: OK' || { echo '  bash -n: FAILED'; exit 1; }

echo
echo '=== 2. tool availability ==='
for t in awk unzip git python3 sed; do
    if command -v "$t" >/dev/null 2>&1; then
        printf '  %-8s %s\n' "$t" "$(command -v "$t")"
    else
        printf '  %-8s MISSING\n' "$t"
    fi
done

echo
echo '=== 3. build a synthetic install ==='
rm -rf "$ROOT"
mkdir -p "$ROOT/opt/sublime_merge/Packages" "$ROOT/home/.config/sublime-merge/Packages"
cp "$WINPKG" "$ROOT/opt/sublime_merge/Packages/" || { echo '  could not copy the package'; exit 1; }
# pre-seed the upstream clone when one is available, so the test needs no network
if [ -d "$WINCLONE/common" ]; then
    cp -r "$WINCLONE" "$ROOT/home/.config/sublime-merge/Packages/Monokai Theme"
else
    echo "  no local clone at '$WINCLONE'; the installer will clone (needs network)"
fi
echo "  package: $(du -h "$ROOT/opt/sublime_merge/Packages/Theme - Merge.sublime-package" | cut -f1)"
echo "  clone pre-seeded: $([ -d "$ROOT/home/.config/sublime-merge/Packages/Monokai Theme/common" ] && echo yes || echo no)"

echo
echo '=== 4. run the installer ==='
bash "$SRC/install-monokai-merge.sh" \
    --merge-dir "$ROOT/opt/sublime_merge" \
    --data-dir "$ROOT/home/.config/sublime-merge"
rc=$?
echo "  exit code: $rc"
[ $rc -eq 0 ] || exit 1

echo
echo '=== 5. files produced ==='
find "$ROOT/home/.config/sublime-merge/Packages/Theme - Merge" \
     "$ROOT/home/.config/sublime-merge/Packages/User" -maxdepth 1 -type f \
    | sort | while read -r f; do printf '  %8d  %s\n' "$(stat -c%s "$f")" "${f#$ROOT/home/.config/sublime-merge/Packages/}"; done

echo
echo '=== 6. the four generated fix rules ==='
grep -nE 'linear_container_control|commit_dialog_summary_container|"class": "header"' \
    "$ROOT/home/.config/sublime-merge/Packages/Theme - Merge/Merge.sublime-theme" \
    | sed 's/^/  /'

echo
echo '=== 7. extends chain ==='
for f in 'Merge.sublime-theme' 'Merge Dark Base.sublime-theme' 'Merge Base.sublime-theme'; do
    p="$ROOT/home/.config/sublime-merge/Packages/Theme - Merge/$f"
    printf '  %-30s %s\n' "$f" "$(grep -m1 '"extends"' "$p" 2>/dev/null || echo '(no extends - root)')"
done

echo
echo '=== 8. literal globals resolved? ==='
grep -m4 -E '"(background|foreground)"' \
    "$ROOT/home/.config/sublime-merge/Packages/User/Monokai Plus Merge.sublime-color-scheme" | sed 's/^/  /'

echo
echo '=== 9. compare against the Windows-verified output ==='
: "${SM_WINOUT:=}"
WINOUT="$SM_WINOUT"
for f in 'Theme - Merge/Merge Base.sublime-theme' 'Theme - Merge/Merge Dark Base.sublime-theme'; do
    a="$WINOUT/$f"; b="$ROOT/home/.config/sublime-merge/Packages/$f"
    if [ -f "$a" ] && [ -f "$b" ]; then
        if diff -q <(tr -d '\r' < "$a") <(tr -d '\r' < "$b") >/dev/null; then
            printf '  IDENTICAL  %s\n' "$f"
        else
            printf '  DIFFERS    %s\n' "$f"
            diff <(tr -d '\r' < "$a") <(tr -d '\r' < "$b") | head -5 | sed 's/^/      /'
        fi
    fi
done

echo
echo '=== 10. JSON validity of every generated file ==='
python3 - "$ROOT/home/.config/sublime-merge/Packages" <<'PY'
import json, re, sys, pathlib
root = pathlib.Path(sys.argv[1])
bad = 0
for p in sorted(root.rglob('*')):
    if p.is_file() and p.suffix in ('.sublime-theme', '.sublime-settings',
                                    '.sublime-color-scheme', '.hidden-color-scheme'):
        if 'Monokai Theme' in str(p):
            continue
        t = p.read_text(encoding='utf-8')
        t = re.sub(r'//[^\n]*', '', t)
        t = re.sub(r',(\s*[}\]])', r'\1', t)
        try:
            json.loads(t)
            print(f'  VALID    {p.relative_to(root)}')
        except Exception as e:
            bad += 1
            print(f'  INVALID  {p.relative_to(root)}: {e}')
sys.exit(1 if bad else 0)
PY

echo
echo '=== 11. uninstall ==='
bash "$SRC/install-monokai-merge.sh" \
    --merge-dir "$ROOT/opt/sublime_merge" \
    --data-dir "$ROOT/home/.config/sublime-merge" --uninstall
echo "  files left in Theme - Merge: $(find "$ROOT/home/.config/sublime-merge/Packages/Theme - Merge" -maxdepth 1 -type f | wc -l)"
