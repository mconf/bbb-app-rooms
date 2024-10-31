// BigBlueButton open source conferencing system - http://www.bigbluebutton.org/.
//
// Copyright (c) 2018 BigBlueButton Inc. and by respective authors (see below).
//
// This program is free software; you can redistribute it and/or modify it under the
// terms of the GNU Lesser General Public License as published by the Free Software
// Foundation; either version 3.0 of the License, or (at your option) any later
// version.
//
// BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License along
// with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
//= require './polling'
//= require i18n/translations

$(document).on('turbolinks:load', function(){
  I18n.locale = $("body").data('locale');
  var controller = $("body").data('controller');
  var action = $("body").data('action');
  var cable = $("body").data('use-cable');

  var pollStatus = function() {
    var url = $('#wait-for-moderator').data('wait-url');
    $.ajax({
      url: url,
      dataType: "json",
      contentType: "application/json",
      error: function() { console.log('Error checking'); },
      success: function(data) {
        if (data['running'] === true) {
          if (data['can_join_or_create'] === true && isMobile()) {
            $(".offcanvas-bottom").offcanvas('show');
          } else {
            joinSession();
          }
        }
      }
    });
  };

  var pollStatusTeste = function() {
    var url = $('#external-join').data('external-url');
    var action = '/updateMeetingData'

    $.ajax({
      url: url + action,
      dataType: "json",
      contentType: "application/json",
      error: function() { console.log('Error do pullStatusTeste'); },
      success: function(data) {
        updateMeetingData(data);
      }
    });
  };

  var updateMeetingData = function(data) {
    // update participants
    var participants = $('#external-join').find('p#participants_count')[0]

    if (data.ended) {
      participants?.remove()
    } else if (data.participants_count == 1 ) {
      participants.innerText = I18n.t('default.scheduled_meeting.distance_in_words.x_participants.one')
    } else if (data.participants_count !== 1) {
      participants.innerText = I18n.t('default.scheduled_meeting.distance_in_words.x_participants.other', { count: data.participants_count } )
    }

    // update start_ago
    var start_ago = $('#external-join').find('span#status-meeting')[0]
    if (data.running == false && data.ended == false) {
      start_ago.innerText = I18n.t('default.scheduled_meeting.external.not_started')
    } else if (data.running == true) {
      start_ago.innerText = I18n.t('default.scheduled_meeting.external.running', { duration: data.start_ago } )
    } else if (data.ended == true){
      start_ago.innerText = I18n.t('default.scheduled_meeting.external.ended')
    }

    // update image
    var image = $('#external-join').find('img')[0]
    if (data.running) {
      image.src= "/rooms/assets/meeting-running.svg"
    } else if (data.ended) {
      image?.remove()
    } else {
      image.src= "/rooms/assets/guest-wait.svg"
    }

    //remove form
    var form = $('#external-join').find('form')[0]
    if (data.ended) {
      form?.remove()
    }

    if (isMobile() && data.can_join_or_create) {
      $('#open-modal').removeClass('d-none')
      $('#browser-join').addClass('d-none')
    } else {
      $('#open-modal').addClass('d-none')
      $('#browser-join').removeClass('d-none')
    }
  };

  var isMobile = function() {
    const regex = /Mobi|Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i;
    return regex.test(navigator.userAgent);
  }

  var joinSession = function() {
    $('#wait-for-moderator').find('form [type=submit]').addClass('disabled');
    $('#wait-for-moderator').find('form').submit();
  };

  var downloadApp = function() {
    storeUrl = ''
    if(/iPhone/i.test(navigator.userAgent)){
      storeUrl = 'https://apps.apple.com/br/app/confer%C3%AAnciaweb/id1666641791'
    } else {
      if (/Android/i.test(navigator.userAgent)) {
      storeUrl = 'https://play.google.com/store/apps/details?id=br.rnp.conferenciawebmobile'
      }
    }

    window.location = storeUrl
  };

  $('.download-app-btn').on('click', function(e){
    e.preventDefault()
    downloadApp()
  });

  $('.open-app-btn').on('click', function(e){
    e.preventDefault()
    hash_id = $(e.target).data('meeting-hash-id')
    $(`#join_in_app-${hash_id}`).val(true)
    $(`#join-form-${hash_id}`).trigger("submit")
  });

  if (controller === 'scheduled_meetings' && action === 'external') {
    Polling.setPolling(pollStatusTeste)
  }

  if (controller === 'scheduled_meetings' && action === 'wait') {
    var room = $('#wait-for-moderator').data('room-id');
    var meeting = $('#wait-for-moderator').data('meeting-id');

    Polling.setPolling(pollStatus)

    var running = $('#wait-for-moderator').data('is-running');
    if (running === true) {
      let canJoin = $('#wait-for-moderator').data('can-join');
      if (canJoin === true && isMobile()){
        setTimeout(function() {
          $(".offcanvas-bottom").offcanvas('show');
        }, 200);
      } else {
        setTimeout(function() { joinSession(); }, 200);
      }
      return;
    }

    var auto = $('#wait-for-moderator').data('auto');
    if (auto === true) {
      var delay = 2000 + Math.floor(Math.random()*1000);
      setTimeout(function() { joinSession(); }, delay);
      return;
    }

    if (cable === 'true') {
      App.cable.subscriptions.create({
        channel: "WaitChannel",
        room: room,
        meeting: meeting
      }, {
        connected: function(data) {
          console.log("connected");
        },
        disconnected: function(data) {
          console.log("disconnected");
          console.log(data);
        },
        rejected: function() {
          console.log("rejected");
        },
        received: function(data) {
          console.log("received", data);
          if (data['action'] === 'started') {
            joinSession();
          }
        }
      });
    }
  }
});
