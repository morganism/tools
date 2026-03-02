# lib/animation_registry.rb
# Registry for built-in and user-uploaded animations

require_relative 'animations/plasma'
require_relative 'animations/fire'
require_relative 'animations/spiral'
require_relative 'animations/matrix_rain'
require_relative 'animations/life'
require_relative 'animations/lissajous'
require_relative 'animations/bouncing_ball'

# ── Base class ───────────────────────────────────────────────────────────────
class Animation
  attr_reader :name, :description, :fps

  def initialize(name:, description:, fps: 12)
    @name        = name
    @description = description
    @fps         = fps
  end

  # Must return Array<Array<[r,g,b]>> – outer = frames, inner = 1024 pixels
  def frames
    raise NotImplementedError
  end

  def frame_count
    frames.length
  end
end

# ── Registry ─────────────────────────────────────────────────────────────────
module AnimationRegistry
  @registry = {}

  def self.register(anim)
    @registry[anim.name] = anim
  end

  def self.list
    @registry.keys
  end

  def self.get(name)
    @registry[name]
  end

  # Accept raw JSON upload format:
  # { "name": "foo", "fps": 10, "description": "...",
  #   "frames": [ [[r,g,b], ...1024...], ... ] }
  def self.register_custom(data)
    name   = data['name'] || "custom_#{Time.now.to_i}"
    fps    = (data['fps'] || 10).to_i
    desc   = data['description'] || 'User-uploaded animation'
    raw_frames = data['frames']

    anim = Class.new(Animation) do
      define_method(:frames) { raw_frames.map { |f| f.map { |px| Array(px) } } }
    end.new(name:, description: desc, fps:)

    register(anim)
    name
  end

  # Register built-ins
  register Animations::Plasma.new
  register Animations::Fire.new
  register Animations::Spiral.new
  register Animations::MatrixRain.new
  register Animations::Life.new
  register Animations::Lissajous.new
  register Animations::BouncingBall.new
end
