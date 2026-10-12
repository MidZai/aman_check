// swift-tools-version: 5.10
import PackageDescription

// Aman Check — contrôle d'état d'un Mac d'occasion.
//
// CDiskIO + DiskHealthCore : moteur S.M.A.R.T. d'Aman Disk (https://github.com/MidZai/aman_disk),
// copié à l'identique sauf un correctif marqué « CORRECTIF Aman Check » (USBBridgeDatabase.swift),
// à reporter dans Aman Disk. Toute autre correction se fait dans Aman Disk, puis se recopie.
let package = Package(
    name: "AmanCheck",
    defaultLocalization: "fr",
    platforms: [
        // Même version minimale qu'Aman Disk.
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AmanCheck", targets: ["AmanCheck"]),
        .library(name: "AmanCore", targets: ["AmanCore"]),
        .library(name: "AmanDesign", targets: ["AmanDesign"]),
        .library(name: "AmanStorageKit", targets: ["AmanStorageKit"])
    ],
    targets: [
        .target(
            name: "CDiskIO",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .target(
            name: "DiskHealthCore",
            dependencies: ["CDiskIO"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("DiskArbitration"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        // Modèle de données, catalogues et analyses : aucune dépendance à l'interface,
        // entièrement testable avec des fixtures.
        .target(
            name: "AmanCore",
            dependencies: ["DiskHealthCore"]
        ),
        // Lecture du stockage (moteur d'Aman Disk) convertie en mesures Aman Check.
        .target(
            name: "AmanStorageKit",
            dependencies: ["AmanCore", "DiskHealthCore"]
        ),
        // Jetons et composants visuels repris d'Aman Disk.
        .target(
            name: "AmanDesign",
            dependencies: ["AmanCore", "DiskHealthCore"]
        ),
        .executableTarget(
            name: "AmanCheck",
            dependencies: ["AmanCore", "AmanDesign", "AmanStorageKit", "DiskHealthCore"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Carbon")
            ]
        ),
        // Export du catalogue de libellés pour la page publique du niveau 2 (server/src/catalog.json).
        .executableTarget(
            name: "AmanCatalogExport",
            dependencies: ["AmanCore", "DiskHealthCore"]
        ),
        // Swift Testing. Sans Xcode : scripts/test.sh.
        .testTarget(
            name: "AmanCoreTests",
            dependencies: ["AmanCore", "AmanStorageKit", "DiskHealthCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
