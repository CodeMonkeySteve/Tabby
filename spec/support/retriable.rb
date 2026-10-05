# frozen_string_literal: true

require 'retriable'

# retry immediately, instead of backing off
Retriable.configure { it.sleep_disabled = true }
