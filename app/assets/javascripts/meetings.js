let currentMeetingsCount = 0;

// URL to fetch meetings
let fetchMeetingsEndpoint;

let maxFetchMeetings;

// Jquery Elements
let $statusElem;
let $loaderElem;
let $allLoadedElem;
let $tableFootnote;
let $toTopButton;
const $WINDOW = $(window);
const $DOCUMENT = $(document);

// Control variables
let isFetching = false;
let hasMoreToFetch = true;
let rendered = false;

// Max time to wait for ajax response
let ajaxTimeout = 15000;

/* This is invoked only in 1 situations:
 * 1. When clicking on the link 'Meetings' in the Room view
*/
$DOCUMENT.on('turbolinks:render', () => {
  const CONTROLLER = $("body").data('controller');
  const ACTION = $("body").data('action');
  if (CONTROLLER != 'rooms' || ACTION != 'meetings') return;

  // Avoid triggering turbolinks:render twice
  if (rendered) return;
  rendered = true;

  initElements();
  resetElements();
});


/* This is invoked in 2 situations:
 * 1. Same as turbolinks:render
 * 2. When loading the page (via URL, F5, etc.)
*/
$DOCUMENT.on('turbolinks:load',  () => {
  const CONTROLLER = $("body").data('controller');
  const ACTION = $("body").data('action');
  if (CONTROLLER != 'rooms' || ACTION != 'meetings') return;

  // Allow turbolinks:render to be called again
  rendered = false;

  initElements();

  currentMeetingsCount = 0;
  fetchMeetingsEndpoint = $statusElem.attr('data-fetch-meetings-endpoint');
  maxFetchMeetings = $statusElem.attr('data-per-page');

  // Max time to wait for ajax response
  if ($statusElem.data('ajax-timeout')) {
    ajaxTimeout = parseInt($statusElem.data('ajax-timeout'));
  }

  $($loadButton).on('click', tryToFetchMeetings);
  $($toTopButton).on('click', handleToTopClick);
  $WINDOW.on('scroll', handleScroll);
  handleScroll();
  tryToFetchMeetings();
});

let initElements = () => {
  $statusElem = $('#status');
  $loaderElem = $('#status .loader-wrapper .loader');
  $allLoadedElem = $('#status .loader-wrapper .all-loaded');
  $loadButton = $('#status .loader-wrapper .load-meetings');
  $emptyElem = $('#status .loader-wrapper .empty')
  $tableFootnote = $('.table-footnote');
  $meetingsTable = $('#meetings-table tbody');
  $toTopButton = $('.to-top');

  isFetching = false;
  hasMoreToFetch = true;
};

let handleToTopClick = () => {
  $('html, body').animate({scrollTop:0}, '3000');
};

let handleScroll = () => {
  if ($WINDOW.scrollTop() > 500) {
    $toTopButton.show();
  } else {
    $toTopButton.hide();
  }
}

let tryToFetchMeetings = () => {
  if (!isFetching && hasMoreToFetch) {
    fetchMeetings();
  }
};

/* Fetch the meetings and process the response
 *
 * In case of success, it will display the received partial.
 * If there is an element with 'data-all-loaded' set, them we will show
 * the 'all-loaded' label instead of the loading button.
 *
 * In case of timeout, the load button will be display and the timeout
 * value will increase in 1 second.
 *
 *
*/
async function fetchMeetings() {
  isFetching = true;
  try {
    setLoadingState();
    let response = await doAjax();
    response = $(response)

    let rows = response.filter('.meeting-row')
    currentMeetingsCount += rows.length;

    /* For every .meeting-row in the response all the scripts for the previous meetings
       are sent, so it should filter only the last n(number of rows per page) scripts. */
    let scripts = response.filter('script').slice(-$statusElem.attr('data-per-page'))

    /* The element with data-all-loaded is added when the API returns
       nextpage=false. We use this information to hide the load button
       and show the 'all loaded' label. */
    hasMoreToFetch = response.filter('[data-all-loaded]').length == 0;

    if (currentMeetingsCount == 0) {
      setEmptyState();
    } else {
      if (hasMoreToFetch) {
        setLoadedState();
      } else {
        setDoneState();
      }
      showMeetings(rows);
      appendScripts(scripts)
    }
  } catch(err) {
    hasMoreToFetch = true;
    if (err.statusText == 'timeout') {
      ajaxTimeout += 1000;
    } else {
      console.error(`Unexpected error: ${err}`);
    }
    setLoadedState();
  }
  isFetching = false;
}

