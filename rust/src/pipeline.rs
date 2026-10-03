//! Complete Ring PPG Preprocessing & Quality Assessment Pipeline (Revision 3),
//! 100% gapless macro-episode partitioning, and multi-domain HRV analysis.

use rayon::prelude::*;
use serde::{Deserialize, Serialize};

use crate::dsp::filter::SosFilter;
use crate::dsp::hrv::{
    compute_poincare_data, compute_time_resolved_hrv, generate_feature_summary,
    FeatureSummaryRow, PoincareData, TimeResolvedHrvResult,
};
use crate::dsp::resample::{interp_1d, median, percentile, resample_uniform, sanitize_timeline};
use crate::dsp::sqi::{
    erode, flag_filtered_outliers, flag_raw_defects, robust_scale, runs, score_window, veto,
    WindowSqi, detect_beats,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PPGWindowResult {
    pub start_s: f64,
    pub end_s: f64,
    pub start_idx: usize,
    pub end_idx: usize,
    pub signal: Vec<f64>,
    pub sqi: WindowSqi,
    pub accepted: bool,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PPGPreprocessResult {
    pub time: Vec<f64>,
    pub filtered: Vec<f64>,
    pub raw_grid: Vec<f64>,
    pub usable: Vec<bool>,
    pub pulse: Vec<bool>,
    pub quality_trace: Vec<f64>,
    pub norm_ppg: Vec<f64>,
    pub fs: f64,
    pub windows: Vec<PPGWindowResult>,
    pub coverage: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContinuousSegment {
    pub id: usize,
    pub onset_s: f64,
    pub duration_s: f64,
    pub end_s: f64,
    pub description: String,
    pub is_good: bool,
    pub hr_bpm: Option<f64>,
    pub quality_score: Option<f64>,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionAnalysisResult {
    pub total_duration_s: f64,
    pub start_time_of_day_s: f64,
    pub sample_rate: f64,
    pub coverage_pct: f64,
    pub accepted_window_count: usize,
    pub total_window_count: usize,
    pub time: Vec<f64>,
    pub norm_ppg: Vec<f64>,
    pub filtered: Vec<f64>,
    pub usable_mask: Vec<bool>,
    pub pulse_mask: Vec<bool>,
    pub quality_trace: Vec<f64>,
    pub sigmot_trace: Vec<f64>,
    pub peaks_indices: Vec<usize>,
    pub gapless_segments: Vec<ContinuousSegment>,
    pub windows: Vec<PPGWindowResult>,
    pub hrv: TimeResolvedHrvResult,
    pub poincare: PoincareData,
    pub summary: Vec<FeatureSummaryRow>,
}

/// Zero-phase bandpass filtering over valid segments matching bandpass_segments()
pub fn bandpass_segments(
    x: &[f64],
    bad: &[bool],
    fs: f64,
    filter: &SosFilter,
    min_segment_s: f64,
    edge_s: f64,
) -> (Vec<f64>, Vec<bool>) {
    let n = x.len();
    let mut y = vec![0.0; n];
    let mut ok = vec![false; n];

    let min_len = (min_segment_s * fs).round() as usize;
    let n_sections = filter.sections.len();
    let padlen = 3 * (2 * n_sections + 1);
    let thresh_len = min_len.max(3 * padlen);

    let not_bad: Vec<bool> = bad.iter().map(|&b| !b).collect();
    for (s, e) in runs(&not_bad) {
        if e - s < thresh_len {
            continue;
        }
        let seg = &x[s..e];
        let med = median(seg);
        let detrended: Vec<f64> = seg.iter().map(|&v| v - med).collect();
        let filt = filter.sosfiltfilt(&detrended);
        for i in 0..filt.len() {
            y[s + i] = filt[i];
            ok[s + i] = true;
        }
    }

    let edge_k = (edge_s * fs).round() as usize;
    let usable = erode(&ok, edge_k);
    (y, usable)
}

/// 9-window HR continuity enforcement matching enforce_hr_continuity() in ppg_preprocess.py
pub fn enforce_hr_continuity(windows: &mut [PPGWindowResult], span: usize, max_dev: f64) {
    let accepted_indices: Vec<usize> = windows
        .iter()
        .enumerate()
        .filter(|(_, w)| w.accepted)
        .map(|(i, _)| i)
        .collect();

    if accepted_indices.len() < 3 {
        return;
    }

    let hrs: Vec<f64> = accepted_indices
        .iter()
        .map(|&i| windows[i].sqi.hr_bpm)
        .collect();

    let half = 1.max(span / 2);

    for (j, &win_idx) in accepted_indices.iter().enumerate() {
        let a = if j >= half { j - half } else { 0 };
        let b = (j + half + 1).min(hrs.len());

        let mut neigh = Vec::new();
        for k in a..j {
            neigh.push(hrs[k]);
        }
        for k in (j + 1)..b {
            neigh.push(hrs[k]);
        }

        if neigh.len() < 2 {
            continue;
        }

        let ref_hr = median(&neigh);
        if ref_hr <= 0.0 {
            continue;
        }

        let curr_hr = hrs[j];
        if (curr_hr - ref_hr).abs() / ref_hr > max_dev {
            // Harmonic / sub-harmonic resolution
            let ratio = curr_hr / ref_hr;
            if ratio >= 0.42 && ratio <= 0.58 && (curr_hr * 2.0 - ref_hr).abs() / ref_hr <= max_dev {
                windows[win_idx].sqi.hr_bpm = curr_hr * 2.0;
                continue;
            } else if ratio >= 1.80 && ratio <= 2.20 && (curr_hr / 2.0 - ref_hr).abs() / ref_hr <= max_dev {
                windows[win_idx].sqi.hr_bpm = curr_hr / 2.0;
                continue;
            }

            // If template correlation and periodicity are solid, preserve
            if windows[win_idx].sqi.template_corr >= 0.82 && windows[win_idx].sqi.periodicity >= 0.45 {
                continue;
            }

            windows[win_idx].accepted = false;
            windows[win_idx].reason = Some("hr_discontinuity".to_string());
        }
    }
}

/// Run Revision 3 preprocessing pipeline matching ppg_preprocess.preprocess_ppg()
pub fn preprocess_ppg(
    raw_seconds: &[f64],
    raw_values: &[f64],
    target_fs: f64,
    lowcut: f64,
    highcut: f64,
    order: usize,
    window_s: f64,
    hop_s: f64,
    min_bpm: f64,
    max_bpm: f64,
    quality_thresh: f64,
    min_rr_smoothness: f64,
    min_rel_amplitude: f64,
    accel: Option<&[f64]>,
    accel_seconds: Option<&[f64]>,
    motion_thresh: Option<f64>,
    adc_min: Option<f64>,
    adc_max: Option<f64>,
    clip_sigma: f64,
) -> Result<PPGPreprocessResult, String> {
    let tl = sanitize_timeline(raw_seconds, raw_values, 2.5, 0.20)?;
    let (grid_t, raw_grid, valid) = resample_uniform(&tl, target_fs);

    let filter = SosFilter::design_butter_bandpass(order, lowcut, highcut, target_fs);
    let guard_s = filter.filter_settling_time(target_fs, 0.02, 12.0);

    let bad = flag_raw_defects(
        &raw_grid,
        target_fs,
        &valid,
        guard_s,
        adc_min,
        adc_max,
        8.0,
        1.0,
    );

    let min_seg_s = 4.0f64.max(window_s / 2.0);
    let (mut filtered, mut usable) = bandpass_segments(
        &raw_grid,
        &bad,
        target_fs,
        &filter,
        min_seg_s,
        guard_s,
    );

    let bad2 = flag_filtered_outliers(&filtered, target_fs, &bad, guard_s, 6.0, 60.0);
    let bad_count: usize = bad.iter().filter(|&&b| b).count();
    let bad2_count: usize = bad2.iter().filter(|&&b| b).count();

    if bad2_count > bad_count {
        let (f2, u2) = bandpass_segments(
            &raw_grid,
            &bad2,
            target_fs,
            &filter,
            min_seg_s,
            guard_s,
        );
        filtered = f2;
        usable = u2;
    }

    // Amplitude reference
    let mut usable_filtered = Vec::new();
    for i in 0..filtered.len() {
        if usable[i] {
            usable_filtered.push(filtered[i].abs());
        }
    }
    let amp_reference = if !usable_filtered.is_empty() {
        percentile(&usable_filtered, 90.0) * 2.0
    } else {
        1.0
    };

    // SigMot motion interpolation
    let motion_series: Option<Vec<f64>> = if let (Some(acc), Some(acc_sec)) = (accel, accel_seconds) {
        if !acc.is_empty() && !acc_sec.is_empty() {
            Some(interp_1d(&grid_t, acc_sec, acc))
        } else {
            None
        }
    } else {
        None
    };

    let wlen = (window_s * target_fs).round() as usize;
    let hop = (hop_s * target_fs).round() as usize;

    let mut window_specs = Vec::new();
    for (s0, e0) in runs(&usable) {
        if e0 - s0 < wlen {
            continue;
        }
        let mut starts = Vec::new();
        let mut s = s0;
        while s + wlen <= e0 {
            starts.push(s);
            s += hop;
        }
        if let Some(&last_s) = starts.last() {
            if last_s + wlen < e0 {
                starts.push(e0 - wlen);
            }
        }
        for start_idx in starts {
            window_specs.push((start_idx, start_idx + wlen));
        }
    }

    // Parallel SQI scoring using Rayon
    let mut windows: Vec<PPGWindowResult> = window_specs
        .par_iter()
        .map(|&(s, e)| {
            let seg = &filtered[s..e];
            let seg_raw = &raw_grid[s..e];

            let motion = if let Some(ref m_series) = motion_series {
                let m_slice = &m_series[s..e];
                let m_mean = m_slice.iter().sum::<f64>() / (m_slice.len() as f64);
                let m_std = (m_slice.iter().map(|&v| (v - m_mean).powi(2)).sum::<f64>()
                    / (m_slice.len() as f64))
                    .sqrt();
                Some(m_std)
            } else {
                None
            };

            let sqi = score_window(seg, seg_raw, target_fs, amp_reference, motion);

            let veto_reason = veto(
                &sqi,
                min_bpm,
                max_bpm,
                min_rr_smoothness,
                min_rel_amplitude,
                motion_thresh,
            );

            let accepted = veto_reason.is_none() && sqi.quality >= quality_thresh;
            let reason = match veto_reason {
                Some(r) => Some(r.to_string()),
                None if !accepted => Some("low_quality".to_string()),
                None => None,
            };

            let med = median(seg);
            let mad = robust_scale(seg);
            let mut norm = Vec::with_capacity(seg.len());
            for &v in seg {
                let scaled = (v - med) / mad.max(1e-9);
                norm.push(scaled.clamp(-clip_sigma, clip_sigma));
            }

            PPGWindowResult {
                start_s: grid_t[s],
                end_s: grid_t[e - 1],
                start_idx: s,
                end_idx: e,
                signal: norm,
                sqi,
                accepted,
                reason,
            }
        })
        .collect();

    enforce_hr_continuity(&mut windows, 9, 0.20);

    let mut pulse = vec![false; filtered.len()];
    let mut quality_trace = vec![0.0; filtered.len()];

    // Require agreement among overlapping windows. A single clean window
    // must not promote all neighboring noisy samples to accepted.
    let mut votes = vec![0usize; filtered.len()];
    let mut accepted_votes = vec![0usize; filtered.len()];
    for w in &windows {
        for i in w.start_idx..w.end_idx {
            votes[i] += 1;
            accepted_votes[i] += usize::from(w.accepted);
            quality_trace[i] += w.sqi.quality;
        }
    }
    for i in 0..filtered.len() {
        if votes[i] > 0 {
            quality_trace[i] /= votes[i] as f64;
            pulse[i] = usable[i] && accepted_votes[i] * 2 > votes[i];
        }
    }

    // Robust normalized PPG waveform matching plot_ring_ppg_mne
    let mut usable_filt = Vec::new();
    for i in 0..filtered.len() {
        if usable[i] {
            usable_filt.push(filtered[i]);
        }
    }
    let (g_med, g_mad) = if !usable_filt.is_empty() {
        (median(&usable_filt), robust_scale(&usable_filt))
    } else {
        (median(&filtered), robust_scale(&filtered))
    };

    let norm_ppg: Vec<f64> = filtered
        .iter()
        .map(|&v| (v - g_med) / g_mad.max(1e-9))
        .collect();

    let pulse_true_count = pulse.iter().filter(|&&p| p).count();
    let coverage = (pulse_true_count as f64) / (pulse.len().max(1) as f64);

    Ok(PPGPreprocessResult {
        time: grid_t,
        filtered,
        raw_grid,
        usable,
        pulse,
        quality_trace,
        norm_ppg,
        fs: target_fs,
        windows,
        coverage,
    })
}

/// Detect systolic peaks on valid pulse intervals matching _extract_global_peaks()
pub fn extract_global_peaks(res: &PPGPreprocessResult) -> Vec<usize> {
    let mut candidates = Vec::new();
    // Use the same detector and local HR hint used for quality scoring.
    for window in &res.windows {
        if !window.accepted { continue; }
        let signal = &res.filtered[window.start_idx..window.end_idx];
        for p in detect_beats(signal, res.fs, window.sqi.hr_bpm) {
            let global = window.start_idx + p;
            if res.pulse[global] { candidates.push(global); }
        }
    }
    candidates.sort_unstable();
    candidates.dedup();
    let mut peaks: Vec<usize> = Vec::new();
    let refractory = (0.30 * res.fs).round() as usize;
    for p in candidates {
        if let Some(&last) = peaks.last() {
            if p - last < refractory {
                if res.filtered[p] > res.filtered[last] { *peaks.last_mut().unwrap() = p; }
                continue;
            }
        }
        peaks.push(p);
    }
    peaks
}

/// Exact quality episodes: no temporal smoothing may turn an artifact into
/// accepted signal. Display labels, coverage, and the HRV mask agree.
pub fn generate_gapless_segments(res: &PPGPreprocessResult) -> (Vec<ContinuousSegment>, Vec<bool>) {
    if res.time.is_empty() { return (Vec::new(), Vec::new()); }
    let n = res.time.len();
    let t0 = res.time[0];
    let end = res.time[n - 1] - t0;
    let state = |i: usize| if !res.usable[i] { 0 } else if !res.pulse[i] { 1 } else { 2 };
    let mut segments = Vec::new();
    let mut start = 0;
    for i in 1..=n {
        if i < n && state(i) == state(start) { continue; }
        let st = state(start);
        let onset = res.time[start] - t0;
        let stop = if i == n { end } else { res.time[i] - t0 };
        let (tag, reason) = match st {
            0 => ("BAD_artifact", "Sensor defect, gap or filter boundary"),
            1 => ("REJECT", "Insufficient pulse quality or inconsistent overlapping windows"),
            _ => ("GOOD", "Accepted pulse quality"),
        };
        segments.push(ContinuousSegment {
            id: segments.len(), onset_s: onset, duration_s: stop - onset, end_s: stop,
            description: tag.to_owned(), is_good: st == 2, hr_bpm: None,
            quality_score: Some(res.quality_trace[start..i].iter().sum::<f64>() / (i - start) as f64),
            reason: Some(reason.to_owned()),
        });
        start = i;
    }
    (segments, res.pulse.clone())
}

/// Analyze entire PPG session end-to-end
pub fn analyze_session(
    raw_seconds: &[f64],
    raw_values: &[f64],
    target_fs: f64,
    sigmot_seconds: Option<&[f64]>,
    sigmot_values: Option<&[f64]>,
    temp_seconds: Option<&[f64]>,
    temp_values: Option<&[f64]>,
) -> Result<SessionAnalysisResult, String> {
    let prep = preprocess_ppg(
        raw_seconds,
        raw_values,
        target_fs,
        0.4,
        8.0,
        3,
        12.0,
        4.0,
        30.0,
        180.0,
        0.50,
        0.65,
        0.12,
        sigmot_values,
        sigmot_seconds,
        Some(5.0),
        None,
        None,
        6.0,
    )?;

    let peaks_indices = extract_global_peaks(&prep);
    let (gapless_segments, valid_mask) = generate_gapless_segments(&prep);

    let t0 = prep.time[0];
    let total_duration_s = prep.time.last().unwrap() - t0;
    let time_rel: Vec<f64> = prep.time.iter().map(|&t| t - t0).collect();

    let sigmot_trace = if let (Some(sec), Some(val)) = (sigmot_seconds, sigmot_values) {
        interp_1d(&prep.time, sec, val)
    } else {
        vec![0.0; prep.time.len()]
    };

    let mut hrv = compute_time_resolved_hrv(
        &time_rel,
        &prep.filtered,
        &peaks_indices,
        target_fs,
        60.0,
        15.0,
        Some(&valid_mask),
    );

    // Interpolate Skin Temperature & Activity Motion onto HRV timeline
    if let (Some(sec), Some(val)) = (temp_seconds, temp_values) {
        let hrv_time_abs: Vec<f64> = hrv.timestamps.iter().map(|&t| t + t0).collect();
        let temp_metric = interp_1d(&hrv_time_abs, sec, val);
        hrv.metrics.insert("Skin_Temperature".to_string(), temp_metric);
    }

    if let (Some(sec), Some(val)) = (sigmot_seconds, sigmot_values) {
        let hrv_time_abs: Vec<f64> = hrv.timestamps.iter().map(|&t| t + t0).collect();
        let sigmot_metric = interp_1d(&hrv_time_abs, sec, val);
        hrv.metrics.insert("Activity_Motion".to_string(), sigmot_metric);
    }

    let mut peak_times = Vec::with_capacity(peaks_indices.len());
    for &p in &peaks_indices {
        peak_times.push(time_rel[p]);
    }

    let mut rr_ms = Vec::new();
    if peak_times.len() >= 2 {
        for i in 0..peak_times.len() - 1 {
            let continuous = prep.pulse[peaks_indices[i]..=peaks_indices[i + 1]].iter().all(|&v| v);
            rr_ms.push(if continuous { (peak_times[i + 1] - peak_times[i]) * 1000.0 } else { f64::NAN });
        }
    }

    let poincare = compute_poincare_data(&rr_ms, Some(&peak_times));
    let summary = generate_feature_summary(&hrv.metrics);

    let accepted_count = prep.windows.iter().filter(|w| w.accepted).count();

    Ok(SessionAnalysisResult {
        total_duration_s,
        start_time_of_day_s: t0,
        sample_rate: target_fs,
        coverage_pct: (prep.coverage * 100.0 * 100.0).round() / 100.0,
        accepted_window_count: accepted_count,
        total_window_count: prep.windows.len(),
        time: time_rel,
        norm_ppg: prep.norm_ppg,
        filtered: prep.filtered,
        usable_mask: prep.usable,
        pulse_mask: prep.pulse,
        quality_trace: prep.quality_trace,
        sigmot_trace,
        peaks_indices,
        gapless_segments,
        windows: prep.windows,
        hrv,
        poincare,
        summary,
    })
}
