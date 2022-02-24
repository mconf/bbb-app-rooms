module TestsHelper
   # FOR TESTS ONLY
   def self.gen_fake_res(options)
    max_recordings = 26
    limit = options[:limit]
    offset = options[:offset]
    r = {}
    r[:returncode] = 'SUCCESS'
    r[:recordings] = gen_fake_recordings(offset, limit, max_recordings)
    if offset + limit < max_recordings
      r[:nextpage] = 'true'
    else
      r[:nextpage] = 'false'
      if offset > max_recordings
        r[:messageKey] = 'noRecordings'
        r[:message] = 'There are no recordings for the meeting(s)'
      end
    end
    r
  end

  # FOR TESTS ONLY
  def self.gen_fake_recordings(offset, limit, max_recordings)
    return if offset > max_recordings
    limit = max_recordings - offset if offset + limit > max_recordings

    arr = []
    limit.times.reverse_each do |l|
      n = l + offset
      end_time = Time.now + 3600
      rec = {}
      rec[:recordID] = "recordID-#{n}-#{end_time}"
      rec[:meetingID] = "meetingID-#{n}-#{end_time}"
      rec[:internalMeetingID] = "internalMeetingID-#{n}-#{end_time}"
      rec[:name] = "Name-#{n}-#{end_time}"
      rec[:isBreakout] = "false"
      rec[:published] = [false, true].sample
      rec[:state] = rec[:published] ? "published" : "umpublished"
      rec[:startTime] = Time.now.to_i - 3600 - n
      rec[:endTime] = end_time
      rec[:size] = rand(1_000_000..10_000_000)
      rec[:rawSize] = "0"
      rec[:participants] = rand(1..50)
      rec[:metadata] = {}
      arr << rec
    end
    arr
  end
end