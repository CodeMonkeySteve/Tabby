# frozen_string_literal: true

module CoreExtensions
  # to_bool
  module String
    def to_bool(default = nil)
      str = downcase.strip
      if str.in? %w[true 1 yes on t]
        true
      elsif str.in? %w[false 0 no off f]
        false
      else
        default
      end
    end
  end

  module Numeric
    def to_bool(_default = nil) = !!nonzero?
  end

  module TrueClass
    def to_bool(_default = nil) = self
  end

  module FalseClass
    def to_bool(_default = nil) = self
  end

  module NilClass
    def to_bool(default = nil) = default
  end
end

CoreExtensions.constants.each do |mod|
  Kernel.const_get(mod).prepend(CoreExtensions.const_get(mod))
end
