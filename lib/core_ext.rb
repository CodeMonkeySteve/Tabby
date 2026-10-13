# frozen_string_literal: true

module CoreExtensions
  module Possessive
    module String
      def possessive
        str = "#{self}'"
        str += 's' unless /(s|se|z|ze|ce|x|xe)$/i.match(self)
        str
      end
    end
  end

  module ToBool
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

  module ArrayInequality
    module Array
      def  <(other)
        (self <=> other or raise(ArgumentError, "#{inspect} < #{other.inspect}")).negative?
      end

      def <=(other)
        (self <=> other or raise(ArgumentError, "#{inspect} < #{other.inspect}")) <= 0
      end

      def >(other)
        (self <=> other or raise(ArgumentError, "#{inspect} < #{other.inspect}")).positive?
      end

      def >=(other)
        (self <=> other or raise(ArgumentError, "#{inspect} < #{other.inspect}")) >= 0
      end
    end
  end
end

CoreExtensions.constants.each do |ext_name|
  extension = CoreExtensions.const_get(ext_name)
  extension.constants.each do |mod|
    Kernel.const_get(mod).prepend(extension.const_get(mod))
  end
end
