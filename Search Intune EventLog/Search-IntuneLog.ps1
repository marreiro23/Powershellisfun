  #-Requires RunAsAdministrator
function Search-IntuneLog {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Nome do computador remoto")][string]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory = $false, HelpMessage = "Número de horas para buscar")][double]$Hours = 1,
        [Parameter(Mandatory = $false, HelpMessage = "String para buscar no conteúdo")][string]$Filter,
        [Parameter(Mandatory = $false, HelpMessage = "Caminho de saída, ex: c:\data\intune_logs.csv", parameterSetName = "CSV")][string]$OutCSV,
        [Parameter(Mandatory = $false, HelpMessage = "Exclui arquivos de log específicos")][string[]]$ExcludeLog,
        [Parameter(Mandatory = $false, HelpMessage = "Exibe resultados em GridView", parameterSetName = "GridView")][switch]$Gridview
    )

    $LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
    $since = (Get-Date).AddHours(-$Hours)

    # Lista arquivos de log, excluindo os especificados
    $logs = Get-ChildItem -Path $LogPath -File | Where-Object {
        $_.LastWriteTime -ge $since -and ($ExcludeLog -eq $null -or $_.Name -notin $ExcludeLog)
    }

    $results = @()
    foreach ($log in $logs) {
        Write-Host ("Analisando arquivo: {0}" -f $log.FullName) -ForegroundColor Green
        try {
            $lines = Get-Content $log.FullName -ErrorAction Stop
            foreach ($line in $lines) {
                if (-not $Filter -or $line -match $Filter) {
                    $results += [PSCustomObject]@{
                        Time         = $log.LastWriteTime.ToString('dd-MM-yyyy HH:mm')
                        Computer     = $ComputerName
                        LogFile      = $log.Name
                        Line         = $line
                    }
                }
            }
        } catch {
            Write-Warning ("Erro ao ler {0}, pulando..." -f $log.FullName)
        }
    }

    if ($Gridview -and $results) {
        $results | Sort-Object Time, LogFile | Out-GridView -Title 'Linhas encontradas nos logs do Intune'
        return
    }

    if ($OutCSV -and $results) {
        try {
            $results | Sort-Object Time, LogFile | Export-Csv -NoTypeInformation -Delimiter ';' -Encoding UTF8 -Path $OutCSV -ErrorAction Stop
            Write-Host ("Exportado para {0}" -f $OutCSV) -ForegroundColor Green
        } catch {
            Write-Warning ("Erro ao exportar para {0}, verifique o caminho ou permissões." -f $OutCSV)
        }
        return
    }

    if (-not $OutCSV -and -not $Gridview -and $results) {
        return $results | Sort-Object Time, LogFile
    }

    if (-not $results) {
        Write-Warning ("Nenhum resultado encontrado nos logs do Intune...")
    }
}
