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

    log = []
    song = Song.from_songsterr(match.url) do |message|
      log << message
      Turbo::StreamsChannel.broadcast_append_to(stream, target: "#{match.frame_id}_log", html: tag.li(message))
    end
    song.save!
    # the log is only worth keeping on the card for its warnings
    log = [] unless log.any? { it.start_with?('Warning:') }
    broadcast_card(stream, match, state: :imported, song:, user:, playlists: user.playlists.order(:name), log:)
  rescue ::Songsterr::Error, ActiveRecord::RecordInvalid => ex
    broadcast_card(stream, match, state: :failed, user:, error: ex.message)
  rescue StandardError
    broadcast_card(stream, match, state: :failed, user:, error: "Import failed unexpectedly") if stream
    raise
  end

  private

  def broadcast_card(stream, match, **locals)
    Turbo::StreamsChannel.broadcast_replace_to(stream, target: match.frame_id, partial: 'songs/songsterr_card',
                                                       locals: { match:, **locals })
  end

  def tag = ActionController::Base.helpers.tag
end
