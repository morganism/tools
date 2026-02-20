# doc_generator

> AI-powered documentation and installer generator that analyses a Ruby script via the Anthropic Claude API and produces Markdown docs, plain-text usage, a groff man page, an install manifest, and a self-contained installer script.

**Version:** 2.0.0  
**Generated:** 2026-02-20

---

## Purpose

Writing comprehensive documentation, man pages, and install tooling for command-line Ruby scripts is tedious and error-prone. doc_generator.rb automates the entire pipeline by sending the target script's source to the Anthropic API, receiving a structured JSON analysis, and rendering five ready-to-use output files from that single response. This lets developers ship well-documented, easily installable CLI tools with minimal manual effort.

## Synopsis

```
doc_generator.rb [options] <script.rb>
```

## Description

The script reads the target Ruby file, constructs a detailed prompt requesting both documentation metadata and an install manifest in a single JSON object, and posts it to the Anthropic Messages API over HTTPS using only Ruby stdlib (net/http, json, optparse, fileutils, date). The raw JSON response is stripped of any accidental markdown fences, parsed, and fed into five generator functions: generate_markdown produces a GitHub Wiki page with tables for options, environment variables, exit codes, and dependencies; generate_usage emits a fixed-width plain-text help file; generate_man builds a complete groff/troff man page with proper .TH/.SH macros; generate_manifest normalises and pretty-prints the install manifest JSON; and generate_installer emits a fully self-contained Ruby installer that embeds the manifest as a constant and supports --install, --uninstall, --check, and --dry-run. All generators are pure string-template functions with no external template engine, keeping the tool zero-dependency beyond Ruby stdlib.

## Notable Qualities

The entire documentation and install metadata extraction is done in a single API call — the prompt is carefully structured so Claude returns both docs and a machine-readable install manifest in one JSON blob, avoiding multiple round-trips. The generated installer script is itself a complete, runnable Ruby program with ANSI colour output, sudo support, dry-run simulation via a unified act() gate function, and config-file-safe uninstallation (config files are never auto-deleted). The groff escaping lambda handles leading-dot lines and backslashes to prevent troff interpretation errors, a subtle but important detail for correct man page rendering.

## Options

| Flag | Description |
|------|-------------|
| `-o, --output DIR` | Output directory for all generated files (default: current directory) |
| `-s, --section NUM` | Man page section number, 1-8 (default: 1) |
| `-a, --author NAME` | Author name used in the man page and installer metadata |
| `-p, --prefix DIR` | Install prefix for the generated installer (default: /usr/local) |
| `-v, --verbose` | Print progress messages to stderr during generation |
| `-V, --version` | Print version string and exit |
| `-h, --help` | Show usage help and exit |

## Usage Examples

```sh
doc_generator.rb my_tool.rb
```

```sh
doc_generator.rb -o ./docs -a 'Jane Doe' my_tool.rb
```

```sh
doc_generator.rb -s 8 -v admin_tool.rb
```

```sh
doc_generator.rb -o /tmp/out --prefix ~/.local my_tool.rb
```

```sh
doc_generator.rb -p /usr/local -a 'Morganism' json_store.rb
```

```sh
ANTHROPIC_API_KEY=sk-ant-xxx doc_generator.rb -o ./docs -v script.rb
```

```sh
doc_generator.rb --version
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Required. Anthropic API key used to authenticate requests to the Claude API. |
| `USER` | Optional. Used as the default author name if --author is not specified. |

## Files

| Path | Description |
|------|-------------|
| `<name>.md` | Generated GitHub Wiki Markdown documentation page |
| `<name>_usage.txt` | Generated plain-text usage/help file |
| `<name>.<section>` | Generated groff/troff man page |
| `<name>.install.json` | Generated JSON install manifest |
| `<name>_install.rb` | Generated self-contained Ruby installer script (chmod 0755) |

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success — all output files generated |
| `1` | Error — missing argument, file not found, missing API key, invalid man section, API failure, or JSON parse failure |

## Dependencies

**Minimum Ruby version:** `3.0`


### System Binaries

| Binary | Package | Status |
|--------|---------|--------|
| `groff` | `groff` | Optional |
| `mandb` | `man-db` | Optional |


## Installation

```sh
# Check dependencies first
ruby doc_generator_install.rb --check

# Install (may need --sudo if prefix is system-owned)
ruby doc_generator_install.rb --install

# Custom prefix
ruby doc_generator_install.rb --install --prefix ~/.local
```

## Bugs / Limitations

The script relies on the AI model returning well-formed JSON matching the expected schema; malformed or incomplete responses will cause a parse error or missing keys. The groff escaping lambda does not handle all possible troff special characters (e.g. single quotes in certain macro contexts). There is no retry logic or rate-limit handling for the API call, and the 120-second read timeout may be insufficient for very large scripts with the chosen model.

## See Also

`groff(1)`, `man(1)`, `ruby(1)`, `curl(1)`, `jq(1)`, `mandb(8)`

---

*Generated by [doc_generator.rb](doc_generator.rb)*
