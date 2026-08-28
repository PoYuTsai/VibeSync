#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
android_root="$repo_root/android"

cd "$repo_root"
flutter pub get

if [[ ! -x "$android_root/gradlew" ]]; then
    temp_root="$(mktemp -d "${TMPDIR:-/tmp}/gate-k-wrapper.XXXXXX")"
    trap 'rm -rf -- "$temp_root"' EXIT
    flutter create \
        --platforms=android \
        --project-name gate_k_wrapper \
        --no-pub \
        "$temp_root"
    cp "$temp_root/android/gradlew" "$android_root/gradlew"
    cp "$temp_root/android/gradlew.bat" "$android_root/gradlew.bat"
    cp \
        "$temp_root/android/gradle/wrapper/gradle-wrapper.jar" \
        "$android_root/gradle/wrapper/gradle-wrapper.jar"
fi

cd "$android_root"
./gradlew :gate-k-prototype:test :gate-k-prototype:connectedDebugAndroidTest
