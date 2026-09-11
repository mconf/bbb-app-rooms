class SimpleJsonFormatter < ActiveSupport::Logger::SimpleFormatter
  @@pid = $$

  def call(severity, _time, _progname, msg)
    @@pid = $$ if @@pid != $$

    log = {
      "@timestamp": Time.now.utc,
      pid: @@pid,
      level: severity,
    }

    begin
      # so that lograge's logs aren't double quoted
      msg = JSON.parse(msg)
    rescue JSON::ParserError, TypeError
      # not JSON, log the message as it came
    end

    log[:message] = msg
    log.to_json + "\n"
  end
end
