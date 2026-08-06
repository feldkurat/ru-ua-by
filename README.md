# Combined Russian–Ukrainian–Belarusian keyboard layout

A single keyboard layout that types all three languages without switching input
methods.

## Design

The three ЙЦУКЕН layouts disagree on six keys, and between them need 38 Cyrillic
letters where a standard layout has 33 letter positions. So:

* **The base layer is the stock Russian layout, unchanged.** Russian typing is
  exactly as it always was — nothing moved, nothing to relearn.
* **The five extra letters (і ї є ґ ў) and the apostrophe live on AltGr** (right
  Alt, or Ctrl+Alt). Each sits on the key it occupies in its own national
  layout, so Ukrainian and Belarusian muscle memory mostly carries over.

| Key   | Base | Shift | AltGr | Shift+AltGr | Why that key                  |
|-------|------|-------|-------|-------------|-------------------------------|
| grave | ё    | Ё     | '     | ’           | Ukrainian: apostrophe key     |
| S     | ы    | Ы     | і     | І           | Ukrainian: і replaces ы       |
| B     | и    | И     | і     | І           | Belarusian: і replaces и      |
| O     | щ    | Щ     | ў     | Ў           | Belarusian: ў replaces щ      |
| ]     | ъ    | Ъ     | ї     | Ї           | Ukrainian: ї replaces ъ       |
| '     | э    | Э     | є     | Є           | Ukrainian: є replaces э       |
| U     | г    | Г     | ґ     | Ґ           | mnemonic: ґ is a variant of г |

"grave" is the key left of `1`, carrying ё on this layout.

`і` is deliberately reachable from **both** `S` and `B`, so neither the
Ukrainian nor the Belarusian habit is wrong.

Caps Lock applies to the AltGr letters too, so Caps Lock + `AltGr+S` gives `І`.
The one key excluded is the grave key, whose AltGr pair is the two apostrophe
forms rather than a letter case-pair.

### Punctuation and currency on AltGr

| Key | AltGr     | Shift+AltGr |
|-----|-----------|-------------|
| 4   | ₴ hryvnia | $           |
| 5   | ₽ ruble   | €           |
| 9   | «         | „           |
| 0   | »         | “           |
| -   | – en dash | — em dash   |

### Full base layer

```
ёЁ  1!  2"  3№  4;  5%  6:  7?  8*  9(  0)  -_  =+
     йЙ  цЦ  уУ  кК  еЕ  нН  гГ  шШ  щЩ  зЗ  хХ  ъЪ
      фФ  ыЫ  вВ  аА  пП  рР  оО  лЛ  дД  жЖ  эЭ  \/
       яЯ  чЧ  сС  мМ  иИ  тТ  ьЬ  бБ  юЮ  .,
```

## Repository layout

```
windows/            everything Windows-specific
  install.cmd         install (batch, self-elevating)
  uninstall.cmd       remove  (batch, self-elevating)
  ruuaby.klc          the layout source (MSKLC format, UTF-16LE)
  build.ps1           ruuaby.klc  -> DLLs, via MSKLC's kbdutool.exe
  make-msi.ps1        DLLs        -> MSI packages
  install.ps1         script-based install with dynamic KLID allocation
  enable-layout.ps1   add to the current user's language bar
  uninstall.ps1       script-based removal
  build/
    msi/ruuaby_amd64.msi    installer for 64-bit Windows
    msi/ruuaby_i386.msi     installer for 32-bit Windows
    amd64|wow64|i386/ruuaby.dll   the layout DLLs
    src/ruuaby.C            generated C source — readable form of the key tables
```

# Windows

## Install

Run `windows\install.cmd` — double-click it, or run it from a prompt. It asks
for administrator rights itself, picks the package matching your machine, and
installs it. `windows\uninstall.cmd` removes it again. Neither needs PowerShell.

Then add the layout to your language bar. This part is **per-user**, not
machine-wide, so it is deliberately not done by the installer:

> Settings → Time & language → Language & region → Russian → Options →
> Add a keyboard → "Russian-Ukrainian-Belarusian"

