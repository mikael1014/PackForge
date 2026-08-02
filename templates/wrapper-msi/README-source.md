# MODÈLE — `README-source.md` (provenance du binaire)

> À placer **dans le dossier du package**, à côté du `.ps1` et de la source.
> Répond à une seule question, six mois plus tard ou face à un audit :
> **« d'où vient exactement ce binaire, et qui l'a mis là ? »**
> Supprimer ce bandeau après copie.

---

## Source

| | |
|---|---|
| **Fichier** | `<nom exact du fichier, version comprise>` |
| **Éditeur** | `<raison sociale>` |
| **URL de téléchargement** | `<URL complète et directe>` |
| **Date de téléchargement** | `JJ/MM/AAAA` |
| **Taille** | `<xx,x Mo>` |
| **SHA-256** | `<empreinte>` |
| **Origine** | site officiel de l'éditeur \| portail client \| fourni par `<nom>` le `JJ/MM/AAAA` |

Calcul de l'empreinte :
```powershell
Get-FileHash -LiteralPath "C:/chemin/vers/le-fichier.msi" -Algorithm SHA256 | Format-List
```

## Identifiants MSI

| | |
|---|---|
| **ProductCode** | `{GUID}` |
| **UpgradeCode** | `{GUID}` |
| **Type d'installation** | machine (`ALLUSERS=1`) \| per-user |

## Éléments fournis par le client

`<fichier de licence, provisionnement VPN, fichier de configuration…>` — **et par qui, à quelle date**.

> ⚠️ **Aucun secret dans le dépôt** : clé de licence, mot de passe, coffre, jeton.
> Décrire le fichier attendu et **où le récupérer**, jamais son contenu.

## Packagé par

`<Prénom Nom>` — `JJ/MM/AAAA`
