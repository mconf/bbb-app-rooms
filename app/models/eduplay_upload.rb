class EduplayUpload < ApplicationRecord
  validates :recording_id, presence: true

  # Override inspect to hide binary data
  def inspect
    inspected = super
    if thumbnail_data.present?
      inspected.gsub!(/thumbnail_data: "[^"]*"/, "thumbnail_data: \"[BINARY DATA #{thumbnail_data.bytesize} bytes]\"")
    end
    inspected
  end

  # Override to_s to hide binary data
  def to_s
    attrs = attributes.map do |key, value|
      if key == 'thumbnail_data' && value.present?
        "#{key}: [BINARY DATA #{value.bytesize} bytes]"
      else
        "#{key}: #{value.inspect}"
      end
    end
    "#<#{self.class.name} #{attrs.join(', ')}>"
  end

  # Override AwesomePrint's ai method to hide binary data
  def ai(options = {})
    if defined?(AwesomePrint)
      data_for_print = attributes.dup
      if data_for_print['thumbnail_data'].present?
        data_for_print['thumbnail_data'] = "[BINARY DATA #{thumbnail_data.bytesize} bytes]"
      end
      data_for_print.ai(options)
    else
      inspect
    end
  end

  def self.recording_uploads(recording_id)
    where(recording_id: recording_id)
  end

  # Delete all eduplay tokens that are older than 2 minutes
  def self.delete_old_tokens
    where('created_at < ?', 2.minutes.ago).destroy_all
  end
end
