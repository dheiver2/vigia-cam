#!/bin/bash
set -e
set -o pipefail

echo "🔨 Building VigiaCam..."
cd VigiaCam
swift build -c release 2>&1 | tail -30
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

if [ -d "VigiaCam/Sources/VigiaCam/Resources/ppe.mlpackage" ]; then
    cp -R VigiaCam/Sources/VigiaCam/Resources/ppe.mlpackage VigiaCam.app/Contents/Resources/
    echo "📦 Copied ppe.mlpackage to bundle"
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
    <string>2.4.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.4.0</string>
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

# Assinatura ESTÁVEL (Developer ID > Apple Development > ad-hoc). Ad-hoc gera
# uma assinatura diferente a cada build — o macOS trata cada versão como um app
# novo e o Keychain volta a pedir senha para a chave AES a cada atualização.
IDENTIDADE=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
if [ -z "$IDENTIDADE" ]; then
    IDENTIDADE=$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
fi
if [ -n "$IDENTIDADE" ]; then
    echo "🔏 Assinando com: $IDENTIDADE"
    codesign --force --deep --options runtime --sign "$IDENTIDADE" VigiaCam.app
else
    echo "🔏 Assinando (ad-hoc — nenhuma identidade encontrada)..."
    codesign --force --deep --sign - VigiaCam.app
fi

echo "✅ Done! Opening VigiaCam..."
echo "(build ok — não abrindo automaticamente)"
