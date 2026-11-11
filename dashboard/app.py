import os
import subprocess
import threading
import json
from pathlib import Path
from collections import OrderedDict
from flask import Flask, jsonify, request, Response, abort

app = Flask(__name__)

MEDIA_ROOT = Path("/mnt/usb/Linux/myworkspace/temp_folder").resolve()

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".webm",".m4v", ".ts", ".m2ts", ".mpg", ".mpeg",".wmv", ".flv", ".3gp", ".mts"}

MAX_CACHE_BYTES = 100 * 1024 * 1024

cache = OrderedDict()
cache_size = 0
cache_lock = threading.Lock()
ffmpeg_slots = threading.Semaphore(2)


def media_ready():
    return MEDIA_ROOT.is_dir() and os.path.ismount(MEDIA_ROOT)


def safe_video_path(relative_path):
    try:
        candidate = (MEDIA_ROOT / relative_path).resolve(strict=True)
        candidate.relative_to(MEDIA_ROOT)

        if not candidate.is_file():
            abort(404)

        if candidate.suffix.lower() not in VIDEO_EXTENSIONS:
            abort(404)

        return candidate

    except (ValueError, FileNotFoundError):
        abort(404)


def get_embedded_thumbnail(video_path):
    """Extract an attached picture if the file contains one."""

    probe = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-select_streams", "v",
            "-show_entries", "stream=index:stream_disposition=attached_pic",
            "-of", "json", str(video_path)
        ],
        capture_output=True,
        text=True,
        timeout=15
    )

    if probe.returncode != 0:
        return None

    try:
        streams = json.loads(probe.stdout).get("streams", [])
        for stream in streams:
            if stream.get("disposition", {}).get("attached_pic") == 1:
                result = subprocess.run(
                    [
                        "ffmpeg", "-hide_banner", "-loglevel", "error",
                        "-i", str(video_path),
                        "-map", f"0:{stream['index']}",
                        "-frames:v", "1",
                        "-q:v", "2",
                        "-f", "image2pipe",
                        "-vcodec", "mjpeg",
                        "pipe:1"
                    ],
                    capture_output=True,
                    timeout=20
                )

                if result.returncode == 0 and result.stdout:
                    return result.stdout

    except (ValueError, KeyError, subprocess.TimeoutExpired):
        pass

    return None


def frame_score(image):
    """Score brightness, contrast and visual detail using FFmpeg."""

    result = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-i", "pipe:0",
            "-frames:v", "1",
            "-vf", "scale=320:-2,format=gray,"
                   "signalstats,metadata=print",
            "-f", "null", "-"
        ],
        input=image,
        capture_output=True,
        timeout=15
    )

    output = result.stderr.decode(errors="ignore")

    values = {}
    for line in output.splitlines():
        if "lavfi.signalstats." in line and "=" in line:
            key, value = line.split("=", 1)
            try:
                values[key.strip().split(".")[-1]] = float(value.strip())
            except ValueError:
                pass

    brightness = values.get("YAVG", 0)
    contrast = values.get("YHIGH", 0) - values.get("YLOW", 0)

    # Reject nearly black and very flat frames.
    if brightness < 12 or contrast < 18:
        return 0

    return brightness + contrast * 0.5


def generate_thumbnail(video_path):
    """Find a useful frame and extract it at original resolution."""

    embedded = get_embedded_thumbnail(video_path)
    if embedded:
        return embedded

    duration_result = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(video_path)
        ],
        capture_output=True,
        text=True,
        timeout=15
    )

    try:
        duration = float(duration_result.stdout.strip())
    except (ValueError, TypeError):
        duration = 60

    # Sample up to 8 positions, avoiding the very beginning and end.
    positions = [
        duration * fraction
        for fraction in (0.03, 0.10, 0.20, 0.35,
                         0.50, 0.65, 0.80, 0.92)
    ]

    best_score = -1
    best_position = None

    for position in positions:
        result = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error",
                "-ss", str(position),
                "-i", str(video_path),
                "-frames:v", "1",
                "-f", "image2pipe",
                "-vcodec", "mjpeg",
                "-q:v", "2",
                "pipe:1"
            ],
            capture_output=True,
            timeout=25
        )

        if result.returncode != 0 or not result.stdout:
            continue

        score = frame_score(result.stdout)

        if score > best_score:
            best_score = score
            best_position = position

    if best_position is None:
        abort(422)

    # Extract the winning frame again, preserving original resolution.
    final_result = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-ss", str(best_position),
            "-i", str(video_path),
            "-frames:v", "1",
            "-q:v", "2",
            "-f", "image2pipe",
            "-vcodec", "mjpeg",
            "pipe:1"
        ],
        capture_output=True,
        timeout=30
    )

    if final_result.returncode != 0 or not final_result.stdout:
        abort(422)

    return final_result.stdout


@app.get("/api/health")
def health():
    return jsonify({
        "status": "ready" if media_ready() else "media_locked"
    })


@app.get("/api/videos")
def videos():
    if not media_ready():
        return jsonify({"error": "Media folder is locked"}), 503

    results = []

    for folder, _, filenames in os.walk(MEDIA_ROOT):
        for filename in filenames:
            path = Path(folder) / filename

            if path.suffix.lower() not in VIDEO_EXTENSIONS:
                continue

            relative = path.relative_to(MEDIA_ROOT).as_posix()

            results.append({
                "name": filename,
                "path": relative
            })

    results.sort(key=lambda item: item["name"].lower())

    return jsonify(results)


@app.get("/api/thumb")
def thumbnail():
    global cache_size

    relative_path = request.args.get("path", "")

    if not media_ready():
        return jsonify({"error": "Media folder is locked"}), 503

    video_path = safe_video_path(relative_path)

    stat = video_path.stat()
    cache_key = (relative_path, stat.st_size, stat.st_mtime_ns)

    with cache_lock:
        if cache_key in cache:
            data = cache.pop(cache_key)
            cache[cache_key] = data
            return Response(
                data,
                mimetype="image/jpeg",
                headers={"Cache-Control": "no-store"}
            )

    with ffmpeg_slots:
        data = generate_thumbnail(video_path)

    if not data:
        abort(422)

    with cache_lock:
        cache[cache_key] = data
        cache_size += len(data)

        while cache_size > MAX_CACHE_BYTES and cache:
            _, removed = cache.popitem(last=False)
            cache_size -= len(removed)

    return Response(
        data,
        mimetype="image/jpeg",
        headers={"Cache-Control": "no-store"}
    )


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)
