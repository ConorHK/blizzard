# pi TTSR and /omfg

Time Traveling Stream Rules, ported from [oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).

`/omfg <complaint>` asks the session model to write a rule that would have caught the
complaint earlier in this conversation. It checks the rule against the conversation, shows
it, and saves it to the project's `.pi/rules/` or to the global rules source. `/ttsr` lists
loaded rules.

Global rules are declarative. `programs.pi.ttsr.ruleDirs` lists rule directories: blizzard's
`ttsr-rules/` comes first, and a consumer flake appends its own, which wins by file name.
`programs.pi.ttsr.rules.<name>` wins over both. Home Manager links the result into
`~/.pi/agent/rules/`. `/omfg` saves global rules into `programs.pi.ttsr.rulesSource`, a
checkout path, so a new rule works in new sessions at once and deploys after you commit and
rebuild.

Load order, first name wins: project `.pi/rules/` (trusted projects only), `rulesSource`,
then `~/.pi/agent/rules/`.

A rule is markdown with frontmatter; the body is the guidance injected on a match.

| Trigger | Checked | On match |
|---|---|---|
| `condition` (regex) on `text`/`thinking` | while the reply streams | reply cut off, dropped from context, retried with the rule |
| `condition` or `astCondition` on tools | before the call runs | call blocked; the model gets the rule as the error |
| `question` | by a judge after the output | warning injected, model continues |

`scope` narrows where a rule looks: `text`, `thinking`, `tool`, `tool:<name>`, or
`tool:<name>(<glob>)`. `edit`/`write` calls are checked as the source text they write,
other tools as JSON arguments. `astCondition` uses the nixpkgs `ast-grep` and needs a
file extension in the scope glob.

Settings live in `~/.pi/agent/ttsr.json` (`programs.pi.ttsr.settings`): `enabled`,
`judge` (`auto`/`off`), `judgeModel` (`provider/id`, a chat or classifier model; default is
the session model), `contextMode`, `interruptMode`, `repeatMode`, `repeatGap`,
`disabledRules`, `rulesSource`.
