# frozen_string_literal: true

require "spec_helper"

RSpec.describe Tesseron::Ruby::Server::App do
  subject(:app) { described_class.new(id: "shop", name: "Acme Shop") }

  describe "#action" do
    it "registers and returns an Action builder" do
      action = app.action("searchProducts")
      expect(action).to be_a(Tesseron::Ruby::Protocol::Action)
      expect(action.name).to eq("searchProducts")
    end

    it "allows chaining the builder" do
      action = app.action("addItem")
        .describe("Add an item to the cart")
        .input_schema({ type: "object", properties: { sku: { type: "string" } } })
        .handler { |input, _ctx| { added: input[:sku] } }

      expect(action.description).to eq("Add an item to the cart")
    end
  end

  describe "#resource" do
    it "registers and returns a Resource builder" do
      resource = app.resource("currentRoute")
      expect(resource).to be_a(Tesseron::Ruby::Protocol::Resource)
      expect(resource.name).to eq("currentRoute")
    end
  end

  describe "#call (Rack interface)" do
    it "returns 426 for non-WebSocket requests" do
      env = Rack::MockRequest.env_for("/")
      status, _headers, _body = app.call(env)
      expect(status).to eq(426)
    end
  end
end
