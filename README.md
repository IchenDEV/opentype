<div align="center">

# OpenType

**Local AI-powered voice input for macOS menu bar**

---

[![GitHub Stars](https://img.shields.io/github/stars/IchenDEV/opentype?style=flat-square&logo=github&color=ffcc00)](https://github.com/IchenDEV/opentype/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/IchenDEV/opentype?style=flat-square&logo=github&color=4a90d9)](https://github.com/IchenDEV/opentype/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/IchenDEV/opentype?style=flat-square&logo=github&color=red)](https://github.com/IchenDEV/opentype/issues)
[![GitHub Trending](https://img.shields.io/badge/GitHub-Trending-brightgreen?style=flat-square&logo=github)](https://github.com/trending/swift)

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/mac/m1/)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

[![100% Local](https://img.shields.io/badge/100%25-Local%20%26%20Offline-success?style=flat-square&logo=shield)](https://github.com/IchenDEV/opentype)
[![No Cloud](https://img.shields.io/badge/No%20Cloud-Privacy%20First-purple?style=flat-square&logo=lock)](https://github.com/IchenDEV/opentype)
[![WhisperKit](https://img.shields.io/badge/Powered%20by-WhisperKit-blue?style=flat-square)](https://github.com/argmaxinc/WhisperKit)
[![MLX](https://img.shields.io/badge/Powered%20by-MLX--LM-orange?style=flat-square)](https://github.com/ml-explore/mlx-swift-lm)

[中文文档](README_zh.md)

</div>

---

## Overview

**OpenType** is a macOS menu bar app for local AI-powered voice input. It runs entirely on-device — no internet connection required after the initial model download. Simply hold a hotkey to start recording, release to transcribe, and the result is typed directly into whatever app you're using.

Two modes are supported:
- **Direct** — raw Whisper transcription, low latency
- **LLM Polish** — transcription cleaned up by a local Qwen3 model (removes filler words, fixes grammar, applies your personal style)

## Screenshot

<img src="Docs/menubar-popover.png" alt="OpenType menu bar popover" width="480" />

*The menu bar popover — showing the last transcription with one-click copy, language selection, and hotkey mode.*

## Features

| Feature | Description |
|---|---|
| **Offline Transcription** | WhisperKit-powered Whisper model, fully local |
| **LLM Text Polishing** | MLX + Qwen3-0.6B 4-bit, removes filler words and cleans up dictation |
| **Global Hotkey** | Hold Fn to record (Ctrl / Shift / Option / Fn — long-press, double-tap, or single-tap) |
| **Screen Context** | Captures on-screen text to help the LLM correct homophones |
| **Microphone Selection** | Choose any audio input device |
| **Sound Feedback** | Audio cues on recording start and stop |
| **Personal Dictionary** | Custom word replacements and LLM edit rules |
| **Language Style** | Concise / Formal / Casual / Custom prompt |

## System Requirements

- **OS**: macOS 26 (Tahoe) or later
- **Chip**: Apple Silicon (M1 / M2 / M3 / M4)
- **Disk**: ~2 GB (Whisper model ~1.5 GB + Qwen3 model ~335 MB)

## Build & Run

```bash
# Build (release)
swift build -c release

# Run
swift run OpenType

# Open in Xcode
open Package.swift
# Select the OpenType scheme → Release configuration → Run (⌘R)
```

## First Run

1. Click the microphone icon in the menu bar
2. Go to **Settings → Permissions** and grant Microphone and Accessibility access
3. Wait for the Whisper model to download (~1.5 GB, one-time)
4. Hold **Fn** to start dictating, release to stop and insert text

## Permissions

| Permission | Purpose | Required |
|---|---|---|
| Microphone | Capture audio input | Yes |
| Accessibility | Global hotkey + text injection (simulated ⌘V) | Yes |
| Speech Recognition | Apple on-device ASR (optional engine) | No |
| Screen Recording | Capture screen text for LLM context | No |
| Network | One-time model download | First run only |

## Project Structure

```
Sources/
├── App/          # Entry point, AppDelegate, AppState, VoicePipeline
├── Audio/        # Microphone capture, sound playback
├── Config/       # AppSettings (UserDefaults), model paths
├── Hotkey/       # Global hotkey via CGEvent tap
├── LLM/          # MLX-LM inference engine, prompt builder
├── Output/       # Text injection (clipboard + simulated paste)
├── Processing/   # Text cleanup, PersonalDictionary
├── Screen/       # Screen OCR (ScreenCaptureKit + Vision)
├── Speech/       # SpeechEngine protocol, WhisperKit, Apple Speech
└── UI/           # SwiftUI menu bar, settings sheet, floating HUD
```

## Tech Stack

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — offline Whisper speech recognition
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) — local LLM inference on Apple Silicon
- **SwiftUI + AppKit** — native macOS UI
- **ScreenCaptureKit + Vision** — screen OCR
- **AVAudioEngine** — low-latency microphone capture

---

<div align="center">

Made with ❤️ for Apple Silicon

</div>
