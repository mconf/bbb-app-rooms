module IconsHelper
  def icon_visibility(options={})
    material_icon_constructor "visibility", "icon material-icons icon-visibility", options
  end

  def icon_visibility_off(options={})
    material_icon_constructor "visibility_off", "icon material-icons icon-visibility-off", options
  end

  def icon_file_download(options={})
    material_icon_constructor "file_download", "icon material-icons icon-file-download", options
  end

  def icon_conference_play(options={})
    material_icon_constructor "play_arrow", "icon material-icons icon-conference-play", options
  end

  def icon_recording_load(options={})
    material_icon_constructor "hourglass_top", "icon material-icons icon-recording-load", options
  end

  def icon_options_dots(options={})
    material_icon_constructor "more_vert", "icon material-icons icon icon-options-dots", options
  end

  # Base method for most of the methods above
  def icon_constructor(title=nil, cls=nil, options={})
    options[:class] = options.has_key?(:class) ? cls + " " + options[:class] : cls
    title = title.nil? ? options[:title] : title
    unless title.nil? or title.blank?
      options = options_for_tooltip(title, options)
    end
    content_tag :i, nil, options
  end

  def material_icon_constructor(icon=nil, cls=nil, options={})
    options[:class] = options.has_key?(:class) ? cls + " " + options[:class] : cls
    title = title.nil? ? options[:title] : title
    unless title.nil? or title.blank?
      options = options_for_tooltip(title, options)
    end
    content_tag :i, icon, options
  end

  def text_icon_constructor(title, cls=nil, text=nil, options={})
    options[:class] = options.has_key?(:class) ? cls + options[:class] : cls
    content_tag :span, text, options_for_tooltip(title, options)
  end
end