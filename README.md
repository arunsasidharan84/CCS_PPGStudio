<p align="center">
  <img src="screenshots/ccs_logo.png" width="160" alt="Centre for Consciousness Studies Logo">
</p>

<h1 align="center">CCS PPG Studio</h1>

<p align="center">
  <b>Clinical & Research Photoplethysmography (PPG) Analytics Platform</b>
</p>

<p align="center">
  A Joint Research & Engineering Collaboration of<br>
  <b>Centre for Consciousness Studies (CCS)</b>, Department of Neurophysiology,<br>
  <b>National Institute of Mental Health and Neurosciences (NIMHANS)</b>, Bengaluru, India<br>
  🤝<br>
  <a href="https://www.sensio-ai.in/"><b>SensIO</b></a> &nbsp;|&nbsp; <a href="https://www.neuro-stellar.com/"><b>Neurostellar</b></a>
</p>

<p align="center">
  <a href="https://github.com/arunsasidharan84/CCS_PPGStudio/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/arunsasidharan84/CCS_PPGStudio?style=for-the-badge&color=2563eb&label=RELEASE"></a>
  <a href="https://github.com/arunsasidharan84/CCS_PPGStudio/actions/workflows/build_and_deploy.yml"><img alt="Desktop build" src="https://img.shields.io/github/actions/workflow/status/arunsasidharan84/CCS_PPGStudio/build_and_deploy.yml?style=for-the-badge&label=BUILD"></a>
  <a href="https://github.com/arunsasidharan84/CCS_PPGStudio/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/arunsasidharan84/CCS_PPGStudio/total?style=for-the-badge&color=16a34a&label=DOWNLOADS"></a>
</p>

<p align="center">
  <b>Current version: 1.0.1</b> ·
  <a href="https://github.com/arunsasidharan84/CCS_PPGStudio/releases">Release notes</a> ·
  <a href="https://github.com/arunsasidharan84/CCS_PPGStudio/issues">Report a problem</a>
</p>

<p align="center">
  <a href="#-quick-download"><b>📥 Download App</b></a> &nbsp;•&nbsp;
  <a href="#about"><b>About</b></a> &nbsp;•&nbsp;
  <a href="#-executive-overview--key-capabilities"><b>Key Capabilities</b></a> &nbsp;•&nbsp;
  <a href="#-visual-walkthrough--module-breakdown"><b>Module Walkthrough</b></a> &nbsp;•&nbsp;
  <a href="#-getting-started--building-locally"><b>Build from Source</b></a> &nbsp;•&nbsp;
  <a href="https://github.com/arunsasidharan84/CCS_PPGStudio/issues"><b>Report Issue</b></a>
</p>

---

### 📥 Quick Download

Pre-built standalone desktop and mobile packages are published automatically through GitHub Releases:

