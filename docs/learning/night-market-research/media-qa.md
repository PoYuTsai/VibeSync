# Night Market media QA

## 2026-09-07 bundle record

All listed outputs were checked with `ffprobe`: 1280×720, H.264 High, `yuv420p`, AAC-LC, faststart.

| asset | duration | SHA256 | QA note |
|---|---:|---|---|
| establish.mp4 | 12.050s | `8efcbd577ea5c481213c9a84f0a67241c941c3ef6156c214aaa1372804d0c739` | Existing bundled opening walk |
| hesitate.mp4 | 12.064s | `d5997a50648b4cb641663d9e207f3f94a076911a6b856d35eeef72ff3eca7712` | Replaced prior NG; Sydney close-up and rightward eyeline, target girl offscreen |
| call.mp4 | 12.064s | `5adbd77f26572f0179335ff617452b067730d2f524965deb702a30d823b97462` | tea pickup and Leah return-to-side action visible; accepted anchor |
| work.mp4 | 6.750s | `e09b40229aef0303eb0a916a52373026b45589ccd9da2638303afbeda184d77f` | source trimmed by 3.3s; subtitle timestamps must subtract 3.3s |
| craft.mp4 | 18.080s | `9e7e39733c165c5f6d2710409f0753ff0699f1ab07e7143819c3fa1ba271f357` | Leah/tea-stall conversation visible |
| concern.mp4 | 8.050s | `84914ba34fc7d66e1c5133d8adb25e6886ebad6ccacb60686f32d033f6cba555` | Existing bundled Leah concern beat |
| coach.mp4 | 12.042s | `0db856649bc13a70eb54a7125c226f1b2b173f0036c5f571d3dd2a244f613020` | Sydney white dress/glasses/long hair visible |
| tease.mp4 | 10.042s | `12be6b13ed2e6635286128e08c541aac7ef56f210d932bead46f287ca0ded764` | Leah adult bob/beige jacket/white top visible |
| decline.mp4 | 8.064s | `a83b4eca1d98c8680f234ff74c076359e7179e68b3d79414ba16a3ddcd32eb78` | retake passes first-person Leah head-and-shoulders; old NG retained as `video-raw/decline-original-ng.mp4` |
| available.mp4 | 10.080s | `30fa21ae6a46af42ba785fceb1c837824d6a6724ea7cc39703b8e536f1a816e9` | Leah adult bob/beige jacket/white top visible |
| busy.mp4 | 8.064s | `8176c9ca291aaf8886247725cc83a499ffb22fa1fe52d24eb94bfe0132158df5` | Leah busy/tea-stall scene bundled |
| opening.mp4 | 14.080s | `d4988ae1e42453dc8464b71c5628634a9fb7c15fa2900ac264a6d5e59ceadcb7` | Leah adult bob/beige jacket/white top; no male foreground hand visible |
| contact.mp4 | 9.264s | `6315d9cde4d6ca51075435cb9ab065148260975118c56e144a88864a9daaffe6` | Approved crop candidate: source trim 2.8s, crop 768×432 at x=256 then scale 1280×720; 4.7–6.7s window checked every 0.25s, no viewer QR phone/hand; Leah's own phone remains allowed |
| date.mp4 | 22.042s | `751d0236cb9c97bf3bcccbdfe4d85547a8be51927589c0cc9cc976d7fd44f66c` | Leah/tea-cup ceramic-stall scene; no male hand or scene mutation. Continuity deviation: the prompt's explicit walk-away ending is not visible; final sampled frames remain on Leah by the stall |

`first_today` has a separate approved trim that keeps source `0–1.3s` with a final `0.02s` fade; it is not a 1.3s front trim. `work` is trimmed from the source at offset 3.3s. Raw source videos remain in local `video-raw/` for QA evidence and are excluded from the formal bundle. Contact sheets and endframes are under `artifact/night-market-contact-sheets/`.

The superseded QR version is retained as `video-raw/contact-original-qr-ng.mp4`. The approved contact crop is softer from 768×432 upscaling. All 14 video beats are now bundled; see `media-manifest.json` for the complete video/audio/poster inventory and hashes.

## Manifest cross-check

Read-only audit on 2026-09-07 compared all 35 manifest items with the current bundle: every file exists, and bytes plus SHA-256 match `media-manifest.json`. The combined manifest payload is approximately 35.37 MB (decimal bytes; 33.73 MiB).

Caption end-time audit was re-run against the current `story.dart` beat blocks (not `nextId` references). All 14 video beats have caption ends at or before their current media durations: `establish` 8.000/12.050 s, `hesitate` 10.000/12.064 s, `opening` 12.000/14.080 s, `concern` 7.720/8.050 s, `work` 6.440/6.750 s, `craft` 16.200/18.080 s, `tease` 10.000/10.042 s, `call` 7.440/12.064 s, `available` 8.000/10.080 s, `date` 16.600/22.042 s, `busy` 7.740/8.064 s, `contact` 7.480/9.264 s, `decline` 4.220/8.064 s, `coach` 11.400/12.042 s. No caption overflow remains; this QA pass does not change source code or media.
