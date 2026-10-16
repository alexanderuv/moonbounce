# Records and replays the environment the Swift installer sets on Windows, so
# CI can cache the installed toolchain (see the windows job in ci.yml).
#
#   snapshot  Before installing: saves the job's environment.
#   record    After installing: writes the variables and search paths the
#             installer set beside the toolchain's folder, then checks that the
#             environment from the snapshot plus that record alone can build
#             and test a package, as a run that restores the cache must.
#   replay    After restoring the cache: sets the recorded environment for the
#             job's later steps.
param(
    [Parameter(Mandatory)]
    [ValidateSet('snapshot', 'record', 'replay')]
    [string] $Action
)
$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:LOCALAPPDATA 'Programs\Swift'
$Snapshot = Join-Path $env:RUNNER_TEMP 'environment-before-swift.xml'
# Recorded values name the toolchain's folder by this token, so the cache
# doesn't depend on the runner's profile path.
$Token = '%SWIFT_ROOT%'

function Read-Record {
    [pscustomobject]@{
        Variables = @(Get-Content "$Root.env" | ForEach-Object {
            $Name, $Value = $_ -split '=', 2
            [pscustomobject]@{ Name = $Name; Value = $Value.Replace($Token, $Root) }
        })
        Paths = @(Get-Content "$Root.path" | ForEach-Object { $_.Replace($Token, $Root) })
    }
}

function Invoke-Checked([string] $Command, [string[]] $Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Host "::error::$Command $Arguments failed in the recorded environment"
        exit 1
    }
}

switch ($Action) {
    'snapshot' {
        Get-ChildItem Env: | Export-Clixml $Snapshot
    }
    'record' {
        $User = [Environment]::GetEnvironmentVariables('User')
        $User.GetEnumerator() |
            Where-Object { $_.Name -ne 'Path' -and $_.Value -like "*$Root*" } |
            ForEach-Object { "$($_.Name)=$($_.Value.Replace($Root, $Token))" } |
            Set-Content "$Root.env"
        $User['Path'] -split ';' |
            Where-Object { $_ -like "$Root*" } |
            ForEach-Object { $_.Replace($Root, $Token) } |
            Set-Content "$Root.path"
        Get-Content "$Root.env", "$Root.path"

        # The installer's step exported the whole environment it left, so the
        # rest of this job can't tell whether the record is complete. Rebuild
        # the environment a restoring run starts from, and run the toolchain.
        $Record = Read-Record
        $Before = Import-Clixml $Snapshot
        Get-ChildItem Env: | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name, $null) }
        $Before | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name, $_.Value) }
        $Record.Variables | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name, $_.Value) }
        $env:Path = (@($Record.Paths) + $env:Path) -join ';'
        Invoke-Checked swift '--version'
        # A package with one Swift Testing test needs what the job's own steps
        # do: swift-build, the SDK, the runtime and the testing libraries.
        $Probe = Join-Path $env:RUNNER_TEMP 'toolchain-probe'
        New-Item -ItemType Directory -Force "$Probe\Sources\Probe", "$Probe\Tests\ProbeTests" | Out-Null
        Set-Content "$Probe\Package.swift" @'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Probe",
    targets: [
        .target(name: "Probe"),
        .testTarget(name: "ProbeTests", dependencies: ["Probe"]),
    ]
)
'@
        Set-Content "$Probe\Sources\Probe\Probe.swift" 'public func answer() -> Int { 42 }'
        Set-Content "$Probe\Tests\ProbeTests\ProbeTests.swift" @'
import Probe
import Testing

@Test func answerIsFortyTwo() {
    #expect(Probe.answer() == 42)
}
'@
        # A run that finds no tests also exits 0 (see swift-test.sh), so
        # require the one test to have run.
        $Output = & swift test --package-path $Probe 2>&1 | ForEach-Object { "$_" }
        $Output
        if ($LASTEXITCODE -ne 0 -or -not ($Output -match 'Test run with 1 test')) {
            Write-Host "::error::swift test didn't run the probe's test in the recorded environment"
            exit 1
        }
    }
    'replay' {
        $Record = Read-Record
        $Record.Variables | ForEach-Object { "$($_.Name)=$($_.Value)" } | Add-Content $env:GITHUB_ENV
        # Each line of GITHUB_PATH goes in front of the last, so add the paths
        # in reverse to keep the installer's order.
        $Paths = $Record.Paths
        [Array]::Reverse($Paths)
        $Paths | Add-Content $env:GITHUB_PATH
    }
}