| Platform | Package Type | Extracted App / Binary | Direct Download Link |
| :--- | :--- | :--- | :--- |
| **macOS** | Universal desktop application (.zip) | **`CCS PPG Studio.app`** | [CCSPPGStudio-macos.zip](https://github.com/arunsasidharan84/CCS_PPGStudio/releases/latest/download/CCSPPGStudio-macos.zip) |
| **Windows** | 64-bit desktop package (.zip) | `CCSPPGStudio.exe` | [CCSPPGStudio-Windows.zip](https://github.com/arunsasidharan84/CCS_PPGStudio/releases/latest/download/CCSPPGStudio-Windows.zip) |
| **Android** | Mobile & Tablet APK | `CCSPPGStudio-Android.apk` | [CCSPPGStudio-Android.apk](https://github.com/arunsasidharan84/CCS_PPGStudio/releases/latest/download/CCSPPGStudio-Android.apk) |
| **iOS** | iOS package (.ipa / .zip) | `CCSPPGStudio-iOS.zip` | [CCSPPGStudio-iOS.zip](https://github.com/arunsasidharan84/CCS_PPGStudio/releases/latest/download/CCSPPGStudio-iOS.zip) |

> 📦 **All Releases & Assets:** View all published binaries and platform assets on the **[GitHub Releases Page](https://github.com/arunsasidharan84/CCS_PPGStudio/releases/latest)**.

#### 🍏 First-Time Launch for macOS Users (Gatekeeper Setup)

When extracting `CCSPPGStudio-macos.zip`, macOS extracts **`CCS PPG Studio.app`** into your `~/Downloads` folder. Because development builds are ad-hoc signed, macOS Gatekeeper blocks opening them by default.

To enable the app, run the following in **Terminal**:

```sh
# 1. Clear Gatekeeper quarantine on the downloaded app:
xattr -rd com.apple.quarantine ~/Downloads/CCS\ PPG\ Studio.app

# 2. Move to Applications folder:
mv ~/Downloads/CCS\ PPG\ Studio.app /Applications/
```

> **Tip (Finder alternative):** In Finder, **Right-click (or Control-click)** `CCS PPG Studio.app` → select **Open** → click **Open** on the security confirmation prompt. You only need to do this once.

<p align="center">
  <img src="screenshots/waveform_timeline.png" width="920" alt="CCS PPG Studio Waveform & Timeline Workspace">
</p>

---

## About

**CCS PPG Studio** is a high-performance, cross-platform signal visualization, quality-gated beat detection, and autonomic neurophysiology analysis suite. Built specifically for continuous photoplethysmography (PPG) acquired from wearable sensors (such as the **SensIO Smart Ring**, **Orbit Wearable**, and clinical pulse oximeters), CCS PPG Studio bridges raw sensor telemetry with publication-ready digital biomarkers, multi-domain Heart Rate Variability (HRV), pulse morphology analytics, and executive PDF reporting.

---

## 🌟 Executive Overview & Key Capabilities

CCS PPG Studio addresses the primary engineering and signal quality challenges inherent in ambulatory and wearable PPG: motion artifacts, sensor detachment, baseline wander, non-uniform Bluetooth packet arrival, and ectopic pulses.

* **Gapless Macro-Episode Quality Partitioning**: Every millisecond of the recording is labeled into mutually exclusive, contiguous states (`GOOD`, `REJECT`, `BAD`), guaranteeing complete coverage accounting without artificial interpolation across artifact gaps.
* **Dual-Stage Refractory SQI Peak Detection**: Combines physiological refractory gating ($250\text{ ms} \le RR \le 2000\text{ ms}$, $30–240\text{ BPM}$) with morphological template matching (skewness, kurtosis, and correlation).
* **Optional Quality-Aware IPFM & SQI-Weighted Kalman Filter**: An advanced cardiac processing pipeline ported and adapted from Orbit CCI, featuring spurious beat pruning ($< 60\%$ confidence), continuous chain segmentation ($\le 4$ missing beats), Integral Pulse Frequency Modulation (IPFM) autonomic decoupling, and Kalman filtering with dynamic measurement noise scaling ($R_k = R_0 / \text{SQI}_k$).
* **Clinical & Research 29-Feature Biomarker Dictionary**: Computes multi-domain physiological indicators across **Time Domain**, **Frequency Domain** (Welch FFT), **Non-Linear Dynamics** (Poincaré ellipse, Sample Entropy, Approximate Entropy), **Pulse Wave Morphology**, and **Circadian Vitals & Actigraphy**.
* **Publication-Grade Vector Poincaré Engine**: True $1\sigma$ orthogonal $SD1/SD2$ ellipse geometry with Gaussian density shading and strict gap-isolation (preventing artificial pairs from bridging rejected segments).
* **Two-Session Comparative Analysis & A/B Reporting**: Interactive dual-session overlay screen and side-by-side comparative PDF generation with quantitative percentage shifts ($\Delta \%$) for interventions, pre/post states, and algorithm benchmarking.
* **Responsive Multi-Form-Factor Architecture**: Seamlessly scales from compact mobile devices (390×844 phone viewports with searchable modal pickers) to expansive desktop and multi-monitor workstations (1280×800+).

---

## 📸 Visual Walkthrough & Module Breakdown

### 1. High-Resolution Waveform & Gapless Quality Timeline
The primary inspection workspace provides real-time visualization of raw vs. zero-phase filtered continuous PPG waveforms, annotated systolic peaks, and macro-episode classification.

<p align="center">
  <img src="screenshots/waveform_timeline.png" width="920" alt="Waveform and Timeline Workspace">
</p>

* **Top KPI Executive Banner**: Instant readout of session viability:
  * **Coverage %**: Percentage of valid, physiologically clean pulses (e.g., $55.9\%$).
  * **Beats**: Total detected clean cardiac cycles (e.g., $26,602\text{ beats}$).
  * **Mean HR**: Average pulse rate in beats per minute ($51.4\text{ BPM}$).
  * **SDNN & RMSSD**: Global and parasympathetic beat-to-beat variability ($131.4\text{ ms}$ and $120.5\text{ ms}$).
  * **Skin Temperature & Motion Activity**: Dual-channel circadian telemetry ($34.09\ ^\circ\text{C}$ and $6.6\text{ index}$).
  * **MQI (Mean Quality Index)**: Aggregate signal quality score ($0.58$).
* **Gapless Quality Ribbon**: The horizontal timeline displays every epoch categorized into:
  * 🟩 **GOOD**: High-fidelity pulse waveforms meeting physiological morphology and amplitude criteria.
  * 🟥 **REJECT**: Identified motion artifacts, sensor detachment, or excessive high-frequency noise.
  * ⬛ **BAD / GAP**: Flatlines, packet dropouts, or non-physiological refractory violations.
* **Continuous Waveform Viewer**: Zero-phase 0.4–8.0 Hz bandpass filtered PPG trace with red systolic peak markers positioned precisely at pulse crests.

---

### 2. Autonomic Dynamics & Vector Poincaré Geometry
The dynamics tab visualizes autonomic nervous system (ANS) balance via non-linear phase space reconstruction and synchronized time-series trend analysis.

<p align="center">
  <img src="screenshots/poincare_dynamics.png" width="920" alt="Poincaré Plot and Feature Trends">
</p>

* **Clinical Poincaré Map ($RR_n \text{ vs } RR_{n+1}$)**:
  * Plots consecutive inter-beat intervals ($RR_n$ on horizontal axis vs. $RR_{n+1}$ on vertical axis).
  * **Orthogonal Eigenvector Axes**: Longitudinal identity line ($y = x$, representing overall variability) and perpendicular dispersion line ($y = -x + 2\overline{RR}$, representing beat-to-beat variability).
  * **$1\sigma$ Confidence Ellipse**: Statistically derived bounding ellipse parameterized by $SD1$ (semi-minor axis) and $SD2$ (semi-major axis).
  * **Gaussian Density Shading**: Color-coded kernel density contours highlight clustering patterns (comet, torpedo, or dispersed fan shapes).
  * **Zero Gap-Bridging Guarantee**: Pairs are constructed strictly from temporally consecutive beats. If an artifact or bad epoch intervenes, pairing safely halts, preventing spurious extreme points.
* **Dual-Axis Multi-Metric Trend Chart**:
  * Simultaneous longitudinal tracking of two user-selectable parameters over the entire recording.
  * Compare autonomic shifts against physiological context (e.g., **Mean HR** in red vs. **Skin Temperature** in blue, or **RMSSD** vs. **Motion Activity**).

---

### 3. Clinical & Research 29-Feature Summary Dictionary
A structured statistical catalog breaking down the recording into 29 standardized physiological metrics across 5 distinct domains.

<p align="center">
  <img src="screenshots/clinical_summary.png" width="920" alt="Clinical Summary Feature Dictionary">
</p>

| Domain | Biomarkers Included | Physiological Significance |
| :--- | :--- | :--- |
| **Time Domain HRV** | Mean HR, Min HR, Max HR, HR Std, Mean RR, SDNN, RMSSD, pNN50, pNN20, CV-RR | Basal cardiac rhythm, sympathetic-parasympathetic balance, vagal tone (RMSSD), and overall heart rate variability. |
| **Frequency Domain HRV** | VLF Power, LF Power, HF Power, Total Power, LF/HF Ratio, LFnu, HFnu | Sympathetic modulation (LF: 0.04–0.15 Hz), parasympathetic respiratory sinus arrhythmia (HF: 0.15–0.40 Hz), and sympathovagal ratio. |
| **Non-Linear Dynamics** | Poincaré SD1, Poincaré SD2, SD1/SD2 Ratio, Approximate Entropy (ApEn), Sample Entropy (SampEn) | Short-term beat-to-beat variance ($SD1$), long-term regulatory variance ($SD2$), autonomic flexibility, and structural physiological complexity. |
| **Pulse Morphology** | Systolic Amplitude, Pulse Width, Crest Time, Reflection Index, Pulse Transit Time proxy | Arterial stiffness, peripheral vascular resistance, systemic compliance, and stroke volume dynamics. |
| **Vitals & Actigraphy** | Skin Temperature, Tri-Axial Motion Index, Signal Quality Index (MQI), Valid Coverage % | Circadian thermoregulation, physical activity tracking, sleep/wake immobility, and artifact burden. |

---

### 4. Time-Series Data Explorer & Raw Stream Viewer
A dedicated tabular inspection view providing pagination, sorting, and microsecond-level precision across all extracted cardiac intervals.

* **Full Inter-Beat Interval (IBI) Table**: Complete listing of timestamp, pulse interval ($RR\text{ ms}$), instantaneous heart rate ($60000 / RR$), and sample-level signal quality index ($\text{SQI}$).
* **Dynamic Search & Filtering**: Isolate specific segments, review anomalous interval transitions, and cross-reference detected beats against raw telemetry.
* **CSV / JSON Data Export**: Export cleaned IBI series directly for external modelling in Python, R, or MATLAB.

---

## ⚡ Speed & Architectural Highlights

CCS PPG Studio is architected for instant responsiveness on large multi-hour recordings:

1. **Native Rust DSP Engine (`sensio_ppg_core`)**: Compute-heavy operations (zero-phase forward-backward digital filtering, convolution kernels, template matching, matrix inversion, and FFT) run in compiled Rust through high-speed C FFI bindings.
2. **Deterministic Memory Footprint**: Ingests multi-gigabyte continuous sensor streams using ring-buffered sliding windows and contiguous memory arrays, running seamlessly on resource-constrained mobile hardware.
3. **Reactive UI State Isolation**: Flutter isolate workers decouple data decoding and DSP computations from the UI rendering thread, locking canvas animations and gesture scrubbing at 60+ FPS.

---

## 🔬 Deep-Dive: Signal Processing Logics

### A. Standard Refractory SQI vs. Quality-Aware IPFM & Kalman Filtering

CCS PPG Studio includes two state-of-the-art peak detection pipelines:

#### 1. Standard Refractory SQI
* **Gating**: Dynamic physiological refractory blanking ($250\text{ ms} \le RR \le 2000\text{ ms}$).
* **Morphology Template Matching**: Computes correlation with an empirical PPG pulse template to produce an epoch SQI between 0.0 and 1.0.
* **Best Suited For**: Clean to moderately noisy daytime records, clinical pulse oximetry, and fast visual verification.

#### 2. Quality-Aware IPFM & SQI-Weighted Kalman Filtering (Orbit Model)
Ported directly from research grade algorithms for wearable ring PPG:
* **Spurious Beat Pruning**: Rejects candidate beats with template confidence $< 60\%$.
* **Continuous Chain Segmentation**: Partitions the beat stream whenever $> 4$ consecutive beats are missing, preventing artificial interpolation across long dropouts.
* **IPFM Representation**: Models the instantaneous cardiac rhythm as the output of an Integral Pulse Frequency Modulation threshold crossing:
  $$m(t) = d_{RR}(t) - 1$$
* **Kalman Filtering with Adaptive Noise Scaling**:
  $$R_k = \frac{R_0}{\text{SQI}_k}$$
  Where noisy samples ($\text{SQI} \to 0$) inflate measurement variance $R_k$, gracefully shifting state estimates toward the physiological prior.

---

## 📑 Comprehensive PDF Reporting & Session Comparison

### 1. Single-Session Executive PDF Report
* Executive cover banner featuring subject ID, recording date, total duration, and overall coverage percentage.
* High-resolution vector Poincaré plot with $SD1/SD2$ orthogonal axes and $1\sigma$ ellipse contours.
* Complete 29-feature clinical biomarker table organized into standardized domains.
* Gapless macro-episode distribution breakdown with percentage pie chart.

### 2. Two-Session A/B Comparison Report
Enables head-to-head comparison between two recordings (e.g., Pre vs. Post intervention, Day 1 vs. Day 2, or Standard vs. IPFM+Kalman processing):
* **Side-by-Side Poincaré Scatter Maps**: Direct visual comparison of ellipse orientation, $SD1$ dispersion, and $SD2$ elongation.
* **Quantitative Shift Matrix ($\Delta$ & $\Delta \%$)**:
  $$\Delta \% = \left(\frac{\text{Session}_2 - \text{Session}_1}{\text{Session}_1}\right) \times 100$$
* Directional change badges without implying statistical significance or clinical benefit.

---

## 📂 Universal Data Ingestion & File Formats

* **SensIO Smart Ring (`*_ppg_data.csv`)**:
  * Configurable file filter (definable in Settings).
  * Ingests synchronized infrared/green PPG, ambient temperature, tri-axial accelerometer ($X/Y/Z$), and battery telemetry.
* **Orbit Smart Wearable (`.orb` & `.signal`)**:
  * Native binary and JSON-lines decoder for Orbit recordings.
  * Specifically targets **Channel E (PPG)**.
  * Preserves hardware sample counter ticks ($T$) at 62.5 Hz to maintain microsecond-accurate timekeeping across Bluetooth packet boundaries.
* **Generic Clinical & Research CSVs**:
  * Header-adaptive column mapper supporting comma, tab, or semicolon delimiters.
  * Compatible with standard physiological recording systems (Empatica, BioRadio, Shimmer, Polar, and custom DAQ boards).

---

## 🚀 Getting Started & Building Locally

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install): 3.22.x or higher (Stable channel)
* [Rust Toolchain](https://www.rust-lang.org/tools/install): `cargo` and `rustc` 1.75+
* C/C++ Compiler: Clang/Xcode on macOS, MSVC on Windows, GCC on Linux

### 1. Clone the Repository
```sh
git clone https://github.com/arunsasidharan84/CCS_PPGStudio.git
cd CCS_PPGStudio
```

### 2. Build the Native Rust Engine
```sh
cd rust
cargo build --release
cd ..
```

### 3. Install Flutter Dependencies & Run
```sh
flutter pub get

# Launch on macOS Desktop
flutter run -d macos

# Launch on Windows Desktop
flutter run -d windows

# Launch on Linux Desktop
flutter run -d linux

# Launch on Connected Android or iOS Device
flutter run -d <device-id>
```

### 4. Run Automated Test Suites
```sh
# Run Dart unit, integration, and UI tests
flutter test

# Run Rust native DSP and matrix tests
cd rust && cargo test && cd ..
```

---

## 🤝 Research Collaboration & Acknowledgments

**CCS PPG Studio** is developed as a joint research and engineering collaboration by:

* **Centre for Consciousness Studies (CCS)**  
  *Department of Neurophysiology*,  
  **National Institute of Mental Health and Neurosciences (NIMHANS)**, Bengaluru, India.  
  *Pioneering research into altered states of consciousness, sleep neurophysiology, meditation, and autonomic dynamics.*

* **SensIO** ([https://www.sensio-ai.in/](https://www.sensio-ai.in/))  
  *Innovators in next-generation smart ring hardware, continuous wearable biosensing, and edge health analytics.*

* **Neurostellar** ([https://www.neuro-stellar.com/](https://www.neuro-stellar.com/))  
  *Experts in advanced neurotechnology, non-invasive physiological monitoring, and clinical-grade health AI platforms.*

---

## 🔗 Related Repositories

| Repository | Description |
| :--- | :--- |
| [CCS Sleep Studio](https://github.com/arunsasidharan84/CCS_SleepStudio) | Sleep EEG visualization, manual staging, 9 automated AI models, and AnalyseNidra quantitative reports |
| [CCS Mobile Studio](https://github.com/arunsasidharan84/CCS_MobileStudio) | Mobile/desktop neurophysiology acquisition, stimulation, ANGEL ERP, and cognitive experiments |
| [CCS EEG Studio](https://github.com/arunsasidharan84/CCS_EEGStudio) | Native-speed EEG preprocessing, feature extraction, connectivity, statistics, and reporting |

---

## 📚 Key Scientific Literature

1. **Task Force of the European Society of Cardiology and the North American Society of Pacing and Electrophysiology** (1996). *Heart rate variability: standards of measurement, physiological interpretation, and clinical use.* Circulation, 93(5), 1043–1065.
2. **Brennan, M., Palaniswami, M., & Kamen, P.** (2001). *Do existing measures of Poincaré plot geometry reflect nonlinear features of heart rate variability?* IEEE Transactions on Biomedical Engineering, 48(11), 1342–1347.
3. **Elgendi, M.** (2012). *On the analysis of fingertip photoplethysmogram signals.* Current Cardiology Reviews, 8(1), 14–25.
4. **Mateo, J., & Laguna, P.** (2000). *Analysis of heart rate variability in the presence of ectopic beats using the heart timing signal.* IEEE Transactions on Biomedical Engineering, 47(7), 896–907.
5. **Orphanidou, C., et al.** (2015). *Signal-quality indices for the electrocardiogram and photoplethysmogram: deriving native indices.* IEEE Journal of Biomedical and Health Informatics, 19(3), 832–839.

## Experiment workspace

Open a recording and use the visible **Compare sessions** action above the analysis tabs.

1. Give both conditions meaningful names in **Condition names & selected regions**.
2. Choose session B. Saved detection corrections are loaded automatically.
3. Select an independent region in A and B with the range handles, or enter exact elapsed seconds and submit the field. **Full session** restores the complete range.
4. Press **Compare selected regions**. Both signals are recalculated with the Standard pipeline, using only samples within each region. Summary values, coverage, accepted beats and Poincaré plots all refer to those regions; precomputed epochs outside the selection are not reused.
5. Review the shared-scale pulse geometry, coverage, duration and feature changes. Filter by feature domain, then use **1-page visual PDF** to preview, print, save or share the report.

The summary records condition names, experiment title, source filenames and regions, coverage and epoch availability. Its optional appendix includes the full metric table, pipeline and review history. Paired bars show epoch means; the Poincaré panel uses pooled intervals within the selection. Changes are descriptive, not a statistical test or a clinical benefit score. The visual summary uses absolute changes; pNN50 changes use percentage points. Unavailable values remain N/A. Short or poor-quality regions can have no valid feature epochs. Match durations and recording conditions when designing experiments.

### Correct detection decisions on phone or desktop

Use **Review detections** above the analysis tabs. Tap a quality episode to select it, adjust the range as needed, then choose:

- **Include region**: override quality rejection and rerun beat detection on usable signal in that range.
- **Exclude region**: remove the region's detections from downstream analysis.
- **Revert region**: restore the app's original decision within the range, preserving corrections elsewhere.
- **Undo**: reverse the most recent review action in the current review screen.
- **Reset all**: restore automatic decisions for the whole session.

Coverage, beats, features and reports are recalculated after each change. Rejected gaps cannot create artificial neighboring interval pairs. Missing samples and structural defects remain unavailable even when a region is manually included. Reviewed analyses use the Standard pipeline to avoid smoothing across excluded regions. Corrections persist locally for the same source path, file size and modification time; replacing the recording starts a new review. Corrections are not written into the source recording. Use **Done** to return to analysis.

### Desktop releases and updates

The same Flutter interface and Rust analysis engine ship on macOS, Windows, Linux, Android and iOS. GitHub version tags build macOS ZIP, Windows ZIP, Linux x64 tar.gz, Android APK/AAB and an unsigned iOS build. macOS requires version 12 or later and iOS requires version 15 or later. Linux requires a GTK 3 desktop; the release build uses Ubuntu 22.04. Build Linux locally with `./scripts/build_linux.sh`.

On desktop, choose **Check for updates** in the app menu. The app checks stable releases from this repository, downloads the matching package, verifies it against the release's `SHA256SUMS`, and offers **Install and restart**. Finish work before restarting. Updates retain a timestamped `.previous-*` installation backup and restore it if package replacement fails. The installation parent folder must be writable. macOS packages are also checked with `codesign`; GitHub desktop builds use ad hoc signatures rather than notarization. Windows and Linux installers must still be verified on their respective operating systems before broad rollout. SHA-256 verifies package integrity against the repository's manifest, not independent publisher identity.

Android distribution uses `./scripts/deploy_firebase.sh` (always rebuilds before upload). iOS uses `./scripts/deploy_testflight.sh`, which prepares the native framework from source, archives the signed app and uploads to App Store Connect. Signing credentials and provisioning profiles must already be configured locally. Optional GitHub workflow distribution requires the corresponding Firebase/App Store secrets; requested uploads fail explicitly when credentials are absent. Unsigned GitHub iOS archives cannot be installed through TestFlight.

### Validation

```sh
cargo test --manifest-path rust/Cargo.toml
cargo build --manifest-path rust/Cargo.toml --release
mkdir -p macos/Frameworks
cp rust/target/release/libsensio_ppg_core.dylib macos/Frameworks/ # macOS tests
flutter analyze
flutter test
```

The regression suite covers region-only recalculation, rejection exclusion without gap bridging, inclusion constrained by structural validity, partial revert, review persistence/file replacement, numeric version ordering, comparison PDF generation, and portrait/landscape/desktop layouts. Platform packages should be smoke-tested on each target OS before distribution to a broader audience.

## Visual condition reports (1.2.0)

Comparison exports now default to a **single-page visual summary**. Six paired bar charts show heart rate, RMSSD, SDNN, pNN50, SD1 and SD2 with a common scale for the two conditions within each measure. Accepted-signal coverage and valid epoch counts are visible before the feature changes; unequal quality and sparse data receive a prominent caution. Pooled Poincaré geometry is distinguished from epoch-mean feature values.

Use **Condition names & selected regions** to name each condition (for example, *Standing pose* and *Half-bending forward pose*). Names are remembered locally per source recording. Meaningful filenames provide initial labels; generic session filenames cannot reveal a pose, so edit the name once. The experiment title follows the condition names unless you supply your own title.

**1-page visual PDF** opens a preview with an editable, descriptive filename containing the recording date, both condition names, source regions and report scope. Enable **Include full metric appendix** only when you need all features and source/review details. The default summary never expands into the old multi-page waveform/trajectory dossier. In the comparison UI, six visual measures lead the results; pulse geometry and all remaining measures are expandable.

The summary is descriptive. Larger changes are not automatically beneficial or statistically significant. A count of one valid epoch is shown explicitly and is not treated as repeated experimental evidence. A pNN50 change is expressed in percentage points, and missing values stay N/A instead of becoming zero.
