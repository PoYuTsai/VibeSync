# Gate K disposable prototype

This module is an isolated Android `InputMethodService` feasibility probe for
M6 `KEY-00` only. It is not part of the VibeSync release application and has
no AI, OCR, network, upload, quota, chat-content, or persistent-image path.

The public seams are:

1. `ImeSessionFloor` — visible/hidden IME events and a monotonic session floor.
2. `ScreenshotCandidateFilter` — fail-closed session, timestamp, source, and
   dimensions checks.
3. `ScreenshotCandidateDedupe` — SHA-256 identity and session-scoped duplicate
   suppression; only hashes are retained.
4. `GateKAttemptCoordinator` — explicit attempt IDs, one terminal outcome, a
   monotonic 3-second timeout, and bounded failure reasons.
5. `GateKMediaStoreQueryContract` and `GateKMediaStoreSessionBaseline` —
   `GENERATION_ADDED` high-water filtering with a one-row initial query and a
   bounded 128-row delta query; `IS_PENDING=0` is required.
6. `GateKPermissionContract` — exact manifest permission/service allowlist;
   API 34+ full/partial/denied state follows Android's grant precedence.
7. `GateKDeviceDescriptor` / `GateKDeviceClassifier` — raw Build metadata is
   preserved; only explicit emulator signals classify as emulator.
8. `GateKEvidenceAggregator`, `GateKEvidenceJson`, and `GateKEvidenceStore` —
   runtime-origin trial records and deterministic app-private JSON. The only
   positive decision is `EMULATOR_CANDIDATE`; this module cannot emit a full
   Gate K pass.

The Android service registers a `MediaStore.Images` `ContentObserver` only
between `onStartInputView` and `onFinishInputView`, and only when a full image
grant is present. It classifies candidates from MediaStore URI, MIME type, and
`RELATIVE_PATH`; it does not accept a caller-supplied screenshot flag as
authority. Image bytes are transiently read for hashing and are not written to
disk, logs, network, or a database.

The full-grant candidate is policy-sensitive and still unapproved. The
allowlisted permission is evaluated against Google's [Understanding Restricted
Permissions with minimum scope alternatives](https://support.google.com/googleplay/android-developer/answer/16935362?hl=en)
policy contract. API 34+ `READ_MEDIA_IMAGES` granted is `FULL`; selected-only
is `PARTIAL`; neither is `DENIED`. The prototype never treats the selected
photos grant as a full screenshot source.
The prototype declares `READ_MEDIA_VISUAL_USER_SELECTED` only to detect and
reject the system's partial selected-photos state; it never uses that grant as
an authoritative screenshot source. It does not request
`MANAGE_EXTERNAL_STORAGE` or `AccessibilityService` access. A persisted SAF
Screenshots-tree grant remains a separate, not-yet-implemented candidate
requiring device evidence; it is not silently treated as equivalent to a full
MediaStore grant, and this prototype makes no SAF success claim.

## Reproducible manual run

From a WSL login shell, after the versioned environment doctor passes:

```bash
# Run from the repository checkout; Flutter/Gradle artifacts stay in WSL.
node '/mnt/d/Obsidian個人大腦/Dev Brain/30_AI協作工作流/agent-control-plane/src/cli.mjs' \
  environment doctor --project-root "$PWD" --command test --host wsl
bash tools/android/run-gate-k-tests.sh
```

The helper uses the pinned Flutter only to materialize the ignored Android
Gradle wrapper when this checkout does not contain one, then runs the JVM unit
tests and connected instrumentation from `android/`. Wrapper generation and
`flutter pub get` are setup only, never test evidence. It requires the pinned
Android SDK/JDK and a running emulator. The static contract can be run
independently with:

```bash
python3 tools/android/gate-k-manifest-contract.py
```

If the wrapper has been materialized, build and install the disposable APK:

```bash
cd android
./gradlew :gate-k-prototype:assembleDebug
adb install -r gate-k-prototype/build/outputs/apk/debug/gate-k-prototype-debug.apk
```

On an API 34+ emulator, grant only the full image permission and select the
prototype IME:

```bash
adb shell pm grant com.vibesync.gatek android.permission.READ_MEDIA_IMAGES
adb shell pm revoke com.vibesync.gatek android.permission.READ_MEDIA_VISUAL_USER_SELECTED || true
adb shell ime enable com.vibesync.gatek/.GateKPrototypeInputMethodService
adb shell ime set com.vibesync.gatek/.GateKPrototypeInputMethodService
```

Focus a text field in another app. In the IME view tap `Start Gate K attempt`,
then make a hardware screenshot within three seconds. Repeat at least 40
times on each of API 34, 35, and 36. The observer query is bounded and only
accepts `GENERATION_ADDED` rows after the session high-water mark; no album-wide
metadata scan is performed.

Export the metadata-only artifact and capture its device descriptor and source
revision for each trial set:

```bash
adb exec-out run-as com.vibesync.gatek cat files/gate-k-evidence.json \
  > gate-k-evidence-api34.json
adb shell getprop ro.product.manufacturer
adb shell getprop ro.product.brand
adb shell getprop ro.product.model
adb shell getprop ro.product.name
adb shell getprop ro.build.fingerprint
adb shell getprop ro.build.version.sdk
git rev-parse HEAD
```

Instrumentation tests validate public seams and artifact shape; they are not a
substitute for 40 real screenshot trials. A Gate K verdict remains
`INCONCLUSIVE` until API 34/35/36 emulator evidence, physical stock Android
evidence, physical Samsung evidence, and policy review are separately present.
The SAF Screenshots-tree path is a documented candidate but is not implemented
or claimed as tested here.
