require 'bigbluebutton_api'
include BbbApi

OUTPUTFILE = "tmp/output_update_scheduled_meetings.log"
DRYRUN = ENV['DRYRUN'] == '1' ? true : false

def puts2(file, str)
  file.puts str
  puts str
end

def run(logfile, dryrun=true)
  global_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  puts2 logfile, "Starting #{__FILE__} in #{dryrun ? 'DRYRUN' : 'REAL'} mode..."
  errors = {}

  updated_rooms = 0
  Room.find_each do |room|
    begin
      options = {
        limit: 1,
        offset: 0,
        sort_by: 'start_time',
        order_by: 'desc',
        includeRecordings: true,
      }
      res = get_all_meetings(room, options)
      meetings, no_more_meetings = res

      if !no_more_meetings
        puts2 logfile, "WARNING: Room handler='#{room.handler}' has more pages of results — only the first page was evaluated"
      end

      if meetings.any?
        # get_all_meetings sorts internally by endTime; sort by createDate here to select the
        # correct most-recent meeting, especially when the server ignores the limit param.
        sorted = meetings.sort_by { |m| m.dig(:meeting, :createDate).to_s }.reverse
        meeting = sorted.first[:meeting]

        if meeting
          begin
            last_meeting_date = Time.zone.parse(meeting[:createDate].to_s)
          rescue ArgumentError, TypeError => e
            puts2 logfile, "ERROR: Could not parse createDate='#{meeting[:createDate]}' for Room handler='#{room.handler}': #{e.message}"
            errors[room.handler] = "#{e.class}: #{e.message}"
            next
          end

          puts2 logfile, "\nRoom handler='#{room.handler}', last_meeting_date='#{last_meeting_date}'"
          updated_rooms += 1
          if dryrun
            updated_sched_count = room.scheduled_meetings.count
          else
            updated_sched_count = room.scheduled_meetings.update_all(last_meeting_date: last_meeting_date)
          end
          puts2 logfile, "Scheduled meetings updated: #{updated_sched_count}"
        end
      else
        puts2 logfile, "No meetings found for Room handler='#{room.handler}'"
      end
    rescue => e
      puts2 logfile, "ERROR processing Room handler='#{room.handler}': #{e.class}: #{e.message}"
      errors[room.handler] = "#{e.class}: #{e.message}"
    end
  end

  if errors.any?
    puts2 logfile, "\nGot #{errors.count} errors:\n" \
    "#{errors.keys.inspect}"
    errors.each do |k, v|
      puts2 logfile, "  handler=#{k}, #{v}"
    end
  end

  puts2 logfile, "\nRooms total: #{Room.count}, Rooms updated: #{updated_rooms}\n"

  puts2 logfile, "Done. Time elapsed: #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - global_start_time).round(3)}s"
end

File.open(OUTPUTFILE, 'w') do |logfile|
  run(logfile, DRYRUN)
end
