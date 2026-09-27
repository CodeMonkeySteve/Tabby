# frozen_string_literal: true

class Song < ApplicationRecord
  include PassiveColumns
  include Sluggable
  include Song::Jellyfin
  include Song::Songsterr

    validates :title, presence: true
  validates :score_data, presence: true

  slug_from :title, :artist

  # only needed by the player
  passive_columns :sync_points

  has_many :play_histories

  after_destroy { Playlist.where('? = ANY(song_ids)', id).update_all(['song_ids = array_remove(song_ids, ?)', id]) }

  include ScoreUploader::Attachment(:score)
  include ApplicationUploader::Attachment(:audio)
  include ImageUploader::Attachment(:cover)

  def self.normalize_instruments(names)
    names.filter_map do |name|
      case name
        when /\bbass\b/i then 'bass'
        when /^pista\b/i then nil
        else name
      end
    end
  end
end
