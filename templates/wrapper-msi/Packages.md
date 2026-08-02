# MODÈLE — Fiche package (à dupliquer par lot de packages)

> **Rôle** : une fiche = tout ce qu'il faut saisir dans Intune (ou SCCM) pour un package, plus la
> **provenance datée** de la source et le **statut de test**. C'est le document que lit le collègue
> qui reprend le package, l'auditeur qui demande d'où vient le binaire, et vous-même dans six mois.
>
> **Comment s'en servir** : copier ce fichier dans le dossier du lot, le renommer `Packages.md`,
> supprimer ce bandeau, garder une section « ## n. Produit » par package.

**Convention de nommage** : `{Editeur}_{Application}_{Version}_{Architecture}_{Release}`
→ ex. `iterate_Cyberduck_9.5.0_x64_R1` · `R1, R2…` = itérations du package · `xALL` si l'architecture est indifférente.

**Préfixe de description** (optionnel, convention client) : certains clients préfixent la description
par les versions d'OS validées, ex. `10-11 - ` pour « testé sur Windows 10 et 11 ». À ajuster par package
selon les OS **réellement** testés — ce n'est pas une décoration.

---

## 1. `<Produit>` `<Version>` — `<✅ prêt | ⏳ source manquante | 🧪 en test>`

| Champ | Valeur |
|---|---|
| **Publisher** | `<éditeur — raison sociale exacte>` |
| **Application** | `<nom produit>` |
| **Version** | `<version complète, celle du MSI, pas celle du site>` |
| **Architecture** | `x64` \| `x86` \| `xALL` |
| **Release** | `R1` |
| **Package Name** | `<Editeur>_<Produit>_<Version>_<Archi>_R1` |
| **Package Type** | PS1 |
| **Description** | `<à quoi sert l'appli + usage métier chez ce client + mode d'installation (machine/utilisateur, silencieux)>` |
| **Install Command** | `powershell -executionpolicy Bypass -file ".\<PackageName>.ps1" -Install` |
| **Uninstall Command** | `powershell -executionpolicy Bypass -file ".\<PackageName>.ps1"` |
| **Install behavior** | `System` (machine) \| `User` (per-user — assigner à des **utilisateurs**, pas à des appareils) |
| **Detection Method** | `MSI` \| `File` \| `Registry` |
| **Detection Line** | ProductCode `{GUID}` — ou chemin/clé exacts |
| **Alternative File** | `<chemin binaire>` (File exists) — repli si le ProductCode ne suffit pas |
| **UpgradeCode** | `{GUID}` (utile pour repérer les versions antérieures) |
| **Source** | `<nom exact du fichier>`, téléchargé le `JJ/MM/AAAA` depuis `<URL complète>` (`<taille>`) |
| **Prérequis** | `<VC++ Redist, .NET, licence, provisionnement…>` ou « aucun » |
| **À valider sur PC** | `<liste des points non encore testés>` — ou date + résultat du test end-to-end |

### Notes de packaging
- `<décisions prises, pièges rencontrés, pourquoi tel flag silencieux, pourquoi telle détection>`

---

## Rappels transverses

### Install / Uninstall / Reinstall
- **Install** : ajouter `-Install` · **Uninstall** : aucun switch · **Reinstall** : `-Reinstall`.

### Format de la commande Intune
```
powershell -executionpolicy Bypass -file ".\Nom_Du_PS1.ps1" -Install
```
Le `.\` **et** les guillemets sont obligatoires côté Intune.

### Détection — ordre de préférence
1. **MSI ProductCode** — le plus fiable quand il existe.
2. **Registre « Key exists »** — clé de service/produit spécifique. ⚠️ Une clé **HKCU** n'est pas
   fiable en détection Intune (le contexte SYSTEM ne voit pas la ruche de l'utilisateur).
3. **Fichier « Path exists » / version ≥** — attention aux dossiers qui changent à chaque
   auto-update (ex. `app-<version>\`) : viser un stub stable.

### Pièges récurrents
- **Bitness** : l'IME lance les scripts en 32-bit → sans auto-relance 64-bit, l'ARP part sous
  `WOW6432Node` et la détection échoue (`0x87D1041C`). Le template intègre la parade.
- **Pas de supersedence** (ou supersedence non utilisée) → patron **auto-nettoyant** : désinstaller
  la version présente avant d'installer la nouvelle. Règle « zéro trou » : poser le neuf **avant**
  de retirer l'ancien quand les deux packages coexistent côté déploiement.
- **Install per-user déployé en SYSTEM** : l'appli atterrit dans le profil `systemprofile` et
  l'utilisateur ne l'a jamais. → `Install behavior = User` + assignation à des utilisateurs.
  ⚠️ Si le champ n'est plus modifiable après création, **recréer l'app** (le `.intunewin` ne change pas).
- **Ne jamais modifier la règle de détection d'un package déjà déployé** pour forcer une
  réinstallation : cela crée une boucle de réinstallation permanente.
