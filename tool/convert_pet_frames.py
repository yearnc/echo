"""把 dsh-pet 的 webm 动画转成桌宠用的无损 WebP 帧序列。

用法（在 Echo 仓库根目录）：
    python tool/convert_pet_frames.py            # 全部 106 个动作
    python tool/convert_pet_frames.py --limit 3  # 只转前 3 个，先看效果
    python tool/convert_pet_frames.py --only act_001

libvpx 解出 RGBA（保留 alpha），在整段里均匀抽 FRAME_COUNT 帧，
缩到 320×180，把 alpha≤8 的压缩噪声归零，再存无损 WebP。
（2026-10-29 排查过：真机上“桌宠发虚”不是 WebP 的锅，是舞台窗带了
FLAG_NOT_TOUCHABLE 被系统压了不透明度；所以 WebP 可以继续用。）
改这里以后记得同步 manifest 的 frames 和护栏测试。
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

FRAME_COUNT = 48
IMAGE_SIZE = (320, 180)
SOURCE_SIZE = (640, 360)
ALPHA_FLOOR = 8

ECHO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAME_DIR = os.path.join(ECHO_ROOT, "assets", "pet_frames")
MANIFEST = os.path.join(FRAME_DIR, "manifest.json")
# 素材源与 ffmpeg 都从命令行/环境变量给，不要把本机路径写进公开仓库：
#   python tool/convert_pet_frames.py --webm-dir <dsh-pet>/assets/webm --ffmpeg <ffmpeg 路径>
WEBM_DIR = os.environ.get("DSH_PET_WEBM_DIR", "")
FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
FRAME_BYTES = SOURCE_SIZE[0] * SOURCE_SIZE[1] * 4


def decode_rgba(path: str) -> bytes:
    """一次解码整段视频。vp9 的 alpha 要显式指定 libvpx-vp9 才有。"""
    cmd = [
        FFMPEG,
        "-loglevel",
        "error",
        "-c:v",
        "libvpx-vp9",
        "-i",
        path,
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgba",
        "-",
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode("utf-8", "replace")[:400])
    return result.stdout


def pick_indices(total: int, count: int) -> list[int]:
    if total <= 0:
        return []
    if total <= count:
        return list(range(total))
    if count == 1:
        return [total - 1]
    return [round((total - 1) * i / (count - 1)) for i in range(count)]


def write_frames(action: dict, raw: bytes) -> int:
    if len(raw) % FRAME_BYTES != 0:
        raise RuntimeError(
            f"解码结果不是 {SOURCE_SIZE[0]}x{SOURCE_SIZE[1]} 的整帧"
            f"（{len(raw)} 字节除不尽 {FRAME_BYTES}）；先确认源片分辨率"
        )
    total = len(raw) // FRAME_BYTES
    indices = pick_indices(total, FRAME_COUNT)
    if len(indices) < FRAME_COUNT:
        # 少写几帧也会让 manifest 与实际素材对不上，宁可不覆盖旧的一整套。
        raise RuntimeError(
            f"源片只有 {total} 帧，凑不满 {FRAME_COUNT} 帧；"
            "请换更长的源片，或先改 FRAME_COUNT 和护栏测试"
        )

    written = set()
    for index, source_index in enumerate(indices):
        offset = source_index * FRAME_BYTES
        frame = Image.frombytes(
            "RGBA", SOURCE_SIZE, raw[offset : offset + FRAME_BYTES]
        )
        frame = frame.resize(IMAGE_SIZE, Image.LANCZOS)
        pixels = np.array(frame)
        pixels[pixels[..., 3] <= ALPHA_FLOOR, 3] = 0
        frame = Image.fromarray(pixels)
        name = f"{action['key']}_{index:02d}.webp"
        frame.save(
            os.path.join(FRAME_DIR, name),
            "WEBP",
            lossless=True,
            quality=100,
            method=4,
        )
        written.add(name)

    # 清掉这个动作多出来的旧帧（以前帧数更多、或旧版留下的 PNG），
    # 否则它们会一起进 APK，而护栏只查首尾帧，看不出来。
    prefix = f"{action['key']}_"
    for old in os.listdir(FRAME_DIR):
        if not old.startswith(prefix) or old in written:
            continue
        if old.endswith(".webp") or old.endswith(".png"):
            os.remove(os.path.join(FRAME_DIR, old))
    return len(indices)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--only", default="")
    parser.add_argument("--webm-dir", default="")
    parser.add_argument("--ffmpeg", default="")
    args = parser.parse_args()

    global WEBM_DIR, FFMPEG
    if args.webm_dir:
        WEBM_DIR = args.webm_dir
    if args.ffmpeg:
        FFMPEG = args.ffmpeg
    if not WEBM_DIR:
        print(
            "请用 --webm-dir（或环境变量 DSH_PET_WEBM_DIR）指定 dsh-pet 的 webm 目录",
            flush=True,
        )
        return 1

    with open(MANIFEST, encoding="utf-8") as handle:
        manifest = json.load(handle)
    actions = manifest["actions"]
    if args.only:
        actions = [a for a in actions if a["key"] == args.only]
        if not actions:
            print(f"manifest 里没有动作 {args.only}", flush=True)
            return 2
    if args.limit:
        actions = actions[: args.limit]

    failures = 0
    for position, action in enumerate(actions, 1):
        source = os.path.join(WEBM_DIR, f"{action['name']}.webm")
        if not os.path.exists(source):
            print(f"[{position}/{len(actions)}] 找不到 {source}", flush=True)
            failures += 1
            continue
        try:
            raw = decode_rgba(source)
            written = write_frames(action, raw)
        except Exception as error:  # noqa: BLE001 - 一个坏片不该拖死整批
            print(
                f"[{position}/{len(actions)}] {action['key']} "
                f"{action['name']} 失败：{error}",
                flush=True,
            )
            failures += 1
            continue
        print(
            f"[{position}/{len(actions)}] {action['key']} {action['name']} "
            f"({written} 帧)",
            flush=True,
        )

    if not args.limit and not args.only and failures == 0:
        for action in manifest["actions"]:
            action["frames"] = FRAME_COUNT
        with open(MANIFEST, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        print(f"manifest.json 已更新为 {FRAME_COUNT} 帧", flush=True)
    if failures:
        print(
            f"有 {failures} 个动作没转成功；manifest 保持原样，先修好再重跑",
            flush=True,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
