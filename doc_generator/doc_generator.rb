#!/usr/bin/env ruby
# frozen_string_literal: true
#
# doc_generator.rb — AI-powered documentation + installer generator
#
# Reads a Ruby script, sends it to the Anthropic API for analysis,
# then generates:
#   - A GitHub Wiki Markdown page      (<n>.md)
#   - A Usage.txt for -h/--help        (<n>_usage.txt)
#   - A groff/troff man page           (<n>.<section>)
#   - An install manifest              (<n>.install.json)
#   - A self-contained installer       (<n>_install.rb)
#
# Requires: ANTHROPIC_API_KEY in environment
# Deps:     net/http, json (both stdlib — no gems required)

require 'net/http'
require 'json'
require 'optparse'
require 'fileutils'
require 'date'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

VERSION     = '2.0.0'
SCRIPT_NAME = File.basename($PROGRAM_NAME)
API_URL     = URI('https://api.anthropic.com/v1/messages')
API_MODEL   = 'claude-opus-4-6'
API_VERSION = '2023-06-01'
MAX_TOKENS  = 6144   # bumped — manifest adds to response size

# ---------------------------------------------------------------------------
# CLI option parsing
# ---------------------------------------------------------------------------

options = {
  output_dir:  '.',
  man_section: '1',
  author:      ENV['USER'] || 'Unknown',
  prefix:      '/usr/local',
  verbose:     false
}

parser = OptionParser.new do |o|
  o.banner = "Usage: #{SCRIPT_NAME} [options] <script.rb>"

  o.separator ''
  o.separator 'Options:'

  o.on('-o', '--output DIR', 'Output directory (default: current dir)') do |d|
    options[:output_dir] = d
  end

  o.on('-s', '--section NUM', '1-8', 'Man page section number (default: 1)') do |s|
    abort "Invalid man section: #{s}" unless ('1'..'8').include?(s)
    options[:man_section] = s
  end

  o.on('-a', '--author NAME', 'Author name for man page and installer') do |a|
    options[:author] = a
  end

  o.on('-p', '--prefix DIR', 'Install prefix for generated installer (default: /usr/local)') do |p|
    options[:prefix] = p
  end

  o.on('-v', '--verbose', 'Print progress to stderr') do
    options[:verbose] = true
  end

  o.on('-V', '--version', 'Print version and exit') do
    puts "#{SCRIPT_NAME} v#{VERSION}"
    exit
  end

  o.on('-h', '--help', 'Show this help') do
    puts o
    exit
  end

  o.separator ''
  o.separator 'Examples:'
  o.separator "  #{SCRIPT_NAME} json_store.rb"
  o.separator "  #{SCRIPT_NAME} -o ./docs -a 'Morganism' -p /usr/local my_tool.rb"
  o.separator "  #{SCRIPT_NAME} -s 8 -v admin_tool.rb"
  o.separator "  #{SCRIPT_NAME} -o /tmp/out --prefix ~/.local my_tool.rb"
  o.separator ''
  o.separator 'Environment:'
  o.separator '  ANTHROPIC_API_KEY   Required. Your Anthropic API key.'
  o.separator ''
  o.separator 'Output files (written to --output DIR):'
  o.separator '  <n>.md               GitHub Wiki Markdown'
  o.separator '  <n>_usage.txt        Plain-text help'
  o.separator '  <n>.<section>        Groff man page'
  o.separator '  <n>.install.json     Install manifest'
  o.separator '  <n>_install.rb       Self-contained installer script'
end

parser.parse!

if ARGV.empty?
  warn "#{SCRIPT_NAME}: error: no script file specified"
  warn parser.banner
  exit 1
end

target = ARGV.shift

unless File.exist?(target)
  warn "#{SCRIPT_NAME}: error: file not found: #{target}"
  exit 1
end

api_key = ENV['ANTHROPIC_API_KEY']
if api_key.nil? || api_key.strip.empty?
  warn "#{SCRIPT_NAME}: error: ANTHROPIC_API_KEY is not set"
  exit 1
end

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log(msg, verbose)
  warn "  => #{msg}" if verbose
end

def slug(path)
  File.basename(path, '.*')
end

# ---------------------------------------------------------------------------
# Anthropic API call
# ---------------------------------------------------------------------------

def call_anthropic(api_key, prompt, verbose)
  log('Calling Anthropic API...', verbose)

  body = {
    model:      API_MODEL,
    max_tokens: MAX_TOKENS,
    messages:   [{ role: 'user', content: prompt }]
  }

  req = Net::HTTP::Post.new(API_URL)
  req['Content-Type']      = 'application/json'
  req['x-api-key']         = api_key
  req['anthropic-version'] = API_VERSION
  req.body = JSON.generate(body)

  http              = Net::HTTP.new(API_URL.host, API_URL.port)
  http.use_ssl      = true
  http.read_timeout = 120

  res = http.request(req)
  abort "API error #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

  data = JSON.parse(res.body)
  data.dig('content', 0, 'text') || abort('Unexpected API response structure')
