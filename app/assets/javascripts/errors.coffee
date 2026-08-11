# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

$(document).on 'click', '#toggle-error-logs', ->
  $('#error-debug-info').toggleClass('d-none')
  expanded = $(this).attr('aria-expanded') == 'true'
  $(this).attr('aria-expanded', !expanded)

$(document).on 'click', '#copy-error-logs', ->
  text = $('#error-debug-info').text()
  navigator.clipboard.writeText(text)
