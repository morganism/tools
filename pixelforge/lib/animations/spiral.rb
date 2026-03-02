# lib/animations/spiral.rb
require_relative '../animation_registry'
module Animations
  class Spiral < Animation
    FRAMES = 24
    SIZE   = 32

    def initialize
      super(name: 'spiral', description: 'Rotating color spiral with hue cycling', fps: 15)
    end

    def frames
      @frames ||= FRAMES.times.map { |t|
        angle_offset = t * Math::PI * 2.0 / FRAMES
        SIZE.times.flat_map { |y|
          SIZE.times.map { |x|
            dx    = x - 15.5
            dy    = y - 15.5
            dist  = Math.sqrt(dx**2 + dy**2)
            angle = Math.atan2(dy, dx) + angle_offset
            hue   = ((angle / (Math::PI * 2) + dist / 10.0) % 1.0).abs
            sat   = [dist / 16.0, 1.0].min
            val   = dist < 1.0 ? 1.0 : [1.0 - (dist - 1.0) / 20.0, 0.0].max
            hsv_to_rgb(hue, sat, val)
          }
        }
      }
    end

    private

    def hsv_to_rgb(h, s, v)
      h6 = h * 6.0; i = h6.floor; f = h6 - i
      p = v*(1-s); q = v*(1-f*s); t2 = v*(1-(1-f)*s)
      r, g, b = case i%6
        when 0 then [v,t2,p]; when 1 then [q,v,p]
        when 2 then [p,v,t2]; when 3 then [p,q,v]
        when 4 then [t2,p,v]; when 5 then [v,p,q]
      end
      [(r*255).round,(g*255).round,(b*255).round]
    end
  end
end
