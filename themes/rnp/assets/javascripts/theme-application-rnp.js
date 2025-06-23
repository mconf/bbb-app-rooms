//= require flatpickr/dist/flatpickr
//= require clipboard
//= require select2

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

  $(".room-launch-new-tab").on('click', function(event) {
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
    createSearchChoice: function(term, data) { if (validateEmail(term.trim())) { return { id: term, text: term }; } },
    formatSearching: function() { return I18n.t('_all.select2.space_or_comma'); },
    formatInputTooShort: function () { return I18n.t('_all.select2.hint') },
    formatNoMatches: function () { return I18n.t('_all.select2.no_results') }
  });

  $("#meeting-recurrence-select").on('change', function(e) {
    value = e.target.value;
    prefix = $("#meeting-recurrence-select").attr('data-prefix');
    trackingId = `lti-${prefix}-meeting-recurrence-${value ? value : 'does_not_repeat'}`;
    e.target.setAttribute("data-tracking-id", trackingId);
  });

  // Change selected thumbnail
  $('#eduplay .thumbnail-default-option').on('click', function(e) {
    e.stopPropagation();
    $('.thumbnail-default-option').addClass('selected');
    $('.thumbnail-upload-option').removeClass('selected');
    $('input[name="thumbnail_option"][value="default"]').prop('checked', true);
  });
  
  $('#eduplay .thumbnail-upload-option').on('click', function(e) {
    let fileInput = $('input[type="file"][name="image"]');
    if (fileInput.val()) {
      e.stopPropagation();
      $('.thumbnail-upload-option').addClass('selected');
      $('.thumbnail-default-option').removeClass('selected');
      $('input[name="thumbnail_option"][value="upload"]').prop('checked', true);
    } else {
      fileInput.trigger("click");
    }
  });

  // Show preview of image and logic to limit size in 4MB
  $('#eduplay input[type="file"][name="image"]').on('change', function(e) {
    let input = e.target;
    if (input.files && input.files[0]) {
      let file = input.files[0];
      if (!file.type.startsWith("image/") || file.size > 4 * 1024 * 1024) {
        $('#preview').hide();
        $('#remove-thumbnail').hide();
        $('.upload-placeholder').show();
        $(input).val('');


        error_message = !file.type.startsWith("image/")
          ? I18n.t('meetings.recording.eduplay.errors.image_not_image')
          : I18n.t('meetings.recording.eduplay.errors.image_too_large');
        $toast = $('.toast', '#eduplay-upload-form-error');
        $toast.find('.toast-header').contents().first()[0].textContent = error_message;
        $toast.toast('dispose');
        $toast.toast('show');
        return;
      }
      let reader = new FileReader();
      reader.onload = function(ev) {
        $('#preview').attr('src', ev.target.result).show();
        $('.upload-placeholder').hide();
        $('#remove-thumbnail').show();
        // Select upload option
        $('.thumbnail-upload-option').addClass('selected');
        $('.thumbnail-default-option').removeClass('selected');
        $('input[name="thumbnail_option"][value="upload"]').prop('checked', true);
      };
      reader.readAsDataURL(file);
    } else {
      $('#preview').hide();
      $('#remove-thumbnail').hide();
      $('.upload-placeholder').show();
    }
  });

  // Remove uploaded image
  $('#eduplay #remove-thumbnail').on('click', function(e) {
    e.stopPropagation();
    $('#preview').hide();
    $('#remove-thumbnail').hide();
    $('.upload-placeholder').show();
    $('input[type="file"][name="image"]').val('');
    // Select default option
    $('.thumbnail-default-option').addClass('selected');
    $('.thumbnail-upload-option').removeClass('selected');
    $('input[name="thumbnail_option"][value="default"]').prop('checked', true);
  });

  $('#eduplay .dropdown-menu .dropdown-item').each(function() {
    $(this).on('click', function(e) {
      e.preventDefault();
      if (!$(this).hasClass('active')) {
        $(this).closest('.dropdown-menu').find('.dropdown-item.active').removeClass('active');
        $(this).addClass('active');

        toggle = $(this).closest('.dropdown').find('.selected-option');
        toggle.empty().append($(this).contents().clone());

        channelVal = $(this).attr('data-attr-value');
        $('input[name="channel"]').val(channelVal);
        if (channelVal == 'new_channel')
          $('.new-channel-form').show()
        else
          $('.new-channel-form').hide()
      }
    })
  });

  $('#eduplay input[name="public"]').on('change', function() {
    var privateWithPassword = $('.password-input').data('private-with-password');
    console.log($(this).val())
    if ($(this).val() == privateWithPassword.toString()) {
      $('.password-input').show();
    } else {
      $('.password-input').hide();
    }
  });

  const validateForm = (formData) => {
    errors = []

    channelId = formData['channel']
    channelName = formData['channel_name']
    channelPublic = formData['channel_public']
    channelTags = formData['channel_tags']

    if (channelId == 'new_channel'){
      if ([channelName, channelPublic, channelTags].some(function(field){return field == null || field == ''})) {
        errors.push(I18n.t('meetings.recording.eduplay.errors.channel_incomplete'));
      } else if (channelName == channelTags) {
        errors.push(I18n.t('meetings.recording.eduplay.errors.channel_same_field'));
      }
    } else if (channelId == '') {
        errors.push(I18n.t('meetings.recording.eduplay.errors.no_channel'));
    }

    videoTitle = formData['title'];
    videoDescription = formData['description'];
    videoPublic = formData['public'];
    if ([videoTitle, videoDescription, videoPublic].some(function(field) { return field == null || field == '';})){
      errors.push(I18n.t('meetings.recording.eduplay.errors.video_incomplete'))
    } else if (videoTitle ==  videoDescription) {
      errors.push(I18n.t('meetings.recording.eduplay.errors.video_same_field'));
    }

    if (videoPublic == $('.password-input').data('private-with-password').toString()) {
      let password = formData['video_password'];
      if (!isPasswordValid(password)) {
        errors.push(I18n.t('meetings.recording.eduplay.errors.password_invalid_requirments'));
      }
    }

    if (errors.length > 0)
      return errors.join(' ');
    return null
  };

  function isPasswordValid(password) {
    if (!password || password.length < 8) return false;

    var hasUpper   = /[A-Z]/.test(password);
    var hasLower   = /[a-z]/.test(password);
    var hasNumber  = /[0-9]/.test(password);
    var hasSpecial = /[*.!@#\$%\^&\(\)\{\}\[\]<>:;,.?\/~+\-=|\\]/.test(password);

    return hasUpper && hasLower && hasNumber && hasSpecial;
  }

  $('#eduplay form').on('submit', function(e) {
    formData = $(this).serializeArray().reduce(function(fieldsObject, field) {
      fieldsObject[field.name] = field.value;
      return fieldsObject;
    }, {});
    errorMessage = validateForm(formData);

    if (errorMessage) {
      e.preventDefault();
      button = $('#eduplay-submit');
      setTimeout(function() {
        button.prop('disabled', false);
      }, 1000);

      $('html, body').animate({ scrollTop: 0 }, 'fast');

      $toast = $('.toast', '#eduplay-upload-form-error');
      $toast.find('.toast-header').contents().first()[0].textContent = errorMessage;
      $toast.toast('dispose');
      $toast.toast('show');
    }
  })

  // Select2
  $("#eduplay-channel-tags").select2 ({
    minimumInputLength: 1,
    width: '100%',
    multiple: true,
    tags: true,
    tokenSeparators: [","],
    formatSearching: function() { return I18n.t('_all.select2.comma_tags') }
  });

  $("#eduplay-video-tags").select2 ({
    minimumInputLength: 1,
    width: '100%',
    multiple: true,
    tags: true,
    tokenSeparators: [","],
    formatSearching: function() { return I18n.t('_all.select2.comma_tags') }
  });

  $('.showable-password-wrapper').each(function() {
    const $wrapper = $(this);
    const $input = $wrapper.find('.showable-password');
    const $showIcon = $wrapper.find('.showable-password-show');
    const $hideIcon = $wrapper.find('.showable-password-hide');

    $showIcon.on('click', function() {
      $input.attr('type', 'text');
      $showIcon.hide();
      $hideIcon.show();
    });

    $hideIcon.on('click', function() {
      $input.attr('type', 'password');
      $hideIcon.hide();
      $showIcon.show();
    });
  });
});

$DOCUMENT.on('turbolinks:load',  () => {
  const CONTROLLER = $("body").data('controller');
  const ACTION = $("body").data('action');
  if (CONTROLLER != 'clients/rnp/controllers/callbacks' || (ACTION != 'eduplay_callback' && ACTION != 'filesender_callback')) return;

  const accessToken = $("#access_token")[0].value
  const refreshToken = $("#refresh_token")[0]?.value
  const expiresAt = $("#expires_at")[0].value
  const recordID = $("#recordID")[0].value
  const service_name = $("#service_name")[0].value
  window.opener.postMessage({
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_at: expiresAt,
    record_id: recordID,
    service_name: service_name
  }, '*')
});
