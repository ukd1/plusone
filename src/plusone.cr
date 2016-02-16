require "./plusone/*"
require "kemal"
require "openssl/hmac"
require "redis"
require "json"
require "uri"
require "http/params"

Kemal.config.port = ENV["PORT"].to_i

uri = URI.parse(ENV["REDIS_URL"])
$redis = Redis.new(uri.host.to_s, uri.port.to_s.to_i, nil, uri.password)

Plusone::Ping.start_pinging_redis

logger = Kemal::LogHandler.new

module Plusone
  def self.set_headers(context)
    # Caching headers - see https://github.com/github/markup/issues/224#issuecomment-37663375
    context.response.headers.add "Cache-Control", "no-cache, no-store, private, must-revalidate, max-age=0, max-stale=0, post-check=0, pre-check=0"
    context.response.headers.add "Pragma", "no-cache"
    context.response.headers.add "Expires", "0"
    context.response.content_type = "image/svg+xml"
  end

  def self.get_svg(text)
    color = "green"
    w = 100
    s_x = w * 0.7

    "<svg xmlns='http://www.w3.org/2000/svg' width='#{w}' height='20'><linearGradient id='a' x2='0' y2='100%'><stop offset='0' stop-color='#bbb' stop-opacity='.1'/><stop offset='1' stop-opacity='.1'/></linearGradient><rect rx='3' width='#{w}' height='20' fill='#555'/><rect rx='3' x='37' width='#{w - 37}' height='20' fill='#{color}'/><path fill='#{color}' d='M37 0h4v20h-4z'/><rect rx='3' width='#{w}' height='20' fill='url(#a)'/><g fill='#fff' text-anchor='middle' font-family='Geneva,sans-serif' font-size='11'><text x='19.5' y='15' fill='#010101' fill-opacity='.3'>build</text><text x='19.5' y='14'>+1s:</text><text x='#{s_x}' y='15' fill='#010101' fill-opacity='.3'>#{text}</text><text x='#{s_x}' y='14'>#{text}</text></g></svg>"
  end

  get "/" do |context|
    if Plusone::Auth.authed?(context, ENV["HTTP_USERNAME"], ENV["HTTP_PASSWORD"])
      repo = context.params.fetch("repo", "") as String
      issue = context.params.fetch("issue", "") as String

      instructions = ""

      if repo != "" && issue != ""
        counter = Plusone::Counter.new(repo, issue)
        badge = "https://#{ENV["HEROKU_APP_NAME"]}.herokuapp.com/count.svg?repo=#{repo}&issue=#{issue}&sig=#{counter.badge_signature}"
        webhook = "https://#{ENV["HEROKU_APP_NAME"]}.herokuapp.com/injest?repo=#{repo}&sig=#{counter.injest_signature}"

        # build the actual badge
        badge = "[![Issue " + issue + "](" + badge + ")](https://github.com/" + repo + "/issues/" + issue + ")"

        instructions = <<-HTML
            <h2>1. Setup Webhook</h2>
            <p>Set this once per repo. Go to <a href="https://github.com/#{repo}/settings/hooks">your github settings</a>:</p>

            <ol>
              <li>Set the <em>Payload URL</em> to:<br /><code>#{webhook}</code></li>
              <li>Then select "Let me select individual events."</li>
              <li>Then check "Issues" &amp; "Issue comment"</li>
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

  post "/injest" do |context|
    if context.params.fetch("repo", false) && context.params.fetch("sig", false)
      sig = context.params.fetch("sig").to_s
      counter = Plusone::Counter.new(context.params.fetch("repo").to_s)

      json = JSON.parse(context.request.body.to_s)
      if counter.injest_signature == sig
        if json["action"].to_s == "created" && json["comment"]["body"].to_s.includes?("+1")
          counter.set_issue_number(json["issue"]["number"])
          counter.incr(json["comment"]["user"]["id"])
        elsif json["action"].to_s == "created"
          logger.write("Comment doesn't have +1: #{json["comment"]["body"]}")
        else
          logger.write("Ignoring useless events: #{json.inspect}")
        end
      else
        logger.write("Invalid signature, please copy the URL again.")
      end
    else
      logger.write("Error missing parameters, please copy the URL again.")
    end
  end

  get "/test.svg" do |context|
    set_headers(context)
    count = context.params.fetch("count") as String
    get_svg(count)
  end

  get "/count.svg" do |context|
    set_headers(context)

    if context.params.fetch("repo", false) && context.params.fetch("issue", false) && context.params.fetch("sig", false)
      counter = Plusone::Counter.new(context.params.fetch("repo").to_s, context.params.fetch("issue").to_s)

      if counter.badge_signature == context.params.fetch("sig", "")
        get_svg(counter.count)
      else
        get_svg("Bad sig")
      end
    else
      get_svg("Bad url")
    end
  end
end
