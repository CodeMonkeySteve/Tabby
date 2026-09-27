require 'cancan'

class Ability
  include CanCan::Ability

  def initialize(user)
    if !user
      ;

    else
      can %i(read update), User, id: user.id
      can :manage, Song
    end
  end
end
