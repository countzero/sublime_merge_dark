# AGENTS.md

Canonical agent-instruction file for this repository. Both Claude Code (via the
`@AGENTS.md` import in `CLAUDE.md`) and OpenCode (which reads `AGENTS.md`
natively) load this file.

## Project Overview

Scripts that apply a dark theme (Monokai Pro) to **Sublime Merge**, including
the surfaces that ordinary theme rules cannot reach. Developed against
**Sublime Merge build 2125, unregistered, Windows**; the Linux installer was
developed and tested against a synthetic install in a Debian WSL guest.

There is no application code here. The deliverable is the two installers. They
generate every theme resource on the target machine, and redistribute none.

```
install-monokai-merge.ps1     Windows installer (verified end-to-end on real Merge)
install-monokai-merge.sh      Linux installer   (verified against a synthetic install)
tools/test-linux.sh           functional test for the bash installer
tools/probe-control-tree.ps1  ctrl+alt+click control-tree reader (see Diagnosis below)
.claude/skills/               plan-review, pr-code-review (see Skills below)
```

## The Licence Gate, and the Mechanism That Bypasses It

Sublime Merge gates theme *selection* behind a licence. Two facts, both
verified empirically rather than inferred:

- Setting `"theme": "Merge Dark.sublime-theme"` in `Preferences.sublime-settings`
  is **silently ignored**; Merge falls back to `Merge.sublime-theme`. It does
  not warn. So the active theme is always **named** `Merge`.
- `light_theme` / `dark_theme` are inert, because `theme` is explicitly set in
  the shipped defaults rather than being `auto`.

What is **not** gated: loose files under
`<data-dir>/Packages/<PackageName>/` replace same-named resources inside the
shipped `.sublime-package` archives. That is the entire basis of this project.
Verified live: adding a rule to the extracted root theme repainted the sidebar
(140,896 px).

**Do not** attempt to work around the licence any other way. No binary
patching, no key generation, no licence-file synthesis. Documented
configuration mechanisms only.

## Theme Structure

Read this before changing anything. The counter-intuitive part is that the
**light** theme is the root.

```
<install>/Packages/Theme - Merge.sublime-package
- Merge.sublime-theme          101,141 B  691 rules  extends: (none)   <- ROOT, and it is LIGHT
- Merge Dark.sublime-theme      12,632 B   34 rules  extends: Merge.sublime-theme
- {File Mode,Commit Message,Git Output} - Merge.sublime-settings       -> Breakers (light)
- {File Mode,Commit Message,Git Output} - Merge Dark.sublime-settings  -> Mariana  (dark)
- Widget - Merge.hidden-color-scheme / Widget - Merge Dark.hidden-color-scheme
```

The stock dark theme is only 34 rules. What makes it dark is its **name**:
Merge binds companion settings as `<ViewType> - <ThemeName>.sublime-settings`,
so `Merge Dark` picks up Mariana while `Merge` picks up Breakers. Since the
name is locked to `Merge`, the light companions always apply.

Our override chain re-hosts the original root under a new name, because our
file takes over the `Merge.sublime-theme` slot and `extends` would otherwise
point at itself:

```
Merge.sublime-theme                 Monokai + our fixes          extends: Merge Dark Base
  Merge Dark Base.sublime-theme     copy of shipped Merge Dark   extends: Merge Base
    Merge Base.sublime-theme        copy of shipped Merge (the light root)
```

`Merge Base` and `Merge Dark Base` are **our** names; they do not exist
upstream.

## Load-Bearing Facts

### 1. Theme variables resolve per-file

A rule resolves `var(...)` against the variables of the file the **rule** lives
in, not the file at the end of the `extends` chain. Overriding
`detail_panel_bg` in the child had no effect on a rule defined in the root.
Do not assume child variables leak upward.

### 2. Colour scheme globals must be LITERAL

Merge does not follow `var()` indirection when deriving theme colours. Upstream
Monokai writes `"background": "var(background)"`, which leaves the chrome
light. Both installers therefore generate a copy of the scheme with every
`globals` value resolved to a literal (`hsl(285, 5%, 17%)` and so on). This is
required, not cosmetic.

Upstream meetio uses the same indirection, so this is not Monokai-specific.

### 3. Three surfaces are engine-drawn and ignore every theme rule

`header` (app bar) and `details_panel` (right-hand pane) have their `layer0`
set by Merge itself, from the light companion scheme. Proven in a **single
run** with both edits live in the root file: `side_bar_container`'s literal
painted 140,896 px while `details_panel`'s painted **0**.

Everything below failed on those two elements:

