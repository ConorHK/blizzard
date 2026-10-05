# pi checkpoint and rewind

Ported from [oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT); see its
`docs/tools/checkpoint.md` and `docs/tools/rewind.md`.

`checkpoint(goal)` marks the start of an investigation. `rewind(report)` ends it: every
assistant turn, tool result, and injected message after the checkpoint is dropped from the
model's context with `context_edit` entries, and the report takes their place. User
messages stay. The session file keeps everything; only what the model sees changes, and
that survives resume.

If the agent tries to stop with a checkpoint open, it is told to rewind first, at most
twice per run. One checkpoint at a time. Subagent children do not get the tools. The
advisor resets after a rewind.
