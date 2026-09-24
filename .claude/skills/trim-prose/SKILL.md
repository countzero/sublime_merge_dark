---
name: trim-prose
description: >
  Editing pass over the comments and documents a branch adds or changes. Cuts
  history lessons, the route to a decision, meta-commentary and the obvious,
  keeps the failure mode a rule prevents, and reports the lines and words
  removed. Use when asked to go through, tighten, shorten, or re-read the
  updated comments and docs of a branch, before opening a pull request whose
  prose has not been re-read, or when the user types /trim-prose. Edits the
  working tree; never commits.
---

# Trim Prose

The rules have one home, `AGENTS.md` → *Comments and Documentation*: what a
comment is for, and the checklist a document is held to. This is the recipe for
applying both to one branch's diff in one pass.

## Setup

Every block below runs in `pwsh` and opens with these lines, because a variable
dies with the shell call that set it and a pass always spans several calls:

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$SessionId = if ($env:SESSION_ID) { $env:SESSION_ID } else { '<minted-once>' }
if ($SessionId -notmatch '^[\w-]+$') { throw 'No session id: AGENTS.md → Multi-Agent Working Tree Discipline, rule 3' }
$Root    = git rev-parse --show-toplevel
$Scratch = Join-Path $Root ".tmp/sessions/$SessionId/trim-prose"
$State   = Join-Path $Scratch 'state.json'
$Edited  = Join-Path $Scratch 'edited-by-hand.txt'
$SplitZ  = { Param ([string[]] $Out) ((@($Out) -join "`n") -split "`0") | Where-Object { $_ } }
```

When the runtime exposes no `SESSION_ID`, mint one id at the start of the pass
(`YYYYMMDD-HHMMSS-<random6>`) and paste it over `<minted-once>` in every block.
The placeholder fails the pattern on purpose: a block run without the
substitution throws instead of writing into a fresh scratch directory that
*Prove* would then read as a capture that never ran.

The encoding line is load-bearing. A Windows console defaults to a legacy code
page (`ibm850` on a German install), git's UTF-8 output is decoded through it,
and a `→` in an added line no longer matches anything searched for.

`$SplitZ` reads `git … -z` output. PowerShell splits native output on newlines
before the script sees it, so the lines are rejoined first and the records split
on NUL: a path holding a newline stays one path, and git's C-quoting of
non-ASCII names never happens.

## Scope

Capture the tree as the pass found it, then list the branch's prose:

```powershell
git fetch origin
$base = git merge-base origin/main HEAD
if ($LASTEXITCODE -ne 0 -or -not $base) { throw 'No merge base with origin/main.' }
$pre = git stash create                      # a commit object; the tree is untouched
if (-not $pre) { $pre = git rev-parse HEAD }
$dirty = @(& $SplitZ (git -C $Root diff HEAD --name-only -z)) +
         @(& $SplitZ (git -C $Root ls-files --others --exclude-standard -z)) |
         Sort-Object -CaseSensitive -Unique
$digests = foreach ($f in $dirty) {
    $p = Join-Path $Root $f
    $h = if (Test-Path -LiteralPath $p) { git hash-object --no-filters -- $p } else { 'absent' }
    [pscustomobject]@{ Path = $f; Hash = $h }
}
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
New-Item -ItemType File -Force -Path $Edited | Out-Null
[pscustomobject]@{ Base = $base; Pre = $pre; Root = $Root; Digests = @($digests) } |
    ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $State
