"""MiniMax H3 Colab Runner Adapter for motion-explainer-video.

Bridges motion-explainer-video's `ai_video.py` with `minimax-h3-colab/scripts/runner.py`.
Enables running MiniMax H3 Reference-to-Video generation directly on Google Colab GPU (e.g. A100/L4),
removing the need for a local 26GB+ VRAM GPU.

Usage Modes:
1. Single clip mode (called automatically by ai_video.py run):
   python colab_runner.py {spec} --out {out} --prompt {prompt} --first-frame {first_frame}

2. Batch mode (recommended to reuse a single Colab session for all project clips):
   python colab_runner.py --batch --project <project_dir> [--gpu A100] [--session <session_name>]
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

sys.stdout.reconfigure(errors="replace")

DEFAULT_COLAB_RUNNER = Path("C:/Users/User/.gemini/config/skills/minimax-h3-colab/scripts/runner.py")


def find_colab_runner() -> Path:
    env_path = os.environ.get("MINIMAX_H3_COLAB_RUNNER")
    if env_path and Path(env_path).is_file():
        return Path(env_path).resolve()
    if DEFAULT_COLAB_RUNNER.is_file():
        return DEFAULT_COLAB_RUNNER.resolve()
    # Try searching relative to this skill
    candidate = Path(__file__).resolve().parents[2] / "minimax-h3-colab" / "scripts" / "runner.py"
    if candidate.is_file():
        return candidate.resolve()
    raise FileNotFoundError(
        f"Could not find minimax-h3-colab runner.py at {DEFAULT_COLAB_RUNNER}. "
        "Set MINIMAX_H3_COLAB_RUNNER environment variable to its path."
    )


def run_single(spec_file: Path, out_dir: Path, prompt_file: Path | None, first_frame: str | None, gpu: str, no_high_mem: bool) -> int:
    spec_file = spec_file.resolve()
    out_dir = out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    target_clip = out_dir / "clip.mp4"

    if target_clip.is_file() and target_clip.stat().st_size > 0:
        print(f"[skip] {target_clip.name} already exists in {out_dir}")
        return 0

    if not spec_file.is_file():
        sys.exit(f"Error: spec file not found: {spec_file}")

    spec = json.loads(spec_file.read_text(encoding="utf-8"))
    duration = float(spec.get("duration", 5.0))
    seed = spec.get("seed")

    # Locate prompt
    if prompt_file and Path(prompt_file).is_file():
        pf = Path(prompt_file).resolve()
    else:
        pf = out_dir / "prompt.txt"
        if not pf.is_file():
            # Build prompt using ai_video build_prompt if available
            try:
                import ai_video
                pf.write_text(ai_video.build_prompt(spec), encoding="utf-8")
            except Exception as e:
                sys.exit(f"Error: prompt file missing and could not auto-build: {e}")

    # Locate first frame image
    ff_path = None
    if first_frame and Path(first_frame).is_file():
        ff_path = Path(first_frame).resolve()
    elif spec.get("first_frame"):
        cand = (spec_file.parent / spec["first_frame"]).resolve()
        if cand.is_file():
            ff_path = cand

    if not ff_path or not ff_path.is_file():
        sys.exit(f"Error: MiniMax H3 Ref2VA requires a valid first frame image. Not found: {first_frame or spec.get('first_frame')}")

    runner_script = find_colab_runner()

    manifest_data = {
        "jobs": [
            {
                "title": out_dir.name,
                "reference_images": [str(ff_path)],
                "prompt_file": str(pf),
                "duration_seconds": duration,
                "seed": seed,
                "output_path": str(target_clip),
            }
        ]
    }

    temp_manifest = out_dir / f".h3_manifest_{uuid.uuid4().hex[:8]}.json"
    temp_manifest.write_text(json.dumps(manifest_data, ensure_ascii=False, indent=2), encoding="utf-8")

    cmd = [
        sys.executable,
        str(runner_script),
        "batch",
        "--manifest",
        str(temp_manifest),
        "--gpu",
        gpu,
        "--output-dir",
        str(out_dir),
    ]
    if no_high_mem:
        cmd.append("--no-high-mem")

    print(f"Calling Colab runner for {out_dir.name} (GPU: {gpu}, duration: {duration}s)...")
    try:
        res = subprocess.run(cmd)
        return res.returncode
    finally:
        temp_manifest.unlink(missing_ok=True)


def run_batch_project(project_dir: Path, gpu: str, no_high_mem: bool, session: str | None) -> int:
    project_dir = project_dir.resolve()
    specs_dir = project_dir / "assets" / "videos" / "gen" / "specs"
    if not specs_dir.is_dir():
        sys.exit(f"Error: specs directory not found: {specs_dir}")

    spec_files = sorted(specs_dir.glob("*.json"))
    if not spec_files:
        print("No spec files found in specs directory.")
        return 0

    runner_script = find_colab_runner()
    jobs = []

    for sp in spec_files:
        clip_name = sp.stem
        out_dir = project_dir / "assets" / "videos" / "gen" / clip_name
        target_clip = out_dir / "clip.mp4"

        if target_clip.is_file() and target_clip.stat().st_size > 0:
            print(f"[skip] {clip_name}: clip.mp4 already exists")
            continue

        out_dir.mkdir(parents=True, exist_ok=True)
        spec = json.loads(sp.read_text(encoding="utf-8"))
        duration = float(spec.get("duration", 5.0))
        seed = spec.get("seed")

        pf = out_dir / "prompt.txt"
        if not pf.is_file():
            try:
                import ai_video
                pf.write_text(ai_video.build_prompt(spec), encoding="utf-8")
            except Exception as e:
                print(f"[warn] {clip_name}: prompt.txt missing and could not auto-build: {e}")
                continue

        ff_path = None
        if spec.get("first_frame"):
            cand = (sp.parent / spec["first_frame"]).resolve()
            if cand.is_file():
                ff_path = cand

        if not ff_path:
            print(f"[warn] {clip_name}: first frame image missing, skipping")
            continue

        jobs.append({
            "title": clip_name,
            "reference_images": [str(ff_path)],
            "prompt_file": str(pf),
            "duration_seconds": duration,
            "seed": seed,
            "output_path": str(target_clip),
        })

    if not jobs:
        print("All clips are already generated or skipped.")
        return 0

    print(f"Queueing {len(jobs)} clip(s) to generate in a single Colab session:")
    for j in jobs:
        print(f" - {j['title']} ({j['duration_seconds']}s) -> {j['output_path']}")

    batch_manifest = project_dir / "assets" / "videos" / "gen" / f".batch_manifest_{uuid.uuid4().hex[:8]}.json"
    batch_manifest.write_text(json.dumps({"jobs": jobs}, ensure_ascii=False, indent=2), encoding="utf-8")

    cmd = [
        sys.executable,
        str(runner_script),
        "batch",
        "--manifest",
        str(batch_manifest),
        "--gpu",
        gpu,
        "--output-dir",
        str(project_dir / "assets" / "videos" / "gen"),
    ]
    if no_high_mem:
        cmd.append("--no-high-mem")
    if session:
        cmd.extend(["--session", session])

    try:
        res = subprocess.run(cmd)
        return res.returncode
    finally:
        batch_manifest.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description="MiniMax H3 Colab Runner Adapter")
    parser.add_argument("spec", nargs="?", help="Path to spec JSON file")
    parser.add_argument("--out", help="Output directory for clip")
    parser.add_argument("--prompt", help="Path to prompt.txt")
    parser.add_argument("--first-frame", dest="first_frame", help="Path to first frame still image")
    parser.add_argument("--gpu", default="A100", help="Colab GPU type (A100, L4, T4, etc., default: A100)")
    parser.add_argument("--no-high-mem", action="store_true", help="Disable high-memory allocation on Colab")

    # Batch mode options
    parser.add_argument("--batch", action="store_true", help="Run all pending specs in project in one Colab session")
    parser.add_argument("--project", help="Project root directory (required when using --batch)")
    parser.add_argument("--session", help="Existing Colab session name to reuse")

    args = parser.parse_args()

    if args.batch:
        if not args.project:
            sys.exit("Error: --project is required when using --batch")
        return run_batch_project(Path(args.project), args.gpu, args.no_high_mem, args.session)

    if not args.spec or not args.out:
        parser.print_help()
        sys.exit(1)

    return run_single(Path(args.spec), Path(args.out), Path(args.prompt) if args.prompt else None, args.first_frame, args.gpu, args.no_high_mem)


if __name__ == "__main__":
    raise SystemExit(main())
