#!/bin/sh
#
# GitHub Actions version script (v2) for the promotion-based deploy flow.
#
# Extends version-gh.sh with one additional output:
#   RELEASE_TAG = v<FULL_VERSION>  (e.g. v26.07.1-1059)
#     Used as the per-build GitHub Release tag — unique across all builds
#     within a release cycle. Distinct from TAG_NAME (v26.07.1) which is the
#     real release tag created only at pilot promotion.
#
# GitHub Actions variable mapping (same as version-gh.sh):
#   CI_COMMIT_REF_NAME  <- GITHUB_REF_NAME
#   CI_PIPELINE_IID     <- GITHUB_RUN_NUMBER
#   CI_COMMIT_SHORT_SHA <- GITHUB_SHA (first 8 chars)
#
# Changes vs GitLab flow (enforced by the caller, not this script):
#   - Release branches: caller uses "next-patch" mode (not "current-release")
#     since each merge to a release branch must increment the patch.
#
# Usage (same as version.sh):
#   ./version-gh2.sh [MODE] [BUILD_NUMBER] [LABEL]
#

# Map GitHub Actions variables → GitLab-style variables that version.sh uses.
export CI_COMMIT_REF_NAME="${CI_COMMIT_REF_NAME:-${GITHUB_REF_NAME:-}}"
export CI_PIPELINE_IID="${CI_PIPELINE_IID:-${GITHUB_RUN_NUMBER:-0}}"
export CI_COMMIT_SHORT_SHA="${CI_COMMIT_SHORT_SHA:-$(echo "${GITHUB_SHA:-localsha}" | cut -c1-8)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Run version.sh and capture stdout; stderr (progress messages) passes through.
OUTPUT=$("$SCRIPT_DIR/version.sh" "$@")
echo "$OUTPUT"

# Append RELEASE_TAG derived from FULL_VERSION.
FULL_VERSION=$(echo "$OUTPUT" | grep "^FULL_VERSION=" | cut -d= -f2)
echo "RELEASE_TAG=v${FULL_VERSION}"
