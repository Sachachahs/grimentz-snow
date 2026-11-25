"""Prépare les dossiers natifs Android / iOS générés par `flutter create`.

Usage (depuis le dossier mobile/) :
    flutter create --org ch.grimentzsnow --project-name grimentz_snow --platforms=android,ios .
    python tool/setup_platforms.py

Le script est idempotent : il peut être relancé sans risque. Il règle :
- le nom affiché de l'application (« Grimentz Snow ») ;
- l'accès à Internet en version release (Android) ;
- l'ouverture des liens officiels dans le navigateur (Android 11+) ;
- les icônes de l'application (Android et iOS).
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "assets" / "icon"
APP_NAME = "Grimentz Snow"


def android():
    manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        print("Android : dossier absent (lancer flutter create d'abord)")
        return
    xml = manifest.read_text(encoding="utf-8")
    xml = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', xml, count=1)
    if "android.permission.INTERNET" not in xml:
        xml = re.sub(r"(<manifest[^>]*>)", r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>', xml, count=1)
    if 'android:scheme="https"' not in xml:
        query = ('        <intent>\n            <action android:name="android.intent.action.VIEW"/>\n'
                 '            <data android:scheme="https"/>\n        </intent>\n')
        if "<queries>" in xml:
            xml = xml.replace("<queries>", "<queries>\n" + query, 1)
        else:
            xml = xml.replace("</manifest>", "    <queries>\n" + query + "    </queries>\n</manifest>", 1)
    manifest.write_text(xml, encoding="utf-8")
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for d in (ICONS / "android").iterdir():
        target = res / d.name
        target.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(d / "ic_launcher.png", target / "ic_launcher.png")
    print("Android : nom, permission Internet, liens et icônes réglés")


def _resize(src: Path, dst: Path, px: int):
    try:
        from PIL import Image  # type: ignore
        Image.open(src).convert("RGB").resize((px, px), Image.LANCZOS).save(dst)
        return
    except ImportError:
        pass
    if shutil.which("sips"):
        shutil.copyfile(src, dst)
        subprocess.run(["sips", "-z", str(px), str(px), str(dst)], check=True, capture_output=True)
        return
    shutil.copyfile(src, dst)  # dernier recours : image non redimensionnée


def ios():
    plist = ROOT / "ios" / "Runner" / "Info.plist"
    if not plist.exists():
        print("iOS : dossier absent (normal sous Windows)")
        return
    text = plist.read_text(encoding="utf-8")
    text = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", rf"\g<1>{APP_NAME}\g<2>", text)
    plist.write_text(text, encoding="utf-8")
    icon_set = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = icon_set / "Contents.json"
    if contents.exists():
        src = ICONS / "icon_1024_square.png"
        for img in json.loads(contents.read_text(encoding="utf-8")).get("images", []):
            name = img.get("filename")
            if not name:
                continue
            size = float(img.get("size", "1024x1024").split("x")[0])
            scale = int(img.get("scale", "1x").rstrip("x"))
            _resize(src, icon_set / name, int(round(size * scale)))
    print("iOS : nom et icônes réglés")


def icons():
    if not (ICONS / "icon_1024.png").exists() or not (ICONS / "android").exists():
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import make_icons
        make_icons.main()


if __name__ == "__main__":
    icons()
    android()
    ios()
    sys.exit(0)
