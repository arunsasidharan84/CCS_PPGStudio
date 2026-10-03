use sensio_ppg_core::pipeline::analyze_session;
use sensio_ppg_core::dsp::hrv::compute_poincare_data;

#[test]
fn poincare_does_not_connect_across_missing_intervals() {
    let rr = [800.0, 810.0, f64::NAN, 1000.0, 1010.0];
    let data = compute_poincare_data(&rr, Some(&[0., 0.8, 1.61, 10., 11., 12.01]));
    assert_eq!(data.x, vec![800., 1000.]);
    assert_eq!(data.y, vec![810., 1010.]);
    assert_eq!(data.timestamps, vec![0., 10.]);
}

#[test]
fn clean_pulses_noise_and_dropout_are_distinguished() {
    let fs = 50.0;
    let n = 180 * 50;
    let time: Vec<f64> = (0..n).map(|i| i as f64 / fs).collect();
    let mut seed = 412u64;
    let raw: Vec<f64> = time.iter().map(|&t| {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
        let noise = ((seed >> 32) as f64 / u32::MAX as f64 - 0.5) * 4.;
        if (70.0..110.0).contains(&t) { 1000. + noise }
        else if (130.0..145.0).contains(&t) { 1000. }
        else {
            let phase = 2. * std::f64::consts::PI * t;
            1000. + phase.sin() + 0.3 * (2. * phase - 0.8).sin()
        }
    }).collect();
    let r = analyze_session(&time, &raw, fs, None, None, None, None).unwrap();
    let fraction = |start: usize, end: usize| {
        r.pulse_mask[start*50..end*50].iter().filter(|&&v| v).count() as f64 / ((end-start)*50) as f64
    };
    assert!(fraction(20, 60) > 0.75, "Clean coverage {}", fraction(20,60));
    assert!(fraction(80, 100) < 0.20, "Noise coverage {}", fraction(80,100));
    assert_eq!(fraction(133, 142), 0.0);
    assert!(r.peaks_indices.iter().all(|&p| r.pulse_mask[p]));
    for seg in &r.gapless_segments {
        let midpoint = (((seg.onset_s + seg.end_s) / 2.) * fs).round() as usize;
        assert_eq!(seg.is_good, r.pulse_mask[midpoint.min(n-1)]);
    }
    let clean_peaks = r.peaks_indices.iter().filter(|&&p| p >= 20*50 && p < 60*50).count();
    assert!((38..=42).contains(&clean_peaks), "Expected ~40 beats, got {clean_peaks}");
}
