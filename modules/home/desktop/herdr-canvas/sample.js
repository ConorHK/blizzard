// A sample canvas: one block of each kind, as pi's show_ui tool would send it.
export const SAMPLE = {
  title: "Sample: nightly upgrade",
  updated: new Date(Date.now() - 4 * 60000).toISOString(),
  blocks: [
    { type: "heading", text: "3 of 5 hosts upgraded" },
    {
      type: "stats",
      items: [
        { label: "failed", value: "1", tone: "bad" },
        { label: "waiting", value: "1", tone: "warn" },
        { label: "switching", value: "1", tone: "info" },
        { label: "done", value: "2", tone: "good" },
      ],
    },
    { type: "progress", label: "Hosts on the new generation", value: 0.6 },
    {
      type: "table",
      columns: ["Host", "Role", "State"],
      rows: [
        ["leprechaun", "server", "failed"],
        ["puca", "server", "switching"],
        ["sluagh", "server", "waiting on a reboot"],
      ],
    },
    {
      type: "list",
      items: [
        { text: "leprechaun", detail: "nginx failed to start after the switch", tone: "bad" },
        { text: "sluagh", detail: "kernel update needs a reboot", tone: "warn" },
        { text: "Upgrade logs", detail: "github.com", link: "https://github.com/ConorHK/blizzard/actions", tone: "info" },
      ],
    },
    {
      type: "markdown",
      text: "**Cause so far.** nginx exits on a missing certificate after the switch. The same generation passed on bananach, so the change looks *host specific*.",
    },
    { type: "code", language: "bash", text: "hc read t14 --lines 40\npi --session ~/.pi/agent/sessions/..." },
    {
      type: "buttons",
      items: [
        { label: "Roll back leprechaun", send: "Roll leprechaun back to its last generation.", tone: "good" },
        { label: "Dig into nginx", send: "Investigate why nginx failed on leprechaun.", tone: "info" },
        { label: "Open logs", link: "https://github.com/ConorHK/blizzard/actions" },
      ],
    },
  ],
};
