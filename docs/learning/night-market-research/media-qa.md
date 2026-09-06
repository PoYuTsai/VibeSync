# Night Market media QA

## 2026-09-07 bundle record

All listed outputs were checked with `ffprobe`: 1280×720, H.264 High, `yuv420p`, AAC-LC, faststart.

| asset | duration | SHA256 | QA note |
|---|---:|---|---|
| establish.mp4 | 12.064s | `6be40eb4aa8a86aea6ee4abc11c415116b8c2f8733136b6a7d0ba51368b3e0e4` | Existing bundled opening walk |
| hesitate.mp4 | 12.11s | `81da1f8dd8464b837e9e03410f4110c3403f647bcf93435ecd4e7f434872dbdb` | Replaced prior NG; Sydney close-up and rightward eyeline, target girl offscreen |
| call.mp4 | 12.1s | `20e1754714f4c2f78a798f68c53ff6020b38a508ab44b73320c59821d3ee4923` | tea pickup and Leah return-to-side action visible; accepted anchor |
| work.mp4 | 6.75s | `04ad92d73867271f7abcbb0a9b215752d0c0f4fb92cd58aeeab4b070230d3d9c` | source trimmed by 3.3s; subtitle timestamps must subtract 3.3s |
| craft.mp4 | 18.08s | `2e1cdd6252b1b779f247fb8366489506aa3b06b361fb9e08c069660ebabada6a` | Leah/tea-stall conversation visible |
| concern.mp4 | 8.064s | `e448f3da971b7d2ebb17c40fe82dbfa49aedd925f72219c7a98fadd69068eef1` | Existing bundled Leah concern beat |
| coach.mp4 | 12.042s | `abc46cf7986c09261673732d4847102b4ec1221e5de75cd5baa528e30c623974` | Sydney white dress/glasses/long hair visible |
| tease.mp4 | 10.042s | `0e1efba67fe09ac8915602ae4d73bb411725e47439f77ca630ac8d3c06c183ea` | Leah adult bob/beige jacket/white top visible |
| decline.mp4 | 8.1s | `78673cf19b981e0634b5fd0b4c7b82802e17f24c330168469fa991d5239fe777` | retake passes first-person Leah head-and-shoulders; old NG retained as `video-raw/decline-original-ng.mp4` |
| available.mp4 | 10.11s | `86b2d6ad0e9e689a2f593286f0a3b4ab6c3bbce9955c72c6fa46532ff8e50287` | Leah adult bob/beige jacket/white top visible |
| busy.mp4 | 8.064s | `0c0f95e0292b8a2ab636bab05682ebe05809688fc893d215131a020896413e41` | Leah busy/tea-stall scene bundled |
| opening.mp4 | 14.1s | `71f28a0590a5a0f7658e684995f6b5373292bf335e59fc4a733da7c5e0a5c024` | Leah adult bob/beige jacket/white top; no male foreground hand visible |
| contact.mp4 | 9.28s | `f27fc831791fae27c4f144c4b503447ec1018612141dad9ba1a04a2386a5580b` | Approved crop candidate: source trim 2.8s, crop 768×432 at x=256 then scale 1280×720; 4.7–6.7s window checked every 0.25s, no viewer QR phone/hand; Leah's own phone remains allowed |
| date.mp4 | 22.042s | `11e90edd377593b01d1ca3597545ef08e8aff9fae751a2c84b34dc20107f3333` | Leah/tea-cup ceramic-stall scene; no male hand or scene mutation. Continuity deviation: the prompt's explicit walk-away ending is not visible; final sampled frames remain on Leah by the stall |

`first_today` has a separate approved trim that keeps source `0–1.3s` with a final `0.02s` fade; it is not a 1.3s front trim. `work` is trimmed from the source at offset 3.3s. Raw source videos remain in local `video-raw/` for QA evidence and are excluded from the formal bundle. Contact sheets and endframes are under `artifact/night-market-contact-sheets/`.

The superseded QR version is retained as `video-raw/contact-original-qr-ng.mp4`. The approved contact crop is softer from 768×432 upscaling. All 14 video beats are now bundled; see `media-manifest.json` for the complete video/audio/poster inventory and hashes.

## Manifest cross-check

Read-only audit on 2026-09-07 compared all 35 manifest items with the current bundle: every file exists, and bytes plus SHA-256 match `media-manifest.json`. The combined manifest payload is 32,580,715 bytes (32.58 MB decimal; 31.07 MiB) after final normalization.

Caption end-time audit was re-run against the current `lib/features/night_market/data/night_market_story.dart` beat blocks. All 14 video beats have caption ends at or before their actual final media durations: `establish` 8.000/12.064 s, `hesitate` 10.920/12.110 s, `opening` 13.800/14.100 s, `concern` 7.720/8.064 s, `work` 6.440/6.750 s, `craft` 16.200/18.080 s, `tease` 8.220/10.042 s, `call` 7.440/12.100 s, `available` 9.940/10.110 s, `date` 16.600/22.042 s, `busy` 7.740/8.064 s, `contact` 7.480/9.280 s, `decline` 4.220/8.100 s, `coach` 11.400/12.042 s. No caption overflow remains. This check reads actual caption calls and ffprobe durations; it does not modify source or media.

## Audio normalization verification

On 2026-09-07, 14 MP4 audio tracks and 14 choice MP3 files were processed with two-pass `ffmpeg loudnorm` targeting `I=-18 LUFS`, `TP=-1.5 dBTP`, `LRA=11`. MP4 video streams were copied without re-encoding; normalized MP4 audio is AAC 48 kHz with faststart. `market-bed.mp3`, `hesitate-heartbeat.wav`, and `ui-cue.wav` were excluded and remain at their pre-normalization hashes.

Final measurement: 28 normalized files ranged from `-19.63` to `-17.89 LUFS` (1.74 dB spread), maximum true peak `-1.55 dBTP`, with no clipping over `0 dBTP`. `decline.mp4` remains lower at `-19.63 LUFS` by design to preserve `-1.55 dBTP` headroom; no fixed gain was applied. Three high MP4 outliers were gently attenuated after the loudnorm pass: `available` −1.34 dB, `opening` −1.15 dB, `hesitate` −0.42 dB.

The final external verification recorded 31/31 media decode passes and matching video stream hashes for all 14 MP4 files, with faststart true for all 14. The refreshed 35-item manifest totals 32,580,715 bytes. Full machine-readable evidence is in `audio-normalization-verification.json` under the external app-review artifact directory.
