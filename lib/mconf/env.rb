module Mconf
  module Env
    TRUTHY_VALUES = %w(true yes 1).freeze
    FALSEY_VALUES = %w(false no 0).freeze

    def self.fetch(name, default=nil)
      ENV.fetch(name, default)
    end

    def self.fetch_boolean(name, default=nil)
      v = ENV[name].to_s.downcase
      return true if TRUTHY_VALUES.include?(v)
      return false if FALSEY_VALUES.include?(v)
      return default unless default.nil?
      raise "Invalid value '#{v}' for boolean casting"
    end
  end
end