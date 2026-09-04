require "test_helper"
require_relative "../../app/middleware/http_request_logger"
require_relative "../../app/middleware/elasticsearch_request_logger"

class SensitiveLoggingTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class CapturingElasticsearchClient
    attr_reader :documents

    def initialize
      @documents = []
    end

    def index(index:, body:)
      @documents << { index: index, body: body }
    end
  end

  test "Rails parameter filtering covers authentication payment and notification secrets" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      "password" => "password-value",
      "access_token" => "access-token-value",
      "client_secret" => "client-secret-value",
      "fcm_token" => "device-token-value",
      "card_number" => "card-value",
      "safe" => "visible"
    )

    assert_equal "[FILTERED]", filtered["password"]
    assert_equal "[FILTERED]", filtered["access_token"]
    assert_equal "[FILTERED]", filtered["client_secret"]
    assert_equal "[FILTERED]", filtered["fcm_token"]
    assert_equal "[FILTERED]", filtered["card_number"]
    assert_equal "visible", filtered["safe"]
  end

  test "Elasticsearch application logger redacts labelled secrets and JWT values" do
    logger = ElasticsearchLogger.allocate
    message = "token=plain-secret authorization:Bearer private-value eyJheader.eyJpayload.signature"

    sanitized = logger.send(:sanitized_message, message)

    assert_includes sanitized, "token=[FILTERED]"
    refute_includes sanitized, "plain-secret"
    refute_includes sanitized, "private-value"
    refute_includes sanitized, "eyJheader.eyJpayload.signature"
  end

  test "HTTP logger records metadata without request values response bodies or personal network data" do
    previous_client = $elasticsearch_client
    client = CapturingElasticsearchClient.new
    $elasticsearch_client = client
    response_secret = "response-secret-value"
    app = ->(_env) { [200, { "Content-Type" => "application/json" }, [JSON.generate(access_token: response_secret)]] }
    middleware = HttpRequestLogger.new(app)
    env = Rack::MockRequest.env_for(
      "/sessions?token=query-secret-value&email=person%40example.com",
      method: "POST",
      input: JSON.generate(password: "request-secret-value"),
      "CONTENT_TYPE" => "application/json",
      "HTTP_USER_AGENT" => "identifying-agent",
      "HTTP_REFERER" => "https://example.com/private"
    )

    middleware.call(env)

    document = client.documents.fetch(0).fetch(:body)
    serialized = document.to_json
    assert_equal "/sessions", document["path"]
    assert_includes document["request_parameter_keys"], "token"
    refute_includes serialized, "query-secret-value"
    refute_includes serialized, "request-secret-value"
    refute_includes serialized, response_secret
    refute_includes serialized, "person@example.com"
    refute_includes serialized, "identifying-agent"
    refute_includes serialized, "example.com/private"
    refute document.key?("client_ip")
    refute document.key?("response_body")
  ensure
    $elasticsearch_client = previous_client
  end

  test "HTTP error logger stores the exception class but not its potentially sensitive message" do
    previous_client = $elasticsearch_client
    client = CapturingElasticsearchClient.new
    $elasticsearch_client = client
    middleware = HttpRequestLogger.new(
      ->(_env) { raise StandardError, "token=error-secret-value" }
    )
    env = Rack::MockRequest.env_for("/failing")

    assert_raises(StandardError) { middleware.call(env) }

    document = client.documents.fetch(0).fetch(:body)
    assert_equal "StandardError", document["error_class"]
    refute_includes document.to_json, "error-secret-value"
  ensure
    $elasticsearch_client = previous_client
  end

  test "Elasticsearch middleware omits query strings IP addresses and identifying headers" do
    client = CapturingElasticsearchClient.new
    middleware = ElasticsearchRequestLogger.new(
      ->(_env) { [204, {}, []] }
    )
    middleware.instance_variable_set(:@elasticsearch_client, client)
    env = Rack::MockRequest.env_for(
      "/private?token=query-secret-value",
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_USER_AGENT" => "identifying-agent",
      "HTTP_REFERER" => "https://example.com/private"
    )

    middleware.call(env)

    document = client.documents.fetch(0).fetch(:body)
    serialized = document.to_json
    assert_equal "/private", document["path"]
    refute_includes serialized, "query-secret-value"
    refute_includes serialized, "127.0.0.1"
    refute_includes serialized, "identifying-agent"
    refute_includes serialized, "example.com/private"
    refute document.key?("ip_address")
    refute document.key?("query_string")
  end
end
