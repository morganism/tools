#!/usr/bin/env ruby
# frozen_string_literal: true
#
# visual_totp.rb — Visual TOTP CLI
# Derives a TOTP secret from 5 visual memory questions.
# Compatible with visual-totp.html and visual-totp-verifier.html
#
# Usage:
#   ruby visual_totp.rb              # interactive — answer all 5 questions
#   ruby visual_totp.rb --token VTOK.xxx.yyy   # skip questions via pre-auth token
#   ruby visual_totp.rb --setup      # show secret + QR uri for authenticator app
#   ruby visual_totp.rb --verify     # verify a 6-digit code you supply
#   ruby visual_totp.rb --gen-token  # answer questions then generate a pre-auth token

require 'openssl'
require 'base64'
require 'json'
require 'io/console'

# ─────────────────────────────────────────────────────────────
# ANSI palette  (same visual identity as the HTML pages)
# ─────────────────────────────────────────────────────────────
module C
  RESET  = "\e[0m"
  def self.neon(s)   = "\e[38;2;57;255;20m#{s}#{RESET}"
  def self.red(s)    = "\e[38;2;255;59;92m#{s}#{RESET}"
  def self.yellow(s) = "\e[38;2;245;196;0m#{s}#{RESET}"
  def self.cyan(s)   = "\e[38;2;0;207;255m#{s}#{RESET}"
  def self.purple(s) = "\e[38;2;123;47;255m#{s}#{RESET}"
  def self.dim(s)    = "\e[38;2;80;100;80m#{s}#{RESET}"
  def self.white(s)  = "\e[38;2;200;220;200m#{s}#{RESET}"
  def self.bold(s)   = "\e[1m#{s}#{RESET}"
  def self.rev(s)    = "\e[7m#{s}#{RESET}"

  # Card colours
  def self.card_red(s)   = "\e[38;2;255;59;92m#{s}#{RESET}"
  def self.card_black(s) = "\e[38;2;220;220;240m#{s}#{RESET}"

  # Tile colours
  def self.tile_r(s) = "\e[41;30m #{s} #{RESET}"
  def self.tile_g(s) = "\e[42;30m #{s} #{RESET}"
  def self.tile_y(s) = "\e[43;30m #{s} #{RESET}"
end

# ─────────────────────────────────────────────────────────────
# BASE-32  (RFC 4648, identical alphabet to JS implementation)
# ─────────────────────────────────────────────────────────────
module Base32
  ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'

  def self.encode(bytes)
    bits = 0; value = 0; out = +''
    bytes.each_byte do |b|
      value = (value << 8) | b
      bits += 8
      while bits >= 5
        out << ALPHABET[(value >> (bits - 5)) & 31]
        bits -= 5
      end
    end
    out << ALPHABET[(value << (5 - bits)) & 31] if bits > 0
    out << '=' until out.length % 8 == 0
    out
  end

  def self.decode(str)
    str = str.upcase.delete('=')
    bits = 0; value = 0; out = ''.b
    str.each_char do |c|
      idx = ALPHABET.index(c)
      next unless idx
      value = (value << 5) | idx
      bits += 5
      if bits >= 8
        out << (value >> (bits - 8) & 0xff).chr
        bits -= 8
      end
    end
    out
  end
end

# ─────────────────────────────────────────────────────────────
# TOTP  (RFC 6238 / RFC 4226, SHA-1, 6 digits, 30s)
# ─────────────────────────────────────────────────────────────
module TOTP
  def self.compute(secret_b32, offset: 0)
    key     = Base32.decode(secret_b32)
    counter = (Time.now.to_i / 30) + offset
    buf     = [counter >> 32, counter & 0xffffffff].pack('NN')
    hmac    = OpenSSL::HMAC.digest('SHA1', key, buf)
    bytes   = hmac.bytes
    offset_byte = bytes[-1] & 0x0f
    code = ((bytes[offset_byte]     & 0x7f) << 24) |
           ((bytes[offset_byte + 1] & 0xff) << 16) |
           ((bytes[offset_byte + 2] & 0xff) <<  8) |
            (bytes[offset_byte + 3] & 0xff)
    (code % 1_000_000).to_s.rjust(6, '0')
  end

  def self.seconds_remaining
    30 - (Time.now.to_i % 30)
  end
end

