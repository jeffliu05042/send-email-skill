#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
send_script="$repo_root/skills/send-email/scripts/send_email.sh"
fixtures="$repo_root/tests/fixtures"
test_dir="$(mktemp -d -t send-email-tests.XXXXXX)"

cleanup() {
  /bin/rm -rf "$test_dir"
}
trap cleanup EXIT

run_with_fakes() {
  SEND_EMAIL_MAIL_BIN="$fixtures/fake_mail.sh" \
  SEND_EMAIL_MAILQ_BIN="$fixtures/fake_mailq.sh" \
  SEND_EMAIL_LOG_BIN="$fixtures/fake_log.sh" \
  SEND_EMAIL_TEST_ARGS_FILE="$test_dir/mail-args" \
  SEND_EMAIL_TEST_LOG_FILE="$test_dir/postfix.log" \
  SEND_EMAIL_VERIFY_ATTEMPTS=1 \
  SEND_EMAIL_VERIFY_INTERVAL=0 \
    "$send_script" "$@"
}

dry_run_output="$(printf '%s\n' 'Regression test body' | \
  "$send_script" \
  --to 'person@example.com' \
  --subject '中文主题' \
  --dry-run)"
[[ "$dry_run_output" == *"SUBJECT_HEADER_READY encoding=rfc2047"* ]] || {
  printf '%s\n' "FAIL: non-ASCII subject was not reported as RFC 2047 encoded." >&2
  exit 1
}

printf '%s\n' \
  '2026-07-23 09:00:00.000 I smtp[123:456] ABC123: to=<person@example.com>, relay=mx.example.com[192.0.2.1]:25, dsn=2.0.0, status=sent (250 Mail OK)' \
  > "$test_dir/postfix.log"
success_output="$(printf '%s\n' 'Regression test body' | \
  run_with_fakes \
  --to 'person@example.com' \
  --subject '中文主题')"
[[ "$success_output" == *"REMOTE_SMTP_ACCEPTED to=person@example.com"* ]] || {
  printf '%s\n' "FAIL: remote SMTP acceptance was not reported." >&2
  exit 1
}
[[ "$success_output" == *"QUEUE_EMPTY"* ]] || {
  printf '%s\n' "FAIL: empty queue was not reported after acceptance." >&2
  exit 1
}
if /usr/bin/grep -Fq '中文主题' "$test_dir/mail-args"; then
  printf '%s\n' "FAIL: raw non-ASCII subject reached the mail command." >&2
  exit 1
fi
if ! /usr/bin/grep -Fq '=?utf-8?' "$test_dir/mail-args"; then
  printf '%s\n' "FAIL: encoded subject was not passed to the mail command." >&2
  exit 1
fi
encoded_subject="$(/usr/bin/awk 'found { print; exit } $0 == "-s" { found = 1 }' "$test_dir/mail-args")"
decoded_subject="$(/usr/bin/python3 - "$encoded_subject" <<'PY'
import sys
from email.header import decode_header, make_header

print(str(make_header(decode_header(sys.argv[1]))))
PY
)"
[[ "$decoded_subject" == '中文主题' ]] || {
  printf 'FAIL: encoded subject decoded as %s.\n' "$decoded_subject" >&2
  exit 1
}

printf '%s\n' \
  '2026-07-23 09:00:00.000 I smtp[123:456] DEF456: to=<person@example.com>, relay=mx.example.com[192.0.2.1]:25, dsn=5.6.7, status=bounced (SMTPUTF8 is required)' \
  > "$test_dir/postfix.log"
set +e
bounce_output="$(printf '%s\n' 'Regression test body' | \
  run_with_fakes \
  --to 'person@example.com' \
  --subject '中文主题' 2>&1)"
bounce_status=$?
set -e
[[ "$bounce_status" -eq 75 ]] || {
  printf 'FAIL: bounce returned %s instead of 75.\n' "$bounce_status" >&2
  exit 1
}
[[ "$bounce_output" == *"REMOTE_SMTP_REJECTED to=person@example.com"* ]] || {
  printf '%s\n' "FAIL: bounce was not reported as remote rejection." >&2
  exit 1
}
if [[ "$bounce_output" == *"REMOTE_SMTP_ACCEPTED"* ]]; then
  printf '%s\n' "FAIL: bounce was misreported as accepted." >&2
  exit 1
fi

printf '%s\n' "PASS: subject encoding and remote delivery verification."
