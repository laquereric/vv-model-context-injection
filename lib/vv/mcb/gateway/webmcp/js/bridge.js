// Vv::Mcb::Gateway::WebmcpBridge — STATIC bridge (PLAN_0_94_0 Phase C).
//
// This file is a plain ES module that ships in the application's STATIC
// bundle (no ERB, no server render). It carries the transport clients
// (`McbWsClient` / `WampRpcClient`) + the registration loop, but the
// session-bound tool list is NO LONGER inlined: `bootWebmcp` mints a
// handshake client-side, FETCHES the tools post-handshake from the
// platform, then registers them with `navigator.modelContext`.
//
// Boot sequence (per `bootWebmcp({ platformOrigin, origin })`):
//   1. POST  ${platformOrigin}/api/v1/web_sessions  { origin }
//        credentials: "include"  ->  { handshake_token, ... }
//   2. GET   ${platformOrigin}/mcb/tools?token=<ht>&origin=<origin>
//        ->  { session_id, tools: [...] }   (tools carry transport
//            url + token + origin — the Phase B authed descriptor)
//   3. build transports from each tool's `transport` descriptor
//   4. navigator.modelContext.registerTool per tool
//   5. window.__vvMcbWebmcp = { tools, transports, controller, sessionId }
//
// Self-no-ops when WebMCP is unavailable, and degrades gracefully (no
// throw) when the mint / tools fetch fails — setting
// window.__vvMcbWebmcp = { unavailable: true, ... } so downstream
// consumers (tool_registry.js) stay safe.

// --- Transports -------------------------------------------------------------

export class McbWsClient {
  constructor(url, sessionId) {
    this.url       = url
    this.sessionId = sessionId
    this.ws        = new WebSocket(url)
    this.nextId    = 1
    this.pending   = new Map()
    this.ready     = new Promise((res) => { this.ws.addEventListener("open", res) })
    this.ws.addEventListener("message", (e) => this._onMessage(e))
  }
  async invoke(tool, args) {
    await this.ready
    const id = this.nextId++
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject })
      this.ws.send(JSON.stringify({
        jsonrpc: "2.0",
        id,
        method: tool.transport.method,
        params: { name: tool.name, args, sessionId: this.sessionId }
      }))
    })
  }
  _onMessage(e) {
    let msg; try { msg = JSON.parse(e.data) } catch { return }
    const slot = this.pending.get(msg.id)
    if (!slot) return
    this.pending.delete(msg.id)
    msg.error ? slot.reject(msg.error) : slot.resolve(msg.result)
  }
}

export class WampRpcClient {
  async invoke(tool, args) {
    const res = await fetch(tool.transport.url, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body:    JSON.stringify({ args: [], kwargs: args })
    })
    const body = await res.json()
    if (body.type === "ERROR") throw body
    return body.kwargs ?? body.result ?? body
  }
}

// --- Boot -------------------------------------------------------------------

// Mint a handshake, fetch the session-bound tool registry, build transports,
// and register every tool. `platformOrigin` is the absolute platform base
// (e.g. "https://platform.example"); `origin` is the app origin pinned into
// the handshake (defaults to the running page's origin).
//
// Returns the `window.__vvMcbWebmcp` registry object it also assigns.
export async function bootWebmcp({ platformOrigin, origin } = {}) {
  const appOrigin = origin || (typeof location !== "undefined" ? location.origin : "")

  // WebMCP capability gate — polyfill absent and not Chrome 149+. Nothing to
  // register against, so we no-op (matches the pre-Phase-C guard).
  if (!("modelContext" in navigator)) {
    window.__vvMcbWebmcp = { tools: [], transports: {}, controller: null, unavailable: true }
    return window.__vvMcbWebmcp
  }

  // 1 + 2 — mint a handshake, then fetch the session-bound tool list. Both
  // legs degrade gracefully: a non-OK response (or a thrown fetch) sets the
  // unavailable registry rather than crashing the page.
  let sessionId = null
  let tools = []
  try {
    const mintRes = await fetch(`${platformOrigin}/api/v1/web_sessions`, {
      method:      "POST",
      headers:     { "Content-Type": "application/json" },
      credentials: "include",
      body:        JSON.stringify({ origin: appOrigin })
    })
    if (!mintRes.ok) {
      window.__vvMcbWebmcp = { tools: [], transports: {}, controller: null, unavailable: true, because: `mint failed: ${mintRes.status}` }
      return window.__vvMcbWebmcp
    }
    const { handshake_token: handshakeToken } = await mintRes.json()

    const toolsUrl = `${platformOrigin}/mcb/tools?token=${encodeURIComponent(handshakeToken)}&origin=${encodeURIComponent(appOrigin)}`
    const toolsRes = await fetch(toolsUrl, { credentials: "include" })
    if (!toolsRes.ok) {
      window.__vvMcbWebmcp = { tools: [], transports: {}, controller: null, unavailable: true, because: `tools fetch failed: ${toolsRes.status}` }
      return window.__vvMcbWebmcp
    }
    const payload = await toolsRes.json()
    sessionId = payload.session_id
    tools = Array.isArray(payload.tools) ? payload.tools : []
  } catch (err) {
    window.__vvMcbWebmcp = { tools: [], transports: {}, controller: null, unavailable: true, because: `handshake error: ${err}` }
    return window.__vvMcbWebmcp
  }

  // 3 — build transports from the descriptors the tools already carry
  // (each transport descriptor is absolute + token + origin per Phase A/B).
  const mcbWsUrl = tools.find((t) => t.transport.kind === "mcb_ws")?.transport?.url
  const transports = {
    mcb_ws:   mcbWsUrl ? new McbWsClient(mcbWsUrl, sessionId) : null,
    wamp_rpc: new WampRpcClient()
  }

  // 4 — register one tool per entry, scoped to an AbortController signal.
  const controller = new AbortController()
  for (const t of tools) {
    navigator.modelContext.registerTool({
      name:        t.name,
      description: t.description,
      inputSchema: t.inputSchema,
      annotations: t.annotations,
      execute: async (args) => {
        const client = transports[t.transport.kind]
        if (!client) throw new Error(`no transport client for kind: ${t.transport.kind}`)
        const result = await client.invoke(t, args)
        return { content: [{ type: "text", text: JSON.stringify(result) }] }
      }
    }, { signal: controller.signal })
  }

  // 5 — expose the registry for downstream consumers (tool_registry.js).
  window.__vvMcbWebmcp = { tools, transports, controller, sessionId }
  return window.__vvMcbWebmcp
}
