#!/usr/bin/env ruby
# frozen_string_literal: true
#
# mandarin.rb — standalone manifest-driven installer
#
# Reads any *.install.json produced by doc_generator.rb and performs
# install, uninstall, check, or dry-run operations.
#
# Unlike <name>_install.rb (which embeds its manifest as a constant),
# this tool is a permanent resident of your toolbox — point it at any
# manifest file and it does the right thing.
#
# Usage:
#   mandarin.rb --manifest tool.install.json --install
#   mandarin.rb --manifest tool.install.json --install --dry-run
#   mandarin.rb --manifest tool.install.json --uninstall
#   mandarin.rb --manifest tool.install.json --check
#
# Requires: ruby 3.0+, stdlib only (fileutils, json, optparse — no gems required)

require 'fileutils'
require 'json'
require 'optparse'

VERSION     = '1.0.0'
SCRIPT_NAME = File.basename($PROGRAM_NAME)

# ---------------------------------------------------------------------------
# ANSI output helpers — degrade gracefully when stdout is not a tty
# ---------------------------------------------------------------------------

COLOUR = $stdout.tty?
# 256-colour orange (#ff8c00 ≈ xterm 208) for that authentic citrus phosphor feel
def ansi(code, str)  = COLOUR ? "\e[#{code}m#{str}\e[0m" : str
def orange(str)      = ansi('38;5;208', str)
def orange_hot(str)  = ansi('38;5;214', str)
def orange_dim(str)  = ansi('38;5;130', str)

def ok(msg)    = puts "  #{orange('🍊')}  #{msg}"
def warn_(msg) = puts "  #{ansi('33', '⚠')}   #{msg}"   # warn_ avoids Kernel#warn
def err(msg)   = puts "  #{ansi('31', '✘')}   #{msg}"
def info(msg)  = puts "  #{orange('→')}   #{msg}"
def dry(msg)   = puts "  #{ansi('36', '[DRY]')}  #{msg}"

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

options = {
  manifest: nil,
  action:   nil,
  prefix:   nil,           # nil = read from manifest binary.destination
  sudo:     false,
  force:    false,
  dry_run:  false,
  verbose:  false
}

parser = OptionParser.new do |o|
  o.banner = "Usage: #{SCRIPT_NAME} --manifest <file.install.json> <action> [options]"

  o.separator ''
  o.separator 'Required:'
  o.on('-m', '--manifest FILE', '*.install.json manifest to operate on') do |f|
    options[:manifest] = f
  end

  o.separator ''
  o.separator 'Actions (pick one):'
  o.on('--install',   'Install binary, man page, verify deps')  { options[:action] = :install   }
  o.on('--uninstall', 'Remove all installed files')             { options[:action] = :uninstall }
  o.on('--check',     'Verify dependencies, show install plan') { options[:action] = :check     }
  o.on('--list',      'Print manifest contents as a summary')   { options[:action] = :list      }

  o.separator ''
  o.separator 'Options:'
  o.on('-n', '--dry-run',
       'Simulate --install/--uninstall: print every action',
       'that WOULD be taken without changing anything.') { options[:dry_run] = true }
  o.on('-p', '--prefix DIR',
       'Override install prefix (default: from manifest)') { |d| options[:prefix] = d }
  o.on('--sudo',    'Prefix shell commands with sudo')     { options[:sudo]    = true }
  o.on('--force',   'Overwrite existing files')            { options[:force]   = true }
  o.on('-v', '--verbose', 'Show each command as run')      { options[:verbose] = true }
  o.on('-V', '--version') { puts "#{orange('🍊')}  mandarin v#{VERSION}  #{orange_dim('manifest · driven · installer')}"; exit }
  o.on('-h', '--help')    { puts o; exit }

  o.separator ''
  o.separator 'Examples:'
  o.separator "  #{SCRIPT_NAME} -m tool.install.json --check"
  o.separator "  #{SCRIPT_NAME} -m tool.install.json --install --dry-run"
  o.separator "  #{SCRIPT_NAME} -m tool.install.json --install --prefix ~/.local"
  o.separator "  #{SCRIPT_NAME} -m tool.install.json --install --sudo"
  o.separator "  #{SCRIPT_NAME} -m tool.install.json --uninstall --dry-run"
  o.separator "  #{SCRIPT_NAME} -m tool.install.json --list"
  o.separator ''
  o.separator 'Manifest discovery:'
  o.separator "  If --manifest is not given and exactly one *.install.json exists"
  o.separator "  in the current directory, it is used automatically."
