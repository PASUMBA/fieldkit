function Get-FieldKitProgressPath {
    $directory = $env:FIELDKIT_PROGRESS_DIR
    if ([string]::IsNullOrWhiteSpace($directory)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $directory = [IO.Path]::Combine($localAppData, 'FieldKit')
    }

    return [IO.Path]::Combine([IO.Path]::GetFullPath($directory), 'progress.json')
}

function Get-FieldKitSessions {
    $stream = $null
    $reader = $null
    try {
        $path = Get-FieldKitProgressPath
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $reader = [IO.StreamReader]::new($stream)
        $records = ConvertFrom-Json -InputObject $reader.ReadToEnd() -ErrorAction Stop
    }
    catch {
        return
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }

    foreach ($record in $records) {
        if ($record -isnot [pscustomobject] -or
            $record.Game -isnot [string] -or
            [string]::IsNullOrWhiteSpace($record.Game) -or
            $record.Completed -isnot [bool]) {
            continue
        }

        $level = $hits = $total = $durationSeconds = 0
        if (-not [int]::TryParse([string]$record.Level, [ref]$level) -or
            -not [int]::TryParse([string]$record.Hits, [ref]$hits) -or
            -not [int]::TryParse([string]$record.Total, [ref]$total) -or
            -not [int]::TryParse([string]$record.DurationSeconds, [ref]$durationSeconds) -or
            $level -lt 0 -or $hits -lt 0 -or $total -lt $hits -or $durationSeconds -lt 0) {
            continue
        }

        $date = [DateTimeOffset]::MinValue
        if ($record.Date -is [datetime]) {
            $date = [DateTimeOffset]::new($record.Date)
        }
        elseif (-not [DateTimeOffset]::TryParse([string]$record.Date, [ref]$date)) {
            continue
        }

        [pscustomobject][ordered]@{
            Game = $record.Game
            Level = $level
            Hits = $hits
            Total = $total
            DurationSeconds = $durationSeconds
            Completed = $record.Completed
            Date = $date.UtcDateTime.ToString('o')
        }
    }
}

function Save-FieldKitSession([string]$Game, [int]$Level, [int]$Hits, [int]$Total, [int]$DurationSeconds) {
    if ([string]::IsNullOrWhiteSpace($Game) -or $Level -lt 0 -or $Hits -lt 0 -or
        $Total -lt $Hits -or $DurationSeconds -lt 0) {
        throw 'The FieldKit session contains invalid progress values.'
    }

    $path = Get-FieldKitProgressPath
    $directory = [IO.Path]::GetDirectoryName($path)
    $mutex = [Threading.Mutex]::new($false, 'FieldKit.Progress')
    $locked = $false
    $temporaryPath = $null
    try {
        try {
            $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(3))
        }
        catch [Threading.AbandonedMutexException] {
            $locked = $true
        }
        if (-not $locked) {
            throw 'FieldKit could not save progress while another session was writing.'
        }

        $null = [IO.Directory]::CreateDirectory($directory)
        $sessions = @(Get-FieldKitSessions)
        $sessions += [pscustomobject][ordered]@{
            Game = $Game
            Level = $Level
            Hits = $Hits
            Total = $Total
            DurationSeconds = $DurationSeconds
            Completed = $Total -gt 0 -and $Hits -eq $Total
            Date = [DateTime]::UtcNow.ToString('o')
        }

        $temporaryPath = [IO.Path]::Combine($directory, [Guid]::NewGuid().ToString('N') + '.tmp')
        $json = ConvertTo-Json -InputObject $sessions -Depth 3
        [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($path)) {
            [IO.File]::Replace($temporaryPath, $path, [NullString]::Value)
        }
        else {
            [IO.File]::Move($temporaryPath, $path)
        }
    }
    finally {
        try {
            if ($null -ne $temporaryPath) { [IO.File]::Delete($temporaryPath) }
        }
        finally {
            if ($locked) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
}
