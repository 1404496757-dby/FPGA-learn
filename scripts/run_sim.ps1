param(
    [ValidateSet('all','common','comm','uart_board','image','interview','spi')][string]$Test='all',
    [string]$VivadoBin='E:\lll\FPGA\Xilinx\Vivado\2018.3\bin',
    [string]$Python='python',
    [string]$FFmpeg='C:\Program Files\ffmpeg-7.0.2-full_build\bin\ffmpeg.exe'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!(Test-Path -LiteralPath (Join-Path $VivadoBin 'xvlog.bat'))) {throw 'Vivado bin not found'}
$tests=if($Test -eq 'all') {@('common','comm','uart_board','image','interview','spi')} else {@($Test)}
$records=@()
foreach($name in $tests) {
    $run=Join-Path $root ('runs\'+$name+'_'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $run | Out-Null
    $sources=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl\common') -Filter '*.v' | ForEach-Object FullName)
    switch($name) {
        'common' {$top='tb_common'; $marker='PASS_COMMON:'}
        'comm' {$top='tb_comm'; $marker='PASS_COMM:'; $sources+=@((Join-Path $root 'rtl\comm\spi_byte_engine.v'),(Join-Path $root 'rtl\comm\comm_service.v'),(Join-Path $root 'vendor\spi\SPI_Master.v'))}
        'uart_board' {$top='tb_uart_board'; $marker='PASS_UART_BOARD:'; $sources+=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl\comm') -Filter '*.v' | ForEach-Object FullName); $sources+=@((Join-Path $root 'vendor\spi\SPI_Master.v'),(Join-Path $root 'vendor\uart\uart_rx.v'),(Join-Path $root 'vendor\uart\uart_tx.v'))}
        'image' {$top='tb_image'; $marker='PASS_IMAGE:'; $sources+=@((Join-Path $root 'rtl\image\jls_frame_service.v'),(Join-Path $root 'vendor\jls\jls_encoder.v'))}
        'interview' {$top='tb_interview'; $marker='PASS_INTERVIEW:'; $sources+=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl\interview') -Filter '*.v' | ForEach-Object FullName)}
        'spi' {$top='tb_spi_checked'; $marker='PASS_SPI:'; $sources+=@(Join-Path $root 'vendor\spi\SPI_Master.v')}
    }
    $sources+=Join-Path $root ('sim\'+$top+'.sv')
    Push-Location -LiteralPath $run
    try {
        & (Join-Path $VivadoBin 'xvlog.bat') --sv @sources
        if($LASTEXITCODE -ne 0) {throw "Compile failed: $name"}
        & (Join-Path $VivadoBin 'xelab.bat') $top -s checked_sim -timescale 1ns/1ps
        if($LASTEXITCODE -ne 0) {throw "Elaboration failed: $name"}
        $batch=(Join-Path $PSScriptRoot 'run_all.tcl').Replace('\','/')
        & (Join-Path $VivadoBin 'xsim.bat') checked_sim -tclbatch $batch -log simulation.log
        if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath 'simulation.log' -SimpleMatch $marker -Quiet)) {
            throw "Simulation did not pass: $name; inspect $run\simulation.log"
        }
        if($name -eq 'image') {
            & $Python (Join-Path $root 'host\compare_jls.py') $run --ffmpeg $FFmpeg
            if($LASTEXITCODE -ne 0) {throw 'Independent decoded-pixel comparison failed'}
        }
        $records+=[pscustomobject]@{test=$name;passed=$true;run=$run}
        Write-Host "PASS $name -> $run"
    } finally {Pop-Location}
}
$records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root ('verification_'+$Test+'.json')) -Encoding utf8