| Attempt                                          | Result                      |
| ------------------------------------------------ | --------------------------- |
| rule appended in the child theme (wins by order) | ignored                     |
| `layer1.tint` instead of `layer0`                | 0 px                        |
| the variable, in the child file                  | no effect                   |
| the variable, in the root file                   | 0 px                        |
| the root's own rule edited to a literal          | 0 px                        |
| an opaque texture plus tint                      | tint ignored, renders white |

**The fix that works:** tint the `linear_container_control` **child**, which
occupies the same rectangle and does obey the theme.

```json
{ "class": "linear_container_control", "parents": [{"class": "details_panel"}],
  "layer0.tint": "<background>", "layer0.opacity": 1.0 },
{ "class": "linear_container_control", "parents": [{"class": "header"}],
  "layer0.tint": "<background>", "layer0.opacity": 1.0 },
{ "class": "header", "content_margin": 0 },
{ "class": "commit_dialog_summary_container",
  "layer0.tint": "<background>", "layer0.opacity": 1.0 }
```

`{ "class": "header", "content_margin": 0 }` is load-bearing: without it the
child's inset leaves a 2 px light line above and below the bar (1,636 px of
`#C7CCD1`).

The commit dialog pane is different: `commit_dialog_summary_container` obeys a
direct tint, no child needed. Neither Monokai nor the light base styles it.

### 4. Generalisable rule

When a surface resists every theme rule, stop attacking the parent. Read the
control tree, find the child that covers the same rectangle, and tint that.

## Diagnosis: `log_control_tree`

The single most valuable technique here, and absent from the themes reference.
Source: a Sublime staff reply, forum topic 55800.

1. Add `"log_control_tree": true` to `Packages/User/Preferences.sublime-settings`.
2. `ctrl+alt+click` any pixel in Merge.
3. Open the console (the `toggle_console` binding, `ctrl` plus backtick). It
   prints the full control tree for what was clicked, **with resolved property
   values**.

Example output that ended a long dead end:

```
details_panel pos: 651,96 size: 989,999
    .layer0.opacity=1
    .layer0.tint=[252, 253, 253, 255]     <- #FCFDFD
  linear_container_control pos: 651,128 size: 989,967
```

Use this **before** guessing at class names. Remove the setting when done.

`tools/probe-control-tree.ps1` automates the click and console capture.
Gotchas it already handles: the console is a **toggle** whose state persists
across restarts; `SetForegroundWindow` is refused from a background session, so
minimise-then-restore or `AttachThreadInput` is needed; and opening the console
re-lays out the window, so capture and click must happen in one pass.

## Verification Method

Never judge a colour change from a screenshot. Measure.

- Capture with `PrintWindow(hwnd, hdc, 2)` (`PW_RENDERFULLCONTENT`).
  `CopyFromScreen` is unreliable because other windows overlap.
- Count exact pixel values. The two target colours are the light toolbar
  `#C7CCD1` and the light panel `#FCFDFD`.
- Report light coverage as the share of sampled pixels with luminance > 150.

Verified end state, both view types, on real Merge:

```
commit dialog   C7CCD1=0   FCFDFD=0   light%=3.22
commit detail   C7CCD1=0   FCFDFD=0   light%=2.46   (22.45 before)
```

Residual light pixels are legitimate: text, diff highlights, badge chips.

