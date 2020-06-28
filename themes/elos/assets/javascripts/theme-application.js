//= require flatpickr/dist/flatpickr
//= require clipboard

$(document).on('turbolinks:load', function(){
  $('.toast').toast();
  $(".toast.toast-auto").each(function() {
    $(this).toast('show');
  });

  $(".datepicker").each(function() {
    var format = $(this).data('format');
    $(this).flatpickr({
      enableTime: false,
      dateFormat: format,
      minDate: new Date(),
    });
  });

  $(".timepicker").each(function() {
    var format = $(this).data('format');
    $(this).flatpickr({
      enableTime: true,
      noCalendar: true,
      dateFormat: format,
      time_24hr: true,
    });
  });

  $(".copy-to-clipboard").each(function() {
    clipboard = new ClipboardJS(this);
    clipboard.on('success', function(e) {
      $('.toast', '#external-link-copied-toast').toast('dispose');
      $('.toast', '#external-link-copied-toast').toast('show');
    });
  });
});