# ─────────────────────────────────────────────────────────────
# SECRET DERIVATION  (SHA-256 of pipe-joined answers, same as JS)
# ─────────────────────────────────────────────────────────────
module SecretDeriver
  def self.derive(answers)
    combined = answers.join('|')
    hash     = OpenSSL::Digest::SHA256.digest(combined)
    Base32.encode(hash[0, 20])
  end
end

# ─────────────────────────────────────────────────────────────
# PRE-AUTH TOKEN
#
# Format:  VTOK.<b64url_payload>.<b64url_sig>
#
# Payload (JSON → base64url):
#   { "s": "<b32_secret>", "e": <unix_expiry>, "l": "<label>", "w": <window_secs> }
#
# Signing:
#   sign_key = SHA-256( Base32.decode(secret) + "VTOK-1" )
#   sig      = HMAC-SHA256(sign_key, payload_b64url)[0..15]   (16 bytes → 22 b64url chars)
# ─────────────────────────────────────────────────────────────
module VToken
  WINDOW_PRESETS = {
    'personal' => { secs: 86_400, label: 'Personal — 24 h'   },
    'shared'   => { secs: 14_400, label: 'Shared — 4 h'      },
    'public'   => { secs:  3_600, label: 'Public — 1 h'      },
  }.freeze

  def self.b64url_encode(data)
    Base64.strict_encode64(data).tr('+/', '-_').delete('=')
  end

  def self.b64url_decode(str)
    padded = str.tr('-_', '+/') + '=' * ((4 - str.length % 4) % 4)
    Base64.strict_decode64(padded)
  end

  def self.sign(secret_b32, payload_b64url)
    key_material = Base32.decode(secret_b32) + 'VTOK-1'
    sign_key     = OpenSSL::Digest::SHA256.digest(key_material)
    OpenSSL::HMAC.digest('SHA256', sign_key, payload_b64url)[0, 16]
  end

  def self.generate(secret_b32, window_type)
    preset  = WINDOW_PRESETS.fetch(window_type, WINDOW_PRESETS['shared'])
    expiry  = Time.now.to_i + preset[:secs]
    payload = JSON.generate({ s: secret_b32, e: expiry, l: window_type, w: preset[:secs] })
    p_b64   = b64url_encode(payload)
    sig     = sign(secret_b32, p_b64)
    "VTOK.#{p_b64}.#{b64url_encode(sig)}"
  end

  def self.verify(token)
    parts = token.split('.')
    return err('malformed token — expected VTOK.<payload>.<sig>') unless parts.length == 3 && parts[0] == 'VTOK'

    _prefix, p_b64, sig_b64 = parts
    payload = JSON.parse(b64url_decode(p_b64), symbolize_names: true)

    return err('token expired')             if Time.now.to_i > payload[:e]
    return err('missing secret in payload') unless payload[:s]

    expected_sig = sign(payload[:s], p_b64)
    given_sig    = b64url_decode(sig_b64)
    return err('signature mismatch — token tampered or from wrong session') unless OpenSSL.fixed_length_secure_compare(expected_sig, given_sig)

    { ok: true, secret: payload[:s], expiry: payload[:e], label: payload[:l], window_secs: payload[:w] }
  rescue => e
    err(e.message)
  end

  def self.err(msg) = { ok: false, error: msg }
end

# ─────────────────────────────────────────────────────────────
# QUESTION DATA  (identical labels/ordering to HTML pages)
# ─────────────────────────────────────────────────────────────
RANKS  = %w[A 2 3 4 5 6 7 8 9 10 J Q K].freeze
SUITS  = [
  { sym: '♠', name: 'S', color: :black },
  { sym: '♥', name: 'H', color: :red   },
  { sym: '♦', name: 'D', color: :red   },
  { sym: '♣', name: 'C', color: :black },
].freeze

EMOJIS = %w[😂 😍 🤔 😎 🥺 😡 🤯 🥳 🙈 💀 👻 🤡 👽 🤖 💩 🦄 🐉 🦊 🐙 🦋 🌈 🔥 💎 ⚡].freeze

CARTOONS = [
  { e: '🐭', label: 'Mickey'  },
  { e: '🤠', label: 'Sheriff' },
  { e: '🦸', label: 'Hero'    },
  { e: '🧙', label: 'Wizard'  },
  { e: '🦹', label: 'Villain' },
  { e: '🧛', label: 'Dracula' },
  { e: '🤖', label: 'Bender'  },
  { e: '🦊', label: 'Foxy'    },
].freeze

