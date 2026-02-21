# installer

> A standalone manifest-driven installer that reads *.install.json files and performs install, uninstall, check, or list operations for Ruby-based CLI tools.

**Version:** 2.0.0  
**Generated:** 2026-02-20

---

## Purpose

This script solves the problem of repeatable, consistent installation of Ruby CLI tools by reading a JSON manifest that declares binaries, man pages, config files, dependencies, and environment requirements. It exists so that each tool does not need its own bespoke installer — instead, any tool can ship a standardized .install.json manifest and this single installer handles everything.

## Synopsis

```
installer.rb --manifest <file.install.json> <action> [options]
```

## Description

The script parses CLI options via OptionParser, auto-discovers a lone *.install.json in the current directory if --manifest is not specified, and dispatches to one of four action methods: do_install, do_uninstall, do_check, or do_list. All side-effecting filesystem operations (mkdir, install, cp, rm, chmod) are routed through an act() gate that respects --dry-run mode, --sudo prefixing, and --verbose output. Dependency checking validates Ruby version via Gem::Version, gem availability via Kernel#gem, system binaries via `which`, and environment variables via ENV lookups. ANSI colour output degrades gracefully when stdout is not a TTY.

## Notable Qualities

The act() function acts as a universal side-effect gate — in dry-run mode it prints what would happen without yielding the block, which makes the dry-run guarantee structural rather than ad-hoc. Config files are deliberately never auto-removed during uninstall, which is a safety-first design choice that prevents accidental data loss. The manifest discovery logic will auto-select a single *.install.json in the working directory, reducing friction for single-tool repositories.

## Options

| Flag | Description |
|------|-------------|
| `-m, --manifest FILE` | Path to *.install.json manifest file to operate on |
| `--install` | Install binary, man pages, config dirs/files, and verify dependencies |
| `--uninstall` | Remove all installed files (except config files which are never auto-deleted) |
| `--check` | Verify dependencies and show the install plan without making changes |
| `--list` | Print a human-readable summary of the manifest contents |
| `-n, --dry-run` | Simulate --install or --uninstall: print every action that would be taken without changing anything |
| `-p, --prefix DIR` | Override the install prefix (default: from manifest or /usr/local) |
| `--sudo` | Prefix shell commands with sudo for privileged installs |
| `--force` | Overwrite existing files that would otherwise block installation |
| `-v, --verbose` | Show each command as it is run |
| `-V, --version` | Print version and exit |
| `-h, --help` | Print usage help and exit |

## Usage Examples

```sh
installer.rb -m mytool.install.json --check
```

```sh
installer.rb -m mytool.install.json --install --dry-run
```

```sh
installer.rb -m mytool.install.json --install --sudo
```

```sh
installer.rb -m mytool.install.json --install --prefix ~/.local
```

```sh
installer.rb -m mytool.install.json --install --force --verbose
```

```sh
installer.rb -m mytool.install.json --uninstall --dry-run
```

```sh
installer.rb -m mytool.install.json --list
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `HOME` | Used to expand ~ in manifest paths via Dir.home |
| `PATH` | Used implicitly by `which` when checking system binary dependencies |

## Files

| Path | Description |
|------|-------------|
| `*.install.json` | JSON manifest file describing binaries, man pages, dependencies, config dirs/files, and post-install notes |
| `installer.rb` | The standalone manifest-driven installer script itself |

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success — action completed (or dry-run finished) without blocking issues |
| `1` | Failure — blocking dependency issues, missing source files, already-installed conflict, or corrupt manifest |

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
ruby installer_install.rb --check

# Install (may need --sudo if prefix is system-owned)
ruby installer_install.rb --install

# Custom prefix
ruby installer_install.rb --install --prefix ~/.local
```

## Bugs / Limitations

Shell injection is possible if manifest values contain shell metacharacters, since several commands are built via string interpolation and passed to system(). The fs_rm and fs_mkdir_p helpers do not quote paths. The --sudo flag uses string concatenation rather than a proper privilege escalation mechanism. Config directories created during install are not removed during uninstall.

## See Also

`install(1)`, `mandb(8)`, `makewhatis(8)`, `gem(1)`, `which(1)`, `sudo(8)`, `jq(1)`

---

*Generated by [doc_generator.rb](doc_generator.rb)*