end

# ---------------------------------------------------------------------------
# Prompt — single API call returns docs + install manifest in one JSON blob
# ---------------------------------------------------------------------------

def analysis_prompt(source, script_name, man_section, prefix)
  <<~PROMPT
    You are a senior Ruby developer, Linux systems administrator, and technical writer.

    Analyse the Ruby script named "#{script_name}" below and return a single JSON
    object. Do NOT include markdown fences — raw JSON only. No preamble, no commentary.

    The JSON must contain ALL of these top-level keys:

    ── Documentation keys ──────────────────────────────────────────────────────

      "description"    — One sentence: what the script does
      "purpose"        — 2-3 sentences: problem solved, why it exists
      "implementation" — 3-5 sentences: internals, key design choices
      "interesting"    — 2-3 sentences: notable techniques or non-obvious behaviours
      "synopsis"       — Short synopsis e.g. "script.rb [options] <file>"
      "options"        — Array of { "flag": "-x, --example VAR", "description": "..." }
      "examples"       — Array of 5-7 realistic shell usage example strings
      "exit_codes"     — Array of { "code": 0, "meaning": "Success" }
      "environment"    — Array of { "var": "NAME", "description": "..." }
      "files"          — Array of { "path": "file.ext", "description": "..." }
      "see_also"       — Array of related commands e.g. "jq(1)", "curl(1)"
      "bugs"           — String: known limitations or "None known."

    ── Install manifest keys ────────────────────────────────────────────────────

      "install" — Object with these keys:

        "binary" — Object:
          "source"      — filename as it exists in the source tree (e.g. "#{script_name}")
          "target"      — installed name without extension (e.g. "#{slug(script_name)}")
          "destination" — install dir, default "#{prefix}/bin"
          "chmod"       — octal string e.g. "0755"

        "man_pages" — Array of objects:
          { "source": "#{slug(script_name)}.#{man_section}",
            "section": "#{man_section}",
            "destination": "#{prefix}/share/man/man#{man_section}" }

        "dependencies" — Object:
          "ruby_version"  — minimum Ruby version string e.g. "3.0"
          "gems"          — Array of { "name": "gemname", "version": ">= 1.0", "optional": false }
          "system_bins"   — Array of { "bin": "jq", "package": "jq", "optional": false }
                            (binaries checked with `which`; package is the apt/brew name)

        "environment" — Array of:
          { "var": "NAME", "required": true, "description": "...",
            "suggest_export": "export NAME=value_hint" }
          (required=true means installer warns loudly if unset)

        "config_dirs" — Array of:
          { "path": "~/.config/toolname", "mode": "0700", "description": "..." }

        "config_files" — Array of:
          { "source": "example.conf", "destination": "~/.config/toolname/config",
            "mode": "0600", "description": "...", "skip_if_exists": true }
          Only list files that physically exist in the source tree.

        "post_install_notes" — Array of human-readable strings for manual post-install steps
        "uninstall_notes"    — Array of human-readable strings for manual uninstall steps

    Script source:
    ```ruby
    #{source}
    ```
  PROMPT
end

# ---------------------------------------------------------------------------
# Document generators
# ---------------------------------------------------------------------------

def generate_markdown(info, script_name, version)
  name = slug(script_name)
  date = Date.today.iso8601

  examples_md = info['examples'].map { |e| "```sh\n#{e}\n```" }.join("\n\n")
  options_md  = info['options'].map  { |o| "| `#{o['flag']}` | #{o['description']} |" }.join("\n")
  env_md      = Array(info['environment']).map { |e| "| `#{e['var']}` | #{e['description']} |" }.join("\n")
  files_md    = Array(info['files']).map       { |f| "| `#{f['path']}` | #{f['description']} |" }.join("\n")
  exit_md     = Array(info['exit_codes']).map  { |e| "| `#{e['code']}` | #{e['meaning']} |" }.join("\n")
  see_also    = Array(info['see_also']).map    { |s| "`#{s}`" }.join(', ')

  inst    = info['install'] || {}
  dep     = inst['dependencies'] || {}
  gems    = Array(dep['gems']).map        { |g| "| `#{g['name']}` | `#{g['version']}` | #{g['optional'] ? 'Optional' : 'Required'} |" }.join("\n")
  sysbins = Array(dep['system_bins']).map { |b| "| `#{b['bin']}` | `#{b['package']}` | #{b['optional'] ? 'Optional' : 'Required'} |" }.join("\n")

  <<~MD
    # #{name}

    > #{info['description']}

    **Version:** #{version}  
    **Generated:** #{date}

    ---

    ## Purpose

    #{info['purpose']}

    ## Synopsis

    ```
    #{info['synopsis']}
    ```

    ## Description

    #{info['implementation']}

    ## Notable Qualities

    #{info['interesting']}

    ## Options

    | Flag | Description |
    |------|-------------|
    #{options_md}

    ## Usage Examples

    #{examples_md}

    ## Environment Variables

    | Variable | Description |
    |----------|-------------|
    #{env_md.empty? ? '| — | None required |' : env_md}

    ## Files

    | Path | Description |
    |------|-------------|
    #{files_md.empty? ? '| — | None |' : files_md}

    ## Exit Codes

    | Code | Meaning |
    |------|---------|
    #{exit_md}

    ## Dependencies

    **Minimum Ruby version:** `#{dep['ruby_version'] || 'Not specified'}`

    #{gems.empty? ? '' : "### Gems\n\n| Gem | Version | Status |\n|-----|---------|--------|\n#{gems}\n"}
    #{sysbins.empty? ? '' : "### System Binaries\n\n| Binary | Package | Status |\n|--------|---------|--------|\n#{sysbins}\n"}

    ## Installation

    ```sh
    # Check dependencies first
    ruby #{name}_install.rb --check

    # Install (may need --sudo if prefix is system-owned)
    ruby #{name}_install.rb --install

    # Custom prefix
    ruby #{name}_install.rb --install --prefix ~/.local
    ```

    ## Bugs / Limitations

    #{info['bugs']}

    ## See Also

    #{see_also.empty? ? 'None' : see_also}

    ---

    *Generated by [doc_generator.rb](doc_generator.rb)*
  MD
