module Plusone
  module Auth
    BASIC                 = "Basic"
    AUTH                  = "Authorization"
    AUTH_MESSAGE          = "Please check your username and password. If you're stuck or want to know what this is, checkout: <a href=https://github.com/ukd1/plusone>+1 source code</a>"
    HEADER_LOGIN_REQUIRED = "Basic realm=\"Login Required\""

    def self.authed?(context, username, password)
      authed = false
      if context.request.headers[AUTH]?
        if value = context.request.headers[AUTH]
          if value.size > 0 && value.starts_with?(BASIC)
            sent_username, sent_password = Base64.decode_string(value[BASIC.size + 1..-1]).split(":")
            return true if sent_username == username && sent_password == password
          end
        end
      end

      context.response.status_code = 401
      context.response.headers["WWW-Authenticate"] = HEADER_LOGIN_REQUIRED
      context.response.print AUTH_MESSAGE

      return false
    end
  end
end
