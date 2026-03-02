# lib/animations/bouncing_ball.rb
require_relative '../animation_registry'
module Animations
  class BouncingBall < Animation
    FRAMES = 32
    SIZE   = 32

    def initialize
      super(name: 'bouncing_ball', description: 'Multi-ball physics with color mixing', fps: 20)
    end

    def frames
      @frames ||= begin
        balls = [
          { x: 8.0, y: 8.0, vx: 0.9, vy: 0.7, r: 3, color: [255, 80,  80]  },
          { x: 20.0,y: 20.0,vx: -0.7,vy: 0.9, r: 3, color: [80,  80,  255] },
          { x: 16.0,y: 6.0, vx: 0.5, vy: -0.8,r: 2, color: [80,  255, 80]  }
        ]

        FRAMES.times.map {
          buf = Array.new(SIZE * SIZE, [0, 0, 0])

          balls.each do |ball|
            # Draw ball with soft edge
            (SIZE).times do |py|
              (SIZE).times do |px|
                dist = Math.sqrt((px - ball[:x])**2 + (py - ball[:y])**2)
                if dist < ball[:r] + 0.5
                  alpha = dist < ball[:r] - 0.5 ? 1.0 : [ball[:r] + 0.5 - dist, 0.0].max
                  old   = buf[py * SIZE + px]
                  cr    = [old[0] + (ball[:color][0] * alpha).round, 255].min
                  cg    = [old[1] + (ball[:color][1] * alpha).round, 255].min
                  cb    = [old[2] + (ball[:color][2] * alpha).round, 255].min
                  buf[py * SIZE + px] = [cr, cg, cb]
                end
              end
            end

            # Physics
            ball[:x] += ball[:vx]; ball[:y] += ball[:vy]
            ball[:vx] *= -1 if ball[:x] < ball[:r] || ball[:x] > SIZE - 1 - ball[:r]
            ball[:vy] *= -1 if ball[:y] < ball[:r] || ball[:y] > SIZE - 1 - ball[:r]
            ball[:x] = ball[:x].clamp(ball[:r], SIZE - 1 - ball[:r])
            ball[:y] = ball[:y].clamp(ball[:r], SIZE - 1 - ball[:r])
          end

          # Checkerboard bg
          buf.each_with_index.map { |px, idx|
            next px if px != [0,0,0]
            x = idx % SIZE; y = idx / SIZE
            (x/4 + y/4).even? ? [15,15,20] : [8,8,12]
          }
        }
      end
    end
  end
end
