# A module to control guest access to the website.
# A guest is a user that is authenticated somehow but doesn't have an account.
# Their information is stored in a cookie with a short expiration time.
module GuestUserModule
  # the name of the cookie
  COOKIE_KEY = :_mconf_guest

  # how long the cookie will last (in seconds)
  COOKIE_DURATION = 3600 # 1h

  def guest_user_signed_in?
    cookies.encrypted[GuestUserModule::COOKIE_KEY].present?
  end

  def current_guest_user
    cookie = cookies.encrypted[GuestUserModule::COOKIE_KEY]
    if cookie.present?
      @guest = {
        uid: cookie['uid'],
        first_name: cookie['first_name'],
        last_name: cookie['last_name']
      }
      @guest
    else
      nil
    end
  end

  def sign_in_guest(first_name, last_name, expires=nil)
    expires ||= Time.now + COOKIE_DURATION
    cookies.encrypted[GuestUserModule::COOKIE_KEY] = {
      value: {
        uid: SecureRandom.uuid.gsub(/\D+/,"").first(7).to_i,
        first_name: first_name,
        last_name: last_name
      },
      expires: expires
    }
  end

  def logout_guest
    cookies.delete(COOKIE_KEY)
  end
end