SIGNS = [
  { id: 'stop',    label: 'STOP'    },
  { id: 'yield',   label: 'YIELD'   },
  { id: 'speed',   label: '50 MPH'  },
  { id: 'noentry', label: 'NO ENTRY'},
  { id: 'oneway',  label: 'ONE WAY' },
  { id: 'dead',    label: 'DEAD END'},
].freeze

TILES_POOL = [
  { letter: 'R', color: 'r', val: 1 },
  { letter: 'R', color: 'r', val: 1 },
  { letter: 'R', color: 'r', val: 1 },
  { letter: 'G', color: 'g', val: 2 },
  { letter: 'G', color: 'g', val: 2 },
  { letter: 'Y', color: 'y', val: 3 },
  { letter: 'Y', color: 'y', val: 3 },
].freeze

# ─────────────────────────────────────────────────────────────
# DISPLAY HELPERS
# ─────────────────────────────────────────────────────────────
module UI
  COLS = (IO.console&.winsize&.last || 80)

  def self.clear   = print("\e[2J\e[H")
  def self.hr(ch = '─') = C.dim(ch * COLS)
  def self.nl      = puts

  def self.banner
    puts C.neon(<<~ART)
      ╦  ╦╦╔═╗╦ ╦╔═╗╦    ╔╦╗╔═╗╔╦╗╔═╗
      ╚╗╔╝║╚═╗║ ║╠═╣║     ║ ║ ║ ║ ╠═╝
       ╚╝ ╩╚═╝╚═╝╩ ╩╩═╝   ╩ ╚═╝ ╩ ╩  
    ART
    puts C.dim('  Mnemonic Authenticator CLI  ·  RFC 6238 TOTP  ·  Visual Secret Derivation')
    puts hr
    nl
  end

  def self.section(n, title, hint)
    puts "\n#{C.bold(C.yellow("▸ QUESTION #{n}:"))} #{C.white(title)}"
    puts C.dim("  #{hint}")
    puts hr('·')
  end

  def self.ok(msg)   = puts("  #{C.neon('✓')} #{C.white(msg)}")
  def self.err(msg)  = puts("  #{C.red('✗')} #{msg}")
  def self.info(msg) = puts("  #{C.dim('·')} #{msg}")

  def self.prompt(msg)
    print "  #{C.cyan('?')} #{C.white(msg)} "
    $stdout.flush
    $stdin.gets.to_s.strip
  end

  def self.render_card(rank, suit)
    str = "#{rank}#{suit[:sym]}"
    suit[:color] == :red ? C.card_red(str) : C.card_black(str)
  end

  def self.render_tile(t)
    case t[:color]
    when 'r' then C.tile_r(t[:letter])
    when 'g' then C.tile_g(t[:letter])
    when 'y' then C.tile_y(t[:letter])
    end
  end

  def self.show_card_grid(selected)
    SUITS.each do |suit|
      row = RANKS.map.with_index do |rank, i|
        id  = "#{rank}#{suit[:name]}"
        idx = selected.index(id)
        cell = render_card(rank.rjust(2), suit)
        idx ? C.rev(C.bold("[#{idx + 1}#{cell[/[^m]+$/]}")) : "  #{cell} "
      end
      puts '  ' + row.join(' ')
    end
  end

  def self.show_emoji_list(selected)
    EMOJIS.each_with_index do |e, i|
      sel_idx = selected.index(e)
      num     = (i + 1).to_s.rjust(2)
      marker  = sel_idx ? C.neon("[#{sel_idx + 1}]") : C.dim("   ")
      print "  #{C.dim(num)}. #{e} #{marker}   "
      puts if (i + 1) % 6 == 0
    end
    puts
  end

  def self.progress_bar(secs, total = 30)
    filled = (secs.to_f / total * 20).round
    bar    = C.neon('█' * filled) + C.dim('░' * (20 - filled))
    "#{bar} #{secs}s"
  end
end

