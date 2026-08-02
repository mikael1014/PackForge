# LogModule.psm1 - v2.0.0 (PackForge)
#
# Logging de packages applicatifs (Intune / SCCM) : format CMTrace, encodage UTF-8 BOM unique,
# repli automatique de dossier, garde-fou de production, bilan fiable.
#
# GENEALOGIE
#   Derive d'un LogModule eprouve en production sur un parc grand compte (2024-2026,
#   plusieurs dizaines de packages Intune/SCCM). Cette v2 est la version GENERIQUE :
#   plus aucun chemin client code en dur.
#
# CE QUI CHANGE PAR RAPPORT AU MODULE D'ORIGINE
#   1. Les dossiers de log sont parametrables :
#        - defaut              : %PROGRAMDATA%\<Organization>\Logs, repli %LOCALAPPDATA%\<Organization>\Logs
#        - preset 'DonneesLog' : C:\Donnees\Log, repli C:\Donnees\Temp   (opt-in EXPLICITE)
#        - libre               : -LogPathCandidates @('D:\Logs','C:\Temp')
#   2. Le garde-fou "ANOMALIE PROD" est generique : sous SYSTEM, si le dossier retenu n'est PAS
#      le candidat de production (le premier de la liste), on logue une anomalie au lieu de la subir.
#   3. L'ACL large (Everyone:Write) du master n'est plus posee par defaut -> switch -SharedWriteAccess.
#   4. Correction d'un bug silencieux du master : le nom des archives de rotation perdait le nom
#      du script ("$scriptBaseName_" etait lu comme la variable $scriptBaseName_, vide).
#   5. Lecture du BOM compatible PowerShell 5.1 ET 7 (plus de Get-Content -Encoding Byte).
#
# PREREQUIS : PowerShell 5.1+ (teste 5.1). Aucune dependance externe.
# ENCODAGE  : ce fichier DOIT rester en UTF-8 avec BOM.

# ---------------------------------------------------------------------------
# Variables de module
# ---------------------------------------------------------------------------
$Script:LogBasePath     = $null                                    # dossier retenu par Initialize-Logging
$Script:LogPathPrimary  = $null                                    # candidat de PRODUCTION (le premier)
$Script:LogPathCandidates = @()                                    # liste ordonnee des candidats
$Script:LogFile         = ""
$Script:MaxLogSize      = 5MB
$Script:MaxLogFiles     = 5
$Script:LogFormat       = "CMTrace"                                # 'CMTrace' (colore dans CMTrace.exe) ou 'Plain'
$Script:LogComponent    = ""                                       # nom du script appelant
$Script:LogEncoding     = New-Object System.Text.UTF8Encoding($true)  # UTF-8 BOM : encodage UNIQUE (anti-charabia)
$Script:CountInfo       = 0
$Script:CountWarning    = 0
$Script:CountError      = 0
$Script:IsSystem        = $false                                   # contexte SYSTEM (prod Intune/SCCM)

