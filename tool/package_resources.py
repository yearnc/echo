#!/usr/bin/env python3
"""把本机模型目录打成 GitHub Release 资源包，并生成 manifest。

用法（在仓库根目录执行）：

    python tool/package_resources.py \
        --models-dir /path/to/assets/models \
        --out-dir /path/to/echo-models

输出：
    echo-models/echo-models-<id>-v1.zip
    echo-models/manifest.json

然后把 zip 上传到 Release `models-v1`，把 manifest.json 覆盖仓库里的
`resources/manifest.json`（或只把 version/bytes/sha256 同步过去）。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path

# id -> (源目录, 解压后的存储目录, 必需文件)
PACKAGES = {
    "asr": (
        "asr",
        "asr",
        ["model.int8.onnx", "tokens.txt"],
    ),
    "tts": (
        "tts",
        "vits-zh-ll",
        [
            "model.onnx",
            "lexicon.txt",
            "tokens.txt",
            "date.fst",
            "number.fst",
            "phone.fst",
        ],
    ),
    "zipvoice": (
        "zipvoice",
        "zipvoice",
        [
            "encoder.int8.onnx",
            "decoder.int8.onnx",
            "vocos_24khz.onnx",
            "tokens.txt",
            "lexicon.txt",
            "espeak-ng-data.zip",
        ],
    ),
    "asr-stream": (
        "asr-stream",
        "asr-stream",
        ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"],
    ),
}

TAG = "models-v1"
REPO = "https://github.com/yearnc/echo"


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description="打包 Echo 模型资源")
    parser.add_argument("--models-dir", required=True, help="assets/models 所在目录")
    parser.add_argument("--out-dir", required=True, help="zip 与 manifest 的输出目录")
    parser.add_argument("--manifest", help="可选的旧 manifest，用来保留 name/description")
    args = parser.parse_args()

    models_dir = Path(args.models_dir).expanduser().resolve()
    out_dir = Path(args.out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    old = {}
    if args.manifest:
        try:
            raw = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
            old = {item["id"]: item for item in raw.get("resources", [])}
        except Exception as error:  # noqa: BLE001 - 只是尽量保留旧文案
            print(f"[warn] 旧 manifest 读不出来，忽略：{error}", file=sys.stderr)

    resources = []
    for resource_id, (source_name, storage_dir, required) in PACKAGES.items():
        source = models_dir / source_name
        if not source.is_dir():
            print(f"[skip] {source} 不存在", file=sys.stderr)
            continue
        missing = [name for name in required if not (source / name).is_file()]
        if missing:
            print(f"[skip] {source} 缺文件：{', '.join(missing)}", file=sys.stderr)
            continue

        zip_path = out_dir / f"echo-models-{resource_id}-v1.zip"
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
            for file in sorted(source.rglob("*")):
                if not file.is_file():
                    continue
                arcname = file.relative_to(source).as_posix()
                if arcname in {"_placeholder.txt", "LICENSE"}:
                    continue
                zf.write(file, arcname)

        size = zip_path.stat().st_size
        digest = sha256_of(zip_path)
        url = f"{REPO}/releases/download/{TAG}/{zip_path.name}"
        meta = old.get(resource_id, {})
        resources.append(
            {
                "id": resource_id,
                "name": meta.get("name", resource_id),
                "description": meta.get("description", ""),
                "storage_dir": storage_dir,
                "required_files": required,
                "version": 1,
                "bytes": size,
                "sha256": digest,
                "url": url,
                "mirror_url": f"https://gh-proxy.com/{url}",
            }
        )
        print(f"[ok] {zip_path.name}  {size / 1024 / 1024:.1f} MB  {digest[:12]}…")

    manifest = {
        "schema": 1,
        "tag": TAG,
        "resources": resources,
    }
    target = out_dir / "manifest.json"
    target.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[ok] {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
