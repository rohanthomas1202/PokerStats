#!/usr/bin/env bash
# Usage: privacy-api-check.sh MANIFEST PATH...
#
# Scans the Swift files under each PATH (a directory or a file) for
# required-reason API symbols and fails unless every category it finds is
# declared, with at least one reason, in MANIFEST (a PrivacyInfo.xcprivacy).
# A missing MANIFEST counts as declaring nothing. Comments (nested block
# comments too) are ignored, and so are folders named PokerStatsTests/ and
# PokerStatsUITests/ at any depth. String literals, """ ones included, are
# scanned as code, so a "/*" inside one does not start a comment, also inside
# an interpolation. Raw strings (#"..."#) and interpolations in multi-line
# strings are not parsed specially.
#
# The patterns are a plain grep, not a compiler: a new use of an API that is
# not listed here passes, and a lookalike name can fail. Categories:
# https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
set -euo pipefail

if (( $# < 2 )); then
  echo "usage: $0 MANIFEST PATH..." >&2
  exit 2
fi
manifest="$1"
shift

categories=(UserDefaults FileTimestamp SystemBootTime DiskSpace ActiveKeyboards)
declare -A patterns=(
  [UserDefaults]='\b(NS)?UserDefaults\b|@AppStorage\b|\bCFPreferences'
  [FileTimestamp]='\b(creationDate|modificationDate|fileCreationDate|fileModificationDate|attributesOfItem|creationDateKey|contentModificationDateKey|contentAccessDateKey|attributeModificationDateKey|f?getattrlist(at|bulk)?|NSFileCreationDate|NSFileModificationDate|NSURLCreationDateKey|NSURLContentModificationDateKey|NSURLContentAccessDateKey|NSURLAttributeModificationDateKey)\b|(^|[^.[:alnum:]_])(f|l)?stat(at)?[[:space:]]*\('
  [SystemBootTime]='\b(systemUptime|mach_absolute_time)\b'
  [DiskSpace]='\b(volumeAvailableCapacity[[:alnum:]]*|volumeTotalCapacityKey|systemFreeSize|systemSize|f?statv?fs)\b'
  [ActiveKeyboards]='\bactiveInputModes\b'
)

# Categories the manifest declares with at least one reason.
declared=""
if [[ -f "$manifest" ]]; then
  declared=$(python3 - "$manifest" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    plist = plistlib.load(f)
for entry in plist.get("NSPrivacyAccessedAPITypes", []):
    if entry.get("NSPrivacyAccessedAPITypeReasons"):
        print(entry.get("NSPrivacyAccessedAPIType", ""))
PY
  )
fi

files=()
for path in "$@"; do
  if [[ ! -e "$path" ]]; then
    echo "error: $path does not exist" >&2
    exit 2
  fi
  while IFS= read -r -d '' file; do
    case "/$file" in
      */PokerStatsTests/*|*/PokerStatsUITests/*) continue ;;
    esac
    files+=("$file")
  done < <(find "$path" -type f -name '*.swift' -print0)
done

# Prints FILE:LINE:TEXT for each match of PATTERN, with comments blanked out
# (line numbers kept). String literals are kept, so "https://" is not a comment.
# The block comment pattern recurses, because Swift block comments nest. A
# one-line string's \(...) interpolation is matched as balanced parentheses,
# so a string literal inside it, as in "\(f("/*"))", does not end the outer
# string early. A one-line string that does not close, or has an unbalanced
# \(, is kept as code to the end of its line. With the possessive repeats this
# keeps the scan linear in the line length (#189).
scan() {
  local pattern="$1" file
  for file in "${files[@]}"; do
    perl -0777 -pe 's{("""(?:\\.|.)*?"""|(?&str)|"[^\n]*)|//[^\n]*|(?&block)(?(DEFINE)(?<str>"(?:\\\((?&interp)\)|\\[^(]|[^"\\\n])*+")(?<interp>(?:(?&str)|\((?&interp)\)|[^()"\n])*+)(?<block>/\*(?:[^/*]|/(?!\*)|\*(?!/)|(?&block))*\*/))}{ defined $1 ? $1 : ($& =~ tr/\n//cdr) }gse' "$file" \
      | { grep -nE "$pattern" || true; } \
      | while IFS= read -r line; do printf '%s:%s\n' "$file" "$line"; done
  done
}

found=0
failed=0
for category in "${categories[@]}"; do
  name="NSPrivacyAccessedAPICategory$category"
  hits=$(scan "${patterns[$category]}")
  [[ -z "$hits" ]] && continue
  found=1
  if grep -qxF "$name" <<<"$declared"; then
    echo "ok    $name is declared in $manifest. Uses:"
    echo "$hits" | sed 's/^/        /'
  else
    echo "error $name is used but not declared in $manifest. Uses:"
    echo "$hits" | sed 's/^/        /'
    failed=1
  fi
done

if (( failed )); then
  [[ -f "$manifest" ]] || echo "$manifest does not exist. Add a privacy manifest to this target." >&2
  echo "Declare each category above, with its reason, in $manifest." >&2
  exit 1
fi
if (( found )); then
  echo "Every required-reason API category used is declared in $manifest."
else
  echo "No required-reason API use found for $manifest."
fi
