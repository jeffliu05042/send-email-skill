#!/bin/bash
set -euo pipefail

mail_bin="${SEND_EMAIL_MAIL_BIN:-/usr/bin/mail}"
mailq_bin="${SEND_EMAIL_MAILQ_BIN:-/usr/bin/mailq}"
log_bin="${SEND_EMAIL_LOG_BIN:-/usr/bin/log}"
python_bin="${SEND_EMAIL_PYTHON_BIN:-/usr/bin/python3}"
verify_attempts="${SEND_EMAIL_VERIFY_ATTEMPTS:-15}"
verify_interval="${SEND_EMAIL_VERIFY_INTERVAL:-1}"
recipient=""
subject=""
body_file=""
dry_run=0
temp_body=""
mail_output=""

usage() {
  printf '%s\n' \
    "Usage: send_email.sh --to ADDRESS --subject SUBJECT [--body-file PATH] [--dry-run]" \
    "If --body-file is omitted, the message body is read from standard input."
}

cleanup() {
  if [[ -n "$temp_body" && -f "$temp_body" ]]; then
    /bin/rm -f "$temp_body"
  fi
  if [[ -n "$mail_output" && -f "$mail_output" ]]; then
    /bin/rm -f "$mail_output"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      recipient="$2"
      shift 2
      ;;
    --subject)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      subject="$2"
      shift 2
      ;;
    --body-file)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      body_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

[[ -x "$mail_bin" ]] || { printf '%s\n' "Missing executable: $mail_bin" >&2; exit 69; }
[[ -x "$mailq_bin" ]] || { printf '%s\n' "Missing executable: $mailq_bin" >&2; exit 69; }
[[ -x "$log_bin" ]] || { printf '%s\n' "Missing executable: $log_bin" >&2; exit 69; }
[[ -x "$python_bin" ]] || { printf '%s\n' "Missing executable: $python_bin" >&2; exit 69; }
[[ "$verify_attempts" =~ ^[1-9][0-9]*$ ]] || {
  printf '%s\n' "SEND_EMAIL_VERIFY_ATTEMPTS must be a positive integer." >&2
  exit 64
}
[[ "$verify_interval" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
  printf '%s\n' "SEND_EMAIL_VERIFY_INTERVAL must be a non-negative number." >&2
  exit 64
}
[[ -n "$recipient" ]] || { printf '%s\n' "Recipient is required." >&2; exit 64; }
[[ "$recipient" != -* ]] || { printf '%s\n' "Recipient cannot begin with '-'." >&2; exit 64; }
[[ "$recipient" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || {
  printf '%s\n' "Recipient is not a valid single email address." >&2
  exit 64
}
[[ -n "$subject" ]] || { printf '%s\n' "Subject is required." >&2; exit 64; }
[[ "$subject" != *$'\n'* && "$subject" != *$'\r'* ]] || {
  printf '%s\n' "Subject cannot contain newlines." >&2
  exit 64
}

subject_info="$($python_bin - "$subject" <<'PY'
import sys
from email.header import Header

subject = sys.argv[1]
try:
    subject.encode("ascii")
except UnicodeEncodeError:
    print("rfc2047")
    print(Header(subject, "utf-8", header_name="Subject", maxlinelen=76).encode(linesep=" "))
else:
    print("ascii")
    print(subject)
PY
)"
subject_encoding="${subject_info%%$'\n'*}"
encoded_subject="${subject_info#*$'\n'}"
[[ -n "$encoded_subject" ]] || { printf '%s\n' "Subject encoding failed." >&2; exit 65; }

temp_body="$(mktemp -t codex-send-email.XXXXXX 2>/dev/null || mktemp "${TMPDIR:-/tmp}/codex-send-email.XXXXXX")"
mail_output="$(mktemp -t codex-send-email-output.XXXXXX 2>/dev/null || mktemp "${TMPDIR:-/tmp}/codex-send-email-output.XXXXXX")"
if [[ -n "$body_file" ]]; then
  [[ -r "$body_file" && -f "$body_file" ]] || {
    printf 'Body file is not a readable regular file: %s\n' "$body_file" >&2
    exit 66
  }
  /bin/cp "$body_file" "$temp_body"
else
  [[ ! -t 0 ]] || {
    printf '%s\n' "Provide --body-file or pipe the body through standard input." >&2
    exit 64
  }
  /bin/cat > "$temp_body"
fi

[[ -s "$temp_body" ]] || { printf '%s\n' "Message body cannot be empty." >&2; exit 65; }
printf 'SUBJECT_HEADER_READY encoding=%s\n' "$subject_encoding"

if [[ "$dry_run" -eq 1 ]]; then
  body_bytes="$(/usr/bin/wc -c < "$temp_body" | /usr/bin/tr -d ' ')"
  printf 'DRY_RUN_OK to=%s body_bytes=%s\n' "$recipient" "$body_bytes"
  exit 0
fi

send_started_at="$(/bin/date '+%Y-%m-%d %H:%M:%S')"
if ! "$mail_bin" -v -s "$encoded_subject" "$recipient" < "$temp_body" > "$mail_output" 2>&1; then
  printf '%s\n' "LOCAL_MAIL_REJECTED" >&2
  /usr/bin/tail -n 20 "$mail_output" >&2
  exit 75
fi
printf 'LOCAL_MAIL_ACCEPTED to=%s\n' "$recipient"

last_delivery_line=""
for ((_attempt = 1; _attempt <= verify_attempts; _attempt++)); do
  log_output="$($log_bin show \
    --start "$send_started_at" \
    --style compact \
    --info \
    --predicate 'process == "smtp"' 2>/dev/null || true)"
  delivery_line="$(printf '%s\n' "$log_output" | /usr/bin/grep -F "to=<${recipient}>" | /usr/bin/tail -n 1 || true)"

  if [[ -n "$delivery_line" ]]; then
    last_delivery_line="$delivery_line"
    if [[ "$delivery_line" == *"status=bounced"* ]]; then
      printf 'REMOTE_SMTP_REJECTED to=%s\n' "$recipient" >&2
      printf '%s\n' "$delivery_line" >&2
      exit 75
    fi
    if [[ "$delivery_line" == *"status=sent"* ]]; then
      printf 'REMOTE_SMTP_ACCEPTED to=%s\n' "$recipient"
      queue_output="$($mailq_bin 2>&1 || true)"
      if [[ "$queue_output" == *"Mail queue is empty"* ]]; then
        printf '%s\n' "QUEUE_EMPTY"
      else
        printf '%s\n' "QUEUE_STATUS_UNAVAILABLE_AFTER_DELIVERY"
      fi
      exit 0
    fi
  fi

  if ((_attempt < verify_attempts)); then
    /bin/sleep "$verify_interval"
  fi
done

if [[ "$last_delivery_line" == *"status=deferred"* ]]; then
  printf 'REMOTE_DELIVERY_DEFERRED to=%s\n' "$recipient" >&2
  printf '%s\n' "$last_delivery_line" >&2
else
  printf 'REMOTE_DELIVERY_UNCONFIRMED to=%s\n' "$recipient" >&2
  /usr/bin/tail -n 20 "$mail_output" >&2
fi
exit 75
