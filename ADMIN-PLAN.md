# SMU//PULSE//GRID — Admin Site: Assessment & Implementation Plan

This document assesses how to split the project into a **public kiosk app** (face sign-in → emotion scan → exercise → sign-out → summary, with voice control) and a separate **admin console** that manages enrolment and routines. It is a plan to review and approve — no code is changed by this document.

---

## 1. What the admin needs to do

1. **Enrol people** — upload a photo + name (+ optional body mass) so the kiosk recognises them at Sign In.
2. **Manage exercise videos** — upload a 9:16 MP4, run pose analysis once to produce `reference.json`, and store the video.
3. **Select the active routine** — choose which exercise the kiosk shows after a user signs in.
4. **(Optionally) view data** — but live data already flows to Google Sheets (Task 3), so dashboards live there / in R Shiny.

The kiosk app then becomes "sign-in-first": no public Photo Bank screen.

---

## 2. The core architectural decision: where do face descriptors live?

Today, enrolment happens **in the kiosk browser** and the 128-D descriptors sit in that browser's `localStorage`. `localStorage` is **per-device, per-origin** — an admin on their laptop cannot populate the kiosk's `localStorage`. So to move enrolment to an admin site, the enrolled bank must become a **shared artifact both sites can read**. Three realistic options:

### Option A — Committed `bank.json` in the repo (simplest, no backend)
- The admin console computes each descriptor **in the browser** (reusing the existing face-api enrolment code) and **downloads a `bank.json`** containing `[{ name, weight, thumb(dataURL), descriptor[128] }]`.
- You commit `bank.json` to the GitHub repo (or upload via the web UI, exactly like `references/test90.json`).
- The kiosk `index.html` **fetches `bank.json` on load** instead of reading `localStorage`.
- **Pros:** zero backend, no installs, fits the current GitHub Pages model, descriptors stay out of any third-party service.
- **Cons:** enrolment is not "live" — you re-generate and re-commit `bank.json` when people change. Thumbnails as data URLs make the file larger (a 5-person bank is still tiny, ~100–300 KB).
- **Privacy note:** committing descriptors + thumbnails to a public repo publishes them. For a class/research setting this may be acceptable; if not, keep the repo private or use Option B/C.

