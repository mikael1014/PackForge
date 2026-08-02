# =============================================================================
#  TEMPLATE - WRAPPER MSI (install / desinstall / reinstall) - PackForge v1.0.0
# =============================================================================
#
#  MODE D'EMPLOI (3 etapes, ~10 minutes)
#  ------------------------------------------------------------------------
#  1. RENOMMER ce fichier selon la convention :
#        {Editeur}_{Produit}_{Version}_{Archi}_{Release}.ps1
#        ex. iterate_Cyberduck_9.5.0_x64_R1.ps1
#     Le nom du fichier devient le nom du composant dans le log CMTrace.
#
#  2. REMPLIR le bloc $PackageConfig ci-dessous (seule zone a modifier).
#     Toute valeur laissee a "[A-REMPLIR]" fait echouer le script au demarrage
#     avec un message explicite : impossible de deployer un template non rempli.
#
#  3. LIVRER le dossier du package avec :
#        - ce .ps1 renomme
#        - LogModule.psm1   (copie depuis PackForge\modules\)
#        - le MSI source
#        - README-source.md (provenance : URL + date + empreinte)
#     Puis remplir la fiche Intune (voir templates\wrapper-msi\Packages.md).
#
#  COMMANDES INTUNE / SCCM
#     Install   : powershell -executionpolicy Bypass -file ".\<Nom>.ps1" -Install
#     Uninstall : powershell -executionpolicy Bypass -file ".\<Nom>.ps1"
#     (les guillemets et le ".\" sont OBLIGATOIRES cote Intune)
#
#  CODES RETOUR
#     0    succes
#     3010 succes + redemarrage requis (propage du MSI)
#     1603 echec
#     (1605 renvoye par msiexec en desinstall = produit deja absent -> traite en succes)
#
#  PIEGES DEJA DESAMORCES DANS CE TEMPLATE
#     - bitness : l'Intune Management Extension lance les scripts en 32-bit ; sans auto-relance,
#       l'ARP atterrit sous WOW6432Node et la detection ProductCode echoue (0x87D1041C).
#     - logs auxiliaires : plus aucun chemin en dur, tout passe par Get-LogPath.
#     - pas de supersedence : patron auto-nettoyant (desinstall prealable de la version presente).
# =============================================================================

[CmdletBinding()]
Param (
    [parameter(Mandatory = $false)][switch]$Install,
    [parameter(Mandatory = $false)][switch]$Trace,
    [parameter(Mandatory = $false)][switch]$Reinstall
)

