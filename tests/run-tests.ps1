param(
    [switch]$IncludeRebuild
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EvidenceRoot = Join-Path $ProjectRoot "evidence\current"
$TesterIp = "192.168.56.20"
$ServerIp = "192.168.56.10"

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
Set-Location $ProjectRoot

$Results = [System.Collections.Generic.List[object]]::new()

function Save-Evidence {
    param([string]$Name, [string]$Text)
    $Text | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot "$Name.txt")
}

function Invoke-HostCommand {
    param([string]$Name, [scriptblock]$Command, [switch]$AllowFailure)
    $output = & $Command 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).TrimEnd()
    Save-Evidence -Name $Name -Text $text
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "Host command '$Name' failed with exit code $exitCode."
    }
    [pscustomobject]@{ ExitCode = $exitCode; Text = $text }
}

function Invoke-LabCommand {
    param(
        [string]$Name,
        [ValidateSet("server", "tester")][string]$Machine,
        [string]$Command,
        [switch]$AllowFailure,
        [int]$Retries = 1
    )
    $attempt = 0
    do {
        $attempt++
        $output = & vagrant ssh $Machine -c $Command 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -and $attempt -lt $Retries) {
            Start-Sleep -Seconds 5
        }
    } while ($exitCode -ne 0 -and $attempt -lt $Retries)
    $text = ($output | Out-String).TrimEnd()
    Save-Evidence -Name $Name -Text $text
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "Lab command '$Name' failed with exit code $exitCode."
    }
    [pscustomobject]@{ ExitCode = $exitCode; Text = $text }
}

function Add-Result {
    param([string]$Id, [string]$Description, [bool]$Passed, [string]$Evidence)
    $Results.Add([pscustomobject]@{
        Testfall = $Id
        Beschreibung = $Description
        Ergebnis = if ($Passed) { "BESTANDEN" } else { "FEHLGESCHLAGEN" }
        Nachweis = $Evidence
    })
}