# ---------------------------------------------------------------------------
# Fonctions internes
# ---------------------------------------------------------------------------
function Test-LogPathWritable {
    # Tente de creer le dossier puis d'y ecrire un fichier temoin.
    # Retourne $true SEULEMENT si l'ecriture reussit reellement (on ne se fie jamais
    # a l'existence du dossier : un dossier peut exister sans etre accessible en ecriture).
    Param (
        [parameter(Mandatory = $true)][string]$Path,
        [parameter(Mandatory = $false)][switch]$SharedWriteAccess
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null

            if ($SharedWriteAccess) {
                # Best-effort : autorise les utilisateurs standard a ecrire dans un dossier cree par SYSTEM
                # (cas d'un package qui tourne dans les DEUX contextes). Non pose par defaut :
                # un dossier de logs inscriptible par tous est alterable par tous.
                try {
                    $acl  = Get-Acl -LiteralPath $Path
                    $sid  = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')  # BUILTIN\Users
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $sid, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
                    $acl.SetAccessRule($rule)
                    Set-Acl -LiteralPath $Path -AclObject $acl
                } catch { }
            }
        }

        $probe = Join-Path $Path ".write_test_$PID.tmp"
        [System.IO.File]::WriteAllText($probe, "test")
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

function Get-LogPathCandidateSet {
    # Construit la liste ordonnee des dossiers candidats selon le preset demande.
    # Le PREMIER de la liste est le candidat de PRODUCTION ; les suivants sont des replis de test.
    Param (
        [parameter(Mandatory = $false)][string]$Organization = 'Packaging',
        [parameter(Mandatory = $false)][ValidateSet('Default','DonneesLog')][string]$Preset = 'Default'
    )

    switch ($Preset) {
        'DonneesLog' {
            # Convention de certains parcs d'entreprise : dossiers C:\Donnees\* pre-crees par GPO,
            # C:\Donnees\Log reserve a SYSTEM et C:\Donnees\Temp servant de repli en test admin.
            # A n'activer que si le client impose cette arborescence.
            return @('C:\Donnees\Log', 'C:\Donnees\Temp')
        }
        default {
            $progData = $env:ProgramData
            if (-not $progData) { $progData = 'C:\ProgramData' }
            $localApp = $env:LOCALAPPDATA
            if (-not $localApp) { $localApp = Join-Path $env:USERPROFILE 'AppData\Local' }
            return @(
                (Join-Path $progData "$Organization\Logs"),
                (Join-Path $localApp "$Organization\Logs")
            )
        }
    }
}

# ---------------------------------------------------------------------------
# API publique
# ---------------------------------------------------------------------------
function Get-LogBasePath {
    # Dossier de log reellement retenu (utile pour y deposer d'autres fichiers).
    return $Script:LogBasePath
}

function Get-LogPath {
    # Chemin complet d'un fichier AUXILIAIRE (log MSI verbeux, log natif d'installeur...)
    # DANS le dossier reellement retenu.
    # Regle : ne JAMAIS coder un chemin de log en dur dans un wrapper -> passer par ici.
    Param (
        [parameter(Mandatory = $true)][string]$FileName
    )
    if (-not $Script:LogBasePath) {
        throw "Get-LogPath : Initialize-Logging doit etre appele avant (LogBasePath non defini)."
    }
    return (Join-Path $Script:LogBasePath $FileName)
}

function Initialize-Logging {
    <#
    .SYNOPSIS
        Initialise le journal du package : choisit le dossier, gere la rotation, detecte le contexte.
    .PARAMETER Organization
        Nom de dossier utilise dans %PROGRAMDATA%\<Organization>\Logs (preset Default uniquement).
        Mettre le nom du client ou du produit. Defaut : 'Packaging'.
    .PARAMETER Preset
        'Default' (generique) ou 'DonneesLog' (C:\Donnees\Log -> repli C:\Donnees\Temp,
        convention imposee par certains parcs d'entreprise).
    .PARAMETER LogPathCandidates
        Override total de la liste des dossiers candidats, du plus prioritaire au dernier repli.
    .PARAMETER SharedWriteAccess
        Pose une ACL Users:Modify sur le dossier cree (packages tournant en SYSTEM *et* en User).
        Non actif par defaut.
    .EXAMPLE
        Initialize-Logging -Organization 'Contoso'
    .EXAMPLE
        Initialize-Logging -Preset DonneesLog
    #>
    Param (
        [parameter(Mandatory = $false)][long]$MaxSize = 5MB,
        [parameter(Mandatory = $false)][int]$MaxFiles = 5,
        [parameter(Mandatory = $false)][ValidateSet('CMTrace','Plain')][string]$Format = 'CMTrace',
        [parameter(Mandatory = $false)][string]$Organization = 'Packaging',
        [parameter(Mandatory = $false)][ValidateSet('Default','DonneesLog')][string]$Preset = 'Default',
        [parameter(Mandatory = $false)][string[]]$LogPathCandidates,
        [parameter(Mandatory = $false)][switch]$SharedWriteAccess
    )

    $Script:MaxLogSize   = $MaxSize
    $Script:MaxLogFiles  = $MaxFiles
    $Script:LogFormat    = $Format
    $Script:CountInfo    = 0
    $Script:CountWarning = 0
    $Script:CountError   = 0

    # --- Nom du script appelant (= composant CMTrace + nom du fichier de log)
    $scriptName = $MyInvocation.PSCommandPath
    if (-not $scriptName) {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) { $scriptName = $callStack[1].ScriptName }
    }
    if (-not $scriptName) {
        throw "Initialize-Logging : impossible de determiner le nom du script appelant."
    }
    $scriptBaseName      = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)
    $Script:LogComponent = $scriptBaseName

    # --- Contexte d'execution : SYSTEM (prod) vs compte interactif (test admin/user)
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $Script:IsSystem = ($id.User.Value -eq 'S-1-5-18')
    } catch { $Script:IsSystem = $false }

    # --- Choix du dossier : premier candidat REELLEMENT accessible en ecriture
    if ($LogPathCandidates -and $LogPathCandidates.Count -gt 0) {
        $Script:LogPathCandidates = $LogPathCandidates
    } else {
        $Script:LogPathCandidates = Get-LogPathCandidateSet -Organization $Organization -Preset $Preset
    }
    $Script:LogPathPrimary = $Script:LogPathCandidates[0]

    $Script:LogBasePath = $null
    foreach ($candidate in $Script:LogPathCandidates) {
        if (Test-LogPathWritable -Path $candidate -SharedWriteAccess:$SharedWriteAccess) {
            $Script:LogBasePath = $candidate
            break
        }
    }
    if (-not $Script:LogBasePath) {
        throw "Aucun dossier de log accessible en ecriture parmi : $($Script:LogPathCandidates -join ', ')"
    }

    $Script:LogFile = Join-Path $Script:LogBasePath "$scriptBaseName.log"

    # --- Securite encodage : un log preexistant en UTF-16 (ancien format) est archive,
    #     sinon le fichier melangerait deux encodages -> charabia dans CMTrace.
    if (Test-Path -LiteralPath $Script:LogFile) {
        try {
            $bom = New-Object byte[] 2
            $fs  = [System.IO.File]::OpenRead($Script:LogFile)
            try { $read = $fs.Read($bom, 0, 2) } finally { $fs.Dispose() }
            if ($read -eq 2 -and (($bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) -or ($bom[0] -eq 0xFE -and $bom[1] -eq 0xFF))) {
                $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                Move-Item -LiteralPath $Script:LogFile `
                          -Destination (Join-Path $Script:LogBasePath "${scriptBaseName}_pre-utf8_$stamp.log") -Force
            }
        } catch { }
    }

    # --- Rotation
    try {
        if (Test-Path -LiteralPath $Script:LogFile) {
            $item = Get-Item -LiteralPath $Script:LogFile
            if ($item.Length -gt $Script:MaxLogSize) {
                $archivePath = Join-Path $Script:LogBasePath 'archive'
                if (-not (Test-Path -LiteralPath $archivePath)) {
                    New-Item -ItemType Directory -Path $archivePath -Force | Out-Null
                }

                $archiveFiles = @(Get-ChildItem -LiteralPath $archivePath -Filter "$scriptBaseName*.log" -ErrorAction SilentlyContinue |
                                  Sort-Object LastWriteTime -Descending)
                if ($archiveFiles.Count -ge $Script:MaxLogFiles) {
                    $archiveFiles[($Script:MaxLogFiles - 1)..($archiveFiles.Count - 1)] | Remove-Item -Force -ErrorAction SilentlyContinue
                }

                # ${scriptBaseName} : les accolades sont OBLIGATOIRES, sinon PowerShell lit
                # la variable "$scriptBaseName_" (l'underscore fait partie d'un nom de variable)
                # et le nom d'archive perd le nom du script. Bug present dans le master historique.
                $archiveName = Join-Path $archivePath "${scriptBaseName}_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
                Move-Item -LiteralPath $Script:LogFile -Destination $archiveName -Force
            }
        }
    }
    catch {
        Write-Host "Erreur lors de l'initialisation des logs: $_" -ForegroundColor Red
        throw
    }

    # --- Garde-fou production : sous SYSTEM, on doit ecrire dans le candidat de PRODUCTION.
    #     Si on a bascule sur un repli de test, c'est une anomalie -> on la signale au lieu de la subir.
    if ($Script:IsSystem -and $Script:LogBasePath -ne $Script:LogPathPrimary) {
        LogProcess -Level 'WARNING' -Message ("ANOMALIE PROD: execution SYSTEM mais logs dans '{0}' au lieu de '{1}' (non accessible en ecriture). En production, les logs doivent etre dans le dossier principal." -f $Script:LogBasePath, $Script:LogPathPrimary)
    }
}

function LogProcess {
    Param (
        [parameter(Mandatory = $true)][string]$Message,
        [parameter(Mandatory = $false)][ValidateSet('DEBUG','INFO','WARNING','ERROR')][string]$Level = 'INFO'
    )

    try {
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Colors = @{ ForegroundColor = "Green" }
        switch ($Level) {
            'ERROR'   { $Colors = @{ ForegroundColor = "Red" } }
            'WARNING' { $Colors = @{ ForegroundColor = "Yellow" } }
            'DEBUG'   { $Colors = @{ ForegroundColor = "Gray" } }
        }
        Write-Host "$FormattedDate ${Level}: $Message" @Colors

        if ($Script:LogFormat -eq 'CMTrace') {
            # type 1 = info (noir), 2 = warning (jaune), 3 = error (rouge) dans CMTrace.exe
            $typeMap = @{ 'INFO' = 1; 'WARNING' = 2; 'ERROR' = 3; 'DEBUG' = 1 }
            $type = $typeMap[$Level]
            if (-not $type) { $type = 1 }
            $now    = Get-Date
            $offset = "{0:+000;-000}" -f [int][System.TimeZoneInfo]::Local.GetUtcOffset($now).TotalMinutes
            $time   = $now.ToString("HH:mm:ss.fff") + $offset
            $date   = $now.ToString("MM-dd-yyyy")
            $line   = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="{5}" file="">' -f `
                        $Message, $time, $date, $Script:LogComponent, $type, $PID
        } else {
            $line = "${FormattedDate} ${Level}: ${Message}"
        }

        # Encodage UNIQUE (UTF-8 BOM) pour tout le fichier -> aucun melange possible
        [System.IO.File]::AppendAllText($Script:LogFile, $line + [System.Environment]::NewLine, $Script:LogEncoding)

        switch ($Level) {
            'ERROR'   { $Script:CountError++ }
            'WARNING' { $Script:CountWarning++ }
            default   { $Script:CountInfo++ }
        }
    }
    catch {
        Write-Host "Erreur lors de l'ecriture dans le fichier de log: $_" -ForegroundColor Red
        throw
    }
}

