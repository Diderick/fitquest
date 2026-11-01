$ErrorActionPreference = 'Stop'
$fitquestRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $fitquestRoot
try {
    if (-not (Test-Path -LiteralPath 'apps/fitquest/client-config.json')) {
        throw 'Missing private apps/fitquest/client-config.json. See the backend README.'
    }
    New-Item -ItemType Directory -Path 'build' -Force | Out-Null
    # Gradle can echo encoded credentials. Keep all build output in an ignored file.
    $fitquestPreviousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & flutter build apk --release --dart-define-from-file=apps/fitquest/client-config.json *> 'build/fitquest-private-build.log'
    $fitquestBuildExit = $LASTEXITCODE
    $ErrorActionPreference = $fitquestPreviousPreference
    if ($fitquestBuildExit -ne 0) {
        throw 'APK build failed. Inspect build/fitquest-private-build.log locally; it may contain credentials.'
    }
    Write-Output 'Connected APK ready: build/app/outputs/flutter-apk/app-release.apk'
} finally {
    Pop-Location
}