end

def generate_usage(info, script_name, version)
  name  = slug(script_name)
  width = 78
  ruler = '-' * width

  options_block  = info['options'].map { |o| "  #{o['flag'].ljust(26)}#{o['description']}" }.join("\n")
  examples_block = info['examples'].map { |e| "  #{e}" }.join("\n\n")
  env_block      = Array(info['environment']).map { |e| "  #{e['var'].ljust(26)}#{e['description']}" }.join("\n")
  exit_block     = Array(info['exit_codes']).map  { |e| "  #{e['code'].to_s.ljust(6)}#{e['meaning']}" }.join("\n")
  see_also       = Array(info['see_also']).join(', ')

  <<~USAGE
    #{name} v#{version}

    #{ruler}
    DESCRIPTION
    #{ruler}

    #{info['purpose'].gsub(/(.{1,#{width}})(\s+|\z)/, "  \\1\n").rstrip}

    #{ruler}
    SYNOPSIS
    #{ruler}

      #{info['synopsis']}

    #{ruler}
    OPTIONS
    #{ruler}

    #{options_block}

    #{ruler}
    EXAMPLES
    #{ruler}

    #{examples_block}

    #{ruler}
    ENVIRONMENT
    #{ruler}

    #{env_block.empty? ? '  None required.' : env_block}

    #{ruler}
    EXIT CODES
    #{ruler}

    #{exit_block}

    #{ruler}
    BUGS / LIMITATIONS
    #{ruler}

      #{info['bugs']}

    #{ruler}
    SEE ALSO
    #{ruler}

      #{see_also.empty? ? 'None' : see_also}

    #{ruler}
    IMPLEMENTATION NOTES
    #{ruler}

    #{info['interesting'].gsub(/(.{1,#{width}})(\s+|\z)/, "  \\1\n").rstrip}

  USAGE
end

