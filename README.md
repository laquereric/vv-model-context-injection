# tesseron-ruby

A Ruby replica of the [Tesseron](https://brainblend-ai.github.io/tesseron/) client/server exchange protocol, built on top of the [`mcp`](https://rubygems.org/gems/mcp) gem (the official Ruby MCP SDK).

Tesseron lets you expose typed web-app actions to MCP-compatible AI agents (Claude Code, Cursor, Claude Desktop) over a WebSocket — no browser automation, no scraping, no Playwright.

---

## Architecture

```
MCP client (Claude, Cursor, etc.)
    ↕  JSON-RPC over stdio / Streamable HTTP
Tesseron::Ruby::Gateway::McpBridge   ← this gem
    ↕  JSON-RPC 2.0 over WebSocket
Tesseron::Ruby::Server::App          ← this gem (Rack app)
    ↕  your Ruby business logic
```

The **app side** (`Server::App`) is a Rack application that accepts WebSocket connections from the gateway. It registers actions and resources, handles invocations, and streams progress notifications.

The **gateway side** (`Gateway::McpBridge`) is an MCP server (using the `mcp` gem) that connects to the app over WebSocket and translates MCP `tools/call` requests into Tesseron `actions/invoke` frames.

The **client side** (`Client::Connection`) is a thin wrapper around `MCP::Client` for agent-side usage.

---

## Installation

Add to your Gemfile:

```ruby
gem "tesseron-ruby"
```

Or install directly:

```bash
gem install tesseron-ruby
```

---

## Quick Start

### 1 — Define your app (Rack `config.ru`)

```ruby
require "tesseron/ruby"

app = Tesseron::Ruby::Server::App.new(id: "shop", name: "Acme Shop")

# A plain action with streaming progress
app.action("searchProducts")
   .describe("Search the product catalog")
   .input_schema({
     type: "object",
     properties: { query: { type: "string", minLength: 1 }, limit: { type: "integer" } },
     required: ["query"]
   })
   .handler do |input, ctx|
     ctx.progress(message: "searching...", percent: 20)
     items = store.search(input[:query], limit: input[:limit] || 10)
     ctx.progress(message: "done", percent: 100)
     { items: items }
   end

# An action that asks the user for confirmation
app.action("checkout")
   .describe("Place the pending order")
   .annotate(destructive: true, requires_confirmation: true)
   .input_schema({ type: "object", properties: { cart_id: { type: "string" } }, required: ["cart_id"] })
   .handler do |input, ctx|
     ok = ctx.confirm(question: "Place order for cart #{input[:cart_id]}? This charges your card.")
     raise "User cancelled" unless ok
     orders.place(input[:cart_id])
   end

# A resource — readable, subscribable app state
app.resource("currentRoute")
   .describe("URL the user is currently viewing")
   .read { request.path }
   .subscribe do |emit|
     # Call emit.call(value) whenever the route changes
   end

run app
```

Start the Rack server:

```bash
bundle exec puma config.ru -p 4000
```

### 2 — Start the MCP gateway

```bash
bundle exec tesseron-gateway start ws://localhost:4000
```

Or from Ruby:

```ruby
bridge = Tesseron::Ruby::Gateway::McpBridge.new(
  app_ws_url: "ws://localhost:4000",
  name: "my-tesseron-gateway"
)
bridge.run  # blocks; starts MCP server on stdio
```

### 3 — Wire the gateway into your agent

**Claude Desktop** (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "tesseron": {
      "command": "bundle",
      "args": ["exec", "tesseron-gateway", "start", "ws://localhost:4000"]
    }
  }
}
```

**Claude Code / Cursor**: same pattern, their own config file.

The agent now sees two MCP tools: `shop__searchProducts` and `shop__checkout`.

---

## Protocol Reference

### Wire Format

Every message is a JSON-RPC 2.0 object sent as a single WebSocket text frame.

| Shape | Fields | When |
|---|---|---|
| Request | `jsonrpc`, `id`, `method`, `params?` | Expects a response |
| Notification | `jsonrpc`, `method`, `params?` | Fire-and-forget, no `id` |
| Success response | `jsonrpc`, `id`, `result` | Reply to a request |
| Error response | `jsonrpc`, `id`, `error` | Reply with failure |

### Method Surface

**App → Gateway (you send):**

| Method | Kind | Purpose |
|---|---|---|
| `tesseron/hello` | request | Register app, actions, resources, capabilities |
| `actions/progress` | notification | Streaming update during an invocation |
| `actions/list_changed` | notification | Action list changed after hello |
| `resources/updated` | notification | Push a new value to a subscriber |
| `resources/list_changed` | notification | Resource list changed after hello |
| `sampling/request` | request | Ask the agent to run an LLM step |
| `elicitation/request` | request | Ask the user via the agent UI |
| `log` | notification | Structured log forwarded to MCP logging |

**Gateway → App (you handle):**

| Method | Kind | Purpose |
|---|---|---|
| `actions/invoke` | request | Agent called an action |
| `actions/cancel` | notification | Agent cancelled an in-flight invocation |
| `resources/read` | request | Agent requested current resource value |
| `resources/subscribe` | request | Agent subscribed to future updates |
| `resources/unsubscribe` | request | Agent unsubscribed |

### Error Codes

| Code | Name | Meaning |
|---|---|---|
| `-32700` | Parse Error | Malformed JSON |
| `-32600` | Invalid Request | Not a valid JSON-RPC object |
| `-32601` | Method Not Found | Unknown method |
| `-32602` | Invalid Params | Invalid method parameters |
| `-32603` | Internal Error | Internal server error |
| `-32000` | Protocol Mismatch | Incompatible `protocolVersion` in hello |
| `-32001` | Cancelled | Explicit cancellation by the agent |
| `-32002` | Timeout | Action timed out |
| `-32003` | Not Found | Unknown action or resource |
| `-32004` | Input Validation | Input failed schema validation |
| `-32005` | Handler Error | Unhandled exception in the action handler |

---

## API Reference

### `Tesseron::Ruby::Server::App`

The Rack application (app side of the WebSocket).

```ruby
app = Tesseron::Ruby::Server::App.new(id: "myapp", name: "My App")
app.action("doSomething").describe("...").input_schema({...}).handler { |input, ctx| ... }
app.resource("liveData").describe("...").read { current_value }.subscribe { |emit| ... }
run app
```

### `Tesseron::Ruby::Protocol::ActionContext` (`ctx`)

Passed to every action handler.

| Method | Purpose |
|---|---|
| `ctx.invocation_id` | Unique ID for this invocation |
| `ctx.agent` | `{ id:, name: }` of the calling agent |
| `ctx.agent_capabilities` | Capabilities declared at handshake |
| `ctx.client` | `{ origin:, route:, user_agent: }` |
| `ctx.cancelled?` | `true` if the agent sent `actions/cancel` |
| `ctx.progress(message:, percent:, data:)` | Emit a streaming progress notification |
| `ctx.sample(messages:, ...)` | Ask the agent LLM for a reasoning step |
| `ctx.confirm(question:)` | Ask the user yes/no; returns `false` if unsupported |
| `ctx.elicit(message:, schema:)` | Ask the user for structured input |
| `ctx.log(level:, message:, meta:)` | Emit a structured log message |

### `Tesseron::Ruby::Protocol::Action` (fluent builder)

| Method | Purpose |
|---|---|
| `.describe(text)` | Human-readable description |
| `.input_schema(hash)` | JSON Schema for input validation |
| `.output_schema(hash)` | JSON Schema for output (advisory) |
| `.annotate(**flags)` | `:read_only`, `:destructive`, `:requires_confirmation` |
| `.timeout(ms:)` | Abort after N milliseconds (default 60 000) |
| `.strict_output!` | Enforce output schema |
| `.handler { |input, ctx| ... }` | Register the handler block |

### `Tesseron::Ruby::Gateway::McpBridge`

MCP server that bridges to the Tesseron app.

```ruby
bridge = Tesseron::Ruby::Gateway::McpBridge.new(
  app_ws_url: "ws://localhost:4000",
  name: "tesseron-gateway"
)
bridge.run  # blocks
```

### `Tesseron::Ruby::Client::Connection`

Agent-side MCP client wrapper.

```ruby
conn = Tesseron::Ruby::Client::Connection.new(
  command: "bundle",
  args: ["exec", "tesseron-gateway", "start", "ws://localhost:4000"]
)
conn.connect
conn.actions.each { |a| puts a.name }
result = conn.invoke("shop__searchProducts", query: "ruby")
conn.close
```

---

## Development

```bash
bundle install
bundle exec rspec           # run tests
bundle exec rspec --format documentation  # verbose output
```

---

## License

MIT
