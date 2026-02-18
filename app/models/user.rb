class User < ApplicationRecord
  include NoBrainer::Document::Timestamps
  include AuthenticationModel

  has_many :playlists
end
