#!/usr/bin/env python3
"""Compare opt-in VitalScore debug WAV exports with canonical openSMILE eGeMAPS.

This script expects a local openSMILE install with SMILExtract available.
It does not upload audio and it does not require network access.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


SCHEMA_VERSION = "vitalscore_opensmile_egemaps_comparison_v1"

VALIDATION_CATALOG: dict[str, dict[str, Any]] = {
    "loudnessMeanDb": {
        "label": "Loudness mean",
        "status": "proxy",
        "scoreEligible": True,
        "note": "RMS dB proxy; compare against openSMILE loudness.",
    },
    "loudnessStdDevDb": {
        "label": "Loudness variation",
        "status": "proxy",
        "scoreEligible": True,
        "note": "RMS dB variability proxy.",
    },
    "f0MeanHz": {
        "label": "F0 mean",
        "status": "proxy",
        "scoreEligible": False,
        "note": "Autocorrelation pitch estimate; withheld from scoring.",
    },
    "f0StdDevHz": {
        "label": "F0 variation",
        "status": "proxy",
        "scoreEligible": False,
        "note": "Autocorrelation pitch variation; withheld from scoring.",
    },
    "jitterLocalPercent": {
        "label": "Jitter local",
        "status": "unsupported",
        "scoreEligible": False,
        "note": "Frame-level approximation, not cycle-level jitter.",
    },
    "shimmerLocalDb": {
        "label": "Shimmer local",
        "status": "unsupported",
        "scoreEligible": False,
        "note": "Frame-level dB delta, not cycle-level shimmer.",
    },
    "hnrMeanDb": {
        "label": "HNR mean",
        "status": "proxy",
        "scoreEligible": False,
        "note": "Autocorrelation harmonicity proxy; withheld from scoring.",
    },
    "spectralFlux": {
        "label": "Spectral flux",
        "status": "proxy",
        "scoreEligible": True,
        "note": "Frame-to-frame energy movement proxy.",
    },
    "mfcc1Mean": {
        "label": "MFCC 1",
        "status": "unsupported",
        "scoreEligible": False,
        "note": "Placeholder transform, not canonical MFCC.",
    },
    "mfcc2Mean": {
        "label": "MFCC 2",
        "status": "unsupported",
        "scoreEligible": False,
        "note": "Placeholder transform, not canonical MFCC.",
    },
    "mfcc3Mean": {
        "label": "MFCC 3",
        "status": "unsupported",
        "scoreEligible": False,
        "note": "Placeholder transform, not canonical MFCC.",
    },
    "voicedSegmentsPerSecond": {
        "label": "Voiced segment rate",
        "status": "proxy",
        "scoreEligible": True,
        "note": "Silence-threshold segment proxy.",
    },
    "meanVoicedSegmentLengthSeconds": {
        "label": "Mean voiced length",
        "status": "proxy",
        "scoreEligible": True,
        "note": "Silence-threshold segment proxy.",
    },
}

SWIFT_FEATURE_KEYS = {
    "loudnessMeanDb": "loudness_mean_db",
    "loudnessStdDevDb": "loudness_std_dev_db",
    "f0MeanHz": "f0_mean_hz",
    "f0StdDevHz": "f0_std_dev_hz",
    "jitterLocalPercent": "jitter_local_percent",
    "shimmerLocalDb": "shimmer_local_db",
    "hnrMeanDb": "hnr_mean_db",
    "spectralFlux": "spectral_flux",
    "mfcc1Mean": "mfcc1_mean",
    "mfcc2Mean": "mfcc2_mean",
    "mfcc3Mean": "mfcc3_mean",
    "voicedSegmentsPerSecond": "voiced_segments_per_second",
    "meanVoicedSegmentLengthSeconds": "mean_voiced_segment_length_seconds",
}


def semitone_from_27_5_to_hz(value: float) -> float:
    return 27.5 * (2 ** (value / 12.0))


OPENSMILE_FEATURES: dict[str, tuple[str, Callable[[float], float] | None]] = {
    "loudnessMeanDb": ("loudness_sma3_amean", None),
    "loudnessStdDevDb": ("loudness_sma3_stddevNorm", None),
    "f0MeanHz": ("F0semitoneFrom27.5Hz_sma3nz_amean", semitone_from_27_5_to_hz),
    "f0StdDevHz": ("F0semitoneFrom27.5Hz_sma3nz_stddevNorm", None),
    "jitterLocalPercent": ("jitterLocal_sma3nz_amean", lambda value: value * 100),
    "shimmerLocalDb": ("shimmerLocaldB_sma3nz_amean", None),
    "hnrMeanDb": ("HNRdBACF_sma3nz_amean", None),
    "spectralFlux": ("spectralFlux_sma3_amean", None),
    "mfcc1Mean": ("mfcc1_sma3_amean", None),
    "mfcc2Mean": ("mfcc2_sma3_amean", None),
    "mfcc3Mean": ("mfcc3_sma3_amean", None),
    "voicedSegmentsPerSecond": ("VoicedSegmentsPerSec", None),
    "meanVoicedSegmentLengthSeconds": ("MeanVoicedSegmentLengthSec", None),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wav-dir", type=Path, required=True, help="Directory containing a VitalScore debug WAV manifest or WAV files.")
    parser.add_argument("--app-export", type=Path, help="Optional VitalScore analysis export JSON to compare against.")
    parser.add_argument("--output", type=Path, help="Optional output JSON path. Defaults to stdout.")
    parser.add_argument("--smilextract", default=shutil.which("SMILExtract"), help="Path to openSMILE SMILExtract.")
    parser.add_argument("--egemaps-config", type=Path, help="Path to eGeMAPSv02.conf.")
    args = parser.parse_args()
    if args.egemaps_config is None:
        args.egemaps_config = find_default_egemaps_config()
    return args


def find_default_egemaps_config() -> Path | None:
    env_path = os.environ.get("OPENSMILE_EGEMAPS_CONFIG")
    candidates = [
        Path(env_path) if env_path else None,
        Path("/opt/homebrew/share/opensmile/config/egemaps/v02/eGeMAPSv02.conf"),
        Path("/usr/local/share/opensmile/config/egemaps/v02/eGeMAPSv02.conf"),
        Path("/usr/share/opensmile/config/egemaps/v02/eGeMAPSv02.conf"),
    ]
    for candidate in candidates:
        if candidate and candidate.exists():
            return candidate
    return None


def load_manifest(wav_dir: Path) -> dict[str, Any] | None:
    manifest_path = wav_dir / "manifest.json"
    if not manifest_path.exists():
        return None
    return json.loads(manifest_path.read_text(encoding="utf-8"))


def discover_samples(wav_dir: Path, manifest: dict[str, Any] | None) -> list[dict[str, Any]]:
    if manifest:
        samples = []
        for sample in manifest.get("samples", []):
            wav_path = wav_dir / sample["fileName"]
            if wav_path.exists():
                item = dict(sample)
                item["path"] = str(wav_path)
                samples.append(item)
        return samples

    return [
        {
            "promptId": path.stem,
            "fileName": path.name,
            "path": str(path),
            "taskType": "unknown",
        }
        for path in sorted(wav_dir.glob("*.wav"))
    ]


def load_feature_vector(path: Path | None) -> dict[str, float]:
    if not path:
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload.get("featureVector") or {}


def run_opensmile(smilextract: str, config: Path, wav_path: Path) -> dict[str, float]:
    with tempfile.TemporaryDirectory() as temp_dir:
        output_path = Path(temp_dir) / "egemaps.csv"
        subprocess.run(
            [
                smilextract,
                "-C",
                str(config),
                "-I",
                str(wav_path),
                "-O",
                str(output_path),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return parse_opensmile_csv(output_path)


def parse_opensmile_csv(path: Path) -> dict[str, float]:
    text = path.read_text(encoding="utf-8", errors="replace")
    sample = text[:2048]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;")
    except csv.Error:
        dialect = csv.excel

    rows = list(csv.DictReader(text.splitlines(), dialect=dialect))
    if not rows:
        return {}
    row = rows[-1]
    parsed: dict[str, float] = {}
    for key, value in row.items():
        try:
            parsed[key] = float(value)
        except (TypeError, ValueError):
            continue
    return parsed


def swift_value(feature_vector: dict[str, float], prompt_id: str, key: str) -> float | None:
    suffix = SWIFT_FEATURE_KEYS[key]
    task_key = f"voice.task.{sanitize_feature_key(prompt_id)}.egemaps.{suffix}"
    aggregate_key = f"voice.egemaps.{suffix}"
    value = feature_vector.get(task_key, feature_vector.get(aggregate_key))
    return float(value) if value is not None else None


def open_smile_value(features: dict[str, float], key: str) -> tuple[str, float | None]:
    feature_name, transform = OPENSMILE_FEATURES[key]
    raw_value = features.get(feature_name)
    if raw_value is None:
        return feature_name, None
    return feature_name, transform(raw_value) if transform else raw_value


def compare_value(swift: float | None, opensmile: float | None) -> dict[str, float | None]:
    if swift is None or opensmile is None:
        return {"delta": None, "relativeDelta": None}
    delta = swift - opensmile
    relative = delta / opensmile if abs(opensmile) > 1e-9 else None
    return {"delta": delta, "relativeDelta": relative}


def sanitize_feature_key(value: str) -> str:
    return "".join(character if character.isalnum() else "_" for character in value)


def main() -> int:
    args = parse_args()
    manifest = load_manifest(args.wav_dir)
    samples = discover_samples(args.wav_dir, manifest)
    feature_vector = load_feature_vector(args.app_export)

    available = bool(args.smilextract and args.egemaps_config and Path(args.smilextract).exists())
    result: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "wavDirectory": str(args.wav_dir),
        "appExport": str(args.app_export) if args.app_export else None,
        "openSMILE": {
            "available": available,
            "SMILExtract": str(args.smilextract) if args.smilextract else None,
            "eGeMAPSConfig": str(args.egemaps_config) if args.egemaps_config else None,
        },
        "featureValidation": [
            {"key": key, **validation}
            for key, validation in VALIDATION_CATALOG.items()
        ],
        "comparisons": [],
    }

    if not available:
        result["openSMILE"]["error"] = "SMILExtract or eGeMAPSv02.conf was not found. Install openSMILE and rerun."
    for sample in samples:
        wav_path = Path(sample["path"])
        opensmile_features = run_opensmile(args.smilextract, args.egemaps_config, wav_path) if available else {}
        feature_comparisons = []
        for key, validation in VALIDATION_CATALOG.items():
            swift = swift_value(feature_vector, sample.get("promptId", wav_path.stem), key)
            opensmile_name, canonical = open_smile_value(opensmile_features, key)
            deltas = compare_value(swift, canonical)
            feature_comparisons.append(
                {
                    "key": key,
                    "label": validation["label"],
                    "status": validation["status"],
                    "scoreEligible": validation["scoreEligible"],
                    "swiftValue": swift,
                    "openSMILEFeature": opensmile_name,
                    "openSMILEValue": canonical,
                    "delta": deltas["delta"],
                    "relativeDelta": deltas["relativeDelta"],
                }
            )

        result["comparisons"].append(
            {
                "fileName": sample.get("fileName", wav_path.name),
                "promptId": sample.get("promptId"),
                "taskType": sample.get("taskType"),
                "status": sample.get("status"),
                "features": feature_comparisons,
            }
        )

    output_text = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output_text + "\n", encoding="utf-8")
    else:
        print(output_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
