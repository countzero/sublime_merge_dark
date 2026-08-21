# sublime_merge_dark

Apply the **Monokai Pro** theme to **Sublime Merge**, including the three
surfaces that ordinary theme rules cannot reach.

Sublime Merge gates theme *selection* behind a licence, but it does **not** gate
package resource overrides. This uses only documented configuration mechanisms:
no binary patching, no licence tampering.

## Before and after

Measured, not eyeballed. Share of pixels with luminance > 150:

| View          | Before      | After     |
| ------------- | ----------- | --------- |
| Commit dialog | ~57%        | **3.22%** |
| Commit detail | 22.45%      | **2.46%** |

Both target light colours, the toolbar `#C7CCD1` and the panel `#FCFDFD`, are
reduced to **zero** pixels. What light remains is text, diff highlights, and
badge chips.

## Install

### Windows

```powershell
.\install-monokai-merge.ps1
```

### Linux

```bash
chmod +x install-monokai-merge.sh
./install-monokai-merge.sh
```

Then **restart Sublime Merge**.

### Options

Both installers take the same options.

| Option                  | Meaning                                              |
| ----------------------- | ---------------------------------------------------- |
| `-Variant` / `--variant` | Monokai filter, e.g. `"Monokai Plus (Octagon)"`      |
| `--merge-dir`            | Sublime Merge install dir, if auto-detection fails    |
| `--data-dir`             | Sublime Merge data dir, if auto-detection fails       |
| `-Uninstall` / `--uninstall` | Remove every file the installer created           |

On Windows the install dir option is `-MergeProgramDir`; the data dir is always
`%AppData%\Sublime Merge`.

Available variants: `Monokai Plus`, and the `(Octagon)`, `(Machine)`,
`(Ristretto)`, `(Spectrum)`, `(Classic)`, `(Dawn)` filters that upstream ships.

### Requirements

- **Windows:** PowerShell 5.1+ and `git` (first run only).
- **Linux:** `bash`, `awk`, `sed`, and either `unzip` or `python3`. `git` is
  needed only on the first run, to fetch the upstream theme. `python3` also
  enables JSON validation of the generated theme.

## Uninstall

```powershell
.\install-monokai-merge.ps1 -Uninstall
```

```bash
./install-monokai-merge.sh --uninstall
```

This removes every file the installer wrote. The upstream `Monokai Theme` clone
and your `Preferences.sublime-settings` are left alone.

## What it installs

Under your Sublime Merge data dir (`%AppData%\Sublime Merge` on Windows,
`~/.config/sublime-merge` on Linux):

```
Packages/Theme - Merge/
    Merge.sublime-theme               Monokai, plus the four fix rules
    Merge Dark Base.sublime-theme     copy of the shipped dark theme
    Merge Base.sublime-theme          copy of the shipped light theme (the root)
    Widget - Merge.hidden-color-scheme
    Widget - Merge.sublime-settings
Packages/User/
    <Variant> Merge.sublime-color-scheme    the scheme, with literal globals
    Diff.sublime-settings
    Diff - Merge.sublime-settings
    File Mode - Merge.sublime-settings
    Git Output - Merge.sublime-settings
    Commit Message - Merge.sublime-settings
    Commit Message (Read Only) - Merge.sublime-settings
    Preferences.sublime-settings            color_scheme only; other keys preserved
Packages/Monokai Theme/                     pristine upstream clone
```

Loose files in `Packages/<PackageName>/` replace same-named resources inside the
shipped `.sublime-package` archives. That is what makes this work without a
licence.

## Why it needs more than a theme file

Two reasons, both non-obvious.

**Colour scheme globals must be literal.** Merge does not follow `var()`
indirection when deriving theme colours, and upstream Monokai writes
`"background": "var(background)"`. The installer generates a copy of the scheme
with every `globals` value resolved to a literal.

**Three surfaces are drawn by the engine, not the theme.** `header` (the app
bar) and `details_panel` (the right-hand pane) have their `layer0` set by Merge
from the *light* companion colour scheme, and they ignore every theme rule aimed
at them, including a literal in the root theme file. The fix is to tint their
`linear_container_control` child, which covers the same rectangle and does obey
the theme, plus zeroing the header's `content_margin` so no light line shows at
the edges.

Full reasoning, the measurements behind it, and the dead ends are in
[AGENTS.md](AGENTS.md).

## Repository layout

```
install-monokai-merge.ps1     Windows installer
install-monokai-merge.sh      Linux installer
packages/                     snapshot of the verified output (build 2125)
tools/test-linux.sh           functional test for the bash installer
tools/probe-control-tree.ps1  control-tree reader, for diagnosing new surfaces
AGENTS.md                     findings, method, and rules for changes
```

`packages/` is a convenience snapshot: unpack it over your data dir's
`Packages/` to skip the installer. Prefer the installers, because two of those
files are extracted from **build 2125's** shipped package and would be stale on
a different version.

## Maintenance

**Re-run the installer after upgrading Sublime Merge.** `Merge Base` and
`Merge Dark Base` are copies of the shipped themes; if Sublime HQ changes them,
your override will be running against an outdated root.

## Debugging a surface that stays light

Add `"log_control_tree": true` to `Packages/User/Preferences.sublime-settings`,
`ctrl+alt+click` the offending pixel, then open the console (`ctrl` plus
backtick). Merge prints the control tree for whatever you clicked, with resolved
property values, which tells you the class name and its current tint instead of
leaving you to guess. Remove the setting afterwards.

## Verified against

Sublime Merge build **2125**, unregistered, Windows 11. The Linux installer is
verified against a synthetic install in a Debian WSL guest: it produces
byte-identical base themes and valid JSON for all 13 files, and `--uninstall`
leaves nothing behind. It has **not** been run against a real Sublime Merge on
Linux.

## Credits

Theme: [bitsper2nd/merge-monokai-theme](https://github.com/bitsper2nd/merge-monokai-theme).
The `log_control_tree` tip comes from a Sublime staff reply on forum topic 55800.
