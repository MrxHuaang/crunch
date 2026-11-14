"""Exporta la imagen de cada pase y producto (items.html) a art/promo/items/<id>.png con Chrome sin ventana.

    python art/promo/render_items.py            # todas
    python art/promo/render_items.py vip sack   # solo esas
"""

import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "items"
CHROME_PATHS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "google-chrome",
]


def chrome() -> str:
    for p in CHROME_PATHS:
        if Path(p).exists() or "/" not in p and "\\" not in p:
            return p
    raise SystemExit("No encuentro Chrome")


def all_ids() -> list[str]:
    src = (HERE / "items.html").read_text(encoding="utf-8")
    block = src.split("const ITEMS = {", 1)[1].split("\n};", 1)[0]
    return re.findall(r"^\s+(\w+):\s+\[", block, re.M)


def main() -> None:
    OUT.mkdir(exist_ok=True)
    ids = sys.argv[1:] or all_ids()
    exe = chrome()
    for item in ids:
        url = (HERE / "items.html").as_uri() + f"?id={item}"
        out = OUT / f"{item}.png"
        subprocess.run(
            [exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--window-size=512,512",
             "--virtual-time-budget=4000", f"--screenshot={out}", url],
            check=True, capture_output=True,
        )
        print(out.relative_to(HERE.parent.parent))


if __name__ == "__main__":
    main()
