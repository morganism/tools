# lib/animations/lissajous.rb
require_relative '../animation_registry'
module Animations
  class Lissajous < Animation
    FRAMES = 48
    SIZE   = 32

    def initialize
      super(name: 'lissajous', description: 'Lissajous figures with color trails', fps: 20)
    end

    def frames
      @frames ||= begin
        steps = 400
        FRAMES.times.map { |t|
          phase = t * Math::PI * 2.0 / FRAMES
          buf   = Array.new(SIZE * SIZE, [0, 0, 0])
          # decay existing
          steps.times do |i|
            frac = i.to_f / steps
            a_phase = frac * Math::PI * 6 + phase
            x = ((Math.sin(a_phase) * 13 + 15.5)).round.clamp(0, 31)
            y = ((Math.sin(frac * Math::PI * 4) * 13 + 15.5)).round.clamp(0, 31)
            hue = (frac + t.to_f / FRAMES) % 1.0
            r, g, b = hsv(hue, 1.0, frac)
            old = buf[y * SIZE + x]
            buf[y * SIZE + x] = [
              [old[0], r].max, [old[1], g].max, [old[2], b].max
            ]
          end
          buf
        }
      end
    end

    private

    def hsv(h, s, v)
      h6=h*6.0; i=h6.floor; f=h6-i
      p=v*(1-s); q=v*(1-f*s); t2=v*(1-(1-f)*s)
      r,g,b=case i%6
        when 0 then [v,t2,p]; when 1 then [q,v,p]
        when 2 then [p,v,t2]; when 3 then [p,q,v]
        when 4 then [t2,p,v]; when 5 then [v,p,q]
      end
      [(r*255).round,(g*255).round,(b*255).round]
    end
  end
end
