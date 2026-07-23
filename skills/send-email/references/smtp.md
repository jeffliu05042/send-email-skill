# Authenticated SMTP Configuration

Use authenticated SMTP when direct Postfix delivery is rejected because of sender-IP reputation or the recipient requires an authenticated identity. The transport uses Python's standard `smtplib`; it does not modify Postfix.

## Settings

| Variable | Required | Meaning |
| --- | --- | --- |
| `SEND_EMAIL_SMTP_HOST` | Yes | SMTP hostname supplied by the provider. |
| `SEND_EMAIL_SMTP_USERNAME` | Yes | Login username, commonly the sender email address. |
| `SEND_EMAIL_SMTP_SECURITY` | No | `starttls` (default) or `ssl`. |
| `SEND_EMAIL_SMTP_PORT` | No | Defaults to `587` for STARTTLS or `465` for SSL. |
| `SEND_EMAIL_SMTP_FROM` | No | Envelope/header sender; defaults to the username. |
| `SEND_EMAIL_SMTP_TIMEOUT` | No | Connection timeout in seconds; defaults to `20`. |
| `SEND_EMAIL_SMTP_PASSWORD` | Conditional | App password supplied through the process environment. |
| `SEND_EMAIL_SMTP_KEYCHAIN_SERVICE` | Conditional | Generic Keychain service containing the app password. |
| `SEND_EMAIL_SMTP_KEYCHAIN_ACCOUNT` | No | Keychain account; defaults to the SMTP username. |

Set exactly one password source. Prefer an application-specific password where the provider supports it; do not use or expose the normal account password.

## Store the Password in macOS Keychain

Choose a service name such as `send-email-smtp`, then add or update the secret without writing it to disk:

```bash
read -s -p 'SMTP app password: ' SMTP_SECRET; printf '\n'
security add-generic-password -U \
  -a "$SEND_EMAIL_SMTP_USERNAME" \
  -s 'send-email-smtp' \
  -w "$SMTP_SECRET"
unset SMTP_SECRET
export SEND_EMAIL_SMTP_KEYCHAIN_SERVICE='send-email-smtp'
```

The script calls `security find-generic-password -w` internally and never prints the returned password.

For a one-off process, `SEND_EMAIL_SMTP_PASSWORD` is supported, but avoid shell history and unset it immediately after use.

## Validate Without Sending

Set the provider values, then run:

```bash
printf '%s\n' 'Test body' | \
  <skill-directory>/scripts/send_email.sh \
  --transport smtp \
  --to 'person@example.com' \
  --subject 'SMTP dry run' \
  --dry-run
```

Require `SMTP_CONFIG_READY`, `MESSAGE_READY`, `DRY_RUN_OK`, and exit code `0`. Dry-run validates configuration and MIME construction but does not connect or verify credentials.

## Send and Verify

Remove `--dry-run` only after the user authorizes delivery. A successful SMTP send reports `SMTP_AUTHENTICATED` followed by `REMOTE_SMTP_ACCEPTED` and exits `0`.

Treat authentication failure, recipient refusal, timeout, TLS failure, or any nonzero exit as a failed send. Do not retry through another transport automatically.