# ─────────────────────────────────────────────────────────────
# QUESTION INTERACTIONS
# ─────────────────────────────────────────────────────────────
module Questions
  def self.ask_cards
    UI.section(1, 'Playing Cards', 'Type card IDs e.g. AH 10S KD — pick exactly 3 in order')
    selected = []
    loop do
      UI.show_card_grid(selected)
      puts
      if selected.size == 3
        UI.ok("Selected: #{selected.join(', ')}")
        break
      end
      input = UI.prompt("Enter card (e.g. #{C.cyan('AS')}, #{C.cyan('10H')}, #{C.cyan('KD')}) or #{C.yellow('undo')}:")
      if input.downcase == 'undo'
        selected.pop unless selected.empty?
        next
      end
      id = input.upcase.strip
      suit_names = SUITS.map { |s| s[:name] }
      rank_str   = id[0..-2]
      suit_char  = id[-1]
      unless RANKS.include?(rank_str) && suit_names.include?(suit_char)
        UI.err("Invalid card '#{id}'.  Format: rank(A/2-10/J/Q/K) + suit(S/H/D/C)")
        next
      end
      if selected.include?(id)
        UI.err("#{id} already selected")
        next
      end
      selected << id
    end
    selected
  end

  def self.ask_emojis
    UI.section(2, 'Emoticons', 'Enter numbers 1-24, exactly 4 in order')
    selected = []
    loop do
      UI.show_emoji_list(selected)
      if selected.size == 4
        UI.ok("Selected: #{selected.join(' ')}")
        break
      end
      input = UI.prompt("Pick emoji by number (#{C.cyan('1-24')}) or #{C.yellow('undo')}:")
      if input.downcase == 'undo'
        selected.pop unless selected.empty?
        next
      end
      n = input.to_i
      unless n.between?(1, EMOJIS.size)
        UI.err("Enter a number between 1 and #{EMOJIS.size}")
        next
      end
      e = EMOJIS[n - 1]
      if selected.include?(e)
        UI.err("#{e} already selected")
        next
      end
      selected << e
    end
    selected
  end

  def self.ask_cartoon
    UI.section(3, 'Cartoon Character', 'Pick exactly 1')
    CARTOONS.each_with_index { |c, i| puts "  #{C.dim((i+1).to_s.rjust(2))}.  #{c[:e]}  #{C.white(c[:label])}" }
    loop do
      n = UI.prompt("Pick number (#{C.cyan('1-#{CARTOONS.size}')})").to_i
      if n.between?(1, CARTOONS.size)
        c = CARTOONS[n - 1]
        UI.ok("Selected: #{c[:e]} #{c[:label]}")
        return c[:label]
      end
      UI.err("Enter 1-#{CARTOONS.size}")
    end
  end

  def self.ask_sign
    UI.section(4, 'Street Sign', 'Pick exactly 1')
    SIGNS.each_with_index { |s, i| puts "  #{C.dim((i+1).to_s.rjust(2))}.  #{C.white(s[:label])}" }
    loop do
      n = UI.prompt("Pick number (#{C.cyan('1-#{SIGNS.size}')})").to_i
      if n.between?(1, SIGNS.size)
        s = SIGNS[n - 1]
        UI.ok("Selected: #{s[:label]}")
        return s[:id]
      end
      UI.err("Enter 1-#{SIGNS.size}")
    end
  end

  def self.ask_tiles
    UI.section(5, 'Scrabble Tiles', 'Type the sequence using R/G/Y — must use all 7 tiles (3R 2G 2Y)')
    pool = TILES_POOL.dup
    puts '  Pool: ' + pool.map { |t| UI.render_tile(t) }.join(' ')
    puts
    puts '  Tile reference:'
    puts "  #{C.tile_r('R')} Red   (×3, val=1)   " \
         "#{C.tile_g('G')} Green (×2, val=2)   " \
         "#{C.tile_y('Y')} Yellow (×2, val=3)"
    puts
    loop do
      input = UI.prompt("Enter 7-letter sequence using R/G/Y (e.g. #{C.cyan('RGRYRGY')}):")
      seq = input.upcase.chars
      counts = seq.tally
      pool_counts = TILES_POOL.map { |t| t[:letter] }.tally
      if seq.length != 7
        UI.err("Need exactly 7 tiles, got #{seq.length}")
        next
      end
      invalid = seq.reject { |c| %w[R G Y].include?(c) }
      if invalid.any?
        UI.err("Invalid letters: #{invalid.uniq.join(', ')} — only R, G, Y allowed")
        next
      end
      if counts.any? { |letter, n| n > pool_counts.fetch(letter, 0) }
        UI.err("Too many of one tile — pool has: R×3, G×2, Y×2")
        next
      end
      tile_seq = seq.map do |letter|
        pool.index { |t| t[:letter] == letter }.then { |i| pool.delete_at(i) }
      end
      UI.ok("Sequence: #{tile_seq.map { |t| UI.render_tile(t) }.join(' ')}")
      return tile_seq
    end
  end

  def self.run_all
    cards   = ask_cards
    emojis  = ask_emojis
    cartoon = ask_cartoon
    sign    = ask_sign
    tiles   = ask_tiles
    {
      cards:   cards,
      emojis:  emojis,
      cartoon: cartoon,
      sign:    sign,
      tiles:   tiles,
    }
  end

  def self.answers_from(qa)
    [
      qa[:cards].join(','),
      qa[:emojis].join(''),
      qa[:cartoon],
      qa[:sign],
      qa[:tiles].map { |t| t[:letter] + t[:color] }.join(''),
    ]
  end
