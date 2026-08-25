param(
  [string]$Executable = "app/build/windows/x64/runner/Profile/wallet_aps.exe",
  [int]$SampleSeconds = 30
)

$ErrorActionPreference = "Stop"
$outputDirectory = Join-Path $PSScriptRoot "../build/performance"
New-Item -ItemType Directory -Force $outputDirectory | Out-Null
$process = Start-Process -FilePath $Executable -PassThru
$samples = @()
try {
  for ($second = 0; $second -lt $SampleSeconds; $second++) {
    Start-Sleep -Seconds 1
    $process.Refresh()
    $samples += [pscustomobject]@{
      second = $second + 1
      workingSetBytes = $process.WorkingSet64
      privateMemoryBytes = $process.PrivateMemorySize64
    }
  }
} finally {
  if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null }
}
$report = [pscustomobject]@{
  timestampUtc = [DateTime]::UtcNow.ToString("o")
  platform = "windows"
  executable = $Executable
  samples = $samples
  peakWorkingSetBytes = ($samples | Measure-Object workingSetBytes -Maximum).Maximum
  peakPrivateMemoryBytes = ($samples | Measure-Object privateMemoryBytes -Maximum).Maximum
}
$report | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $outputDirectory "windows-memory.json")
$report | ConvertTo-Json -Depth 5
