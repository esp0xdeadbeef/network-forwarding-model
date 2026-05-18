test_start_ms="$(date +%s%3N)"

test_now_ms() {
  date +%s%3N
}

test_elapsed_ms() {
  local start_ms="${1:-${test_start_ms}}"
  printf '%s\n' "$(($(test_now_ms) - start_ms))"
}

pass_timed() {
  local name="$1"
  local start_ms="${2:-${test_start_ms}}"
  printf 'PASS %sms %s\n' "$(test_elapsed_ms "${start_ms}")" "${name}"
}