# =============================================================================
# AUTO-RELANCE 64-BIT (parade au piege de bitness Intune)
# Doit rester AVANT toute autre action.
# =============================================================================
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    $sysnative = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $sysnative) {
        $argList = @('-ExecutionPolicy','Bypass','-NoProfile','-File', "`"$PSCommandPath`"")
        if ($Install)   { $argList += '-Install' }
        if ($Reinstall) { $argList += '-Reinstall' }
        if ($Trace)     { $argList += '-Trace' }
        $p = Start-Process -FilePath $sysnative -ArgumentList $argList -Wait -NoNewWindow -PassThru
        exit $p.ExitCode
    }
}

Import-Module -Name "$PSScriptRoot\LogModule.psm1" -Force

# Nom d'organisation utilise pour le dossier de logs : %PROGRAMDATA%\<Organization>\Logs
# (repli automatique sur %LOCALAPPDATA% en test compte utilisateur).
# Mettre le nom du client ou du produit.
$OrganizationName = "[A-REMPLIR-Organisation]"

# Controle AVANT Initialize-Logging : sinon un template non rempli creerait un dossier
# de logs portant litteralement le placeholder. Le log n'existe pas encore -> Write-Host.
if ($OrganizationName -match '\[A-REMPLIR') {
    Write-Host "TEMPLATE NON RENSEIGNE : renseigner la variable `$OrganizationName avant tout deploiement." -ForegroundColor Red
    exit 1603
}

# Si le client impose l'arborescence C:\Donnees\Log (repli C:\Donnees\Temp) :
# utiliser -Preset DonneesLog a la place de -Organization.
Initialize-Logging -Organization $OrganizationName

# =============================================================================
# ↓↓↓  SEULE ZONE A MODIFIER  ↓↓↓
# =============================================================================
$PackageConfig = @{
    # --- Identite du produit -------------------------------------------------
    AppName    = "[A-REMPLIR-NomProduit]"        # ex. "Cyberduck"
    AppVersion = "[A-REMPLIR-Version]"           # ex. "9.5.0.45237"

    # --- Source MSI (place a cote de ce script) ------------------------------
    Msi        = "$PSScriptRoot\[A-REMPLIR-NomDuFichier.msi]"

    # --- Identifiants MSI ----------------------------------------------------
    # Lecture rapide du ProductCode sans installer :
    #   Orca (table Property) ou :
    #   $w = New-Object -ComObject WindowsInstaller.Installer
    #   $db = $w.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$w,@('C:\chemin\vers.msi',0))
    #   $v = $db.GetType().InvokeMember('OpenView','InvokeMethod',$null,$db,@("SELECT Value FROM Property WHERE Property='ProductCode'"))
    #   $v.GetType().InvokeMember('Execute','InvokeMethod',$null,$v,$null)
    #   $r = $v.GetType().InvokeMember('Fetch','InvokeMethod',$null,$v,$null)
    #   $r.GetType().InvokeMember('StringData','GetProperty',$null,$r,1)
    ProductCode = "[A-REMPLIR-{GUID}]"           # ex. "{CB6B38BF-1F4D-4377-AB02-F96C5C3455F4}"

    # --- Proprietes MSI additionnelles (optionnel) ---------------------------
    # ALLUSERS=1 force l'installation machine. Ajouter ici les proprietes propres au produit
    # (ex. "ALLUSERS=1 DESKTOPSHORTCUT=0"). Laisser "" si aucune.
    MsiProperties = "ALLUSERS=1"

    # --- Processus a fermer avant install/desinstall (optionnel) --------------
    ProcessesToKill = @()                        # ex. @("Cyberduck")

    # --- Detection de repli, si le ProductCode ne suffit pas (optionnel) ------
    DetectionFilePath = ""                       # ex. "$env:ProgramFiles\Cyberduck\Cyberduck.exe"

    # --- Privileges ----------------------------------------------------------
    RequireAdmin = $true                         # $false uniquement pour un MSI per-user
}

# Fichiers de log auxiliaires : TOUJOURS via Get-LogPath (jamais de chemin en dur),
# ils suivent ainsi le dossier de log reellement retenu.
$PackageConfig.MsiLog       = Get-LogPath ("{0}_msiexec_install.log"   -f $PackageConfig.AppName)
$PackageConfig.MsiUninstLog = Get-LogPath ("{0}_msiexec_uninstall.log" -f $PackageConfig.AppName)

# =============================================================================
# ↑↑↑  FIN DE LA ZONE A MODIFIER  ↑↑↑
# =============================================================================

# =============================================================================
# FONCTIONS UTILITAIRES (generiques - ne pas modifier)
# =============================================================================

function Test-ConfigCompleted {
    # Garde-fou : un template non rempli ne doit JAMAIS partir en deploiement.
    $restants = @()
    foreach ($cle in @('AppName','AppVersion','Msi','ProductCode')) {
        if ("$($PackageConfig[$cle])" -match '\[A-REMPLIR') { $restants += $cle }
    }
    if ($restants.Count -gt 0) {
        LogProcess -Message ("TEMPLATE NON RENSEIGNE : champs restants -> {0}" -f ($restants -join ', ')) -Level "ERROR"
        LogProcess -Message "Remplir le bloc PackageConfig avant tout deploiement." -Level "ERROR"
        return $false
    }
    if ($PackageConfig.ProductCode -notmatch '^\{[0-9A-Fa-f\-]{36}\}$') {
        LogProcess -Message ("ProductCode invalide : '{0}' (attendu : {{GUID}} entre accolades)" -f $PackageConfig.ProductCode) -Level "ERROR"
        return $false
    }
    return $true
}

function Get-AppByProductCode {
    # Recherche le produit dans HKLM\...\Uninstall, vues 64 ET 32-bit.
    # OpenBaseKey contourne la redirection WOW6432Node : fiable quel que soit le bitness du process.
    $productCode  = $PackageConfig.ProductCode
    $subKeyParent = "Software\Microsoft\Windows\CurrentVersion\Uninstall"
    $views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)

    foreach ($view in $views) {
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $entry   = $baseKey.OpenSubKey("$subKeyParent\$productCode")
            if ($entry) {
                $displayName = $entry.GetValue("DisplayName")
                if ($displayName) {
                    $result = [PSCustomObject]@{
                        Nom         = $displayName
                        Version     = $entry.GetValue("DisplayVersion")
                        Editeur     = $entry.GetValue("Publisher")
                        ProductCode = $productCode
                        RegView     = $view.ToString()
                    }
                    $entry.Close(); $baseKey.Close()
                    return $result
                }
                $entry.Close()
            }
            $baseKey.Close()
        } catch { }   # vue indisponible ou cle absente -> candidat suivant
    }
    return $null
}

