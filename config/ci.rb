# frozen_string_literal: true

# Run using bin/ci

CI.run do
  step "Ruby audit", 'bin/ruby-audit check'
  step "Rubygem audit", 'bin/bundler-audit check'
  step "Importmap audit", 'bin/importmap audit'
  step "Security audit", 'bin/brakeman'
  step "Dependency load check", 'bin/rails zeitwerk:check'
  step "Ruby style", 'bin/rubocop'
  step "Tests", 'bin/rspec'
end