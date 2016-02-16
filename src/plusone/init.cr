# Default a bunch of env vars for development
ENV["HTTP_USERNAME"] ||= "admin"
ENV["HTTP_PASSWORD"] ||= "password"
ENV["HEROKU_APP_NAME"] ||= "your-app-name-here"
ENV["HMAC_SECRET"] ||= "test"
ENV["PORT"] ||= "3000"
ENV["REDIS_URL"] ||= "redis://localhost:6379"
