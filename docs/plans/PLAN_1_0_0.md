# PLAN_1_0_0 — `vv-mcb` first stable release

> *Ratifies `vv-mcb` as the **Ruby replica of the Model-Context
> Injection (MCB) client/server exchange protocol** at the 1.0.0
> cut. v1.0.0 ships the **minimum viable consumer-pinned surface** —
> the `Vv::Mcb::Server::App` Rack application, the fluent
> `Protocol::Action` builder, the `Protocol::ActionContext`
> handler-side callback surface (`progress` / `confirm` / `elicit` /
> `sample` / `log`), the `Gateway::McpBridge` MCP server, the new
> `Gateway::WebmcpBridge` browser-side bridge with the `McbAdapter`,
> and the `Client::Connection` agent-side wrapper. v1.0.0 also
> finalises the **rename** from `tesseron-ruby` / `::Tesseron::Ruby::*`
> to `vv-mcb` / `::Vv::Mcb::*` so the gem matches the substrate's
> Model-Context Injection doctrine — the prior Tesseron framing is
> retired upstream and the gem follows it. The bet: lock the surface
> that the `magentic-market-ai` substrate already exercises (per
> `CONSUMER_REQUIREMENT_MM.md`) and defer everything else — multiple
> registry adapters beyond MCB, persistent-session resumption, AR /
> Bronze integration, additional gateway transports — until a
> consumer asks.*

## Anchors

| Anchor | Where | Role |
|---|---|---|
| `vendor/vv-mcb/README.md` | sibling | The gem's own user-facing contract. Documents the three sides (`Server::App`, `Gateway::McpBridge`, `Client::Connection`), the wire format, the method surface, the error codes, and the `ctx` callback table. The v1.0.0 surface is the README's surface. |
| `vendor/vv-mcb/CONSUMER_REQUIREMENT_MM.md` | sibling | The pinned consumer surface. Enumerates which classes, methods, and kwargs MM (the substrate) actually imports. Drift between this file and the gem signals a co-ordinated PR-pair. The v1.0.0 contract table below mirrors this file. |
| `magentic-market-ai/docs/plans/PLAN_0_27_5j.md` (parent repo) | upstream | The substrate plan that originally introduced the dependency as `tesseron-ruby`. |
| `magentic-market-ai/docs/plans/PLAN_0_81_0.md` | upstream | Solidified the CR (Consumer Requirement) discipline — every vendored gem keeps a `CONSUMER_REQUIREMENT_<consumer>.md`. |
| `magentic-market-ai/docs/plans/PLAN_0_82_1.md` | upstream | Retired the Tesseron doctrine substrate-side; the gem followed in `PLAN_0_92_0`. |
| `magentic-market-ai/docs/plans/PLAN_0_92_0.md` | upstream | Drove the rename: `tesseron-ruby` → `vv-mcb`; `::Tesseron::Ruby::*` → `::Vv::Mcb::*`; GitHub repo renamed to `vv-model-context-injection`. The CR file's "Last reviewed" line points here. |
| `magentic-market-ai/docs/plans/PLAN_0_93_0.md` | upstream | Drove the new `Gateway::WebmcpBridge` surface (Phase A in MM; Phase E here). Added `Protocol::Action#domain` and `Server::App#actions`. |
| `magentic-market-ai/docs/architecture/principles/model-context-injection.md` | upstream | The substrate doctrine this gem implements one side of. `ctx.sample` is the load-bearing primitive named there. |
| `magentic-market-ai/docs/architecture/principles/tesseron.md` | upstream (historical) | The **retired** doctrine page. Preserved as historical record; no new code is written against this framing. |
| `vendor/vv-agent/docs/plans/PLAN_0_1_0.md` | sibling | Independent of this gem by design. Agent calls *out* to hosted runtimes; MCB exposes substrate actions *to* hosted agents. Both can live in one substrate without conflict. Listed in vv-agent's own anchors table. |
| `vendor/vv-community/docs/plans/PLAN_0_1_0.md` | sibling | The "consumer-pinned surface" pattern this PLAN mirrors. Both gems exist for the substrate; both let MM call out drift via the CR file. |
| `vendor/vv-visualize/` | sibling | The other registry the WebMCP bridge aggregates. `Vv::Visualize::Wamp::ProcedureRegistry::WebmcpAdapter` is the second adapter constructed alongside `McbAdapter` in MM's `Harness::Mcb::WebmcpMount`. The bridge does not depend on `vv-visualize` — it depends on the adapter contract. |
| official `mcp` gem (rubygems) | upstream SDK | The bridge wraps `MCP::Client` / `MCP::Server`. Pinned at `~> 0.16.0` per the gemspec. v1.0.0's bridge code is the only place that knows about MCP wire conventions; the rest of the gem talks pure JSON-RPC. |

## Current state baseline (2026-05-27)

`vendor/vv-mcb/` carries the Bundler layout below, the full surface
catalogued in the v1.0.0 contract table, all six spec files
green, and an in-tree `VERSION` string `1.0.0`. Recent commits:

- `2cb1988` — initial implementation (as `tesseron-ruby`).
- `e13d9a4` — added `CONSUMER_REQUIREMENT_MM.md` (substrate-side
  consumer contract).
- `10d4db6` — `CONSUMER_REQUIREMENT_MM.md` Doctrine status banner
  (Tesseron → MCB).
- `3bcfada` — **1.0.0** — renamed gem `tesseron-ruby` → `vv-mcb`,
  namespace `::Tesseron::Ruby::*` → `::Vv::Mcb::*`.
