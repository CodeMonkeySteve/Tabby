# frozen_string_literal: true

class Playlist < ApplicationRecord
  extend FriendlyId

  belongs_to :user
  belongs_to_many :songs

  validates :name, presence: true

  # unique per user, since playlists are only found within the current user's
  friendly_id :name, use: %i[scoped sequentially_slugged history reserved], scope: :user, reserved_words: %w[new],
                     treat_reserved_as_conflict: true

  # The saved slug, for URLs that work while the playlist has unsaved changes, e.g. redisplaying the edit form with a new name
  def to_param
    slug_in_database || super
  end

  def should_generate_new_friendly_id?
    will_save_change_to_name? || super
  end

  # Songs in playlist order
  def ordered_songs
    songs.in_order_of(:id, song_ids)
  end

  # Atomically adds or removes a song, without disturbing concurrent changes to the rest of the playlist
  def include_song!(song, included: true)
    ids =
      if included
        'CASE WHEN :id = ANY(song_ids) THEN song_ids ELSE array_append(song_ids, :id) END'
      else
        'array_remove(song_ids, :id)'
      end
    self.class.where(id:).update_all(["song_ids = #{ids}, updated_at = :now", { id: song.id, now: Time.current }])
    reload
  end

  # Moves songs to the given order, keeping any added concurrently at the end and dropping any since removed
  def reorder_songs!(ids)
    with_lock do
      update!(song_ids: (ids & song_ids) | song_ids)
    end
  end

  # The songs before and after the given one, either of which is nil at the ends (or both, if it isn't in the playlist)
  def neighbors_of(song)
    index = song_ids.index(song.id) or return [nil, nil]
    previous_id = song_ids[index - 1] if index.positive?
    next_id = song_ids[index + 1]
    neighbors = Song.where(id: [previous_id, next_id].compact).index_by(&:id)
    neighbors.values_at(previous_id, next_id)
  end
end
