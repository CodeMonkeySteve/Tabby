# frozen_string_literal: true

class Credential < ApplicationRecord
  PROVIDERS = {
    google_oauth2: "Google",
  }.freeze

  belongs_to :user

  enum :provider, PROVIDERS.keys.index_with(&:to_s), validate: true

  validates :uid, presence: true, uniqueness: { scope: :provider }
end
