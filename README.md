# SMU//PULSE//GRID — Technical, Clinical & Scientific Manual

**Version 0.1.0 · Phase 2 (live logging + analytics)**
A browser-based, follow-along exercise platform that recognises a participant by face, captures their emotional state **before and after** a workout, and tracks head-to-knee movement against a reference instructor video — entirely client-side, served as static files. Finished sessions are logged live to a Google Sheet and visualised in an R Shiny analytics dashboard.

> **Indicative wellness tool, not a medical device.** All emotion, stress, calorie and movement outputs are indicative cues derived from consumer-grade computer vision. They are **not** a diagnosis and must not be used for clinical decision-making. See [§12 Limitations & Disclaimers](#12-limitations--disclaimers).

---

## Live links

| Surface | URL | What it is |
| --- | --- | --- |
| **Kiosk app** | https://aaron-chen-angus.github.io/smu-pulsegrid | The participant-facing follow-along app. Opens at face **Sign In**. |
| **Admin console** | https://aaron-chen-angus.github.io/smu-pulsegrid/admin.html | Operator-only: enrol people, manage the routine library, publish `bank.json`. |
| **R Shiny dashboard** | https://01a10953-fcaf-2d0f-a681-f45028deda33.share.connect.posit.cloud/ | Live analytics over the Google Sheet (overview, session drill-down, emotion, cohort). |
| **Live results (Google Sheet)** | https://docs.google.com/spreadsheets/d/1iYSFfDxljE1kT8cqAjHRvG2QVQ0374ZQRY-_e7cL_k8/edit?usp=sharing | The backing data store: three tabs (`Sessions`, `EmotionScans`, `IntensityTimeline`). |

> The kiosk and admin are served from **GitHub Pages** (static). The dashboard runs on **Posit Connect Cloud**. The three surfaces share one Google Sheet as the single source of truth, written by the kiosk via a Google Apps Script Web App.

---

## Table of contents

1. [Overview & architecture](#1-overview--architecture)
2. [Runtime libraries & models](#2-runtime-libraries--models)
3. [Facial recognition (Sign In / Sign Out)](#3-facial-recognition-sign-in--sign-out)
4. [Emotion sensing & the Stress Indicator](#4-emotion-sensing--the-stress-indicator)
5. [Pose markers & movement intensity](#5-pose-markers--movement-intensity)
6. [Reference comparison (user vs instructor)](#6-reference-comparison-user-vs-instructor)
7. [Energy expenditure (calories)](#7-energy-expenditure-calories)
8. [Session metrics](#8-session-metrics)
9. [Admin console & bank publishing](#9-admin-console--bank-publishing)
10. [Data capture, persistence & Google Sheets logging](#10-data-capture-persistence--google-sheets-logging)
11. [R Shiny analytics dashboard](#11-r-shiny-analytics-dashboard)
12. [Limitations & disclaimers](#12-limitations--disclaimers)
13. [Data dictionary](#13-data-dictionary)
14. [Scientific references (APA)](#14-scientific-references-apa)

---

## 1. Overview & architecture

SMU//PULSE//GRID is a set of static assets with **no build step and no server-side runtime** of its own. The kiosk and admin console are plain HTML/CSS/vanilla JavaScript; the only backend is a Google Apps Script Web App that appends rows to a Google Sheet, and an R Shiny dashboard that reads that Sheet. It is designed desktop-first in landscape (1920×1080 design canvas) and is also responsive to mobile portrait, where the instructor video becomes the forefront element and the webcam + pose skeleton is shown as a draggable picture-in-picture overlay.

### 1.1 System diagram

```
        ┌────────────────────┐        enrol faces,            ┌──────────────────┐
        │   admin.html        │  publish bank.json / routines  │  GitHub repo /    │
        │  (operator console) │ ─────────────────────────────▶ │  GitHub Pages     │
        └────────────────────┘                                 └──────────────────┘
                                                                        │ serves
                                                                        ▼
   participant ──▶ ┌────────────────────┐  reads bank.json, routines.json, references/*
                   │   index.html         │
                   │   (kiosk app)        │  POST session bundle (text/plain, token)
                   └────────────────────┘ ───────────────────────────┐
                                                                      ▼
                                                        ┌──────────────────────────┐
                                                        │  Apps Script Web App       │
                                                        │  (apps-script/Code.gs)     │
                                                        └──────────────────────────┘
                                                                      │ appendRow
                                                                      ▼
                                                        ┌──────────────────────────┐
                                                        │  Google Sheet (3 tabs)     │
                                                        └──────────────────────────┘
                                                                      │ public CSV export
                                                                      ▼
                                                        ┌──────────────────────────┐
                                                        │  R Shiny dashboard         │
                                                        │  (dashboard/app.R)         │
                                                        └──────────────────────────┘
```

### 1.2 Files

| File | Role |
| --- | --- |
| `index.html` | The entire kiosk app: all seven screens, CSS and JavaScript inline. Opens at **Sign In**. |
| `admin.html` | Operator console (separate page): enrol up to **20** people, manage the routine library, publish `bank.json`. No authentication (demo). |
| `config.js` | Single source of truth for every tunable threshold, the active routine, and the Google Sheets URL/token (`window.CONFIG`). |
| `pose-intensity.js` | Shared movement-intensity engine (`window.PoseIntensity`), used identically by the live workout and the offline Reference Builder. |
| `bank.json` | Admin-published enrolment list (name + 128-D descriptor + thumbnail per person). Committed to the public repo; fetched by the kiosk at startup. |
| `routines.json` | Routine catalogue (title, YouTube ID, aspect, trim, reference file, MET range, `active` flag). |
| `references/<routineId>.json` | Pre-computed per-0.5 s instructor intensity for one routine. |
| `reference-builder.html` | Offline tool: a local MP4 → `references/<routineId>.json`. |
| `apps-script/Code.gs` | Google Apps Script backend: receives one session bundle per POST and appends rows to the three Sheet tabs. |
| `dashboard/app.R` | R Shiny analytics dashboard. Reads the Google Sheet via the public CSV export and renders charts with ggplot2. |

### 1.3 Session flow (seven screens)

```
PHOTO_BANK → SIGN_IN → READY → EXERCISE → COMPLETE → SIGN_OUT → SUMMARY
```

The kiosk **boots directly to `SIGN_IN`** — the participant-facing entry point is face login, not enrolment. Enrolment lives in the admin console; the on-device Photo Bank screen still exists but is reached only via a deep link (`#PHOTO_BANK`, the gear icon) for on-device testing.

1. **Photo Bank** *(admin/testing only)* — on-device enrolment (photo + name + optional body mass).
2. **Sign In** — recognise the participant by face against the merged bank, then run a 5 s emotion scan (**phase `in`**).
3. **Ready** — show the routine, confirm camera framing, 5-4-3-2-1 countdown.
4. **Exercise** — play the reference video and track movement in real time.
5. **Session Complete** — headline metrics. (Nothing is persisted here — see [§10.2](#102-when-the-session-is-persisted-and-why).)
6. **Sign Out** — verify identity by face, run a second emotion scan (**phase `out`**).
7. **Summary** — personalised results, In→Out emotion comparison, export, **and the single point at which the finished session is persisted and pushed to the Sheet**.

### 1.4 Privacy model

Face descriptors (128-dimensional vectors) and thumbnails live **only** in the browser's `localStorage` (kiosk and admin) and inside `bank.json` for admin-enrolled people. They are used **only** on-device for matching. Everything that leaves the browser — the JSON/CSV export and the live Google Sheets log — contains **no biometric templates and no images**, only the participant's name and derived numeric metrics (see [§13](#13-data-dictionary)).

### 1.4 Coordinate conventions

- **Face/landmark pixel space:** face-api returns detections in the video element's pixel coordinates.
- **Pose landmark space:** MediaPipe returns 33 landmarks as **normalised** image coordinates `x, y ∈ [0, 1]` plus a `visibility ∈ [0, 1]` score per landmark. Because all pose maths divide by the person's own torso length, intensity is **independent of camera distance and resolution**.
- **Display mapping:** the webcam is shown uncropped (`object-fit: contain`) and mirrored; skeleton overlays mirror the x-axis to match.

---

## 2. Runtime libraries & models

All kiosk/admin libraries are loaded from a pinned CDN (jsDelivr / Google), so there is nothing to install.

| Library | Pinned version | Purpose |
| --- | --- | --- |
| `@vladmandic/face-api` | 1.7.15 | Face detection, 68 landmarks, 128-D descriptor, 7-class expression classifier (kiosk + admin) |
| `@mediapipe/tasks-vision` | 0.10.35 | Pose Landmarker (33 landmarks, VIDEO mode) |
| YouTube IFrame Player API | current | Reference video playback and timing (`getCurrentTime`, `getDuration`) |
| Chart.js | 4 | Live intensity chart and Summary visualisations |
| Web Speech API | browser-native | Spoken greetings/countdown (synthesis) and voice commands (recognition) |

### 2.0 Full tech stack at a glance

| Layer | Technology | Notes |
| --- | --- | --- |
| Kiosk + admin UI | Plain HTML, CSS, vanilla JavaScript | No npm, no bundler, no framework. CDN-only. |
| Face recognition & emotion | `@vladmandic/face-api` 1.7.15 | SSD MobileNet v1 (enrol), TinyFaceDetector (live), Landmark 68, Recognition, Expression |
| Pose tracking | `@mediapipe/tasks-vision` 0.10.35 | BlazePose `pose_landmarker_lite`, VIDEO mode, GPU→CPU fallback |
| Video playback | YouTube IFrame Player API | Reference instructor video + playback clock |
| Charts (app) | Chart.js 4 | Live gauges/timeline and Summary charts |
| Voice | Web Speech API | Synthesis (all browsers) + recognition (Chromium only) |
| Hosting | GitHub Pages | Static kiosk + admin |
| Backend | Google Apps Script Web App | `doPost` appends to the Sheet; `text/plain` transport avoids CORS preflight |
| Data store | Google Sheets (3 tabs) | `Sessions`, `EmotionScans`, `IntensityTimeline` |
| Analytics | R + Shiny + shinydashboard + ggplot2 | Reads the Sheet via public CSV export; hosted on Posit Connect Cloud |

### 2.1 Face models (from the `@vladmandic/face-api` `/model` folder)

- **SSD MobileNet v1** — used for **enrolment** (accurate single-image detection).
- **TinyFaceDetector** (`inputSize 320`) — used for **live** detection at Sign In / Sign Out and the expression scan (fast).
- **Face Landmark 68** — 68-point facial landmark model.
- **Face Recognition** — produces the 128-D descriptor used for identity matching.
- **Face Expression** — produces the 7-class expression probability distribution.

The expression classifier is the FER-style model distributed with face-api, trained on facial-expression datasets; it outputs a softmax distribution over seven categories derived from Ekman's basic-emotion taxonomy (Ekman & Friesen, 1971; Barsoum et al., 2016).

### 2.2 Pose model

- **`pose_landmarker_lite`** (float16) in **VIDEO** mode, GPU delegate with automatic CPU fallback. MediaPipe BlazePose produces 33 body landmarks with per-landmark visibility (Bazarevsky et al., 2020; Lugaresi et al., 2019). The spec permits swapping to `pose_landmarker_full` if accuracy is insufficient.

> **Timestamp note (engineering).** MediaPipe `detectForVideo` requires strictly increasing timestamps for the lifetime of a landmarker instance. Because one landmarker is shared across the Ready and Exercise screens, the app supplies a single global monotonic timestamp counter.

---

## 3. Facial recognition (Sign In / Sign Out)

### 3.1 Enrolment (Photo Bank)

For each uploaded photo the app detects **exactly one** face (rejecting zero or multiple), computes a **128-D descriptor**, and stores a 160×200 thumbnail. Small images are upscaled before detection so the detectable face reaches a usable size (minimum face height 80 px).

### 3.2 Live recognition

At Sign In the app:

1. Displays a guide circle; shows directional hints until the face is centred and sized appropriately (between 35% and 90% of the circle diameter), then holds steady for **1 s**.
2. Collects **10 consecutive frames**, computes a **per-dimension median** descriptor (robust to single-frame noise).
3. Compares that median to each enrolled descriptor using **Euclidean distance** and accepts the best match if distance ≤ **0.60**.
4. Reports confidence as `100 × (1 − distance)%`.
5. Prompts to improve lighting if mean face luminance < 60/255.

If no enrolled descriptor is within 0.60, the participant proceeds via a **typed name** (default body mass 65 kg). The median descriptor captured at Sign In is retained in session memory so that **Sign Out can verify the same person** (threshold 0.60), with a logged override option.

The 0.60 Euclidean threshold on 128-D FaceNet-style embeddings follows the convention established by the underlying recognition model and common practice for this descriptor family (Schroff et al., 2015).

---

## 4. Emotion sensing & the Stress Indicator

### 4.1 What is measured — two scans per session (in & out)

Every session produces **two** emotion scans, driven by one shared implementation (`PULSE.emotionScan.run(sectionEl, phase)`) so both are measured identically:

- **Phase `in`** — captured at **Sign In**, immediately after the face is recognised, before the workout. Stored in session memory as `session.emotionIn`.
- **Phase `out`** — captured at **Sign Out**, after identity is re-verified, after the workout. Stored as `session.emotionOut`.

During each scan the app samples the **7-class facial-expression probability distribution** at ≥ 5 Hz for 5 s, discarding frames whose face-detection confidence is below 0.6 and requiring at least 15 valid frames (a scan with fewer is flagged `insufficient` and the participant may still proceed). The seven classes are:

```
neutral, happy, sad, angry, fearful, disgusted, surprised
```

For each class it records the **mean** and **max** across valid frames. Capturing the same distribution at both ends lets the Summary and the dashboard compute the **In→Out change** — the emotion delta per class, the valence shift, and the stress-level transition. The `in` and `out` scans become the two rows of the `EmotionScans` table for that `session_id` (see [§10](#10-data-capture-persistence--google-sheets-logging) and [§13.2](#132-table-emotionscans-two-rows-per-session-phase-in-and-out)).

### 4.2 Derived affect indices

Let `mean(x)` be the mean probability of class `x` across valid frames.

| Index | Definition | Range |
| --- | --- | --- |
| **Negative affect (NA)** | `mean(sad) + mean(angry) + mean(fearful) + mean(disgusted)` | 0 … 4 (practically ≪ 1) |
| **Valence** | `clip(mean(happy) − NA, −1, +1)` | −1 … +1 |
| **Arousal proxy** | `clip(1 − mean(neutral), 0, 1)` | 0 … 1 |
| **Dominant emotion** | `argmax` over the seven class means | categorical |

The valence/arousal framing follows the circumplex model of affect (Russell, 1980). Arousal here is a **proxy** — the degree to which the face departs from neutral — not a physiological arousal measurement.

### 4.3 Stress Indicator (three levels)

The Stress Indicator is a **transparent, configurable heuristic**, not a validated clinical instrument. There are no established population norms for webcam expression-classifier probabilities, so the thresholds below encode the assumption that a relaxed, neutral face in good lighting scores low on all negative classes. All thresholds live in `config.js → emotion.stress`.

| Level | Trigger (any condition) |
| --- | --- |
| **Normal** | `NA < 0.25` **and** every single negative mean `< 0.30` |
| **Elevated** | `NA ∈ [0.25, 0.45]`, **or** any single negative mean `∈ [0.30, 0.50]` |
| **High** | `NA > 0.45`, **or** any single negative mean `> 0.50` in **≥ 40%** of frames |

At Elevated or High, the app names the **driver** — the negative emotion with the highest mean (e.g. "elevated sadness", "high anger") — and this becomes the plain-language discomfort statement on the Summary page.

> **Scientific caveat.** Automated facial-expression recognition infers *displayed* expressions, which do not map one-to-one onto *felt* emotion; the validity of inferring internal states from facial configurations is actively debated (Barrett et al., 2019). Treat the Stress Indicator as a coarse, indicative signal only.

---

## 5. Pose markers & movement intensity

### 5.1 Landmarks evaluated

Of MediaPipe's 33 landmarks, the intensity engine evaluates the following, grouped into **upper body** and **lower body**. A landmark contributes to a frame only when its `visibility ≥ 0.5`.

| Group | Landmark | MediaPipe index | Weight |
| --- | --- | --- | --- |
| Upper | Left shoulder | 11 | 0.5 |
| Upper | Right shoulder | 12 | 0.5 |
| Upper | Left elbow | 13 | 0.8 |
| Upper | Right elbow | 14 | 0.8 |
| Upper | Left wrist | 15 | 1.0 |
| Upper | Right wrist | 16 | 1.0 |
| Lower | Left hip | 23 | 0.6 |
| Lower | Right hip | 24 | 0.6 |
| Lower | Left knee | 25 | 1.0 |
| Lower | Right knee | 26 | 1.0 |
| Lower (bonus) | Left ankle | 27 | 1.0 |
| Lower (bonus) | Right ankle | 28 | 1.0 |

**Ankles are a bonus group**: they are included only when both are visible, and are excluded otherwise. This is deliberate — participants are framed head-to-knee, so the lower-body score is driven by hips and knees. The Reference Builder applies the identical rule, so the instructor and the user are scored the same way.

Additional landmarks used elsewhere: the **nose (0)** and **shoulders/hips** are used for the Ready-screen framing check (presence + distance), and shoulders/hips define the torso length below.

### 5.2 Torso-normalised joint speed

For a joint *j* with position `p_j(t)` and the time step `Δt` between frames, instantaneous normalised speed is:

```
v_j(t) = ‖ p_j(t) − p_j(t−Δt) ‖  /  ( Δt · L(t) )
```

where **L(t)** is the **torso length** — the Euclidean distance between the shoulder midpoint and the hip midpoint — smoothed with a **2 s moving median**. Dividing by L makes the measure scale-invariant (independent of how close the person stands or how the instructor was filmed).

### 5.3 Group intensity (0–100)

For each group, the group speed `S_group` is the **weighted mean** of `v_j` over visible joints (using the weights above), then smoothed with an exponential moving average (**α = 0.2**). It is mapped to a 0–100 scale by a saturation constant **S_max = 4.0** torso-lengths per second:

```
I_group   = 100 · min( 1, S_group / S_max )
I_overall = 0.5 · I_upper + 0.5 · I_lower
```

A frame in which fewer than 50% of a group's joints are visible marks that group as **missing** for that frame. If no previous frame or no valid torso length exists, the frame yields no intensity.

### 5.4 Binning

Per-frame intensities are aggregated into fixed **0.5 s bins** (the mean of contributing frames). A bin with no contributing frames for a group is stored as `null` (missing). These bins drive the live chart, the comparison metrics, and the exported `IntensityTimeline`.

The joint-speed-as-effort approach and torso normalisation are consistent with markerless-pose validation work showing MediaPipe/BlazePose kinematics track reference systems well enough for relative movement quantification, while cautioning against treating them as laboratory-grade (Bazarevsky et al., 2020; Lugaresi et al., 2019).

### 5.5 Out-of-frame behaviour

The workout never auto-pauses on loss of tracking. Once the body has been detected at least once ("calibrated"), frames with no detected body are recorded as **zero** movement (not gaps), and a non-blocking "step into frame" hint appears. This keeps the timeline continuous and the video playing.

---

## 6. Reference comparison (user vs instructor)

The Reference Builder runs the **identical** `pose-intensity` pipeline over the instructor's local MP4 (seeking frame-by-frame at 15 fps) and stores per-0.5 s `upper[]`, `lower[]`, `overall[]` arrays in `references/<routineId>.json`. At runtime the reference value for the current moment is looked up at:

```
index = floor( player.getCurrentTime() / binSec )     (binSec = 0.5)
```

| Metric | Definition | Where shown |
| --- | --- | --- |
| **Match % (per bin)** | `100 × (1 − min(1, |u − r| / max(r, 10)))` | Live readout (smoothed over 3 s) |
| **Session Match %** | Mean per-bin Match % over bins where `r > 5` | Summary |
| **Effort ratio (per group)** | `100 × Σu / Σr` | Summary (e.g. "Upper body 92% of instructor") |
| **Sync score** | Best Pearson *r* between user and reference overall series across lags −1.0 … +1.0 s, scaled to 0–100 | Summary |
| **Time in zone** | % of bins where `u` is within ±15% of `r` | Summary |

where `u` is the user's binned intensity and `r` the reference's. The `max(r, 10)` floor prevents divide-by-small-number noise when the instructor is nearly still. The **sync score searches lags** because a 0.5–1 s reaction delay is expected when following a video; cross-correlation lag selection is standard for aligning delayed physiological/behavioural signals.

If the reference file is missing, comparison metrics display "—" and export blank — the session still runs and records user intensity.

---

## 7. Energy expenditure (calories)

Calories use the ACSM-style MET framework (Jetté et al., 1990; Ainsworth et al., 2011). The MET for each 0.5 s bin is interpolated between the routine's light and vigorous MET values (defaults 2.8 and 8.0, approximate Compendium values for calisthenics) by that bin's overall intensity:

```
MET_bin = MET_min + (MET_max − MET_min) · ( I_overall / 100 )

kcal    = Σ_bins  MET_bin · 3.5 · body_mass_kg · (Δt_min / 200)
```

with `Δt_min = binSec / 60`. Computing per bin means short bursts contribute correctly. Body mass defaults to 65 kg when not provided (flagged as `weight_defaulted = TRUE`). This is an **estimate**: it uses a generic MET model, not individual calorimetry, and does not account for fitness, age, or metabolic variation.

---

## 8. Session metrics

Shown on Session Complete and Summary, computed from the recorded timeline:

| Metric | Definition |
| --- | --- |
| **Duration** | `number of bins × 0.5 s` |
| **Active %** | % of bins with overall intensity > 10 |
| **Upper/Lower avg, peak** | Mean and maximum of the group's binned intensity |
| **Upper/Lower effort %** | `100 × Σu / Σr` for that group |
| **Overall avg** | Mean overall intensity |
| **Session Match %** | See [§6](#6-reference-comparison-user-vs-instructor) |
| **Sync score** | See [§6](#6-reference-comparison-user-vs-instructor) |
| **Time in zone** | See [§6](#6-reference-comparison-user-vs-instructor) |
| **Best 15 s segment** | The 15 s window (30 bins) with the highest mean Match % |
| **Upper–lower balance** | Rule-based comment comparing the two effort ratios |
| **Emotion change** | Valence delta and stress level In → Out |

---

## 9. Admin console & bank publishing

The admin console (`admin.html`) is a **separate operator-only page**, deliberately kept out of the participant kiosk. It has no authentication (demo context) and three tabs.

### 9.1 People (enrolment)

- Up to **20 person slots**. For each: upload a photo, type a name, optionally set body mass.
- Enrolment runs the same face-api pipeline as the kiosk (SSD MobileNet v1 detection, 128-D descriptor, 160×200 thumbnail), detecting **exactly one** face per photo.
- The result is **Option A**: the admin **downloads `bank.json`**, a plain array of `{ name, weight, thumb, descriptor[128] }`, which is **committed to the public repo**. No MP4s and no raw photos are ever committed — only the derived descriptor and a small thumbnail.

### 9.2 Library (routines)

- Manage the entries in `routines.json` (title, YouTube ID, aspect, trim, reference file, MET range).
- Exactly one routine can be flagged `"active": true`; the kiosk honours that flag first.

### 9.3 Routines resolution order (kiosk)

When the kiosk starts it resolves the routine to play by this priority:

1. a routine flagged `{ "active": true }` in `routines.json` (set by the admin console); else
2. `config.activeRoutineId`; else
3. the first routine in the list.

### 9.4 How the kiosk consumes admin output

At startup the kiosk `fetch`es `bank.json` (`cache: 'no-store'`) and merges it with any on-device Photo Bank entries. People are keyed by name; a **local on-device entry overrides** an admin entry with the same name. This means an operator can enrol a cohort once in admin, commit `bank.json`, and every kiosk device recognises them without local enrolment.

---

## 10. Data capture, persistence & Google Sheets logging

This section documents the end-to-end path from a finished workout to a row in the Sheet — including the specific fix that ensures **both** the `in` and `out` emotion scans are logged.

### 10.1 The session bundle

A finished session is mapped to the three §13 tables by `PULSE.record.toBundle(session)`, producing:

```js
{ sessions: [ …1 row… ],
  emotionScans: [ …in row…, …out row… ],   // built from session.emotionIn & session.emotionOut
  intensityTimeline: [ …one row per 0.5 s bin… ] }
```

`buildEmotionRows` emits a row for `in` whenever `session.emotionIn` exists and a row for `out` whenever `session.emotionOut` exists. Because the `out` scan is only captured at Sign Out, **the bundle is only complete once the participant has reached Sign Out → Summary.**

### 10.2 When the session is persisted — and why

Persistence happens **exactly once, at the Summary screen**, via `PULSE.record.persist(session)` called from the Summary controller's entry.

This is deliberate and is the fix for a logging bug. Persisting at **Session Complete** (earlier, before Sign Out) wrote the row **before** `emotionOut` existed; a dedupe-by-`session_id` guard then blocked the later, complete row — so only `in` scans ever reached the Sheet. The corrected design:

- **Session Complete persists nothing.**
- **Summary persists once.** By then `emotionOut` exists, so the bundle contains both emotion rows.
- The dedupe guard allows **one upgrade**: if a prior saved copy of this `session_id` lacked an `out` scan and the current session now has one, `persist` re-saves and re-posts so the complete record (including `emotionOut`) reaches the Sheet. It upgrades at most once (null → has-out).

Net effect: every completed session logs **two** `EmotionScans` rows (`in` and `out`), and the dashboard's emotion-delta / valence-change charts populate.

### 10.3 Transport to Google Sheets

- `persist` calls `sendToSheets(bundle)`, which `POST`s to the Apps Script Web App URL in `config.js → sheets.url`.
- The body is `JSON.stringify({ token, sessions, emotionScans, intensityTimeline })` sent with `Content-Type: text/plain;charset=utf-8`. Using `text/plain` keeps it a CORS "simple request", so no preflight is sent (Apps Script web apps cannot answer a preflight). The reply JSON is still readable (no `no-cors`).
- The shared `token` must equal `SHEET_TOKEN` in `apps-script/Code.gs`, or the server rejects the POST with `bad token`.
- On the server, `doPost` parses the body, checks the token, and `appendRows` writes each tab in the authoritative column order (writing the header row on first use).

### 10.4 Resilience: offline queue + retry

Logging is **non-blocking** and failure-tolerant:

- If a POST fails (offline, server error, bad reply), the bundle is pushed onto a `localStorage` retry queue (`pulsegrid.sheetsQueue`).
- On the next successful send — and on the next app load — `flushQueue` drains the queue, so sessions captured offline are eventually logged. A session is never lost because the network blipped.
- The kiosk also keeps the last 50 sessions in `localStorage` and offers **JSON / CSV export** of the current or any stored session from the Summary screen, independent of the Sheet.

### 10.5 Deploying the Apps Script backend (one-time)

1. In the Google Sheet: **Extensions → Apps Script**, paste `apps-script/Code.gs`.
2. Set `SHEET_TOKEN` to a long random string and put the same value in `config.js → sheets.token`.
3. **Deploy → New deployment → Web app**; *Execute as: Me*, *Who has access: Anyone*.
4. Copy the `/exec` Web App URL into `config.js → sheets.url`.
5. Visit the URL in a browser — a `doGet` returns `{ ok: true, service: "pulsegrid", tabs: [...] }` to confirm the deployment.

---

## 11. R Shiny analytics dashboard

`dashboard/app.R` is a self-contained Shiny app that visualises the live Sheet. It is hosted on **Posit Connect Cloud** and is a read-only consumer of the data.

### 11.1 How it reads the Sheet

The dashboard does **not** use `googlesheets4::read_sheet` (which returns list-columns that break downstream plotting). Instead it reads each tab via the **public CSV export** endpoint:

```
https://docs.google.com/spreadsheets/d/<SHEET_ID>/gviz/tq?tqx=out:csv&sheet=<tab>
```

with `readr::read_csv(..., col_types = cols(.default = col_character()))`, then coerces every column to a plain character vector (`unlist`) before casting the numeric columns itself. This avoids the `is.character(txt) is not TRUE` htmlwidgets/plotly error seen on Posit Cloud and keeps the data types predictable. The Sheet must be shared as **"Anyone with the link can view"** for the CSV endpoint to work. Data auto-refreshes every 60 s and on a manual **Refresh now** button.

### 11.2 Charting choice

All charts are rendered with **ggplot2 via `renderPlot`**, not plotly — a deliberate decision after plotly's htmlwidgets dependency chain failed on Posit Cloud. Each `renderPlot` is called with `bg = PANEL` so the plot device canvas matches the dark TRON panel (this removes the white strips that `coord_polar` otherwise leaves beside the circular Completion donut).

### 11.3 Tabs

| Tab | Contents |
| --- | --- |
| **Overview** | Value boxes (sessions, unique people, avg match %, total kcal); sessions over time; completion donut; match % distribution; upper-vs-lower effort. |
| **Session drill-down** | Pick a session; duration/kcal/match/sync value boxes; intensity timeline (you vs instructor); emotion In-vs-Out; emotion change (Out − In). |
| **Emotion & stress** | Stress level In vs Out; valence change In→Out; mean emotion profile across all scans. |
| **Cohort analytics** | Match % vs sync scatter (with trend line); average match % per person; correlation heatmap of session metrics. |
| **Raw data** | The three Sheet tabs as searchable tables. |

### 11.4 In/Out dependency

The **emotion change** and **valence change** charts need **both** an `in` and an `out` scan for a session. Before the §10.2 persistence fix the Sheet held only `in` rows, so these charts correctly showed *"Need both scans"*. Once a full run reaches Sign Out → Summary, both rows are logged and these charts populate automatically.

### 11.5 Running / deploying the dashboard

```r
install.packages(c("shiny","shinydashboard","dplyr","tidyr","ggplot2",
                   "DT","lubridate","readr","scales"))
shiny::runApp("dashboard")              # local
# Deploy to Posit Connect Cloud by publishing dashboard/app.R.
```

---

## 12. Limitations & disclaimers

- **Not a medical device.** Emotion, stress, calorie and movement outputs are indicative wellness cues from consumer webcams, not clinical measurements, and must not inform diagnosis or treatment.
- **Displayed vs felt emotion.** Expression classifiers infer displayed facial configurations; these do not reliably indicate internal emotional states (Barrett et al., 2019).
- **No validated norms.** The Stress Indicator thresholds are transparent heuristics, not population-calibrated cut-offs.
- **Pose accuracy.** Single-camera markerless pose is sensitive to lighting, clothing, occlusion, camera height and field of view; derived intensities are relative, not absolute biomechanical quantities.
- **Calorie estimates** use a generic MET model and default body mass when unknown.
- **Lighting & framing** materially affect both recognition and emotion sensing.
- **No authentication on the admin console.** It is a demo tool; anyone with the URL can enrol or edit routines. Do not expose it to untrusted users without adding access control.
- **Public data store.** `bank.json` and the Google Sheet backing the dashboard are world-readable by design in this deployment. They contain names + descriptors (bank) and names + numeric metrics (Sheet), but no images or raw video.
- **Browser support.** Camera, microphone and Web Speech require a secure context (HTTPS or `localhost`); voice recognition is Chromium-only and needs internet. iOS Safari does **not** implement SpeechRecognition, so spoken voice commands do not work on iPhone (an Apple platform limitation).

---

## 13. Data dictionary

Phase 1 exports (and the Phase 2 Google Sheet) use three tables with stable **snake_case** names and **ISO 8601** timestamps in **Asia/Singapore** (`+08:00`). Export JSON writes one object `{ sessions, emotionScans, intensityTimeline }`; Export CSV writes three files. **No descriptors or thumbnails are ever included.**

### 13.1 Table `Sessions` (one row per workout)

| Column | Type | Units / range | Description |
| --- | --- | --- | --- |
| `session_id` | string | — | Unique session identifier (generated at Sign In). |
| `name` | string | — | Participant name (matched or typed). |
| `matched_bank` | boolean | TRUE/FALSE | Whether recognised against the photo bank. |
| `match_distance` | number | ≥ 0 | Median descriptor Euclidean distance at Sign In (lower = closer). |
| `routine_id` | string | — | Routine played. |
| `sign_in_at` | datetime | ISO 8601 +08:00 | Sign In time. |
| `start_at` | datetime | ISO 8601 +08:00 | Workout start (after countdown). |
| `end_at` | datetime | ISO 8601 +08:00 | Workout end. |
| `sign_out_at` | datetime | ISO 8601 +08:00 | Sign Out time. |
| `duration_s` | number | seconds | Tracked duration (bins × 0.5). |
| `completed` | boolean | TRUE/FALSE | FALSE if ended early. |
| `signout_override` | boolean | TRUE/FALSE | TRUE if Sign Out face match was overridden. |
| `active_pct` | number | 0–100 | % of bins with overall intensity > 10. |
| `kcal` | number | kcal | Estimated energy expenditure (§7). |
| `met_mean` | number | METs | Mean per-bin MET. |
| `upper_avg` | number | 0–100 | Mean upper-body intensity. |
| `upper_peak` | number | 0–100 | Peak upper-body intensity. |
| `upper_effort_pct` | number | % | Upper effort ratio vs instructor. |
| `lower_avg` | number | 0–100 | Mean lower-body intensity. |
| `lower_peak` | number | 0–100 | Peak lower-body intensity. |
| `lower_effort_pct` | number | % | Lower effort ratio vs instructor. |
| `overall_avg` | number | 0–100 | Mean overall intensity. |
| `match_pct` | number | 0–100 | Session Match %. |
| `sync_score` | number | 0–100 | Lagged Pearson sync score. |
| `zone_pct` | number | 0–100 | Time in zone. |
| `weight_kg` | number | kg | Body mass used for calories. |
| `weight_defaulted` | boolean | TRUE/FALSE | TRUE if the 65 kg default was used. |
| `app_version` | string | — | Build version. |

### 13.2 Table `EmotionScans` (two rows per session: phase `in` and `out`)

| Column | Type | Units / range | Description |
| --- | --- | --- | --- |
| `session_id` | string | — | Foreign key to `Sessions`. |
| `name` | string | — | Participant name. |
| `phase` | string | `in` / `out` | Sign In or Sign Out scan. |
| `scanned_at` | datetime | ISO 8601 +08:00 | Scan time. |
| `frames` | integer | count | Valid frames used. |
| `neutral` | number | 0–1 | Mean probability. |
| `happy` | number | 0–1 | Mean probability. |
| `sad` | number | 0–1 | Mean probability. |
| `angry` | number | 0–1 | Mean probability. |
| `fearful` | number | 0–1 | Mean probability. |
| `disgusted` | number | 0–1 | Mean probability. |
| `surprised` | number | 0–1 | Mean probability. |
| `dominant` | string | class name | Highest-mean emotion. |
| `valence` | number | −1 … +1 | `mean(happy) − NA`. |
| `arousal` | number | 0 … 1 | `1 − mean(neutral)`. |
| `neg_affect` | number | ≥ 0 | NA = sum of four negative means. |
| `stress_level` | string | Normal/Elevated/High | Stress Indicator level. |
| `stress_driver` | string | — | Driver phrase at Elevated/High (else blank). |

### 13.3 Table `IntensityTimeline` (one row per 0.5 s bin)

| Column | Type | Units / range | Description |
| --- | --- | --- | --- |
| `session_id` | string | — | Foreign key to `Sessions`. |
| `t_s` | number | seconds | Bin start time (0, 0.5, 1.0 …). |
| `user_upper` | number \| null | 0–100 | User upper-body intensity (null if missing). |
| `user_lower` | number \| null | 0–100 | User lower-body intensity. |
| `user_overall` | number \| null | 0–100 | User overall intensity. |
| `ref_upper` | number \| null | 0–100 | Reference upper-body intensity. |
| `ref_lower` | number \| null | 0–100 | Reference lower-body intensity. |
| `ref_overall` | number \| null | 0–100 | Reference overall intensity. |
| `match_pct` | number \| null | 0–100 | Per-bin Match %. |

### 13.4 Underlying raw/engine values (not exported directly)

These feed the exported metrics and are documented for completeness.

| Symbol | Meaning | Source |
| --- | --- | --- |
| `p_j(t)` | Normalised position of landmark *j* | MediaPipe |
| `visibility_j` | Per-landmark visibility 0–1 | MediaPipe |
| `L(t)` | Torso length (shoulder-mid to hip-mid), 2 s median | engine |
| `v_j(t)` | Torso-normalised joint speed | engine |
| `S_group` | Weighted-mean group speed, EMA α 0.2 | engine |
| `expr_k(frame)` | Per-frame probability of emotion *k* | face-api |
| `descriptor[128]` | Face embedding (browser-only, never exported) | face-api |

### 13.5 Key constants (from `config.js`)

| Constant | Value | Used for |
| --- | --- | --- |
| `recognition.matchThreshold` | 0.60 | Face match acceptance |
| `recognition.matchFrames` | 10 | Frames per Sign In match |
| `emotion.sampleHz` / `scanSeconds` / `minValidFrames` | 5 / 5 / 15 | Emotion sampling |
| `emotion.stress.*` | 0.25 / 0.45 / 0.30 / 0.50 / 0.40 | Stress thresholds |
| `intensity.sMax` | 4.0 | Intensity saturation |
| `intensity.emaAlpha` | 0.2 | Group-speed smoothing |
| `intensity.torsoMedianSeconds` | 2 | Torso-length window |
| `intensity.binSeconds` | 0.5 | Binning |
| `intensity.minVisibility` | 0.5 | Joint inclusion |
| `comparison.matchFloor` | 10 | Match % denominator floor |
| `comparison.syncLagSeconds` | 1.0 | Sync lag search range |
| `comparison.inZonePct` | 0.15 | Time-in-zone band |
| `calories.metMin/Max` | 2.8 / 8.0 | MET interpolation |

---

## 14. Scientific references (APA)

Ainsworth, B. E., Haskell, W. L., Herrmann, S. D., Meckes, N., Bassett, D. R., Tudor-Locke, C., Greer, J. L., Vezina, J., Whitt-Glover, M. C., & Leon, A. S. (2011). 2011 Compendium of Physical Activities: A second update of codes and MET values. *Medicine & Science in Sports & Exercise, 43*(8), 1575–1581. https://doi.org/10.1249/MSS.0b013e31821ece12

Barrett, L. F., Adolphs, R., Marsella, S., Martinez, A. M., & Pollak, S. D. (2019). Emotional expressions reconsidered: Challenges to inferring emotion from human facial movements. *Psychological Science in the Public Interest, 20*(1), 1–68. https://doi.org/10.1177/1529100619832930

Barsoum, E., Zhang, C., Canton Ferrer, C., & Zhang, Z. (2016). Training deep networks for facial expression recognition with crowd-sourced label distribution. In *Proceedings of the 18th ACM International Conference on Multimodal Interaction* (pp. 279–283). Association for Computing Machinery. https://doi.org/10.1145/2993148.2993165

Bazarevsky, V., Grishchenko, I., Raveendran, K., Zhu, T., Zhang, F., & Grundmann, M. (2020). BlazePose: On-device real-time body pose tracking. *arXiv*. https://arxiv.org/abs/2006.10204

Ekman, P., & Friesen, W. V. (1971). Constants across cultures in the face and emotion. *Journal of Personality and Social Psychology, 17*(2), 124–129. https://doi.org/10.1037/h0030377

Jetté, M., Sidney, K., & Blümchen, G. (1990). Metabolic equivalents (METS) in exercise testing, exercise prescription, and evaluation of functional capacity. *Clinical Cardiology, 13*(8), 555–565. https://doi.org/10.1002/clc.4960130809

Lugaresi, C., Tang, J., Nash, H., McClanahan, C., Uboweja, E., Hays, M., Zhang, F., Chang, C.-L., Yong, M. G., Lee, J., Chang, W.-T., Hua, W., Georg, M., & Grundmann, M. (2019). MediaPipe: A framework for building perception pipelines. *arXiv*. https://arxiv.org/abs/1906.08172

Russell, J. A. (1980). A circumplex model of affect. *Journal of Personality and Social Psychology, 39*(6), 1161–1178. https://doi.org/10.1037/h0077714

Schroff, F., Kalenichenko, D., & Philbin, J. (2015). FaceNet: A unified embedding for face recognition and clustering. In *Proceedings of the IEEE Conference on Computer Vision and Pattern Recognition* (pp. 815–823). IEEE. https://doi.org/10.1109/CVPR.2015.7298682

---

*SMU//PULSE//GRID — Phase 2 (static kiosk + admin on GitHub Pages, Google Sheets live logging, R Shiny analytics on Posit Connect Cloud). This manual documents indicative wellness functionality for research and demonstration. It is not a certified medical or diagnostic system.*