def generate_man(info, script_name, section, author, version)
  name    = slug(script_name).upcase
  date    = Date.today.strftime('%B %Y')
  package = "#{slug(script_name)} #{version}"

  esc = ->(str) { str.to_s.gsub('\\', '\\\\').gsub(/^\./, '\\&.') }

  options_groff = info['options'].map { |o| ".TP\n.B #{esc.(o['flag'])}\n#{esc.(o['description'])}" }.join("\n")

  examples_groff = info['examples'].each_with_index.map do |e, i|
    ".PP\n.B Example #{i + 1}:\n.PP\n.RS 4\n.EX\n#{esc.(e)}\n.EE\n.RE"
  end.join("\n")

  env_groff   = Array(info['environment']).map { |e| ".TP\n.B #{esc.(e['var'])}\n#{esc.(e['description'])}" }.join("\n")
  files_groff = Array(info['files']).map       { |f| ".TP\n.I #{esc.(f['path'])}\n#{esc.(f['description'])}" }.join("\n")
  exit_groff  = Array(info['exit_codes']).map  { |e| ".TP\n.B #{esc.(e['code'])}\n#{esc.(e['meaning'])}" }.join("\n")

  see_also_groff = Array(info['see_also']).map do |s|
    s =~ /^(.+)\((\d)\)$/ ? ".BR #{$1} (#{$2})" : ".B #{esc.(s)}"
  end.join(",\n")

  inst    = info['install'] || {}
  dep     = inst['dependencies'] || {}
  gems    = Array(dep['gems'])
  sysbins = Array(dep['system_bins'])

  dep_groff = ''
  unless gems.empty? && sysbins.empty?
    dep_groff  = ".SS Ruby Gems\n"
    dep_groff += gems.map { |g| ".TP\n.B #{g['name']} #{g['version']}\n#{g['optional'] ? 'Optional' : 'Required'}" }.join("\n") unless gems.empty?
    dep_groff += "\n.SS System Binaries\n"
    dep_groff += sysbins.map { |b| ".TP\n.B #{b['bin']}\nPackage: #{b['package']}. #{b['optional'] ? 'Optional' : 'Required'}" }.join("\n") unless sysbins.empty?
  end

  <<~MAN
    .TH #{name} #{section} "#{date}" "#{package}" "User Commands"
    .\"
    .\" Generated by doc_generator.rb v#{VERSION}
    .\"
    .SH NAME
    #{slug(script_name)} \\- #{esc.(info['description'])}
    .SH SYNOPSIS
    .B #{esc.(info['synopsis'])}
    .SH DESCRIPTION
    #{esc.(info['purpose'])}
    .PP
    #{esc.(info['implementation'])}
    .SH OPTIONS
    #{options_groff}
    .SH EXAMPLES
    #{examples_groff}
    .SH ENVIRONMENT
    #{env_groff.empty? ? 'No environment variables required.' : env_groff}
    .SH FILES
    #{files_groff.empty? ? 'No files used.' : files_groff}
    .SH DEPENDENCIES
    Requires Ruby #{dep['ruby_version'] || '2.7'}+.
    #{dep_groff.empty? ? 'No additional dependencies.' : dep_groff}
    .SH "EXIT STATUS"
    #{exit_groff}
    .SH BUGS
    #{esc.(info['bugs'])}
    .SH NOTES
    #{esc.(info['interesting'])}
    .SH "SEE ALSO"
    #{see_also_groff.empty? ? 'None.' : see_also_groff}
    .SH AUTHOR
    #{esc.(author)}
    .PP
    Documentation generated by
    .BR doc_generator.rb .
  MAN
end

# ---------------------------------------------------------------------------
# Install manifest — written from the 'install' key returned by the API
# ---------------------------------------------------------------------------

def generate_manifest(info, script_name, version, author, man_section, prefix)
  inst = info['install'] || {}

  # Fill in anything Claude left blank
  inst['name']    = slug(script_name)
  inst['version'] = version
  inst['author']  = author

  bin_info = inst['binary'] ||= {}
  bin_info['source']      ||= script_name
  bin_info['target']      ||= slug(script_name)
  bin_info['destination'] ||= "#{prefix}/bin"
  bin_info['chmod']       ||= '0755'

  if Array(inst['man_pages']).empty?
    inst['man_pages'] = [{
      'source'      => "#{slug(script_name)}.#{man_section}",
      'section'     => man_section,
      'destination' => "#{prefix}/share/man/man#{man_section}"
    }]
  end

  inst['dependencies'] ||= { 'ruby_version' => '3.0', 'gems' => [], 'system_bins' => [] }
  inst['environment']  ||= []
  inst['config_dirs']  ||= []
  inst['config_files'] ||= []
  inst['post_install_notes'] ||= []
  inst['uninstall_notes']    ||= []

  JSON.pretty_generate(inst)
end

# ---------------------------------------------------------------------------
# Installer script — self-contained, embeds the manifest as a constant
# ---------------------------------------------------------------------------

