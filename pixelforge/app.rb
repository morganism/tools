#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sinatra'
require 'sinatra/json'
require 'json'
require_relative 'lib/animation_registry'
require_relative 'lib/bit_depth'

set :port, 4567
set :bind, '0.0.0.0'
set :public_folder, File.join(__dir__, 'public')
set :views, File.join(__dir__, 'views')

# ── Routes ──────────────────────────────────────────────────────────────────

get '/' do
  @animations = AnimationRegistry.list
  @bit_depths  = BitDepth::DEPTHS
  erb :index
end

# List all available animations
get '/api/animations' do
  json AnimationRegistry.list.map { |name|
    anim = AnimationRegistry.get(name)
    { name:, description: anim.description, frames: anim.frame_count, fps: anim.fps }
  }
end

# Get animation frames at a given bit depth
# Returns array of frames; each frame = array of 1024 palette-index integers (32×32)
# plus the palette for the requested bit depth
get '/api/animations/:name' do
  name      = params[:name]
  bit_depth = (params[:bit_depth] || 24).to_i
  anim      = AnimationRegistry.get(name)
  halt 404, json(error: "Animation '#{name}' not found") unless anim

  palette = BitDepth.palette(bit_depth)
  frames  = anim.frames.map { |frame|
    BitDepth.quantize(frame, bit_depth, palette)
  }

  json({
    name:,
    bit_depth:,
    width:   32,
    height:  32,
    fps:     anim.fps,
    palette:,
    frames:
  })
end

# Upload / store a custom animation (JSON body)
post '/api/animations' do
  request.body.rewind
  data = JSON.parse(request.body.read)
  name = AnimationRegistry.register_custom(data)
  json({ status: 'ok', name: })
rescue JSON::ParserError => e
  halt 400, json(error: e.message)
end
