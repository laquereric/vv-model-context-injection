# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vv::Mcb do
  it "has a version number" do
    expect(Vv::Mcb::VERSION).not_to be_nil
  end

  it "exposes the protocol version constant" do
    expect(Vv::Mcb::Protocol::PROTOCOL_VERSION).to eq("1.1.0")
  end

  it "exposes the Server::App entry point" do
    expect(Vv::Mcb::Server::App).to be_a(Class)
  end

  it "exposes the Client::Connection entry point" do
    expect(Vv::Mcb::Client::Connection).to be_a(Class)
  end

  it "exposes the Gateway::McpBridge entry point" do
    expect(Vv::Mcb::Gateway::McpBridge).to be_a(Class)
  end

  it "exposes the Gateway::WebmcpBridge entry point" do
    expect(Vv::Mcb::Gateway::WebmcpBridge).to be_a(Class)
  end
end
