# frozen_string_literal: true

require "spec_helper"

RSpec.describe Tesseron::Ruby::Protocol::Resource do
  subject(:resource) { described_class.new("currentRoute") }

  describe "fluent builder" do
    it "sets the name" do
      expect(resource.name).to eq("currentRoute")
    end

    it "sets description via .describe" do
      resource.describe("URL the user is viewing")
      expect(resource.description).to eq("URL the user is viewing")
    end

    it "returns self from builder methods for chaining" do
      expect(resource.describe("test")).to be(resource)
    end
  end

  describe "#current_value" do
    it "returns the value from the read handler" do
      resource.read { "/home" }
      expect(resource.current_value).to eq("/home")
    end

    it "raises when no read handler is registered" do
      expect { resource.current_value }.to raise_error(ArgumentError, /No read handler/)
    end
  end

  describe "#subscribable?" do
    it "is false without a subscribe handler" do
      expect(resource.subscribable?).to be(false)
    end

    it "is true after a subscribe handler is registered" do
      resource.subscribe { |_emit| }
      expect(resource.subscribable?).to be(true)
    end
  end

  describe "#to_wire" do
    it "includes subscribable flag when a subscribe handler exists" do
      resource.describe("Current route").subscribe { |_emit| }
      wire = resource.to_wire
      expect(wire[:name]).to eq("currentRoute")
      expect(wire[:description]).to eq("Current route")
      expect(wire[:subscribable]).to be(true)
    end

    it "omits subscribable when no subscribe handler exists" do
      wire = resource.to_wire
      expect(wire).not_to have_key(:subscribable)
    end
  end

  describe "#add_subscriber and push updates" do
    it "notifies subscribers when a value is emitted" do
      received = []
      emit_ref = nil

      resource.subscribe { |emit| emit_ref = emit }
      resource.add_subscriber(->(v) { received << v })

      # Simulate the subscribe block calling emit
      emit_ref.call("/about")
      expect(received).to eq(["/about"])
    end
  end
end
