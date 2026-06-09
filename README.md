<p align="center">
  <img src="assets/logo/openssl_chug_logo_1024.png" width="360" alt="OpenSSL Chug logo">
</p>

# OpenSSL Chug

Windows OpenSSL build automation.  
Pick a stable 3.x tag, choose a build (`secure` / `weak` / `fips`), and get a clean, versioned install with zero guesswork!

> Status: v1.0 (working build flow, menus, and MSVC auto-bootstrap)

---

## Why Chug?

- Simple, repeatable builds on Windows (MSVC toolchain)
- Stable-only tags (no alpha/beta/rc) with a minimal menu
- Three builds:  
  - `secure` – default provider only (no legacy)  
  - `weak` – default + legacy provider enabled  
  - `fips` – FIPS provider enabled
- Clean outputs in a predictable tree
- Optional NASM; falls back to `no-asm` automatically
- Optional MSVC auto-bootstrap if you’re not in the native tools shell

> Not in the tools prompt? Chug will try to load `vcvars64.bat` automatically.

---

## Prerequisites

- Git  
- Perl (e.g., Strawberry Perl)  
- Microsoft C++ Build Tools (or run from “x64 Native Tools Command Prompt for VS”)  
- NASM (optional; improves perf, otherwise we build with `no-asm`)

---

## Quick Start

```bat
cd <your>\openssl-chug\bin
openssl-chug.cmd
```

You’ll see three short menus:

1. Select branch/minor (e.g., `openssl-3.5`)
2. Select release tag (e.g., `openssl-3.5.2`)
3. Select build: `secure`, `weak`, or `fips`

At the end you’ll get an OpenSSL ready to use, plus a quick `README.txt` and a sample provider config (`openssl-<build>.cnf`).

---

## Usage

```bat
openssl-chug.cmd [-h|--help] [-v|--verbose]
openssl-chug.cmd [REPO] [INSTALL_ROOT] [-platform x64|x86] [--source|-s] [-v|--verbose]
```

**Arguments**
- `REPO` — path to local OpenSSL git repo. Default: `%USERPROFILE%\Projects\openssl`
- `INSTALL_ROOT` — root for installs/output. Default: `%USERPROFILE%\OpenSSL`

**Options**
- `-platform <x64|x86>` — target architecture (default: `x64`). `x86` is cross-built from an x64 host and runs under WOW64, so no 32-bit machine is needed.
- `-s, --source` — keep the git worktree source under `src` in the output
- `-v, --verbose` — show detailed `[CHUG]` diagnostic logs (default run is quieter)
- `-h, --help` — show help and exit

**Examples**
```bat
openssl-chug.cmd
openssl-chug.cmd -s
openssl-chug.cmd -v
openssl-chug.cmd C:\src\openssl D:\OpenSSL --source -v
```

---

## Paths & Configuration

`openssl-chug.cmd` accepts two optional positional parameters:

```bat
openssl-chug.cmd [REPO] [INSTALL_ROOT]
```

Defaults (if omitted):

- `REPO` → `%USERPROFILE%\Projects\openssl`  
- `INSTALL_ROOT` → `%USERPROFILE%\OpenSSL`

Validation
- **REPO**
  - Chug verifies the OpenSSL repo exists at the path provided
  - If the repo doesn’t exist (or doesn’t look like OpenSSL), you’ll receive an error
- **INSTALL_ROOT**
  - Chug verifies the folder exists at the path provided
  - If the folder doesn’t exist, you’ll be prompted to create it (or run with a path that already exists)

---

## Output Layout

```
%USERPROFILE%\OpenSSL\
  └─ openssl-<MAJOR>.<MINOR>\
     └─ openssl-<MAJOR>.<MINOR>.<PATCH>\
        └─ <build>\                # secure | weak | fips
           └─ <platform>\          # x64 | x86
              ├─ install\          # final install prefix
              │  ├─ bin\
              │  ├─ include\
              │  ├─ lib\
              │  └─ ssl\           # openssl-<build>.cnf (+ fipsmodule.cnf for fips)
              ├─ README.txt        # quickstart written by Chug
              └─ src\              # git worktree at the chosen tag (optional)
```

---

## Notes

- Stable-only releases are presented in menus (no pre-releases)
- If NASM isn’t found, Chug configures OpenSSL with `no-asm`
- If not already in a Visual C++ tools environment, Chug loads the VS build environment via `vcvarsall.bat` for the chosen platform
- `-platform x86` cross-builds 32-bit OpenSSL from an x64 host (no 32-bit machine required) and runs/verifies under WOW64; outputs are kept in a per-platform folder so x64 and x86 never overwrite each other
- `fips` builds also run `fipsinstall` (generating `fipsmodule.cnf`); the generated `openssl-fips.cnf` pulls it in via `.include`

---

## License

MIT — see `LICENSE`.
