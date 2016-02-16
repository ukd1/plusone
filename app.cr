require "kemal"
require "openssl/hmac"
require "redis"
require "json"
require "uri"
require "http/params"

ENV["HTTP_USERNAME"] ||= "admin"
ENV["HTTP_PASSWORD"] ||= "password"
ENV["HEROKU_APP_NAME"] ||= "your-app-name-here"
ENV["HMAC_SECRET"] ||= "test"
ENV["PORT"] ||= "3000"
Kemal.config.port = ENV["PORT"].to_i

ENV["REDIS_URL"] ||= "redis://localhost:6379"
uri = URI.parse(ENV["REDIS_URL"])
$redis = Redis.new(uri.host.to_s, uri.port.to_s.to_i, nil, uri.password)

logger = Kemal::LogHandler.new

# Keep redis alive
spawn do
  loop do
    $redis.ping
    sleep(1)
  end
end

BASIC                 = "Basic"
AUTH                  = "Authorization"
AUTH_MESSAGE          = "Please check your username and password. If you're stuck or want to know what this is, checkout: <a href=https://github.com/ukd1/plusone>+1 source code</a>"
HEADER_LOGIN_REQUIRED = "Basic realm=\"Login Required\""  
def authed?(context, username, password)
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


get "/" do |context|
  if authed?(context, ENV["HTTP_USERNAME"], ENV["HTTP_PASSWORD"])
    repo = context.params.fetch("repo", "") as String
    issue = context.params.fetch("issue", "") as String
    
    instructions = ""

    if repo != "" && issue != ""
      key = redis_key(repo, issue)
      badge = "https://#{ENV["HEROKU_APP_NAME"]}.herokuapp.com/count.svg?repo=#{repo}&issue=#{issue}&sig=#{sign(key)}"
      webhook = "https://#{ENV["HEROKU_APP_NAME"]}.herokuapp.com/injest?repo=#{repo}&sig=#{sign("injest/#{repo}")}"

      # build the actual badge
      badge = "[![Issue " + issue + "](" + badge + ")](https://github.com/" + repo + "/issues/" + issue + ")"

      instructions = <<-HTML
            <h2>1. Setup Webhook</h2>
            <p>Set this once per repo. Go to <a href="https://github.com/#{repo}/settings/hooks">your github settings</a>:</p>

            <ol>
              <li>Set the <em>Payload URL</em> to:<br /><code>#{webhook}</code></li>
              <li>Then select "Let me select individual events."</li>
              <li>Then check "Issues" & "Issue comment"</li>
            </ol>

            <h2>2. Get Badge</h2>
            <p>Paste the following code in to your issue:</p>

            <code>#{badge}</code>
      HTML
    end

    template = <<-HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>+1</title>
          <style type="text/css">
          body { font-family:helvetica,arial;color:#888;margin:2em}
          ol li { margin-bottom: 1em; }
          code { margin: 0.5em; padding: 0.5em; background-color: #eee; display: inline-block; }
          </style>
        </head>
        <body>
          <h1>Hello.</h1>
          <p>Enter your repo name and issue number to get started.</p>

          <form method="get">
            <input type="text" name="repo" value="#{repo}" placeholder="ukd1/plusone" />
            <input type="number" name="issue" value="#{issue}" placeholder="1" />
            <input type="submit" value="Get URLs" />
          </form>

          #{instructions}
        </body>
        </html>
    HTML
    
    template
  end
end

post "/injest" do |env|
  if env.params.fetch("repo", false) && env.params.fetch("sig", false)
    repo = env.params.fetch("repo") as String
    sig = env.params.fetch("sig") as String

    json = JSON.parse(env.request.body.to_s)
    if valid_key?("injest/#{repo}", sig)
      if json["action"].to_s == "created" && json["comment"]["body"].to_s.includes?("+1")
        incr_count(json["repository"]["full_name"], json["issue"]["number"], json["comment"]["user"]["id"])
      else
        logger.write("Ignoring events: #{json.inspect}")
      end
    else
      # Invalid signature. Write a valid one to the log so admin can set it up.
    key = redis_key(json["repository"]["full_name"], json["issue"]["number"])
      "Invalid signature."
    end
  else
    "Error missing parameters. Please contact support."
  end
end

get "/test.svg" do |env|
  # Caching headers - see https://github.com/github/markup/issues/224#issuecomment-37663375
  env.response.headers.add "Cache-Control", "no-cache, no-store, private, must-revalidate, max-age=0, max-stale=0, post-check=0, pre-check=0"
  env.response.headers.add "Pragma", "no-cache"
  env.response.headers.add "Expires", "0"
  env.response.content_type = "image/svg+xml"

  count = env.params.fetch("count") as String

  get_svg(count)
end

get "/count.svg" do |env|
  # Caching headers - see https://github.com/github/markup/issues/224#issuecomment-37663375
  env.response.headers.add "Cache-Control", "no-cache, no-store, private, must-revalidate, max-age=0, max-stale=0, post-check=0, pre-check=0"
  env.response.headers.add "Pragma", "no-cache"
  env.response.headers.add "Expires", "0"
  env.response.content_type = "image/svg+xml"

  if env.params.fetch("repo", false) && env.params.fetch("issue", false) && env.params.fetch("sig", false)
    repo = env.params.fetch("repo") as String
    issue = env.params.fetch("issue") as String
    sig = env.params.fetch("sig") as String

    key = redis_key(repo, issue)
    if valid_key?(key, sig)
      env.response.content_type = "image/svg+xml"
      get_badge(repo, issue)
    else
      logger.write("Invalid signature.\n")
      get_svg("Bad sig")
    end
  else
    get_svg("Bad url")
  end
end

def valid_key?(key, signature)
  signature == sign(key)
end

def sign(key)
  OpenSSL::HMAC.hexdigest(:sha512, ENV["HMAC_SECRET"], key.to_s)
end

def redis_key(repo, issue)
  "p1:#{repo}:#{issue}"
end

def incr_count(repo, issue, user_id)
  $redis.sadd(redis_key(repo, issue), user_id)
end

def current_count(repo, issue)
  $redis.scard(redis_key(repo, issue)).to_i.to_s
end

def get_badge(repo, issue)
  get_svg(current_count(repo, issue))
end

def get_svg(text)
  color = "green"
  w = 100
  s_x = w * 0.7

  "<svg xmlns='http://www.w3.org/2000/svg' width='#{w}' height='20'><linearGradient id='a' x2='0' y2='100%'><stop offset='0' stop-color='#bbb' stop-opacity='.1'/><stop offset='1' stop-opacity='.1'/></linearGradient><rect rx='3' width='#{w}' height='20' fill='#555'/><rect rx='3' x='37' width='#{w - 37}' height='20' fill='#{color}'/><path fill='#{color}' d='M37 0h4v20h-4z'/><rect rx='3' width='#{w}' height='20' fill='url(#a)'/><g fill='#fff' text-anchor='middle' font-family='Geneva,sans-serif' font-size='11'><text x='19.5' y='15' fill='#010101' fill-opacity='.3'>build</text><text x='19.5' y='14'>+1s:</text><text x='#{s_x}' y='15' fill='#010101' fill-opacity='.3'>#{text}</text><text x='#{s_x}' y='14'>#{text}</text></g></svg>"
end