/* Request the meetings partial to the server.
 * @offset is the 'index' of the meeting.
 * @limit is the max number of meetings we want.
*/
let doAjax = async () => {
  return $.ajax({
    url: fetchMeetingsEndpoint,
    data: {
      "offset": currentMeetingsCount,
      "limit": maxFetchMeetings
    },
    type: "GET",
    timeout: ajaxTimeout
  });
};

/* Initial state
 * Show the loader animation
*/
let setLoadingState = () => {
  hideAll();

  $loaderElem.show();
  if (currentMeetingsCount > 0) {
    $tableFootnote.show();
  }
};

/* Final state (1)
 * This state is reached when there is 0 meetings for the room
*/
let setEmptyState = () => {
  hideAll();

  $emptyElem.show();
};

/* Intermediate state
 * This state is reached when meetings are received
 * and there is more meetings to be loaded from the server.
*/
let setLoadedState = () => {
  hideAll();

  $loadButton.show();
  $tableFootnote.show();
};

/* Final state (2)
 * This state is reached when meetings are received
 * and the server has all loaded meetings to provide.
*/
let setDoneState = () => {
  hideAll();

  $allLoadedElem.show();
  $tableFootnote.show();
};

let resetElements = () => {
  hideAll();

  $meetingsTable.empty();
};

let hideAll = () => {
  $emptyElem.hide();
  $loadButton.hide();
  $loaderElem.hide();
  $allLoadedElem.hide();
  $tableFootnote.hide();
};

var authWindow;
// Origin the callback page is served from, read from the redirect_uri of the
// authorization URL instead of being assumed to be ours, since the callback can
// be configured on a different host than the one serving this page.
var authWindowOrigin;
function openAuthWindow(url, service) {
  authWindow = window.open(url, service, 'width=800,height=600');
  const redirectUri = new URL(url, window.location.href).searchParams.get('redirect_uri');
  authWindowOrigin = redirectUri ? new URL(redirectUri, window.location.href).origin : window.location.origin;
}

/* Check whether a message is the one posted by our own OAuth callback page.
 *
 * The login pages loaded inside the popup also post messages to the opener, and
 * they share the same event.source as our callback, so checking the source
 * alone would close the popup in the middle of the login flow.
*/
let isAuthCallbackMessage = (event) => {
  if (event.source !== authWindow) return false;
  if (event.data === null || typeof event.data !== 'object') return false;
  if (event.data.source !== 'bbb-app-rooms') return false;

  if (event.origin !== authWindowOrigin) {
    console.warn(`Ignored a callback message from ${event.origin}, expected ${authWindowOrigin}`);
    return false;
  }

  return true;
};

window.addEventListener('message', function(event) {
  if (!isAuthCallbackMessage(event)) return;

  authWindow.close()
  const room_path = $("#room_path")[0].value
  $.ajax({
    url: room_path + '/recording/' + event.data['record_id'] + '/' + event.data['service_name'],
    type: "POST",
    data: { access_token: event.data['access_token'], refresh_token: event.data['refresh_token'], expires_at: event.data['expires_at']  }
  });
});
/* Request the documents of a meeting to the server.
*/
let doAjaxDownloadDocuments = async (download_documents_endpoint) => {
  return $.ajax({
    url: download_documents_endpoint,
    type: "GET",
    timeout: ajaxTimeout
  });
}

let showMeetings = (rows) => {
  for(let row of rows) {
    $meetingsTable.append(row)
  }
};

// The request in flight for each dropdown, so a response is only rendered while
// it is still the latest one asked for
let documentsLatestRequest = {};

/* showLoading is false when the contents on screen are still the right ones and only
   need to be brought up to date, so the placeholder does not flash over them */
let downloadDocuments = async(meeting_id, download_documents_endpoint, showLoading = true) => {
  if (!download_documents_endpoint) return;

  if (showLoading) showDocumentsLoading(meeting_id);

  /* Opening and closing the dropdown quickly leaves more than one request in
     flight, and they can come back out of order */
  const request = doAjaxDownloadDocuments(download_documents_endpoint);
  documentsLatestRequest[meeting_id] = request;

  try {
    let response = await request;
    if (documentsLatestRequest[meeting_id] !== request) return;

    showDocumentItems(response, meeting_id);
  } catch(err) {
    if (err.statusText == 'timeout') {
      ajaxTimeout += 1000;
    } else {
      console.error(`Unexpected error: ${err}`);
    }
  }
};

const DOCUMENTS_AUTO_CLOSE_DELAY = 2 * 60 * 1000;

// One timer per dropdown, since each meeting has its own
let documentsAutoCloseTimers = {};

