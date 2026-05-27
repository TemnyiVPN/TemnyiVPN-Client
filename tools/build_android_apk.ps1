param(
  [ValidateSet('Debug', 'Release')]
  [string]$Mode = 'Release',
  [string]$AndroidSdk = 'C:\Android\Sdk'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk

$flutter = 'C:\flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) {
  $flutter = 'flutter'
}

if ($Mode -eq 'Release') {
  $keyProperties = Join-Path $repoRoot 'android\key.properties'
  if (-not (Test-Path -LiteralPath $keyProperties)) {
    throw 'android\key.properties is missing. Provide a real release keystore before building publishable release APKs.'
  }
  & $flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
} else {
  & $flutter build apk --debug --split-per-abi --target-platform android-arm,android-arm64
}

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$output = Join-Path $repoRoot 'build\app\outputs\flutter-apk'
Get-ChildItem -LiteralPath $output -Filter '*.apk' |
  Sort-Object Length |
  Select-Object Name, Length, LastWriteTime
