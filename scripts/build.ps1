param(
    [ValidateSet('comm','image')][string]$Project='comm',
    [string]$VivadoBin='E:\lll\FPGA\Xilinx\Vivado\2018.3\bin'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$logs=Join-Path $root 'build_logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$id=$Project+'_'+[guid]::NewGuid().ToString('N')
$log=Join-Path $logs ($id+'.log')
$journal=Join-Path $logs ($id+'.jou')
Push-Location -LiteralPath $root
try {
    $source=(Join-Path $PSScriptRoot 'build_vivado.tcl').Replace('\','/')
    & (Join-Path $VivadoBin 'vivado.bat') -mode batch -source $source -log $log -journal $journal -tclargs $Project
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch 'PASS_BUILD:' -Quiet)) {
        throw "Build did not pass; see $log"
    }
} finally {Pop-Location}
