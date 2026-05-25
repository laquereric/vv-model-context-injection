# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vv::Mcb::Protocol::Action do
  subject(:action) { described_class.new("searchProducts") }

  describe "fluent builder" do
    it "sets the name" do
      expect(action.name).to eq("searchProducts")
    end

    it "sets description via .describe" do
      action.describe("Search the product catalog")
      expect(action.description).to eq("Search the product catalog")
    end

    it "sets input schema via .input_schema" do
      schema = { type: "object", properties: { query: { type: "string" } } }
      action.input_schema(schema)
      expect(action.input_json_schema).to eq(schema)
    end

    it "sets output schema via .output_schema" do
      schema = { type: "object", properties: { items: { type: "array" } } }
      action.output_schema(schema)
      expect(action.output_json_schema).to eq(schema)
    end

    it "sets annotations via .annotate" do
      action.annotate(read_only: true, destructive: false)
      expect(action.annotations[:read_only]).to be(true)
    end

    it "sets timeout via .timeout" do
      action.timeout(ms: 30_000)
      expect(action.timeout_ms).to eq(30_000)
    end

    it "defaults timeout to 60_000 ms" do
      expect(action.timeout_ms).to eq(60_000)
    end

    it "enables strict output via .strict_output!" do
      expect(action.strict_output?).to be(false)
      action.strict_output!
      expect(action.strict_output?).to be(true)
    end

    it "returns self from builder methods for chaining" do
      expect(action.describe("test")).to be(action)
      expect(action.timeout(ms: 1000)).to be(action)
    end
  end

  describe "#call" do
    it "invokes the registered handler with input and context" do
      ctx = instance_double(Vv::Mcb::Protocol::ActionContext, cancelled?: false)
      action.handler { |input, _ctx| { result: input[:query].upcase } }
      result = action.call({ query: "ruby" }, ctx)
      expect(result).to eq({ result: "RUBY" })
    end

    it "raises ArgumentError when no handler is registered" do
      ctx = instance_double(Vv::Mcb::Protocol::ActionContext, cancelled?: false)
      expect { action.call({}, ctx) }.to raise_error(ArgumentError, /No handler registered/)
    end
  end

  describe "#to_wire" do
    it "serialises to the expected wire format" do
      action
        .describe("Search products")
        .input_schema({ type: "object" })
        .annotate(read_only: true)
        .timeout(ms: 15_000)
        .handler { |_input, _ctx| {} }

      wire = action.to_wire
      expect(wire[:name]).to eq("searchProducts")
      expect(wire[:description]).to eq("Search products")
      expect(wire[:inputSchema]).to eq({ type: "object" })
      expect(wire[:annotations][:readOnly]).to be(true)
      expect(wire[:timeoutMs]).to eq(15_000)
    end
  end
end
