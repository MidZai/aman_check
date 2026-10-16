// swift-tools-version: 5.10
import PackageDescription

// Aman Check — contrôle d'état d'un Mac d'occasion.
//
// CDiskIO + DiskHealthCore : moteur S.M.A.R.T. d'Aman Disk (https://github.com/MidZai/aman_disk),
// copié à l'identique (scripts/sync-engine.sh d'Aman Legacy, vérifié par diff -rq).
// Toute correction se fait dans Aman Disk, puis se recopie.
let package = Package(
    name: "AmanCheck",
    defaultLocalization: "fr",
    platforms: [
        // macOS 13 Ventura : dernière version des MacBook Pro, MacBook et iMac 2017.
        // Aman Disk reste en macOS 14 ; ce qui demande macOS 14 passe par #available.
        .macOS(.v13)
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
        // Lecture seule du SMC (ventilateurs, températures), propre à Aman Check.
        .target(
            name: "CSMC",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        // Modèle de données, catalogues et analyses : aucune dépendance à l'interface,
        // entièrement testable avec des fixtures.
        .target(
            name: "AmanCore",
            dependencies: ["DiskHealthCore"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
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
            dependencies: ["AmanCore", "AmanDesign", "AmanStorageKit", "DiskHealthCore", "CSMC"],
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
