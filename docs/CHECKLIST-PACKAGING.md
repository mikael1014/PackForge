# CHECKLIST PACKAGING — de la source au package validé

> Une page, à parcourir **dans l'ordre**, pour chaque package. Chaque case cochée est une chose
> qui ne reviendra pas vous mordre en production. Version 1.0 — 02/08/2026.

---

## 1. Source (avant d'écrire une ligne)

- [ ] Binaire récupéré depuis **le site officiel de l'éditeur** ou le portail client — jamais un miroir tiers.
- [ ] `README-source.md` rempli : **URL complète, date de téléchargement, taille, SHA-256**.
      ```powershell
      Get-FileHash -LiteralPath "C:/sources/mon-produit.msi" -Algorithm SHA256 | Format-List
      ```
- [ ] Moteur d'installation identifié : **MSI** · EXE **Inno Setup** · **NSIS** · **Squirrel** (per-user) · autre.
      En cas de doute sur un EXE, l'ouvrir avec `innounp` (Inno) ou vérifier les chaînes du binaire.
- [ ] **Type d'installation** tranché : **machine** (`ALLUSERS=1`) ou **per-user**.
      ⚠️ Un installeur per-user déployé en SYSTEM atterrit dans le profil `systemprofile` :
      l'utilisateur ne verra jamais l'application.
- [ ] Prérequis listés (VC++ Redist, .NET, runtime) — et décision prise : embarqués ou packages séparés ?
- [ ] Licence / configuration : le fichier attendu est identifié, **et il ne finira pas dans le dépôt**.

## 2. Identifiants MSI

- [ ] **ProductCode** relevé (sans installer) :
      ```powershell
      $msi = "C:/sources/mon-produit.msi"
      $w  = New-Object -ComObject WindowsInstaller.Installer
      $db = $w.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$w,@($msi,0))
      $v  = $db.GetType().InvokeMember('OpenView','InvokeMethod',$null,$db,@("SELECT Value FROM Property WHERE Property='ProductCode'"))
      $v.GetType().InvokeMember('Execute','InvokeMethod',$null,$v,$null)
      $r  = $v.GetType().InvokeMember('Fetch','InvokeMethod',$null,$v,$null)
      $r.GetType().InvokeMember('StringData','GetProperty',$null,$r,1)
      ```
      *(remplacer `ProductCode` par `UpgradeCode` ou `ProductVersion` pour les autres propriétés)*
- [ ] **UpgradeCode** relevé (sert à repérer les versions antérieures présentes sur le parc).
- [ ] Pour un produit **déjà installé** quelque part : `Get-MsiProductInfo.ps1` donne
      `UninstallString`, `QuietUninstallString` et le MSI en cache (`C:\Windows\Installer`).

## 3. Construction du package

- [ ] Dossier nommé selon la convention : `{Editeur}_{Produit}_{Version}_{Archi}_{Release}`.
- [ ] `TEMPLATE_wrapper-msi.ps1` copié, **renommé comme le package**, bloc `$PackageConfig` rempli
      (plus aucun `[A-REMPLIR]` — le script refuse de tourner sinon).
- [ ] `LogModule.psm1` copié **dans le dossier du package** (Intune ne déploie qu'un dossier autonome).
- [ ] `Initialize-Logging -Organization "<Client>"` renseigné — ou `-Preset DonneesLog` si le client
      impose l'arborescence `C:\Donnees\*`. Aucun chemin de log en dur nulle part : tout passe par `Get-LogPath`.
- [ ] Fichiers du package : `.ps1` + `LogModule.psm1` + source + `README-source.md`. Rien d'autre.
- [ ] **Aucun secret** dans le dossier : clé de licence, mot de passe, coffre, jeton, export de comptes.

## 4. Tests sur poste — les 4 combinaisons, sur machine vierge

> C'est l'étape que tout le monde abrège et c'est celle qui coûte le plus cher quand on la saute.

- [ ] **Install en admin** → code retour `0` (ou `3010`), application fonctionnelle.
- [ ] **Désinstall en admin** → code `0`, plus rien dans l'ARP, pas de résidu bloquant.
- [ ] **Install en SYSTEM** (contexte réel Intune) :
      ```powershell
      # PsExec (Sysinternals), depuis une console admin
      PsExec.exe -s -i powershell.exe -ExecutionPolicy Bypass -File "C:\pkg\<Nom>.ps1" -Install
      ```
- [ ] **Désinstall en SYSTEM** → code `0`.
- [ ] Le **log** est bien dans le dossier attendu, lisible dans **CMTrace**, sans charabia d'accents,
      et se termine par un bilan `INFO/WARNING/ERROR`.
- [ ] Aucune ligne **« ANOMALIE PROD »** dans le log en contexte SYSTEM
      (elle signalerait que les logs sont partis dans le dossier de repli de test).
- [ ] **Réinstallation** (`-Reinstall`) testée si le produit doit être mis à jour sans supersedence.

## 5. Emballage et publication Intune

- [ ] `.intunewin` généré :
      ```
      IntuneWinAppUtil.exe -c "C:\pkg\<Nom>" -s "<Nom>.ps1" -o "C:\out" -q
      ```
- [ ] **Install command** : `powershell -executionpolicy Bypass -file ".\<Nom>.ps1" -Install`
- [ ] **Uninstall command** : `powershell -executionpolicy Bypass -file ".\<Nom>.ps1"`
      *(le `.\` et les guillemets sont obligatoires)*
- [ ] **Install behavior** cohérent avec le type d'installation (System / User).
      ⚠️ per-user → assigner à des **utilisateurs**, pas à des appareils.
- [ ] **Détection** : ProductCode MSI en premier choix, sinon fichier stable (jamais un dossier
      `app-<version>\` qui change à chaque auto-update), sinon clé registre HKLM
      (**jamais HKCU** : le contexte SYSTEM ne voit pas la ruche utilisateur).
- [ ] **Requirements** renseignés (architecture, version d'OS minimale).
- [ ] Dépendances / supersedence décidées — ou patron **auto-nettoyant** assumé à la place.
- [ ] Fiche `Packages.md` complétée : source datée, détection, statut de test.

## 6. Après le premier déploiement pilote

- [ ] Vérifié sur un poste réel du parc, pas seulement la VM de test.
- [ ] Logs IME relus en cas d'échec :
      `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` (CMTrace).
- [ ] ⚠️ **Ne jamais modifier la règle de détection d'un package déjà déployé** pour forcer une
      réinstallation : cela produit une boucle de réinstallation permanente. Publier une **R2** à la place.
- [ ] Fiche `Packages.md` mise à jour : date du test end-to-end + résultat.

---

## Codes retour à connaître

| Code | Sens | Traitement |
|---|---|---|
| `0` | Succès | — |
| `3010` | Succès, redémarrage requis | à propager tel quel (Intune sait le gérer) |
| `1603` | Échec fatal de l'installation | lire le log MSI verbeux (`/l*v`) |
| `1605` | Produit inconnu (désinstall) | **succès** : il n'était déjà plus là |
| `1618` | Une autre installation est en cours | réessayer plus tard |
| `1641` | Succès, redémarrage déclenché | à éviter en déploiement silencieux (`/norestart`) |
| `0x87D1041C` | Détection Intune en échec | typiquement le piège de bitness (ARP sous `WOW6432Node`) |
