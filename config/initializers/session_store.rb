# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

attrs = {
  key: '_bbb_app_rooms_session',
  secure: ENV['COOKIES_SECURE_OFF'].blank?,
  same_site: ENV['COOKIES_SAME_SITE'].blank? ? 'None' : ENV['COOKIES_SAME_SITE']
}
Rails.application.config.session_store(:cookie_store, **attrs)


# Patch the `Rack::Utils` method that set cookies, to add the `partitioned` cookie attribute.
# More info about the attribute here: https://developers.google.com/privacy-sandbox/3pcd/chips?hl=pt-br
#
# Necessary until this [PR](https://github.com/rack/rack/pull/2131) is released into a stable version
# Base code defined in https://github.com/rack/rack/blob/v2.2.9/lib/rack/utils.rb#L237-L276
module RackUtilsMonkeypatch

  def self.add_cookie_to_header(header, key, value)
    case value
    when Hash
      domain  = "; domain=#{value[:domain]}"   if value[:domain]
      path    = "; path=#{value[:path]}"       if value[:path]
      max_age = "; max-age=#{value[:max_age]}" if value[:max_age]
      expires = "; expires=#{value[:expires].httpdate}" if value[:expires]
      secure  = "; secure"  if value[:secure]
      httponly = "; HttpOnly" if (value.key?(:httponly) ? value[:httponly] : value[:http_only])
      same_site =
        case value[:same_site]
        when false, nil
          nil
        when :none, 'None', :None
          '; SameSite=None'
        when :lax, 'Lax', :Lax
          '; SameSite=Lax'
        when true, :strict, 'Strict', :Strict
          '; SameSite=Strict'
        else
          raise ArgumentError, "Invalid SameSite value: #{value[:same_site].inspect}"
        end
      partitioned = "; partitioned" # adding the attribute to all cookies, whether it's present on value or not
      value = value[:value]
    end
    value = [value] unless Array === value

    cookie = "#{Rack::Utils.escape(key)}=#{value.map { |v| Rack::Utils.escape v }.join('&')}#{domain}" \
      "#{path}#{max_age}#{expires}#{secure}#{httponly}#{same_site}#{partitioned}"

    case header
    when nil, ''
      cookie
    when String
      [header, cookie].join("\n")
    when Array
      (header + [cookie]).join("\n")
    else
      raise ArgumentError, "Unrecognized cookie header value. Expected String, Array, or nil, got #{header.inspect}"
    end
  end

end

# Overwrite the method that calls `::Rack::Utils.add_cookie_to_header` to use our monkeypatch.
# Base code defined in https://github.com/rails/rails/blob/v6.1.4.4/actionpack/lib/action_dispatch/middleware/cookies.rb#L424-L435
class ActionDispatch::Cookies::CookieJar
  private
  def make_set_cookie_header(header)
    header = @set_cookies.inject(header) { |m, (k, v)|
      if write_cookie?(v)
        # ::Rack::Utils.add_cookie_to_header(m, k, v)
        ::RackUtilsMonkeypatch.add_cookie_to_header(m, k, v) # calling the monkeypatch method
      else
        m
      end
    }
    @delete_cookies.inject(header) { |m, (k, v)|
      ::Rack::Utils.add_remove_cookie_to_header(m, k, v)
    }
  end
end
