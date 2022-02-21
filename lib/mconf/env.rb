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

    def self.fetch_int(name, default=nil)
      v = ENV[name]
      if v.blank?
        if default.nil?
          raise "No value and no default set for #{name}"
        else
          default
        end
      else
        if !v.to_s.downcase.match(/^(\d)+$/)  # set but not an integer
          raise "Invalid value '#{v}' for integer casting"
        else
          ENV.fetch(name, default).to_i
        end
      end
    end
  end
end