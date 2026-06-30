param(
  [string]$EventPath = $env:GITHUB_EVENT_PATH,
  [string]$EventName = $env:GITHUB_EVENT_NAME,
  [string]$PolicyPath = '.github/no_ai_contributor_policy.json',
  [switch]$FixDocs,
  [switch]$FullScan,
  [switch]$WorkingTree
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path '.').Path
$policyFile = Join-Path $repoRoot $PolicyPath
if (-not (Test-Path $policyFile -PathType Leaf)) {
  throw "No-AI contributor policy file was not found at '$policyFile'."
}

$policy = Get-Content -Raw $policyFile | ConvertFrom-Json -Depth 16
$blockedTerms = @($policy.blockedTerms)
$docSectionHeaders = @($policy.docSectionHeaders | ForEach-Object { $_.ToString().Trim().ToLowerInvariant() })
$docExtensions = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
@($policy.docExtensions) | ForEach-Object { [void]$docExtensions.Add($_.ToString()) }
$assetExtensions = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
@($policy.assetExtensions) | ForEach-Object { [void]$assetExtensions.Add($_.ToString()) }
$excludedPrefixes = @($policy.excludedPathPrefixes | ForEach-Object { $_.ToString().Replace('\', '/').TrimStart('./') })
$violations = New-Object 'System.Collections.Generic.List[string]'
$sanitizedDocs = New-Object 'System.Collections.Generic.List[string]'

if ($blockedTerms.Count -eq 0) {
  throw 'The no-AI contributor policy does not define any blocked terms.'
}

$blockedContributorPattern = '(?i)(chatgpt|codex|openai|claude|anthropic|gemini|copilot|\bgpt(?:-\d+(?:\.\d+)*)?\b|\bllm\b|artificial intelligence|\bai assistant\b)'
$assetMetadataPattern = '(?i)(' + ((@($policy.assetMetadataTerms) | ForEach-Object { [regex]::Escape($_.ToString()) }) -join '|') + ')'

function Normalize-RepoPath {
  param([string]$Path)
  if (-not $Path) {
    return $null
  }

  return $Path.Replace('\', '/').Trim()
}

function Get-NormalizedHeader {
  param([string]$HeaderText)

  if (-not $HeaderText) {
    return ''
  }

  $normalized = $HeaderText.Trim().ToLowerInvariant()
  $normalized = $normalized -replace '[#`*_]+', ''
  $normalized = $normalized -replace '\s+', ' '
  return $normalized.Trim()
}

function Should-ExcludePath {
  param([string]$RepoPath)

  $normalized = Normalize-RepoPath $RepoPath
  if (-not $normalized) {
    return $true
  }

  foreach ($prefix in $script:excludedPrefixes) {
    if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return $false
}

function Is-DocFile {
  param([string]$RepoPath)

  if (Should-ExcludePath $RepoPath) {
    return $false
  }

  $extension = [System.IO.Path]::GetExtension($RepoPath)
  return $script:docExtensions.Contains($extension)
}

function Is-AssetFile {
  param([string]$RepoPath)

  if (Should-ExcludePath $RepoPath) {
    return $false
  }

  $extension = [System.IO.Path]::GetExtension($RepoPath)
  return $script:assetExtensions.Contains($extension)
}

function Get-CommitContext {
  param(
    [string]$Path,
    [string]$Name
  )

  $revisionRange = $null
  $commitRefs = @()

  if ($Path -and (Test-Path $Path -PathType Leaf)) {
    $event = Get-Content -Raw $Path | ConvertFrom-Json -Depth 32

    switch ($Name) {
      'pull_request' {
        $base = $event.pull_request.base.sha
        $head = $event.pull_request.head.sha
        if ($base -and $head) {
          $revisionRange = "$base..$head"
        }
      }
      'push' {
        $base = $event.before
        $head = $event.after
        if ($base -and $head -and $base -notmatch '^0+$') {
          $revisionRange = "$base..$head"
        } elseif ($head) {
          $commitRefs = @($head)
        }
      }
      default {
        $sha = $event.after
        if ($sha) {
          $commitRefs = @($sha)
        }
      }
    }
  }

  if ($revisionRange) {
    $commitRefs = @((git rev-list $revisionRange) | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)
  } elseif ($commitRefs.Count -eq 0 -and -not $WorkingTree) {
    git rev-parse --verify HEAD *> $null
    if ($LASTEXITCODE -eq 0) {
      $commitRefs = @((git rev-parse HEAD).Trim())
    }
  }

  [pscustomobject]@{
    RevisionRange = $revisionRange
    CommitRefs     = @($commitRefs)
  }
}

function Get-WorkingTreeFiles {
  $files = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($line in (git status --short)) {
    if (-not $line -or $line.Length -lt 4) {
      continue
    }

    $status = $line.Substring(0, 2)
    $pathPart = $line.Substring(3).Trim()
    if (-not $pathPart) {
      continue
    }

    if ($pathPart -match ' -> ') {
      $pathPart = ($pathPart -split ' -> ')[-1]
    }

    if ($status.Contains('D')) {
      continue
    }

    [void]$files.Add((Normalize-RepoPath $pathPart))
  }

  return @($files)
}

function Get-ChangedFiles {
  param([pscustomobject]$Context)

  $files = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

  if ($FullScan) {
    foreach ($line in (git ls-files)) {
      if ($line) {
        [void]$files.Add((Normalize-RepoPath $line))
      }
    }
    return @($files)
  }

  if ($WorkingTree) {
    foreach ($path in (Get-WorkingTreeFiles)) {
      [void]$files.Add((Normalize-RepoPath $path))
    }
    return @($files)
  }

  if ($Context.RevisionRange) {
    foreach ($line in (git diff --name-only --diff-filter=ACMR $Context.RevisionRange)) {
      if ($line) {
        [void]$files.Add((Normalize-RepoPath $line))
      }
    }
    return @($files)
  }

  foreach ($commitRef in $Context.CommitRefs) {
    foreach ($line in (git show --pretty='' --name-only --diff-filter=ACMR $commitRef)) {
      if ($line) {
        [void]$files.Add((Normalize-RepoPath $line))
      }
    }
  }

  return @($files)
}

function Test-Identity {
  param(
    [string]$CommitRef,
    [string]$Role,
    [string]$Name,
    [string]$Email
  )

  $identity = "$Name <$Email>"
  if ($identity -match $script:blockedContributorPattern) {
    $script:violations.Add("Commit $CommitRef contains blocked $Role identity '$identity'.")
  }
}

function Test-LineIsAutoRemovable {
  param(
    [string]$Line,
    [string]$CurrentHeader
  )

  if (-not $Line -or $Line -notmatch $script:blockedContributorPattern) {
    return $false
  }

  $trimmed = $Line.Trim()
  if (-not $trimmed -or $trimmed.StartsWith('#')) {
    return $false
  }

  if ($trimmed -match '^\s*```') {
    return $false
  }

  if ($trimmed -match '^\s*\*\*(?:tools?|tooling|contributors?|credits?|acknowledg(?:e)?ments?|review(?:ed)? by|authored by|generated with)\*\*\s*:\s*.+$') {
    return $true
  }

  if ($trimmed -match '^\s*(?:tools?|tooling|contributors?|credits?|acknowledg(?:e)?ments?|review(?:ed)? by|authored by|generated with)\s*[:|-]\s*.+$') {
    return $true
  }

  if (-not $script:docSectionHeaders.Contains($CurrentHeader)) {
    return $false
  }

  if ($trimmed -match '^\s*(?:[-*+]|\d+\.)\s*.+$') {
    return $true
  }

  if ($trimmed -match '^\s*\|.+\|$') {
    return $true
  }

  if ($trimmed -match '^\s*[A-Za-z][A-Za-z /_-]{0,32}\s*:\s*.+$') {
    return $true
  }

  if ($trimmed -notmatch '[.!?]$') {
    return $true
  }

  return $false
}

function Inspect-DocFile {
  param([string]$RepoPath)

  $fullPath = Join-Path $script:repoRoot $RepoPath
  if (-not (Test-Path $fullPath -PathType Leaf)) {
    return
  }

  $lines = [System.IO.File]::ReadAllLines($fullPath)
  $output = New-Object 'System.Collections.Generic.List[string]'
  $changed = $false
  $insideCodeFence = $false
  $currentHeader = ''

  for ($index = 0; $index -lt $lines.Length; $index++) {
    $line = $lines[$index]
    $lineNumber = $index + 1

    if ($line -match '^\s*```') {
      $insideCodeFence = -not $insideCodeFence
      $output.Add($line)
      continue
    }

    if (-not $insideCodeFence -and $line -match '^\s{0,3}#{1,6}\s+(.+?)\s*$') {
      $currentHeader = Get-NormalizedHeader $Matches[1]
      $output.Add($line)
      continue
    }

    if ($insideCodeFence -or $line -notmatch $script:blockedContributorPattern) {
      $output.Add($line)
      continue
    }

    if ($FixDocs -and (Test-LineIsAutoRemovable -Line $line -CurrentHeader $currentHeader)) {
      $changed = $true
      $script:sanitizedDocs.Add("${RepoPath}:$lineNumber")
      continue
    }

    if (Test-LineIsAutoRemovable -Line $line -CurrentHeader $currentHeader) {
      $script:violations.Add("Documentation file '$RepoPath' contains blocked AI contributor attribution at line $lineNumber.")
    }

    $output.Add($line)
  }

  if ($changed) {
    [System.IO.File]::WriteAllLines($fullPath, $output)
  }
}

function Inspect-AssetFile {
  param([string]$RepoPath)

  $fullPath = Join-Path $script:repoRoot $RepoPath
  if (-not (Test-Path $fullPath -PathType Leaf)) {
    return
  }

  $fileName = [System.IO.Path]::GetFileName($RepoPath)
  if ($fileName -match $script:blockedContributorPattern) {
    $script:violations.Add("Asset '$RepoPath' uses a blocked AI contributor term in its filename '$fileName'.")
    return
  }

  $bytes = [System.IO.File]::ReadAllBytes($fullPath)
  $content = [System.Text.Encoding]::ASCII.GetString($bytes)
  if ($content -match $script:assetMetadataPattern) {
    $script:violations.Add("Asset '$RepoPath' contains blocked AI provenance or generator metadata.")
  }
}

$commitContext = Get-CommitContext -Path $EventPath -Name $EventName
$changedFiles = Get-ChangedFiles -Context $commitContext

foreach ($commitRef in $commitContext.CommitRefs) {
  $authorName = (git show -s --format='%an' $commitRef).Trim()
  $authorEmail = (git show -s --format='%ae' $commitRef).Trim()
  $committerName = (git show -s --format='%cn' $commitRef).Trim()
  $committerEmail = (git show -s --format='%ce' $commitRef).Trim()
  $message = git show -s --format=%B $commitRef

  Test-Identity -CommitRef $commitRef -Role 'author' -Name $authorName -Email $authorEmail
  Test-Identity -CommitRef $commitRef -Role 'committer' -Name $committerName -Email $committerEmail

  $coAuthorMatches = [regex]::Matches($message, '(?im)^co-authored-by:\s*(.+?)\s*<([^>]+)>\s*$')
  foreach ($match in $coAuthorMatches) {
    Test-Identity `
      -CommitRef $commitRef `
      -Role 'co-author' `
      -Name $match.Groups[1].Value.Trim() `
      -Email $match.Groups[2].Value.Trim()
  }
}

foreach ($repoPath in $changedFiles) {
  if (Is-DocFile $repoPath) {
    Inspect-DocFile -RepoPath $repoPath
    continue
  }

  if (Is-AssetFile $repoPath) {
    Inspect-AssetFile -RepoPath $repoPath
  }
}

if ($sanitizedDocs.Count -gt 0) {
  Write-Host 'Removed blocked AI contributor references from these doc lines:' -ForegroundColor Yellow
  $sanitizedDocs | Sort-Object -Unique | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
}

if ($violations.Count -gt 0) {
  Write-Host 'No-AI contributor policy violations found:' -ForegroundColor Red
  $violations | Sort-Object -Unique | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
  exit 1
}

Write-Host 'No-AI contributor checks passed for the evaluated commit and file set.' -ForegroundColor Green
