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

  $(".timepicker").each(function() {
    var format = $(this).data('format');
    $(this).flatpickr({
      enableTime: true,
      noCalendar: true,
      dateFormat: format,
      time_24hr: true,
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

  $("#meetings-filters input").on('change', function() {
    filter = $('input[name=filters]:checked', '#meetings-filters').val();
    switch (filter) {
      case 'recorded-only':
        $('#recording-table').addClass('filter-recorded-only');
        if(window.history.state.filter != null)
          window.history.replaceState({filter: "recorded-only"}, 'filter', '?filter=recorded-only')
        else
          window.history.pushState({filter: "recorded-only"}, 'filter', '?filter=recorded-only')
        break;
      default:
        $('#recording-table').removeClass('filter-recorded-only');
        window.history.replaceState({filter: "no-filters"}, 'filter', '?filter=no-filters')
    };
    return true;
  });

  if ((new URL(window.location.href)).searchParams.get("filter") == 'recorded-only' ) {
    $("#meetings-filters input[value=recorded-only]").attr("checked", true);
    $("#meetings-filters input[value=no-filters]").attr("checked", false);
    $('#recording-table').addClass('filter-recorded-only');
    if(window.history.state.filter != null)
      window.history.replaceState({filter: "recorded-only"}, 'filter', '?filter=recorded-only')
    else
      window.history.pushState({filter: "recorded-only"}, 'filter', '?filter=recorded-only')
  }

  $("#recording-table").on('click', function(e) {
    if (e.target.classList.contains('rec-edit')) {
      if (window.history.state.filter != null && window.history.state.filter == 'recorded-only')
        e.target.href += '?filter=recorded-only';
    }
  });
});
