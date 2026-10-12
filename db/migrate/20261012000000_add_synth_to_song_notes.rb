class AddSynthToSongNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :song_notes, :synth, :boolean # plays the score with the synthesizer instead of the song's audio
  end
end
