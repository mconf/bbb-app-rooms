# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

$(document).on 'click', '#toggle-error-logs', ->
  $('#error-debug-info').toggleClass('d-none')
  expanded = $(this).attr('aria-expanded') == 'true'
  $(this).attr('aria-expanded', !expanded)

# has to wait for turbolinks:load so ClipboardJS is defined by the time this runs.
$(document).on 'turbolinks:load', ->
  return unless $('#copy-error-logs').length

  clipboard = new ClipboardJS '#copy-error-logs',
    text: -> $('#error-debug-info').text()

  clipboard.on 'success', (e) ->
    e.clearSelection()

    $toast = $('.toast', '#error-logs-copied-toast')
    $toast.toast('dispose')
    $toast.toast('show')
