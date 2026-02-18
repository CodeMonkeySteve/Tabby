# frozen_string_literal: true

require 'jellyfin'

module Song::Jellyfin
  extend ActiveSupport::Concern

  included do
    field :jellyfin_id, type: String, index: true

    before_save :set_jellyfin_id, if: ->{ !jellyfin_id || (%w[title artist] & changed).any? }
    before_save :set_cover, if: ->{ !cover_data && jellyfin_id_changed? && jellyfin_id.present? }
    before_save :set_audio, if: ->{ !audio_data && jellyfin_id_changed? && jellyfin_id.present? }
  end

  def jellyfin
    ::Jellyfin::Item.new('Id' => self.jellyfin_id)
  end

  def find_jellyfin
    songs = ::Jellyfin.items(searchTerm: title, Artists: artist, includeItemTypes: 'Audio', Recursive: true)
    if songs.empty?
      songs = ::Jellyfin.items(searchTerm: title, includeItemTypes: 'Audio', Recursive: true)
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

    songs
  end

  def set_jellyfin_id
    self.jellyfin_id = find_jellyfin.first&.id
  end

  def set_cover
    if (image_tag = jellyfin.dig('ImageTags', 'Primary'))
      res = jellyfin.get('Images/Primary', fillHeight: 480, fillWidth: 480, quality: 96, tag: image_tag)
    elsif (image_tag = jellyfin.dig('AlbumPrimaryImageTag'))
      album = Jellyfin::Item.new('Id' => jellyfin['AlbumId'])
      res = album.get('Images/Primary', fillHeight: 480, fillWidth: 480, quality: 96, tag: image_tag)
    end

    self.cover = StringIO.new(res.body, 'rb')  if image_tag
  end

  def set_audio
    res = jellyfin.get('Download')
    self.audio = StringIO.new(res.body, 'rb')
  end

  module ClassMethods
    def from_score(path)
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

      self.title ||= title
      self.artist ||= artist
      self.tempo ||= info['tempo']
      self.instruments ||= Song.normalize_instruments(info['tracks']&.pluck('name')).presence
    end
  end
end
