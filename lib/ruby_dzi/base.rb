require 'rubygems'
require 'fileutils'
require 'mini_magick'
require 'open-uri'
require 'net/http'

module RubyDzi
  class Base
    include MiniMagick

    attr_accessor :image_path, :name, :format, :output_ext, :quality, :dir, :tile_size, :overlap

    def initialize(image_path, store = FileStore.new)
      @store = store

      # set defaults
      @quality    = 75
      @dir        = '.'
      @tile_size  = 254
      @overlap    = 1
      @min_level  = 2
      @output_ext = 'dzi'

      @source_image = nil
      @image_path = image_path
    end

    def generate!(name, format = 'jpg')
      image = setup_image_for_tile_generation(name, format)
      orig_width, orig_height = image.width, image.height

      # iterate over all levels (= zoom stages)
      max_level(orig_width, orig_height).downto(@min_level) do |level|
        width, height = image.width, image.height

        current_level_dir = File.join(@levels_root_dir, level.to_s)
        @store.create_dir current_level_dir

        # iterate over columns
        x, col_count = 0, 0
        while x < width
          # iterate over rows
          y, row_count = 0, 0
          while y < height
            dest_path = File.join(current_level_dir, "#{col_count}_#{row_count}.#{@format}")
            tile_width, tile_height = tile_dimensions(x, y, @tile_size, @overlap)

            tmp_image = MiniMagick::Image.open(image.tempfile.path)
            save_cropped_image(tmp_image, dest_path, x, y, tile_width, tile_height, @quality)

            y += (tile_height - (2 * @overlap))
            row_count += 1
          end
          x += (tile_width - (2 * @overlap))
          col_count += 1
        end

        image.resize("50%")
      end

      # generate xml descriptor and write file
      write_xml_descriptor(@xml_descriptor_path,
      :tile_size => @tile_size,
      :overlap   => @overlap,
      :format    => @format,
      :width     => orig_width,
      :height    => orig_height)

      # destroy main image to free up allocated memory
      image.destroy!
    end

    def remove_files!
      file_remove_res = @store.remove_file(@xml_descriptor_path)
      dir_remove_res  = @store.remove_dir(@levels_root_dir)

      file_remove_res || dir_remove_res
    end

  protected

    def setup_image_for_tile_generation(name, format)
      @name   = name
      @format = format

      @levels_root_dir     = File.join(@dir, @name + '_files')
      @xml_descriptor_path = File.join(@dir, @name + '.' + @output_ext)
      remove_files!

      image = get_image(@image_path)

      image.strip # remove meta information
      image
    end

    def tile_dimensions(x, y, tile_size, overlap)
      overlapping_tile_size = tile_size + (2 * overlap)
      border_tile_size      = tile_size + overlap

      tile_width  = (x > 0) ? overlapping_tile_size : border_tile_size
      tile_height = (y > 0) ? overlapping_tile_size : border_tile_size

      return tile_width, tile_height
    end

    def max_level(width, height)
      return (Math.log([width, height].max) / Math.log(2)).ceil
    end

    def save_cropped_image(src, dest, x, y, width, height, quality = 75)
      if src.is_a? MiniMagick::Image
        img = src
      else
        img = MiniMagick::Image.open(src)
      end

      quality = quality * 100 if quality < 1

      img.crop("#{width}x#{height}+#{x}+#{y}")
      @store.save_image_file img, dest, quality

      # destroy cropped image to free up allocated memory
      img.destroy!
    end

    def write_xml_descriptor(path, attr)
      attr = { :xmlns => 'http://schemas.microsoft.com/deepzoom/2008' }.merge attr

      xml = "<?xml version='1.0' encoding='UTF-8'?>" +
      "<Image TileSize='#{attr[:tile_size]}' Overlap='#{attr[:overlap]}' " +
      "Format='#{attr[:format]}' xmlns='#{attr[:xmlns]}'>" +
      "<Size Width='#{attr[:width]}' Height='#{attr[:height]}'/>" +
      "</Image>"

      @store.save_file path, xml
    end

    def split_to_filename_and_extension(path)
      extension = File.extname(path).gsub('.', '')
      filename  = File.basename(path, '.' + extension)
      return filename, extension
    end

    def valid_url?(urlStr)
      url = URI.parse(urlStr)

      Net::HTTP.start(url.host, url.port) do |http|
        return http.head(url.request_uri).code == "200"
      end
    end

    def get_image(image_path)
      image = nil
      image = MiniMagick::Image.open(image_path)

      return image
    end

  end
end
