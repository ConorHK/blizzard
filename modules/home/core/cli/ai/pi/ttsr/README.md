# pi TTSR and /omfg

Time Traveling Stream Rules, ported from [oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).

`/omfg <complaint>` asks the session model to write a rule that would have caught the
complaint earlier in this conversation. It checks the rule against the conversation, shows
it, and saves it to `.pi/rules/` (project) or `~/.pi/agent/rules/` (global). `/ttsr` lists
loaded rules.

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
`disabledRules`. Project rules load only in trusted projects.
