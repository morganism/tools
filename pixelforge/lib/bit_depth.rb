# lib/bit_depth.rb
# Palette generation and color quantization for various bit depths
# Each animation frame is stored as 24-bit RGB triples; this module
# reduces them to the target bit depth palette.

module BitDepth
  # Supported depths and their human labels
  DEPTHS = {
    1  => '1-bit  (2 colors  – monochrome)',
    2  => '2-bit  (4 colors  – CGA)',
    4  => '4-bit  (16 colors – EGA)',
    8  => '8-bit  (256 colors – VGA)',
    16 => '16-bit (65,536 colors – High Color)',
    24 => '24-bit (16M colors – True Color)'
  }.freeze

  # ── Palette builders ────────────────────────────────────────────────────

  # Returns an Array of [r, g, b] entries for the given bit depth
  def self.palette(bits)
    case bits
    when 1  then mono_palette
    when 2  then cga_palette
    when 4  then ega_palette
    when 8  then vga_palette
    when 16 then nil          # high-color: no indexed palette, pack directly
    when 24 then nil          # true-color: return raw RGB
    else raise ArgumentError, "Unsupported bit depth: #{bits}"
    end
  end

  # ── Quantization ────────────────────────────────────────────────────────

  # frame   – Array of 1024 [r,g,b] triples (32×32 pixels)
  # bits    – target bit depth
  # palette – Array of [r,g,b] entries (nil for 16/24-bit)
  #
  # Returns a Hash:
  #   { pixels: Array<Integer>, palette: Array<[r,g,b]>|nil }
  #
  # pixels for indexed modes = palette indices (0..palette.size-1)
  # pixels for 16-bit = packed r5g6b5 integers
  # pixels for 24-bit = packed 0xRRGGBB integers
  def self.quantize(frame, bits, palette)
    case bits
    when 1, 2, 4, 8
      { pixels: frame.map { |px| nearest_index(px, palette) }, palette: }
    when 16
      { pixels: frame.map { |px| pack_r5g6b5(px) }, palette: nil }
    when 24
      { pixels: frame.map { |px| pack_rgb24(px) }, palette: nil }
    else
      raise ArgumentError, "Unsupported bit depth: #{bits}"
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  def self.nearest_index(px, palette)
    r, g, b = px
    best_i  = 0
    best_d  = Float::INFINITY
    palette.each_with_index do |(pr, pg, pb), i|
      d = (r - pr)**2 + (g - pg)**2 + (b - pb)**2
      if d < best_d
        best_d = d
        best_i = i
      end
    end
    best_i
  end
  private_class_method :nearest_index

  def self.pack_r5g6b5(px)
    r, g, b = px
    ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
  end
  private_class_method :pack_r5g6b5

  def self.pack_rgb24(px)
    r, g, b = px
    (r << 16) | (g << 8) | b
  end
  private_class_method :pack_rgb24

  # ── Built-in palettes ────────────────────────────────────────────────────

  def self.mono_palette
    [[0, 0, 0], [255, 255, 255]]
  end

  def self.cga_palette
    [
      [0,   0,   0  ],
      [0,   170, 170],
      [170, 0,   170],
      [170, 170, 170]
    ]
  end

  def self.ega_palette
    [
      [0,0,0], [0,0,170], [0,170,0], [0,170,170],
      [170,0,0], [170,0,170], [170,85,0], [170,170,170],
      [85,85,85], [85,85,255], [85,255,85], [85,255,255],
      [255,85,85], [255,85,255], [255,255,85], [255,255,255]
    ]
  end

  def self.vga_palette
    pal = []
    # 216-color web-safe cube
    [0, 95, 135, 175, 215, 255].each do |r|
      [0, 95, 135, 175, 215, 255].each do |g|
        [0, 95, 135, 175, 215, 255].each do |b|
          pal << [r, g, b]
        end
      end
    end
    # 24 grayscale ramp (skip 0 and 255, already in cube)
    24.times { |i| v = 8 + i * 10; pal << [v, v, v] }
    # 16 system colors (classic VGA)
    pal += [
      [0,0,0],[128,0,0],[0,128,0],[128,128,0],
      [0,0,128],[128,0,128],[0,128,128],[192,192,192],
      [128,128,128],[255,0,0],[0,255,0],[255,255,0],
      [0,0,255],[255,0,255],[0,255,255],[255,255,255]
    ]
    pal.first(256)
  end
end
