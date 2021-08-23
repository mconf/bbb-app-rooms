let currentRecordingsCount = 0;

// URL to fetch recordings
let fetchRecordingsEndpoint;

let maxFetchRecordings;

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
let ajaxTimeout = 5000;

/* This is invoked only in 1 situations:
 * 1. When clicking on the link 'Recordings' in the Room view
*/
$DOCUMENT.on('turbolinks:render', () => {
  const CONTROLLER = $("body").data('controller');
  const ACTION = $("body").data('action');
  if (CONTROLLER != 'rooms' || ACTION != 'recordings') return;

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
  if (CONTROLLER != 'rooms' || ACTION != 'recordings') return;

  // Allow turbolinks:render to be called again
  rendered = false;

  initElements();

  currentRecordingsCount = 0;
  fetchRecordingsEndpoint = $statusElem.attr('data-fetch-recordings-endpoint');
  maxFetchRecordings = $statusElem.attr('data-per-page');

  $($loadButton).on('click', tryToFetchRecordings);
  $($toTopButton).on('click', handleToTopClick);
  $WINDOW.on('scroll', handleScroll);
  handleScroll();
  tryToFetchRecordings();
});

let initElements = () => {
  $statusElem = $('#status');
  $loaderElem = $('#status .loader-wrapper .loader');
  $allLoadedElem = $('#status .loader-wrapper .all-loaded');
  $loadButton = $('#status .loader-wrapper .load-recordings');
  $emptyElem = $('#status .loader-wrapper .empty')
  $tableFootnote = $('.table-footnote');
  $recordingsTable = $('#recording-table tbody');
  $toTopButton = $('.to-top');

  isFetching = false;
  hasMoreToFetch = true;
};

let handleToTopClick = () => {
  $DOCUMENT.scrollTop(0);
};

let handleScroll = () => {
  if ($WINDOW.scrollTop() > 500) {
    $toTopButton.show();
  } else {
    $toTopButton.hide();
  }
}

let tryToFetchRecordings = () => {
  if (!isFetching && hasMoreToFetch) {
    fetchRecordings();
  }
};

/* Fetch the recordings and process the response
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
async function fetchRecordings() {
  isFetching = true;
  try {
    setLoadingState();
    let response = await doAjax();
    response = $(response)

    let rows = response.filter('.recording-row')
    currentRecordingsCount += rows.length;

    /* The element with data-all-loaded is added when the API returns
       nextpage=false. We use this information to hide the load button
       and show the 'all loaded' label. */
    hasMoreToFetch = response.filter('[data-all-loaded]').length == 0;

    if (currentRecordingsCount == 0) {
      setEmptyState();
    } else {
      if (hasMoreToFetch) {
        setLoadedState();
      } else {
        setDoneState();
      }
      showRecordings(rows);
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

/* Request the recordings partial to the server.
 * @offset is the 'index' of the recording.
 * @limit is the max number of recordings we want.
*/
let doAjax = async () => {
  return $.ajax({
    url: fetchRecordingsEndpoint,
    data: {
      "offset": currentRecordingsCount,
      "limit": maxFetchRecordings
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
  if (currentRecordingsCount > 0) {
    $tableFootnote.show();
  }
};

/* Final state (1)
 * This state is reached when there is 0 recordings for the room
*/
let setEmptyState = () => {
  hideAll();

  $emptyElem.show();
};

/* Intermediate state
 * This state is reached when recordings are received
 * and there is more recordings to be loaded from the server.
*/
let setLoadedState = () => {
  hideAll();

  $loadButton.show();
  $tableFootnote.show();
};

/* Final state (2)
 * This state is reached when recordings are received
 * and the server has all loaded recordings to provide.
*/
let setDoneState = () => {
  hideAll();

  $allLoadedElem.show();
  $tableFootnote.show();
};

let resetElements = () => {
  hideAll();

  $recordingsTable.empty();
};

let hideAll = () => {
  $emptyElem.hide();
  $loadButton.hide();
  $loaderElem.hide();
  $allLoadedElem.hide();
  $tableFootnote.hide();
};

let showRecordings = (rows) => {
  for(let row of rows) {
    $recordingsTable.append(row)
  }
};