<#
  Rilascio di una nuova versione ufficiale del gestionale.

  Uso (doppio clic su rilascia.bat, oppure dal terminale nella cartella del repo):
    rilascia.bat          V1.0.0 -> V1.0.1  (correzioni e piccole modifiche)
    rilascia.bat minor    V1.0.0 -> V1.1.0  (nuove funzioni)
    rilascia.bat major    V1.0.0 -> V2.0.0  (cambiamenti grossi)
    rilascia.bat 1.2.0    versione precisa (es. per il primo rilascio: rilascia.bat 1.0.0)
    rilascia.bat prova    mostra solo quale sarebbe la prossima versione, non cambia niente

  Cosa fa, tutto da solo:
    1. controlla di essere su main e che tutto sia salvato;
    2. esegue i test;
    3. scrive la versione in pubspec.yaml e crea l'APK in rilasci\;
    4. prepara le note (da note-rilascio\Vx.y.z.md se c'e, altrimenti dai commit);
    5. fa commit "Rilascio Vx.y.z", tag vx.y.z e push su GitHub;
    6. crea la Release su GitHub con le note e l'APK allegato.
  La versione compare in fondo alla schermata principale dell'app.
#>
param([string]$Tipo = 'patch')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Set-Location $PSScriptRoot
$app = Join-Path $PSScriptRoot 'applicazione_gestionale'
$pubspec = Join-Path $app 'pubspec.yaml'
$utf8 = New-Object Text.UTF8Encoding $false

$prova = $Tipo -eq 'prova'
if ($prova) { $Tipo = 'patch' }
$versionePrecisa = $Tipo -match '^\d+\.\d+\.\d+$'
if (-not $versionePrecisa -and $Tipo -notin @('patch', 'minor', 'major')) {
  throw "Tipo sconosciuto '$Tipo'. Usa: patch, minor, major, una versione tipo 1.0.0, oppure prova."
}

# --- calcolo della nuova versione ---
$content = [IO.File]::ReadAllText($pubspec)
# Funziona sia con righe Windows (CRLF) sia Unix (LF): il fine riga non viene toccato.
$m = [regex]::Match($content, '(?m)^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)(?=[ \t]*\r?$)')
if (-not $m.Success) { throw 'Riga "version: x.y.z+n" non trovata in pubspec.yaml' }
$major = [int]$m.Groups[1].Value
$minor = [int]$m.Groups[2].Value
$patch = [int]$m.Groups[3].Value
$build = [int]$m.Groups[4].Value
$old = "$major.$minor.$patch"
if ($versionePrecisa) {
  $new = $Tipo
} else {
  switch ($Tipo) {
    'major' { $major++; $minor = 0; $patch = 0 }
    'minor' { $minor++; $patch = 0 }
    default { $patch++ }
  }
  $new = "$major.$minor.$patch"
}
$build++
Write-Host ""
Write-Host "Versione attuale: V$old   ->   nuova versione: V$new (build $build)" -ForegroundColor Cyan
if ($prova) { Write-Host 'Modalita prova: non cambio niente.'; exit 0 }

# --- controlli prima di partire ---
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') { throw "Sei sul branch '$branch'. I rilasci ufficiali si fanno da main." }
if (git status --porcelain) { throw 'Ci sono modifiche non salvate: fai prima il commit.' }
if (git tag --list "v$new") { throw "La versione V$new esiste gia (tag v$new)." }

# --- test, versione, APK ---
Push-Location $app
try {
  Write-Host 'Eseguo i test...' -ForegroundColor Cyan
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'I test non passano: rilascio annullato.' }

  $newContent = $content.Remove($m.Index, $m.Length).Insert($m.Index, "version: $new+$build")
  [IO.File]::WriteAllText($pubspec, $newContent, $utf8)

  Write-Host 'Creo l''APK (la prima volta puo volerci qualche minuto)...' -ForegroundColor Cyan
  flutter build apk --release
  if ($LASTEXITCODE -ne 0) {
    [IO.File]::WriteAllText($pubspec, $content, $utf8)
    throw 'Creazione APK non riuscita: rilascio annullato, versione ripristinata.'
  }
}
finally {
  Pop-Location
}

