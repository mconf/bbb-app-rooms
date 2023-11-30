//= require flatpickr/dist/flatpickr
//= require clipboard
//= require select2

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

  $(".copy-to-clipboard").each(function() {
    $toast = $('.toast', $(this).data('toast-id'));
    clipboard = new ClipboardJS(this);
    clipboard.on('success', function(e) {
      $toast.toast('dispose');
      $toast.toast('show');
    });
  });

  $(".btn-retry").on('click', function() {
    window.open($(this).data('launch'));
    $(this).addClass('disabled');
    $(this).attr('disabled', '1');
    $(this).removeData('launch');
    return true;
  });

  // When the #meetings-filters radio input changes, adds or removes a class to
  // #meetings-table, which will hide or show meetings depending on the filter.
  // Also adds the filter to the current URL, so it can be kept between page reloads.
  $("#meetings-filters input").on('change', function() {
    filter = $('input[name=filters]:checked', '#meetings-filters').val();
    switch (filter) {
      case 'recorded-only':
        $('#meetings-table').addClass('filter-recorded-only');
        window.history.replaceState({filter: "recorded-only"}, null, '?filter=recorded-only');
        break;
      default:
        $('#meetings-table').removeClass('filter-recorded-only');
        window.history.replaceState(null, null, 'meetings');
    };
    return true;
  });

  // On page load, if the URL contains a 'recorded-only' filter, checks the radio input
  // and hides non-recorded meetings.
  if ((new URL(window.location.href)).searchParams.get("filter") == 'recorded-only' ) {
    $("#meetings-filters input[value=recorded-only]").attr("checked", true);
    $("#meetings-filters input[value=no-filters]").attr("checked", false);
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

  // Returns whether an email is valid or not.
  // From: http://www.w3resource.com/javascript/form/email-validation.php
  const validateEmail = (email) => {
    return email.match(
      /^(([^<>()\[\]\\.,;:\s@"]+(\.[^<>()\[\]\\.,;:\s@"]+)*)|(".+"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/
    );
  };

  // Select2 
  $("#filesender-emails").select2({
    theme: "bootstrap",
    minimumInputLength: 1,
    width: '100%',
    tags: true,
    tokenSeparators: [",", ";", " "],
    createSearchChoice: function(term, data) { if (validateEmail(term.trim())) { return { id: term, text: term }; } }
  });

});
