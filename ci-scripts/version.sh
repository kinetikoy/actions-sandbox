#!/bin/sh
#
# Generates versioning variables for Android applications in a CI/CD environment.
#
# Usage: ./version.sh [MODE] [BUILD_NUMBER] [LABEL]
#
# Arguments:
#   MODE (arg 1):
#     - "next-release":    Calculates version YY.MM.1 based on current date. If vYY.MM.1 tag exists, it tries next month.
#     - "next-patch":      Calculates version from current branch (release/vYY.MM), increments patch of last tag.
#     - "current-release": Calculates version from current branch (release/vYY.MM), uses patch of last tag.
#   BUILD_NUMBER (arg 2): Build number. Defaults to 1.
#   LABEL        (arg 3): Optional label (e.g., "dev", "stage").
#
# Output variables:
#    VERSION_NAME, BUILD_NUMBER, FULL_VERSION, TAG_NAME, RELEASE_BRANCH, APP_TAG

# 1. Configuration & Input Setup
MODE=${1:-"next-release"}
BUILD_NUMBER=${2:-1}
CI_ENV_LABEL=${3:-""}

# Variables that must be guarded by defaults for local runs
CI_PIPELINE_IID=${CI_PIPELINE_IID:-0}
CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA:-"localsha"}

# Sync with remote to remove stale tags and branches
echo "Fetching from remote and pruning stale tags/branches..." >&2
git fetch --prune origin "+refs/tags/*:refs/tags/*" >&2
git remote prune origin >&2

APP_TAG=""
VERSION_NAME=""
VERSION_PREFIX=""

# --- Internal Functions ---

get_current_branch() {
    # If CI_COMMIT_REF_NAME is set (GitLab CI), use it. Otherwise use git.
    if [ -n "$CI_COMMIT_REF_NAME" ]; then
        echo "$CI_COMMIT_REF_NAME"
    else
        git rev-parse --abbrev-ref HEAD
    fi
}

get_last_tag() {
    prefix=$1
    # Find tags matching vYY.MM.patch
    git tag -l "v${prefix}.*" | grep -E "^v${prefix}\.[0-9]+$" | sort -V | tail -n 1
}

# --- 2. Determine Base Version based on MODE ---

if [ "$MODE" = "next-release" ]; then
    # Start with current month
    year_yy=$(date +%y)
    month_mm=$(date +%m)

    # Loop to find the next available release slot
    while true; do
        version_prefix_to_check="${year_yy}.${month_mm}"
        tag_to_check="v${version_prefix_to_check}.1"

        if [ -z "$(git tag -l "$tag_to_check")" ]; then
            # Tag does not exist, we can use this version
            VERSION_PREFIX=$version_prefix_to_check
            VERSION_NAME="${VERSION_PREFIX}.1"
            break
        else
            # Tag exists, increment month
            echo "Tag $tag_to_check already exists. Incrementing to next month." >&2

            # Convert to numbers for arithmetic
            month_num=$(expr "$month_mm" + 0)
            year_num=$(expr "$year_yy" + 0)

            if [ "$month_num" -eq 12 ]; then
                month_mm="01"
                year_yy=$(expr "$year_num" + 1)
            else
                month_num=$(expr "$month_num" + 1)
                # Pad with zero if needed
                if [ "$month_num" -lt 10 ]; then
                    month_mm="0${month_num}"
                else
                    month_mm="$month_num"
                fi
            fi
        fi
    done

elif [ "$MODE" = "next-patch" ] || [ "$MODE" = "current-release" ]; then
    CURRENT_BRANCH=$(get_current_branch)

    # Check if branch matches release/vYY.MM
    case "$CURRENT_BRANCH" in
        release/v*)
            # Extract YY.MM
            VERSION_PREFIX=${CURRENT_BRANCH#release/v}
            ;;
        *)
            echo "Error: Current branch '$CURRENT_BRANCH' does not match format 'release/vYY.MM' required for mode '$MODE'" >&2
            exit 1
            ;;
    esac

    # Find last tag for this prefix
    LAST_TAG=$(get_last_tag "$VERSION_PREFIX")

    if [ -z "$LAST_TAG" ]; then
        echo "Error: No tags found for prefix v${VERSION_PREFIX} in mode '$MODE'. At least one tag must exist." >&2
        exit 1
    fi

    # Extract patch from vYY.MM.PATCH
    # Remove 'v' prefix
    VERSION_PART=${LAST_TAG#v}
    # Get 3rd field (patch)
    CURRENT_PATCH=$(echo "$VERSION_PART" | cut -d. -f3)

    if [ "$MODE" = "next-patch" ]; then
        NEXT_PATCH=$(expr "$CURRENT_PATCH" + 1)
        VERSION_NAME="${VERSION_PREFIX}.${NEXT_PATCH}"
    else
        # current-release
        VERSION_NAME="${VERSION_PREFIX}.${CURRENT_PATCH}"
    fi

else
    echo "Error: Invalid MODE '$MODE'. Allowed values: next-release, next-patch, current-release" >&2
    exit 1
fi

# --- 3. Apply Label and Finalize ---

if [ -n "$CI_ENV_LABEL" ]; then
    # Development/Labeled Build
    VERSION_NAME="${VERSION_NAME}-${CI_ENV_LABEL}"
    FULL_VERSION="${VERSION_NAME}-${BUILD_NUMBER}"
    APP_TAG=""
else
    # Production/Release Build
    FULL_VERSION="${VERSION_NAME}-${BUILD_NUMBER}"
    APP_TAG="v${VERSION_NAME}"
fi

# --- 4. Output for .env File (stdout) ---

echo "VERSION_NAME=$VERSION_NAME"
echo "BUILD_NUMBER=$BUILD_NUMBER"
echo "FULL_VERSION=$FULL_VERSION"
echo "TAG_NAME=v${VERSION_NAME}"
echo "RELEASE_BRANCH=release/v${VERSION_PREFIX}"

# Include other internal variables
echo "APP_TAG=$APP_TAG"
echo "PIPELINE_IID=$CI_PIPELINE_IID"
