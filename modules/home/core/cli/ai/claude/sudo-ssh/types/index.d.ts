export type Prompt = { host: string; command: string; length: number }

declare module 'claude-code' {
  interface PluginState {
    'sudo-ssh': { prompt: Prompt | null }
  }
}
