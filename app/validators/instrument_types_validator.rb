# frozen_string_literal: true

# Validates an array of Song::INSTRUMENT_TYPES, optionally excluding some (e.g. `validates :types, instrument_types: { except: :other }`)
class InstrumentTypesValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, types)
    allowed = Song::INSTRUMENT_TYPES.map(&:to_s) - Array(options[:except]).map(&:to_s)
    invalid = Array(types) - allowed
    record.errors.add(attribute, :inclusion, value: invalid.to_sentence) if invalid.any?
  end
end
