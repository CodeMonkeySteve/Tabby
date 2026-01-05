# frozen_string_literal: true

# NoBrainer / OmniAuth
module AuthenticationModel
  extend ActiveSupport::Concern

  included do
    field :name, type: String
    field :email, type: String, required: true, unique: true

    has_many :credentials
  end

  module ClassMethods
    def find_or_create_from_omniauth!(auth, current_user = nil)
      name, email = auth[:info]&.values_at(:name, :email)
      cred = Credential.where(provider: auth[:provider], uid: auth[:uid]).first_or_create! do
        user =
          current_user ||
          User.where(email: email).first_or_create!(name: name) ||
          User.create!(email: email, name: name)
        { user: user }
      end
      cred.user
    end
  end
end
