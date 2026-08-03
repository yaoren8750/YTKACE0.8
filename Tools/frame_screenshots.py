from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "screenshots" / "source"
OUTPUT = ROOT / "screenshots" / "framed"
FRAME = ROOT / "screenshots" / "phone-template-product-red.png"
NAMES = (
    "settings",
    "player-settings",
    "sponsorblock-settings",
    "tab-editor",
    "video-download-menu",
    "shorts-download-menu",
    "download-library",
    "download-progress",
    "video-player",
    "audio-player",
    "audio-queue",
)


def contain(image, size):
    scale = min(size[0] / image.width, size[1] / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", size, (0, 0, 0, 255))
    left = (size[0] - resized.width) // 2
    top = (size[1] - resized.height) // 2
    canvas.alpha_composite(resized, (left, top))
    return canvas


def source_path(name):
    for suffix in (".png", ".jpg", ".jpeg"):
        path = SOURCE / f"{name}{suffix}"
        if path.exists():
            return path
    raise FileNotFoundError(name)


def frame(path, phone):
    display = (191, 109, 833, 1454)
    size = (display[2] - display[0], display[3] - display[1])
    screen = contain(Image.open(path).convert("RGBA"), size)
    mask = Image.new("L", phone.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(display, radius=76, fill=255)

    canvas = Image.new("RGBA", phone.size, (0, 0, 0, 0))
    canvas.paste(screen, display[:2], mask.crop(display))
    canvas.alpha_composite(phone)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    result = canvas.resize((800, 1200), Image.Resampling.LANCZOS)
    result.save(OUTPUT / f"{path.stem}.png", optimize=True)


phone_image = Image.open(FRAME).convert("RGBA")
for name in NAMES:
    frame(source_path(name), phone_image)
