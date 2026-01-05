# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :user
  # attribute :request
  # delegate :user_agent, to: :request, allow_nil: true

  # def user=(user)
  #   super
  #   PaperTrail.request.whodunnit = user&.id
  # end
end