end

# ─────────────────────────────────────────────────────────────
# TOKEN GENERATION PROMPT
# ─────────────────────────────────────────────────────────────
def prompt_token_generation(secret)
  puts
  puts UI.hr
  puts "\n  #{C.yellow('▸ GENERATE PRE-AUTH TOKEN')}"
  puts C.dim('  Allow future logins without answering all 5 questions.')
  puts
  VToken::WINDOW_PRESETS.each_with_index do |(key, val), i|
    puts "  #{C.cyan((i+1).to_s)}.  #{C.white(val[:label])}"
  end
  puts "  #{C.dim('0')}.  #{C.dim('Skip — no token')}"
  puts
  choice = UI.prompt('Choose window (0-3):').to_i
  return nil if choice == 0

  keys = VToken::WINDOW_PRESETS.keys
  return nil unless choice.between?(1, keys.size)

  window_type = keys[choice - 1]
  token = VToken.generate(secret, window_type)
  puts
  puts '  ' + UI.hr('─')
  puts "  #{C.neon('TOKEN:')}"
  puts
  # Wrap token at 64 chars for readability
  token.chars.each_slice(64) { |chunk| puts "  #{C.yellow(chunk.join)}" }
  puts
  expiry = Time.now + VToken::WINDOW_PRESETS[window_type][:secs]
  UI.info("Valid until #{C.white(expiry.strftime('%Y-%m-%d %H:%M:%S %Z'))}")
  UI.info("Use: #{C.cyan('ruby visual_totp.rb --token VTOK.xxx.yyy')}")
  UI.info("Or paste into the HTML Verifier / Generator token field.")
  puts '  ' + UI.hr('─')
  token
end

# ─────────────────────────────────────────────────────────────
# LIVE TOTP DISPLAY  (refreshes every second, Ctrl+C to exit)
# ─────────────────────────────────────────────────────────────
def show_live_totp(secret, &after_block)
  puts
  puts UI.hr
  puts "\n  #{C.neon('▸ YOUR TOTP CODE')}\n\n"
  last_code = nil
  trap('INT') { puts "\n\n  #{C.dim('Goodbye.')}"; exit 0 }
  loop do
    code  = TOTP.compute(secret)
    secs  = TOTP.seconds_remaining
    print "\r  #{C.bold(C.neon(code.scan(/.{3}/).join(' ')))}   #{UI.progress_bar(secs)}    "
    $stdout.flush
    if last_code && code != last_code
      # Code just rolled — flash notification
      print "\r  #{C.bold(C.yellow(code.scan(/.{3}/).join(' ')))}   #{C.yellow('↻ refreshed')}           "
      $stdout.flush
      sleep 0.15
    end
    last_code = code
    sleep 1
  end
end

