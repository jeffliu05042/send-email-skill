#!/bin/bash
set -euo pipefail

mail_bin="/usr/bin/mail"
mailq_bin="/usr/bin/mailq"
recipient=""
subject=""
body_file=""
dry_run=0
temp_body=""

usage() {
  printf '%s\n' \
    "Usage: send_email.sh --to ADDRESS --subject SUBJECT [--body-file PATH] [--dry-run]" \
    "If --body-file is omitted, the message body is read from standard input."
}

cleanup() {
  if [[ -n "$temp_body" && -f "$temp_body" ]]; then
    /bin/rm -f "$temp_body"
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

temp_body="$(mktemp -t codex-send-email.XXXXXX 2>/dev/null || mktemp "${TMPDIR:-/tmp}/codex-send-email.XXXXXX")"
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

if [[ "$dry_run" -eq 1 ]]; then
  body_bytes="$(/usr/bin/wc -c < "$temp_body" | /usr/bin/tr -d ' ')"
  printf 'DRY_RUN_OK to=%s body_bytes=%s\n' "$recipient" "$body_bytes"
  exit 0
fi

if ! "$mail_bin" -s "$subject" "$recipient" < "$temp_body"; then
  printf '%s\n' "LOCAL_MAIL_REJECTED" >&2
  exit 75
fi
printf 'LOCAL_MAIL_ACCEPTED to=%s\n' "$recipient"

queue_output=""
for _attempt in 1 2 3 4 5; do
  if queue_output="$($mailq_bin 2>&1)"; then
    if [[ "$queue_output" == *"Mail queue is empty"* ]]; then
      printf '%s\n' "QUEUE_EMPTY"
      exit 0
    fi
  fi
  /bin/sleep 1
done

printf '%s\n' "QUEUE_STATUS_UNCONFIRMED" >&2
printf '%s\n' "$queue_output" >&2
exit 75
