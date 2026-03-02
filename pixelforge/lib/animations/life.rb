# lib/animations/life.rb
require_relative '../animation_registry'
module Animations
  class Life < Animation
    FRAMES = 48
    SIZE   = 32

    def initialize
      super(name: 'life', description: "Conway's Game of Life – R-pentomino seed", fps: 8)
    end

    def frames
      @frames ||= begin
        grid = Array.new(SIZE * SIZE, 0)
        # R-pentomino near center
        seed = [[15,14],[16,14],[14,15],[15,15],[15,16]]
        seed.each { |x, y| grid[y * SIZE + x] = 1 }

        FRAMES.times.map {
          pixels = grid.map { |c|
            age   = c
            alive = age > 0
            if alive
              intensity = [age * 20, 255].min
              [0, intensity, (intensity * 0.4).round]
            else
              [0, 0, 0]
            end
          }
          grid = step(grid)
          pixels
        }
      end
    end

    private

    def step(grid)
      new_grid = Array.new(SIZE * SIZE, 0)
      SIZE.times do |y|
        SIZE.times do |x|
          nbrs = 0
          (-1..1).each do |dy|
            (-1..1).each do |dx|
              next if dx == 0 && dy == 0
              nx = (x + dx) % SIZE
              ny = (y + dy) % SIZE
              nbrs += 1 if grid[ny * SIZE + nx] > 0
            end
          end
          cur   = grid[y * SIZE + x]
          alive = cur > 0
          if alive && (nbrs == 2 || nbrs == 3)
            new_grid[y * SIZE + x] = cur + 1
          elsif !alive && nbrs == 3
            new_grid[y * SIZE + x] = 1
          end
        end
      end
      new_grid
    end
  end
end
