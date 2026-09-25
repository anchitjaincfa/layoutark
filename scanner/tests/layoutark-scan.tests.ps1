Describe 'layoutark-scan' {
    BeforeAll {
        $scanner = Join-Path (Split-Path -Parent $PSScriptRoot) 'layoutark-scan.ps1'
    }

    BeforeEach {
        $case = Join-Path $TestDrive 'estate'
        New-Item -ItemType Directory -Path (Join-Path $case 'Nested') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $case 'Alpha.pub'), 'content is never parsed')
        [IO.File]::WriteAllText((Join-Path $case 'Nested\BETA.PUB'), 'other bytes')
        [IO.File]::WriteAllText((Join-Path $case 'ignore.txt'), 'not a publisher file')
        $json = Join-Path $TestDrive 'result.json'
        $csv = Join-Path $TestDrive 'result.csv'
    }

    It 'writes a contract-shaped manifest and inventories .pub case-insensitively' {
        & $scanner -Root $case -JsonPath $json -CsvPath $csv -HostLabel 'TEST-HOST' | Out-Null
        $manifest = Get-Content -Raw $json | ConvertFrom-Json
        $manifest.schema | Should -Be 'layoutark.manifest'
        $manifest.version | Should -Be 1
        $manifest.generator.name | Should -Be 'layoutark-scan'
        $manifest.host.publisher.via | Should -Be 'not-probed'
        $manifest.scan.complete | Should -BeTrue
        $manifest.scan.fileCount | Should -Be 2
        @($manifest.files.name) | Should -Contain 'Alpha.pub'
        @($manifest.files.name) | Should -Contain 'BETA.PUB'
        @($manifest.files.name) | Should -Not -Contain 'ignore.txt'
    }

    It 'emits UTF-8 without a BOM and a CSV with the same rows' {
        & $scanner -Root $case -JsonPath $json -CsvPath $csv | Out-Null
        $jsonBytes = [IO.File]::ReadAllBytes($json)
        ($jsonBytes.Length -gt 3) | Should -BeTrue
        (($jsonBytes[0] -eq 0xEF) -and ($jsonBytes[1] -eq 0xBB) -and ($jsonBytes[2] -eq 0xBF)) | Should -BeFalse
        @(Import-Csv $csv).Count | Should -Be 2
    }

    It 'does not open Publisher files to inspect their contents' {
        $locked = Join-Path $case 'Locked.pub'
        [IO.File]::WriteAllText($locked, 'locked')
        $stream = [IO.File]::Open($locked, 'Open', 'ReadWrite', 'None')
        try {
            & $scanner -Root $case -JsonPath $json -CsvPath $csv | Out-Null
            (Get-Content -Raw $json | ConvertFrom-Json).scan.fileCount | Should -Be 3
        }
        finally { $stream.Dispose() }
    }

    It 'aggregates missing roots without aborting valid roots' {
        $missing = Join-Path $TestDrive 'absent'
        & $scanner -Root @($case, $missing) -JsonPath $json -CsvPath $csv | Out-Null
        $manifest = Get-Content -Raw $json | ConvertFrom-Json
        $manifest.scan.complete | Should -BeFalse
        ($manifest.scan.errors | Where-Object kind -eq 'missing-root').count | Should -Be 1
        $manifest.scan.fileCount | Should -Be 2
    }

    It 'redacts the profile prefix when it appears in diagnostics' {
        $profileMissing = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'layoutark-definitely-missing'
        & $scanner -Root $profileMissing -JsonPath $json -CsvPath $csv -Redaction profile | Out-Null
        $sample = (Get-Content -Raw $json | ConvertFrom-Json).scan.errors[0].samples[0]
        $sample | Should -Match '^%USERPROFILE%'
        $sample | Should -Not -Match ([regex]::Escape([Environment]::GetFolderPath('UserProfile')))
    }
}
