# FeatherScope [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://galenlynch.github.io/FeatherScope.jl/stable/) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://galenlynch.github.io/FeatherScope.jl/dev/) [![Build Status](https://github.com/galenlynch/FeatherScope.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/galenlynch/FeatherScope.jl/actions/workflows/CI.yml?query=branch%3Amain) [![Coverage](https://codecov.io/gh/galenlynch/FeatherScope.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/galenlynch/FeatherScope.jl)

Hardware-level synchronization and alignment tools for FeatherScope microscope data. This package handles the core task of aligning video frames to DAQ-recorded sync pulses and shutter signals, enabling precise temporal registration between imaging and electrophysiology data.

### Functionality

- **DAQ file reading**: Parse binary ADC data and MATLAB-format DAQ recordings (sync pulses, shutter signals, microphone data)
- **Sync alignment**: Match video frames to DAQ sync pulses by detecting edge triggers in both the sync signal and frame intensity time series
- **Exposed period detection**: Identify which video frames were acquired with the shutter open, using intensity thresholds (manual or GMM-fitted) and shutter edge timing
- **Video I/O**: Read AVI files frame-by-frame, compute per-frame mean intensities, and crop/clip videos to exposed periods via FFmpeg

### Related packages

- **[FeatherscopeExtraction](https://github.com/galenlynch/FeatherscopeExtraction.jl)**: Low-level frame extraction and color conversion. Handles reading raw FeatherScope binary files, converting Bayer-pattern data to RGB, grouping files by recording session, and writing extracted frames.
- **[FeatherScopePrePro](https://github.com/galenlynch/FeatherScopePrePro.jl)**: Higher-level preprocessing pipelines. Builds on FeatherScope and FeatherscopeExtraction to perform demining, median filtering, brightness normalization, LUT-based pixel mapping, and video encoding to compressed formats.

## Citing

See [`CITATION.bib`](CITATION.bib) for the relevant reference(s).