end

parser.parse!

# ---------------------------------------------------------------------------
# Manifest discovery — use the lone *.install.json in cwd if not specified
# ---------------------------------------------------------------------------

if options[:manifest].nil?
  candidates = Dir['*.install.json']
  case candidates.length
  when 0
    warn "#{SCRIPT_NAME}: error: no --manifest given and no *.install.json found in #{Dir.pwd}"
    abort parser.banner
  when 1
    options[:manifest] = candidates.first
    warn "#{SCRIPT_NAME}: using #{options[:manifest]}"
  else
    warn "#{SCRIPT_NAME}: error: multiple *.install.json found — specify one with --manifest"
    candidates.each { |c| warn "  #{c}" }
    abort parser.banner
  end
end

unless File.exist?(options[:manifest])
  abort "#{SCRIPT_NAME}: manifest not found: #{options[:manifest]}"
end

if options[:action].nil?
  warn "#{SCRIPT_NAME}: error: specify --install, --uninstall, --check, or --list"
  abort parser.banner
end

if options[:dry_run] && options[:action] == :check
  warn "#{SCRIPT_NAME}: --dry-run has no effect with --check (already non-destructive)"
  options[:dry_run] = false
end

# ---------------------------------------------------------------------------
# Load and validate manifest
# ---------------------------------------------------------------------------

manifest = begin
  JSON.parse(File.read(options[:manifest], encoding: 'UTF-8'))
rescue JSON::ParserError => e
  abort "#{SCRIPT_NAME}: corrupt manifest JSON: #{e.message}"
end

# Resolve prefix: CLI flag > manifest binary.destination parent > /usr/local
options[:prefix] ||=
  manifest.dig('binary', 'destination')&.then { |d| File.dirname(d) } || '/usr/local'

# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

def expand_path(path, prefix)
  path.to_s
      .sub('~', Dir.home)
      .sub('{prefix}', prefix)
      .sub('$PREFIX', prefix)
end

def bin_available?(name)
  system("which #{name} >/dev/null 2>&1")
end

# act() — single gate for all side effects.
# dry_run: prints description, never yields.
# real:    yields the block (and prints on verbose).
def act(description, dry_run:, verbose:, sudo: false)
  label = sudo ? "sudo #{description}" : description
  if dry_run
    dry label
  else
    puts "    #{label}" if verbose
    yield
  end
end

def sh_act(cmd, opts)
  act(cmd, dry_run: opts[:dry_run], verbose: opts[:verbose], sudo: opts[:sudo]) do
    full = opts[:sudo] ? "sudo #{cmd}" : cmd
    system(full) || abort("Command failed: #{full}")
  end
end

def fs_mkdir_p(dir, opts)
  act("mkdir -p #{dir}", dry_run: opts[:dry_run], verbose: opts[:verbose], sudo: opts[:sudo]) do
    if opts[:sudo]
      system("sudo mkdir -p #{dir}") || abort("mkdir failed: #{dir}")
    else
      FileUtils.mkdir_p(dir)
    end
  end
end

def fs_install(src, dst, chmod, opts)
  act("install -m #{chmod} #{src} #{dst}",
      dry_run: opts[:dry_run], verbose: opts[:verbose], sudo: opts[:sudo]) do
    cmd  = "install -m #{chmod} #{src} #{dst}"
    full = opts[:sudo] ? "sudo #{cmd}" : cmd
    system(full) || abort("install failed: #{src} → #{dst}")
  end
end

def fs_cp(src, dst, mode, opts)
  act("cp #{src} #{dst}  (mode #{mode})",
      dry_run: opts[:dry_run], verbose: opts[:verbose]) do
    FileUtils.mkdir_p(File.dirname(dst))
    FileUtils.cp(src, dst)
    FileUtils.chmod(mode.to_i(8), dst)
  end
end

def fs_rm(path, opts)
  act("rm #{path}", dry_run: opts[:dry_run], verbose: opts[:verbose], sudo: opts[:sudo]) do
    if opts[:sudo]
      system("sudo rm #{path}") || abort("rm failed: #{path}")
    else
      FileUtils.rm(path)
    end
  end
end

