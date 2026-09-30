# frozen_string_literal: true

require 'cover_art'

module Song::CoverArt
  extend ActiveSupport::Concern

  # Attaches (without saving) the album cover of the song's recording from an online catalog, returning the CoverArt::Match, or nil
  # if none was found.  Raises CoverArt::Error if a catalog can't be searched or the image can't be downloaded.
  def fetch_cover_art
    match = ::CoverArt.search(artist:, title:) or return
    self.cover = ::CoverArt.download(match)
    match
  end
end
