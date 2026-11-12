module Mconf
  module Maintenance
    # Used when the env value has no offset
    TIME_ZONE = 'Brasilia'.freeze

    def self.active?
      return @active unless @active.nil?

      config = Rails.application.config
      @active = config.theme == 'rnp' &&
                config.maintenance_enabled &&
                valid_window?
    end

    def self.valid_window?
      starts_at.present? && ends_at.present? && ends_at > starts_at
    end

    def self.starts_at
      window[:starts_at]
    end

    def self.ends_at
      window[:ends_at]
    end

    def self.overlaps?(from, to)
      return false unless active? && from.present? && to.present?

      from < ends_at && to > starts_at
    end

    # The config comes from the env, so the window is parsed once and reused
    def self.window
      @window ||= {
        starts_at: parse(Rails.application.config.maintenance_start),
        ends_at: parse(Rails.application.config.maintenance_end)
      }
    end

    # Drops the memoized values, for tests and the console
    def self.reset!
      @window = nil
      @active = nil
    end

    # A malformed value disables the feature instead of raising
    def self.parse(value)
      return nil if value.blank?

      ActiveSupport::TimeZone[TIME_ZONE].iso8601(value)
    rescue ArgumentError
      nil
    end
  end
end
