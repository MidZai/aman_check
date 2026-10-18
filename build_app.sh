#!/bin/bash
# Construit « Aman Check.app » (même méthode qu'Aman Disk : SwiftPM + bundle fait main).
#   ./build_app.sh               → architecture de cette machine (développement)
#   UNIVERSAL=1 ./build_app.sh   → binaire universel, puis scripts/make-dmg.sh pour le DMG
#
# Signature : ad hoc par défaut (pas de compte développeur). Pour une distribution,
# scripts/notarize.sh (Developer ID + notarisation, docs/RELEASE.md). Ne pas changer ce défaut.
# Hardened Runtime activé (--options runtime) : sans lui, les entitlements caméra / micro
# n'ont aucun effet, ce qui empêchait la caméra de s'afficher dans la version précédente.
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-1.1.0}"
# Numéro de build : nombre de commits, ou 1 hors dépôt git. Date de compilation : lue par l'app
# (point fort « dernier macOS » uniquement si cette version a moins de 18 mois).
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
BUILD_DATE="$(date -u +%Y-%m-%d)"
# UNIVERSAL=1 : binaire universel (Apple Silicon + Intel) pour une distribution, comme Aman Disk.
# Une compilation par architecture (--triple ne demande pas xcbuild), puis lipo.
UNIVERSAL="${UNIVERSAL:-0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_NAME="Aman Check.app"
CONTENTS="$APP_NAME/Contents"
BUILT_BINARY=".build/AmanCheck-bundle-binary"

if [ "$UNIVERSAL" == "1" ]; then
    echo "Compilation (release, universel arm64 + x86_64)…"
    SLICES=()
    for ARCH in arm64 x86_64; do
        swift build -c release --product AmanCheck --triple "$ARCH-apple-macosx13.0"
        SLICES+=("$(swift build -c release --product AmanCheck --triple "$ARCH-apple-macosx13.0" --show-bin-path)/AmanCheck")
    done
    lipo -create "${SLICES[@]}" -output "$BUILT_BINARY"
    BIN_PATH="$(swift build -c release --product AmanCheck --triple "x86_64-apple-macosx13.0" --show-bin-path)"
else
    echo "Compilation (release, $(uname -m))…"
    swift build -c release --product AmanCheck
    BIN_PATH="$(swift build -c release --show-bin-path)"
    cp "$BIN_PATH/AmanCheck" "$BUILT_BINARY"
fi

echo "Création du bundle…"
rm -rf "$APP_NAME"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILT_BINARY" "$CONTENTS/MacOS/AmanCheck"
cp "Branding/Aman-Disk-brand/app-icon/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
# Ressources SwiftPM (base des ponts USB de DiskHealthCore) : à côté de l'exécutable et dans Resources.
for bundle in "$BIN_PATH"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$CONTENTS/Resources/"
done
cp "Sources/DiskHealthCore/Resources/usb-bridges.json" "$CONTENTS/Resources/"

cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AmanCheck</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.aman-disk.AmanCheck</string>
    <key>CFBundleName</key>
    <string>Aman Check</string>
    <key>CFBundleDisplayName</key>
    <string>Aman Check</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>AmanBuildDate</key>
    <string>$BUILD_DATE</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleAllowMixedLocalizations</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Aman Check shows the camera picture to check that it works. Nothing is recorded.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Aman Check measures the microphone level and records 3 seconds so you can hear them back. Nothing is kept.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Aman Check checks that this Mac's Bluetooth is present and turned on.</string>
</dict>
</plist>
PLIST

