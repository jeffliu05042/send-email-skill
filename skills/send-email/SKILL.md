---
name: send-email
description: Send plain-text email through either macOS /usr/bin/mail or an explicitly selected authenticated SMTP service, with RFC 2047 subject encoding and remote acceptance verification. Use when the user asks to email, mail, send, or deliver a report, notification, or confirmation, including when direct Postfix delivery is rejected because of sender-IP reputation.
---

# Send Email

Use `scripts/send_email.sh`, resolved relative to this `SKILL.md`. It supports two explicit transports and never retries through a different transport automatically.

## Safety

1. Send only when the user explicitly authorizes delivery and supplies or confirms the recipient.
2. Review the recipient, subject, body, and transport before execution. Never include credentials, private keys, or unrelated local data.
3. Send exactly once. Investigate an uncertain result before retrying.
4. Prefer a macOS Keychain item for SMTP passwords. Never place passwords in files, command arguments, commits, or user-facing output.
5. Use plain-text content. Attachments and HTML are outside this skill's scope.

## Select a Transport

- `local` (default): use `/usr/bin/mail` and direct Postfix delivery. Choose only when the current network's sender IP is acceptable to the recipient domain.
- `smtp`: log in to a configured SMTP service over SSL or STARTTLS. Choose when direct delivery is blocked or authenticated sender identity is required. Read [references/smtp.md](references/smtp.md) before use.

Do not fall back from `local` to `smtp` automatically: a local result may be delayed or ambiguous, and fallback could send a duplicate.

## Send

Pipe a generated body through standard input:

```bash
printf '%s\n' 'Report body' | \
  <skill-directory>/scripts/send_email.sh \
  --transport local \
  --to 'person@example.com' \
  --subject 'Report subject'
```

For authenticated SMTP, configure the variables in [references/smtp.md](references/smtp.md), then change the transport:

```bash
printf '%s\n' 'Report body' | \
  <skill-directory>/scripts/send_email.sh \
  --transport smtp \
  --to 'person@example.com' \
  --subject 'Report subject'
```

Alternatively pass `--body-file '/absolute/path/report.txt'`. Use `--dry-run` to validate inputs and configuration without sending or connecting to the SMTP server.

## Interpret Results

- `SUBJECT_HEADER_READY` reports ASCII or RFC 2047 subject preparation.
- `LOCAL_MAIL_ACCEPTED` means `/usr/bin/mail` accepted a local-transport message.
- `SMTP_CONFIG_READY` and `SMTP_AUTHENTICATED` describe authenticated SMTP setup and login.
- `REMOTE_SMTP_ACCEPTED` means the receiving SMTP server accepted the message; require it plus exit code `0` before reporting success.
- `REMOTE_SMTP_REJECTED`, `REMOTE_DELIVERY_DEFERRED`, `REMOTE_DELIVERY_UNCONFIRMED`, `SMTP_AUTH_FAILED`, and `SMTP_SEND_FAILED` are failures.
- Say the receiving SMTP server accepted the message; do not claim the recipient read it.
- On nonzero exit, report the exact failure and do not silently switch transports or retry.
