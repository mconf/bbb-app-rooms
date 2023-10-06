# coding: utf-8
# frozen_string_literal: true

require 'user'
require 'bbb_api'

class WorkaController < ApplicationController
  include ApplicationHelper

  def open
    @url_to_open = 'http://play.workadventure.localhost/'
    redirect_to @url_to_open
  end

end