### Option B — Google Drive + Apps Script (matches your Drive request)
- The admin console uploads the photo and name; an **Apps Script Web App** (same pattern as the Sheets backend) stores the **image in a Drive folder** and appends an **enrolment row** (name, weight, Drive file ID, and the browser-computed descriptor) to an `Enrolments` sheet/Drive JSON.
- The kiosk fetches the enrolment list (a published JSON endpoint from Apps Script) on load and builds its recognition bank from it.
- **Pros:** live updates without committing to Git; images organised in Drive; one Google project already in use for Sheets.
- **Cons:** needs the Apps Script Web App and careful sharing settings; Drive image serving has quirks (use the Apps Script to return the stored thumbnail/descriptor JSON rather than hotlinking Drive images). Descriptors still computed in-browser (face-api doesn't run in Apps Script).
- **Important:** descriptors must still be computed **client-side** (in the admin browser) because face-api needs a browser/WebGL. Apps Script only **stores** what the admin browser computed.

### Option C — A real backend (Firebase/Supabase) — out of scope for Phase 1/2
- Proper auth, a database of descriptors, admin roles. Most robust, but introduces a hosted backend and installs, which contradicts the project's "no backend, static hosting" constraint. Recommend only if the programme grows beyond a kiosk.

**Recommendation:** **Option A for immediate use** (fastest, fits the no-backend model), with **Option B as the upgrade** once the Apps Script project is already set up for Sheets. The admin console can support **both**: a "Download bank.json" button (A) and a "Push to Drive" button (B).

---

## 3. Proposed structure: one admin console (`admin.html`)

Extend the existing `reference-builder.html` into a tabbed **`admin.html`** (or keep them separate and link). It is an offline/privileged tool, so it may scroll and need not be TRON-strict.

```
admin.html
├── Tab 1 · People          (enrol photos + names  → bank.json / Drive)
├── Tab 2 · Exercise Library (upload 9:16 MP4 → reference.json; list routines)
└── Tab 3 · Active Routine   (pick which routine the kiosk shows; writes routines.json / active flag)
```

### Tab 1 · People (enrolment)
- Reuses the **existing** face-api enrolment pipeline already in `index.html` (single-face check, 160×200 thumbnail, 128-D descriptor).
- UI: 5+ rows, each with drop-photo + name + weight, a "Face OK/rejected" status.
- Outputs:
  - **Download `bank.json`** (Option A), and/or
  - **Push to Drive** via Apps Script (Option B).
- The kiosk's current Photo Bank code already knows this exact record shape, so the kiosk change is only "load from `bank.json`/endpoint instead of `localStorage`."

### Tab 2 · Exercise Library (reference builder)
- This is today's `reference-builder.html`, generalised:
  - Pick a local 9:16 MP4, enter routine metadata (id, title, YouTube ID for playback, trim, MET range).
  - Run the existing frame-stepped pose analysis → **download `references/<id>.json`**.
  - Enforce/confirm 9:16 aspect on load (warn if not vertical).
- Video storage: the MP4 itself is **never committed** (steering rule). For playback the kiosk uses the **YouTube ID** (as now). Google Drive can hold the master MP4 for your records; it is not used at runtime.
- Output: `references/<id>.json` + a `routines.json` entry.

### Tab 3 · Active Routine
- Lists all routines from `routines.json`; the admin picks the active one.
- Writes `config.js`'s `activeRoutineId` (or an `active: true` flag in `routines.json`). In the no-backend model this is a **download `routines.json` / `config.js`** that you commit; in the Drive model it's a value the kiosk reads from the endpoint.

---

## 4. Kiosk app changes (small, well-scoped)

1. **Make Photo Bank admin-only / hidden.** Flow starts at Sign In. The gear icon on each screen can route to a passcode-gated Photo Bank, or be removed from the public build.
2. **Load the bank at startup** from `bank.json` (Option A) or the Apps Script endpoint (Option B), with `localStorage` as a cache/fallback. One new loader in the bank module (`PULSE.bank`), ~15 lines.
3. **Load the active routine** the same way (already reads `routines.json`; just honour an `active` flag or a config value).

None of the recognition, emotion, pose, comparison or export logic changes — only the **source** of the bank and the **entry screen**.

---

## 5. Google Drive storage model (Option B specifics)

- Create one Drive folder, e.g. `PULSEGRID/enrolments/` for thumbnails and `PULSEGRID/videos/` for master MP4s.
- The Apps Script Web App (extend `apps-script/Code.gs`):
  - `doPost` with `action: 'enrol'` → save thumbnail (base64) to Drive, append `{name, weight, descriptor, driveFileId, enrolled_at}` to an `Enrolments` sheet.
  - `doGet` with `?action=bank` → return the current enrolment list as JSON for the kiosk.
- Sharing: the Web App runs **Execute as Me / Anyone**, so the kiosk can read without a login. Keep the Drive folder private; expose only the JSON the kiosk needs.
- Still no biometric data leaves to third parties beyond your own Google account.

---

## 6. Implementation phases (suggested order)

| Phase | Deliverable | Backend needed |
| --- | --- | --- |
| 4a | `admin.html` Tab 2 = today's reference-builder, tidied + aspect check | none |
| 4b | `admin.html` Tab 1 = enrolment → **Download `bank.json`** (Option A) | none |
| 4c | Kiosk: load `bank.json` at startup; hide public Photo Bank; start at Sign In | none |
| 4d | `admin.html` Tab 3 = active-routine selector → `routines.json`/config | none |
| 4e (optional) | Apps Script enrolment + Drive storage; kiosk reads bank endpoint (Option B) | Apps Script + Drive |

Phases 4a–4d keep the entire "no backend, static GitHub Pages" model and give you a working admin split. 4e adds live Drive-backed enrolment when you want it.

---

## 7. Open questions for you

1. **Privacy:** is the repo public? If yes, Option A publishes descriptors+thumbnails — acceptable, or must we use Option B from the start?
2. **Who runs the admin console** — just you on a trusted laptop? (Affects whether we add a passcode.)
3. **Video of record:** do you need the master MP4 archived in Drive, or is the YouTube ID enough (the app only needs the YouTube ID + reference.json at runtime)?
4. **Routine switching cadence:** change rarely (commit `routines.json`) or frequently (needs the Drive endpoint)?

Tell me your answers (especially #1 and #2) and I'll build the chosen path — I'd suggest starting with **4a–4c (Option A)** since it needs no new infrastructure and immediately moves enrolment off the kiosk.
