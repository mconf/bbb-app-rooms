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
let loadedMeetingId = null;

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
function openAuthWindow(url, service) {
  authWindow = window.open(url, service, 'width=800,height=600');
}

window.addEventListener('message', function(event) {
  // Verify the origin of the message
  if (event.source === authWindow) {
    authWindow.close()
    const room_path = $("#room_path")[0].value
    $.ajax({
      url: room_path + '/recording/' + event.data['record_id'] + '/' + event.data['service_name'],
      type: "POST",
      data: { access_token: event.data['access_token'], refresh_token: event.data['refresh_token'], expires_at: event.data['expires_at']  }
    });
  }
});
/* Request the meeting artifacts to Data API.
*/
let doAjaxDownloadArtifacts = async (download_artifacts_endpoint) => {
  return $.ajax({
    url: download_artifacts_endpoint,
    type: "GET",
    timeout: ajaxTimeout
  });
}

/* Fetch the files from Data API and process the response
 *
 * In case of success, it will display the received partial.
 * In case of timeout, the timeout value will increase in 1 second.
*/
let downloadArtifacts = async(meeting_id, download_artifacts_endpoint) => {
  if (loadedMeetingId != meeting_id) {
    try {
      let response = await doAjaxDownloadArtifacts(download_artifacts_endpoint);
      response = $(response);
  
      loadedMeetingId = meeting_id;
      let buttons = response.filter('a')
      showDropdownItems(buttons, meeting_id);
    } catch(err) {
      if (err.statusText == 'timeout') {
        ajaxTimeout += 1000;
      } else {
        console.error(`Unexpected error: ${err}`);
      }
    }
  }
};

let showMeetings = (rows) => {
  for(let row of rows) {
    $meetingsTable.append(row)
  }

  $('.eduplay-login').on('click', function(e) {
    e.preventDefault()
    openAuthWindow($(this).data('url'), 'Eduplay');
  });

  $('.filesender-login').on('click', function(e) {
    e.preventDefault()
    openAuthWindow($(this).data('url'), 'Filesender');
  });

  $('.dropdown-opts-link').on('click', function(e) {
    downloadArtifacts(this.getAttribute('internal-meeting-id'), this.getAttribute('download-artifacts-endpoint'));
  });
};

let showDropdownItems = (buttons, meeting_id) => {
  // Hide the loading items animation
  $(`div[aria-labelledby="dropdown-opts-${meeting_id}"] .dropdown-item-loading`).hide();
  // Remove only the items appended previously
  $(`div[aria-labelledby="dropdown-opts-${meeting_id}"] .appended-item`).remove();

  for (let button of buttons) {
    if(!$(button).find('button:disabled').length > 0)
      $(button).addClass('create-session-token');

    $(button).addClass('appended-item rec-edit');

    // Safari blocks all links opened in new tabs (popups), so we need to open them in the same tab
    if (!!$("body").data('browser-is-safari')) {
      $(button).removeClass('create-session-token');
      $(button).attr("target", "_self");
    }

    $(`div[aria-labelledby="dropdown-opts-${meeting_id}"]`).append(button);
    $(button).removeClass('create-session-token');
  }
};

let appendScripts = (scripts) => {
  for(let script of scripts) {
    $('body').append(script)
  }
};
