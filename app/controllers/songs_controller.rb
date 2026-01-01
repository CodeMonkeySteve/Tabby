class SongsController < ApplicationController
  def show
    @song = Song.find(params[:id])
    render locals: { song: @song }
  end

  def score
    @song = Song.find(params[:id])
    send_data(@song.score.read, filename: @song.score.original_filename, content_type: @song.score.mime_type, disposition: 'inline')
  end

  def audio
    @song = Song.find(params[:id])
    if @song.audio
      send_data(@song.audio.read, filename: @song.audio.original_filename, content_type: @song.audio.mime_type, disposition: 'inline')
    else
      head :not_found
    end
  end
end