git diff $base --stat
git diff --stat
git ls-files --others --exclude-standard     # git diff never shows these
```

This repository commits to `main` directly, so on `main` the pass covers the
unpushed commits and the working tree, and on a branch everything since it left
`main`. `git stash create` records the tree without touching a file, and
*Report* diffs against it so the counts describe this pass rather than
everything uncommitted. `$Root` is written into `state.json` and *Prove* reads
it back rather than re-deriving it, because `git rev-parse --show-toplevel`
answers for whatever directory the call starts in.

The `ls-files` line is not redundant. An untracked file appears in no diff, so a
document the branch added and has not staged would go unread and the pass would
report itself clean. Read each one whole: every line of a new file is an added
line.

**Uncommitted prose may not be yours.** This pass edits a working tree other
agents share, and reaches into exactly the uncommitted files where their work
lives. Before editing a dirty file, establish whose the dirty hunks are; a file
carrying both your findings and someone else's edits stops the pass and goes to
the user (`AGENTS.md` → *Multi-Agent Working Tree Discipline*). Re-wrapping a
paragraph around a foreign sentence is a change nobody asked for and nobody can
easily unpick.

Then read the **added lines**, not the files:

```powershell
$s = Get-Content -LiteralPath $State -Raw | ConvertFrom-Json
git diff $s.Base -U0 | Select-String -CaseSensitive -Pattern '^(@@|\+)' | ForEach-Object Line
```

`+++ b/<path>` and `@@` survive that filter on purpose: without them a struck
phrase cannot be located again, and *Report* anchors every finding to where it
was found.

In scope: a `+` line that is a `#` comment or inside `<# #>` in either
installer or under `tools/`; a `//` comment line an installer emits into the
generated theme; `AGENTS.md`, `CLAUDE.md`, `README.md`, every `SKILL.md`; a
comment in `.gitattributes` or `.gitignore`. Out of scope: code, identifiers,
the theme rules themselves, anything under `.tmp/`, and the `Monokai Theme`
clone, which is never edited (`AGENTS.md` → *Rules for Changes*, rule 4).

## Cut

Each category is a test with a yes/no answer. A sentence that is merely long is
not a finding.

| Cut                   | The test                                                             |
| --------------------- | -------------------------------------------------------------------- |
| History lesson        | Does it say what the code, the file or the rule **used to** be?      |
| Route to the decision | Does it narrate how the decision was reached instead of stating it?  |
| Meta-commentary       | Is the subject the prose itself rather than the thing it describes?  |
| The obvious           | Would the code beside it, or the sentence before it, already say so? |
| Second copy           | Does this rationale already have an authoritative home?              |
| Inventory             | Is it a count or a list the file system or the code answers?         |

A *second copy* is replaced by a pointer, `` `AGENTS.md` → *Section* ``, never
deleted outright. An *inventory* goes when nobody reasons about the number; a
constant that carries meaning stays.

## Keep

Cutting these is the failure mode of this pass:

- **The failure mode a rule prevents.** "A malformed theme fails silently and
  Merge falls back, which reads as 'the rule did not work'" is why the JSON
  gate exists, and the reader cannot re-derive it.
- **A measured number.** "`side_bar_container`'s literal painted 140,896 px
  while `details_panel`'s painted 0."
- **A constraint from outside the repository.** Debian's default `awk` is
  `mawk`, which has no interval expressions; Merge hard-codes `layer0` for the
  `dialog` class.
- **The one authoritative statement** of a rationale, at its definition, however
  long it has to be. The fix block both installers emit is the reference example.
- **`AGENTS.md` → *Dead Ends: Do Not Repeat***, which is history by design:
  each entry is a cost paid again by whoever retries it.

## Verify

From the repository root, before reporting:

```powershell
foreach ($f in 'install-monokai-merge.ps1', 'tools/probe-control-tree.ps1') {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $f), [ref] $null, [ref] $errors)
    "$f parse errors: $(@($errors).Count)"
}
Get-Item AGENTS.md, README.md, .claude/skills/*/SKILL.md | Select-Object FullName, Length
```

Then `bash -n install-monokai-merge.sh tools/test-linux.sh` in any bash, which
on Windows is the Debian WSL guest. An edit to a line either installer emits
into the theme changes its output, so it is checked by running the installer:
`tools/test-linux.sh` for the bash one (`AGENTS.md` → *Rules for Changes*,
rule 7), and for the PowerShell one a run that writes into the real
`%AppData%\Sublime Merge`, which needs the user's go-ahead first.

