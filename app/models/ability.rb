# frozen_string_literal: true

require 'cancan'

class Ability
  include CanCan::Ability

  def initialize(user)
    return unless user

    can %i[read update], User, id: user.id
    can :manage, Song
  end
end
