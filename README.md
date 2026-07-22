# send-email-skill

An Agent Skill for sending plain-text email through macOS `/usr/bin/mail` and verifying local Postfix queue state.

## Install

```bash
npx skills add jeffliu05042/send-email-skill@send-email -g -y
```

For a manual Codex installation:

```bash
git clone https://github.com/jeffliu05042/send-email-skill.git
mkdir -p ~/.codex/skills
cp -R send-email-skill/skills/send-email ~/.codex/skills/
```

## Use

Ask your agent to use `$send-email`, for example:

```text
Use $send-email to send the release report to person@example.com.
```

The skill requires explicit user authorization before sending. It validates a single recipient, subject, and non-empty plain-text body; invokes `/usr/bin/mail`; waits for on-demand Postfix startup; and reports success only when the local queue is empty.

## Requirements

- macOS with `/usr/bin/mail` and `/usr/bin/mailq`
- A working local Postfix configuration capable of external delivery

This skill intentionally does not support HTML or attachments. An empty local queue confirms local handoff, not recipient receipt.

## Validate Without Sending

```bash
printf '%s\n' 'Test body' | \
  skills/send-email/scripts/send_email.sh \
  --to 'person@example.com' \
  --subject 'Dry run' \
  --dry-run
```

## License

MIT
