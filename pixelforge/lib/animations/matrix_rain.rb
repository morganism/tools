# lib/animations/matrix_rain.rb
require_relative '../animation_registry'
module Animations
  class MatrixRain < Animation
    FRAMES = 32
    SIZE   = 32
    GREEN  = [57, 255, 20].freeze

    def initialize
      super(name: 'matrix_rain', description: 'Green digital rain columns', fps: 16)
    end

    def frames
      @frames ||= begin
        # Each column has an independent drop head position
        srand(42)
        cols = SIZE.times.map { { pos: rand(SIZE), speed: 1 + rand(3), trail: rand(6) + 4 } }
        FRAMES.times.map { |_t|
          grid = Array.new(SIZE * SIZE, 0.0)
          cols.each_with_index do |col, x|
            trail_len = col[:trail]
            trail_len.times do |i|
              row = (col[:pos] - i) % SIZE
              brightness = (trail_len - i).to_f / trail_len
              grid[row * SIZE + x] = [grid[row * SIZE + x], brightness].max
            end
            col[:pos] = (col[:pos] + col[:speed]) % SIZE
          end
          grid.map { |b|
            if b > 0.9
              [180, 255, 180]           # head – bright white-green
            elsif b > 0.0
              [(GREEN[0] * b).round, (GREEN[1] * b).round, (GREEN[2] * b * 0.4).round]
            else
              [0, rand(8), 0]           # slight noise in black
            end
          }
        }
      end
    end
  end
end
