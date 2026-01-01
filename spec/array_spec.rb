# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CoreExtensions' do
  describe 'ArrayInequality' do
    it '<' do
      expect([42]).to be < [43]
      expect([42]).not_to be < [41]
      expect([42]).not_to be < []
      expect { [42] < nil }.to raise_error(ArgumentError)
    end

    it '<=' do
      expect([42]).to be <= [42]
      expect([42]).to be <= [43]
      expect([42]).not_to be <= [41]
      expect([42]).not_to be <= []
      expect { [42] <= nil }.to raise_error(ArgumentError)
    end

    it '>' do
      expect([42]).not_to be > [43]
      expect([42]).to be > [41]
      expect([42]).to be > []
      expect { [42] > nil }.to raise_error(ArgumentError)
    end

    it '>=' do
      expect([42]).to be >= [41]
      expect([42]).to be >= [42]
      expect([42]).not_to be >= [43]
      expect([42]).to be >= []
      expect { [42] >= nil }.to raise_error(ArgumentError)
    end
  end
end