# ─────────────────────────────────────────────────────────────
# VERIFY MODE
# ─────────────────────────────────────────────────────────────
def verify_mode(secret)
  puts
  puts UI.hr
  puts "\n  #{C.yellow('▸ VERIFY A CODE')}\n"
  code = UI.prompt('Enter 6-digit TOTP code:').strip
  unless code.match?(/\A\d{6}\z/)
    UI.err("Must be exactly 6 digits")
    return
  end
  match_window = nil
  window_codes = {}
  (-1..1).each do |off|
    c = TOTP.compute(secret, offset: off)
    window_codes[off] = c
    match_window = off if c == code
  end
  puts
  if match_window
    label = { -1 => 'previous window (clock ahead)', 0 => 'current window', 1 => 'next window (clock behind)' }[match_window]
    puts "  #{C.neon('✓ ACCESS GRANTED')}  —  matched #{C.white(label)}"
  else
    puts "  #{C.red('✗ ACCESS DENIED')}  —  code #{C.yellow(code)} not valid in any window"
    puts
    puts "  #{C.dim('Window codes for debugging:')}"
    window_codes.each do |off, c|
      lbl = { -1 => 'prev', 0 => 'now ', 1 => 'next' }[off]
      indicator = off == match_window ? C.neon('←') : ' '
      puts "    #{C.dim(lbl)}  #{C.white(c)} #{indicator}"
    end
  end
end

# ─────────────────────────────────────────────────────────────
# SETUP MODE  (output secret + otpauth:// URI for scannable QR)
# ─────────────────────────────────────────────────────────────
def setup_mode(secret)
  puts
  puts UI.hr
  puts "\n  #{C.yellow('▸ SETUP — Enroll in Authenticator App')}\n"
  puts
  puts "  #{C.dim('Base-32 secret:')}"
  puts "  #{C.neon(secret)}"
  puts
  uri = "otpauth://totp/VisualTOTP?secret=#{secret}&issuer=MnemonicAuth&algorithm=SHA1&digits=6&period=30"
  puts "  #{C.dim('OTP Auth URI (scan with qrencode or your app):')}"
  puts "  #{C.cyan(uri)}"
  puts
  # Try qrencode if available
  if system('which qrencode > /dev/null 2>&1')
    puts "  #{C.dim('QR code:')}\n"
    system("qrencode -t ANSIUTF8 '#{uri}'")
  else
    UI.info("Install #{C.yellow('qrencode')} to render a QR code in-terminal: apt/brew install qrencode")
  end
end

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────
def main
  UI.clear
  UI.banner

  # ── Parse flags ──────────────────────────────────────────
  setup_mode_flag    = ARGV.include?('--setup')
  verify_mode_flag   = ARGV.include?('--verify')
  gen_token_flag     = ARGV.include?('--gen-token')
  token_idx          = ARGV.index('--token')
  provided_token     = token_idx ? ARGV[token_idx + 1] : nil

  secret = nil

  # ── Token path ───────────────────────────────────────────
  if provided_token
    puts "  #{C.dim('Checking pre-auth token…')}\n"
    result = VToken.verify(provided_token)
    if result[:ok]
      secret = result[:secret]
      expiry = Time.at(result[:expiry])
      UI.ok("Token valid  —  #{C.white(result[:label])} window  —  expires #{C.yellow(expiry.strftime('%H:%M:%S %Z'))}")
      puts
    else
      UI.err("Invalid token: #{result[:error]}")
      puts "  #{C.dim('Falling through to full question flow.')}\n"
    end
  end

  # ── Check for token in STDIN if piped ────────────────────
  if !secret && !$stdin.tty?
    piped = $stdin.read.strip
    if piped.start_with?('VTOK.')
      result = VToken.verify(piped)
      if result[:ok]
        secret = result[:secret]
        UI.ok("Piped token accepted  —  #{result[:label]}")
      else
        UI.err("Piped token invalid: #{result[:error]}")
      end
    end
  end

  # ── Question flow if no valid token ──────────────────────
  unless secret
    puts "  #{C.dim('Answer all 5 questions to derive your TOTP secret.')}"
    puts "  #{C.dim('Answers must exactly match your enrollment choices.')}\n"
    qa      = Questions.run_all
    answers = Questions.answers_from(qa)
    secret  = SecretDeriver.derive(answers)
    UI.ok("Secret derived: #{C.dim(secret[0, 8] + '…')}")
  end

  # ── Mode dispatch ─────────────────────────────────────────
  if setup_mode_flag
    setup_mode(secret)
  elsif verify_mode_flag
    verify_mode(secret)
  elsif gen_token_flag || (!setup_mode_flag && !verify_mode_flag && !provided_token)
    # Always offer token generation after answering questions
    prompt_token_generation(secret) if gen_token_flag || ARGV.empty?
    puts
    show_live_totp(secret)
  else
    # Arrived here via --token without other flags — show live TOTP
    show_live_totp(secret)
  end
end

main