function Stop-RunningProcesses {
    if (-not $PackageConfig.ProcessesToKill -or $PackageConfig.ProcessesToKill.Count -eq 0) { return }
    LogSection -Title ("ARRET DES PROCESSUS {0}" -f $PackageConfig.AppName.ToUpper())
    foreach ($processName in $PackageConfig.ProcessesToKill) {
        $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($processes) {
            foreach ($proc in $processes) {
                try {
                    Stop-Process -Id $proc.Id -Force
                    LogProcess -Message "Processus arrete: $($proc.ProcessName)" -Level "INFO"
                } catch {
                    LogProcess -Message "Erreur arret processus $($proc.ProcessName): $_" -Level "WARNING"
                }
            }
            Start-Sleep -Seconds 2
        }
    }
}

function Test-RequiredFiles {
    LogSection -Title "VERIFICATION DES FICHIERS REQUIS"
    $allOk = $true
    foreach ($file in @($PackageConfig.Msi, "$PSScriptRoot\LogModule.psm1")) {
        if (Test-Path -LiteralPath $file) {
            $size = [math]::Round((Get-Item -LiteralPath $file).Length / 1MB, 2)
            LogProcess -Message "OK: $file ($size MB)" -Level "INFO"
        } else {
            LogProcess -Message "MANQUANT: $file" -Level "ERROR"
            $allOk = $false
        }
    }
    return $allOk
}

# =============================================================================
# INSTALL / UNINSTALL / VERIFICATION
# =============================================================================

function Invoke-PackageInstall {
    LogSection -Title ("INSTALLATION {0} (MSI)" -f $PackageConfig.AppName.ToUpper())

    # -ArgumentList en STRING UNIQUE : evite le double-quoting des tableaux par PowerShell.
    $props     = if ($PackageConfig.MsiProperties) { " $($PackageConfig.MsiProperties)" } else { "" }
    $argString = "/i `"$($PackageConfig.Msi)`"$props /quiet /norestart /l*v `"$($PackageConfig.MsiLog)`""
    LogProcess -Message "Commande: msiexec $argString" -Level "INFO"

    try {
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $argString -Wait -NoNewWindow -PassThru
        LogProcess -Message "Code retour MSI: $($process.ExitCode)" -Level "INFO"
        return $process.ExitCode
    } catch {
        LogProcess -Message "Exception MSI: $_" -Level "ERROR"
        return 1603
    }
}

