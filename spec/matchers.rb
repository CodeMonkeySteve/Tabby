# frozen_string_literal: true

Spec::Matchers.define :respond_with do |attributes|
  match do |obj|
    attributes.all? do |k, v|
      @method = k.to_sym
      @expect = v
      @actual = obj.send(@method)
      @expect == @actual
    end
  end
  failure_message_for_should do |_obj|
    "expected: #{@expect.inspect},\n" \
    "     got: #{@actual.inspect} (calling #{@method})"
  end
  failure_message_for_should_not do |_obj|
    "expected not: #{@expect.inspect} (calling #{@method})"
  end
end