def fs_chmod(path, mode, opts)
  act("chmod #{mode} #{path}", dry_run: opts[:dry_run], verbose: opts[:verbose]) do
    FileUtils.chmod(mode.to_i(8), path)
  end
end

# ---------------------------------------------------------------------------
# Dependency checker
# Returns array of blocking issue strings.
# Always runs live — the whole point of dry-run is to see deps too.
# ---------------------------------------------------------------------------

def check_deps(manifest)
  dep    = manifest['dependencies'] || {}
  issues = []

  # Ruby version
  min = dep['ruby_version'] || '2.7'
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new(min)
    err "Ruby #{min}+ required, running #{RUBY_VERSION}"
    issues << :ruby_version
  else
    ok "Ruby #{RUBY_VERSION} >= #{min}"
  end

  # Gems
  Array(dep['gems']).each do |g|
    begin
      gem g['name'], g['version'] || '>= 0'
      ok "gem #{g['name']} #{g['version']}"
    rescue Gem::LoadError
      label = "gem #{g['name']} #{g['version']}"
      if g['optional']
        warn_ "#{label} not installed (optional)"
      else
        err   "#{label} missing — run: gem install #{g['name']}"
        issues << "gem:#{g['name']}"
      end
    end
  end

  # System binaries
  Array(dep['system_bins']).each do |b|
    if bin_available?(b['bin'])
      ok "binary #{b['bin']} found"
    elsif b['optional']
      warn_ "binary #{b['bin']} not found (optional) — apt/brew install #{b['package']}"
    else
      err   "binary #{b['bin']} not found — install package: #{b['package']}"
      issues << "bin:#{b['bin']}"
    end
  end

  # Environment variables
  Array(manifest['environment']).each do |e|
    val = ENV[e['var']]
    if val && !val.strip.empty?
      ok "env #{e['var']} set"
    elsif e['required']
      err "env #{e['var']} not set — #{e['description']}"
      if e['suggest_export']
        warn_ "  Hint: #{e['suggest_export']}"
        warn_ "  Add to ~/.bashrc or ~/.zshrc"
      end
      issues << "env:#{e['var']}"
    else
      warn_ "env #{e['var']} not set (optional) — #{e['description']}"
    end
  end

  issues
end

# ---------------------------------------------------------------------------
# --list  — human-readable manifest summary, no ops
# ---------------------------------------------------------------------------

def do_list(manifest, manifest_path)
  name    = manifest['name']    || File.basename(manifest_path, '.install.json')
  version = manifest['version'] || '?'
  author  = manifest['author']  || '?'
  bin     = manifest['binary']  || {}
  dep     = manifest['dependencies'] || {}

  width = 70
  ruler = '─' * width

  puts "\n#{ruler}"
  puts " Manifest: #{manifest_path}"
  puts " Tool:     #{name} v#{version}  (author: #{author})"
  puts ruler

  puts "\nBinary"
  puts "  source:      #{bin['source']}"
  puts "  install as:  #{bin['target']}"
  puts "  destination: #{bin['destination']}"
  puts "  chmod:       #{bin['chmod']}"

  unless Array(manifest['man_pages']).empty?
    puts "\nMan pages"
    manifest['man_pages'].each do |mp|
      puts "  section #{mp['section']}: #{mp['source']} → #{mp['destination']}/"
    end
  end

  unless (min = dep['ruby_version']).nil?
    puts "\nDependencies"
    puts "  Ruby >= #{min}"
  end

  gems = Array(dep['gems'])
  unless gems.empty?
    puts "  Gems:"
    gems.each { |g| puts "    #{g['optional'] ? '(optional) ' : ''}#{g['name']} #{g['version']}" }
  end

  bins = Array(dep['system_bins'])
  unless bins.empty?
    puts "  System binaries:"
    bins.each { |b| puts "    #{b['optional'] ? '(optional) ' : ''}#{b['bin']}  [pkg: #{b['package']}]" }
  end

  env = Array(manifest['environment'])
  unless env.empty?
    puts "\nEnvironment variables"
    env.each do |e|
      req = e['required'] ? ansi('31', 'required') : ansi('33', 'optional')
      puts "  #{e['var'].ljust(24)} #{req}  — #{e['description']}"
    end
  end

  dirs = Array(manifest['config_dirs'])
  unless dirs.empty?
    puts "\nConfig dirs"
    dirs.each { |cd| puts "  #{cd['path']}  (mode #{cd['mode']})" }
  end

  files = Array(manifest['config_files'])
  unless files.empty?
    puts "\nConfig files"
    files.each { |cf| puts "  #{cf['source']} → #{cf['destination']}  (mode #{cf['mode']})" }
  end

  notes = Array(manifest['post_install_notes'])
  unless notes.empty?
    puts "\nPost-install notes"
    notes.each { |n| puts "  • #{n}" }
  end

  puts "\n#{ruler}\n"
