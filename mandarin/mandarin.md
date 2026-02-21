# mandarin

> A standalone, manifest-driven installer that reads *.install.json files and performs install, uninstall, check, or list operations for Ruby-based CLI tools.

**Version:** 2.0.0  
**Generated:** 2026-02-21

---

## Purpose

mandarin.rb solves the problem of repeatedly writing bespoke install scripts for each CLI tool by providing a single, reusable installer driven by JSON manifests. It reads manifest files (typically produced by a companion doc_generator.rb) and handles binary installation, man page placement, config file copying, dependency verification, and uninstallation — all controlled by a declarative JSON document rather than hard-coded logic.

## Synopsis

```
mandarin.rb --manifest <file.install.json> <action> [options]
```

## Description

The script parses CLI options via OptionParser, auto-discovers a lone *.install.json if --manifest is not given, then dispatches to one of four action handlers: --install, --uninstall, --check, or --list. All file-system side effects are funnelled through a small set of helper functions (fs_mkdir_p, fs_install, fs_cp, fs_rm, fs_chmod) that respect a --dry-run flag via a central act() gate, ensuring nothing is written during simulation. Dependency checking validates Ruby version via Gem::Version, probes gems with Kernel#gem, tests system binaries with `which`, and inspects environment variables. The --sudo flag prefixes shell commands with sudo for system-wide installs, and --prefix allows overriding the installation root directory at runtime.

## Notable Qualities

The dry-run mode is architecturally clean: every side effect passes through act(), which either yields the block or prints a [DRY] message, so dry-run and real execution share identical code paths. Config files are deliberately never auto-removed during uninstall — a safety-conscious design choice that prevents accidental loss of user customisations. The ANSI colour helpers use 256-colour orange tones (xterm 208/214/130) for branding and degrade gracefully to plain text when stdout is not a TTY.

## Options

| Flag | Description |
|------|-------------|
| `-m, --manifest FILE` | Path to the *.install.json manifest to operate on. Auto-discovered if exactly one exists in cwd. |
| `--install` | Install binary, man pages, config dirs/files, and verify dependencies. |
| `--uninstall` | Remove all installed files (except config files, which are never auto-deleted). |
| `--check` | Verify dependencies and display the install plan without changing anything. |
| `--list` | Print a human-readable summary of the manifest contents. |
| `-n, --dry-run` | Simulate --install or --uninstall: print every action that would be taken without writing or removing anything. |
| `-p, --prefix DIR` | Override the install prefix directory (default: read from manifest or /usr/local). |
| `--sudo` | Prefix file-system and shell commands with sudo for system-wide installs. |
| `--force` | Overwrite existing files that would otherwise block installation. |
| `-v, --verbose` | Show each command as it is executed. |
| `-V, --version` | Print version information and exit. |
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
mandarin.rb -m mytool.install.json --list
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `HOME` | Used to expand ~ in manifest paths (via Dir.home). |

## Files

| Path | Description |
|------|-------------|
| `*.install.json` | JSON manifest file describing the tool to install — binary location, man pages, dependencies, config files, and post-install notes. |

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success — requested action completed without errors. |
| `1` | Blocking dependency issues found, source file missing, file already exists without --force, or other fatal error. |

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

Shell injection is possible if manifest fields contain malicious values, since several paths are interpolated directly into system() calls. Config directories created during install are not removed during uninstall. The --sudo flag shells out rather than using Ruby privilege escalation, so it requires an interactive sudo session. The `which` lookup for system binaries may behave inconsistently across shells and platforms.

## See Also

`install(1)`, `sudo(8)`, `mandb(8)`, `which(1)`, `gem(1)`, `jq(1)`, `ruby(1)`

---

*Generated by [doc_generator.rb](doc_generator.rb)*
