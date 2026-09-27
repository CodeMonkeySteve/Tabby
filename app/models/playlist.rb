# frozen_string_literal: true

class Playlist < ApplicationRecord
  belongs_to :user
  belongs_to_many :songs

  validates :name, presence: true

  # Songs in playlist order
  def ordered_songs
    songs.in_order_of(:id, song_ids)
  end

  # Atomically adds or removes a song, without disturbing concurrent changes to the rest of the playlist
  def include_song!(song, included = true)
    ids =
      if included
        'CASE WHEN :id = ANY(song_ids) THEN song_ids ELSE array_append(song_ids, :id) END'
      else
        'array_remove(song_ids, :id)'
      end
    self.class.where(id:).update_all([ "song_ids = #{ids}, updated_at = :now", { id: song.id, now: Time.current } ])
    reload
  end
end
