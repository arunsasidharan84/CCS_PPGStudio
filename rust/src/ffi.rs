//! C-compatible Foreign Function Interface (FFI) for Flutter cross-platform integration.

use std::ffi::{CStr, CString};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::os::raw::c_char;
use std::path::Path;

use chrono::{NaiveTime, Timelike};
use serde::Serialize;

use crate::pipeline::{analyze_session, SessionAnalysisResult};

#[derive(Serialize)]
struct FfiResponse<T: Serialize> {
    success: bool,
    error: Option<String>,
    data: Option<T>,
}

/// Read timestamps and raw values from a Ring PPG CSV file matching load_ring_ppg() in Python
pub fn load_ring_ppg_csv(path: &Path) -> Result<(Vec<f64>, Vec<f64>), String> {
    let file = File::open(path).map_err(|e| format!("Failed to open PPG file: {}", e))?;
    let reader = BufReader::new(file);

    let mut seconds_list = Vec::new();
    let mut values_list = Vec::new();
    let mut in_data = false;

    let mut prev_total_sec: Option<f64> = None;
    let mut day_offset = 0.0;

    for line_result in reader.lines() {
        let line = match line_result {
            Ok(l) => l,
            Err(_) => continue,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let mut parts = trimmed.split(',');
        let col0 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        if !in_data {
            if col0.to_lowercase().starts_with("timestamp") {
                in_data = true;
            }
            continue;
        }

        let col1 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        let val: f64 = match col1.parse() {
            Ok(v) => v,
            Err(_) => continue,
        };

        // Format timestamp: HH:MM:SS:mmm -> HH:MM:SS.mmm
        let mut ts_str = col0.to_string();
        if ts_str.matches(':').count() == 3 {
            if let Some(idx) = ts_str.rfind(':') {
                ts_str.replace_range(idx..=idx, ".");
            }
        }

        let time_obj = match NaiveTime::parse_from_str(&ts_str, "%H:%M:%S%.f") {
            Ok(t) => t,
            Err(_) => continue,
        };

        let sec_of_day = (time_obj.hour() as f64) * 3600.0
            + (time_obj.minute() as f64) * 60.0
            + (time_obj.second() as f64)
            + (time_obj.nanosecond() as f64) / 1e9;

        if let Some(prev) = prev_total_sec {
            if sec_of_day < prev - 12.0 * 3600.0 {
                day_offset += 86400.0;
            }
        }
        prev_total_sec = Some(sec_of_day);

        seconds_list.push(sec_of_day + day_offset);
        values_list.push(val);
    }

    if values_list.is_empty() {
        return Err("No valid PPG data found in file".to_string());
    }

    Ok((seconds_list, values_list))
}

/// Read timestamps and values from a matching SigMot IMU CSV file
pub fn load_sigmot_csv(path: &Path) -> Option<(Vec<f64>, Vec<f64>)> {
    let file = File::open(path).ok()?;
    let reader = BufReader::new(file);

    let mut seconds_list = Vec::new();
    let mut values_list = Vec::new();
    let mut in_data = false;

    let mut prev_total_sec: Option<f64> = None;
    let mut day_offset = 0.0;

    for line_result in reader.lines() {
        let line = match line_result {
            Ok(l) => l,
            Err(_) => continue,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let mut parts = trimmed.split(',');
        let col0 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        if !in_data {
            if col0.to_lowercase().starts_with("timestamp") {
                in_data = true;
            }
            continue;
        }

        let col1 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        let val: f64 = match col1.parse() {
            Ok(v) => v,
            Err(_) => continue,
        };

        let mut ts_str = col0.to_string();
        if ts_str.matches(':').count() == 3 {
            if let Some(idx) = ts_str.rfind(':') {
                ts_str.replace_range(idx..=idx, ".");
            }
        }

        let time_obj = match NaiveTime::parse_from_str(&ts_str, "%H:%M:%S%.f") {
            Ok(t) => t,
            Err(_) => continue,
        };

        let sec_of_day = (time_obj.hour() as f64) * 3600.0
            + (time_obj.minute() as f64) * 60.0
            + (time_obj.second() as f64)
            + (time_obj.nanosecond() as f64) / 1e9;

        if let Some(prev) = prev_total_sec {
            if sec_of_day < prev - 12.0 * 3600.0 {
                day_offset += 86400.0;
            }
        }
        prev_total_sec = Some(sec_of_day);

        seconds_list.push(sec_of_day + day_offset);
        values_list.push(val);
    }

    if values_list.is_empty() {
        None
    } else {
        Some((seconds_list, values_list))
    }
}

/// Read timestamps and skin temperature values from a matching temperature CSV file
pub fn load_temperature_csv(path: &Path) -> Option<(Vec<f64>, Vec<f64>)> {
    let file = File::open(path).ok()?;
    let reader = BufReader::new(file);

    let mut seconds_list = Vec::new();
    let mut values_list = Vec::new();
    let mut in_data = false;

    let mut prev_total_sec: Option<f64> = None;
    let mut day_offset = 0.0;

    for line_result in reader.lines() {
        let line = match line_result {
            Ok(l) => l,
            Err(_) => continue,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let mut parts = trimmed.split(',');
        let col0 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        if !in_data {
            if col0.to_lowercase().starts_with("timestamp") {
                in_data = true;
            }
            continue;
        }

        let col1 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        let raw_val: f64 = match col1.parse() {
            Ok(v) => v,
            Err(_) => continue,
        };

        let mut ts_str = col0.to_string();
        if ts_str.matches(':').count() == 3 {
            if let Some(idx) = ts_str.rfind(':') {
                ts_str.replace_range(idx..=idx, ".");
            }
        }

        let time_obj = match NaiveTime::parse_from_str(&ts_str, "%H:%M:%S%.f") {
            Ok(t) => t,
            Err(_) => continue,
        };

        let sec_of_day = (time_obj.hour() as f64) * 3600.0
            + (time_obj.minute() as f64) * 60.0
            + (time_obj.second() as f64)
            + (time_obj.nanosecond() as f64) / 1e9;

        if let Some(prev) = prev_total_sec {
            if sec_of_day < prev - 12.0 * 3600.0 {
                day_offset += 86400.0;
            }
        }
        prev_total_sec = Some(sec_of_day);

        // Convert ADC centi-degrees to Celsius if needed (e.g. 3454 -> 34.54 °C)
        let temp_c = if raw_val > 100.0 {
            raw_val / 100.0
        } else {
            raw_val
        };

        seconds_list.push(sec_of_day + day_offset);
        values_list.push(temp_c);
    }

    if values_list.is_empty() {
        None
    } else {
        Some((seconds_list, values_list))
    }
}

/// Helper to convert Rust String into C string pointer
fn to_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a C string allocated by sensio_ppg_core
#[no_mangle]
pub extern "C" fn sensio_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Returns library version string
#[no_mangle]
pub extern "C" fn sensio_get_version() -> *const c_char {
    static VERSION: &[u8] = b"1.0.0\0";
    VERSION.as_ptr() as *const c_char
}

/// Process a PPG CSV file with optional SigMot IMU and Temperature files, returning JSON
#[no_mangle]
pub extern "C" fn sensio_process_file(
    ppg_path_ptr: *const c_char,
    sigmot_path_ptr: *const c_char,
    sample_rate: f64,
) -> *mut c_char {
    if ppg_path_ptr.is_null() {
        let resp: FfiResponse<SessionAnalysisResult> = FfiResponse {
            success: false,
            error: Some("Null PPG file path".to_string()),
            data: None,
        };
        return to_c_string(serde_json::to_string(&resp).unwrap());
    }

    let ppg_path_str = match unsafe { CStr::from_ptr(ppg_path_ptr) }.to_str() {
        Ok(s) => s,
        Err(e) => {
            let resp: FfiResponse<SessionAnalysisResult> = FfiResponse {
                success: false,
                error: Some(format!("Invalid UTF-8 in PPG path: {}", e)),
                data: None,
            };
            return to_c_string(serde_json::to_string(&resp).unwrap());
        }
    };

    let ppg_path = Path::new(ppg_path_str);
    let (raw_sec, raw_val) = match load_ring_ppg_csv(ppg_path) {
        Ok(data) => data,
        Err(e) => {
            let resp: FfiResponse<SessionAnalysisResult> = FfiResponse {
                success: false,
                error: Some(e),
                data: None,
            };
            return to_c_string(serde_json::to_string(&resp).unwrap());
        }
    };

    let (sig_sec, sig_val) = if !sigmot_path_ptr.is_null() {
        if let Ok(sig_str) = unsafe { CStr::from_ptr(sigmot_path_ptr) }.to_str() {
            let sig_path = Path::new(sig_str);
            if sig_path.exists() {
                match load_sigmot_csv(sig_path) {
                    Some((s, v)) => (Some(s), Some(v)),
                    None => (None, None),
                }
            } else {
                (None, None)
            }
        } else {
            (None, None)
        }
    } else {
        // Auto-detect adjacent sigmot if null
        let parent = ppg_path.parent();
        let fname = ppg_path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        if let Some(p) = parent {
            let cand = p.join(fname.replace("_ppg_data.csv", "_sigmot_data.csv"));
            if cand.exists() {
                match load_sigmot_csv(&cand) {
                    Some((s, v)) => (Some(s), Some(v)),
                    None => (None, None),
                }
            } else if let Ok(entries) = std::fs::read_dir(p) {
                let mut found = None;
                let mut fallback = None;
                for entry in entries.flatten() {
                    let path = entry.path();
                    let f = path
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("")
                        .to_lowercase();
                    if f.contains("sigmot") && f.ends_with(".csv") {
                        if fname.len() >= 15
                            && f.contains(&fname[..fname.len().min(15)].to_lowercase())
                        {
                            found = Some(path);
                            break;
                        }
                        fallback = Some(path);
                    }
                }
                match found.or(fallback).and_then(|path| load_sigmot_csv(&path)) {
                    Some((s, v)) => (Some(s), Some(v)),
                    None => (None, None),
                }
            } else {
                (None, None)
            }
        } else {
            (None, None)
        }
    };

    // Auto-detect adjacent temperature file
    let (temp_sec, temp_val) = {
        let parent = ppg_path.parent();
        let fname = ppg_path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        if let Some(p) = parent {
            let cand = p.join(fname.replace("_ppg_data.csv", "_temperature_data.csv"));
            if cand.exists() {
                match load_temperature_csv(&cand) {
                    Some((s, v)) => (Some(s), Some(v)),
                    None => (None, None),
                }
            } else if let Ok(entries) = std::fs::read_dir(p) {
                let mut found = None;
                let mut fallback = None;
                for entry in entries.flatten() {
                    let path = entry.path();
                    let f = path
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("")
                        .to_lowercase();
                    if (f.contains("temperature") || f.contains("temp")) && f.ends_with(".csv") {
                        if fname.len() >= 15
                            && f.contains(&fname[..fname.len().min(15)].to_lowercase())
                        {
                            found = Some(path);
                            break;
                        }
                        fallback = Some(path);
                    }
                }
                match found
                    .or(fallback)
                    .and_then(|path| load_temperature_csv(&path))
                {
                    Some((s, v)) => (Some(s), Some(v)),
                    None => (None, None),
                }
            } else {
                (None, None)
            }
        } else {
            (None, None)
        }
    };

    let fs = if sample_rate > 0.0 { sample_rate } else { 50.0 };

    let sig_sec_ref = sig_sec.as_deref();
    let sig_val_ref = sig_val.as_deref();
    let temp_sec_ref = temp_sec.as_deref();
    let temp_val_ref = temp_val.as_deref();

    match analyze_session(
        &raw_sec,
        &raw_val,
        fs,
        sig_sec_ref,
        sig_val_ref,
        temp_sec_ref,
        temp_val_ref,
    ) {
        Ok(result) => {
            let resp = FfiResponse {
                success: true,
                error: None,
                data: Some(result),
            };
            to_c_string(serde_json::to_string(&resp).unwrap())
        }
        Err(e) => {
            let resp: FfiResponse<SessionAnalysisResult> = FfiResponse {
                success: false,
                error: Some(e),
                data: None,
            };
            to_c_string(serde_json::to_string(&resp).unwrap())
        }
    }
}

/// Re-evaluate a reviewed signal or selected experiment region using the same DSP engine.
#[derive(serde::Deserialize)]
struct ReviewRequest {
    time: Vec<f64>,
    filtered: Vec<Option<f64>>,
    norm_ppg: Vec<Option<f64>>,
    usable_mask: Vec<bool>,
    pulse_mask: Vec<bool>,
    quality_trace: Vec<Option<f64>>,
    sigmot_trace: Vec<Option<f64>>,
    peaks_indices: Vec<usize>,
    sample_rate: f64,
    start: f64,
    end: f64,
    overrides: Vec<ReviewRange>,
    #[serde(default)]
    ancillary: std::collections::HashMap<String, Vec<Option<f64>>>,
    #[serde(default)]
    epoch_times: Vec<f64>,
}
#[derive(serde::Deserialize)]
struct ReviewRange {
    start: f64,
    end: f64,
    include: bool,
}

fn review_signal(req: ReviewRequest) -> Result<SessionAnalysisResult, String> {
    use crate::pipeline::{generate_gapless_segments, PPGPreprocessResult};
    use crate::{
        compute_poincare_data, compute_time_resolved_hrv, detect_beats, generate_feature_summary,
        interp_1d,
    };
    let n = req.time.len();
    if n < 2
        || !req.sample_rate.is_finite()
        || req.sample_rate <= 0.0
        || req.filtered.len() != n
        || req.norm_ppg.len() != n
        || req.usable_mask.len() != n
        || req.pulse_mask.len() != n
        || req.quality_trace.len() != n
        || !req.start.is_finite()
        || !req.end.is_finite()
        || req.end <= req.start
        || req.time.windows(2).any(|w| w[1] <= w[0])
    {
        return Err("Invalid signal arrays or selection".into());
    }
    let first = req.time.partition_point(|t| *t < req.start);
    let last = req.time.partition_point(|t| *t <= req.end);
    if last.saturating_sub(first) < 2 {
        return Err("Select at least two signal samples".into());
    }
    let offset = req.time[first];
    let time: Vec<f64> = req.time[first..last].iter().map(|t| t - offset).collect();
    let filtered: Vec<f64> = req.filtered[first..last]
        .iter()
        .map(|v| v.unwrap_or(0.0))
        .collect();
    let usable = req.usable_mask[first..last].to_vec();
    let mut pulse = req.pulse_mask[first..last].to_vec();
    let mut included = vec![false; last - first];
    for range in &req.overrides {
        if !range.start.is_finite() || !range.end.is_finite() || range.end <= range.start {
            return Err("Invalid review range".into());
        }
        for i in 0..pulse.len() {
            let t = time[i] + offset;
            if t >= range.start && t < range.end {
                // Structural defects remain unavailable; a quality override cannot restore missing samples.
                pulse[i] = range.include && usable[i] && req.filtered[first + i].is_some();
                included[i] = pulse[i];
            }
        }
    }
    let mut peaks: Vec<usize> = req
        .peaks_indices
        .iter()
        .filter_map(|p| {
            if *p >= first && *p < last && pulse[*p - first] {
                Some(*p - first)
            } else {
                None
            }
        })
        .collect();
    // Re-detect only manually included runs; keep original detections elsewhere.
    let mut i = 0;
    while i < included.len() {
        if !included[i] {
            i += 1;
            continue;
        }
        let start = i;
        while i < included.len() && included[i] {
            i += 1;
        }
        peaks.retain(|p| *p < start || *p >= i);
        peaks.extend(
            detect_beats(&filtered[start..i], req.sample_rate, f64::NAN)
                .iter()
                .map(|p| p + start),
        );
    }
    peaks.sort_unstable();
    peaks.dedup();
    let mut separated: Vec<usize> = Vec::new();
    for peak in peaks {
        if let Some(last) = separated.last_mut() {
            if peak - *last < (req.sample_rate * 0.30).round() as usize {
                if filtered[peak] > filtered[*last] {
                    *last = peak;
                }
                continue;
            }
        }
        separated.push(peak);
    }
    let peaks = separated;
    let prep = PPGPreprocessResult {
        time: time.clone(),
        filtered: filtered.clone(),
        raw_grid: vec![],
        usable: usable.clone(),
        pulse: pulse.clone(),
        quality_trace: req.quality_trace[first..last]
            .iter()
            .map(|v| v.unwrap_or(0.0))
            .collect(),
        norm_ppg: req.norm_ppg[first..last]
            .iter()
            .map(|v| v.unwrap_or(0.0))
            .collect(),
        fs: req.sample_rate,
        windows: vec![],
        coverage: 0.0,
    };
    let (segments, _) = generate_gapless_segments(&prep);
    let duration = *time.last().unwrap();
    let coverage = segments
        .iter()
        .filter(|s| s.is_good)
        .map(|s| s.duration_s)
        .sum::<f64>()
        / duration
        * 100.0;
    let mut hrv = compute_time_resolved_hrv(
        &time,
        &filtered,
        &peaks,
        req.sample_rate,
        60.0,
        15.0,
        Some(&pulse),
    );
    for (key, values) in req.ancillary {
        if values.len() == req.epoch_times.len() && !values.is_empty() {
            let vals: Vec<f64> = values.iter().map(|v| v.unwrap_or(f64::NAN)).collect();
            let targets: Vec<f64> = hrv.timestamps.iter().map(|t| t + offset).collect();
            hrv.metrics
                .insert(key, interp_1d(&targets, &req.epoch_times, &vals));
        }
    }
    let peak_times: Vec<f64> = peaks.iter().map(|p| time[*p]).collect();
    let rr: Vec<f64> = peaks
        .windows(2)
        .map(|w| {
            if pulse[w[0]..=w[1]].iter().all(|v| *v) {
                (time[w[1]] - time[w[0]]) * 1000.0
            } else {
                f64::NAN
            }
        })
        .collect();
    let poincare = compute_poincare_data(&rr, Some(&peak_times));
    let summary = generate_feature_summary(&hrv.metrics);
    Ok(SessionAnalysisResult {
        total_duration_s: duration,
        start_time_of_day_s: offset,
        sample_rate: req.sample_rate,
        coverage_pct: coverage,
        accepted_window_count: 0,
        total_window_count: 0,
        time,
        filtered,
        norm_ppg: prep.norm_ppg,
        usable_mask: usable,
        pulse_mask: pulse,
        quality_trace: prep.quality_trace,
        sigmot_trace: if req.sigmot_trace.len() == n {
            req.sigmot_trace[first..last]
                .iter()
                .map(|v| v.unwrap_or(0.0))
                .collect()
        } else {
            vec![0.0; last - first]
        },
        peaks_indices: peaks,
        gapless_segments: segments,
        windows: vec![],
        hrv,
        poincare,
        summary,
    })
}

#[no_mangle]
pub extern "C" fn sensio_review_signal(ptr: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if ptr.is_null() {
            return Err("Missing review request".to_string());
        }
        let text = unsafe { CStr::from_ptr(ptr) }
            .to_str()
            .map_err(|e| e.to_string())?;
        let req: ReviewRequest = serde_json::from_str(text).map_err(|e| e.to_string())?;
        review_signal(req)
    })
    .unwrap_or_else(|_| Err("Unable to recalculate selection".into()));
    let resp = match result {
        Ok(data) => FfiResponse {
            success: true,
            error: None,
            data: Some(data),
        },
        Err(error) => FfiResponse {
            success: false,
            error: Some(error),
            data: None,
        },
    };
    to_c_string(serde_json::to_string(&resp).unwrap())
}

#[cfg(test)]
mod review_tests {
    use super::*;
    fn request() -> ReviewRequest {
        let n = 6001;
        ReviewRequest {
            time: (0..n).map(|i| i as f64 / 50.0).collect(),
            filtered: (0..n)
                .map(|i| Some((i as f64 * std::f64::consts::TAU / 50.0).sin()))
                .collect(),
            norm_ppg: vec![Some(0.0); n],
            usable_mask: vec![true; n],
            pulse_mask: vec![true; n],
            quality_trace: vec![Some(0.9); n],
            sigmot_trace: vec![Some(0.0); n],
            peaks_indices: (1..120).map(|i| i * 50).collect(),
            sample_rate: 50.0,
            start: 0.0,
            end: 120.0,
            overrides: vec![],
            ancillary: Default::default(),
            epoch_times: vec![],
        }
    }
    #[test]
    fn exclude_recomputes_coverage_beats_and_never_bridges_gap() {
        let mut req = request();
        req.overrides.push(ReviewRange {
            start: 40.0,
            end: 60.0,
            include: false,
        });
        let res = review_signal(req).unwrap();
        assert!((res.coverage_pct - 100.0 * 100.0 / 120.0).abs() < 0.01);
        assert!(res.peaks_indices.iter().all(|p| *p < 2000 || *p >= 3000));
        assert!(res
            .poincare
            .timestamps
            .iter()
            .all(|t| *t < 38.0 || *t >= 60.0));
    }
    #[test]
    fn subregion_recomputes_from_selected_samples_and_rebases_time() {
        let mut req = request();
        req.start = 30.0;
        req.end = 90.0;
        let res = review_signal(req).unwrap();
        assert_eq!(res.time[0], 0.0);
        assert_eq!(res.total_duration_s, 60.0);
        assert_eq!(res.peaks_indices.len(), 61);
        assert_eq!(res.hrv.timestamps.len(), 1);
        assert!(res.poincare.timestamps.iter().all(|t| *t <= 60.0));
    }
    #[test]
    fn include_redetects_quality_rejections_but_not_structural_defects() {
        let mut req = request();
        req.pulse_mask.fill(false);
        req.peaks_indices.clear();
        req.usable_mask[2000..3000].fill(false);
        req.overrides.push(ReviewRange {
            start: 0.0,
            end: 120.0,
            include: true,
        });
        let res = review_signal(req).unwrap();
        assert!(!res.peaks_indices.is_empty());
        assert!(res.pulse_mask[2000..3000].iter().all(|v| !v));
    }
    #[test]
    fn invalid_arrays_and_empty_region_are_rejected() {
        let mut req = request();
        req.filtered.pop();
        assert!(review_signal(req).is_err());
        let mut req = request();
        req.end = req.start;
        assert!(review_signal(req).is_err());
    }
}