# Textes des trois demandes d'autorisation, par langue (macOS affiche la langue de l'utilisateur).
permission_texts() {
    case "$1" in
        en) echo "Aman Check shows the camera picture to check that it works. Nothing is recorded.|Aman Check measures the microphone level and records 3 seconds so you can hear them back. Nothing is kept.|Aman Check checks that this Mac's Bluetooth is present and turned on." ;;
        fr) echo "Aman Check affiche l'image de la caméra pour vérifier qu'elle fonctionne. Rien n'est enregistré.|Aman Check mesure le niveau du micro et enregistre 3 secondes pour vous les faire réécouter. Rien n'est conservé.|Aman Check vérifie que le Bluetooth de ce Mac est présent et allumé." ;;
        zh-Hans) echo "Aman Check 显示摄像头画面以检查其是否正常工作。不会录制任何内容。|Aman Check 测量麦克风音量并录制 3 秒以便您回放。不会保留任何内容。|Aman Check 检查这台 Mac 的蓝牙是否存在并已开启。" ;;
        zh-Hant) echo "Aman Check 顯示相機畫面以檢查其是否正常運作。不會錄製任何內容。|Aman Check 測量麥克風音量並錄製 3 秒供您回放。不會保留任何內容。|Aman Check 檢查這台 Mac 的藍牙是否存在並已開啟。" ;;
        ko) echo "Aman Check는 카메라가 작동하는지 확인하기 위해 카메라 화면을 표시합니다. 아무것도 녹화되지 않습니다.|Aman Check는 마이크 레벨을 측정하고 다시 들을 수 있도록 3초를 녹음합니다. 아무것도 보관되지 않습니다.|Aman Check는 이 Mac의 블루투스가 있고 켜져 있는지 확인합니다." ;;
        ar) echo "يعرض Aman Check صورة الكاميرا للتحقق من أنها تعمل. لا يتم تسجيل أي شيء.|يقيس Aman Check مستوى الميكروفون ويسجل 3 ثوانٍ لتعيد سماعها. لا يتم الاحتفاظ بأي شيء.|يتحقق Aman Check من وجود بلوتوث هذا الـ Mac ومن أنه مشغّل." ;;
        pt-BR|pt) echo "O Aman Check mostra a imagem da câmera para verificar se ela funciona. Nada é gravado.|O Aman Check mede o nível do microfone e grava 3 segundos para você ouvir de volta. Nada é guardado.|O Aman Check verifica se o Bluetooth deste Mac está presente e ligado." ;;
        es) echo "Aman Check muestra la imagen de la cámara para comprobar que funciona. No se graba nada.|Aman Check mide el nivel del micrófono y graba 3 segundos para que los escuche. No se conserva nada.|Aman Check comprueba que el Bluetooth de este Mac está presente y encendido." ;;
        de) echo "Aman Check zeigt das Kamerabild, um zu prüfen, ob die Kamera funktioniert. Es wird nichts aufgezeichnet.|Aman Check misst den Mikrofonpegel und nimmt 3 Sekunden auf, damit Sie sie anhören können. Es wird nichts behalten.|Aman Check prüft, ob das Bluetooth dieses Mac vorhanden und eingeschaltet ist." ;;
        it) echo "Aman Check mostra l'immagine della fotocamera per verificare che funzioni. Non viene registrato nulla.|Aman Check misura il livello del microfono e registra 3 secondi per fartele riascoltare. Non viene conservato nulla.|Aman Check verifica che il Bluetooth di questo Mac sia presente e acceso." ;;
        ja) echo "Aman Check はカメラが動作するか確認するためにカメラの映像を表示します。何も記録されません。|Aman Check はマイクのレベルを測定し、聞き直せるように 3 秒間録音します。何も保存されません。|Aman Check はこの Mac の Bluetooth が存在し、オンになっているか確認します。" ;;
        ru) echo "Aman Check показывает изображение с камеры, чтобы проверить её работу. Ничего не записывается.|Aman Check измеряет уровень микрофона и записывает 3 секунды, чтобы вы могли их прослушать. Ничего не сохраняется.|Aman Check проверяет, что Bluetooth этого Mac присутствует и включён." ;;
        tr) echo "Aman Check, çalışıp çalışmadığını denetlemek için kamera görüntüsünü gösterir. Hiçbir şey kaydedilmez.|Aman Check mikrofon seviyesini ölçer ve geri dinleyebilmeniz için 3 saniye kaydeder. Hiçbir şey saklanmaz.|Aman Check bu Mac'in Bluetooth'unun var ve açık olduğunu denetler." ;;
        nl) echo "Aman Check toont het camerabeeld om te controleren of de camera werkt. Er wordt niets opgenomen.|Aman Check meet het microfoonniveau en neemt 3 seconden op zodat u ze kunt terugluisteren. Er wordt niets bewaard.|Aman Check controleert of de Bluetooth van deze Mac aanwezig en ingeschakeld is." ;;
        pl) echo "Aman Check pokazuje obraz z kamery, aby sprawdzić, czy działa. Nic nie jest nagrywane.|Aman Check mierzy poziom mikrofonu i nagrywa 3 sekundy, aby można było je odsłuchać. Nic nie jest zachowywane.|Aman Check sprawdza, czy Bluetooth tego Maca jest obecny i włączony." ;;
        hi) echo "Aman Check कैमरे की तस्वीर दिखाता है ताकि जाँच हो सके कि वह काम करता है। कुछ भी रिकॉर्ड नहीं किया जाता।|Aman Check माइक्रोफ़ोन का स्तर मापता है और 3 सेकंड रिकॉर्ड करता है ताकि आप उन्हें दोबारा सुन सकें। कुछ भी रखा नहीं जाता।|Aman Check जाँचता है कि इस Mac का Bluetooth मौजूद और चालू है।" ;;
        vi) echo "Aman Check hiển thị hình ảnh camera để kiểm tra camera hoạt động. Không có gì được ghi lại.|Aman Check đo mức micrô và ghi 3 giây để bạn nghe lại. Không có gì được lưu giữ.|Aman Check kiểm tra Bluetooth của máy Mac này có tồn tại và đang bật." ;;
        uk) echo "Aman Check показує зображення з камери, щоб перевірити її роботу. Нічого не записується.|Aman Check вимірює рівень мікрофона й записує 3 секунди, щоб ви могли їх прослухати. Нічого не зберігається.|Aman Check перевіряє, що Bluetooth цього Mac присутній і ввімкнений." ;;
        *) echo "Aman Check shows the camera picture to check that it works. Nothing is recorded.|Aman Check measures the microphone level and records 3 seconds so you can hear them back. Nothing is kept.|Aman Check checks that this Mac's Bluetooth is present and turned on." ;;
    esac
}

echo "Textes d'autorisation localisés…"
for lang in en fr zh-Hans zh-Hant ko ar pt-BR pt es de it ja ru tr nl pl hi vi uk; do
    IFS='|' read -r CAM MIC BT <<< "$(permission_texts "$lang")"
    mkdir -p "$CONTENTS/Resources/$lang.lproj"
    cat > "$CONTENTS/Resources/$lang.lproj/InfoPlist.strings" << EOF
CFBundleDisplayName = "Aman Check";
CFBundleName = "Aman Check";
NSCameraUsageDescription = "$CAM";
NSMicrophoneUsageDescription = "$MIC";
NSBluetoothAlwaysUsageDescription = "$BT";
EOF
done

cat > "AmanCheck.entitlements" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signature ($SIGN_IDENTITY, Hardened Runtime)…"
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" --entitlements AmanCheck.entitlements "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"
codesign -d --entitlements - "$APP_NAME" 2>/dev/null | grep -q "device.camera" && echo "Entitlement caméra : présent"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_NAME" 2>/dev/null || true
echo "Terminé : $(pwd)/$APP_NAME"
