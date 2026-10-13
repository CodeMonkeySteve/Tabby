# frozen_string_literal: true

# OmniAuth
module AuthenticationModel
  extend ActiveSupport::Concern

  included do
    has_many :credentials, dependent: nil

    validates :email, presence: true, uniqueness: true, email: true
  end

  module ClassMethods
    def find_or_create_from_omniauth!(auth, current_user = nil)
      name, email = auth[:info]&.values_at(:name, :email)
      cred = Credential.create_with(user: current_user).find_or_create_by!(provider: auth[:provider], uid: auth[:uid]) do |credential|
        credential.user ||= User.create_with(name:).find_or_create_by!(email:)
      end
      cred.user
    end
  end
end
