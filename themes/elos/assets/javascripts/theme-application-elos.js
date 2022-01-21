//= require flatpickr/dist/flatpickr
//= require clipboard

$(document).on('turbolinks:load', function(){
  $('.toast').toast();
  $(".toast.toast-auto").each(function() {
    $(this).toast('show');
  });

  $('[data-toggle="tooltip"]').tooltip();

  $(".datepicker").each(function() {
    var format = $(this).data('format');
    $(this).flatpickr({
      disableMobile: true,
      enableTime: false,
      dateFormat: format,
      minDate: new Date(),
    });
  });

  if (window.location.href.includes('/scheduled_meetings')) {
    var datePicker = document.getElementsByName("scheduled_meeting[date]")[0];
    datePicker.addEventListener('change', checkTime);

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

  $(".timepicker").each(function() {
    var format = $(this).data('format');
    $(this).flatpickr({
      enableTime: true,
      noCalendar: true,
      dateFormat: format,
      time_24hr: true,
      minTime: new Date(),
    });
  });

  $(".timepicker-duration").each(function() {
    var format = $(this).data('format');
    $(this).flatpickr({
      enableTime: true,
      noCalendar: true,
      dateFormat: format,
      time_24hr: true,
      minuteIncrement: 1,
      minTime: "00:10",
    });
  });

  clipboard = new ClipboardJS('.copy-to-clipboard');
  clipboard.on('success', function(e) {
    toast_id = $(e.trigger).data('toast-id');
    $toast = $('.toast', toast_id);
    $toast.toast('dispose');
    $toast.toast('show');
  });

  $(".btn-retry").on('click', function() {
    window.open($(this).data('launch'));
    $(this).addClass('disabled');
    $(this).attr('disabled', '1');
    $(this).removeData('launch');
    return true;
  });
});