function LogSection {
    Param (
        [parameter(Mandatory = $true)][string]$Title
    )
    LogProcess -Message "==================================================" -Level "INFO"
    LogProcess -Message $Title -Level "INFO"
    LogProcess -Message "==================================================" -Level "INFO"
}

# Helpers explicites (plus courts et plus surs que LogProcess -Level X)
function LogInfo  { Param([parameter(Mandatory = $true)][string]$Message) LogProcess -Message $Message -Level 'INFO'    }
function LogWarn  { Param([parameter(Mandatory = $true)][string]$Message) LogProcess -Message $Message -Level 'WARNING' }
function LogError { Param([parameter(Mandatory = $true)][string]$Message) LogProcess -Message $Message -Level 'ERROR'   }
function LogDebug { Param([parameter(Mandatory = $true)][string]$Message) LogProcess -Message $Message -Level 'DEBUG'   }

function Get-LogSummary {
    # Bilan des niveaux emis depuis Initialize-Logging (comptage automatique, jamais a la main).
    return [pscustomobject]@{
        Info      = $Script:CountInfo
        Warning   = $Script:CountWarning
        Error     = $Script:CountError
        LogFile   = $Script:LogFile
        BasePath  = $Script:LogBasePath
        IsSystem  = $Script:IsSystem
    }
}

Export-ModuleMember -Function LogProcess, Initialize-Logging, LogSection, Get-LogBasePath, Get-LogPath,
                              LogInfo, LogWarn, LogError, LogDebug, Get-LogSummary
