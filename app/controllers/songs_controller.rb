class SongsController < ApplicationController
  def show
    @song = Song.find(params[:id])
    render locals: { song: @song }
  end

  def score
    @song = Song.find(params[:id])
    send_data(@song.score.download, filename: @song.score.filename.to_s, content_type: @song.score.content_type, disposition: 'inline')
  end

  def audio
    @song = Song.find(params[:id])
    if @song.audio.attached?
      send_data(@song.audio.download, filename: @song.audio.filename.to_s, content_type: @song.audio.content_type, disposition: 'inline')
    else
      head :not_found
    end
  end
end