function Invoke-PackageUninstall {
    LogSection -Title ("DESINSTALLATION {0}" -f $PackageConfig.AppName.ToUpper())

    $app = Get-AppByProductCode
    if (-not $app) {
        LogProcess -Message "$($PackageConfig.AppName) non trouve par ProductCode $($PackageConfig.ProductCode) - desinstallation ignoree" -Level "INFO"
        return 0
    }
    LogProcess -Message "Application trouvee: $($app.Nom) v$($app.Version) (vue $($app.RegView))" -Level "INFO"

    $argString = "/x $($PackageConfig.ProductCode) REBOOT=ReallySuppress /quiet /norestart /l*v `"$($PackageConfig.MsiUninstLog)`""
    LogProcess -Message "Commande: msiexec $argString" -Level "INFO"

    try {
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $argString -Wait -NoNewWindow -PassThru
        $code = $process.ExitCode
        if ($code -eq 1605) {
            # ERROR_UNKNOWN_PRODUCT : le produit n'est deja plus la -> objectif atteint
            LogProcess -Message "Code 1605 (ERROR_UNKNOWN_PRODUCT) : produit deja absent - considere desinstalle" -Level "INFO"
            return 0
        }
        LogProcess -Message "Code retour desinstallation: $code" -Level "INFO"
        return $code
    } catch {
        LogProcess -Message "Exception desinstallation: $_" -Level "ERROR"
        return 1603
    }
}

function Test-PackageInstallation {
    LogSection -Title "VERIFICATION POST-INSTALLATION"
    $app = Get-AppByProductCode
    if ($app) {
        LogProcess -Message "OK - trouve: $($app.Nom) v$($app.Version) (vue $($app.RegView))" -Level "INFO"
        return $true
    }
    # Repli fichier : certains MSI n'ecrivent pas un ProductCode exploitable
    if ($PackageConfig.DetectionFilePath -and (Test-Path -LiteralPath $PackageConfig.DetectionFilePath)) {
        LogProcess -Message "OK - detecte par fichier: $($PackageConfig.DetectionFilePath)" -Level "INFO"
        return $true
    }
    LogProcess -Message "$($PackageConfig.AppName) non detecte (ni ProductCode, ni fichier)" -Level "WARNING"
    return $false
}

# =============================================================================
# PROGRAMME PRINCIPAL
# =============================================================================
$global:ErrorCount = 0

LogSection -Title ("LANCEMENT DU PACKAGE {0}" -f ([System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)))
LogProcess -Message "Composant: $($PackageConfig.AppName) v$($PackageConfig.AppVersion)" -Level "INFO"
LogProcess -Message "Install: $Install | Reinstall: $Reinstall | Trace: $Trace" -Level "INFO"
LogProcess -Message "Contexte: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -Level "INFO"
LogProcess -Message "PS Process: $(if ([Environment]::Is64BitProcess) {'64-bit'} else {'32-bit'}) | OS: $(if ([Environment]::Is64BitOperatingSystem) {'64-bit'} else {'32-bit'})" -Level "INFO"

if (-not (Test-ConfigCompleted)) { exit 1603 }

if ($PackageConfig.RequireAdmin) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        LogProcess -Message "Le script doit etre execute avec des privileges administrateur (SYSTEM ou Admin)" -Level "ERROR"
        exit 1603
    }
}

if (-not (Test-RequiredFiles)) {
    LogProcess -Message "Arret du script - fichiers requis manquants" -Level "ERROR"
    exit 1603
}

# -----------------------------------------------------------------------------
if ($Reinstall) {
    LogSection -Title "MODE REINSTALLATION"
    $Install = $true
    Stop-RunningProcesses
    Invoke-PackageUninstall | Out-Null
    Start-Sleep -Seconds 3
}

# -----------------------------------------------------------------------------
if ($Install) {
    LogSection -Title "INSTALLATION"
    Stop-RunningProcesses

    # Patron auto-nettoyant : sans supersedence, on retire la version presente avant de poser la neuve.
    $existing = Get-AppByProductCode
    if ($existing) {
        LogProcess -Message "Version existante detectee ($($existing.Nom) v$($existing.Version)) - desinstallation prealable..." -Level "INFO"
        Invoke-PackageUninstall | Out-Null
        Start-Sleep -Seconds 3
    }

    $resultMsi    = Invoke-PackageInstall
    $rebootNeeded = $false

    if ($resultMsi -eq 0 -or $resultMsi -eq 3010) {
        LogProcess -Message "Installation MSI reussie (code: $resultMsi)" -Level "INFO"
        if ($resultMsi -eq 3010) {
            $rebootNeeded = $true
            LogProcess -Message "Redemarrage requis apres installation MSI (code 3010)" -Level "WARNING"
        }
        if (-not (Test-PackageInstallation)) {
            LogProcess -Message "Verification post-install: application non detectee" -Level "WARNING"
            $global:ErrorCount++
        }
    } else {
        LogProcess -Message "Echec installation MSI (code: $resultMsi)" -Level "ERROR"
        $global:ErrorCount++
    }

    LogSection -Title "RESUME FINAL INSTALLATION"
    LogProcess -Message "MSI    : code $resultMsi" -Level "INFO"
    LogProcess -Message "Erreurs: $global:ErrorCount" -Level "INFO"
    $sum = Get-LogSummary
    LogProcess -Message "Bilan log : INFO=$($sum.Info) WARNING=$($sum.Warning) ERROR=$($sum.Error) | fichier: $($sum.LogFile)" -Level "INFO"

    if ($global:ErrorCount -eq 0) {
        if ($rebootNeeded) {
            LogProcess -Message "Installation terminee avec succes - redemarrage requis (exit 3010)" -Level "INFO"
            exit 3010
        }
        LogProcess -Message "Installation terminee avec succes" -Level "INFO"
        exit 0
    }
    LogProcess -Message "Installation terminee avec erreurs ($global:ErrorCount)" -Level "WARNING"
    exit 1603
}

# -----------------------------------------------------------------------------
else {
    LogSection -Title "DESINSTALLATION"
    Stop-RunningProcesses

    $resultMsi = Invoke-PackageUninstall

    if (Get-AppByProductCode) {
        LogProcess -Message "$($PackageConfig.AppName) encore present apres desinstallation" -Level "WARNING"
        $global:ErrorCount++
    }

    LogSection -Title "RESUME FINAL DESINSTALLATION"
    LogProcess -Message "MSI    : code $resultMsi" -Level "INFO"
    LogProcess -Message "Erreurs: $global:ErrorCount" -Level "INFO"
    $sum = Get-LogSummary
    LogProcess -Message "Bilan log : INFO=$($sum.Info) WARNING=$($sum.Warning) ERROR=$($sum.Error)" -Level "INFO"

    if ($global:ErrorCount -eq 0) {
        LogProcess -Message "Desinstallation terminee avec succes" -Level "INFO"
        exit 0
    }
    LogProcess -Message "Desinstallation terminee avec erreurs ($global:ErrorCount)" -Level "WARNING"
    exit 1603
}