function Invoke-TestCase {
    param([string]$Id, [string]$Description, [scriptblock]$Body)
    try {
        $evidence = & $Body
        Add-Result -Id $Id -Description $Description -Passed $true -Evidence ($evidence -join "; ")
        Write-Host "[PASS] $Id - $Description" -ForegroundColor Green
    }
    catch {
        Add-Result -Id $Id -Description $Description -Passed $false -Evidence $_.Exception.Message
        Write-Host "[FAIL] $Id - $Description`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Invoke-TestCase "T01" "Vagrant-Umgebung und Gesamtvalidierung sind erfolgreich." {
    $status = Invoke-HostCommand "T01-vagrant-status" { vagrant status --machine-readable }
    if ($status.Text -notmatch 'server,state,running' -or $status.Text -notmatch 'tester,state,running') {
        throw "Nicht beide VMs sind running."
    }
    $validation = Invoke-LabCommand "T01-security-test" server "sudo security-test"
    if ($validation.Text -notmatch '10/10 Pruefungen bestanden') {
        throw "security-test meldet nicht 10/10."
    }
    "vagrant status", "security-test 10/10"
}

Invoke-TestCase "T02" "Legitimer SSH-Login funktioniert." {
    $login = Invoke-LabCommand "T02-legitimate-login" tester 'sshpass -f /etc/defense-in-depth/lab-password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 labuser@192.168.56.10 hostname'
    if ($login.Text -notmatch 'security-server') { throw "Server-Hostname fehlt." }
    "security-server"
}

Invoke-TestCase "T03" "Root-Login wird technisch und wirksam verhindert." {
    $root = Invoke-LabCommand "T03-root-login" tester 'set +e; sshpass -f /etc/defense-in-depth/lab-password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=5 root@192.168.56.10 true; rc=$?; echo root_login_exit=$rc; exit 0'
    $setting = Invoke-LabCommand "T03-root-setting" server 'sudo sshd -T | grep permitrootlogin'
    if ($root.Text -notmatch 'root_login_exit=255' -or $setting.Text -notmatch 'permitrootlogin no') {
        throw "Root-Login ist nicht eindeutig blockiert."
    }
    "Verbindung abgewiesen", "permitrootlogin no"
}

Invoke-TestCase "T04" "Nicht erlaubter Port wird trotz aktivem Listener blockiert." {
    Invoke-LabCommand "T04-listener" server 'sudo nohup timeout 15 nc -l -p 8080 >/tmp/did-nc.log 2>&1 & sleep 1; ss -lnt | grep :8080' | Out-Null
    $blocked = Invoke-LabCommand "T04-firewall-block" tester 'set +e; nc -z -w 3 192.168.56.10 8080; rc=$?; echo port_8080_exit=$rc; exit 0'
    if ($blocked.Text -notmatch 'port_8080_exit=1') { throw "Port 8080 wurde nicht blockiert." }
    "Listener aktiv", "Verbindung durch INPUT drop blockiert"
}

Invoke-TestCase "T05" "Drei falsche SSH-Anmeldungen fuehren zum Fail2ban-Ban." {
    Invoke-LabCommand "T05-reset-ban" server "sudo fail2ban-client set sshd unbanip $TesterIp >/dev/null 2>&1 || true; sudo systemctl restart fail2ban; sleep 3" | Out-Null
    $banEvidencePath = Join-Path $EvidenceRoot "T05-ban-status.txt"
    Remove-Item -LiteralPath $banEvidencePath -Force -ErrorAction SilentlyContinue
    Invoke-LabCommand "T05-start-collector" server "sudo systemd-run --unit=did-ban-capture --collect capture-fail2ban-ban $TesterIp" | Out-Null
    Invoke-LabCommand "T05-failed-logins" tester 'set +e; for i in 1 2 3; do sshpass -p wrong-password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=5 labuser@192.168.56.10 true; echo attempt_${i}_exit=$?; done; exit 0' | Out-Null
    $deadline = (Get-Date).AddSeconds(25)
    do {
        Start-Sleep -Milliseconds 500
        $banText = if (Test-Path -LiteralPath $banEvidencePath) {
            Get-Content -LiteralPath $banEvidencePath -Raw
        } else { "" }
    } while ($banText -notmatch [regex]::Escape($TesterIp) -and (Get-Date) -lt $deadline)
    if ($banText -notmatch [regex]::Escape($TesterIp) -or $banText -notmatch 'addr-set-sshd') {
        throw "Aktiver Tester-Ban oder nftables-Set fehlt im Collector-Nachweis."
    }
    "Tester-IP gebannt", "nftables-Regel vorhanden"
}

Invoke-TestCase "T06" "Nach Bantime ist die Verbindung wieder moeglich." {
    Start-Sleep -Seconds 35
    $status = Invoke-LabCommand "T06-unban-status" server 'sudo fail2ban-client status sshd' -Retries 3
    $login = Invoke-LabCommand "T06-login-after-unban" tester 'sshpass -f /etc/defense-in-depth/lab-password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 labuser@192.168.56.10 hostname' -Retries 3
    if ($status.Text -notmatch 'Currently banned:\s+0' -or $login.Text -notmatch 'security-server') {
        throw "Automatischer Unban oder Login ist fehlgeschlagen."
    }
    "Currently banned: 0", "security-server"
}

Invoke-TestCase "T07" "Manipulation erzeugt ein Auditd-Ereignis mit Key did_demo." {
    $audit = Invoke-LabCommand "T07-audit-event" server 'date +audit-test-%s | sudo tee -a /opt/defense-in-depth/monitored/demo.txt >/dev/null; sleep 1; sudo ausearch -k did_demo -ts recent -i | tail -n 40'
    if ($audit.Text -notmatch 'key=did_demo|key="did_demo"') { throw "Audit-Key did_demo fehlt." }
    "ausearch -k did_demo"
}

Invoke-TestCase "T08" "AIDE erkennt eine kontrollierte Dateiveraenderung." {
    $aide = Invoke-LabCommand "T08-aide-detection" server 'set +e; sudo aide --config /etc/aide/defense-in-depth.conf --check; rc=$?; echo aide_exit=$rc; exit 0'
    if ($aide.Text -notmatch 'demo.txt' -or $aide.Text -match 'aide_exit=0') {
        throw "AIDE hat demo.txt nicht als veraendert gemeldet."
    }
    "demo.txt veraendert", "AIDE Exitcode ungleich 0"
}

Invoke-TestCase "T09" "Security-Dienste bleiben nach Neustart aktiv." {
    Invoke-HostCommand "T09-reload" { vagrant reload server } | Out-Null
    $services = Invoke-LabCommand "T09-services-after-restart" server 'systemctl is-active ssh nftables fail2ban auditd rsyslog'
    if (@($services.Text -split "\r?\n" | Where-Object { $_ -eq 'active' }).Count -ne 5) {
        throw "Nicht alle fuenf Security-Dienste sind aktiv."
    }
    "ssh, nftables, fail2ban, auditd, rsyslog aktiv"
}

if ($IncludeRebuild) {
    Invoke-TestCase "T10" "Kompletter Neuaufbau funktioniert." {
        Invoke-HostCommand "T10-destroy" { vagrant destroy -f } | Out-Null
        Invoke-HostCommand "T10-up" { vagrant up } | Out-Null
        $validation = Invoke-LabCommand "T10-security-test" server 'sudo security-test'
        if ($validation.Text -notmatch '10/10 Pruefungen bestanden') {
            throw "Gesamtvalidierung nach Neuaufbau ist fehlgeschlagen."
        }
        "vagrant destroy -f", "vagrant up", "security-test 10/10"
    }
}
else {
    $Results.Add([pscustomobject]@{
        Testfall = "T10"
        Beschreibung = "Kompletter Neuaufbau funktioniert."
        Ergebnis = "NICHT VERIFIZIERT"
        Nachweis = "Erneut mit -IncludeRebuild ausfuehren."
    })
    Write-Host "[SKIP] T10 - fuer Volltest -IncludeRebuild verwenden" -ForegroundColor Yellow
}

$Results | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $EvidenceRoot "test-results.csv")
$passed = @($Results | Where-Object Ergebnis -eq "BESTANDEN").Count
$failed = @($Results | Where-Object Ergebnis -eq "FEHLGESCHLAGEN").Count
$notVerified = @($Results | Where-Object Ergebnis -eq "NICHT VERIFIZIERT").Count
$summary = @(
    "Defense in Depth - automatisierter Testlauf"
    "Zeitpunkt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
    "Server: $ServerIp"
    "Tester: $TesterIp"
    "Bestanden: $passed"
    "Fehlgeschlagen: $failed"
    "Nicht verifiziert: $notVerified"
    ""
    ($Results | Format-Table -AutoSize | Out-String)
)
$summary | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot "test-summary.txt")
$summary

if ($failed -gt 0) { exit 1 }
