# LayoutArk scanner

`layoutark-scan.ps1` is an unsigned, auditable PowerShell 5.1/7 metadata scanner. Read it before running it.

```powershell
powershell -NoProfile -File .\scanner\layoutark-scan.ps1 `
  -Root "$env:USERPROFILE\Documents" `
  -JsonPath .\layoutark-manifest.json `
  -CsvPath .\layoutark-files.csv
```

The scanner recursively inventories `.pub` files, skips directory reparse points, and writes a v1 JSON manifest plus a flat CSV. It reads file-system metadata only: it does not open Publisher documents, use COM, export or convert files, or make network requests. Cloud placeholder state is inferred from Windows file attributes and does not hydrate files.

By default, occurrences of the current profile prefix in root paths and error samples become `%USERPROFILE%`. Use `-Redaction names` for stronger diagnostic path masking, or `-Redaction none` only when you explicitly want full paths. The manifest records missing/inaccessible roots and other failures in `scan.errors`; `scan.complete` is false when an error may make the inventory incomplete.

Run tests with Pester 5:

```powershell
Invoke-Pester .\scanner\tests
```
