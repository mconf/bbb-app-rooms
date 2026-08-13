# frozen_string_literal: true

# Holds state scoped to the current unit of work (a request or a job). Rails
# resets it automatically when the unit of work ends

class Current < ActiveSupport::CurrentAttributes
  MAX_MOODLE_CALLS = 15

  attribute :moodle_calls, :moodle_calls_total
  before_reset :log_moodle_calls

  def record_moodle_call(wsfunction:, status:, duration: nil, errorcode: nil)
    self.moodle_calls ||= []
    self.moodle_calls_total = (moodle_calls_total || 0) + 1
    return if moodle_calls.size >= MAX_MOODLE_CALLS

    moodle_calls << {
      wsfunction: wsfunction,
      status: status,
      duration: duration&.round(3),
      errorcode: errorcode
    }.compact
  end

  def moodle_calls_count_label
    return moodle_calls.size.to_s if moodle_calls_total.to_i <= moodle_calls.size

    "#{moodle_calls.size}/#{moodle_calls_total} (truncated)"
  end

  def log_moodle_calls
    return if moodle_calls.blank?

    summary = moodle_calls.map do |call|
      "#{call[:wsfunction]}:#{call[:errorcode] || call[:status]}:#{call[:duration]}s"
    end.join(', ')

    Rails.logger.info "[MOODLE SEQ] calls=#{moodle_calls_count_label} " \
                      "errors=#{moodle_calls.count { |c| c[:status] != 'ok' }} " \
                      "[#{summary}]"
  end
end
