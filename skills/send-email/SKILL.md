---
name: send-email
description: Send plain-text email through the macOS local /usr/bin/mail command and verify Postfix submission and queue state. Use when the user asks to email, mail, send, or deliver a report, notification, or confirmation from this machine, especially when local terminal delivery should be used instead of Apple Mail automation or a cloud connector.
---

# Send Email

Use `scripts/send_email.sh`, resolved relative to this `SKILL.md`, for deterministic local delivery. It invokes `/usr/bin/mail`, waits for the on-demand Postfix process, and verifies that the local queue becomes empty.

## Safety

1. Treat sending as an external side effect. Send only when the user explicitly asks to send and supplies or confirms the recipient.
2. Review the recipient, subject, and body before execution. Never include credentials, tokens, private keys, or unrelated local data.
3. Send exactly once. If an earlier attempt has an uncertain result, inspect its command status and queue evidence before retrying.
4. Use plain-text content. Attachments and HTML are outside this skill's scope.

## Send

Pipe a generated body through standard input:

```bash
printf '%s\n' 'Report body' | \
  <skill-directory>/scripts/send_email.sh \
  --to 'person@example.com' \
  --subject 'Report subject'
```

Or read an existing plain-text file:

```bash
<skill-directory>/scripts/send_email.sh \
  --to 'person@example.com' \
  --subject 'Report subject' \
  --body-file '/absolute/path/report.txt'
```

Replace `<skill-directory>` with the directory containing this `SKILL.md`. Use `--dry-run` to validate inputs without sending.

## Interpret Results

- `LOCAL_MAIL_ACCEPTED` means `/usr/bin/mail` accepted the message locally.
- `QUEUE_EMPTY` means no message remains in the local Postfix queue.
- Report success only when both markers appear and the script exits `0`.
- Say the email was submitted or sent; do not claim the recipient received it unless independently confirmed.
- On any nonzero exit, report the exact failure and do not silently switch to Apple Mail or retry.
