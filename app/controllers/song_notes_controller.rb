# frozen_string_literal: true

class SongNotesController < ApplicationController
  def update
    song = Song.find_by_slug_or_id!(params[:song_id])
    note = song.note || song.build_note
    if note.update(note_params)
      head :no_content
    else
      render json: note.errors, status: :unprocessable_entity
    end
  end

private

  def note_params
    params.require(:song_note)
      .permit(*SongNote::PLAYBACK_ATTRIBUTES, tracks: [], muted_tracks: [], solo_tracks: [], track_volumes: {}, track_tunings: {})
  end
end
