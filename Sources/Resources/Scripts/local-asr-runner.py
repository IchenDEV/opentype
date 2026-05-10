#!/usr/bin/env python3
import argparse
import json
import pathlib
import sys


def qwen_language(code):
    return {
        "zh": "Chinese",
        "en": "English",
        "ja": "Japanese",
        "ko": "Korean",
        "yue": "Cantonese",
    }.get(code)


def mimo_tag(code):
    return {
        "zh": "<chinese>",
        "en": "<english>",
    }.get(code)


def transcribe_qwen(args):
    try:
        from qwen3_asr_mlx import Qwen3ASR
    except ImportError as exc:
        raise RuntimeError(
            "Missing qwen3-asr-mlx. Install it in this Python environment: "
            "pip install qwen3-asr-mlx"
        ) from exc

    model = Qwen3ASR.from_pretrained(args.model)
    kwargs = {}
    language = qwen_language(args.language)
    if language:
        kwargs["language"] = language
    result = model.transcribe(args.audio, **kwargs)
    return {
        "text": result.text,
        "language": getattr(result, "language", None),
        "duration": getattr(result, "duration", None),
    }


def transcribe_mimo(args):
    if args.repo:
        sys.path.insert(0, args.repo)
    try:
        from src.mimo_audio.mimo_audio import MimoAudio
    except ImportError as exc:
        raise RuntimeError(
            "Missing Xiaomi MiMo-V2.5-ASR repo. Set the repo path to the cloned "
            "XiaomiMiMo/MiMo-V2.5-ASR directory and install its requirements."
        ) from exc

    model = MimoAudio(model_path=args.model, tokenizer_path=args.tokenizer)
    tag = mimo_tag(args.language)
    if tag:
        text = model.asr_sft(args.audio, audio_tag=tag)
    else:
        text = model.asr_sft(args.audio)
    return {"text": text}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["qwen3", "mimo"], required=True)
    parser.add_argument("--audio", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--language")
    parser.add_argument("--tokenizer")
    parser.add_argument("--repo")
    args = parser.parse_args()

    audio_path = pathlib.Path(args.audio)
    if not audio_path.exists():
        raise FileNotFoundError(f"Audio file not found: {audio_path}")

    if args.provider == "qwen3":
        result = transcribe_qwen(args)
    else:
        if not args.tokenizer:
            raise ValueError("MiMo-V2.5-ASR requires --tokenizer")
        result = transcribe_mimo(args)

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
