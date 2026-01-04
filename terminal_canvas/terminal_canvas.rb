#!/usr/bin/env ruby
# frozen_string_literal: true

require 'io/console'

# Terminal canvas module for ANSI-based graphics and cursor control
module TerminalCanvas
  # Handles ANSI escape sequences for terminal manipulation
  class Canvas
    # ANSI escape sequence constants
    ESC = "\033"
    
    # Control sequences
    CLEAR_SCREEN  = "#{ESC}[2J#{ESC}[H"
    HIDE_CURSOR   = "#{ESC}[?25l"
    SHOW_CURSOR   = "#{ESC}[?25h"
    RESET_COLOR   = "#{ESC}[0m"
    
    # Terminal title sequences
    SET_TITLE_FMT = "#{ESC}]0;%s\007"
    GET_TITLE_SEQ = "#{ESC}[21t"
    
    def initialize
      @cursor_visible = true
    end
    
    # Clear the entire screen and move cursor to top-left
    def clear
      emit(CLEAR_SCREEN)
      self
    end
    
    # Hide the cursor (useful during drawing)
    def hide_cursor
      emit(HIDE_CURSOR) if @cursor_visible
      @cursor_visible = false
      self
    end
    
    # Show the cursor
    def show_cursor
      emit(SHOW_CURSOR) unless @cursor_visible
      @cursor_visible = true
      self
    end
    
    # Move cursor to specific coordinates (1-indexed like terminal)
    # @param x [Integer] column position (1-based)
    # @param y [Integer] row position (1-based)
    def move_to(x, y)
      emit("#{ESC}[#{y};#{x}H")
      self
    end
    
    # Draw a colored character at specific position
    # @param x [Integer] column position
    # @param y [Integer] row position
    # @param char [String] character to draw (default: filled block)
    # @param r [Integer] red component (0-255)
    # @param g [Integer] green component (0-255)
    # @param b [Integer] blue component (0-255)
    def pixel(x, y, char = "█", r: 255, g: 255, b: 255)
      move_to(x, y)
      emit(color_rgb(r, g, b))
      emit(char)
      emit(RESET_COLOR)
      self
    end
    
    # Draw text at specific position with optional color
    # @param x [Integer] column position
    # @param y [Integer] row position
    # @param text [String] text to draw
    # @param r [Integer] red component (optional)
    # @param g [Integer] green component (optional)
    # @param b [Integer] blue component (optional)
    def text(x, y, text, r: nil, g: nil, b: nil)
      move_to(x, y)
      if r && g && b
        emit(color_rgb(r, g, b))
        emit(text)
        emit(RESET_COLOR)
      else
        emit(text)
      end
      self
    end
    
    # Set the terminal window title
    # @param title [String] new window title
    def set_title(title)
      emit(SET_TITLE_FMT % title)
      self
    end
    
    # Attempt to get current terminal title
    # @return [String, nil] current title or nil if unsupported
    def get_title
      emit(GET_TITLE_SEQ)
      
      response = ""
      $stdin.raw do |io|
        # Terminal responds with: ESC]l<title>ESC\
        # Timeout after 100ms to avoid hanging
        if IO.select([io], nil, nil, 0.1)
          response = io.readpartial(1024)
        end
      end
      
      # Parse response format: \033]l<title>\033\\
      response[/#{ESC}\]l(.+?)#{ESC}\\/, 1]
    rescue StandardError
      nil
    end
    
    # Reset terminal to default state
    def reset
      show_cursor
      emit(RESET_COLOR)
      self
    end
    
    private
    
    # Generate RGB color ANSI sequence
    # @param r [Integer] red (0-255)
    # @param g [Integer] green (0-255)
    # @param b [Integer] blue (0-255)
    # @return [String] ANSI color sequence
    def color_rgb(r, g, b)
      "#{ESC}[38;2;#{r};#{g};#{b}m"
    end
    
    # Emit ANSI sequence to stdout with immediate flush
    # @param seq [String] sequence to emit
    def emit(seq)
      print seq
      $stdout.flush
    end
  end
end

# -------------------------------------------------------
# DEMO / CLI ENTRYPOINT
# -------------------------------------------------------

if __FILE__ == $0
  include TerminalCanvas
  
  canvas = Canvas.new
  
  # Set window title
  canvas.set_title("Terminal Canvas Demo")
  
  # Clear screen and hide cursor for clean drawing
  canvas.clear.hide_cursor
  
  # Draw a colorful pattern
  10.times do |i|
    canvas.pixel(10 + i, 5, "█", r: 250 - (i * 20), g: 128, b: 64 + (i * 15))
    canvas.pixel(10 + i, 6, "█", r: 64 + (i * 15), g: 128, b: 250 - (i * 20))
  end
  
  # Draw some text
  canvas.text(10, 8, "Hello, Terminal Canvas!", r: 100, g: 255, b: 100)
  canvas.text(10, 9, "ANSI codes are fun!", r: 255, g: 200, b: 50)
  
  # Move cursor out of the way
  canvas.move_to(1, 12)
  
  # Try to display current title
  if title = canvas.get_title
    puts "Current window title: '#{title}'"
  else
    puts "Terminal doesn't support title queries"
  end
  
  # Clean up
  canvas.show_cursor
  
  puts "\nDemo complete!"
end
