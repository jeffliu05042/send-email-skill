# send-email-skill

[English](README.md) | [简体中文](README.zh-CN.md)

An Agent Skill that sends plain-text email through either macOS `/usr/bin/mail` or an explicitly selected authenticated SMTP service. It safely handles non-ASCII subjects and verifies remote SMTP acceptance.

## Features

- Supports direct local Postfix delivery and authenticated SMTP over SSL or STARTTLS.
- Reads SMTP app passwords from macOS Keychain or the process environment; it never stores them in the repository.
- Validates one recipient, the subject, and a non-empty message body before sending.
- Encodes non-ASCII subjects with RFC 2047 so servers without `SMTPUTF8` can accept them.
- Requires explicit user authorization and sends each requested message only once.
- Supports body content from standard input or a plain-text file.
- Provides `--dry-run` validation without sending a message.
- Returns deterministic markers for configuration, authentication, local acceptance, remote SMTP acceptance or rejection, and queue status.

## Requirements

- A Unix-like shell and `/usr/bin/python3`
- For the default `local` transport: macOS with `/usr/bin/mail`, `/usr/bin/mailq`, `/usr/bin/log`, and working Postfix delivery
- For the `smtp` transport: provider SMTP settings and an app password; macOS Keychain is recommended
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

The agent should review the recipient, subject, body, and transport, then run the bundled script only after the user has authorized delivery. It must not automatically switch transports or retry an uncertain result.

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

To use authenticated SMTP, configure the variables described in [`skills/send-email/references/smtp.md`](skills/send-email/references/smtp.md), then select it explicitly:

```bash
printf '%s\n' 'Test body' | \
  skills/send-email/scripts/send_email.sh \
  --transport smtp \
  --to 'person@example.com' \
  --subject 'Authenticated SMTP test' \
  --dry-run
```

## Result Contract

| Marker | Meaning |
| --- | --- |
| `DRY_RUN_OK` | Inputs passed validation; no email was sent. |
| `SUBJECT_HEADER_READY` | The subject is ASCII or has been RFC 2047 encoded. |
| `SMTP_CONFIG_READY` | Authenticated SMTP configuration and MIME construction passed validation. |
| `SMTP_AUTHENTICATED` | The configured SMTP service accepted the login. |
| `LOCAL_MAIL_ACCEPTED` | `/usr/bin/mail` accepted the message locally. |
| `REMOTE_SMTP_ACCEPTED` | The receiving SMTP server accepted the message. |
| `REMOTE_SMTP_REJECTED` | The receiving SMTP server rejected the message. |
| `REMOTE_DELIVERY_DEFERRED` | Postfix deferred the delivery for a later retry. |
| `REMOTE_DELIVERY_UNCONFIRMED` | No terminal remote status appeared during the verification window. |
| `QUEUE_EMPTY` | No message remains in the local Postfix queue. |
| `LOCAL_MAIL_REJECTED` | The local mail command rejected the message. |
| `QUEUE_STATUS_UNAVAILABLE_AFTER_DELIVERY` | Remote acceptance was confirmed, but the stopped on-demand Postfix service could not report the global queue. |

A successful send requires exit code `0` plus `REMOTE_SMTP_ACCEPTED`. This confirms acceptance by the receiving SMTP server, not that the recipient has read the message.

## Safety and Limitations

- Do not include passwords, API keys, private keys, or unrelated local data.
- An uncertain or failed result must be investigated before retrying to avoid duplicate email.
- Only one recipient and a plain-text body are supported.
- HTML, CC, BCC, and attachments are intentionally outside the current scope.
- Deliverability and inbox placement still depend on the selected relay, DNS, sender configuration, and recipient-side filtering.
- Use an app password, preferably stored in macOS Keychain; never commit or print credentials.

## Project Structure

```text
skills/send-email/
├── SKILL.md
├── agents/openai.yaml
├── references/smtp.md
└── scripts/
    ├── send_email.sh
    └── smtp_send.py
tests/
├── fixtures/
├── test_send_email.sh
└── test_smtp_send.py
```

## License

[MIT](LICENSE)
