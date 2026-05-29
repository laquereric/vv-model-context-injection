# Consumer requirements — MagenticMarket substrate

This file records the surface
[MagenticMarket](https://github.com/laquereric/magentic-market-ai)
(the substrate; "MM" hereafter) consumes from `vv-mcb`.
It exists so upstream changes can be checked against a written
consumer expectation — **drift** between this file and the gem's
actual behaviour signals work that needs to land in both repos
lockstep.

- MM repo: <https://github.com/laquereric/magentic-market-ai>
- MM plan that introduced this dependency: `docs/plans/PLAN_0_27_5j.md`
  (originally as `tesseron-ruby`, a Ruby SDK named after the
  Tesseron client/server exchange protocol)
- MM plan that solidified the CR discipline: `docs/plans/PLAN_0_81_0.md`
- MM plan that retired the Tesseron doctrine: `docs/plans/PLAN_0_82_1.md`
  (the substrate's framing doctrine became Model-Context Injection
  / MCB; the gem stayed pinned)
- MM plan that renamed the gem + namespace: `docs/plans/PLAN_0_92_0.md`
  (`tesseron-ruby` → `vv-mcb`; `::Tesseron::Ruby::*` → `::Vv::Mcb::*`;
  GitHub repo renamed to `vv-model-context-injection`)
- Sibling consumers (if any): none registered

> **Status note.** Locked-in for the Alpha distribution. The
> substrate is the gem's primary consumer; the gem's surface
> evolves through MM PR-pairs (gem repo + substrate). The
> upstream's own roadmap lives at `vendor/vv-mcb/docs/plans/`
> (per "gems do their own planning"); MM declares what it
> currently exercises, no more.

## How MM pins this gem

```ruby
# server/Gemfile — local development (submodule checkout)
gem "vv-mcb", path: "../vendor/vv-mcb"

# server/Gemfile — CI / production (pinned SHA, when path moves to git)
# gem "vv-mcb", git: "https://github.com/laquereric/vv-model-context-injection",
#               ref: "<sha>"
```

`vendor/vv-mcb` is a tracked git submodule; the substrate's
`Gemfile.lock` records the resolved version. CI clones submodules
by default (`actions/checkout` with `submodules: 'true'`).

## Surfaces MM consumes

The substrate's actual import surface is *narrower than the gem's
full API*. MM uses:

### `::Vv::Mcb::Server::App`

The app-side Rack application class. Constructed once at boot in
`server/packs/platform/app/services/harness/mcb/app.rb`:

```ruby
app = ::Vv::Mcb::Server::App.new(
  id:      "ai.magenticmarket.substrate",
  name:    "MagenticMarket",
  version: substrate_version,
)
```

MM relies on:

- The `id:` parameter being a free-form string the substrate
  controls (substrate identifier per the cross-platform identifier
  scheme — `alpha-distribution-scope.md`).
- The `name:` + `version:` parameters being surfaced via the gem's
  MCP-bridge identity (so connected agents see "MagenticMarket
  v0.27.0" in their tool-list listings).
- The returned app being a Rack-mountable object.

### `app.action(name).describe(desc).input_schema({}).annotate(...).handler { … }`

The fluent action-declaration chain. MM declares ~17 actions
this way today (substrate_summary, learning_propose_next,
quick_note, backlog_curate, profile_evolve, actor_curate,
journey_curate, flow_curate, etc.). MM relies on:

- `action(name)` accepting a string + returning a builder.
- `.describe(string)` setting the agent-visible description.
- `.input_schema(hash)` accepting a JSON-Schema-shaped hash for
  parameter validation.
- `.annotate(read_only:, destructive:, requires_confirmation:)`
  recording action-side hints surfaced to the agent. MM's
  `Harness::Mcb::ActorGate` reads these annotations.
- `.handler { |input, ctx| … }` accepting a 2-arity block; the
  `ctx` object the block receives MUST respond to `progress`,
  `confirm`, `elicit`, `sample`. The substrate's `ctx.sample`
  doctrine (see `docs/architecture/principles/model-context-injection.md`)
  depends on `sample` being available.

### `::Vv::Mcb::Protocol::Action#domain`

Added per `magentic-market-ai/docs/plans/PLAN_0_93_0.md` (Phase A). The
`WebmcpBridge` composes WebMCP tool names as `mm.<domain>.<action>`, so
every MM action declaration tags a domain:

```ruby
app.action("substrate_summary")
  .domain("summary")
  .describe(...).input_schema(...).handler { … }
```

MM relies on:

- `.domain(value)` accepting a String or Symbol, coercing via `#to_s`,
  and returning the builder for chaining.
- `.domain` (no arg) returning the stored domain string (or nil if unset).
- `WebmcpBridge::McbAdapter` reading `#domain` directly off the Action.
- A domain being set before the bridge mounts — the bridge raises
  `WebmcpBridge::MissingDomain` otherwise.

### `::Vv::Mcb::Server::App#actions`

Iterable surface added per PLAN_0_93_0 (Phase A). Returns the registered
Action builders in declaration order so the WebMCP adapter can enumerate
them:

```ruby
app.actions.each { |a| ... }  # => Array<Vv::Mcb::Protocol::Action>
```

MM relies on:

- `App#actions` returning an Array (or any Enumerable) of `Protocol::Action`.
- Declaration order being preserved so the tool catalogue is stable.

### `::Vv::Mcb::Gateway::WebmcpBridge`

Added per PLAN_0_93_0 Phase A; **reshaped per `magentic-market-ai`
PLAN_0_94_0 Phase C** (static bridge + post-handshake tools). Aggregates
one or more registry adapters into the merged, normalised tool catalogue
(`#collect_tools`). The per-session JS bridge is **no longer server
rendered** — the transport clients + the registration loop ship in the
application's STATIC bundle (`webmcp/js/bridge.js`, exporting
`bootWebmcp`), and the session-bound tool list arrives **post-handshake**
over the authed carriage (MM's platform `GET /mcb/tools` endpoint serves
`#collect_tools`). MM constructs the bridge in `Harness::Mcb::WebmcpMount`:

```ruby
bridge = ::Vv::Mcb::Gateway::WebmcpBridge.new(adapters: [
  ::Vv::Mcb::Gateway::WebmcpBridge::McbAdapter.new(
    app: McpApp.instance, websocket_url: McpApp.websocket_url_for(session),
    token: handshake_token, origin: platform_origin
  ),
  ::Vv::Visualize::Wamp::Procedures::WebmcpAdapter.new(
    base: platform_origin, token: handshake_token, origin: platform_origin
  )
])

# app body (the authed layout) — STATIC-bridge boot snippet, no inlined tools:
bridge.render_boot_snippet(platform_origin: platform_origin)
# post-handshake (GET /mcb/tools) — the session-bound tool catalogue:
bridge.collect_tools
```

MM relies on:

- `WebmcpBridge.new(adapters:)` accepting an Array of adapter objects,
  each responding to `each_tool` yielding hashes shaped
  `{domain, action, description, input_schema, annotations, transport_descriptor}`.
- `#collect_tools` returning the merged, normalised `Array<Hash>` of
  `mm.<domain>.<action>` entries (each with a `transport` descriptor
  carrying url + token + origin). This is the **post-handshake** delivery
  surface — MM's `GET /mcb/tools` returns it as JSON.
- `#render_boot_snippet(platform_origin:, asset_path: "/js/webmcp-bridge.js")`
  returning a tiny `<script type="module">` that imports + calls
  `bootWebmcp({ platformOrigin })` — inline-safe in the layout `<head>`,
  carrying **NO** `tools_json` / `session_id` (those arrive post-handshake).
- Tool-name normalisation to `mm.<domain>.<action>`. Collisions raise
  `WebmcpBridge::NameCollision`.
- The STATIC bridge (`webmcp/js/bridge.js`) exposing the global
  `window.__vvMcbWebmcp = { controller, tools, transports, sessionId }`
  after `bootWebmcp` resolves (or `{ unavailable: true, ... }` on a missing
  WebMCP / failed handshake), so MM's `vv-visualize--local-agent`
  controller (PLAN_0_93_0 Phase C) can read the same registry without
  re-deriving it. MM serves the static module from `server/public/js/
  webmcp-bridge.js` (a copy of the gem's `webmcp/js/bridge.js`).
- `WebmcpBridge::McbAdapter.new(app:, websocket_url:, token:, origin:)`
  wrapping a running `Server::App` and emitting `transport_descriptor:
  { kind: "mcb_ws", url:, method: "action.invoke"[, token:, origin:] }`
  per action.

The bridge is browser-side: it emits the boot snippet + the tool
catalogue, it does not invoke actions server-side. Invocations from the
static bundle round-trip back through the existing WebSocket transport
`App` already serves (i.e. through the same path the existing `McpBridge`
uses on the other side).

> **Retired:** `#render_bridge_js(session_id:)` (the ERB server render that
> inlined `tools_json` + `session_id`) was removed in PLAN_0_94_0 Phase C.
> Consumers must boot the static bridge (`render_boot_snippet`) and serve the
> tool list post-handshake (`collect_tools` via `GET /mcb/tools`).

### `ctx` callback surface (from inside handlers)

| Method | MM uses |
|---|---|
| `ctx.progress(message:, percent: nil, data: nil)` | yes — every long-running action |
| `ctx.confirm(question:)` | yes — `ActorGate`'s approval-required path |
| `ctx.elicit(message:, schema: nil)` | yes — operator-input prompts |
| `ctx.sample(messages:, system_prompt: nil, max_tokens: nil)` | yes — substrate_summary + learning_propose_next + future actions; load-bearing for the no-LLM-credentials-substrate-side principle |

MM relies on each call returning a value the substrate can pattern-
match on (string for `sample`; boolean for `confirm`; arbitrary
hash for `elicit`; nothing for `progress`). The `ctx.sample`
return-shape variance is what `Mm::LlmMock::ExtractText` decodes
(see `server/lib/mm/llm_mock.rb`).

## What would break MM if it changed

- **Removing or renaming `Server::App`** — substrate's app.rb
  imports it by fully-qualified constant.
- **Changing `action(...).describe().input_schema().annotate().handler()`
  fluent shape** — ~17 callsites would need lockstep updates.
- **Removing `ctx.sample`** — the entire `substrate_summary` +
  `learning_propose_next` flow depends on it; per
  `model-context-injection.md`, this is the substrate's only
  sanctioned LLM-dispatch primitive.
- **Changing `annotate` keyword args** (`read_only:`,
  `destructive:`, `requires_confirmation:`) — `ActorGate`'s gate
  decision reads these by exact name.
- **Tightening `id:` parameter validation** to reject
  reverse-DNS-shaped strings — MM's `ai.magenticmarket.substrate`
  identifier wouldn't pass.
- **Removing `WebmcpBridge` or changing its `adapters:` array contract**
  — `Harness::Mcb::WebmcpMount` constructs it by exact shape.
- **Removing `#collect_tools` or changing its `Array<Hash>` shape** — MM's
  `GET /mcb/tools` (PLAN_0_94_0 Phase C) serves it as the post-handshake
  tool catalogue.
- **Removing `#render_boot_snippet` or changing its signature
  (`platform_origin:`, `asset_path:`)** — `WebmcpMount#render_for` emits the
  app body's WebMCP boot from it.
- **Changing `bootWebmcp`'s boot contract** (`POST /api/v1/web_sessions` →
  `GET /mcb/tools?token=&origin=`, or the `window.__vvMcbWebmcp` shape it
  assigns) — MM's static bundle + the `vv-visualize--local-agent` controller
  depend on it.
- **Removing `Action#domain` or changing it to require a non-string
  value** — every MM action declaration uses string domains; the
  bridge's name-composition would break and `MissingDomain` would
  raise on render.
- **Changing the `__vvMcbWebmcp` window-global shape**
  (`{controller, tools, transports, sessionId}`) — the
  `vv-visualize--local-agent` controller reads `transports` and `tools` to
  drive the Prompt API path.
- **Removing `App#actions`** — `WebmcpBridge::McbAdapter` iterates it.

## What MM tolerates

- Adding new `ctx.*` callback methods (MM ignores them).
- Adding new fluent builder methods on `action()` (MM ignores
  them unless they appear on a documented callsite).
- Internal refactors to the WebSocket transport layer —
  MM doesn't observe transport details.
- Performance improvements — neutral.
- New MCP-bridge gateways targeting other clients (Claude Code,
  Cursor) — MM's app-side surface is unchanged.
- Bumping the gem's own minor + patch versions when the surfaces
  above don't change.

## See also

- `vendor/vv-mcb/README.md` — the gem's own contract.
- `docs/architecture/principles/model-context-injection.md` —
  the substrate doctrine this gem implements one side of.
- `docs/architecture/principles/tesseron.md` — the **retired**
  doctrine page (preserved as historical record; do not write
  new code against this framing).
- `server/packs/platform/app/services/harness/mcb/` — every
  MM consumer of this gem lives under that path.

## Last reviewed

2026-05-29 against MM substrate per `docs/plans/PLAN_0_94_0.md` (Phase C — static
bridge + post-handshake tools; `render_bridge_js` retired → `render_boot_snippet`).
