# frozen_string_literal: true

module Mconf
  # Masks credentials before they reach a log line, keeping a short prefix of long values so
  # we can still tell which one was used (e.g. after a BBB secret rotation).
  # Names and e-mails are not masked: support needs them, and log retention handles them.
  module LogFilter
    CREDENTIAL_KEY = /secret|token|passw/i
    PREFIX_LENGTH = 7
    # Below this, the prefix would give away too much of the value
    MIN_LENGTH_FOR_PREFIX = 24

    def self.mask(value)
      value = value.to_s
      return '[FILTERED]' if value.length < MIN_LENGTH_FOR_PREFIX

      "#{value[0, PREFIX_LENGTH]}[FILTERED]"
    end

    FILTER = ActiveSupport::ParameterFilter.new([
      lambda do |key, value|
        value.replace(mask(value)) if value.is_a?(String) && key.to_s.match?(CREDENTIAL_KEY)
      end
    ])

    def self.filter(params)
      FILTER.filter(params)
    end
  end
end
