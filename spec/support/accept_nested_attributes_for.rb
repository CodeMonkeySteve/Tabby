# frozen_string_literal: true

RSpec::Matchers.define :accept_nested_attributes_for do |attribute_name|
  match do |actual|
    expect(actual.class.method_defined?(:"#{attribute_name}_attributes=")).to be true
  end

  failure_message_for_should do |actual|
    "expected that #{actual} would accept_nested_attributes_for #{attribute_name}"
  end

  failure_message_for_should_not do |actual|
    "expected that #{actual} would not accept_nested_attributes_for #{attribute_name}"
  end

  description do
    "accept_nested_attributes_for #{expected}"
  end
end