def generate_installer(info, script_name, version)
  inst     = info['install'] || {}
  embedded = JSON.generate(inst)
  base     = slug(script_name)

  <<~INSTALLER
    #!/usr/bin/env ruby
    # frozen_string_literal: true
    #
    # #{base}_install.rb — self-contained installer for #{script_name} v#{version}
    #
    # Generated by doc_generator.rb. The MANIFEST constant below is the
    # source of truth — also available as #{base}.install.json.
    # To regenerate: ruby doc_generator.rb #{script_name}

    require 'fileutils'
    require 'json'
    require 'optparse'

    MANIFEST = JSON.parse(<<~'JSON')
    #{embedded}
    JSON

    VERSION     = #{version.inspect}
    SCRIPT_NAME = File.basename($PROGRAM_NAME)

    # ANSI colour helpers — degrade gracefully if stdout is not a tty
    COLOUR = $stdout.tty?
    def ansi(code, str) = COLOUR ? "\\e[\#{code}m\#{str}\\e[0m" : str
    def ok(msg)    = puts "  \#{ansi('32',  '✔')}  \#{msg}"
    def warn_(msg) = puts "  \#{ansi('33',  '⚠')}  \#{msg}"   # warn_ avoids clobbering Kernel#warn
    def err(msg)   = puts "  \#{ansi('31',  '✘')}  \#{msg}"
    def info(msg)  = puts "  \#{ansi('34',  '→')}  \#{msg}"
    def dry(msg)   = puts "  \#{ansi('36', '[DRY]')}  \#{msg}" # cyan — would-do actions

    options = {
      action:   nil,
      prefix:   MANIFEST.dig('binary', 'destination')&.then { |d| File.dirname(d) } || '/usr/local',
      sudo:     false,
      force:    false,
      dry_run:  false,
      verbose:  false
    }

    parser = OptionParser.new do |o|
      o.banner = "Usage: \#{SCRIPT_NAME} <action> [options]"
      o.separator ''
      o.separator 'Actions (required, pick one):'
      o.on('--install',   'Install binary, man page, verify deps')  { options[:action] = :install   }
      o.on('--uninstall', 'Remove all installed files')              { options[:action] = :uninstall }
      o.on('--check',     'Verify dependencies only (no file ops)')  { options[:action] = :check     }
      o.separator ''
      o.separator 'Options:'
      o.on('-n', '--dry-run',
           'Simulate --install or --uninstall: print every action',
           'that WOULD be taken without changing anything on disk.') { options[:dry_run] = true }
      o.on('-p', '--prefix DIR',
           "Install prefix (default: \#{options[:prefix]})") { |d| options[:prefix] = d }
      o.on('--sudo',    'Prefix shell commands with sudo')  { options[:sudo]    = true }
      o.on('--force',   'Overwrite existing files')         { options[:force]   = true }
      o.on('-v', '--verbose', 'Show each command as run')   { options[:verbose] = true }
      o.on('-V', '--version') { puts "\#{SCRIPT_NAME} v\#{VERSION}"; exit }
      o.on('-h', '--help')    { puts o; exit }
      o.separator ''
      o.separator 'Examples:'
      o.separator "  \#{SCRIPT_NAME} --install --dry-run          # simulate install, touch nothing"
      o.separator "  \#{SCRIPT_NAME} --install --prefix ~/.local  # install to home prefix"
      o.separator "  \#{SCRIPT_NAME} --install --sudo             # install to system prefix"
      o.separator "  \#{SCRIPT_NAME} --uninstall --dry-run        # see what uninstall would remove"
      o.separator "  \#{SCRIPT_NAME} --check                      # dep check only"
    end

    parser.parse!

    if options[:action].nil?
      warn "\#{SCRIPT_NAME}: error: specify --install, --uninstall, or --check"
      abort parser.banner
    end

    if options[:dry_run] && options[:action] == :check
      warn "\#{SCRIPT_NAME}: --dry-run has no effect with --check (--check is already non-destructive)"
      options[:dry_run] = false
    end

    # ---------------------------------------------------------------------------
    # Core helpers
    # ---------------------------------------------------------------------------

    def expand_path(path, prefix)
      path.to_s.sub('~', Dir.home).sub('{prefix}', prefix)
    end

    def bin_available?(name)
      system("which \#{name} >/dev/null 2>&1")
    end

    # act() is the single gate for all side-effecting operations.
    #
    # In normal mode:  runs the block, prints label on verbose.
    # In dry-run mode: prints what would happen — block is NEVER called.
    #
    # Usage:
    #   act("install /foo/bar", dry_run: opts[:dry_run], verbose: opts[:verbose]) do
    #     FileUtils.cp(src, dst)
    #   end
    def act(description, dry_run:, verbose:, sudo_prefix: nil)
      prefix_str = sudo_prefix ? "sudo " : ""
      if dry_run
        dry "\#{prefix_str}\#{description}"
      else
        puts "    \#{prefix_str}\#{description}" if verbose
        yield
      end
    end

    # Thin wrapper for shell commands routed through act()
    def sh(cmd, opts)
      act(cmd, dry_run: opts[:dry_run], verbose: opts[:verbose],
          sudo_prefix: opts[:sudo] ? true : nil) do
        full = opts[:sudo] ? "sudo \#{cmd}" : cmd
        system(full) || abort("Command failed: \#{full}")
      end
    end

    # FileUtils wrappers — all routed through act() so dry-run is uniform
    def fs_mkdir_p(dir, opts)
      act("mkdir -p \#{dir}", dry_run: opts[:dry_run], verbose: opts[:verbose],
          sudo_prefix: opts[:sudo] ? true : nil) do
        if opts[:sudo]
          system("sudo mkdir -p \#{dir}") || abort("mkdir failed: \#{dir}")
        else
          FileUtils.mkdir_p(dir)
        end
      end
    end

    def fs_install(src, dst, chmod, opts)
      act("install -m \#{chmod} \#{src} \#{dst}",
          dry_run: opts[:dry_run], verbose: opts[:verbose],
          sudo_prefix: opts[:sudo] ? true : nil) do
        sh_cmd = "install -m \#{chmod} \#{src} \#{dst}"
        full   = opts[:sudo] ? "sudo \#{sh_cmd}" : sh_cmd
        system(full) || abort("install failed: \#{src} → \#{dst}")
      end
    end

    def fs_cp(src, dst, mode, opts)
      act("cp \#{src} \#{dst}  (mode \#{mode})",
          dry_run: opts[:dry_run], verbose: opts[:verbose]) do
        FileUtils.mkdir_p(File.dirname(dst))
        FileUtils.cp(src, dst)
        FileUtils.chmod(mode.to_i(8), dst)
      end
    end

    def fs_rm(path, opts)
      act("rm \#{path}", dry_run: opts[:dry_run], verbose: opts[:verbose],
          sudo_prefix: opts[:sudo] ? true : nil) do
        if opts[:sudo]
          system("sudo rm \#{path}") || abort("rm failed: \#{path}")
        else
          FileUtils.rm(path)
        end
      end
    end

    def fs_chmod(path, mode, opts)
      act("chmod \#{mode} \#{path}", dry_run: opts[:dry_run], verbose: opts[:verbose]) do
        FileUtils.chmod(mode.to_i(8), path)
      end
    end

    # ---------------------------------------------------------------------------
    # Dependency check — used by --check and --install (also --install --dry-run)
    # Deps are ALWAYS checked for real, even in dry-run — that's the whole point.
    # Returns array of blocking issue strings.
    # ---------------------------------------------------------------------------

    def check_deps(manifest)
      dep    = manifest['dependencies'] || {}
      issues = []

      min = dep['ruby_version'] || '2.7'
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new(min)
        err "Ruby \#{min}+ required, running \#{RUBY_VERSION}"
        issues << :ruby_version
      else
        ok "Ruby \#{RUBY_VERSION} >= \#{min}"
      end

      Array(dep['gems']).each do |g|
        begin
          gem g['name'], g['version'] || '>= 0'
          ok "gem \#{g['name']} \#{g['version']}"
        rescue Gem::LoadError
          label = "gem \#{g['name']} \#{g['version']}"
          if g['optional']
            warn_ "\#{label} not installed (optional)"
          else
            err   "\#{label} missing — run: gem install \#{g['name']}"
            issues << "gem:\#{g['name']}"
          end
        end
      end

      Array(dep['system_bins']).each do |b|
        if bin_available?(b['bin'])
          ok "binary \#{b['bin']} found"
        elsif b['optional']
          warn_ "binary \#{b['bin']} not found (optional) — apt/brew install \#{b['package']}"
        else
          err   "binary \#{b['bin']} not found — install: \#{b['package']}"
          issues << "bin:\#{b['bin']}"
        end
      end

      Array(manifest['environment']).each do |e|
        val = ENV[e['var']]
        if val && !val.strip.empty?
          ok "env \#{e['var']} set"
        elsif e['required']
          err "env \#{e['var']} not set — \#{e['description']}"
          warn_("  Hint: \#{e['suggest_export']}  → add to ~/.bashrc") if e['suggest_export']
          issues << "env:\#{e['var']}"
        else
          warn_ "env \#{e['var']} not set (optional) — \#{e['description']}"
        end
      end

      issues
    end

    # ---------------------------------------------------------------------------
    # --install  (also handles --install --dry-run)
    # ---------------------------------------------------------------------------

    def do_install(manifest, opts)
      prefix  = opts[:prefix]
      dry_run = opts[:dry_run]

      banner = dry_run ? "DRY-RUN — no files will be written" : "Installing \#{manifest['name']} v\#{manifest['version']}"
      puts "\\n=== \#{banner} ===\\n"

      puts "\\n--- Dependency check (always live, even in dry-run) ---"
      issues = check_deps(manifest)

      unless issues.empty?
        err "Blocking issues — fix before installing:"
        issues.each { |i| err "  \#{i}" }
        # In dry-run we warn but continue so the full plan is visible
        exit 1 unless dry_run
        warn_ "Continuing dry-run despite issues so you can see the full plan..."
      end

      # Binary
      bin     = manifest['binary'] || {}
      src     = bin['source'].to_s
      dst_dir = expand_path(bin['destination'] || "\#{prefix}/bin", prefix)
      dst     = File.join(dst_dir, bin['target'] || File.basename(src, '.*'))
      chmod   = bin['chmod'] || '0755'

      puts "\\n--- Binary ---"
      unless File.exist?(src)
        # In dry-run we note the missing source but continue showing the plan
        if dry_run
          warn_ "Source not found: \#{src} — in a real install this would abort here"
        else
          abort "  \#{ansi('31','✘')}  Source not found: \#{src}"
        end
      end

      if !dry_run && File.exist?(dst) && !opts[:force]
        err "Already installed: \#{dst}  (use --force to overwrite)"
        exit 1
      end

      info "Would install: \#{src} → \#{dst}  (chmod \#{chmod})" if dry_run
      fs_mkdir_p(dst_dir, opts)
      fs_install(src, dst, chmod, opts)
      ok "\#{src} → \#{dst}" unless dry_run

      # Man pages
      Array(manifest['man_pages']).each do |mp|
        msrc = mp['source'].to_s
        mdir = expand_path(mp['destination'] || "\#{prefix}/share/man/man\#{mp['section']}", prefix)
        mdst = File.join(mdir, File.basename(msrc))

        puts "\\n--- Man page (section \#{mp['section']}) ---"

        unless File.exist?(msrc)
          msg = "\#{msrc} not found — run doc_generator.rb first"
          dry_run ? warn_("Would skip: \#{msg}") : warn_(msg)
          next
        end

        info "Would install: \#{msrc} → \#{mdst}" if dry_run
        fs_mkdir_p(mdir, opts)
        fs_install(msrc, mdst, '0644', opts)
        ok "\#{msrc} → \#{mdst}" unless dry_run

        unless dry_run
          %w[mandb makewhatis].each do |cmd|
            next unless bin_available?(cmd)
            sh("\#{cmd} -q 2>/dev/null || true", opts)
            break
          end
        else
          dry "mandb / makewhatis  (man index refresh)"
        end
      end

      # Config dirs
      Array(manifest['config_dirs']).each do |cd|
        dir  = expand_path(cd['path'], prefix)
        mode = cd['mode'] || '0700'
        puts "\\n--- Config dir ---"
        info "Would create: \#{dir}  (mode \#{mode})" if dry_run
        fs_mkdir_p(dir, opts)
        fs_chmod(dir, mode, opts)
        ok "\#{dir}  (mode \#{mode})" unless dry_run
      end

      # Config files
      Array(manifest['config_files']).each do |cf|
        csrc = cf['source'].to_s
        cdst = expand_path(cf['destination'], prefix)
        mode = cf['mode'] || '0600'

        puts "\\n--- Config file ---"
        unless File.exist?(csrc)
          msg = "Source not found: \#{csrc}"
          dry_run ? warn_("Would skip: \#{msg}") : warn_(msg)
          next
        end

        if File.exist?(cdst) && cf['skip_if_exists'] && !opts[:force]
          msg = "Exists, would skip: \#{cdst}  (--force to overwrite)"
          dry_run ? dry(msg) : info(msg)
          next
        end

        info "Would copy: \#{csrc} → \#{cdst}  (mode \#{mode})" if dry_run
        fs_cp(csrc, cdst, mode, opts)
        ok "\#{csrc} → \#{cdst}  (mode \#{mode})" unless dry_run
      end

      # Post-install notes (always shown — they're manual steps regardless)
      notes = Array(manifest['post_install_notes'])
      unless notes.empty?
        puts "\\n--- Post-install manual steps ---"
        notes.each { |n| warn_ n }
      end

      suffix = dry_run ? ansi('36', '✔  Dry-run complete. Nothing was written.') \
                       : ansi('32', '✔  Installation complete.')
      puts "\\n\#{suffix}"
    end

    # ---------------------------------------------------------------------------
    # --uninstall  (also handles --uninstall --dry-run)
    # ---------------------------------------------------------------------------

    def do_uninstall(manifest, opts)
      prefix  = opts[:prefix]
      dry_run = opts[:dry_run]

      banner = dry_run ? "DRY-RUN — no files will be removed" : "Uninstalling \#{manifest['name']}"
      puts "\\n=== \#{banner} ===\\n"

      # Binary
      bin     = manifest['binary'] || {}
      dst_dir = expand_path(bin['destination'] || "\#{prefix}/bin", prefix)
      dst     = File.join(dst_dir, bin['target'] || File.basename(bin['source'].to_s, '.*'))

      puts "--- Binary ---"
      if File.exist?(dst)
        info "Would remove: \#{dst}" if dry_run
        fs_rm(dst, opts)
        ok "Removed \#{dst}" unless dry_run
      else
        warn_ "Not found (already removed?): \#{dst}"
      end

      # Man pages
      Array(manifest['man_pages']).each do |mp|
        mdir = expand_path(mp['destination'] || "\#{prefix}/share/man/man\#{mp['section']}", prefix)
        mdst = File.join(mdir, File.basename(mp['source'].to_s))

        puts "\\n--- Man page ---"
        if File.exist?(mdst)
          info "Would remove: \#{mdst}" if dry_run
          fs_rm(mdst, opts)
          ok "Removed \#{mdst}" unless dry_run
        else
          warn_ "Not found: \#{mdst}"
        end
      end

      # Config files — only removed if explicitly listed (never auto-remove dirs)
      Array(manifest['config_files']).each do |cf|
        cdst = expand_path(cf['destination'], prefix)
        next unless File.exist?(cdst)
        puts "\\n--- Config file ---"
        warn_ "config file: \#{cdst}"
        warn_ "  Not auto-removing config — delete manually if desired"
        dry "  Would NOT remove: \#{cdst}  (config files are never auto-deleted)" if dry_run
      end

      notes = Array(manifest['uninstall_notes'])
      unless notes.empty?
        puts "\\n--- Manual cleanup ---"
        notes.each { |n| warn_ n }
      end

      suffix = dry_run ? ansi('36', '✔  Dry-run complete. Nothing was removed.') \
                       : ansi('32', '✔  Uninstall complete.')
      puts "\\n\#{suffix}"
    end

    # ---------------------------------------------------------------------------
    # --check  (dependency check only — no file operations, no dry-run needed)
    # ---------------------------------------------------------------------------

    def do_check(manifest, opts)
      prefix = opts[:prefix]
      name   = manifest['name'] || '(unknown)'
      ver    = manifest['version'] || '?'

      puts "=== Dependency check: \#{name} v\#{ver} ===\\n"
      issues = check_deps(manifest)

      puts "\\n=== Install plan (prefix: \#{prefix}) ==="
      bin     = manifest['binary'] || {}
      dst_dir = expand_path(bin['destination'] || "\#{prefix}/bin", prefix)
      info "Binary:   \#{bin['source']} → \#{dst_dir}/\#{bin['target']}"

      Array(manifest['man_pages']).each do |mp|
        mdir = expand_path(mp['destination'] || "\#{prefix}/share/man/man\#{mp['section']}", prefix)
        info "Man(\#{mp['section']}): \#{mp['source']} → \#{mdir}/"
      end

      Array(manifest['config_dirs']).each  { |cd| info "Config dir:  \#{expand_path(cd['path'], prefix)}" }
      Array(manifest['config_files']).each { |cf| info "Config file: \#{cf['source']} → \#{expand_path(cf['destination'], prefix)}" }

      puts ''
      if issues.empty?
        puts ansi('32', '✔  All checks passed. Ready to install.')
        puts "    Run with --install to proceed, --install --dry-run to preview."
      else
        puts ansi('33', "⚠  \#{issues.size} issue(s) — see above.")
        exit 1
      end
    end

    # ---------------------------------------------------------------------------
    # Dispatch
    # ---------------------------------------------------------------------------

    case options[:action]
    when :install   then do_install(MANIFEST, options)
    when :uninstall then do_uninstall(MANIFEST, options)
    when :check     then do_check(MANIFEST, options)
    end
  INSTALLER
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