Check **both** states. The commit *dialog* (nothing selected) and the commit
*detail* (a commit's diff open) expose different surfaces; a fix verified in
one can be absent in the other.

## Dead Ends: Do Not Repeat

Each of these cost real time and produced a confident wrong answer.

- **`#FCFDFD` equals Breakers' background exactly** (`hsl(180, 9%, 99%)`).
  A **red herring**. Overriding `Breakers.sublime-color-scheme` works (verified:
  a view bound to it went dark) yet the panel stayed light.
- Sweeping all 314 base classes with marker colours: the target surface is not
  among them, because its value is engine-set rather than rule-set.
- Overriding the view-type settings (`File Mode - Merge` and friends) as package
  resources: no effect on the engine-drawn surfaces.
- `themed_title_bar: false`: keeps the light strip and adds a menu bar.
- `Diff.sublime-settings` (un-suffixed), the file the docs name as the source of
  theme colours: no observable effect. Both installers still write it, because
  the documentation says to and it is harmless.
- Installing the complete third-party **meetio** theme (290 styled classes
  against Monokai's 53): shows the same white surfaces. Not a Monokai gap.

## Portability Notes

Both caught by `tools/test-linux.sh`; both would otherwise have shipped
silently.

- **No `eval` on resolved colours.** Values like `hsl(285, 5%, 17%)` contain
  parentheses and spaces, which `eval` treats as shell syntax. Read them with
  `sed -n "s/^key=//p"` instead.
- **No interval expressions in awk.** Debian's default `awk` is `mawk`, where
  `/^[[:space:]]{0,4}\]$/` does not match. Use `[[:space:]]*` and take the last
  match.
- Extraction accepts `unzip` **or** `python3`; `git` is required only when the
  upstream clone is missing.

Linux paths, in probe order. Data dir: `$XDG_CONFIG_HOME/sublime-merge`, then
`~/.config/sublime_merge`, then the Flatpak location. Install dir:
`/opt/sublime_merge`, `/usr/lib/sublime-merge`, `/usr/share/sublime-merge`, then
Flatpak. Both are overridable with `--data-dir` / `--merge-dir`.

## Scratch Files

Ad-hoc agent artefacts (screenshots, pixel measurements, control-tree captures,
scratch scripts, diffs) go under `.tmp/sessions/<session-id>/`. `.tmp/` is
gitignored. Never write scratch files to `.claude/`, the repository root, or
`tools/`. `tools/probe-control-tree.ps1` takes `-OutputDir` for exactly this
reason: point it at your session directory rather than letting captures land
next to the script.

## Multi-Agent Working Tree Discipline

Multiple agents may share this directory; foreign uncommitted changes and
untracked files are untouchable.

1. **Foreign changes off-limits.** Never run `git checkout --`, `restore --`,
   `reset --hard`, `clean`, `rm`, `mv`, or `git stash pop/apply` on a path
   another agent modified or an untracked file another agent created. "Commit
   and push" does NOT authorise destructive cleanup of foreign paths.
2. **Preflight.** `git status --porcelain -u` at task start and again before
   `git commit`. Stage with explicit pathspecs; never `git add -A`.
3. **Session-scoped scratch.** Use `<session-id>` from your runtime's session
   metadata if exposed; otherwise mint `YYYYMMDD-HHMMSS-<random6>`.
4. **Stashes session-scoped.** Only with an explicit pathspec and a tagged
   message: `git stash push --message "session-<id>: <reason>" -- <files>`.
   Bare `git stash`, `-u`, `--all`, and pop/apply of foreign stashes are
   forbidden.
5. **Edit and shell writes are mutually exclusive per file.** If a file was
   written outside the Edit tool, the cached content is stale. Re-Read before
   the next Edit. If Edit fails with "oldString not found", assume a concurrent
   foreign write: surface it to the user, do not guess.

When your changes overlap foreign WIP in the same file, stop and ask. Do not
reset, restore, or stash.

## Skills

Under `.claude/skills/`, loaded on demand:

- `plan-review`: second-pass design review before presenting a non-trivial
  plan. Ten lenses; emits a tail marker only when the pass changed something.
- `pr-code-review`: three-pass defect review of a diff, severity-filtered, with
  deep links. Advisory only; it never writes to GitHub. Its project-specific
  checklist is the enforcement arm of *Rules for Changes* below.

## Rules for Changes

1. **Verify by measurement, in both view states, before claiming a fix.** A
   screenshot impression is not evidence. This was got wrong once: the toolbar
   was reported fixed while still `#C7CCD1`.
2. **Validate generated JSON before writing it.** Theme files permit `//`
   comments and trailing commas, so strip both before parsing. A malformed
   theme fails *silently* and Merge falls back, which looks like "the rule did
   not work" and sends you down a dead end. Both installers gate on this.
3. **A rule that appears inert may not have been applied at all.** Include a
   control that is known to paint, in the same run. Several early conclusions
   were void for want of this.
4. **Never edit the `Monokai Theme` clone** on a target machine; it is a
   pristine upstream checkout and the installers read from it.
5. **Never commit generated theme resources.** `Merge Base.sublime-theme` is a
   verbatim copy of Sublime HQ's shipped theme; the installers extract it from
   the user's own installation at run time, which is why this repository
   redistributes nothing. Re-run an installer after any Sublime Merge upgrade,
   since that copy is version-specific.
6. Keep the installers idempotent, and keep `--uninstall` in step with whatever
   files they create.
7. Run `tools/test-linux.sh` after touching the bash installer. It needs a
   Debian-like guest and the paths at the top adjusted.

## Reference

- Themes reference: https://www.sublimemerge.com/docs/themes
- `log_control_tree`: forum topic 55800, reply 2
- Upstream theme: https://github.com/bitsper2nd/merge-monokai-theme
