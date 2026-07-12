#!/bin/bash
set -e

echo "🔨 Building VigiaCam..."
cd VigiaCam
swift build -c release 2>&1 | tail -3
cd ..

echo "📦 Creating .app bundle..."
rm -rf VigiaCam.app
mkdir -p VigiaCam.app/Contents/MacOS
mkdir -p VigiaCam.app/Contents/Resources
cp VigiaCam/.build/release/VigiaCam VigiaCam.app/Contents/MacOS/VigiaCam

# Copy model to Resources
if [ -d "VigiaCam/Sources/VigiaCam/Resources/yolov8n.mlpackage" ]; then
    cp -R VigiaCam/Sources/VigiaCam/Resources/yolov8n.mlpackage VigiaCam.app/Contents/Resources/
    echo "📦 Copied yolov8n.mlpackage to bundle"
fi

# Copy SPM resource bundle if exists
SPM_RESOURCES=$(find VigiaCam/.build -name "VigiaCam_VigiaCam.bundle" -type d 2>/dev/null | head -1)
if [ -n "$SPM_RESOURCES" ]; then
    cp -R "$SPM_RESOURCES" VigiaCam.app/Contents/Resources/
    echo "📦 Copied SPM resource bundle"
fi

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns VigiaCam.app/Contents/Resources/AppIcon.icns
    echo "🎨 Ícone AppIcon.icns aplicado."
else
    echo "⚠️  AppIcon.icns não encontrado na raiz do projeto — bundle sem ícone."
fi

cat > VigiaCam.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>VigiaCam</string>
    <key>CFBundleDisplayName</key>
    <string>VigiaCam</string>
    <key>CFBundleIdentifier</key>
    <string>com.vigiacam.app</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>VigiaCam</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSCameraUsageDescription</key>
    <string>VigiaCam precisa acessar a câmera para vigilância em tempo real.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>VigiaCam pode gravar áudio junto com vídeo.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🔏 Assinando (ad-hoc)..."
codesign --force --deep --sign - VigiaCam.app

echo "✅ Done! Opening VigiaCam..."
open VigiaCam.app