- `b1f5c0f` — `Gateway::WebmcpBridge` — emit in-page JS that
  registers actions as WebMCP tools.

The substrate (`server/`) currently mounts the gem at
`server/packs/platform/app/services/harness/mcb/` and declares
~17 actions via the `app.action(...).describe(...).input_schema(...)
.annotate(...).handler { ... }` chain. `Harness::Mcb::WebmcpMount`
constructs the WebmcpBridge with two adapters
(`Gateway::WebmcpBridge::McbAdapter` + the visualize-side
`ProcedureRegistry::WebmcpAdapter`) and emits the JS via
`render_bridge_js(session_id:)`. Both surfaces are exercised on
every substrate boot.

The retired Tesseron framing remains in tree only as the legacy
`exe/tesseron-gateway` shim (kept as a backwards-compatibility
alias for one minor; tracked for removal in 1.1.0 — see "Out of
scope" / "Risks"). All Ruby modules, constants, and require paths
are under `Vv::Mcb`.

## Architectural shape (frozen at v1.0.0)

```
   ┌─────────────────────────────────────────────────────────────────────────┐
   │  Web-app side (your Rack app)                                           │
   │    Vv::Mcb::Server::App   (Rack app — accepts WS frames)                │
   │       │                                                                  │
   │       ├── app.action(name).describe(...).input_schema(...)              │
   │       │              .annotate(...).domain(...).handler { |in, ctx| } ──┼── operator code
   │       ├── app.resource(name).describe(...).read { ... }.subscribe { …}  │
   │       └── app.actions  (iterable — for WebmcpBridge::McbAdapter)        │
   └──────────────────┬─────────────────────────┬────────────────────────────┘
                      │                         │
                      │   JSON-RPC 2.0 / WS    ⇆
                      ▼                         ▼
   ┌──────────────────────────────┐  ┌───────────────────────────────────────┐
   │ Vv::Mcb::Gateway::McpBridge  │  │ Vv::Mcb::Gateway::WebmcpBridge        │
   │   wraps MCP::Server          │  │   render_bridge_js(session_id:) →     │
   │   speaks stdio / Streamable  │  │   inline <script> registers tools via │
   │   HTTP to MCP clients        │  │   navigator.modelContext.registerTool │
   │                              │  │   ├── McbAdapter   (Server::App tools)│
   │                              │  │   └── (any) adapter responding to     │
   │                              │  │       each_tool with the tool-hash    │
   └──────────────┬───────────────┘  └───────────────────────┬───────────────┘
                  │                                          │
   stdio / HTTP   ▼                                          ▼  in-page JS
   ┌──────────────────────────────┐  ┌───────────────────────────────────────┐
   │ Claude Desktop / Cursor /    │  │ Browser tab — Gemini-in-Chrome,       │
   │ Claude Code / Cline          │  │ LanguageModel({tools}), or any        │
   │ (MCP clients)                │  │ window.modelContext-aware agent       │
   └──────────────────────────────┘  └───────────────────────────────────────┘

   ┌──────────────────────────────┐
   │ Vv::Mcb::Client::Connection  │   (agent-side — thin MCP::Client wrapper;
   │   .connect / .invoke / ...   │    used by harness tests + tooling)
   └──────────────────────────────┘
```

The wire surface is **pure JSON-RPC 2.0 over a single WebSocket
text frame per message** between `Server::App` and either
`McpBridge` or any external WebMCP-side client. The MCP envelope is
spoken **only** by `McpBridge`; the rest of the gem is wire-agnostic.

`WebmcpBridge` is **render-time only** — it emits JS, it does not
hold a runtime connection. The in-page JS round-trips back through
the same `App` WebSocket that `McpBridge` uses on the other side.

## Scope

### Phase A — gem skeleton + Bundler layout

The repo layout the v1.0.0 cut freezes:

```
vv-mcb/
├── vv-mcb.gemspec
├── Gemfile
├── Gemfile.lock
├── Rakefile
├── VERSION                                   # "1.0.0"
├── lib/
│   └── vv/
│       ├── mcb.rb                            # top-level entry — requires the rest
│       └── mcb/
│           ├── version.rb                    # VERSION = "1.0.0"
│           ├── protocol/
│           │   ├── jsonrpc.rb                # request/notification/response shaping
│           │   ├── pending_requests.rb       # id correlation table
│           │   ├── action.rb                 # fluent builder (Phase B)
│           │   ├── action_context.rb         # ctx surface (Phase B)
│           │   └── resource.rb               # readable + subscribable app state
│           ├── server/
│           │   ├── app.rb                    # Rack app (Phase C)
│           │   └── websocket_transport.rb    # WS bridge + frame parsing
│           ├── client/
│           │   ├── connection.rb             # MCP::Client wrapper (Phase F)
│           │   └── websocket_transport.rb    # client-side WS adapter
│           └── gateway/
│               ├── mcp_bridge.rb             # MCP server (Phase D)
│               ├── webmcp_bridge.rb          # browser bridge (Phase E)
│               ├── webmcp_bridge/
│               │   └── mcb_adapter.rb        # App → tool-hash adapter
│               └── webmcp/
│                   └── js/
│                       └── bridge.js.erb     # the rendered in-page bridge
├── exe/
│   └── tesseron-gateway                      # legacy alias — slated 1.1.0 removal
├── bin/
│   ├── console
│   └── setup
├── spec/
│   ├── spec_helper.rb
│   └── vv/
│       ├── mcb_spec.rb
│       └── mcb/
│           ├── server/app_spec.rb
│           ├── protocol/
│           │   ├── action_spec.rb
│           │   ├── action_context_spec.rb
│           │   ├── jsonrpc_spec.rb
│           │   ├── pending_requests_spec.rb
│           │   └── resource_spec.rb
│           └── gateway/
│               └── webmcp_bridge_spec.rb
├── sig/                                      # placeholder for RBS sigs (empty at 1.0.0)
├── README.md
├── CONSUMER_REQUIREMENT_MM.md
└── docs/
    └── plans/
        └── PLAN_1_0_0.md                     # this file
```

#### Implementation
- `vv-mcb.gemspec`:
  - `spec.required_ruby_version = ">= 3.0.0"` (looser than the
    `vv-*` 3.4 floor on purpose — this gem is consumed by the
    substrate's Rails 8.1 app but does not depend on Rails).
  - Runtime deps: `mcp ~> 0.16.0`, `thor ~> 1.3.0`,
    `faye-websocket ~> 0.11.3`, `eventmachine ~> 1.2.7`,
    `rack ~> 3.0`, `puma ~> 6.4`.
  - **No** runtime dep on Rails, ActiveRecord, `vv-memory`, or
    `vv-community`. The gem is a protocol library, not a Rails
    engine; consumers mount it as a Rack app.
- `lib/vv/mcb.rb` is the single top-level entry, eagerly requiring
  every namespaced file. The top-level constant is
  `Vv::Mcb::Error < StandardError` (gem-wide base error class;
  bridge-specific subclasses live next to the bridge they belong
  to — see `WebmcpBridge::NameCollision`, `WebmcpBridge::MissingDomain`).
- Spec scaffold: vanilla `bundle exec rspec`. No Rails harness, no
  AR, no fixture loaders. Spec covers the protocol shapes
  (JSON-RPC, pending requests, action wire format, resource wire
  format), the action context callback surface, the app's wiring,
  and the WebMCP bridge's JS rendering.

#### Exit criteria (already met)
- `bundle install` from `vendor/vv-mcb/` resolves clean.
- `bundle exec rspec` is green; spec count tracks the surface
  catalogued in the contract table.
- `require "vv/mcb"` in a host Ruby process exposes
  `Vv::Mcb::VERSION == "1.0.0"`, `Vv::Mcb::Server::App`,
  `Vv::Mcb::Gateway::McpBridge`, `Vv::Mcb::Gateway::WebmcpBridge`,
  `Vv::Mcb::Client::Connection`, and `Vv::Mcb::Protocol::Action`.

### Phase B — protocol value objects

The wire vocabulary of the gem. All four files live under
`lib/vv/mcb/protocol/`. None of them reach out to a transport;
they are pure value objects / builders.

#### `Protocol::Jsonrpc`
- Module of factory methods that build the four JSON-RPC 2.0 shapes
  (`request`, `notification`, `success`, `error`) and parses a raw
  frame into one of those.
- The dispatcher in `Server::App` and `Gateway::McpBridge` reads
  the parsed shape's `:kind` (`:request | :notification | :response`)
  and routes accordingly.
- Spec covers: encode/decode round-trip; error-code constants
  match the README's table; malformed frames return a
  `parse_error`-shaped response with id `null`.

#### `Protocol::PendingRequests`
- Correlation table for outstanding requests (id → Promise / Queue).
- Used by `Server::App` to await `sampling/request`,
  `elicitation/request`, and the gateway's
  `actions/invoke` responses.
- Thread-safe (Monitor-guarded).
- Spec: register, resolve, reject, timeout-on-abandon all
  round-trip.

#### `Protocol::Action` (fluent builder)
- Constructor takes a string `name`; chainable setters mutate the
  builder and return `self`:
  - `.describe(text)` — human-readable description.
  - `.input_schema(hash)` — JSON Schema (any hash; not validated
    at build time; consumers' validators run at invoke time).
  - `.output_schema(hash)` — advisory unless `.strict_output!`.
  - `.annotate(read_only:, destructive:, requires_confirmation:)`
    — agent-visible hints; the substrate's `ActorGate` reads
    these by exact name.
  - `.timeout(ms:)` — invocation timeout (default 60 000 ms).
  - `.domain(value)` — WebMCP URI segment (Phase E);
    reader+setter polymorphic per CR contract.
  - `.handler { |input, ctx| ... }` — finalises the builder by
    attaching the 2-arity block.
- `#call(input, ctx)` — invokes the handler; raises `ArgumentError`
  if none registered.
- `#to_wire` — serialises the action to the `mcb/hello` payload
  shape (`name`, `description`, `inputSchema`, `outputSchema`,
  `annotations` mapped to camelCase, `timeoutMs`).
- The `domain` field is **stored but not serialised on the
  `mcb/hello` wire** — it is read directly by `WebmcpBridge::McbAdapter`
  in-process. This is deliberate: the MCP side doesn't care about
  the WebMCP URI scheme, so adding it to the hello frame would
  noise-up the audit.

#### `Protocol::ActionContext` (`ctx`)
- The per-invocation handle passed to every action handler.
- Pinned surface (per CONSUMER_REQUIREMENT_MM):

  | Method | Returns | Behaviour |
  |---|---|---|
  | `ctx.invocation_id` | String | Unique id for this invocation |
  | `ctx.agent` | `{id:, name:}` | Calling agent identity |
  | `ctx.agent_capabilities` | Hash | Capabilities declared in `mcb/hello` |
  | `ctx.client` | `{origin:, route:, user_agent:}` | Browser context |
  | `ctx.cancelled?` | Boolean | Flips to `true` on `actions/cancel` |
  | `ctx.progress(message:, percent: nil, data: nil)` | nil | Emits `actions/progress` notification |
  | `ctx.sample(messages:, system_prompt: nil, max_tokens: nil)` | String (or variant — see CR) | Asks the agent LLM; load-bearing for `model-context-injection.md` |
  | `ctx.confirm(question:)` | Boolean | Asks the user via the agent UI; `false` if unsupported |
  | `ctx.elicit(message:, schema: nil)` | Hash | Asks the user for structured input |
  | `ctx.log(level:, message:, meta: nil)` | nil | Structured log forwarded to MCP logging |

- The `ctx.sample` return shape *varies by upstream MCP client* —
  the CR documents that the substrate's `Mm::LlmMock::ExtractText`
  decodes the variance. The gem returns the raw string when the
  response is text-shaped, and the raw hash otherwise; the
  contract is "callable and matchable", not "specific shape".

#### `Protocol::Resource`
- Companion to `Action` for readable + subscribable app state.
- Fluent: `.describe(text)`, `.read { ... }`, `.subscribe { |emit| ... }`.
- `Server::App` calls the read block on `resources/read` and the
  subscribe block once per `resources/subscribe`; `emit.call(value)`
  pushes a `resources/updated` notification.
- v1.0.0 ships Resource but the substrate does not yet consume it
  (no entry in `CONSUMER_REQUIREMENT_MM.md`). Pinned anyway — the
  shape is straightforward and removing it later would be a
  major-version churn.

#### Exit criteria (already met)
- Specs: `action_spec.rb`, `action_context_spec.rb`,
  `jsonrpc_spec.rb`, `pending_requests_spec.rb`, `resource_spec.rb`
  all green.
- `Protocol::Action#to_wire` round-trips an action through a
  `mcb/hello` frame and back into a builder via the dispatcher's
  parser without losing fields.
- `Protocol::Action#domain(value)` returns `self`;
  `Protocol::Action#domain` returns the stored string (or nil).
- `ActionContext#progress` / `confirm` / `elicit` / `sample` /
  `log` each emit the right JSON-RPC envelope on a stubbed
  transport.

### Phase C — `Vv::Mcb::Server::App` (Rack application)

The app-side surface — the gem's primary consumer-pinned
entrypoint.

#### Constructor

```ruby
app = Vv::Mcb::Server::App.new(
  id:      "ai.magenticmarket.substrate",
  name:    "MagenticMarket",
  version: substrate_version,
)
```

Pinned by `CONSUMER_REQUIREMENT_MM.md`:

- `id:` is a free-form string the substrate controls. **No format
  validation** — reverse-DNS shapes like `ai.magenticmarket.substrate`
  must pass.
- `name:` and `version:` are surfaced via the gem's MCP-bridge
  identity (so connected agents see `"MagenticMarket v0.27.0"` in
  tool-list listings).
- Returned object is Rack-mountable (`#call(env)` → `[status,
  headers, body]`).

#### Surface

```ruby
app.action(name)         # → Protocol::Action builder
app.resource(name)       # → Protocol::Resource builder
app.actions              # → Array<Protocol::Action> in declaration order (CR-pinned)
app.resources            # → Array<Protocol::Resource>
app.call(env)            # Rack — upgrades to WebSocket, handles handshake
```

Pinned by CR:

- `app.action(name)` returns a `Protocol::Action` builder bound to
  the app. Subsequent fluent calls do not need to be re-attached;
  the builder calls `app.register_action(self)` on `.handler { ... }`.
- `app.actions` returns an **Array** (or any Enumerable) of
  `Protocol::Action` in declaration order. The
  `WebmcpBridge::McbAdapter` iterates this. Declaration-order
  stability is part of the contract — the tool catalogue is
  stable across reloads.

#### Lifecycle

1. WebSocket connects, app accepts the upgrade.
2. Gateway sends `mcb/hello` with its agent identity; app responds
   with `result` listing all registered actions + resources +
   capabilities (server's `name`, `version`, `id`).
3. Gateway sends `actions/invoke`; app validates input against
   `inputSchema`, instantiates an `ActionContext`, calls the
   action's handler, returns the result on the matching id.
4. While the handler runs, `ctx.progress(...)` emits
   `actions/progress` notifications. `ctx.sample`,
   `ctx.confirm`, `ctx.elicit` emit *request* envelopes back to
   the gateway and await the matching response via
   `PendingRequests`.
5. If the gateway sends `actions/cancel` with the matching id,
   `ctx.cancelled?` flips; the handler is responsible for
   honouring it (no preemptive thread kill).

#### Exit criteria (already met)
- Spec: `Server::App.new(id:, name:, version:)` constructs without
  validating `id:` shape (reverse-DNS allowed).
- Spec: `app.action("foo").handler { ... }` registers; `app.actions`
  includes it in declaration order.
- Spec: `mcb/hello` round-trip on a stubbed WS transport returns
  the expected server identity and the wire-form action list.
- Spec: an `actions/invoke` with `inputSchema` that the input fails
  to satisfy returns `error.code: -32004` (Input Validation), not
  an exception.
- Spec: a handler that raises returns `error.code: -32005` (Handler
  Error) with the exception class name + message in `data`.

### Phase D — `Gateway::McpBridge` (MCP server)

The MCP-side bridge. Wraps `MCP::Server` (from the `mcp` gem,
`~> 0.16.0`) and translates MCP `tools/call` requests into MCB
`actions/invoke` frames over the WebSocket transport.

#### Surface

```ruby
bridge = Vv::Mcb::Gateway::McpBridge.new(
  app_ws_url: "ws://localhost:4000",
  name:       "mcb-gateway",
)
bridge.run  # blocks; speaks MCP on stdio
```

Or via the executable shipped in `exe/`:

```bash
bundle exec mcb-gateway start ws://localhost:4000
```

#### Implementation
- Single-process: one WebSocket to one app, one MCP server on
  stdio (or Streamable HTTP — `mcp` gem's choice of transport).
- On startup: connect WS, exchange `mcb/hello`, build the tool list
  from the app's action descriptors, expose each as an MCP tool
  whose name is `"#{app_id}__#{action_name}"` (substrate's existing
  flat namespace; the WebMCP-side `mm.<domain>.<action>` URI is a
  separate concern).
- MCP `tools/call` → MCB `actions/invoke`: forwards input, awaits
  result, returns to MCP client. `actions/progress` notifications
  forward as MCP `notifications/progress`.

#### Exit criteria (already met)
- A stubbed MCP client connects to a `McpBridge` against a
  stubbed `Server::App` and round-trips an action invocation.
- The `exe/mcb-gateway` executable is wired via Thor and accepts
  `start <ws-url>`.
- The legacy `exe/tesseron-gateway` shim aliases to the same
  command (slated 1.1.0 removal — see Risks).

### Phase E — `Gateway::WebmcpBridge` (browser-side bridge)

The bridge added in commit `b1f5c0f`. Render-time only — emits an
inline-`<script>` JS bundle that registers tools via
`navigator.modelContext.registerTool` (the WebMCP spec).

#### Surface (CR-pinned)

```ruby
bridge = Vv::Mcb::Gateway::WebmcpBridge.new(adapters: [
  Vv::Mcb::Gateway::WebmcpBridge::McbAdapter.new(
    app:           McpApp.instance,
    websocket_url: McpApp.websocket_url_for(session),
  ),
  Vv::Visualize::Wamp::ProcedureRegistry::WebmcpAdapter.new(
    registry: Vv::Visualize::Wamp::ProcedureRegistry.instance,
  ),
])
bridge.render_bridge_js(session_id: session.id)
# => "(function(){ ... })();"   inline as a <script>
```

#### Adapter contract

Every adapter responds to `#each_tool` yielding hashes shaped:

```ruby
{
  domain:               String,
  action:               String,
  description:          String,
  input_schema:         Hash,
  annotations:          { read_only: Bool, untrusted_content: Bool, ... },
  transport_descriptor: Hash,   # see below
}
```

Tool names are composed as `"mm.#{domain}.#{action}"` and asserted
unique across adapters. Two collision modes raise at render time:

- `WebmcpBridge::MissingDomain` if `domain` is nil/empty.
- `WebmcpBridge::NameCollision` if two adapters yield the same
  `mm.<domain>.<action>`.

#### Transport descriptors

The bridge ships **two** transport kinds; the in-page JS dispatches
on `transport.kind`:

```ruby
{ kind: "mcb_ws",   url: "wss://example/mcb",      method: "action.invoke" }
{ kind: "wamp_rpc", url: "/visualize/rpc/<name>" }
```

`McbAdapter` emits `mcb_ws` descriptors. `wamp_rpc` is consumed
by `vv-visualize`'s adapter. New transport kinds land additively
in 1.0.x.

#### `McbAdapter` (Phase E sub-surface)

```ruby
McbAdapter.new(app:, websocket_url:).each_tool { |tool| ... }
```

Iterates `app.actions` and yields one tool-hash per action. Reads:

- `action.name` → tool `action`.
- `action.domain` → tool `domain`. Raises `MissingDomain` if unset.
- `action.description` → `description`.
- `action.input_json_schema` → `input_schema`.
- `action.annotations[:read_only]` → `annotations[:read_only]`.
- (Future) `action.annotations[:untrusted_content]` →
  `annotations[:untrusted_content]`. Default `false` at 1.0.0.

#### The emitted JS — window-global contract

The rendered JS exposes `window.__vvMcbWebmcp = { controller,
tools, transports }`. The substrate's
`vv-visualize--local-agent` Stimulus controller reads
`__vvMcbWebmcp.transports` and `__vvMcbWebmcp.tools` to drive the
Prompt API path. Per CR: changing the shape (key names, level
of nesting) is a breaking change.

#### Exit criteria (already met)
- Spec: `webmcp_bridge_spec.rb` builds a bridge with two stubbed
  adapters, renders the JS, parses the embedded tool array, and
  asserts the composed `mm.<domain>.<action>` names + transport
  descriptors.
- Spec: an adapter yielding two tools with the same
  `mm.<domain>.<action>` raises `NameCollision` at `collect_tools`
  time, before render.
- Spec: an adapter yielding a tool with `domain: nil` raises
  `MissingDomain`.
- Spec: the rendered JS string contains `window.__vvMcbWebmcp = `
  and the `controller`, `tools`, `transports` keys (substring
  checks — full JS evaluation is out of scope for unit specs).

### Phase F — `Client::Connection` (agent-side wrapper)

Thin wrapper around `MCP::Client` so substrate tooling + tests
can drive the bridge from Ruby without spawning a real agent.

```ruby
conn = Vv::Mcb::Client::Connection.new(
  command: "bundle",
  args:    ["exec", "mcb-gateway", "start", "ws://localhost:4000"],
)
conn.connect
conn.actions.each { |a| puts a.name }
result = conn.invoke("shop__searchProducts", query: "ruby")
conn.close
```

Not pinned by `CONSUMER_REQUIREMENT_MM.md` (MM does not currently
import it). Kept in the public surface because the gem's own
README documents it; pinning is **additive** in 1.0.x — drop into
a future CR if MM starts consuming.

#### Exit criteria
- The class exists and `require "vv/mcb"` loads it.
- (Future) Spec coverage lands when MM or another consumer starts
  importing it.

### Phase G — docs + housekeeping

- `README.md` — already in place; documents every surface in the
  Phase B-F catalogue.
- `CONSUMER_REQUIREMENT_MM.md` — already in place; pinned via
  PLAN_0_92_0 and PLAN_0_93_0 substrate-side.
- `docs/plans/PLAN_1_0_0.md` — this file. Created concurrently
  with this PR.
- `CHANGELOG.md` — **not yet present** in tree. Defer to 1.0.1
  when the first post-1.0.0 change lands; the rename + WebMCP work
  is captured by the commits + this PLAN.
- `VERSION` → `1.0.0`. Already there.

#### Exit criteria
- This PLAN is committed under `docs/plans/PLAN_1_0_0.md`.
- The `README.md`'s surface matches the v1.0.0 contract table
  exactly (already true — surface listed there is the surface
  shipped).
- `CONSUMER_REQUIREMENT_MM.md`'s "Last reviewed" line is current
  for the v1.0.0 cut (already at substrate commit `87d84cf` per
  PLAN_0_92_0).

## Out of scope for v1.0.0

- **A second MCP-style gateway (`StreamableHttpBridge`,
  `StdioBridge`, etc.).** The single `McpBridge` covers the
  stdio + Streamable HTTP transports the `mcp` gem ships. A
  per-transport bridge subclass lands additively when a consumer
  asks (or the upstream `mcp` gem refactors).
- **Persistent session resumption.** `Client::Connection`
  reconnect-on-drop + in-flight `actions/invoke` replay is a
  v1.1.x concern. v1.0.0 closes the WS on drop; the agent retries.
- **AR / Bronze integration.** No `vv-memory`, no
  `vv-community`, no AR persistence of invocations. This gem is
  a *protocol library*. Consumers who want audit log of every
  `actions/invoke` add a wrapping handler in their own code; the
  substrate's `Harness::Mcb::*` services already do.
- **Permission model.** The `annotate(read_only:, destructive:,
  requires_confirmation:)` flags are *hints*. Enforcement lives
  in the substrate's `ActorGate` — out of scope for the gem.
- **Resource subscription wire-format hardening.** `Protocol::Resource`
  is shipped but the substrate does not yet consume it. The
  `resources/subscribe` / `resources/updated` shapes may evolve
  *additively* in 1.0.x — non-breaking only — before the first
  consumer lands.
- **The legacy `exe/tesseron-gateway` shim.** Slated for removal
  in **1.1.0**. Kept for one minor as a backwards-compatibility
  alias for operator scripts that still type the old name.
- **RBS sigs.** `sig/` directory exists as a placeholder; v1.0.0
  ships no `.rbs` files. Adding them is additive; not a contract.
- **WebMCP transport kinds beyond `mcb_ws` and `wamp_rpc`.** The
  `transport_descriptor` shape is open-ended — new kinds land
  additively when an adapter ships one.
- **Multiple `Server::App` instances per process.** The bridge
  contract assumes one app per WS endpoint. A multi-app variant
  (e.g., one process exposing two MCB roots) is a 1.x.0 concern.
- **`Vv::Mcb::Engine` Rails engine wrapper.** This gem is **not**
  a Rails engine, deliberately. Mounting in a Rails substrate is
  via Rack routes, not via `mount`. A future Rails-engine shim
  could land in a separate gem (`vv-mcb-rails`) if a consumer
  asks; not here.
- **Publishing the `vv-mcb` name to rubygems.org.** Path-sourced
  via `gem "vv-mcb", path: "../vendor/vv-mcb"` in the substrate
  for the entire 1.x.x line. The gemspec carries
  `metadata["allowed_push_host"] = "https://rubygems.org"` but
  no actual push happens at this cut.

## v1.0.0 contract additions (frozen at release)

This table is the authoritative pinned surface; it duplicates and
extends `CONSUMER_REQUIREMENT_MM.md`. **Removing or renaming any
row below is a major-version change.**

| Surface | Shape | Mutability |
|---|---|---|
| `Vv::Mcb::VERSION` constant | String `"1.0.0"` | **Pinned.** |
| `Vv::Mcb::Error < StandardError` | base error class | **Pinned.** |
| `Vv::Mcb::Server::App.new(id:, name:, version:)` → Rack app | constructor | **Pinned signature.** `id:` accepts any string (no format validation). |
| `Vv::Mcb::Server::App#action(name)` → `Protocol::Action` | instance method | **Pinned.** Declaration order preserved in `#actions`. |
| `Vv::Mcb::Server::App#resource(name)` → `Protocol::Resource` | instance method | **Pinned.** |
| `Vv::Mcb::Server::App#actions` → Enumerable of `Protocol::Action` | instance method | **Pinned.** Iteration order matches declaration order. |
| `Vv::Mcb::Server::App#resources` → Enumerable of `Protocol::Resource` | instance method | **Pinned.** |
| `Vv::Mcb::Server::App#call(env)` | Rack `#call` | **Pinned.** WebSocket-upgrade-or-501. |
| `Vv::Mcb::Protocol::Action#describe(text)` | builder | **Pinned.** |
| `Vv::Mcb::Protocol::Action#input_schema(hash)` | builder | **Pinned.** |
| `Vv::Mcb::Protocol::Action#output_schema(hash)` | builder | **Pinned.** |
| `Vv::Mcb::Protocol::Action#annotate(read_only:, destructive:, requires_confirmation:)` | builder | **Pinned kwarg names.** Additive new kwargs allowed in 1.0.x. |
| `Vv::Mcb::Protocol::Action#timeout(ms:)` | builder | **Pinned.** Default `60_000`. |
| `Vv::Mcb::Protocol::Action#strict_output!` | builder | **Pinned.** |
| `Vv::Mcb::Protocol::Action#domain(value = nil)` → setter/reader | builder | **Pinned.** Polymorphic — reader without arg, setter (returns self) with arg. |
| `Vv::Mcb::Protocol::Action#handler { |input, ctx| ... }` | builder | **Pinned.** 2-arity block. |
| `Vv::Mcb::Protocol::ActionContext#invocation_id` / `#agent` / `#agent_capabilities` / `#client` / `#cancelled?` | readers | **Pinned method names.** |
| `Vv::Mcb::Protocol::ActionContext#progress(message:, percent: nil, data: nil)` | side-effect | **Pinned kwarg names.** |
| `Vv::Mcb::Protocol::ActionContext#sample(messages:, system_prompt: nil, max_tokens: nil)` → String/Hash | request | **Pinned kwarg names.** Return shape variance documented. |
| `Vv::Mcb::Protocol::ActionContext#confirm(question:)` → Boolean | request | **Pinned.** `false` when the agent does not support confirm. |
| `Vv::Mcb::Protocol::ActionContext#elicit(message:, schema: nil)` → Hash | request | **Pinned.** |
| `Vv::Mcb::Protocol::ActionContext#log(level:, message:, meta: nil)` | side-effect | **Pinned.** |
| `Vv::Mcb::Gateway::McpBridge.new(app_ws_url:, name:)` + `#run` | constructor + entry | **Pinned.** |
| `Vv::Mcb::Gateway::WebmcpBridge.new(adapters:)` | constructor | **Pinned.** `adapters:` is an Array of `#each_tool`-responding objects. |
| `Vv::Mcb::Gateway::WebmcpBridge#render_bridge_js(session_id:)` → String | render | **Pinned.** Returns inline-`<script>`-safe JS. |
| `Vv::Mcb::Gateway::WebmcpBridge#collect_tools` → Array<Hash> | render | **Pinned.** Public for tests + adapter authors. |
| `Vv::Mcb::Gateway::WebmcpBridge::McbAdapter.new(app:, websocket_url:)` + `#each_tool` | adapter | **Pinned.** |
| `Vv::Mcb::Gateway::WebmcpBridge::NameCollision` / `MissingDomain` | exception classes | **Pinned class names.** |
| Adapter tool-hash shape `{ domain:, action:, description:, input_schema:, annotations:, transport_descriptor: }` | convention | **Pinned key names.** Additive new keys allowed in 1.0.x. |
| Tool URI convention `"mm.<domain>.<action>"` | convention | **Pinned.** |
| `transport_descriptor` kinds — `mcb_ws` (with `url:`, `method:`), `wamp_rpc` (with `url:`) | convention | **Pinned kinds.** Additive new kinds allowed in 1.0.x. |
| Window-global `window.__vvMcbWebmcp = { controller, tools, transports }` | convention | **Pinned key names.** |
| `Vv::Mcb::Client::Connection.new(command:, args:)` + `#connect` / `#actions` / `#invoke` / `#close` | client API | **Pinned signatures.** Not consumed by MM at 1.0.0; pinned because the README documents it. |
| JSON-RPC error codes `-32700..-32005` per the README's table | convention | **Pinned numeric values + names.** |
| Reserved MCB method strings (`mcb/hello`, `actions/invoke`, `actions/cancel`, `actions/progress`, `actions/list_changed`, `resources/read`, `resources/subscribe`, `resources/unsubscribe`, `resources/updated`, `resources/list_changed`, `sampling/request`, `elicitation/request`, `log`) | convention | **Pinned.** |
| Wire-format keys for `Action#to_wire` (`name`, `description`, `inputSchema`, `outputSchema`, `annotations` → `readOnly` / `destructive` / `requiresConfirmation`, `timeoutMs`) | convention | **Pinned camelCase key names.** |
| `exe/mcb-gateway` executable + Thor `start <ws-url>` subcommand | CLI | **Pinned.** |
| `exe/tesseron-gateway` legacy alias | CLI | **Deprecated.** Slated 1.1.0 removal — not contract-pinned. |

## Risks

| Risk | Mitigation |
|---|---|
| The substrate adds an action handler that depends on an undocumented `ctx.*` method (e.g., a hypothetical `ctx.snapshot`) and the gem later refactors away from it. | The CR table enumerates every `ctx.*` method MM uses. Additions to `ActionContext` are additive only in 1.0.x; removals/renames require a co-ordinated PR pair (gem + substrate) at the next major. |
| `ctx.sample` return-shape variance leaks past `Mm::LlmMock::ExtractText` into a substrate handler. | Documented in CR as a known variance. The gem returns *what the upstream MCP client returned* — adapting the shape is the substrate's concern, not the gem's. A v1.1.x `ctx.sample_text` strict-string variant could land additively. |
| `Protocol::Action#domain` was added late (post-rename) and not all in-tree action declarations set it. Bridge raises `MissingDomain` at render time. | Documented. Every MM action declaration sets `.domain(...)` — that's enforced by the substrate's own `WebmcpMount` test suite. Operators adding new actions get a clear render-time error pointing at the missing line. |
| The legacy `exe/tesseron-gateway` alias confuses operators (running the old script + the new one against the same WS endpoint). | Slated 1.1.0 removal. The README's `## Quick Start` section uses `mcb-gateway` only. A deprecation banner could land in 1.0.x if the substrate or another consumer files a confusion report. |
| Re-record / re-rev of the bridge.js.erb template breaks `window.__vvMcbWebmcp` consumers (the visualize-side Stimulus controller). | The window-global shape is contract-pinned. The bridge's `webmcp_bridge_spec.rb` asserts the substring presence of `__vvMcbWebmcp` + the three top-level keys. Any further key rename is a major-version churn — not a 1.0.x change. |
| Two adapter authors yield tools with the same `mm.<domain>.<action>` URI from different registries. | `WebmcpBridge#collect_tools` raises `NameCollision` at render time. Substrate's `Harness::Mcb::WebmcpMount` test suite hits this on every boot — the offending PR fails to merge. |
| The `mcp` gem (upstream) makes a breaking change (`~> 0.16.0` → `0.17.0`). | The gemspec pins `~> 0.16.0`. Bumping is a co-ordinated PR-pair when the time comes; not silently auto-floated. |
| WebSocket transport flakes (faye-websocket + eventmachine are venerable). The substrate sometimes sees dropped frames. | Documented as a known limitation of the EM stack. A replacement transport (e.g., on top of `async` / `async-http`) is a v1.x.0 concern; the bridge's high-level surface stays the same. |
| Operators install `vv-mcb` outside of a Rack-WebSocket-capable server (e.g., Falcon, plain Webrick) and the upgrade handshake fails. | Documented in the README ("Start with `bundle exec puma config.ru -p 4000`"). The `Server::App` does not paper over an unsupported transport — it returns the upgrade-failure status the underlying server emits. |
| `Resource` ships unconsumed; later 1.0.x evolves its wire format and accidentally breaks a hypothetical-but-existing consumer. | The CR for resources is empty by design — no consumer pinned. Changes to `Protocol::Resource` between 1.0.0 and the first resource consumer are *additive only* by convention; a major-version bump frees up any actual breakage. |
| `version:` parameter of `Server::App.new` is a free-form string and an operator passes a non-semver value; agent-side listings render garbage. | Documented as the operator's contract with their tool-list consumers. The gem stores and forwards what was given. |
| The `exe/mcb-gateway` executable depends on `thor` and a `puma`-served WS endpoint; a slim substrate (e.g., a CI runner that needs only the gem's library surface) pulls them unnecessarily. | Acceptable cost at 1.0.0. Splitting into a library gem + an executable gem is a v1.x.0 cleanup if anyone asks. |

## Acceptance signal

1. Phase A–G all green; spec count tracks the contract table.
2. `bundle exec rspec` exits 0 from `vendor/vv-mcb/`.
3. `VERSION` → `1.0.0` (already in tree).
4. `README.md` documents every surface in the v1.0.0 contract table.
5. `CONSUMER_REQUIREMENT_MM.md` lists every surface MM imports and points at PLAN_0_92_0 / PLAN_0_93_0 for the substrate-side context.
6. `docs/plans/PLAN_1_0_0.md` (this file) is committed.
7. The substrate (`magentic-market-ai`) at the matching commit (`87d84cf` per CR's last-reviewed line) boots, mounts the app, renders the WebMCP bridge, and serves every action declared in `Harness::Mcb::*` against the tagged 1.0.0. (Substrate-side acceptance — tracked separately in MM's own plans.)

## Cross-references

- `../../README.md` — this gem's user-facing contract (the
  surface the v1.0.0 contract table mirrors).
- `../../CONSUMER_REQUIREMENT_MM.md` — the substrate-side pinned
  consumer surface; drift signals a co-ordinated PR pair.
- `../../../vv-agent/docs/plans/PLAN_0_1_0.md` — sibling
  outbound-agent gem. Independent of vv-mcb by design (different
  direction, different audience).
- `../../../vv-community/docs/plans/PLAN_0_1_0.md` — sibling
  consumer-pinned gem the PLAN structure here mirrors.
- `../../../../docs/architecture/principles/model-context-injection.md`
  — substrate doctrine; the `ctx.sample` surface is its
  load-bearing primitive.
- `../../../../docs/architecture/principles/tesseron.md` —
  **retired** doctrine. Historical only.
- `../../../../docs/plans/PLAN_0_92_0.md` — substrate plan that
  drove the gem rename (`tesseron-ruby` → `vv-mcb`).
- `../../../../docs/plans/PLAN_0_93_0.md` — substrate plan that
  drove `Protocol::Action#domain`, `Server::App#actions`, and
  `Gateway::WebmcpBridge`.
- upstream MCB reference docs:
  <https://brainblend-ai.github.io/mcb/>.
- upstream `mcp` Ruby SDK: rubygems `mcp ~> 0.16.0`.
