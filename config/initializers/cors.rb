# frozen_string_literal: true

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins do |source, _env|
      CorsOrigins.list.include?(source) ? source : nil
    end

    resource "*",
             headers: :any,
             methods: %i[get post put patch delete options head],
             expose: [ "X-Request-Id" ],
             max_age: 600
  end
end
