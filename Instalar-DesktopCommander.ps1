# Desktop Commander - menu de administracion local
# Version 2.0 - 2026-11-26. No contiene credenciales.
$ErrorActionPreference = 'Stop'
$Package = '@wonderwhy-er/desktop-commander'
$Dashboard = 'https://mcp.desktopcommander.app/'
# Solo nombres exactos reservados para la tarea de Desktop Commander.
$KnownTaskNames = @('DEscena - Desktop Commander Remote', 'Desktop Commander Remote', 'DesktopCommander Remote')

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
function Check-Node {
    if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'WinGet no disponible. Instala Node.js LTS desde nodejs.org.' }
        winget.exe install --id OpenJS.NodeJS.LTS -e
        if ($LASTEXITCODE -ne 0) { throw 'Error instalando Node.js.' }
        Refresh-Path
    }
    node.exe --version
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprobar Node.js.' }
}
function Get-InstalledPackage {
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { return $null }
    $raw = npm.cmd list -g --depth=0 --json
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar la instalacion global de NPM.' }
    $info = ($raw -join "`n") | ConvertFrom-Json
    if ($null -ne $info.dependencies) {
        $prop = $info.dependencies.PSObject.Properties[$Package]
        if ($null -ne $prop) { return $prop.Value }
    }
    return $null
}
function Install-DC {
    Check-Node
    npm.cmd install -g $Package
    if ($LASTEXITCODE -ne 0) { throw 'Error de instalacion de Desktop Commander.' }
    Refresh-Path
    $p = Get-InstalledPackage
    if ($null -eq $p) { throw 'La instalacion no se pudo verificar.' }
    Write-Host ('Desktop Commander instalado: ' + $p.version) -ForegroundColor Green
}
function Uninstall-DC {
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'NPM no disponible; no se puede verificar la desinstalacion.' }
    if ($null -eq (Get-InstalledPackage)) { Write-Host 'No hay instalacion global del paquete.'; return }
    npm.cmd uninstall -g $Package
    if ($LASTEXITCODE -ne 0) { throw 'Error de desinstalacion.' }
    if ($null -ne (Get-InstalledPackage)) { throw 'El paquete sigue instalado.' }
    Write-Host 'Paquete global desinstalado. Node.js se conserva.' -ForegroundColor Green
    Write-Host 'La revocacion de la cuenta (5) y la retirada de la tarea (8) son independientes. El cache de NPX no se modifica.'
}
function Get-DCCommand {
    $cmd = Get-Command desktop-commander.cmd -ErrorAction SilentlyContinue
    if (-not $cmd) { throw 'Desktop Commander no encontrado. Usa primero la opcion 2.' }
    return $cmd.Source
}
function Connect-DC {
    $cmd = Get-DCCommand
    Write-Host 'Se abre una consola visible. Autoriza el equipo mediante el flujo oficial, con conocimiento de sus usuarios.'
    Write-Host 'Comprueba el codigo de autenticacion y el dispositivo en el panel oficial. Cierra la consola para finalizar esa sesion.'
    Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /c ""' + $cmd + '" remote"')
}
function Disconnect-DC {
    $cmd = Get-DCCommand
    & $cmd remote --logout
    if ($LASTEXITCODE -ne 0) { throw "Cierre de sesion fallido. Revoca exclusivamente este equipo en $Dashboard" }
    Write-Host 'El comando oficial ha finalizado correctamente.' -ForegroundColor Green
    Write-Host "Comprueba la revocacion del equipo en $Dashboard. No se ha verificado independientemente el servidor."
}
function Get-DCTasks {
    Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -like '*Desktop Commander*' -or $_.TaskName -like '*DesktopCommander*' }
}
function Show-Status {
    Write-Host ('Equipo: ' + $env:COMPUTERNAME + ' | Usuario: ' + $env:USERNAME)
    if (Get-Command node.exe -ErrorAction SilentlyContinue) { Write-Host ('Node.js: ' + (node.exe --version)) } else { Write-Host 'Node.js: no detectado.' }
    if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
        try {
            $p = Get-InstalledPackage
            if ($null -ne $p) { Write-Host ('Desktop Commander global: ' + $p.version) } else { Write-Host 'Desktop Commander global: no instalado (no descarta NPX).' }
        } catch { Write-Warning $_.Exception.Message }
    } else { Write-Host 'Desktop Commander global: no verificado (NPM no disponible).' }
    try {
        $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe' OR Name = 'cmd.exe'" | Where-Object { $_.CommandLine -match '(?i)desktop[- ]?commander' -and $_.CommandLine -match '(?i)\bremote\b|desktop-commander-device' })
        if ($processes.Count) { Write-Host 'Procesos compatibles detectados:'; $processes | Select-Object ProcessId,Name,SessionId | Format-Table } else { Write-Host 'Proceso remoto: no detectado (no garantiza que este detenido).' }
    } catch { Write-Host 'Proceso remoto: no verificado.' }
    Write-Host "Vinculacion y conexion remota: no verificadas localmente. Consulta $Dashboard"
    try {
        $tasks = @(Get-DCTasks)
        if ($tasks.Count) {
            foreach ($t in $tasks) {
                $i = Get-ScheduledTaskInfo -InputObject $t -ErrorAction Stop
                [pscustomobject]@{ Tarea = $t.TaskName; Ruta = $t.TaskPath; Estado = $t.State; Usuario = $t.Principal.UserId; UltimaEjecucion = $i.LastRunTime; Resultado = $i.LastTaskResult }
            }
        } else { Write-Host 'Tarea programada: no detectada.' }
    } catch { Write-Host ('Tarea programada: no verificada. ' + $_.Exception.Message) }
}
function Remove-DCTask {
    $tasks = @(Get-DCTasks | Where-Object { $_.TaskName -in $KnownTaskNames })
    if ($tasks.Count -eq 0) { Write-Host 'No se ha encontrado una tarea con nombre exacto conocido. No se ha eliminado nada.'; return }
    if ($tasks.Count -ne 1) { Write-Host 'Hay varias coincidencias. No se elimina ninguna automaticamente.'; $tasks | Select-Object TaskName,TaskPath,State | Format-Table; return }
    $t = $tasks[0]
    # No eliminar una tarea ajena que reutilice el nombre: comprobar la accion.
    $actionText = ($t.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
    if ($actionText -notmatch '(?i)desktop[- ]?commander') { throw 'La accion de la tarea no identifica claramente Desktop Commander. No se elimina.' }
    Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
    $remaining = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -eq $t.TaskName -and $_.TaskPath -eq $t.TaskPath })
    if ($remaining.Count) { throw 'La tarea sigue registrada.' }
    Write-Host ('Tarea eliminada y verificada: ' + $t.TaskPath + $t.TaskName) -ForegroundColor Green
    Write-Host 'No se ha detenido ningun proceso ni desvinculado ninguna cuenta.'
}
do {
    Write-Host "`n=== DESKTOP COMMANDER 2.0 ==="
    Write-Host '1. Comprobar e instalar Node.js'
    Write-Host '2. Instalar Desktop Commander'
    Write-Host '3. Desinstalar Desktop Commander'
    Write-Host '4. Vincular la cuenta'
    Write-Host '5. Desvincular la cuenta'
    Write-Host '6. Comprobar el estado'
    Write-Host '7. Configurar la tarea programada (procedimiento local)'
    Write-Host '8. Desconfigurar la tarea programada'
    Write-Host '9. Salir'
    $choice = Read-Host 'Opcion'
    try {
        switch ($choice) {
            '1' { Check-Node }
            '2' { Install-DC }
            '3' { Uninstall-DC }
            '4' { Connect-DC }
            '5' { Disconnect-DC }
            '6' { Show-Status }
'7' {

    $taskName = 'DEscena - Desktop Commander Remote'

    $action = New-ScheduledTaskAction `
        -Execute 'npx.cmd' `
        -Argument '--yes "@wonderwhy-er/desktop-commander@latest" remote'

   $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description 'Inicia Desktop Commander Remote al arrancar Windows.' `
-User "$env:USERDOMAIN\$env:USERNAME" `
-RunLevel Limited ``
        -Force -ErrorAction Stop

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop

$task | Select-Object TaskName, State, TaskPath | Format-Table

Write-Host "Tarea creada y verificada correctamente: $taskName" -ForegroundColor Green
}

'8' {

    $taskName = 'DEscena - Desktop Commander Remote'

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($null -eq $task) {
        Write-Host 'La tarea no existe.'
    }
    else {

        Unregister-ScheduledTask `
            -TaskName $taskName `
            -Confirm:$false

        Start-Sleep -Seconds 1

        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            throw 'La tarea sigue existiendo después de intentar eliminarla.'
        }

        Write-Host "Tarea eliminada correctamente: $taskName" -ForegroundColor Green
    }
}
            '9' { break }
            default { Write-Host 'Opcion no valida.' }
        }
    } catch { Write-Warning $_.Exception.Message }
} while ($choice -ne '9')
