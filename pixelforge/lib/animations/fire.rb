# lib/animations/fire.rb
require_relative '../animation_registry'
module Animations
  class Fire < Animation
    SIZE   = 32
    FRAMES = 48

    def initialize
      super(name: 'fire', description: 'DOOM-style fire propagation', fps: 24)
    end

    def frames
      @frames ||= begin
        # Seed bottom row
        buf = Array.new(SIZE * SIZE, 0)
        SIZE.times { |x| buf[(SIZE - 1) * SIZE + x] = 255 }

        FRAMES.times.map {
          new_buf = buf.dup
          # Propagate upward
          (SIZE - 1).times do |y|
            SIZE.times do |x|
              below = buf[(y + 1) * SIZE + x]
              decay = rand(0..3)
              src_x = x - rand(-1..1)
              src_x = src_x.clamp(0, SIZE - 1)
              val   = [below - decay, 0].max
              new_buf[y * SIZE + src_x] = val
            end
          end
          buf = new_buf
          buf.map { |v| fire_color(v) }
        }
      end
    end

    private

    FIRE_PALETTE = begin
      pal = Array.new(256)
      256.times do |i|
        if i < 64
          pal[i] = [0, 0, 0]
        elsif i < 128
          t = (i - 64) / 64.0
          pal[i] = [(t * 255).round, 0, 0]
        elsif i < 192
          t = (i - 128) / 64.0
          pal[i] = [255, (t * 165).round, 0]
        else
          t = (i - 192) / 64.0
          pal[i] = [255, (165 + t * 90).round, (t * 255).round]
        end
      end
      pal
    end

    def fire_color(v)
      FIRE_PALETTE[v.clamp(0, 255)]
    end
  end
end
