# frozen_string_literal: true

require 'songsterr'

# Imports a Songsterr song in the background, broadcasting its progress and result to the user's search result card
class SongsterrImportJob < ApplicationJob
  # Time for the importing card to subscribe to its stream before the first broadcast, which is otherwise lost
  START_DELAY = 2.seconds

  # The Turbo stream for a user's import of a match
  def self.stream(user, match) = [user, "songsterr_import_#{match.song_id}"]

  def perform(user, match_hash)
    match = Song::SongsterrMatch.new(**match_hash)
    stream = self.class.stream(user, match)

    song = Song.from_songsterr(match.url) do |message|
      Turbo::StreamsChannel.broadcast_append_to(stream, target: "#{match.frame_id}_log", html: tag.li(message))
    end
    song.save!
    broadcast_card(stream, match, state: :imported, song:)
  rescue ::Songsterr::Error, ActiveRecord::RecordInvalid => ex
    broadcast_card(stream, match, state: :failed, error: ex.message)
  rescue StandardError
    broadcast_card(stream, match, state: :failed, error: "Import failed unexpectedly") if stream
    raise
  end

  private

  def broadcast_card(stream, match, **locals)
    Turbo::StreamsChannel.broadcast_replace_to(stream, target: match.frame_id, partial: 'songs/songsterr_card',
                                                       locals: { match:, **locals })
  end

  def tag = ActionController::Base.helpers.tag
end
