# frozen_string_literal: true

key_name = ENV['OMNIAUTH_BBBLTIBROKER_KEY']
secret = ENV['OMNIAUTH_BBBLTIBROKER_SECRET']

default_tools = [
  {
    name: ENV['DEFAULT_LTI_TOOL'],
    uid: key_name,
    secret: secret,
    redirect_uri: "#{ENV['APP_ROOMS_URL']}/rooms/auth/bbbltibroker/callback",
    scopes: 'api'
  }
]

default_tools.each do |default_tool|
  app = Doorkeeper::Application.find_by(name: default_tool[:name])
  if app.present?
    puts "Creating app #{default_tool[:name]}"
    app.update_attributes(default_tool)
  else
    puts "Updating app #{default_tool[:name]}"
    Doorkeeper::Application.create!(default_tool)
  end
end