source      = File.read(target, encoding: 'UTF-8')
script_name = File.basename(target)
base        = slug(target)
out_dir     = options[:output_dir]

FileUtils.mkdir_p(out_dir)

log("Analysing #{script_name} via Anthropic API...", options[:verbose])

raw_json = call_anthropic(
  api_key,
  analysis_prompt(source, script_name, options[:man_section], options[:prefix]),
  options[:verbose]
)

# Strip any accidental markdown fences the model might include despite the prompt
raw_json = raw_json.gsub(/\A```(?:json)?\s*/m, '').gsub(/\s*```\z/m, '').strip

begin
  info = JSON.parse(raw_json)
rescue JSON::ParserError => e
  abort "Failed to parse API response as JSON: #{e.message}\n\nRaw:\n#{raw_json}"
end

log('Generating Markdown...', options[:verbose])
md_path = File.join(out_dir, "#{base}.md")
File.write(md_path, generate_markdown(info, script_name, VERSION))

log('Generating usage text...', options[:verbose])
usage_path = File.join(out_dir, "#{base}_usage.txt")
File.write(usage_path, generate_usage(info, script_name, VERSION))

log('Generating man page...', options[:verbose])
man_path = File.join(out_dir, "#{base}.#{options[:man_section]}")
File.write(man_path, generate_man(info, script_name, options[:man_section], options[:author], VERSION))

log('Generating install manifest...', options[:verbose])
manifest_path = File.join(out_dir, "#{base}.install.json")
File.write(manifest_path, generate_manifest(info, script_name, VERSION, options[:author], options[:man_section], options[:prefix]))

log('Generating installer...', options[:verbose])
installer_path = File.join(out_dir, "#{base}_install.rb")
File.write(installer_path, generate_installer(info, script_name, VERSION))
FileUtils.chmod(0o755, installer_path)

puts 'Generated:'
puts "  #{md_path}"
puts "  #{usage_path}"
puts "  #{man_path}"
puts "  #{manifest_path}"
puts "  #{installer_path}"
puts
puts 'Next steps:'
puts "  ruby #{base}_install.rb --check             # verify deps"
puts "  ruby #{base}_install.rb --install           # install to #{options[:prefix]}"
puts "  ruby #{base}_install.rb --install --sudo    # if prefix is system-owned"
puts "  ruby #{base}_install.rb --uninstall         # remove"
puts "  groff -man -Tutf8 #{man_path} | less        # preview man page"