let clearDocumentsAutoClose = (toggle) => {
  const meeting_id = toggle.getAttribute('internal-meeting-id');
  if (!documentsAutoCloseTimers[meeting_id]) return;

  clearTimeout(documentsAutoCloseTimers[meeting_id]);
  delete documentsAutoCloseTimers[meeting_id];
};

let scheduleDocumentsAutoClose = (toggle) => {
  // Drop the previous timer, otherwise it would close a dropdown the user just reopened
  clearDocumentsAutoClose(toggle);

  const meeting_id = toggle.getAttribute('internal-meeting-id');
  documentsAutoCloseTimers[meeting_id] = setTimeout(() => {
    delete documentsAutoCloseTimers[meeting_id];
    bootstrap.Dropdown.getOrCreateInstance(toggle).hide();
  }, DOCUMENTS_AUTO_CLOSE_DELAY);
};

let documentsContainerSelector = (meeting_id) => {
  return `div[aria-labelledby="dropdown-documents-${meeting_id}"]`;
};

/* Every open refetches, so the contents rendered on the previous open are dropped
   and the placeholder comes back while the new request is in flight. Otherwise the
   old contents would stay on screen as if they were the current ones. */
let showDocumentsLoading = (meeting_id) => {
  const containerSelector = documentsContainerSelector(meeting_id);
  $(`${containerSelector} .appended-item`).remove();
  $(`${containerSelector} .dropdown-item-loading`).show();
};

let showDocumentItems = (html, meeting_id) => {
  const containerSelector = documentsContainerSelector(meeting_id);
  $(`${containerSelector} .dropdown-item-loading`).hide();
  $(`${containerSelector} .appended-item`).remove();
  $(containerSelector).append($(html).addClass('appended-item'));
  document.querySelectorAll(`${containerSelector} [data-bs-toggle="tooltip"]`).forEach(el => {
    new bootstrap.Tooltip(el);
  });
};

$DOCUMENT.on('click', '.eduplay-login', function(e) {
  e.preventDefault();
  openAuthWindow($(this).data('url'), 'Eduplay');
});

$DOCUMENT.on('click', '.filesender-login', function(e) {
  e.preventDefault();
  openAuthWindow($(this).data('url'), 'Filesender');
});

/* Fetching on 'shown' (instead of 'click') refreshes the dropdown contents on every
   open, which is how the user sees documents that became ready meanwhile */
$DOCUMENT.on('shown.bs.dropdown', '.dropdown-documents-link', function(e) {
  downloadDocuments(this.getAttribute('internal-meeting-id'), this.getAttribute('download-documents-endpoint'));
  scheduleDocumentsAutoClose(this);
});

$DOCUMENT.on('hidden.bs.dropdown', '.dropdown-documents-link', function(e) {
  clearDocumentsAutoClose(this);
});

$(document).on('click', '.request-ai-artifacts-btn', function(e) {
  e.stopPropagation();
  const $btn = $(this);
  const endpoint = $btn.data('request-endpoint');
  const requestedTypes = $btn.data('requestedTypes');
  const textOriginal = $btn.text().trim();

  $btn.prop('disabled', true).text($btn.data('text-requesting'));

  $.ajax({
    url: endpoint,
    method: 'POST',
    data: { requested_artifact_types: requestedTypes },
    headers: { 'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content') },
    success: function() {
      /* The request left the documents pending in the cache, and rendering that state is
         the server's job: a row waiting for its file drops the 'unavailable' icon, gets
         its spinner and takes the AI mark back. Patching all of that here would be a
         second, drifting copy of those rules, so the contents are fetched again instead */
      const toggle = $btn.closest('.dropdown').find('.dropdown-documents-link')[0];
      if (toggle) {
        downloadDocuments(toggle.getAttribute('internal-meeting-id'),
          toggle.getAttribute('download-documents-endpoint'), false);
      }
      const $successToast = $('#ai-artifacts-success-toast .toast');
      $successToast.toast('dispose');
      $successToast.toast('show');
    },
    error: function(err) {
      const $toastWrapper = $('#ai-artifacts-error-toast');
      const message = err.responseJSON?.message || $toastWrapper.data('default-message');
      $toastWrapper.find('.ai-artifacts-error-message').text(message);
      const $toast = $toastWrapper.find('.toast');
      $toast.toast('dispose');
      $toast.toast('show');
      $btn.prop('disabled', false).text(textOriginal);
    }
  });
});

let appendScripts = (scripts) => {
  for(let script of scripts) {
    $('body').append(script)
  }
};
