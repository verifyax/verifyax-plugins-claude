#!/usr/bin/env bash
#
# build-skill.sh — package a plugin's skill into a Claude.ai `.skill` bundle.
#
# The bundle is a zip whose top level contains a single folder named after the
# skill, with SKILL.md (and any resource files) inside it -- the layout Claude.ai
# requires. We emit it twice: `<skill>.zip`, which is the extension Claude.ai's
# uploader documents, and `<skill>.skill`, kept so links to older release assets
# keep working. Both files are byte-identical archives.
#
# Usage:
#   scripts/build-skill.sh [plugin] [skill]
#
#   plugin   plugin directory name under plugins/   (default: verifyax-api)
#   skill    skill directory name under the plugin  (default: same as plugin)
#
# Examples:
#   scripts/build-skill.sh                      # builds dist/verifyax-api.zip
#   scripts/build-skill.sh verifyax-api         # same
#
# Output: dist/<skill>.zip  (and dist/<skill>.skill, same bytes)
#
set -euo pipefail

PLUGIN="${1:-verifyax-api}"
SKILL="${2:-$PLUGIN}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/$PLUGIN/skills/$SKILL"
DIST_DIR="$REPO_ROOT/dist"
OUT="$DIST_DIR/$SKILL.zip"
OUT_LEGACY="$DIST_DIR/$SKILL.skill"

if [[ ! -f "$SKILL_DIR/SKILL.md" ]]; then
  echo "error: $SKILL_DIR/SKILL.md not found" >&2
  echo "       expected layout: plugins/<plugin>/skills/<skill>/SKILL.md" >&2
  exit 1
fi

command -v zip >/dev/null 2>&1 || { echo "error: 'zip' is required but not installed" >&2; exit 1; }

# Read the version from the plugin's plugin.json (best-effort, for the log line).
PLUGIN_JSON="$REPO_ROOT/plugins/$PLUGIN/.claude-plugin/plugin.json"
VERSION="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null | head -1 | grep -oE '[0-9][^"]*' || true)"

# Stage <skill>/ so the archive has the folder at its top level, then zip.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$SKILL_DIR" "$STAGE/$SKILL"

# Normalise CRLF -> LF in the staged text before zipping. A Windows
# core.autocrlf checkout hands us CRLF working-tree files, so the bundle would
# ship line endings that differ from the committed source. CI never catches it
# because CI runs on Linux; the asset a maintainer uploads by hand is the one
# that breaks. A published artifact should be identical whoever built it.
# Strip unconditionally and compare sizes rather than testing first: git-bash's
# grep opens files in text mode and drops CR before matching, so a "does this
# file contain CR" test silently reports no on the very platform that needs the
# fix. Byte counts do not lie.
CR="$(printf '\r')"
normalised=0
while IFS= read -r f; do
  case "$f" in
    *.md | *.txt | *.json | *.yaml | *.yml)
      before=$(wc -c <"$f")
      tr -d "$CR" <"$f" >"$f.lf" && mv "$f.lf" "$f"
      after=$(wc -c <"$f")
      [ "$before" -eq "$after" ] || normalised=$((normalised + 1))
      ;;
  esac
done <<EOF
$(find "$STAGE/$SKILL" -type f)
EOF
[ "$normalised" -eq 0 ] || echo "note: normalised CRLF -> LF in $normalised file(s) before packaging"

mkdir -p "$DIST_DIR"
rm -f "$OUT" "$OUT_LEGACY"
( cd "$STAGE" && zip -r -X "$OUT" "$SKILL" >/dev/null )
# Same archive under the legacy extension, so older release links keep resolving.
cp "$OUT" "$OUT_LEGACY"

echo "Built $OUT${VERSION:+ (v$VERSION)}"
echo "Built $OUT_LEGACY (same bytes, legacy extension)"
echo "Contents:"
zip -sf "$OUT" | sed 's/^/  /'
