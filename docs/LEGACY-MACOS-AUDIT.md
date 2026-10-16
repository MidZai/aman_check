# Aman Check — audit des anciens macOS (12 Monterey, 13 Ventura)

Audit du 2026-10-16, demandé par les retours Reddit (« support des Mac plus anciens »). **Décision attendue du mainteneur** : ce document ne porte rien.

## État de départ

- **macOS 13 Ventura : déjà fait.** Depuis le commit `949f293` (« feat: run on macOS 13 Ventura »), `Package.swift` cible `.macOS(.v13)` et `LSMinimumSystemVersion` vaut 13.0. Sept appels SwiftUI passent par des variantes macOS 13 ou par `#available` ; rien ne change sur macOS 14 et plus (les symboles Touch ID et haut-parleurs ne s'animent pas sur 13). Couvre en plus les MacBook Pro 2017, MacBook 2017 et iMac 2017. **Pas encore vérifié sur un vrai Mac sous Ventura.** Le README et le site disent encore « macOS 14 ou plus » jusqu'à la prochaine version publiée.
- **Reste à décider : macOS 12 Monterey.**

## Méthode

Un `grep` ne suffit pas : la copie du dépôt (worktree jetable) a été compilée avec `.macOS(.v12)` et `swift build --product AmanCheck --triple x86_64-apple-macosx12.0`, puis les erreurs ont été collectées. Les modules **AmanCore, AmanDesign, AmanStorageKit, DiskHealthCore, CDiskIO et CSMC compilent sans erreur** pour macOS 12 : tout le travail serait dans l'app (`Sources/AmanCheck`). Après correction de ces erreurs, d'autres peuvent apparaître (le compilateur s'arrête par fichier) : l'estimation est un minimum.

## Ce qui exige macOS 13 (23 appels, 10 fichiers)

| API (macOS 13+) | Fichiers | Équivalent sur 12 | Risque |
|---|---|---|---|
| `ImageRenderer`, `ProposedViewSize` (rendu du PDF) | `Report/ReportExporter.swift` | Aucun équivalent SwiftUI : passer par `NSHostingView` + `dataWithPDF(inside:)` ou un contexte PDF Core Graphics, page par page | **Élevé** : c'est le rapport lui-même (polices, pagination, QR codes, RTL arabe). Deux chemins de rendu à maintenir |
| `Layout` (`EqualHeightGrid`, grilles à hauteurs égales) | `UI/OverviewView.swift` | `LazyVGrid` (cartes de hauteurs inégales) ou mesure par `PreferenceKey` | Moyen : régression visuelle sur l'écran principal |
| `NavigationSplitView`, `navigationSplitViewColumnWidth` | `UI/ContentView.swift` | `NavigationView` avec barre latérale | Moyen : comportement de la barre latérale et de la barre d'outils différent |
| `Window` (fenêtre unique), `defaultSize` | `AmanCheckApp.swift` | `WindowGroup` (plusieurs fenêtres possibles), `frame` | Moyen : deux contrôles en parallèle deviendraient possibles |
| `ViewThatFits` | `UI/OverviewView.swift`, `UI/ResultsShowcase.swift` | Choix de mise en page par `GeometryReader` | Faible |
| `formStyle(.grouped)` | `Report/ReportScreen.swift`, `UI/SettingsView.swift` | Style de formulaire par défaut de macOS 12 | Faible (apparence) |
| `LabeledContent` | `Report/ReportScreen.swift` | `HStack` | Faible |
| `fontWeight` | `UI/ContentView.swift`, `UI/OverviewView.swift` | `.font(… .weight(…))` | Faible |
| `Color.gradient` | `UI/ProjectLinks.swift` | `LinearGradient` | Faible |
| `AVCaptureDevice.isContinuityCamera` | `Tests/CameraTest.swift` | `#available(macOS 13, *)` (pas de caméra de continuité sur 12) | Faible |

## Estimation par cible

| Cible | Fichiers touchés | API sans équivalent direct | Risque de régression | Macs gagnés |
|---|---|---|---|---|
| **13 Ventura** | — (fait) | — | Aucun sur 14+ ; non vérifié sur 13 | MacBook Pro 2017, MacBook 2017, iMac 2017 |
| **12 Monterey** | ≈ 10 fichiers, ≈ 23 appels (minimum) | `ImageRenderer` (PDF), `Layout` | **Élevé** sur le PDF, moyen sur la navigation et l'écran principal | 13 identifiants, ci-dessous |

Macs dont le dernier macOS est Monterey (catalogue `MacModelCatalog`) : MacBook Pro 13″ 2015 (`MacBookPro12,1`), 15″ 2015 (`MacBookPro11,4`, `11,5`), 13″ et 15″ 2016 (`MacBookPro13,1`, `13,2`, `13,3`) ; MacBook Air 11″ 2015 (`MacBookAir7,1`) et 13″ 2015–2017 (`MacBookAir7,2`) ; MacBook 12″ 2016 (`MacBook9,1`) ; iMac 21,5″ et 27″ 2015 (`iMac16,1`, `16,2`, `17,1`) ; Mac mini 2014 (`Macmini7,1`) ; Mac Pro 2013 (`MacPro6,1`).

À noter : ce sont tous des Mac Intel **sans puce T2**. Sur eux, le verrouillage d'activation n'est pas lisible depuis macOS, le mot de passe firmware reste une vérification manuelle, et Touch ID n'existe que sur deux modèles. Le rapport y serait plus pauvre que sur un Mac récent, quel que soit l'effort de portage.

## Recommandation

**Ne pas porter vers macOS 12.** Le coût est concentré sur le rendu du PDF, cœur du produit, qui demanderait un second chemin de rendu à tenir identique au premier ; le gain est un groupe de Mac 2013–2016 sur lesquels les contrôles les plus importants (verrouillage d'activation) restent impossibles.

À la place :

1. Publier la version macOS 13 (déjà prête), après une vérification sur un vrai Mac sous Ventura (`docs/VERIFICATION.md`).
2. Dire clairement sur le site et dans le README quels Macs sont exclus : « macOS 13 Ventura ou plus récent. Les Mac qui ne peuvent pas dépasser macOS 12 (MacBook Pro 2015–2016, MacBook Air 2015–2017, MacBook 2016, iMac 2015, Mac mini 2014, Mac Pro 2013) ne sont pas pris en charge. »
3. Répondre dans l'issue GitHub #7 avec cette décision.

Si le mainteneur choisit malgré tout Monterey : commencer par le rendu PDF (prototype `NSHostingView` → PDF comparé page à page avec la version actuelle, en français, anglais et arabe), avant toute autre adaptation.
