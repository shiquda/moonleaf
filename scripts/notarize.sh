#!/bin/bash
# Notarizes and staples the release disk image via notarytool.
#
# Credentials come from the environment so the same script works locally and in
# CI: MP_NOTARY_KEYCHAIN_PROFILE, or MP_NOTARY_APPLE_ID + MP_NOTARY_TEAM_ID +
# MP_NOTARY_PASSWORD (an app-specific password).
#
# usage: scripts/notarize.sh submit <dmg> [--no-wait]
#        scripts/notarize.sh info <submission-id>
#        scripts/notarize.sh log <submission-id> [output-path]
#        scripts/notarize.sh staple <dmg>
set -euo pipefail

PROFILE=${MP_NOTARY_KEYCHAIN_PROFILE:-}
APPLE_ID=${MP_NOTARY_APPLE_ID:-}
TEAM_ID=${MP_NOTARY_TEAM_ID:-}
PASSWORD=${MP_NOTARY_PASSWORD:-}

usage() {
    printf '%s\n' "usage: $0 submit <dmg> [--no-wait] | info <id> | log <id> [output] | staple <dmg>" >&2
}

notarytool() {
    if [ -n "$PROFILE" ]; then
        xcrun notarytool "$@" --keychain-profile "$PROFILE"
    elif [ -n "$APPLE_ID" ] && [ -n "$TEAM_ID" ] && [ -n "$PASSWORD" ]; then
        xcrun notarytool "$@" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$PASSWORD"
    else
        printf '%s\n' "error: set MP_NOTARY_KEYCHAIN_PROFILE or MP_NOTARY_APPLE_ID + MP_NOTARY_TEAM_ID + MP_NOTARY_PASSWORD" >&2
        exit 1
    fi
}

command=${1:-}
case "$command" in
    submit)
        DMG=${2:?"submit requires a dmg path"}
        shift 2
        WAIT=true
        for arg in "$@"; do
            case "$arg" in
                --no-wait) WAIT=false ;;
                *) usage; exit 2 ;;
            esac
        done
        if [ "$WAIT" = true ]; then
            notarytool submit "$DMG" --wait --timeout 30m
        else
            notarytool submit "$DMG" --no-wait --output-format json
        fi
        ;;
    info)
        notarytool info "${2:?"info requires a submission id"}" --output-format json
        ;;
    log)
        ID=${2:?"log requires a submission id"}
        if [ $# -ge 3 ]; then
            notarytool log "$ID" "$3"
        else
            notarytool log "$ID"
        fi
        ;;
    staple)
        DMG=${2:?"staple requires a dmg path"}
        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
        ;;
    *)
        usage
        exit 2
        ;;
esac
