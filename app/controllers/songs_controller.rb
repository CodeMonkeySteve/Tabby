class SongsController < ApplicationController
  before_action :find_song, only: %i[edit update destroy player score audio sync_points]

  def index
    @songs ||= Song.all.order_by(:artist, :title)
  end

  def new
    @song = Song.new
  end

  def edit
  end

  def create
    @song = Song.new(song_params)
    respond_to do |format|
      if @song.save
        format.html { redirect_to @song, notice: "Song was successfully created." }
        format.json { render :player, status: :created, location: @song }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @song.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @song.update(song_params)
        format.html { redirect_to @song, notice: "Song was successfully updated.", status: :see_other }
        format.json { render :player, status: :ok, location: @song }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @song.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @song.destroy
    respond_to do |format|
      format.html { redirect_to songs_path, notice: "Song was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def player
    render layout: false
  end

  def score
    send_data(@song.score.read, filename: @song.score.original_filename, content_type: @song.score.mime_type, disposition: 'inline')
  end

  def audio
    @song.audio or return head :not_found
    send_data(@song.audio.read, filename: @song.audio.original_filename, content_type: @song.audio.mime_type, disposition: 'inline')
  end

  def sync_points
    points = (params[:sync_points] || []).map do |sp|
      sp.permit(:barIndex, :barOccurence, :barPosition, :millisecondOffset).to_h
    end

    if @song.update(sync_points: points)
      head :ok
    else
      render json: @song.errors, status: :unprocessable_entity
    end
  end

private

  def find_song
    @song = Song.find_by_slug_or_id(params[:id])
  end

  def song_params
    sync_points = JSON.parse(params[:song][:sync_points].presence || '[]')
    params.require(:song)
      .permit(:title, :artist, :sync_points, :cover, :cover_data,
        score: {}, audio: {},
        instruments: []
      )
      .with_defaults(instruments: %w[bass])
      .merge(sync_points:)
  end
end
