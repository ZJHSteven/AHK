"""校验 Codex 预设文件。

这个脚本只做语法校验，不打印文件内容，避免把 auth.json 里的密钥输出到终端。

用法：
    python tools/validate_codex_profile.py <auth.json> <config.toml>
"""

from __future__ import annotations

import json
import sys
import tomllib
from pathlib import Path


def main(argv: list[str]) -> int:
    """读取两个路径并校验 JSON / TOML 语法。

    参数：
        argv: 命令行参数，必须包含 auth.json 和 config.toml 两个路径。

    返回：
        0 表示两份文件都可解析；1 表示参数、文件或语法有问题。
    """

    if len(argv) != 3:
        print("usage: validate_codex_profile.py <auth.json> <config.toml>")
        return 1

    auth_path = Path(argv[1])
    config_path = Path(argv[2])

    try:
        with auth_path.open("r", encoding="utf-8-sig") as auth_file:
            json.load(auth_file)
    except Exception as exc:  # noqa: BLE001 - 这里要把 JSON 解析错误压成简短提示。
        print(f"auth.json 校验失败：{type(exc).__name__}: {exc}")
        return 1

    try:
        with config_path.open("rb") as config_file:
            tomllib.load(config_file)
    except Exception as exc:  # noqa: BLE001 - 同上，只输出错误类型与位置，不输出配置内容。
        print(f"config.toml 校验失败：{type(exc).__name__}: {exc}")
        return 1

    print("OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

