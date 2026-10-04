/* PULSE//GRID — config.js
 * Thresholds, active routine ID and Phase 2 Sheets settings (design §3.1).
 * Plain global object; no modules, no build step. Loaded before the app in index.html.
 * Values here are the single source of truth for tunable constants so later tasks
 * (T2–T12) read from CONFIG rather than hard-coding numbers.
 */
window.CONFIG = {
  appVersion: '0.1.0',

  // Active routine (R10). routines.json is the list; this picks the default.
  activeRoutineId: 'test90',

  // --- CDN libraries (pinned; design §3.2) ---
  cdn: {
    // @vladmandic/face-api 1.7.15 UMD build + models from the package /model folder.
    faceApiScript: 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@1.7.15/dist/face-api.js',
    faceApiModels: 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@1.7.15/model',
    // @mediapipe/tasks-vision 0.10.35 ESM bundle + wasm fileset for Pose Landmarker.
    mediapipeBundle: 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35',
    mediapipeWasm: 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/wasm'
  },

  // --- MediaPipe Pose Landmarker (R5, §3.2) ---
  pose: {
    // pose_landmarker_lite; the spec allows falling back to _full if accuracy is poor.
    modelLite: 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task',
    modelFull: 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task',
    numPoses: 1,
    delegate: 'GPU',            // falls back to CPU automatically if GPU unavailable
    minPoseDetectionConfidence: 0.5,
    minPosePresenceConfidence: 0.5,
    minTrackingConfidence: 0.5,
    referenceFps: 15            // Reference Builder frame-step rate (§3.5)
  },

  // --- Face model loading (R1, §3.2) ---
  face: {
    tinyInputSize: 320,          // TinyFaceDetector inputSize for live detection
    modelLoadRetries: 3,         // retry model fetch 3x with backoff (§3.12)
    modelLoadBackoffMs: 800,
    enrolMinFaceHeight: 80,      // R1.5: passport-size minimum face height (px)
    upscaleTargetFace: 160,      // upscale small images so faces reach ~this height
    thumbW: 160,                 // R1.2: thumbnail dimensions
    thumbH: 200
  },

  // --- Face recognition / Sign In (R2) ---
  recognition: {
    matchThreshold: 0.60,      // max median descriptor distance to accept a match
    matchFrames: 10,           // consecutive frames compared at Sign In
    faceMinPctOfCircle: 0.35,  // face too small below this fraction of guide circle
    faceMaxPctOfCircle: 0.90,  // face too large above this
    holdSteadyMs: 1000,        // centred+sized this long before scan starts
    minFaceLuminance: 60,      // mean face luminance (0-255) below this = too dark
    defaultWeightKg: 65        // typed-name guests default weight
  },

  // --- Emotion scan (R3 / §3.6) ---
  emotion: {
    sampleHz: 5,               // minimum sampling rate
    scanSeconds: 5,
    minValidFrames: 15,
    minFaceConfidence: 0.6,    // discard frames below this detection confidence
    stress: {
      // Negative affect NA = mean(sad)+mean(angry)+mean(fearful)+mean(disgusted)
      naElevated: 0.25,        // NA at/above -> at least Elevated
      naHigh: 0.45,            // NA above -> High
      singleElevated: 0.30,    // any single negative mean at/above -> Elevated
      singleHigh: 0.50,        // any single negative mean above -> High (in >=40% frames)
      highFrameFraction: 0.40
    }
  },

  // --- Movement intensity (§3.4) ---
  intensity: {
    sMax: 4.0,                 // saturation: torso lengths/sec mapped to 100
    emaAlpha: 0.2,             // group speed smoothing
    torsoMedianSeconds: 2,     // torso-length moving-median window
    binSeconds: 0.5,           // downsample bin for comparison/logging
    minVisibility: 0.5,        // per-joint visibility threshold
    minGroupVisibleFraction: 0.5
  },

  // --- Comparison / Match (§3.5) ---
  comparison: {
    matchFloor: 10,            // r floor in Match % formula
    matchSmoothingSeconds: 3,
    sessionMatchMinRef: 5,     // only bins with r > this count toward session match
    syncLagSeconds: 1.0,       // Pearson search range -lag..+lag
    inZonePct: 0.15            // +/- band for time-in-zone and "In sync!"
  },

  // --- Exercise coaching cues (R5) ---
  coaching: {
    belowRefPct: 0.60,         // below 60% of reference ...
    belowRefSeconds: 3,        // ... for 3s -> "Pick it up!"
    outOfFrameSeconds: 5       // leave frame >5s -> pause
  },

  // --- Camera framing (R12 / §3.13) ---
  camera: {
    preferredWidth: 1280,      // try 4:3 first
    preferredHeight: 960,
    fallbackWidth: 1280,
    fallbackHeight: 720,
    shoulderPctMin: 0.12,      // "Good" distance: shoulders 12-20% of frame width
    shoulderPctMax: 0.20
  },

  // --- Calories (§3.7) ---
  calories: {
    metMinDefault: 2.8,
    metMaxDefault: 8.0
  },

  // --- Storage (R9) ---
  storage: {
    bankKey: 'pulsegrid.bank',
    sessionsKey: 'pulsegrid.sessions',
    maxSessions: 50
  },

  // --- Locale / time (R9.3) ---
  locale: {
    speechLang: 'en-SG',
    speechLangFallback: 'en-US',
    timeZone: 'Asia/Singapore'
  },

  // --- Phase 2 Google Sheets live logging (§3.9) ---
  // url = the Apps Script Web App /exec URL.
  // token = MUST match SHEET_TOKEN in apps-script/Code.gs exactly, or posts are
  //         rejected with "bad token". Update this to the string you set.
  sheets: {
    url: 'https://script.google.com/macros/s/AKfycbzTsz2fM1388oQFDSv7HGkFGYk7UeFFWd6Wngvwp1AU4uPp6maSOb1MnVerR5Fsrn6Wsg/exec',
    token: 'smupg-7h3Qx9K2mNp4'
  }
};
