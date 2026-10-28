#!/usr/bin/env bash
# Tests for app-store-metadata-check.sh. Run: .github/scripts/app-store-metadata-check-test.sh
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/app-store-metadata-check.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

# Prints N copies of a character.
repeat() { local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }

# expect NAME pass|fail FILE CONTENT [FILE CONTENT ...]
# Starts from a valid folder, then writes each FILE with CONTENT as given
# (printf %s, so CONTENT carries its own newline). CONTENT "-" deletes FILE.
expect() {
  local name="$1" want="$2" got
  shift 2
  rm -rf "$tmp/m"
  mkdir -p "$tmp/m"
  printf '%s\n' "session,hand,log" > "$tmp/m/keywords.txt"
  printf '%s\n' "Track sessions." > "$tmp/m/promotional_text.txt"
  printf '%s\n' "A description." > "$tmp/m/description.txt"
  printf '%s\n' "First release." > "$tmp/m/release_notes.txt"
  printf '%s\n' "https://example.com/support" > "$tmp/m/support_url.txt"
  while (( $# >= 2 )); do
    if [[ "$2" == "-" ]]; then rm -f "$tmp/m/$1"; else printf '%s' "$2" > "$tmp/m/$1"; fi
    shift 2
  done
  if "$script" "$tmp/m" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  fi
}

nl=$'\n'
cr=$'\r'
expect "valid folder"                       pass
expect "missing optional file is skipped"   pass release_notes.txt -
expect "keywords at 100"                    pass keywords.txt "$(repeat a 100)$nl"
expect "keywords at 101"                    fail keywords.txt "$(repeat a 101)$nl"
expect "promo at 170"                       pass promotional_text.txt "$(repeat a 170)$nl"
expect "promo at 171"                       fail promotional_text.txt "$(repeat a 171)$nl"
expect "description at 4000"                pass description.txt "$(repeat a 4000)$nl"
expect "description at 4001"                fail description.txt "$(repeat a 4001)$nl"
expect "release notes at 4001"              fail release_notes.txt "$(repeat a 4001)$nl"
expect "name at 31"                         fail name.txt "$(repeat a 31)$nl"
expect "subtitle at 30"                     pass subtitle.txt "$(repeat a 30)$nl"
expect "counts characters, not bytes"       pass promotional_text.txt "$(repeat é 170)$nl"
expect "multibyte over the limit"           fail promotional_text.txt "$(repeat é 171)$nl"
expect "no trailing newline"                fail description.txt "A description."
expect "carriage return"                    fail description.txt "A description.$cr$nl"
expect "invalid UTF-8"                      fail description.txt $'\xff\xfe'"$nl"
expect "empty description"                  fail description.txt "$nl"
expect "space after a comma"                fail keywords.txt "session, hand$nl"
expect "space before a comma"               fail keywords.txt "session ,hand$nl"
expect "empty keyword"                      fail keywords.txt "session,,hand$nl"
expect "trailing comma"                     fail keywords.txt "session,hand,$nl"
expect "repeated keyword, any case"         fail keywords.txt "session,hand,Session$nl"
expect "two keyword lines"                  fail keywords.txt "session${nl}hand$nl"
expect "keyword repeats the name"           fail keywords.txt "poker,hand$nl" name.txt "Poker Tracker$nl"
expect "keyword not in the name"            pass keywords.txt "session,hand$nl" name.txt "Poker Tracker$nl"
expect "http URL"                           fail support_url.txt "http://example.com$nl"
expect "URL with a space"                   fail privacy_url.txt "https://example.com/a b$nl"
expect "two URL lines"                      fail marketing_url.txt "https://a.example${nl}https://b.example$nl"

# The committed metadata must pass too.
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)/fastlane/metadata/en-US"
if "$script" "$repo_dir" >/dev/null 2>&1; then
  echo "ok   committed fastlane/metadata/en-US"
else
  echo "FAIL committed fastlane/metadata/en-US"
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  echo "$failures test(s) failed." >&2
  exit 1
fi
echo "All app-store-metadata-check tests passed."
