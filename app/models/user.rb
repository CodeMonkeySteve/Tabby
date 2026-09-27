class User < ApplicationRecord
  include AuthenticationModel

  has_many :playlists
  has_many :play_histories
end
