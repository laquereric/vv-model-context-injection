# Consumer requirements — MagenticMarket substrate

This file records the surface
[MagenticMarket](https://github.com/laquereric/magentic-market-ai)
(the substrate; "MM" hereafter) consumes from `tesseron-ruby`.
It exists so upstream changes can be checked against a written
consumer expectation — **drift** between this file and the gem's
actual behaviour signals work that needs to land in both repos
lockstep.

- MM repo: <https://github.com/laquereric/magentic-market-ai>
- MM plan that introduced this dependency: `docs/plans/PLAN_0_27_5j.md`
  (Tesseron Ruby SDK as a substrate submodule)
- MM plan that solidified the CR discipline: `docs/plans/PLAN_0_81_0.md`
  (this file is the Phase D backfill against tesseron-ruby)
- Sibling consumers (if any): none registered

> **Status note.** Locked-in for the Alpha distribution. The
> substrate is the gem's primary consumer; the gem's surface
> evolves through MM PR-pairs (gem repo + substrate). The
> upstream's own roadmap lives at
> `vendor/tesseron-ruby/docs/plans/` (per "gems do their own
> planning"); MM declares what it currently exercises, no more.

## How MM pins this gem

```ruby
# server/Gemfile — local development (submodule checkout)
gem "tesseron-ruby", path: "../vendor/tesseron-ruby"

# server/Gemfile — CI / production (pinned SHA, when path moves to git)
# gem "tesseron-ruby", git: "https://github.com/laquereric/tesseron-ruby",
#                     ref: "<sha>"
```

`vendor/tesseron-ruby` is a tracked git submodule; the
substrate's `Gemfile.lock` records the resolved version. CI
clones submodules by default (`actions/checkout` with
`submodules: 'true'`).

## Surfaces MM consumes

The substrate's actual import surface is *narrower than the
gem's full API*. MM uses:

### `::Tesseron::Ruby::Server::App`

The app-side Rack application class. Constructed once at boot in
`server/packs/platform/app/services/harness/tesseron/app.rb`:

```ruby
app = ::Tesseron::Ruby::Server::App.new(
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
  `Harness::Tesseron::ActorGate` reads these annotations.
- `.handler { |input, ctx| … }` accepting a 2-arity block; the
  `ctx` object the block receives MUST respond to `progress`,
  `confirm`, `elicit`, `sample`. The substrate's `ctx.sample`
  doctrine (see `docs/architecture/principles/tesseron.md`)
  depends on `sample` being available.

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
  `tesseron.md`, this is the substrate's only sanctioned LLM-
  dispatch primitive.
- **Changing `annotate` keyword args** (`read_only:`,
  `destructive:`, `requires_confirmation:`) — `ActorGate`'s gate
  decision reads these by exact name.
- **Tightening `id:` parameter validation** to reject
  reverse-DNS-shaped strings — MM's `ai.magenticmarket.substrate`
  identifier wouldn't pass.

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

- `vendor/tesseron-ruby/README.md` — the gem's own contract.
- `docs/architecture/principles/tesseron.md` — the substrate
  doctrine this gem implements one side of.
- `server/packs/platform/app/services/harness/tesseron/` — every
  MM consumer of this gem lives under that path.
