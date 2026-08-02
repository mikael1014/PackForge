# PackForge — boîte à outils de packaging applicatif

> **Ce que c'est** : le socle technique réutilisable pour packager une application Windows
> (Intune / SCCM) chez **n'importe quel client**, extrait de 2 ans et demi de production réelle
> et débarrassé de toute convention propre à un client donné.
>
> **Ce que ce n'est pas** : le dossier commercial du Centre de Packaging (pitch, prospects,
> offre) — celui-là vit dans `programation\Centre de Packaging`. Ici, il n'y a que du code
> et des procédures.

---

## Démarrage rapide — packager un MSI en 10 minutes

```
1. Créer le dossier du package, nommé  {Editeur}_{Produit}_{Version}_{Archi}_R1
2. Y copier :
     modules\LogModule.psm1
     templates\wrapper-msi\TEMPLATE_wrapper-msi.ps1   -> renommé comme le dossier
     le MSI source
     templates\wrapper-msi\README-source.md           -> rempli (URL + date + SHA-256)
3. Ouvrir le .ps1, remplir $OrganizationName puis le bloc $PackageConfig (seule zone à toucher)
4. Dérouler docs\CHECKLIST-PACKAGING.md
```

Le script **refuse de démarrer** tant qu'un champ `[A-REMPLIR]` subsiste : un template non
rempli ne peut pas partir en déploiement par inadvertance.

---

## Contenu

| Chemin | Rôle |
|---|---|
| `modules\LogModule.psm1` | Journalisation CMTrace, UTF-8 BOM, choix et repli automatique du dossier de log, garde-fou de production, bilan de fin |
| `templates\wrapper-msi\TEMPLATE_wrapper-msi.ps1` | Wrapper install / désinstall / réinstall d'un MSI — auto-relance 64-bit, patron auto-nettoyant, codes retour SCCM/Intune |
| `templates\wrapper-msi\Packages.md` | Modèle de fiche package (tous les champs Intune + provenance + statut de test) |
| `templates\wrapper-msi\README-source.md` | Modèle de traçabilité du binaire (URL, date, SHA-256) |
| `docs\CHECKLIST-PACKAGING.md` | Checklist de bout en bout : source → tests 4 contextes → `.intunewin` → pilote |

---

## Le LogModule en trois idées

1. **Le dossier de log n'est jamais codé en dur.** `Initialize-Logging -Organization "Contoso"`
   écrit dans `%PROGRAMDATA%\Contoso\Logs`, avec repli automatique sur `%LOCALAPPDATA%\Contoso\Logs`
   si le premier n'est pas accessible en écriture (typiquement : test en compte utilisateur).
   Les logs auxiliaires (log MSI verbeux…) suivent le même dossier via `Get-LogPath "fichier.log"`.

2. **Le repli est signalé, pas subi.** Sous le compte SYSTEM (la production), si le module a dû
   basculer sur un dossier de repli, il écrit une ligne **`ANOMALIE PROD`** dans le journal.
   Sans ça, on découvre six mois plus tard que la prod journalise dans un dossier de test.

3. **Un seul encodage, UTF-8 avec BOM.** C'est ce qui évite le charabia d'accents dans CMTrace.
   Un journal préexistant en UTF-16 est archivé automatiquement plutôt que mélangé.

Conventions client : `-Preset DonneesLog` reproduit l'arborescence `C:\Donnees\Log` → `C:\Donnees\Temp`
imposée par certains parcs d'entreprise. C'est un **opt-in explicite** : aucune convention client
n'est le comportement par défaut.

### API

| Fonction | Usage |
|---|---|
| `Initialize-Logging [-Organization] [-Preset] [-LogPathCandidates] [-MaxSize] [-MaxFiles] [-Format] [-SharedWriteAccess]` | à appeler une fois, en tête de script |
| `LogInfo` / `LogWarn` / `LogError` / `LogDebug` | écrire une ligne |
| `LogSection -Title "..."` | séparateur visuel |
| `LogProcess -Message "..." -Level INFO\|WARNING\|ERROR\|DEBUG` | forme complète |
| `Get-LogPath "fichier.log"` | chemin d'un log auxiliaire **dans le dossier retenu** |
| `Get-LogBasePath` | dossier de log effectivement utilisé |
| `Get-LogSummary` | compteurs INFO/WARNING/ERROR + chemin du journal + contexte SYSTEM |

---

## Ce qui a été vérifié (02/08/2026)

Tests réels exécutés sur ce poste, en compte utilisateur standard :

| Test | Résultat |
|---|---|
| Écriture CMTrace (type 1/2/3), BOM UTF-8, accents relus intacts | ✅ |
| `Get-LogPath` suit le dossier retenu | ✅ |
| Repli automatique quand le premier candidat est inaccessible | ✅ |
| Rotation au dépassement de taille + purge à `MaxFiles` | ✅ (3 archives conservées sur 8) |
| Nom d'archive contenant bien le nom du script | ✅ (bug du module d'origine corrigé) |
| Template non rempli → refus de démarrer, aucun dossier parasite créé | ✅ exit `1603` |
| Template sans privilèges admin → refus explicite | ✅ exit `1603` |
| Template avec source manquante → arrêt sur fichier manquant | ✅ exit `1603` |
| Désinstallation d'un produit absent → succès (chaîne complète) | ✅ exit `0` |
| Lecture du ProductCode d'un MSI par COM (commande de la checklist) | ✅ testée sur un MSI réel |

**Non encore vérifié** : exécution réelle en contexte **SYSTEM** (nécessite PsExec en admin),
installation d'un vrai MSI de bout en bout, et la ligne `ANOMALIE PROD` en conditions réelles.
Ces trois points sont à couvrir au premier package réel.

---

## Origine

Extrait de l'outillage constitué sur un parc grand compte entre janvier 2024 et juin 2026
(plusieurs dizaines de packages Intune/SCCM en production). Les conventions propres à ce client
— arborescence de logs, préfixes de nommage, chemins réseau, noms de personnes — ont été retirées
du comportement par défaut : ce qui reste est soit générique, soit activable explicitement.

**Aucun secret, aucune donnée client, aucun nom de client** ne doit entrer dans ce dépôt : ni
coffre, ni clé de licence, ni export de comptes, ni binaire sous licence client. Le dépôt est
conçu pour pouvoir être ouvert devant un prospect sans rien avoir à masquer.
