$(document).on('turbolinks:load', function(){
  if(window.location.href.includes('/scheduled_meetings')){
    var valueSelect = document.getElementsByName("scheduled_meeting[duration]")[0],
      contentCustomDuration = document.getElementById("content_custom_duration")

    valueSelect.addEventListener('change', controlCustomDuration)
    function controlCustomDuration(e) {
      let valueSelectDuration = e.target.value;
      valueSelectDuration == 0 ? contentCustomDuration.classList.add('d-block') :
        contentCustomDuration.classList.remove('d-block')
    }

    if(window.location.href.includes('/new')) {
      let recurrenceSelect = document.getElementsByName("scheduled_meeting[repeat]")[0]
      recurrenceSelect.addEventListener('change', toggleCalendar)

      function toggleCalendar(e) {
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
  }
})
