# Convstaff: Visual MIDI Extraction Engine
## System Architecture & Code-Level Documentation

This document provides an in-depth, code-level analysis of the `convstaff` engine, detailing the step-by-step pipeline used to extract MIDI note events from Synthesia-style piano videos using purely visual heuristics (zero machine learning).

The system consists of three main stages:
1. **Video Decoding & Frame Extraction** (`VideoAnalyzerService`)
2. **Keyboard Geometry Mapping** (`KeyMapperService`)
3. **Temporal Note Extraction & MIDI Generation** (`NoteExtractorService`)

---

## 1. Video Decoding (`video_analyzer_service.dart`)

The `VideoAnalyzerService` is responsible for extracting raw image frames from the input video using FFmpeg.

### Core Functions
- **`extractFrameAt(String videoPath, double timeInSeconds, ...)`**: Uses FFmpeg to seek to a specific timestamp (`-ss`) and extract a single frame. This is used iteratively during the auto-detection phase to find the exact frame where the video has faded in and the piano is fully visible.
- **`extractFrames(String videoPath, ...)`**: Extracts the entire sequence of frames for the video.
  - It uses `ffprobe` to automatically detect the exact native framerate (e.g., 60 fps).
  - It utilizes FFmpeg's `crop` video filter to slice a narrow horizontal strip of the video (using the `targetY` coordinate discovered during the mapping phase). By throwing away the rest of the frame before saving it to disk, it significantly reduces I/O and memory overhead.

---

## 2. Keyboard Geometry Mapping (`key_mapper_service.dart`)

Before note extraction can begin, the engine must understand the exact physical bounds (left/right pixel coordinates) of all 88 piano keys.

### The Auto-Detection Loop (`video_bloc.dart`)
The `VideoBloc` coordinates the mapping phase:
1. **Sharpness/Contrast Plateau:** It steps through the video at 0.1s intervals, evaluating the contrast of the piano row. Once the contrast delta drops below 5, it assumes the camera/render blur has resolved.
2. **Brightness Plateau:** It continues stepping until the total brightness delta of the row drops below 1000, ensuring any fade-in or opacity effects have completed.
3. **Manual Override:** If the user provides a manual start time, the auto-detect loop is bypassed, and the geometry is mapped directly from the specified frame.

### Key Mapping Logic (`mapKeys`)
The algorithm scans horizontal rows from the bottom of the frame upwards, looking for the row with the highest "contrast score" (distinct black keys separated by thin white slits).
1. **Binarization:** It converts the row to grayscale and applies dynamic thresholding.
2. **Pattern Matching:** It searches for the repeating pattern of black keys (groupings of 2 and 3). 
3. **Interpolation:** Once the 36 black keys are found, it uses the average black key width to mathematically interpolate the borders of the 52 white keys. The keys are built sequentially from A0 to C8.
4. **Vignette Compensation:** Because videos often have a vignette (darker edges), it calculates a smooth luminance envelope across the row and generates `vignetteGains`. This ensures that notes on the far edges of the piano are artificially boosted to match the brightness of the center keys.

---

## 3. Temporal Note Extraction (`note_extractor_service.dart`)

This is the core DSP (Digital Signal Processing) equivalent for pixels. It iterates through every extracted frame and evaluates the brightness of each of the 88 keys to determine Note On and Note Off events.

### The Problem: Light Bleed & Bloom
When a key lights up, it casts a heavy visual glow (bloom) onto adjacent keys. A naive threshold-based algorithm would falsely trigger the adjacent keys, causing chords to clump together. The engine uses two advanced visual heuristics to prevent this.

### Heuristic A: Temporal Edge Detection (Velocity)
Instead of looking at the absolute brightness (`currD = current - baseline`), the engine tracks the rate of change (`velocity = currD - prevD`) across a single frame.
- As light bloom washes over a key, the brightness ramps up slowly (e.g., +10 per frame).
- When a physical key is struck (or its LED activates), the brightness spikes violently (e.g., +100 in one frame).
- The engine demands a sharp `velocity` spike (e.g., `velocity >= 15`) to trigger a Note On. This ignores the approaching bloom and snaps the timing exactly to the impact frame.

### Heuristic B: Spatial Peak Isolation
To prevent adjacent keys from triggering during a bright chord, the engine enforces a strict spatial peak check.
- It compares the brightness of a key (`currD`) to its immediate left and right neighbors (`leftD` and `rightD`).
- Because light bloom spills outward from the physical strike, the true key is always the epicenter.
- A key is only allowed to trigger if it is structurally brighter than both of its neighbors. This mathematically annihilates false positives from light bleed.

### White Key Darkening Guarantee
White keys start at pure white (luminance 255). When pressed, they often turn a color (e.g., green, luminance 150). This results in a massive drop in luminance. Because light bleed (adding light) can never make a pure white pixel darker, any darkening on a white key is a 100% mathematical guarantee of a physical key press, allowing the engine to bypass the spatial/velocity checks entirely for white keys.

### Note Off & MIDI Encoding
- When the `detectHandSwitch` toggle is off, the engine uses ultra-strict drop-off tracking. If a key drops by 10 units from its absolute peak, it instantly cuts the note off, ignoring the long visual release tail.
- Finally, the `generateMidiFile` function sorts all Note On/Off events chronologically, calculates the delta times in milliseconds, and writes a standard Format 0 MIDI file using Variable Length Quantities (VLQ) for the delta ticks.

