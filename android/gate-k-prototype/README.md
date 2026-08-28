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
4. `GateKPermissionContract` — exact manifest permission/service allowlist.
5. `GateKEvidenceAggregator` and `GateKEvidenceJson` — raw trial records and
   deterministic derived counts/latencies. The only positive decision is
   `EMULATOR_CANDIDATE`; this module cannot emit a full Gate K pass.

The Android service registers a `MediaStore.Images` `ContentObserver` only
between `onStartInputView` and `onFinishInputView`, and only when a full image
grant is present. It classifies candidates from MediaStore URI, MIME type, and
`RELATIVE_PATH`; it does not accept a caller-supplied screenshot flag as
authority. Image bytes are transiently read for hashing and are not written to
disk, logs, network, or a database.

The full-grant candidate is policy-sensitive and still unapproved. The
allowlisted permission maps to Google's [Permissions and APIs that Access
Sensitive Information](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en)
policy; minimum-scope alternatives are documented in [Understanding Restricted
Permissions with minimum scope alternatives](https://support.google.com/googleplay/android-developer/answer/16935362?hl=en).
The prototype declares `READ_MEDIA_VISUAL_USER_SELECTED` only to detect and
reject the system's partial selected-photos state; it never uses that grant as
an authoritative screenshot source. It does not request
`MANAGE_EXTERNAL_STORAGE` or `AccessibilityService` access. A persisted SAF
Screenshots-tree grant remains a separate, not-yet-implemented candidate
requiring device evidence; it is not silently treated as equivalent to a full
MediaStore grant, and this prototype makes no SAF success claim.

## Checks

From a WSL login shell, after the versioned environment doctor passes:

```bash
bash tools/android/run-gate-k-tests.sh
```

The helper uses the pinned Flutter only to materialize the ignored Android
Gradle wrapper when this checkout does not contain one, then runs both the JVM
unit tests and connected instrumentation from `android/`. It requires the
pinned Android SDK/JDK and an emulator; wrapper generation itself is not test
evidence. The static contract can be run independently with:

```bash
python3 tools/android/gate-k-manifest-contract.py
```

API 34, 35, and 36 each need at least 40 raw trials before the result can be
called an emulator candidate. Physical stock Android and Samsung evidence plus
policy review remain hard prerequisites for any Gate K decision.
