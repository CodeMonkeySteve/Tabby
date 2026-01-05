class SongsController < ApplicationController
  load_resource

  def index
@songs ||= Song.all
  end

  def show
  end

  def new
  end

  def edit
  end

  def create
  end

  def update
  end

  def destroy
    @song.destroy
  end

  def player
  end

  def score
    send_data(@song.score.read, filename: @song.score.original_filename, content_type: @song.score.mime_type, disposition: 'inline')
  end

  def audio
    @song.audio or return head :not_found
    send_data(@song.audio.read, filename: @song.audio.original_filename, content_type: @song.audio.mime_type, disposition: 'inline')
  end
end
