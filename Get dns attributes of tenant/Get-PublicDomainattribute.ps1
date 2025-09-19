$dnsdomain = "C:\Users\User\PSisFun-git-repos\Powershellisfun\Get dns attributes of tenant\sinqia-dns.csv"
$dnscsv = Test-Path -Path $dnsdomain
if ($dnscsv) {
    $dnsdata = Import-Csv -Path $dnsdomain
} else {
    $dnsdata = @()
}

$resultados = @()

foreach ($entry in $dnsdata) {
    Write-Host "Consultando CNAME para enterpriseenrollment.$($entry.Domain)..."
    $queryEE = nslookup.exe -type=cname enterpriseenrollment.$($entry.Domain) | Select-String "canonical name ="
    $cnameEE = if ($queryEE) { ($queryEE -split "=")[-1].Trim() } else { "Não encontrado" }

    Write-Host "Consultando CNAME para enterpriseregistration.$($entry.Domain)..."
    $queryER = nslookup.exe -type=cname enterpriseregistration.$($entry.Domain) | Select-String "canonical name ="
    $cnameER = if ($queryER) { ($queryER -split "=")[-1].Trim() } else { "Não encontrado" }

    $resultados += [PSCustomObject]@{
        Dominio         = $entry.Domain
        CNAME_Enrollment = $cnameEE
        CNAME_Registration = $cnameER
    }
}

$resultados | Format-Table -AutoSize