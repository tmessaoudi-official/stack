require 'json'

def handler(event:, context:)
  {
    statusCode: 200,
    body: {
      message: "Hello from Lambda/Ruby running offline!, Running on Ruby version: #{RUBY_VERSION} #{Dir.pwd}",
      input: event,
      context: context.to_s
    }.to_json
  }
end