$outDir = Join-Path $PSScriptRoot 'rilasci'
New-Item -ItemType Directory -Force $outDir | Out-Null
$apkName = "Gestionale-Spiaggia-V$new.apk"
$apk = Join-Path $outDir $apkName
Copy-Item (Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk') $apk -Force

# --- note di rilascio ---
$curated = Join-Path $PSScriptRoot "note-rilascio\V$new.md"
if (Test-Path $curated) {
  $notes = [IO.File]::ReadAllLines($curated, $utf8)
} else {
  $previousTag = git tag --list 'v*' --sort=-v:refname | Select-Object -First 1
  if ($previousTag) {
    $changes = git log --no-merges --pretty='- %s' "$previousTag..HEAD"
  } else {
    $changes = git log --no-merges --pretty='- %s' -n 30
  }
  $changes = $changes | Where-Object { $_ -notmatch '^- Rilascio V' }
  $notes = @("## Versione V$new", '', 'Novita e correzioni:', '') + $changes
}
$notes = @($notes) + @('', "Da installare sui telefoni: $apkName")
$notesFile = Join-Path $outDir "Note-V$new.md"
[IO.File]::WriteAllLines($notesFile, $notes, $utf8)

# --- commit, tag e push ---
git add applicazione_gestionale/pubspec.yaml
git commit -m "Rilascio V$new"
if ($LASTEXITCODE -ne 0) { throw 'Commit non riuscito.' }
git tag -a "v$new" -m "Versione V$new"
git push
if ($LASTEXITCODE -ne 0) { throw 'Push non riuscito: la versione e salvata in locale, riprova con "git push --follow-tags".' }
git push origin "v$new"
if ($LASTEXITCODE -ne 0) { throw 'Push del tag non riuscito: riprova con "git push origin v' + $new + '".' }

Write-Host ""
Write-Host "Versione V$new salvata su GitHub (commit e tag)." -ForegroundColor Green
Write-Host "APK: $apk"

# --- Release su GitHub con l'APK allegato ---
$remote = (git remote get-url origin).Trim()
$rm = [regex]::Match($remote, 'github\.com[/:]([^/]+)/([^/]+?)(\.git)?$')
$repoUrl = $remote -replace '\.git$', '' -replace '://[^@/]+@', '://'
$creata = $false
if ($rm.Success) {
  $owner = $rm.Groups[1].Value
  $repo = $rm.Groups[2].Value
  try {
    # Credenziali GitHub gia salvate su questo PC (Git Credential Manager): non vengono mostrate ne salvate altrove.
    $userPart = ''
    $um = [regex]::Match($remote, '://([^@/]+)@')
    if ($um.Success) { $userPart = "username=$($um.Groups[1].Value)`n" }
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE = 'never'
    $cred = "protocol=https`nhost=github.com`n$userPart`n" | git credential fill 2>$null
    $token = (($cred | Where-Object { $_ -like 'password=*' }) -replace '^password=', '')
    if (-not $token) { throw 'credenziali GitHub non trovate' }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{
      Authorization          = "Bearer $token"
      Accept                 = 'application/vnd.github+json'
      'X-GitHub-Api-Version' = '2022-11-28'
      'User-Agent'           = 'rilascia-gestionale-spiaggia'
    }
    $body = @{ tag_name = "v$new"; name = "V$new"; body = ($notes -join "`n"); draft = $false; prerelease = $false } | ConvertTo-Json
    $release = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$owner/$repo/releases" -Headers $headers `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json; charset=utf-8'
    $uploadUrl = $release.upload_url -replace '\{.*\}$', ''
    Write-Host 'Carico l''APK sulla Release...' -ForegroundColor Cyan
    Invoke-RestMethod -Method Post -Uri "${uploadUrl}?name=$apkName" -Headers $headers -InFile $apk `
      -ContentType 'application/vnd.android.package-archive' | Out-Null
    $creata = $true
    Write-Host ""
    Write-Host "Release V$new pubblicata su GitHub con l'APK: $($release.html_url)" -ForegroundColor Green
    Start-Process $release.html_url
  }
  catch {
    Write-Host ""
    Write-Host "Non sono riuscito a creare la Release da solo ($($_.Exception.Message))." -ForegroundColor Yellow
  }
  finally {
    $token = $null
    $headers = $null
  }
}
if (-not $creata) {
  Write-Host 'Ultimo passo a mano: si apre GitHub. Incolla le note (gia copiate), trascina l''APK e premi "Publish release".'
  Set-Clipboard -Value ($notes -join "`r`n")
  Start-Process "$repoUrl/releases/new?tag=v$new&title=V$new"
  explorer.exe "/select,$apk"
}
