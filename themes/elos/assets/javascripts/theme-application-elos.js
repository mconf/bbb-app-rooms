//= require flatpickr/dist/flatpickr
//= require clipboard

$(document).on('turbolinks:load', function(){
  $('.toast').toast();
  $(".toast.toast-auto").each(function() {
    $(this).toast('show');
  });

  $('[data-toggle="tooltip"]').tooltip();

  $("#group_id").on('change', function() {
    $("#set-group-form").trigger('submit')
  });

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

  $(".btn-retry").on('click', function(event) {
    event.preventDefault();
    window.open($(this).data('launch'));
    $(this).addClass('disabled');
    $(this).attr('disabled', '1');
    $(this).removeData('launch');
    return true;
  });

  // Links that open in a new tab need a session token to access the
  // user session in an external context, where the Rails cookie cannot be used.
  // Makes an AJAX request to obtain a session token, and then opens a new window
  // with the URL that includes the session token as a query parameter.
  // Delegates the event listener to body and check if the click target has the expected class,
  // to listen even for dinamically created elements
  $('body').on('click', '.create-session-token', function(e) {
    e.preventDefault();

    const elem = $(this);
    let url;
    try {
      if (elem.is('a')) {
        url = new URL(elem.attr('href'), window.location.origin);
      } else if (elem.is('form')) {
        url = new URL(elem.attr('action'), window.location.origin);
      }
    } catch (error) {
      console.error('Invalid URL:', error);
      return;
    }
    const sessionTokenUrl = $('body').data('session-token-url');
    // e.g. ['', 'rooms', '883a883477bd260c46d7d87a1553204f1d7a620c']
    const roomId = window.location.pathname.split('/')[2];
    if (!sessionTokenUrl || !roomId) {
      console.error('Missing required data attributes for create-session-token AJAX call.');
      return;
    }

    const params = { room_id: roomId };
    $.getJSON(sessionTokenUrl, params)
      .done(function(data) {
        url.searchParams.set('session_token', data.token);
        window.open(url);
      })
      .fail(function(jqXHR) {
        $toast = $('.toast', '#session-token-req-failed-toast');
        $toast.toast('dispose');
        $toast.toast('show');
        console.warn('Request to create session_token failed:', jqXHR.responseText);
      });
  });

  // When the #meetings-filters radio input changes, adds or removes a class to
  // #meetings-table, which will hide or show meetings depending on the filter.
  // Also adds the filter to the current URL, so it can be kept between page reloads.
  $("#meetings-filters input").on('change', function() {
    filter = $('input[name=filters]:checked', '#meetings-filters').val();
    switch (filter) {
      case 'recorded-only':
        $('#meetings-filters input[value=recorded-only]').closest('label').addClass('active');
        $('#meetings-filters input[value=no-filters]').closest('label').removeClass('active');
        $('#meetings-table').addClass('filter-recorded-only');
        window.history.replaceState({filter: "recorded-only"}, null, '?filter=recorded-only');
        break;
      default:
        $('#meetings-filters input[value=no-filters]').closest('label').addClass('active');
        $('#meetings-filters input[value=recorded-only]').closest('label').removeClass('active');
        $('#meetings-table').removeClass('filter-recorded-only');
        window.history.replaceState(null, null, 'meetings');
    };
    return true;
  });

  // On page load, if the URL contains a 'recorded-only' filter, checks the radio input
  // and hides non-recorded meetings.
  if ((new URL(window.location.href)).searchParams.get("filter") == 'recorded-only' ) {
    $("#meetings-filters input[value=recorded-only]").attr("checked", true);
    $('#meetings-filters input[value=recorded-only]').closest('label').addClass('active');
    $("#meetings-filters input[value=no-filters]").attr("checked", false);
    $('#meetings-filters input[value=no-filters]').closest('label').removeClass('active');
    $('#meetings-table').addClass('filter-recorded-only');
    window.history.replaceState({filter: "recorded-only"}, null, '?filter=recorded-only');
  }

  // Adds the 'recorded-only' filter to recording edit links after click, to keep it
  // after reload.
  $("#meetings-table").on('click', function(e) {
    if (e.target.classList.contains('rec-edit')) {
      if (window.history.state.filter == 'recorded-only')
        e.target.href += '?filter=recorded-only';
    }
  });
});