end

# ---------------------------------------------------------------------------
# --install
# ---------------------------------------------------------------------------

def do_install(manifest, opts)
  prefix  = opts[:prefix]
  dry_run = opts[:dry_run]

  banner = dry_run ? "DRY-RUN — no files will be written" \
                   : "Installing #{manifest['name']} v#{manifest['version']}"
  puts "\n=== #{banner} ===\n"

  puts "\n--- Dependency check (always live) ---"
  issues = check_deps(manifest)

  unless issues.empty?
    err "Blocking issues found:"
    issues.each { |i| err "  #{i}" }
    if dry_run
      warn_ "Continuing dry-run so you can see the full plan..."
    else
      exit 1
    end
  end

  # Binary
  bin     = manifest['binary'] || {}
  src     = bin['source'].to_s
  dst_dir = expand_path(bin['destination'] || "#{prefix}/bin", prefix)
  dst     = File.join(dst_dir, bin['target'] || File.basename(src, '.*'))
  chmod   = bin['chmod'] || '0755'

  puts "\n--- Binary ---"
  unless File.exist?(src)
    if dry_run
      warn_ "Source not found: #{src} — real install would abort here"
    else
      abort "  #{ansi('31','✘')}  Source not found: #{src}"
    end
  end

  if !dry_run && File.exist?(dst) && !opts[:force]
    err "Already installed: #{dst}  (use --force to overwrite)"
    exit 1
  end

  info "Would install: #{src} → #{dst}  (chmod #{chmod})" if dry_run
  fs_mkdir_p(dst_dir, opts)
  fs_install(src, dst, chmod, opts)
  ok "#{src} → #{dst}" unless dry_run

  # Man pages
  Array(manifest['man_pages']).each do |mp|
    msrc = mp['source'].to_s
    mdir = expand_path(mp['destination'] || "#{prefix}/share/man/man#{mp['section']}", prefix)
    mdst = File.join(mdir, File.basename(msrc))

    puts "\n--- Man page (section #{mp['section']}) ---"
    unless File.exist?(msrc)
      msg = "#{msrc} not found — run doc_generator.rb to build it"
      dry_run ? warn_("Would skip: #{msg}") : warn_(msg)
      next
    end

    info "Would install: #{msrc} → #{mdst}" if dry_run
    fs_mkdir_p(mdir, opts)
    fs_install(msrc, mdst, '0644', opts)
    ok "#{msrc} → #{mdst}" unless dry_run

    unless dry_run
      %w[mandb makewhatis].each do |cmd|
        next unless bin_available?(cmd)
        sh_act("#{cmd} -q 2>/dev/null || true", opts)
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
    puts "\n--- Config dir ---"
    info "Would create: #{dir}  (mode #{mode})" if dry_run
    fs_mkdir_p(dir, opts)
    fs_chmod(dir, mode, opts)
    ok "#{dir}  (mode #{mode})" unless dry_run
  end

  # Config files
  Array(manifest['config_files']).each do |cf|
    csrc = cf['source'].to_s
    cdst = expand_path(cf['destination'], prefix)
    mode = cf['mode'] || '0600'

    puts "\n--- Config file ---"
    unless File.exist?(csrc)
      msg = "Source not found: #{csrc}"
      dry_run ? warn_("Would skip: #{msg}") : warn_(msg)
      next
    end

    if File.exist?(cdst) && cf['skip_if_exists'] && !opts[:force]
      msg = "Exists, skipping: #{cdst}  (--force to overwrite)"
      dry_run ? dry(msg) : info(msg)
      next
    end

    info "Would copy: #{csrc} → #{cdst}  (mode #{mode})" if dry_run
    fs_cp(csrc, cdst, mode, opts)
    ok "#{csrc} → #{cdst}  (mode #{mode})" unless dry_run
  end

  # Post-install notes — always shown, they're manual steps regardless
  notes = Array(manifest['post_install_notes'])
  unless notes.empty?
    puts "\n--- Post-install manual steps ---"
    notes.each { |n| warn_ n }
  end

  suffix = dry_run ? ansi('36', '✔  Dry-run complete. Nothing was written.') \
                   : "#{orange('🍊')}  #{orange_hot('Installation complete.')}"
  puts "\n#{suffix}"
