#!/usr/bin/env bash
# Checks the App Store text in fastlane/metadata/<locale>/ against Apple's
# limits (#53). Run: .github/scripts/app-store-metadata-check.sh [dir]
#
# Counts characters (not bytes) with the final newline left out, as fastlane
# strips it. A file that isn't there is skipped; App Store Connect keeps
# whatever it already has. Checks:
#   - name and subtitle 30, keywords 100, promotional text 170, description
#     and release notes 4000 characters
#   - every .txt file is valid UTF-8, has no CR, and ends with a newline
#   - keywords: one line, comma-separated, no spaces next to a comma, no empty
#     or repeated keyword, none that repeats a word of name.txt
#   - URL files: one https:// line with no spaces
set -euo pipefail
export LC_ALL=C.UTF-8

dir=${1:-fastlane/metadata/en-US}
[[ -d "$dir" ]] || { echo "app-store-metadata-check: no folder $dir" >&2; exit 2; }
failures=0

fail() {
  echo "FAIL $1" >&2
  failures=$((failures + 1))
}

# Prints the file without its final newline.
text() {
  local content
  content=$(cat "$1"; printf x)
  content=${content%x}
  printf '%s' "${content%$'\n'}"
}

for file in "$dir"/*.txt; do
  [[ -e "$file" ]] || continue
  name=$(basename "$file")
  if ! iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1; then
    fail "$name is not valid UTF-8"
    continue
  fi
  if grep -q $'\r' "$file"; then fail "$name has a carriage return"; fi
  if [[ -s "$file" && $(tail -c 1 "$file" | od -An -c | tr -d ' ') != '\n' ]]; then
    fail "$name does not end with a newline"
  fi
done

check_length() {
  local file="$dir/$1" limit="$2" value
  [[ -e "$file" ]] || return 0
  value=$(text "$file")
  if (( ${#value} > limit )); then
    fail "$1 is ${#value} characters (limit $limit)"
  elif [[ -z "${value//[[:space:]]/}" ]]; then
    fail "$1 is empty"
  else
    echo "ok   $1: ${#value}/$limit"
  fi
}

check_length name.txt 30
check_length subtitle.txt 30
check_length keywords.txt 100
check_length promotional_text.txt 170
check_length description.txt 4000
check_length release_notes.txt 4000

if [[ -e "$dir/keywords.txt" ]]; then
  keywords=$(text "$dir/keywords.txt")
  if [[ "$keywords" == *$'\n'* ]]; then fail "keywords.txt has more than one line"; fi
  if [[ "$keywords" =~ (^|,)[[:blank:]]|[[:blank:]](,|$) ]]; then
    fail "keywords.txt has a space next to a comma"
  fi
  name_words=""
  if [[ -e "$dir/name.txt" ]]; then
    name_words=$(text "$dir/name.txt" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n')
  fi
  seen=$'\n'
  IFS=',' read -ra list <<< "$keywords"
  [[ "$keywords" == *, ]] && list+=("")
  for keyword in "${list[@]}"; do
    lower=$(printf '%s' "$keyword" | tr '[:upper:]' '[:lower:]')
    if [[ -z "$lower" ]]; then fail "keywords.txt has an empty keyword"; continue; fi
    if [[ "$seen" == *$'\n'"$lower"$'\n'* ]]; then fail "keywords.txt repeats \"$keyword\""; fi
    seen+="$lower"$'\n'
    if [[ -n "$name_words" ]] && grep -qxF "$lower" <<< "$name_words"; then
      fail "keywords.txt repeats \"$keyword\" from name.txt"
    fi
  done
fi

for url_file in support_url.txt marketing_url.txt privacy_url.txt; do
  [[ -e "$dir/$url_file" ]] || continue
  url=$(text "$dir/$url_file")
  if [[ "$url" =~ ^https://[^[:space:]]+$ ]]; then
    echo "ok   $url_file"
  else
    fail "$url_file must be one https:// URL with no spaces"
  fi
done

if (( failures > 0 )); then
  echo "$failures App Store metadata problem(s) in $dir." >&2
  exit 1
fi
echo "App Store metadata in $dir is within Apple's limits."
