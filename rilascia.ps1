<#
  Rilascio di una nuova versione ufficiale del gestionale.

  Uso (doppio clic su rilascia.bat, oppure dal terminale nella cartella del repo):
    rilascia.bat          V1.0.0 -> V1.0.1  (correzioni e piccole modifiche)
    rilascia.bat minor    V1.0.0 -> V1.1.0  (nuove funzioni)
    rilascia.bat major    V1.0.0 -> V2.0.0  (cambiamenti grossi)
    rilascia.bat prova    mostra solo quale sarebbe la prossima versione, non cambia niente

  Cosa fa: aumenta la versione in pubspec.yaml, esegue i test, crea l'APK in rilasci\,
  poi fa commit "Rilascio Vx.y.z", crea il tag vx.y.z e fa il push su GitHub.
  La versione compare in fondo alla schermata principale dell'app.
#>
param([string]$Tipo = 'patch')

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$app = Join-Path $PSScriptRoot 'applicazione_gestionale'
$pubspec = Join-Path $app 'pubspec.yaml'

$prova = $Tipo -eq 'prova'
if ($prova) { $Tipo = 'patch' }
if ($Tipo -notin @('patch', 'minor', 'major')) {
  throw "Tipo sconosciuto '$Tipo'. Usa: patch, minor, major oppure prova."
}

# --- calcolo della nuova versione ---
$content = [IO.File]::ReadAllText($pubspec)
$m = [regex]::Match($content, '(?m)^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*$')
if (-not $m.Success) { throw 'Riga "version: x.y.z+n" non trovata in pubspec.yaml' }
$major = [int]$m.Groups[1].Value
$minor = [int]$m.Groups[2].Value
$patch = [int]$m.Groups[3].Value
$build = [int]$m.Groups[4].Value
$old = "$major.$minor.$patch"
switch ($Tipo) {
  'major' { $major++; $minor = 0; $patch = 0 }
  'minor' { $minor++; $patch = 0 }
  default { $patch++ }
}
$build++
$new = "$major.$minor.$patch"
Write-Host ""
Write-Host "Versione attuale: V$old   ->   nuova versione: V$new (build $build)" -ForegroundColor Cyan
if ($prova) { Write-Host 'Modalita prova: non cambio niente.'; exit 0 }

# --- controlli prima di partire ---
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') { throw "Sei sul branch '$branch'. I rilasci ufficiali si fanno da main." }
if (git status --porcelain) { throw 'Ci sono modifiche non salvate: fai prima il commit.' }
if (git tag --list "v$new") { throw "Il tag v$new esiste gia." }

# --- test, versione, APK ---
Push-Location $app
try {
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'I test non passano: rilascio annullato.' }

  $newContent = $content.Remove($m.Index, $m.Length).Insert($m.Index, "version: $new+$build")
  [IO.File]::WriteAllText($pubspec, $newContent, (New-Object Text.UTF8Encoding $false))

  flutter build apk --release
  if ($LASTEXITCODE -ne 0) {
    [IO.File]::WriteAllText($pubspec, $content, (New-Object Text.UTF8Encoding $false))
    throw 'Creazione APK non riuscita: rilascio annullato, versione ripristinata.'
  }
}
finally {
  Pop-Location
}

$outDir = Join-Path $PSScriptRoot 'rilasci'
New-Item -ItemType Directory -Force $outDir | Out-Null
$apk = Join-Path $outDir "Gestionale-Spiaggia-V$new.apk"
Copy-Item (Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk') $apk -Force

# --- note di rilascio: le modifiche dall'ultima versione ---
$previousTag = git tag --list 'v*' --sort=-v:refname | Select-Object -First 1
if ($previousTag) {
  $changes = git log --no-merges --pretty='- %s' "$previousTag..HEAD"
} else {
  $changes = git log --no-merges --pretty='- %s' -n 30
}
$changes = $changes | Where-Object { $_ -notmatch '^- Rilascio V' }
$notesFile = Join-Path $outDir "Note-V$new.md"
$notes = @("## Versione V$new", '', 'Novita e correzioni:', '') + $changes + @('', 'Da installare: allegare il file APK Gestionale-Spiaggia-V' + $new + '.apk')
[IO.File]::WriteAllLines($notesFile, $notes, (New-Object Text.UTF8Encoding $false))

# --- commit, tag e push ---
git add applicazione_gestionale/pubspec.yaml
git commit -m "Rilascio V$new"
if ($LASTEXITCODE -ne 0) { throw 'Commit non riuscito.' }
git tag -a "v$new" -m "Versione V$new"
git push
if ($LASTEXITCODE -ne 0) { throw 'Push non riuscito: la versione e salvata in locale, riprova con "git push --follow-tags".' }
git push origin "v$new"

Write-Host ""
Write-Host "Fatto! Versione V$new rilasciata." -ForegroundColor Green
Write-Host "APK da installare sui telefoni: $apk"
Write-Host "Note di rilascio: $notesFile"

# --- pagina GitHub per pubblicare la Release (con le note e l'APK allegato) ---
$remote = (git remote get-url origin).Trim() -replace '\.git$', '' -replace '://[^@/]+@', '://'
if ($remote -match '^https://github\.com/') {
  $releaseUrl = "$remote/releases/new?tag=v$new&title=V$new"
  Write-Host ""
  Write-Host 'Ultimo passo (1 minuto): si apre GitHub. Incolla le note, trascina l''APK nel riquadro allegati e premi "Publish release".'
  Set-Clipboard -Value ($notes -join "`r`n")
  Write-Host '(Le note sono gia copiate: basta incollarle con Ctrl+V.)'
  Start-Process $releaseUrl
  explorer.exe "/select,$apk"
}
