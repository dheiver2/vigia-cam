#!/usr/bin/env bash
# Empacota o vigia-cam como um .app do macOS e instala atalho na Área de Trabalho.
set -e
PROJ="$(cd "$(dirname "$0")" && pwd)"
APP="$PROJ/build/VigiaCam.app"
DESKTOP="$HOME/Desktop"

echo "→ Montando bundle em $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# ícone
cp "$PROJ/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Info.plist
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>VigiaCam</string>
  <key>CFBundleDisplayName</key><string>Vigia-Cam</string>
  <key>CFBundleIdentifier</key><string>ai.mangaba.vigiacam</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>VigiaCam</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# launcher: caminhos ABSOLUTOS + arch nativa (evita Rosetta/x86_64 no Finder).
NATIVE_ARCH="$(uname -m)"
cat > "$APP/Contents/MacOS/VigiaCam" <<LAUNCH
#!/bin/bash
PROJ="$PROJ"
ARCH="$NATIVE_ARCH"
LOG="\$PROJ/build/run.log"
mkdir -p "\$PROJ/build"
echo "=== \$(date) iniciando (arch \$ARCH) ===" >> "\$LOG"
cd "\$PROJ" || { echo "cd falhou" >> "\$LOG"; exit 1; }
if [ ! -x "\$PROJ/.venv/bin/python" ]; then
  arch -\$ARCH /usr/bin/python3 -m venv "\$PROJ/.venv" >> "\$LOG" 2>&1
  arch -\$ARCH "\$PROJ/.venv/bin/python" -m pip install -q --upgrade pip >> "\$LOG" 2>&1
  arch -\$ARCH "\$PROJ/.venv/bin/python" -m pip install -q -r "\$PROJ/requirements.txt" >> "\$LOG" 2>&1
fi
exec arch -\$ARCH "\$PROJ/.venv/bin/python" "\$PROJ/cameras_app/app.py" >> "\$LOG" 2>&1
LAUNCH
chmod +x "$APP/Contents/MacOS/VigiaCam"

# desregistra atributo de quarentena (evita aviso ao abrir local)
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "→ Instalando atalho na Área de Trabalho"
rm -rf "$DESKTOP/VigiaCam.app"
cp -R "$APP" "$DESKTOP/VigiaCam.app"

echo "✓ Pronto. Abra 'VigiaCam' na Área de Trabalho."