Switch layouts with `Win+Space`. If it does not appear, sign out and back in —
Windows caches the per-user input list.

### Other ways in

Straight to the package, if you prefer:

```powershell
msiexec /i windows\build\msi\ruuaby_amd64.msi     # needs elevation
.\windows\enable-layout.ps1 -Klid a0000419        # per-user; do NOT elevate
```

Or skip the MSI entirely and use the scripts, which allocate the KLID
dynamically so it cannot collide with anything already installed:

```powershell
.\windows\install.ps1        # elevated
.\windows\enable-layout.ps1  # NOT elevated
.\windows\uninstall.ps1
```

`install.ps1` records the KLID it chose in `windows\build\klid.txt`. To offer
the layout under Ukrainian or Belarusian instead of Russian, pass
`-LanguageId 0422` or `-LanguageId 0423`, with a matching `-LanguageTag uk`
or `-LanguageTag be` for `enable-layout.ps1`.

The MSI, by contrast, hardcodes KLID `a0000419` and `Layout Id` `0100`, both
fixed at build time — MSKLC's own setup packages work the same way. `Layout Id`
must be unique among installed layouts; inbox Windows layouts only occupy the
low range, so `0100` is safe in practice. Pass `-Klid`/`-LayoutId` to
`make-msi.ps1` to change them.

### ARM64

Not supported. Layout DLLs must be native to the processor architecture, and
MSKLC cannot build ARM64 layouts, so neither package is usable on an ARM64
machine. `install.cmd` detects this and refuses rather than registering a layout
Windows cannot load.

## Build from source

```powershell
.\windows\build.ps1      # ruuaby.klc -> build\{src,i386,amd64,wow64}
.\windows\make-msi.ps1   # build\*.dll -> build\msi\ruuaby_{amd64,i386}.msi
```

`build.ps1` needs MSKLC installed, for its bundled `kbdutool.exe`.
`make-msi.ps1` needs only Windows itself — it authors the database through the
Windows Installer automation interface and packs the payload with `makecab.exe`.
(It also folds in MSKLC's `inc\_Validation.idt` when MSKLC is present; optional,
but it makes the package well formed for ICE validation tools.)

MSKLC's GUI can produce a setup package of its own — **File → Load Source File**
→ `ruuaby.klc` → **Project → Build DLL and Setup Package**. Its `-build`
command-line switch is *not* a headless equivalent: it opens the GUI and waits,
which is why `make-msi.ps1` exists.

## Verifying a build

`windows/build/src/ruuaby.C` is what `kbdutool` generates from the `.klc`, and
is the clearest way to confirm the key tables: the `aVkToWch5` array lists every
key with its five shift states (base, Shift, Ctrl, Ctrl+Alt, Shift+Ctrl+Alt),
and the `CAPLOK | CAPLOKALTGR` flags mark the keys where Caps Lock reaches the
AltGr layer.

The MSIs can be checked without installing anything, since their
`AdminExecuteSequence` is populated:

```powershell
msiexec /a windows\build\msi\ruuaby_i386.msi /qn TARGETDIR=C:\some\empty\dir
```

That extracts the payload and exercises costing and validation. The amd64
package extracts only one `ruuaby.dll` this way — an administrative install
collapses `System64Folder` and `SystemFolder` into `TARGETDIR`, so both builds
land on the same name. In a real install they go to `System32` and `SysWOW64`
respectively.

To check an *installed* layout end to end, load it by KLID and query it through
`ToUnicodeEx`, which exercises the OS translation path rather than the source
file. Watch the marshalling: declare the output buffer as `CharSet.Unicode`, or
every result comes back as the low byte of the real codepoint (`ы` U+044B reads
as `K`).

Two gotchas if you edit `make-msi.ps1`. The MSI `Version` column rejects the
comma-separated form `1, 0, 3, 40` carried in `kbdutool`'s version resource: it
must be dotted-numeric, or Windows Installer fails with error 2725. And a
freshly written MSI stays file-locked briefly after the building process exits,
so run `msiexec` against it from a separate process.
