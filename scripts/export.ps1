
$ErrorActionPreference = "Stop"

$container = "n8n"
$tempPath = "/tmp/n8n-export"

$outputPath = Join-Path $PSScriptRoot "..\workflows"
$stagingPath = Join-Path $PSScriptRoot ".export-temp"

# Limpa a exportação temporária dentro do container
docker exec $container sh -c "rm -rf $tempPath && mkdir -p $tempPath"

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao preparar a pasta temporária."
}

# Exporta todos os workflows
docker exec $container n8n export:workflow `
    --all `
    --separate `
    "--output=$tempPath"

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao exportar os workflows."
}

# Prepara as pastas locais
New-Item -ItemType Directory -Force -Path $stagingPath |
    Out-Null

New-Item -ItemType Directory -Force -Path $outputPath |
    Out-Null

# Limpa os arquivos temporários anteriores
Get-ChildItem $stagingPath -File |
    Remove-Item -Force

# Copia a exportação para uma pasta temporária local
docker cp "${container}:${tempPath}/." $stagingPath

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao copiar os arquivos exportados."
}

# Lê os workflows e exclui os arquivados da exportação local
$workflows = @(
    Get-ChildItem $stagingPath -Filter "*.json" -File |
    ForEach-Object {
        $workflow = Get-Content $_.FullName -Raw |
            ConvertFrom-Json

        # Não confundir workflow inativo com arquivado
        $isArchived = (
            $workflow.isArchived -eq $true -or
            $workflow.archived -eq $true
        )

        if (-not $isArchived) {
            [PSCustomObject]@{
                File = $_
                Workflow = $workflow
            }
        }
    }
)

# Evita deixar JSONs antigos na pasta versionada
Get-ChildItem $outputPath -Filter "*.json" -File |
    Remove-Item -Force

# Salva os workflows pelo nome original
$usedNames = @{}

foreach ($item in $workflows) {
    $workflow = $item.Workflow

    $name = $workflow.name -replace '[<>:"/\\|?*]', '_'
    $name = $name.Trim().TrimEnd('.')

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $workflow.id
    }

    $fileName = "$name.json"

    if ($usedNames.ContainsKey($fileName)) {
        $fileName = "$name-$($workflow.id).json"
    }

    $usedNames[$fileName] = $true

    $destination = Join-Path $outputPath $fileName

    Copy-Item $item.File.FullName $destination
}

Write-Host ""
Write-Host "Exportação concluída."
Write-Host "Workflows exportados: $($workflows.Count)"
Write-Host "Destino: $outputPath"

Remove-Item $stagingPath -Recurse -Force

Write-Host "Arquivos temporários removidos."