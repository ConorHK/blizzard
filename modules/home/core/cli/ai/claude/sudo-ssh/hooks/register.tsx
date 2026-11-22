import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Prompt } from '../types'

const PANE = 'sudo-password'
const TOOL = 'mcp__sudo-ssh__sudo_ssh'

const prompt = atom({ plugin: 'sudo-ssh', key: 'prompt' } as const, null)

// Passwords live in module memory only, never in $.state or messages.
const cache = new Map<string, string>()
let typed = ''
let settle: ((password: string | null) => void) | undefined

type Input = { host: string; command: string; user?: string; timeoutSec?: number }

function shQuote(text: string): string {
  return `'${text.replaceAll("'", "'\\''")}'`
}

function sudoWrap(command: string, user?: string): string {
  const flag = user ? ` -u ${shQuote(user)}` : ''
  return `sudo -S -p ''${flag} -- bash -c ${shQuote(command)}`
}

function scrub(text: string, secret: string | undefined): string {
  return secret ? text.split(secret).join('********') : text
}

function finish(password: string | null) {
  const done = settle
  settle = undefined
  typed = ''
  done?.(password)
}

async function askPassword($: EngineInterface, host: string, command: string): Promise<string | null> {
  finish(null)
  await update($, prompt, () => ({ host, command, length: 0 }) satisfies Prompt)
  const answer = new Promise<string | null>(resolve => (settle = resolve))
  const opened = await $.ui.open({
    id: PANE,
    title: `sudo password: ${host}`,
    focus: true,
    closeOnEscape: true,
    rows: 7,
  })
  if (!opened.isPlaced) finish(null)
  const password = await answer
  await update($, prompt, () => null)
  await $.ui.close({ id: PANE })
  return password
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.tool.register({
      name: 'sudo_ssh',
      description:
        'Run a command as root on a remote host over ssh. The user types the sudo password into a hidden dialog; the password never enters the conversation. It is cached per host for the session; later calls ask for confirmation. A wrong password clears the cache. Never ask the user to type a password into chat.',
      inputSchema: {
        type: 'object',
        properties: {
          host: { type: 'string', description: 'ssh destination, e.g. leprechaun' },
          command: { type: 'string', description: 'shell command run under sudo on the host' },
          user: { type: 'string', description: 'run as this user instead of root' },
          timeoutSec: { type: 'number', description: 'kill after N seconds, default 120' },
        },
        required: ['host', 'command'],
      },
      isDeferred: false,
    })
    await $.command.register({
      name: 'sudopw',
      description: 'Cache or clear a sudo password',
      argumentHint: '<host> | forget',
    })
    return next(e)
  })

  on('ui.close', async ($, e, next) => {
    if (e.id === PANE) finish(null)
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Input } = $.ui.resolve(e)
    const p = await read($, prompt)
    if (!p) return <Text dimColor>No password asked.</Text>
    return (
      <Box flexDirection="column">
        <Text dimColor>runs: {p.command.slice(0, 200)}</Text>
        <Input
          key="password"
          label="password: "
          value={'*'.repeat(p.length)}
          submitLabel="run"
          autoFocus
          onInput={value => {
            // The field shows asterisks, so only its tail past them is new.
            typed = value.length > typed.length ? typed + value.slice(typed.length) : typed.slice(0, value.length)
            void update($, prompt, cur => (cur ? { ...cur, length: typed.length } : cur))
          }}
          onSubmit={value => {
            if (value.length > typed.length) typed += value.slice(typed.length)
            finish(typed)
          }}
        />
        <Text dimColor>Enter runs, Esc cancels</Text>
      </Box>
    )
  })

  on('tool.call', { tool: TOOL }, async ($, e) => {
    const { host, command, user, timeoutSec } = e as unknown as Input
    const timeoutMs = Math.min(600, Math.max(1, timeoutSec ?? 120)) * 1000
    const ssh = ['ssh', '-o', 'ConnectTimeout=10', host]

    const probe = await $.process
      .run([...ssh, '-o', 'BatchMode=yes', 'sudo -n true'], { timeoutMs: 30_000 })
      .catch(() => ({ exitCode: 1 }))
    let password: string | undefined
    if (probe.exitCode !== 0) {
      const cached = cache.get(host)
      if (cached === undefined) {
        const given = await askPassword($, host, command)
        if (given === null) return { deny: 'User declined the password prompt.' }
        cache.set(host, given)
        password = given
      } else {
        const pick = await $.ui.ask(`Run as root on ${host}: ${command.slice(0, 300)}?`, ['Run', 'Cancel']).catch(() => 'Cancel')
        if (pick !== 'Run') return { deny: 'User declined the command.' }
        password = cached
      }
    }

    let out: string
    let code: number | string
    try {
      const r = await $.process.run([...ssh, sudoWrap(command, user)], {
        stdin: password === undefined ? undefined : `${password}\n`,
        timeoutMs,
      })
      out = r.stdout + r.stderr
      code = r.exitCode
    } catch (err) {
      out = String(err)
      code = 'timed out or failed to start'
    }
    const text = scrub(out, password)
    const authFailure = password !== undefined && /incorrect password attempt|authentication failure/i.test(text)
    if (authFailure) cache.delete(host)
    const body = text.length > 20000 ? `${text.slice(0, 10000)}\n...truncated...\n${text.slice(-9000)}` : text
    const head = [`host: ${host}`, `exit: ${code}`, authFailure ? 'wrong password; cache cleared' : null]
      .filter(Boolean)
      .join(', ')
    const result = `${head}\n${body}`
    return code === 0 ? { result } : { isError: true as const, result, text: result }
  })

  on('command.run', { command: 'sudopw' }, async ($, e) => {
    const arg = e.args.trim()
    if (arg === 'forget') {
      cache.clear()
      return { text: 'Passwords cleared.' }
    }
    if (!arg) return { text: 'Usage: /sudopw <host> or /sudopw forget' }
    const given = await askPassword($, arg, 'cached for later sudo_ssh calls')
    if (given === null) return { text: 'Cancelled.' }
    cache.set(arg, given)
    return { text: `Password cached for ${arg}.` }
  })

  on('session.end', async ($, e, next) => {
    cache.clear()
    return next(e)
  })
}
