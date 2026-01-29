# frozen_string_literal: true

require_relative '../config/environment'
require 'jellyfin'
require 'alpha_tab'

include ActionView::Helpers::NumberHelper

def import_score!(path)
  info = AlphaTab.new.score_info(path)

  title = info['title'].presence
  title or return
  artist = info['artist'].presence
  if artist.blank? && title.include?('-')
    artist, title = title.split('-', 2).map(&:strip)
  end
  if artist.blank? && (filename = File.basename(path, File.extname(path))).include?('-')
    artist, title = filename.split('-', 2).map(&:strip)
  end

  song = Song.where(title:, artist:).first
  if song && song.attributes.values_at(:title, :artist, :score, :audio, :cover).all?(&:present?)
    puts "✅"
    return
  end

  song ||= Song.new(title:, artist:, score: File.open(path, 'rb'))
  song.tempo ||= info['tempo']
  song.instruments ||= Song.normalize_instruments(info['tracks']&.pluck('name')).presence || %w[bass]
  puts "",
       "  Artist: #{song.artist}",
       "  Title: #{song.title}",
       "  Tempo: #{song.tempo} BPM",
       "  Instruments: #{song.instruments.join(', ')}"

  unless song.audio && song.cover
    jellyfin = find_jellyfin(title:, artist:)
    jellyfin_id = jellyfin&.dig('Id')
    puts "  jellyfin ID: #{jellyfin_id}"

    if !song.audio && jellyfin
      res = jellyfin.get('Download')
      puts "  Audio: #{res.headers['content-type']} #{number_to_human_size(res.body.length)}"
      song.audio = StringIO.new(res.body, 'rb')
    end

    if jellyfin && !song.cover
      if (image_tag = jellyfin.dig('ImageTags', 'Primary'))
        puts "  Image Tag: #{image_tag}"
        res = jellyfin.get('Images/Primary', fillHeight: 480, fillWidth: 480, quality: 96, tag: image_tag)
      elsif (image_tag = jellyfin.dig('AlbumPrimaryImageTag'))
        puts "  Album Image Tag: #{image_tag}"
        album = Jellyfin::Item.new('Id' => jellyfin['AlbumId'])
        res = album.get('Images/Primary', fillHeight: 480, fillWidth: 480, quality: 96, tag: image_tag)
      end

      if image_tag
        puts "  Image: #{res.headers['content-type']} #{number_to_human_size(res.body.length)}"
        song.cover = StringIO.new(res.body, 'rb')
      end
    end
  end

  song.save!
  puts
end

def find_jellyfin(title:, artist: nil)
  songs = Jellyfin.items(searchTerm: title, Artists: artist, includeItemTypes: 'Audio', Recursive: true)
  if songs.empty?
    songs = Jellyfin.items(searchTerm: title, includeItemTypes: 'Audio', Recursive: true)
  end

  if (songs.length > 1) && artist
    alts =
      songs.select { _1['Artists'].map(&:downcase).include?(artist.downcase) }.presence ||
      songs.select { _1['Artists'].map(&:downcase).any? { |a| a.include?(artist.downcase) } }
    songs = alts if alts.any?
  end

  if songs.length > 1
    alts = songs.select { _1['ProductionYear'].present? }
    if alts.length >= 1
      songs = alts.sort_by! { _1['ProductionYear'] }
    end
  end

  songs.first
end

$stdout.sync = true

ARGV.each do |path|
  path = Pathname.new(path)
  if path.directory?
    path.glob('*').each do |path|
      print "#{File.basename(path)} … "
      import_score!(path)
    end
  else
    print "#{File.basename(path)}: … "
    import_score!(path)
  end
end