Sizes go against `AGENTS.md` → *Comments and Documentation*. Re-wrap every
paragraph touched to the width the file already uses, 80 columns in every
document here; a half-rewrapped paragraph is a larger diff than the edit inside
it. Say plainly when a command fails for a reason the pass did not cause.

## Report

The counts, because a pass that changed nothing should be visible as such:

```powershell
$s = Get-Content -LiteralPath $State -Raw | ConvertFrom-Json
$add = 0; $del = 0
foreach ($row in git diff $s.Pre --numstat) {
    $a, $d, $null = $row -split "`t"
    if ($a -match '^\d+$') { $add += [int]$a; $del += [int]$d }
}
$words = { Param ($Mark) @(git diff $s.Pre -U0 "--output-indicator-$Mark" |
    Where-Object { $_.StartsWith('~') } |
    ForEach-Object { $_.Substring(1) -split '\s+' | Where-Object { $_ } }).Count }
"lines -$del +$add; words -$(& $words 'old=~') +$(& $words 'new=~')"
```

Every count is against *Scope*'s snapshot, not a bare `git diff`, which would
also see whatever was already uncommitted and credit this pass with someone
else's reductions. Edits to an **untracked** file appear in no diff at all, so
count those by reading the file.

The indicator re-marks one side as `~` and leaves the `--- a/<path>` header
alone, which is the reason for it: filtering the header out by pattern takes
every deleted line beginning `--` with it, a front-matter delimiter or a
horizontal rule, and the files this pass edits most open with `---`.

Present one table (deleted, added, net for lines and words), then the findings
grouped by cut category, each with the struck phrase. Most deleted lines are
rewrites, so the net figure is the real reduction.

## Prove

**Append every file you edit to `$Edited`** as you edit it, one root-relative
path per line with forward slashes (`Add-Content -LiteralPath $Edited
-Value 'AGENTS.md'`). It is the only thing that separates an edit this pass
chose from damage it did not. Then, before reporting:

```powershell
if (-not (Test-Path -LiteralPath $State)) { 'PROOF INCOMPLETE: no capture ran'; return }
$s      = Get-Content -LiteralPath $State -Raw | ConvertFrom-Json
$edited = @(Get-Content -LiteralPath $Edited -ErrorAction SilentlyContinue)
foreach ($d in @($s.Digests)) {
    if ($edited -ccontains $d.Path) { continue }
    $p = Join-Path $s.Root $d.Path
    if ($d.Hash -eq 'absent') { if (Test-Path -LiteralPath $p) { "reappeared: $($d.Path)" } }
    elseif ((git hash-object --no-filters -- $p 2>$null) -ne $d.Hash) { "moved: $($d.Path)" }
}
foreach ($f in & $SplitZ (git -C $s.Root diff $s.Pre --name-only -z)) {
    if ($edited -cnotcontains $f) { "undeclared: $f" }
}
```

Silence is the pass. A name is a file whose bytes moved without this pass
choosing to edit it; `reappeared:` is a file that was deleted when the pass
started and is back. A file edited but never written down is also reported,
which is a false alarm the user sees, and that is the direction this proof has to
fail in.

The two loops cover different files. The digests hold what was dirty or
untracked at capture, which includes a new document no snapshot records. The
snapshot diff reaches a file that was committed and clean, which is most of the
prose this pass edits and none of what the digests hold.

`--no-filters` is what makes the digest a byte comparison. Plain
`git hash-object` runs the file through the clean filters, and under this
repository's `.gitattributes` (`eol=lf`) a file whose line endings the pass
rewrote hashes to the digest it started with.

## Don't

- Don't rewrite a passage no category above caught.
- Don't edit a file whose dirty hunks are not yours, and don't re-wrap a
  paragraph around a foreign sentence; hand the file to the user instead.
- Don't touch code, identifiers or theme rules; a rename is a different ask.
- Don't strip em dashes mechanically (the global `AGENTS.md` → *Output
  Formatting*).
- Don't commit or push.
- Don't report a pass whose *Prove* printed a name; that is a file this pass
  damaged, not a finding to write up.
