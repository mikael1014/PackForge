---
projet: PackForge
statut: actif
maj: 2026-08-20
version: 1.0.0
ports: []
bloque_par: "aucun - TRANCHE le 20/08/2026 : (1) les binaires portables de bin/ NE SONT PAS versionnes - un binaire entre dans l'historique y reste meme supprime ensuite ; ils restent dans C:/Donnees/bin, proprietaire des binaires partages. (2) CN du certificat Authenticode = Mikael Corp (forme ASCII) : PackForge est le socle technique de l'offre packaging, donc un travail POUR LA SOCIETE - cas ou cette signature est eligible, ici confirmee explicitement."
git: oui
---

# ÉTAT — PackForge

> **À lire en premier.** Répond à une seule question : **où en est le projet ?**
> `README.md` dit **comment s'en servir** · `docs\CHECKLIST-PACKAGING.md` dit **comment packager**.

**Dernière mise à jour : 02/08/2026.**

---

## En un coup d'œil

| | |
|---|---|
| **Nature** | Boîte à outils technique de packaging applicatif (Intune / SCCM), réutilisable chez tout client |
| **Version** | 1.1.0 — socle P1 posé, testé, et purgé de toute référence nominative à un client |
| **Origine** | Chantier n°1 de `Centre de Packaging\ETAT.md`, plan détaillé dans `Centre de Packaging\BOITE-A-OUTILS.md` |
| **Git** | `github.com/mikael1014/PackForge` (privé) |
| **⚠️ Règle du dépôt** | **aucun nom de client dans ce repo** — il doit pouvoir être ouvert devant un prospect. La traçabilité de l'origine reste dans `Centre de Packaging\` (dossier privé) |
| **Frontière** | PackForge = le **code** · Centre de Packaging = le **commercial** (pitch, offre, prospects) |

---

## ✅ Acquis (fait et vérifié le 02/08/2026)

| Brique | État |
|---|---|
| **LogModule générique v2.0.0** (`modules\`) | ✅ générisé : `-Organization` → `%PROGRAMDATA%\<Org>\Logs`, repli `%LOCALAPPDATA%`, `-Preset DonneesLog` en opt-in pour les parcs imposant `C:\Donnees\*`. Garde-fou « ANOMALIE PROD » rendu générique (compare au candidat de production, plus de chemin en dur) |
| **Template wrapper MSI** (`templates\wrapper-msi\`) | ✅ auto-relance 64-bit, patron auto-nettoyant, `Get-LogPath` partout, garde-fou anti-template-non-rempli, codes 0/3010/1603/1605 |
| **Modèle de fiche package Intune** | ✅ tous les champs + provenance datée + statut de test + rappels des pièges |
| **Modèle `README-source.md`** | ✅ traçabilité du binaire (URL, date, SHA-256) |
| **Checklist packaging 1 page** | ✅ source → identifiants MSI → construction → **4 contextes de test** → `.intunewin` → pilote, avec table des codes retour |
| **Tests** | ✅ 10 vérifications passées en compte utilisateur (détail dans `README.md` § Ce qui a été vérifié) |
| **2 corrections sur le module d'origine** | ✅ nom d'archive de rotation (bug `$scriptBaseName_` silencieux) · lecture du BOM compatible PowerShell 5.1 **et** 7 |

---

## ⏳ Ce qui reste

| Sujet | Qui/quoi bloque | Effort | Impact si non fait |
|---|---|---|---|
| **Valider en contexte SYSTEM** (PsExec, compte admin) + un vrai MSI de bout en bout | **Mikaël** — nécessite une console admin | 30 min | Le socle reste validé « en labo » ; c'est en SYSTEM que se jouent les pièges réels. Commande prête dans `docs\CHECKLIST-PACKAGING.md` §4 |
| **Template wrapper EXE** (Inno / NSIS) | — | ~2 h | Tout produit non-MSI reste à packager à la main |
| **Bibliothèque de détections Intune** (`Detect-*.ps1` : ProductCode, fichier+version, registre 64/32) | — | ~2 h | Les briques existent, dispersées ; rien de prêt à coller dans Intune |
| **Outils de diagnostic** (Get-MsiProductInfo, ListAllApps, analyse logs IME, Network-Diag, Diag-AAD_TPM) | — | ~3 h | Le kit jour 1 reste incomplet (5 des 13 éléments) |
| ~~**Rapatrier les binaires portables**~~ (`bin\` : CMTrace, Orca, innounp, Win32 Content Prep Tool, Sysinternals) | ✅ **Tranché le 20/08/2026** | — | **Non versionnés** : un binaire entré dans un historique git y reste, même supprimé ensuite. Ils vivent dans `C:\Donnees\bin`, propriétaire des binaires partagés. |
| **Page « mon standard vs PSADT »** | — | 1 h | Aucune réponse prête quand un client impose PSADT |
| **Signature Authenticode des scripts** | ✅ **CN tranché le 20/08/2026** : `Mikael Corp` (forme ASCII) | reste à générer/acheter le certificat | Blocage possible en environnement durci (AppLocker) |

---

## 📋 Chantiers

| Chantier | État |
|---|---|
| Socle P1 : LogModule + wrapper MSI + fiche package + checklist | ✅ **terminé le 02/08/2026** |
| Sauvegarde hors machine (remote GitHub privé) | ✅ **fait le 02/08/2026** |
| Kit jour 1 complet (13 éléments) | ⬜ 5/13 |
| Fusion avec le kit modulaire historique (`encours\python\MainScript.ps1`) | ⬜ non démarré |

---

## 🔌 Ports

**Aucun** — outillage local, aucun service.

---

## 🗓️ Journal des jalons

| Date | Jalon |
|---|---|
| 02/08/2026 | Cartographie de l'outillage réel → `Centre de Packaging\BOITE-A-OUTILS.md` |
| 02/08/2026 | **Création de PackForge** : socle P1 posé, générisé et testé (10 vérifications) |
| 02/08/2026 | v1.1.0 — preset renommé `DonneesLog`, **purge complète des références nominatives client**, dépôt poussé sur GitHub privé |
| **10/08/2026** | Checklist **1.1** : nouveau § 7 « Quand ce n'est pas le package — le poste ment » (client SCCM dont le namespace `root\ccm` existe mais dont les classes `SMS_Client`/`SMS_Authority` sont vides). Cas réel de mission, **versé sans nom de client ni de poste**, conformément à la règle du dépôt |
