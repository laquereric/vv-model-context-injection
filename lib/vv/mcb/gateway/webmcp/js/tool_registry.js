// Prompt-API consumer of the in-page tool registry.
// Per PLAN_0_93_0 C.1: one registry, two consumers. The bridge
// (bridge.js.erb) already registered every tool with
// `navigator.modelContext` — the first consumer. This is the second:
// it maps the same `window.__vvMcbWebmcp` registry to the shape
// `LanguageModel.create({ tools })` expects, sharing one transport
// dispatch so the throttle applies uniformly across both consumers.
export function registryForPromptApi() {
  const reg = window.__vvMcbWebmcp;
  if (!reg || reg.unavailable || !Array.isArray(reg.tools)) return [];

  return reg.tools.map((t) => ({
    name:        t.name,
    description: t.description,
    parameters:  t.inputSchema,
    execute: (args) => {
      const client = reg.transports[t.transport.kind];
      if (!client) throw new Error(`no transport client for kind: ${t.transport.kind}`);
      return client.invoke(t, args);
    }
  }));
}
