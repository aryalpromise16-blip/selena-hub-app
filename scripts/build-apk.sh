#!/usr/bin/env bash
set -e

# 1. Create app shell
mkdir -p app/www
cd app
npm init -y >/dev/null
npm i @capacitor/core@6 @capacitor/cli@6 @capacitor/android@6 @capacitor/push-notifications@6
echo '<!doctype html><html><body>Loading Selena Hub…</body></html>' > www/index.html

cat > capacitor.config.json <<'CFG'
{
  "appId": "com.selenahub.app",
  "appName": "Selena Hub",
  "webDir": "www",
  "server": {
    "url": "https://selenahub.com/?app=android",
    "cleartext": false
  },
  "android": {
    "appendUserAgent": "SelenaHubApp"
  }
}
CFG

npx cap add android

# 2. Branding icons
pip install --break-system-packages pillow || pip install pillow
curl -sSL "https://selenahub.com/assets/selena-hub-logo-CSl0s06P.png" -o selena-logo.png || curl -sSL "https://selenahub.com/favicon.png" -o selena-logo.png

python3 - <<'PY'
import os
from PIL import Image

src_logo = "selena-logo.png"
img = Image.open(src_logo).convert("RGBA")
res_dir = "android/app/src/main/res"

densities = {
    "mipmap-mdpi": (48, 108),
    "mipmap-hdpi": (72, 162),
    "mipmap-xhdpi": (96, 216),
    "mipmap-xxhdpi": (144, 324),
    "mipmap-xxxhdpi": (192, 432)
}

for folder, (std_size, fg_size) in densities.items():
    target_folder = os.path.join(res_dir, folder)
    os.makedirs(target_folder, exist_ok=True)
    icon = img.resize((std_size, std_size), Image.Resampling.LANCZOS)
    icon.save(os.path.join(target_folder, "ic_launcher.png"), "PNG")
    icon.save(os.path.join(target_folder, "ic_launcher_round.png"), "PNG")
    fg = Image.new("RGBA", (fg_size, fg_size), (0, 0, 0, 0))
    content_size = int(fg_size * 0.72)
    scaled_logo = img.resize((content_size, content_size), Image.Resampling.LANCZOS)
    offset = (fg_size - content_size) // 2
    fg.paste(scaled_logo, (offset, offset), scaled_logo)
    fg.save(os.path.join(target_folder, "ic_launcher_foreground.png"), "PNG")

print("Generated launcher icons")
PY

cat > android/app/src/main/res/values/ic_launcher_background.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#23032b</color>
</resources>
XML

# 3. Permissions & signing
python3 - <<'PY'
manifest_path = "android/app/src/main/AndroidManifest.xml"
with open(manifest_path, "r", encoding="utf-8") as f:
    content = f.read()

permissions = """
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
"""

if "POST_NOTIFICATIONS" not in content:
    content = content.replace("<application", permissions + "\n    <application", 1)
    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Added notification permissions")

gradle_path = "android/app/build.gradle"
with open(gradle_path, "r", encoding="utf-8") as f:
    gradle = f.read()

signing = """
    signingConfigs {
        release {
            storeFile file("../../../signing/selena-release.p12")
            storePassword "selenahub2026"
            keyAlias "selena"
            keyPassword "selenahub2026"
            storeType "PKCS12"
        }
    }
"""

if "signingConfigs {" not in gradle:
    gradle = gradle.replace("buildTypes {", signing.strip() + "\n    buildTypes {", 1)
    gradle = gradle.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    if "signingConfig signingConfigs.release" not in gradle:
        gradle = gradle.replace("buildTypes {", "buildTypes {\n        release {\n            signingConfig signingConfigs.release\n        }", 1)
    with open(gradle_path, "w", encoding="utf-8") as f:
        f.write(gradle)
    print("Added release signing config")
PY

# 4. Copy google-services.json for push notifications
if [ -f ../google-services.json ]; then
  cp ../google-services.json android/app/google-services.json
  echo "Copied google-services.json to android/app/"
else
  echo "google-services.json not found!"
fi

npx cap sync android

# 5. Build APK
cd android
chmod +x gradlew
./gradlew assembleRelease assembleDebug --no-daemon

if [ -f app/build/outputs/apk/release/app-release.apk ]; then
  cp app/build/outputs/apk/release/app-release.apk ../selena-hub.apk
else
  cp app/build/outputs/apk/debug/app-debug.apk ../selena-hub.apk
fi
echo "APK build complete: app/selena-hub.apk"
