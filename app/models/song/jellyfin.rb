# frozen_string_literal: true

require 'jellyfin'

module Song::Jellyfin
  extend ActiveSupport::Concern

  included do
    before_save :set_cover, if: ->{ !cover_data && jellyfin_id_changed? }
    before_save :set_audio, if: ->{ !audio_data && jellyfin_id_changed? }
  end

  def jellyfin
    if jellyfin_id
      @jellyfin ||= ::Jellyfin::Item.new('Id' => jellyfin_id) #.ensure!
    end
  end

  def find_jellyfin
    songs = ::Jellyfin.items(searchTerm: title, Artists: artist, includeItemTypes: 'Audio', Recursive: true)
    if songs.empty?
      songs = ::Jellyfin.items(searchTerm: title, includeItemTypes: 'Audio', Recursive: true)
    end

    if (songs.length > 1) && artist
      alts =
        songs.select { it['Artists'].map(&:downcase).include?(artist.downcase) }.presence ||
        songs.select { it['Artists'].map(&:downcase).any? { |a| a.include?(artist.downcase) } }
      songs = alts if alts.any?
    end

    if songs.length > 1
      alts = songs.select { it['ProductionYear'].present? }
      if alts.length >= 1
        songs = alts.sort_by! { it['ProductionYear'] }
      end
    end

    songs
  end

  def jellyfin_cover(item)
    if (image_tag = item.dig('ImageTags', 'Primary'))
      res = item.get('Images/Primary', fillHeight: 480, fillWidth: 480, quality: 96, tag: image_tag)
    elsif (image_tag = item['AlbumPrimaryImageTag'])
      album = ::Jellyfin::Item.new('Id' => item['AlbumId'])
      res = album.get('Images/Primary', fillHeight: 480, fillWidth: 480, quality: 96, tag: image_tag)
    end

    StringIO.new(res.body, 'rb') if image_tag
  end

  def set_cover
    jellyfin or return

    # if (image_tag = jellyfin.dig('ImageTags', 'Primary'))
    #   res = jellyfin.get('Images/Primary', fillHeight: 480, fillWidth: 480, quality: 96, tag: image_tag)
    # elsif (image_tag = jellyfin.dig('AlbumPrimaryImageTag'))
    #   album = Jellyfin::Item.new('Id' => jellyfin['AlbumId'])
    #   res = album.get('Images/Primary', fillHeight: 480, fillWidth: 480, quality: 96, tag: image_tag)
    # end
    #
    # self.cover = StringIO.new(res.body, 'rb')  if image_tag
  end

  def set_audio
    jellyfin or return

    res = jellyfin.get('Download')
    self.audio = StringIO.new(res.body, 'rb')
  end

  module ClassMethods
    def from_score(path)
      begin
        info = AlphaTab.new.score_info(path)
      rescue Nodo::JavaScriptError => e
        puts e.message
        return nil
      end

      title = info['title'].presence
      title or return

      artist = info['artist'].presence
      if artist.blank? && title.include?('-')
        artist, title = title.split('-', 2).map(&:strip)
      end
      if artist.blank? && (filename = File.basename(path, File.extname(path))).include?('-')
        artist, title = filename.split('-', 2).map(&:strip)
      end

      song = Song.find_or_initialize_by(title:, artist:)
      unless song.score
        song.score = File.open(path, 'rb')
        song.track_types = Song.track_types_from(info)
      end
      song.tempo ||= info['tempo']

      if !song.jellyfin_id && (jellyfin = song.find_jellyfin&.first)
        song.jellyfin_id = jellyfin.id

        cover = song.jellyfin_cover(jellyfin)
        song.cover = cover if cover
      end

      song
    end
  end
end
