# send-email-skill

[English](README.md) | [简体中文](README.zh-CN.md)

An Agent Skill that sends plain-text email through macOS `/usr/bin/mail` and verifies local Postfix queue state.

## Features

- Uses the mail transport already configured on the machine; no additional SMTP credentials are stored by the skill.
- Validates one recipient, the subject, and a non-empty message body before sending.
- Requires explicit user authorization and sends each requested message only once.
- Supports body content from standard input or a plain-text file.
- Provides `--dry-run` validation without sending a message.
- Returns deterministic markers for local acceptance and queue status.

## Requirements

- macOS with `/usr/bin/mail` and `/usr/bin/mailq`
- A working local Postfix configuration capable of external delivery
- An Agent Skills-compatible client such as Codex

## Install

Install with the Skills CLI:

```bash
npx skills add jeffliu05042/send-email-skill@send-email -g -y
```

Or install manually for Codex:

```bash
git clone https://github.com/jeffliu05042/send-email-skill.git
mkdir -p ~/.codex/skills
cp -R send-email-skill/skills/send-email ~/.codex/skills/
```

Restart the client or begin a new task if it does not immediately discover the skill.

## Use with an Agent

Invoke the skill explicitly and provide the recipient and purpose:

```text
Use $send-email to send the release report to person@example.com.
```

The agent should review the recipient, subject, and body, then run the bundled script only after the user has authorized delivery.

## Use the Script Directly

Pipe the body through standard input:

```bash
printf '%s\n' 'The release is complete.' | \
  skills/send-email/scripts/send_email.sh \
  --to 'person@example.com' \
  --subject 'Release completed'
```

Or read the body from a file:

```bash
skills/send-email/scripts/send_email.sh \
  --to 'person@example.com' \
  --subject 'Release report' \
  --body-file '/absolute/path/report.txt'
```

Validate without sending:

```bash
printf '%s\n' 'Test body' | \
  skills/send-email/scripts/send_email.sh \
  --to 'person@example.com' \
  --subject 'Dry run' \
  --dry-run
```

## Result Contract

| Marker | Meaning |
| --- | --- |
| `DRY_RUN_OK` | Inputs passed validation; no email was sent. |
| `LOCAL_MAIL_ACCEPTED` | `/usr/bin/mail` accepted the message locally. |
| `QUEUE_EMPTY` | No message remains in the local Postfix queue. |
| `LOCAL_MAIL_REJECTED` | The local mail command rejected the message. |
| `QUEUE_STATUS_UNCONFIRMED` | The script could not confirm an empty queue within five seconds. |

A successful send requires exit code `0` plus both `LOCAL_MAIL_ACCEPTED` and `QUEUE_EMPTY`. These signals confirm local submission, not that the recipient has read or received the message.

## Safety and Limitations

- Do not include passwords, API keys, private keys, or unrelated local data.
- An uncertain or failed result must be investigated before retrying to avoid duplicate email.
- Only one recipient and a plain-text body are supported.
- HTML, CC, BCC, and attachments are intentionally outside the current scope.
- Deliverability still depends on the machine's Postfix relay, DNS, and sender configuration.

## Project Structure

```text
skills/send-email/
├── SKILL.md
├── agents/openai.yaml
└── scripts/send_email.sh
```

## License

[MIT](LICENSE)
