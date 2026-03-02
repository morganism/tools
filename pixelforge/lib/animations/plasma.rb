# lib/animations/plasma.rb
require_relative '../animation_registry'
module Animations
  class Plasma < Animation
    FRAMES = 32
    SIZE   = 32

    def initialize
      super(name: 'plasma', description: 'Classic sine-wave plasma in true color', fps: 20)
    end

    def frames
      @frames ||= FRAMES.times.map { |t|
        phase = t * Math::PI * 2.0 / FRAMES
        SIZE.times.flat_map { |y|
          SIZE.times.map { |x|
            v  = Math.sin(x / 4.0 + phase)
            v += Math.sin(y / 4.0 + phase * 1.3)
            v += Math.sin((x + y) / 5.5 + phase * 0.7)
            v += Math.sin(Math.sqrt((x - 16.0)**2 + (y - 16.0)**2) / 3.5 + phase)
            v = (v + 4.0) / 8.0  # normalize 0..1
            hsv_to_rgb(v, 1.0, 1.0)
          }
        }
      }
    end

    private

    def hsv_to_rgb(h, s, v)
      h6 = h * 6.0
      i  = h6.floor
      f  = h6 - i
      p  = v * (1 - s)
      q  = v * (1 - f * s)
      t  = v * (1 - (1 - f) * s)
      r, g, b = case i % 6
                when 0 then [v, t, p]
                when 1 then [q, v, p]
                when 2 then [p, v, t]
                when 3 then [p, q, v]
                when 4 then [t, p, v]
                when 5 then [v, p, q]
                end
      [(r * 255).round, (g * 255).round, (b * 255).round]
    end
  end
end
