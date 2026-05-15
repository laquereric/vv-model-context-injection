# frozen_string_literal: true

require "spec_helper"

RSpec.describe Tesseron::Ruby do
  it "has a version number" do
    expect(Tesseron::Ruby::VERSION).not_to be_nil
  end

  it "exposes the protocol version constant" do
    expect(Tesseron::Ruby::Protocol::PROTOCOL_VERSION).to eq("1.1.0")
  end

  it "exposes the Server::App entry point" do
    expect(Tesseron::Ruby::Server::App).to be_a(Class)
  end

  it "exposes the Client::Connection entry point" do
    expect(Tesseron::Ruby::Client::Connection).to be_a(Class)
  end

  it "exposes the Gateway::McpBridge entry point" do
    expect(Tesseron::Ruby::Gateway::McpBridge).to be_a(Class)
  end
end
