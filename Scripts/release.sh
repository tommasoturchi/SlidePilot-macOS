#!/bin/bash
#
# Builds SlidePilot, signs it for Sparkle and publishes it as a GitHub release of this fork.
#
# Raise the version (MARKETING_VERSION) and build (CURRENT_PROJECT_VERSION) in Xcode and commit,
# then run from the repository root:
#
#   Scripts/release.sh [--dry-run] [release-notes.md]
#
# Installed copies look for updates in the appcast.xml of the latest release, so they are offered
# the update as soon as the release is published. With --dry-run, the app, archive and appcast are
# only built in build/release.

set -euo pipefail

REPO=tommasoturchi/SlidePilot-macOS
OUTPUT=build/release

DRY_RUN=false
if [[ ${1:-} == --dry-run ]]; then
    DRY_RUN=true
    shift
fi
NOTES=${1:-}

cd "$(dirname "$0")/.."

# xcodebuild needs Xcode, not just the command line tools
if [[ -z ${DEVELOPER_DIR:-} && $(xcode-select -p) == *CommandLineTools* ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ $DRY_RUN == false && -n $(git status --porcelain) ]]; then
    echo "Commit your changes first, so that the release matches the repository." >&2
    exit 1
fi

SETTINGS=$(xcodebuild -project SlidePilot.xcodeproj -target SlidePilot -configuration Release -showBuildSettings 2>/dev/null)
setting() { awk -v name="$1" '$1 == name { print $3; exit }' <<< "$SETTINGS"; }
VERSION=$(setting MARKETING_VERSION)
BUILD_NUMBER=$(setting CURRENT_PROJECT_VERSION)
MINIMUM_SYSTEM=$(setting MACOSX_DEPLOYMENT_TARGET)
TAG="v$VERSION"
ARCHIVE="SlidePilot-$VERSION.zip"

if [[ $DRY_RUN == false ]] && gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "$TAG is already released. Raise the version first." >&2
    exit 1
fi

echo "Building SlidePilot $VERSION ($BUILD_NUMBER)…"
rm -rf "$OUTPUT"
# Without a Developer ID the app is signed for this Mac only. The hardened runtime is turned off,
# because it only allows loading the Sparkle framework when both are signed by the same team.
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilot -configuration Release -derivedDataPath "$OUTPUT/DerivedData" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO \
    build -quiet
APP="$OUTPUT/DerivedData/Build/Products/Release/SlidePilot.app"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$ARCHIVE"
SIGNATURE=$(swift Scripts/sparkle.swift sign "$OUTPUT/$ARCHIVE")
LENGTH=$(stat -f %z "$OUTPUT/$ARCHIVE")

# Sparkle shows the release notes as HTML
DESCRIPTION=""
if [[ -n $NOTES ]]; then
    ESCAPED=$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$NOTES")
    DESCRIPTION="<description><![CDATA[<pre style=\"font: -apple-system-body; white-space: pre-wrap\">$ESCAPED</pre>]]></description>"
fi

cat > "$OUTPUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SlidePilot+</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM</sparkle:minimumSystemVersion>
      $DESCRIPTION
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$ARCHIVE" sparkle:version="$BUILD_NUMBER" sparkle:shortVersionString="$VERSION" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
EOF

if [[ $DRY_RUN == true ]]; then
    echo "Built $OUTPUT/$ARCHIVE and $OUTPUT/appcast.xml without publishing."
    exit 0
fi

if [[ -n $NOTES ]]; then
    NOTES_OPTION=(--notes-file "$NOTES")
else
    NOTES_OPTION=(--generate-notes)
fi
gh release create "$TAG" "$OUTPUT/$ARCHIVE" "$OUTPUT/appcast.xml" --repo "$REPO" --title "SlidePilot+ $VERSION" "${NOTES_OPTION[@]}"
echo "Published $TAG. Installed copies will offer the update on their next check."
