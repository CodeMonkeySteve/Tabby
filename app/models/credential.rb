# frozen_string_literal: true

class Credential < ApplicationRecord
  include NoBrainer::Document::Timestamps

  PROVIDERS = {
    google_oauth2: "Google",
  }.freeze

  belongs_to :user, required: true

  field :provider, type: Enum, required: true, in: PROVIDERS.keys
  field :uid,                  required: true, unique: { scope: :provider }
  field :token,    type: Hash

  index %i(provider uid)
end
