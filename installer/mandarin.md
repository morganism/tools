# mandarin

> A standalone, manifest-driven installer that reads *.install.json files and performs install, uninstall, check, or list operations for CLI tools.

**Version:** 2.0.0  
**Generated:** 2026-02-20

---

## Purpose

mandarin.rb solves the problem of repeatedly writing bespoke install scripts for each CLI tool by providing a single, reusable installer that is driven entirely by a JSON manifest. It exists as a permanent toolbox utility: point it at any *.install.json (produced by a companion doc_generator.rb) and it handles binary installation, man page placement, config file setup, dependency verification, and clean uninstallation.

## Synopsis

```
mandarin.rb --manifest <file.install.json> <action> [options]
```

## Description

The script parses CLI flags with OptionParser, auto-discovers a lone *.install.json in the working directory if --manifest is omitted, and loads the JSON manifest into a Hash. All filesystem side-effects (mkdir, install, cp, rm, chmod) pass through a unified act() gate that respects --dry-run (print-only) and --sudo (prefix commands) flags, ensuring no mutations occur during simulation. Dependency checking inspects Ruby version via Gem::Version, probes gems with Kernel#gem, locates system binaries with `which`, and validates environment variables. The four actions (--install, --uninstall, --check, --list) are dispatched via a case statement, each implemented as a top-level method that walks manifest sections (binary, man_pages, config_dirs, config_files) in order.

## Notable Qualities

The act() helper creates a single chokepoint for every side-effect, making the dry-run mode trivially correct rather than scattering conditionals throughout the code. Config files are deliberately never auto-removed during uninstall — a safety-first design choice that avoids destroying user customisation. ANSI colour output uses 256-colour orange tones (xterm 208/214/130) with graceful tty detection fallback, giving the tool a distinctive 'citrus' visual identity.

## Options

| Flag | Description |
|------|-------------|
| `-m, --manifest FILE` | Path to the *.install.json manifest to operate on. Auto-discovered if exactly one exists in cwd. |
| `--install` | Install binary, man pages, config dirs/files, and verify dependencies. |
| `--uninstall` | Remove all installed files (except config files, which are never auto-deleted). |
| `--check` | Verify dependencies and display the install plan without changing anything. |
| `--list` | Print a human-readable summary of the manifest contents. |
| `-n, --dry-run` | Simulate --install or --uninstall: print every action that would be taken without writing or removing any files. |
| `-p, --prefix DIR` | Override the install prefix directory (default: read from manifest or /usr/local). |
| `--sudo` | Prefix filesystem and shell commands with sudo for privileged installation. |
| `--force` | Overwrite existing files that would otherwise cause the installer to abort. |
| `-v, --verbose` | Show each command as it is executed. |
| `-V, --version` | Print the version string and exit. |
| `-h, --help` | Print usage help and exit. |

## Usage Examples

```sh
mandarin.rb -m mytool.install.json --check
```

```sh
mandarin.rb -m mytool.install.json --install --dry-run
```

```sh
mandarin.rb -m mytool.install.json --install --sudo
```

```sh
mandarin.rb -m mytool.install.json --install --prefix ~/.local --verbose
```

```sh
mandarin.rb -m mytool.install.json --install --force
```

```sh
mandarin.rb -m mytool.install.json --uninstall --dry-run
```

```sh
mandarin.rb --list
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `HOME` | Used to expand ~ in manifest paths (via Dir.home). |

## Files

| Path | Description |
|------|-------------|
| `*.install.json` | JSON manifest file describing the tool to install: binary info, man pages, dependencies, config dirs/files, and post-install notes. |
| `mandarin.rb` | The installer script itself. |

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success — action completed (or dry-run printed) without errors. |
| `1` | Blocking dependency issues found, missing source file, file already exists without --force, or missing/invalid arguments. |

## Dependencies

**Minimum Ruby version:** `3.0`


### System Binaries

| Binary | Package | Status |
|--------|---------|--------|
| `install` | `coreutils` | Required |
| `mandb` | `man-db` | Optional |
| `sudo` | `sudo` | Optional |


## Installation

```sh
# Check dependencies first
ruby mandarin_install.rb --check

# Install (may need --sudo if prefix is system-owned)
ruby mandarin_install.rb --install

# Custom prefix
ruby mandarin_install.rb --install --prefix ~/.local
```

## Bugs / Limitations

Shell injection is possible if manifest fields contain malicious characters, since values are interpolated into system() calls without escaping. The `which` check uses a bare system() call rather than Ruby's built-in File/PATH lookup. Config files are never auto-removed on uninstall, which is intentional but may surprise users expecting a clean teardown.

## See Also

`install(1)`, `json(1)`, `mandb(8)`, `makewhatis(8)`, `sudo(8)`, `gem(1)`, `which(1)`

---

*Generated by [doc_generator.rb](doc_generator.rb)*
