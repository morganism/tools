#!/usr/bin/env ruby
# frozen_string_literal: true
#
# doc_generator.rb — AI-powered documentation generator
#
# Reads a Ruby script, sends it to the Anthropic API for analysis,
# then generates:
#   - A GitHub Wiki Markdown page
#   - A Usage.txt suitable for -h / --help output
#   - A properly formatted man page (groff/troff)
#
# Requires: ANTHROPIC_API_KEY in environment
# Deps:     net/http, json (both stdlib)

require 'net/http'
require 'json'
require 'optparse'
require 'fileutils'
require 'time'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

VERSION     = '1.0.0'
SCRIPT_NAME = File.basename($PROGRAM_NAME)
API_URL     = URI('https://api.anthropic.com/v1/messages')
API_MODEL   = 'claude-opus-4-6'
API_VERSION = '2023-06-01'
MAX_TOKENS  = 4096

# ---------------------------------------------------------------------------
# CLI option parsing
# ---------------------------------------------------------------------------

options = {
  output_dir:  '.',
  man_section: '1',
  author:      ENV['USER'] || 'Unknown',
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

  o.on('-a', '--author NAME', 'Author name for man page') do |a|
    options[:author] = a
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
  o.separator "  #{SCRIPT_NAME} -o ./docs -a 'Ada Lovelace' my_tool.rb"
  o.separator "  #{SCRIPT_NAME} -s 8 -v admin_tool.rb"
  o.separator ''
  o.separator 'Environment:'
  o.separator '  ANTHROPIC_API_KEY   Required. Your Anthropic API key.'
  o.separator ''
  o.separator "Output files (written to --output DIR):"
  o.separator '  <script_name>.md          GitHub Wiki Markdown'
  o.separator '  <script_name>_usage.txt   Plain-text help output'
  o.separator '  <script_name>.<section>   Groff man page'
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

  http = Net::HTTP.new(API_URL.host, API_URL.port)
  http.use_ssl     = true
  http.read_timeout = 120

  res = http.request(req)

  unless res.is_a?(Net::HTTPSuccess)
    abort "API error #{res.code}: #{res.body}"
  end

  data = JSON.parse(res.body)
  data.dig('content', 0, 'text') || abort('Unexpected API response structure')
end

# ---------------------------------------------------------------------------
# Prompt builders
# ---------------------------------------------------------------------------

def analysis_prompt(source, script_name)
  <<~PROMPT
    You are a senior Ruby developer and technical writer.

    Analyse the following Ruby script named "#{script_name}" and return a JSON
    object with EXACTLY these keys. Do not include markdown fences — raw JSON only.

    Keys required:
      "description"      — One sentence: what the script does
      "purpose"          — 2-3 sentences: what problem it solves and why it exists
      "implementation"   — 3-5 sentences: how it works internally, key design choices
      "interesting"      — 2-3 sentences: notable qualities, clever techniques, or
                           non-obvious behaviours worth highlighting
      "options"          — Array of objects, each: { "flag": "-x, --example VAR",
                           "description": "What it does" }
      "examples"         — Array of 5-7 realistic shell usage examples as strings
      "exit_codes"       — Array of objects: { "code": 0, "meaning": "Success" }
      "environment"      — Array of objects: { "var": "NAME", "description": "..." }
      "files"            — Array of objects: { "path": "file.json", "description": "..." }
      "see_also"         — Array of related commands/tools as strings e.g. "jq(1)"
      "bugs"             — String: any known limitations or caveats (or "None known.")
      "synopsis"         — Short synopsis line e.g. "script.rb [options] <file>"

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

  options_md = info['options'].map do |o|
    "| `#{o['flag']}` | #{o['description']} |"
  end.join("\n")

  env_md = Array(info['environment']).map do |e|
    "| `#{e['var']}` | #{e['description']} |"
  end.join("\n")

  files_md = Array(info['files']).map do |f|
    "| `#{f['path']}` | #{f['description']} |"
  end.join("\n")

  exit_md = Array(info['exit_codes']).map do |e|
    "| `#{e['code']}` | #{e['meaning']} |"
  end.join("\n")

  see_also = Array(info['see_also']).map { |s| "`#{s}`" }.join(', ')

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

    ## Bugs / Limitations

    #{info['bugs']}

    ## See Also

    #{see_also.empty? ? 'None' : see_also}

    ---

    *Generated by [doc_generator.rb](doc_generator.rb)*
  MD
end

def generate_usage(info, script_name, version)
  name = slug(script_name)
  width = 78

  ruler = '-' * width

  options_block = info['options'].map do |o|
    flag_part = "  #{o['flag']}"
    # Wrap description at width, indented
    "#{flag_part.ljust(28)}#{o['description']}"
  end.join("\n")

  examples_block = info['examples'].map { |e| "  #{e}" }.join("\n\n")

  env_block = Array(info['environment']).map do |e|
    "  #{e['var'].ljust(26)}#{e['description']}"
  end.join("\n")

  exit_block = Array(info['exit_codes']).map do |e|
    "  #{e['code'].to_s.ljust(6)}#{e['meaning']}"
  end.join("\n")

  see_also = Array(info['see_also']).join(', ')

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
    INTERESTING IMPLEMENTATION NOTES
    #{ruler}

    #{info['interesting'].gsub(/(.{1,#{width}})(\s+|\z)/, "  \\1\n").rstrip}

  USAGE
end

def generate_man(info, script_name, section, author, version)
  name    = slug(script_name).upcase
  date    = Date.today.strftime('%B %Y')  # e.g. "February 2026"
  package = "#{slug(script_name)} #{version}"

  # groff escape: periods at line start must be escaped
  def esc(str)
    str.to_s.gsub('\\', '\\\\').gsub(/^\./, '\\&.')
  end

  options_groff = info['options'].map do |o|
    ".TP\n.B #{esc(o['flag'])}\n#{esc(o['description'])}"
  end.join("\n")

  examples_groff = info['examples'].each_with_index.map do |e, i|
    ".PP\n.B Example #{i + 1}:\n.PP\n.RS 4\n.EX\n#{esc(e)}\n.EE\n.RE"
  end.join("\n")

  env_groff = Array(info['environment']).map do |e|
    ".TP\n.B #{esc(e['var'])}\n#{esc(e['description'])}"
  end.join("\n")

  files_groff = Array(info['files']).map do |f|
    ".TP\n.I #{esc(f['path'])}\n#{esc(f['description'])}"
  end.join("\n")

  exit_groff = Array(info['exit_codes']).map do |e|
    ".TP\n.B #{esc(e['code'])}\n#{esc(e['meaning'])}"
  end.join("\n")

  see_also_groff = Array(info['see_also']).map do |s|
    # Attempt to detect section number e.g. "jq(1)" -> .BR jq (1)
    if s =~ /^(.+)\((\d)\)$/
      ".BR #{$1} (#{$2})"
    else
      ".B #{esc(s)}"
    end
  end.join(",\n")

  <<~MAN
    .TH #{name} #{section} "#{date}" "#{package}" "User Commands"
    .\"
    .\" Generated by doc_generator.rb
    .\"
    .SH NAME
    #{slug(script_name)} \\- #{esc(info['description'])}
    .SH SYNOPSIS
    .B #{esc(info['synopsis'])}
    .SH DESCRIPTION
    #{esc(info['purpose'])}
    .PP
    #{esc(info['implementation'])}
    .SH OPTIONS
    #{options_groff}
    .SH EXAMPLES
    #{examples_groff}
    .SH ENVIRONMENT
    #{env_groff.empty? ? 'No environment variables required.' : env_groff}
    .SH FILES
    #{files_groff.empty? ? 'No files used.' : files_groff}
    .SH "EXIT STATUS"
    #{exit_groff}
    .SH BUGS
    #{esc(info['bugs'])}
    .SH NOTES
    #{esc(info['interesting'])}
    .SH "SEE ALSO"
    #{see_also_groff.empty? ? 'None.' : see_also_groff}
    .SH AUTHOR
    #{esc(author)}
    .PP
    Documentation generated by
    .BR doc_generator.rb .
  MAN
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

source      = File.read(target, encoding: 'UTF-8')
script_name = File.basename(target)
base        = slug(target)
out_dir     = options[:output_dir]

FileUtils.mkdir_p(out_dir)

log("Analysing #{script_name}...", options[:verbose])

raw_json = call_anthropic(api_key, analysis_prompt(source, script_name), options[:verbose])

# Strip any accidental markdown fences the model might include despite instructions
raw_json = raw_json.gsub(/\A```(?:json)?\s*/m, '').gsub(/\s*```\z/m, '').strip

begin
  info = JSON.parse(raw_json)
rescue JSON::ParserError => e
  abort "Failed to parse API response as JSON: #{e.message}\n\nRaw response:\n#{raw_json}"
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

puts "Generated:"
puts "  #{md_path}"
puts "  #{usage_path}"
puts "  #{man_path}"
puts
puts "To view man page:"
puts "  man #{man_path}"
puts "  # or without installing:"
puts "  groff -man -Tutf8 #{man_path} | less"