end

# ---------------------------------------------------------------------------
# --uninstall
# ---------------------------------------------------------------------------

def do_uninstall(manifest, opts)
  prefix  = opts[:prefix]
  dry_run = opts[:dry_run]

  banner = dry_run ? "DRY-RUN — no files will be removed" \
                   : "Uninstalling #{manifest['name']}"
  puts "\n=== #{banner} ===\n"

  # Binary
  bin     = manifest['binary'] || {}
  dst_dir = expand_path(bin['destination'] || "#{prefix}/bin", prefix)
  dst     = File.join(dst_dir, bin['target'] || File.basename(bin['source'].to_s, '.*'))

  puts "--- Binary ---"
  if File.exist?(dst)
    info "Would remove: #{dst}" if dry_run
    fs_rm(dst, opts)
    ok "Removed #{dst}" unless dry_run
  else
    warn_ "Not found (already removed?): #{dst}"
  end

  # Man pages
  Array(manifest['man_pages']).each do |mp|
    mdir = expand_path(mp['destination'] || "#{prefix}/share/man/man#{mp['section']}", prefix)
    mdst = File.join(mdir, File.basename(mp['source'].to_s))

    puts "\n--- Man page ---"
    if File.exist?(mdst)
      info "Would remove: #{mdst}" if dry_run
      fs_rm(mdst, opts)
      ok "Removed #{mdst}" unless dry_run
    else
      warn_ "Not found: #{mdst}"
    end
  end

  # Config files — list but NEVER auto-remove
  Array(manifest['config_files']).each do |cf|
    cdst = expand_path(cf['destination'], prefix)
    next unless File.exist?(cdst)
    puts "\n--- Config file (not auto-removed) ---"
    warn_ "#{cdst}"
    warn_ "  Config files are never auto-deleted — remove manually if desired"
  end

  # Uninstall notes
  notes = Array(manifest['uninstall_notes'])
  unless notes.empty?
    puts "\n--- Manual cleanup ---"
    notes.each { |n| warn_ n }
  end

  suffix = dry_run ? ansi('36', '✔  Dry-run complete. Nothing was removed.') \
                   : "#{orange('🍊')}  #{orange_hot('Uninstall complete.')}"
  puts "\n#{suffix}"
end

# ---------------------------------------------------------------------------
# --check
# ---------------------------------------------------------------------------

def do_check(manifest, opts)
  prefix = opts[:prefix]
  name   = manifest['name']    || '(unknown)'
  ver    = manifest['version'] || '?'

  puts "=== Dependency check: #{name} v#{ver} ===\n"
  issues = check_deps(manifest)

  puts "\n=== Install plan (prefix: #{prefix}) ==="
  bin     = manifest['binary'] || {}
  dst_dir = expand_path(bin['destination'] || "#{prefix}/bin", prefix)
  info "Binary:   #{bin['source']} → #{dst_dir}/#{bin['target']}"

  Array(manifest['man_pages']).each do |mp|
    mdir = expand_path(mp['destination'] || "#{prefix}/share/man/man#{mp['section']}", prefix)
    info "Man(#{mp['section']}): #{mp['source']} → #{mdir}/"
  end

  Array(manifest['config_dirs']).each  { |cd| info "Config dir:  #{expand_path(cd['path'], prefix)}" }
  Array(manifest['config_files']).each { |cf| info "Config file: #{cf['source']} → #{expand_path(cf['destination'], prefix)}" }

  puts ''
  if issues.empty?
    puts "#{orange('🍊')}  #{orange_hot('All checks passed. Ready to install.')}"
    puts "    Run with --install to proceed, or --install --dry-run to preview."
  else
    puts ansi('33', "⚠  #{issues.size} issue(s) found — see above.")
    exit 1
  end
end

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case options[:action]
when :install   then do_install(manifest, options)
when :uninstall then do_uninstall(manifest, options)
when :check     then do_check(manifest, options)
when :list      then do_list(manifest, options[:manifest])
end
