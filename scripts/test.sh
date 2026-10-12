#!/bin/bash
# Lance les tests unitaires (Swift Testing), même méthode qu'Aman Disk.
#
# Avec Xcode : `swift test` suffit.
# Avec les seuls Command Line Tools, le module Testing n'est pas dans le chemin de recherche,
# et depuis macOS 26 l'outil d'aide de SwiftPM (signé Apple, validation des bibliothèques)
# refuse de charger le paquet de tests signé localement. On compile donc les tests,
# puis on les exécute avec un petit lanceur local (scripts/TestRunner.swift).
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

DEV="$(xcode-select -p)"
if [[ "$DEV" != *CommandLineTools* ]]; then
    exec swift test "$@"
fi

FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"
swift build --build-tests \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW"

RUNNER=".build/test-runner/TestRunner"
if [ ! -x "$RUNNER" ] || [ "scripts/TestRunner.swift" -nt "$RUNNER" ]; then
    mkdir -p .build/test-runner
    swiftc -parse-as-library -O -F "$FW" -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" \
        scripts/TestRunner.swift -o "$RUNNER"
fi

BUNDLE="$(swift build --show-bin-path)/AmanCheckPackageTests.xctest/Contents/MacOS/AmanCheckPackageTests"
exec "$RUNNER" "$BUNDLE" "$@"
