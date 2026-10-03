/* PULSE//GRID — pose-intensity.js
 * Shared movement-intensity engine implementing design §3.4, used identically by
 * the Reference Builder (T6, offline over a local MP4) and live Exercise tracking
 * (T8). Keeping ONE implementation is what guarantees the instructor and the user
 * are scored the same way (ankles excluded, same weights, same normalisation).
 *
 * Plain global (window.PoseIntensity); no modules, no build step. Reads tunables
 * from window.CONFIG.intensity when present, else uses the §3.4 defaults.
 *
 * Input landmarks: an array of 33 MediaPipe pose landmarks, each { x, y, visibility }
 * in normalised [0..1] image coordinates. Because every value is normalised to the
 * frame and then divided by torso length, the score is independent of camera
 * distance and of how the instructor was filmed (§3.4).
 */
(function () {
  'use strict';

  var C = (window.CONFIG && window.CONFIG.intensity) || {};
  var DEF = {
    sMax: C.sMax != null ? C.sMax : 4.0,                 // saturation (torso lengths/sec)
    emaAlpha: C.emaAlpha != null ? C.emaAlpha : 0.2,     // group-speed smoothing
    torsoMedianSeconds: C.torsoMedianSeconds != null ? C.torsoMedianSeconds : 2,
    binSeconds: C.binSeconds != null ? C.binSeconds : 0.5,
    minVisibility: C.minVisibility != null ? C.minVisibility : 0.5,
    minGroupVisibleFraction: C.minGroupVisibleFraction != null ? C.minGroupVisibleFraction : 0.5
  };

  // MediaPipe landmark indices (§3.4).
  var IDX = {
    shoulderL: 11, shoulderR: 12,
    elbowL: 13, elbowR: 14,
    wristL: 15, wristR: 16,
    hipL: 23, hipR: 24,
    kneeL: 25, kneeR: 26,
    ankleL: 27, ankleR: 28
  };

  // Group definitions with per-joint weights (§3.4). Ankles are a "bonus" group:
  // included only when visible, so head-to-knee framing scores identically to the
  // Reference Builder, which excludes them when not present.
  var UPPER = [
    { i: IDX.shoulderL, w: 0.5 }, { i: IDX.shoulderR, w: 0.5 },
    { i: IDX.elbowL, w: 0.8 }, { i: IDX.elbowR, w: 0.8 },
    { i: IDX.wristL, w: 1.0 }, { i: IDX.wristR, w: 1.0 }
  ];
  var LOWER = [
    { i: IDX.hipL, w: 0.6 }, { i: IDX.hipR, w: 0.6 },
    { i: IDX.kneeL, w: 1.0 }, { i: IDX.kneeR, w: 1.0 }
  ];
  var ANKLES = [
    { i: IDX.ankleL, w: 1.0 }, { i: IDX.ankleR, w: 1.0 }
  ];

  function vis(lm) { return (lm && typeof lm.visibility === 'number') ? lm.visibility : 1; }
  function dist(a, b) { var dx = a.x - b.x, dy = a.y - b.y; return Math.sqrt(dx * dx + dy * dy); }

  // Running median over a time window (for torso length smoothing).
  function WindowedMedian(seconds) {
    this.seconds = seconds;
    this.buf = []; // { t, v }
  }
  WindowedMedian.prototype.push = function (t, v) {
    this.buf.push({ t: t, v: v });
    var cutoff = t - this.seconds;
    while (this.buf.length && this.buf[0].t < cutoff) this.buf.shift();
  };
  WindowedMedian.prototype.value = function () {
    if (!this.buf.length) return null;
    var vals = this.buf.map(function (e) { return e.v; }).sort(function (a, b) { return a - b; });
    var n = vals.length;
    return (n % 2) ? vals[(n - 1) / 2] : (vals[n / 2 - 1] + vals[n / 2]) / 2;
  };

  // ---- IntensityTracker --------------------------------------------------
  // Stateful across frames. Call update(landmarks, tSec) per frame; returns
  // { upper, lower, overall, torso, hasUpper, hasLower } with intensities 0-100
  // (or null for a group whose joints are insufficiently visible this frame).
  function IntensityTracker(opts) {
    opts = opts || {};
    this.sMax = opts.sMax != null ? opts.sMax : DEF.sMax;
    this.alpha = opts.emaAlpha != null ? opts.emaAlpha : DEF.emaAlpha;
    this.minVis = opts.minVisibility != null ? opts.minVisibility : DEF.minVisibility;
    this.minFrac = opts.minGroupVisibleFraction != null ? opts.minGroupVisibleFraction : DEF.minGroupVisibleFraction;
    this.torsoMedian = new WindowedMedian(opts.torsoMedianSeconds != null ? opts.torsoMedianSeconds : DEF.torsoMedianSeconds);
    this.prev = null;        // { lm, t }
    this.emaUpper = null;
    this.emaLower = null;
  }

  // Weighted mean joint speed for a group, normalised by torso length.
  // Returns { speed, visibleFrac } or null if no previous frame.
  IntensityTracker.prototype._groupSpeed = function (group, lm, prevLm, dt, torso) {
    var wSum = 0, acc = 0, visCount = 0;
    for (var k = 0; k < group.length; k++) {
      var j = group[k].i, w = group[k].w;
      var cur = lm[j], old = prevLm[j];
      if (!cur || !old) continue;
      if (vis(cur) < this.minVis || vis(old) < this.minVis) continue;
      var v = dist(cur, old) / (dt * torso);     // §3.4: ||Δp|| / (Δt · L)
      acc += w * v;
      wSum += w;
      visCount++;
    }
    var frac = visCount / group.length;
    if (wSum === 0 || frac < this.minFrac) return null;
    return { speed: acc / wSum, visibleFrac: frac };
  };

  IntensityTracker.prototype._scale = function (s) {
    return 100 * Math.min(1, s / this.sMax);
  };

  IntensityTracker.prototype.update = function (lm, tSec) {
    var out = { upper: null, lower: null, overall: null, torso: null, hasUpper: false, hasLower: false };
    if (!lm || lm.length < 29) { this.prev = lm ? { lm: lm, t: tSec } : this.prev; return out; }

    // Torso length L = mid-shoulder to mid-hip, smoothed with a moving median.
    var sL = lm[IDX.shoulderL], sR = lm[IDX.shoulderR], hL = lm[IDX.hipL], hR = lm[IDX.hipR];
    var torso = null;
    if (sL && sR && hL && hR &&
        vis(sL) >= this.minVis && vis(sR) >= this.minVis &&
        vis(hL) >= this.minVis && vis(hR) >= this.minVis) {
      var midShoulder = { x: (sL.x + sR.x) / 2, y: (sL.y + sR.y) / 2 };
      var midHip = { x: (hL.x + hR.x) / 2, y: (hL.y + hR.y) / 2 };
      var raw = dist(midShoulder, midHip);
      if (raw > 1e-4) this.torsoMedian.push(tSec, raw);
    }
    torso = this.torsoMedian.value();
    out.torso = torso;

    if (!this.prev || !torso) { this.prev = { lm: lm, t: tSec }; return out; }
    var dt = tSec - this.prev.t;
    if (dt <= 0) { this.prev = { lm: lm, t: tSec }; return out; }

    // Upper
    var up = this._groupSpeed(UPPER, lm, this.prev.lm, dt, torso);
    if (up) {
      this.emaUpper = (this.emaUpper == null) ? up.speed : this.alpha * up.speed + (1 - this.alpha) * this.emaUpper;
      out.upper = this._scale(this.emaUpper);
      out.hasUpper = true;
    }

    // Lower = hips + knees, plus ankles ONLY if visible this frame (§3.4).
    var lowerGroup = LOWER.slice();
    var ankVisible = ANKLES.every(function (a) { return lm[a.i] && vis(lm[a.i]) >= 0.5; });
    if (ankVisible) lowerGroup = lowerGroup.concat(ANKLES);
    var lo = this._groupSpeed(lowerGroup, lm, this.prev.lm, dt, torso);
    if (lo) {
      this.emaLower = (this.emaLower == null) ? lo.speed : this.alpha * lo.speed + (1 - this.alpha) * this.emaLower;
      out.lower = this._scale(this.emaLower);
      out.hasLower = true;
    }

    // Overall = 0.5 upper + 0.5 lower (using whatever groups are present).
    if (out.upper != null && out.lower != null) out.overall = 0.5 * out.upper + 0.5 * out.lower;
    else if (out.upper != null) out.overall = out.upper;
    else if (out.lower != null) out.overall = out.lower;

    this.prev = { lm: lm, t: tSec };
    return out;
  };

  // ---- Binner ------------------------------------------------------------
  // Aggregates per-frame intensities into fixed 0.5 s bins (mean per bin). A bin
  // with < 1 contributing frame for a group is recorded as null (missing), per
  // "Frames with < 50% of a group's joints visible mark that bin as missing".
  function Binner(binSeconds) {
    this.binSeconds = binSeconds || DEF.binSeconds;
    this.bins = {}; // index -> { upper:[], lower:[], overall:[] }
    this.maxIndex = -1;
  }
  Binner.prototype.add = function (tSec, frame) {
    var idx = Math.floor(tSec / this.binSeconds);
    if (idx < 0) return;
    if (!this.bins[idx]) this.bins[idx] = { upper: [], lower: [], overall: [] };
    if (frame.upper != null) this.bins[idx].upper.push(frame.upper);
    if (frame.lower != null) this.bins[idx].lower.push(frame.lower);
    if (frame.overall != null) this.bins[idx].overall.push(frame.overall);
    if (idx > this.maxIndex) this.maxIndex = idx;
  };
  function meanOrNull(a) {
    if (!a || !a.length) return null;
    var s = 0; for (var i = 0; i < a.length; i++) s += a[i];
    return Math.round((s / a.length) * 10) / 10;   // 0.1 precision keeps JSON small
  }
  // Returns { upper[], lower[], overall[] } arrays of length maxIndex+1.
  Binner.prototype.series = function (count) {
    var n = (count != null) ? count : (this.maxIndex + 1);
    var upper = [], lower = [], overall = [];
    for (var i = 0; i < n; i++) {
      var b = this.bins[i];
      upper.push(b ? meanOrNull(b.upper) : null);
      lower.push(b ? meanOrNull(b.lower) : null);
      overall.push(b ? meanOrNull(b.overall) : null);
    }
    return { upper: upper, lower: lower, overall: overall };
  };

  window.PoseIntensity = {
    IntensityTracker: IntensityTracker,
    Binner: Binner,
    IDX: IDX,
    defaults: DEF
  };
})();
