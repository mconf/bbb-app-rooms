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

    if($('input[name="scheduled_meeting[create_moodle_calendar_event]"]')) {
      let recurrenceSelect = document.getElementsByName("scheduled_meeting[repeat]")[0]
      recurrenceSelect?.addEventListener('change', toggleMoodleCalendarCheckbox)

      function toggleMoodleCalendarCheckbox(e) {
        let valueSelectDuration = e.target.value;
        if (!!valueSelectDuration) {
          $('input[name="scheduled_meeting[create_moodle_calendar_event]"]').each(function () {
            $(this).prop('checked', false);
            $(this).prop('disabled', true);
          });
        } else {
          $('input[name="scheduled_meeting[create_moodle_calendar_event]"]').each(function () {
            $(this).prop('checked', true);
            $(this).prop('disabled', false);
          });
        }
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
  }
})
