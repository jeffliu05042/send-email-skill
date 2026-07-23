#!/bin/bash
set -euo pipefail

printf '%s\n' "$@" > "$SEND_EMAIL_TEST_ARGS_FILE"
/bin/cat > /dev/null
printf '%s\n' "fake mail accepted"
