$(document).on('turbolinks:load', function(){
  if(window.location.href.includes('/scheduled_meetings')){
    var valueSelect = document.getElementsByName("scheduled_meeting[duration]")[0],
      contentCustomDuration = document.getElementById("content_custom_duration")
    valueSelect?.addEventListener('change', controlCustomDuration)

    var datePicker = document.getElementsByName("scheduled_meeting[date]")[0];
    datePicker?.addEventListener('change', checkTime);

    function controlCustomDuration(e) {
      let valueSelectDuration = e.target.value;
      valueSelectDuration == 0 ? contentCustomDuration.classList.add('d-block') :
        contentCustomDuration.classList.remove('d-block')
    }

    const createMoodleCalendarCheckbox = $('input[name="scheduled_meeting[create_moodle_calendar_event]"].form-check-input');
    if (createMoodleCalendarCheckbox.length) {
      const canCreateCalendar = createMoodleCalendarCheckbox[0].dataset.canCreate;
      const hintIcon = createMoodleCalendarCheckbox.closest('.form-check').find('.icon-label-hint');

      if (canCreateCalendar == 'true') { // Only apply JS logic if the Moodle function is configured
        var persisted = createMoodleCalendarCheckbox.data('persisted');
        var replicated = createMoodleCalendarCheckbox.data('replicated');
        var hintText;

        if (persisted) { // Edit action
          createMoodleCalendarCheckbox.prop('disabled', true);
          if (replicated) {
            createMoodleCalendarCheckbox.prop('checked', true);
            hintText = I18n.t('default.scheduled_meeting.tooltip.replicate_in_moodle_calendar');
          } else {
            createMoodleCalendarCheckbox.prop('checked', false);
            hintText = I18n.t('default.scheduled_meeting.tooltip.disable_replicate_in_moodle_calendar');
          }
        } else { // New action
          createMoodleCalendarCheckbox.prop('checked', true);
          // Checkbox is already enabled by ERB if canCreateCalendar is true
          hintText = I18n.t('default.scheduled_meeting.tooltip.create_moodle_calendar_event');
        }
        if (hintIcon.length) {
          hintIcon.attr("title", hintText); // Update title if JS logic applies
        }
      } else {
        createMoodleCalendarCheckbox.prop('disabled', true);
        createMoodleCalendarCheckbox.prop('checked', false);
      }
      // Ensure Bootstrap tooltip is initialized/updated with the correct title (either from ERB or JS)
      if (hintIcon.length && hintIcon[0]) {
        var tooltipInstance = bootstrap.Tooltip.getInstance(hintIcon[0]);
        if (tooltipInstance) {
          tooltipInstance.dispose(); // Dispose of old instance to ensure new title is picked up correctly
        }
        new bootstrap.Tooltip(hintIcon[0]); // Create new instance
      }
    }

    if(window.location.href.includes('/edit')){
      var duration = document.getElementsByName("scheduled_meeting[custom_duration]")[0].value,
          durationSeconds = (duration.split(':')[0] * 60 * 60 ) + ( duration.split(':')[1] * 60 ),
          durationsDefault = []
      valuesDurationsDefault = document.getElementsByName('scheduled_meeting[duration]')[0].options
      transformTimeToDuration(durationSeconds)

      function transformTimeToDuration(duration) {
        for(var i = 0; i < valuesDurationsDefault.length; i++) {
          durationsDefault.push(valuesDurationsDefault[i].value)
          if (durationsDefault.includes(duration.toString())){
            valueSelect.value = duration
            contentCustomDuration.classList.remove('d-block')
            break
          }
          else {
            valueSelect.value = 0
            contentCustomDuration.classList.add('d-block')
          }
        }
      }
    }

    function checkTime(e) {
      var dateFormat = $(".datepicker").first().data('format');
      let selectedDate;
      if (dateFormat === 'd/m/Y') {
        let dataString = e.target.value.split("/");
        selectedDate = new Date(dataString[2], dataString[1] - 1, dataString[0]);
      } else {
        selectedDate = new Date(e.target.value);
      }

      const today = new Date();
      let selectedDateIsToday = selectedDate.getDate() === today.getDate() &&
        selectedDate.getMonth() === today.getMonth() &&
        selectedDate.getFullYear() === today.getFullYear();

      let isHourInPast = parseInt($(".timepicker")[0].value.split(':')[0]) <= (new Date()).getHours();

      $(".timepicker").each(function() {
        var timeFormat = $(this).data('format');
        $(this).flatpickr({
          enableTime: true,
          noCalendar: true,
          dateFormat: timeFormat,
          time_24hr: true,
          minTime: selectedDateIsToday ? new Date() : undefined,
          defaultDate: (selectedDateIsToday && isHourInPast)
            ? `${(new Date()).getHours() + 1}:00`
            : $(".timepicker")[0].value,
        });
      });
    }

    // Logic for disabling wait_moderator based on mark_moodle_attendance
    var markMoodleAttendanceCheckbox = $('input[name="scheduled_meeting[mark_moodle_attendance]"]');
    var waitModeratorCheckbox = $('input[name="scheduled_meeting[wait_moderator]"]');

    function toggleWaitModeratorBasedOnAttendance() {
      if (markMoodleAttendanceCheckbox.length && waitModeratorCheckbox.length) {
        if (markMoodleAttendanceCheckbox.is(':checked')) {
          // If attendance is checked, wait_moderator MUST be checked and disabled.
          waitModeratorCheckbox.prop('checked', true);
          waitModeratorCheckbox.prop('disabled', true);
        } else {
          waitModeratorCheckbox.prop('disabled', false);
        }
      }
    }

    // Set initial state on page load
    toggleWaitModeratorBasedOnAttendance();

    // Add event listener for changes
    if (markMoodleAttendanceCheckbox.length) {
      markMoodleAttendanceCheckbox.on('change', toggleWaitModeratorBasedOnAttendance);
    }
  }
})
