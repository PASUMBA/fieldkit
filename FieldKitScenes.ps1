$script:fieldKitMeshes = @{}
$script:fieldKitMaterials = @{}

function Add-FieldKitTriangle($Mesh, [int]$A, [int]$B, [int]$C) {
    $Mesh.TriangleIndices.Add($A)
    $Mesh.TriangleIndices.Add($B)
    $Mesh.TriangleIndices.Add($C)
}

function Get-FieldKitMesh([string]$Shape) {
    if ($script:fieldKitMeshes.ContainsKey($Shape)) {
        return $script:fieldKitMeshes[$Shape]
    }

    $mesh = [Windows.Media.Media3D.MeshGeometry3D]::new()
    switch ($Shape) {
        'Block' {
            foreach ($z in -1, 1) {
                foreach ($corner in @(@(-1, -1), @(1, -1), @(1, 1), @(-1, 1))) {
                    $mesh.Positions.Add([Windows.Media.Media3D.Point3D]::new($corner[0], $corner[1], $z))
                }
            }
            foreach ($face in @(@(0, 3, 2, 1), @(4, 5, 6, 7), @(0, 1, 5, 4),
                    @(3, 7, 6, 2), @(0, 4, 7, 3), @(1, 2, 6, 5))) {
                Add-FieldKitTriangle $mesh $face[0] $face[1] $face[2]
                Add-FieldKitTriangle $mesh $face[0] $face[2] $face[3]
            }
        }
        'Ring' {
            $segments = 48
            for ($i = 0; $i -le $segments; $i++) {
                $angle = 2 * [Math]::PI * $i / $segments
                foreach ($radius in 0.83, 1.0) {
                    $mesh.Positions.Add([Windows.Media.Media3D.Point3D]::new(
                        $radius * [Math]::Cos($angle), 0, $radius * [Math]::Sin($angle)))
                }
                if ($i -lt $segments) {
                    $a = 2 * $i
                    Add-FieldKitTriangle $mesh $a ($a + 2) ($a + 1)
                    Add-FieldKitTriangle $mesh ($a + 1) ($a + 2) ($a + 3)
                }
            }
        }
        default {
            $faceted = $Shape -eq 'Rock'
            $sides = if ($faceted) { 8 } else { 16 }
            $layers = if ($faceted) { 5 } else { 10 }
            for ($row = 0; $row -le $layers; $row++) {
                $polar = [Math]::PI * $row / $layers
                for ($column = 0; $column -le $sides; $column++) {
                    $azimuth = 2 * [Math]::PI * $column / $sides
                    $radius = 1.0
                    if ($faceted -and $row -gt 0 -and $row -lt $layers) {
                        $radius += 0.16 * [Math]::Sin(2.1 * $row + 3 * $azimuth)
                    }
                    $mesh.Positions.Add([Windows.Media.Media3D.Point3D]::new(
                        $radius * [Math]::Sin($polar) * [Math]::Cos($azimuth),
                        $radius * [Math]::Cos($polar),
                        $radius * [Math]::Sin($polar) * [Math]::Sin($azimuth)))
                    if ($row -lt $layers -and $column -lt $sides) {
                        $a = $row * ($sides + 1) + $column
                        $b = $a + $sides + 1
                        Add-FieldKitTriangle $mesh $a ($a + 1) $b
                        Add-FieldKitTriangle $mesh ($a + 1) ($b + 1) $b
                    }
                }
            }
        }
    }

    $mesh.Freeze()
    $script:fieldKitMeshes[$Shape] = $mesh
    return $mesh
}

function Add-FieldKitShape($Parent, [string]$Shape, [string]$Color,
    [double]$X, [double]$Y, [double]$Z, [double]$Width, [double]$Height, [double]$Depth,
    [double]$Roll = 0, [double]$Pitch = 0, [switch]$Glow) {
    $materialKey = $Color + [string]$Glow.IsPresent
    if (-not $script:fieldKitMaterials.ContainsKey($materialKey)) {
        $brush = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($Color))
        $material = if ($Glow) { [Windows.Media.Media3D.EmissiveMaterial]::new($brush) }
                    else { [Windows.Media.Media3D.DiffuseMaterial]::new($brush) }
        $material.Freeze()
        $script:fieldKitMaterials[$materialKey] = $material
    }

    $model = [Windows.Media.Media3D.GeometryModel3D]::new(
        (Get-FieldKitMesh $Shape), $script:fieldKitMaterials[$materialKey])
    $model.BackMaterial = $model.Material
    $transforms = [Windows.Media.Media3D.Transform3DGroup]::new()
    $transforms.Children.Add([Windows.Media.Media3D.ScaleTransform3D]::new($Width, $Height, $Depth))
    if ($Pitch -ne 0) {
        $pitchAxis = [Windows.Media.Media3D.Vector3D]::new(1, 0, 0)
        $transforms.Children.Add([Windows.Media.Media3D.RotateTransform3D]::new(
            [Windows.Media.Media3D.AxisAngleRotation3D]::new($pitchAxis, $Pitch)))
    }
    if ($Roll -ne 0) {
        $rollAxis = [Windows.Media.Media3D.Vector3D]::new(0, 0, 1)
        $transforms.Children.Add([Windows.Media.Media3D.RotateTransform3D]::new(
            [Windows.Media.Media3D.AxisAngleRotation3D]::new($rollAxis, $Roll)))
    }
    $transforms.Children.Add([Windows.Media.Media3D.TranslateTransform3D]::new($X, $Y, $Z))
    $model.Transform = $transforms
    $model.Freeze()
    $Parent.Children.Add($model)
}

function Add-FieldKitPalm($Parent, [double]$X, [double]$Y, [double]$Z, [double]$Size) {
    Add-FieldKitShape $Parent Rock '#B88B54' $X ($Y + 0.44 * $Size) $Z (0.07 * $Size) (0.53 * $Size) (0.07 * $Size) -9
    $topX = $X + 0.07 * $Size
    $topY = $Y + 0.92 * $Size
    foreach ($direction in -1, 1) {
        Add-FieldKitShape $Parent Rock '#5B9C5A' ($topX + $direction * 0.23 * $Size) ($topY + 0.12 * $Size) $Z (0.31 * $Size) (0.07 * $Size) (0.13 * $Size) ($direction * 16)
        Add-FieldKitShape $Parent Rock '#2E784A' ($topX + $direction * 0.25 * $Size) ($topY - 0.02 * $Size) ($Z + 0.08 * $Size) (0.32 * $Size) (0.06 * $Size) (0.11 * $Size) ($direction * -19)
    }
    Add-FieldKitShape $Parent Rock '#96BC60' $topX ($topY + 0.12 * $Size) $Z (0.24 * $Size) (0.06 * $Size) (0.19 * $Size) 70
}

function Add-FieldKitLantern($Parent, [double]$X, [double]$Y, [double]$Z, [double]$Size, [double]$Roll) {
    Add-FieldKitShape $Parent Orb '#F58738' $X $Y $Z (0.21 * $Size) (0.30 * $Size) (0.17 * $Size) $Roll
    Add-FieldKitShape $Parent Orb '#FFB366' $X ($Y - 0.015 * $Size) ($Z + 0.11 * $Size) (0.16 * $Size) (0.23 * $Size) (0.09 * $Size) $Roll -Glow
    Add-FieldKitShape $Parent Block '#67333D' $X ($Y + 0.26 * $Size) $Z (0.19 * $Size) (0.035 * $Size) (0.15 * $Size) $Roll
    Add-FieldKitShape $Parent Block '#663143' $X ($Y - 0.25 * $Size) $Z (0.16 * $Size) (0.05 * $Size) (0.14 * $Size) $Roll
    Add-FieldKitShape $Parent Rock '#D77055' $X ($Y - 0.39 * $Size) $Z (0.021 * $Size) (0.13 * $Size) (0.015 * $Size) $Roll
}

function New-FieldKitScene([string]$Mode) {
    $viewport = [Windows.Controls.Viewport3D]::new()
    $viewport.IsHitTestVisible = $false
    $viewport.ClipToBounds = $true
    $viewport.Camera = [Windows.Media.Media3D.PerspectiveCamera]::new(
        [Windows.Media.Media3D.Point3D]::new(0, 1.9, 9.6),
        [Windows.Media.Media3D.Vector3D]::new(0, -1.45, -9.6),
        [Windows.Media.Media3D.Vector3D]::new(0, 1, 0), 46)

    $world = [Windows.Media.Media3D.Model3DGroup]::new()
    $world.Children.Add([Windows.Media.Media3D.AmbientLight]::new(
        [Windows.Media.Color]::FromRgb(115, 120, 132)))
    $world.Children.Add([Windows.Media.Media3D.DirectionalLight]::new(
        [Windows.Media.Color]::FromRgb(223, 218, 202), [Windows.Media.Media3D.Vector3D]::new(2, -3, -2)))
    $world.Children.Add([Windows.Media.Media3D.DirectionalLight]::new(
        [Windows.Media.Color]::FromRgb(81, 103, 160), [Windows.Media.Media3D.Vector3D]::new(-3, 0, 1)))

    $landscape = [Windows.Media.Media3D.Model3DGroup]::new()
    $world.Children.Add($landscape)
    $accents = [Windows.Media.Media3D.Model3DGroup]::new()
    $landscape.Children.Add($accents)
    $parallax = [Windows.Media.Media3D.TranslateTransform3D]::new()
    $landscape.Transform = $parallax
    $drift = [Windows.Media.Media3D.TranslateTransform3D]::new()
    $accents.Transform = $drift

    switch -Wildcard ($Mode) {
        '*Ferry*' {
            Add-FieldKitShape $landscape Block '#0F5555' 0 -1.29 -0.8 8 0.025 6
            for ($index = 0; $index -lt 15; $index++) {
                $x = -4.5 + (($index * 59) % 100) * 0.09
                $z = -4.2 + (($index * 29) % 100) * 0.07
                Add-FieldKitShape $accents Orb '#237C7B' $x -1.22 $z (0.26 + 0.04 * ($index % 5)) 0.012 0.07
            }
            Add-FieldKitShape $landscape Rock '#315E51' -2.98 -1.24 -2.8 2.13 0.38 0.91
            Add-FieldKitShape $landscape Rock '#398169' 3.7 -1.15 -3.3 2.5 0.38 0.77
            Add-FieldKitShape $landscape Rock '#81AE88' 0.7 -1.23 -6 3.7 0.25 0.3
            Add-FieldKitPalm $landscape -3.68 -0.95 -2.7 1.45
            Add-FieldKitPalm $landscape -2.87 -0.92 -2.7 1.07
            Add-FieldKitPalm $landscape 3.25 -0.88 -3.4 1.38
            Add-FieldKitPalm $landscape 4.21 -0.91 -4.0 1.13
            Add-FieldKitShape $landscape Block '#D0AB69' 2.3 -0.61 -2.8 0.44 0.26 0.26
            Add-FieldKitShape $landscape Rock '#A65342' 2.3 -0.32 -2.8 0.61 0.21 0.33
            Add-FieldKitShape $landscape Block '#584C55' 2.2 -0.66 -2.525 0.085 0.12 0.018
            Add-FieldKitShape $landscape Orb '#E7C47E' 3.55 1.91 -5 0.41 0.41 0.35
        }
        '*Lantern*' {
            Add-FieldKitShape $landscape Orb '#EEB882' 2.56 1.49 -4.4 0.69 0.69 0.62
            Add-FieldKitShape $landscape Rock '#693958' -3.1 -0.61 -4.0 2.55 0.85 0.48 12
            Add-FieldKitShape $landscape Rock '#503658' 3.19 -0.87 -3.88 2.4 0.75 0.45 -14
            Add-FieldKitShape $landscape Block '#6A3D53' -2.92 -0.89 -2.3 0.66 0.35 0.37
            Add-FieldKitShape $landscape Block '#A25761' -2.92 -0.50 -2.3 0.88 0.055 0.47
            Add-FieldKitShape $landscape Block '#8D4D5A' -2.92 -0.36 -2.3 0.65 0.055 0.38
            Add-FieldKitShape $landscape Block '#544052' -2.92 -0.85 -1.89 0.14 0.22 0.02
            Add-FieldKitShape $landscape Rock '#B27072' 2.75 -0.98 -2.3 1.11 0.24 0.50
            Add-FieldKitLantern $accents -3.52 1.43 -2.7 0.97 -8
            Add-FieldKitLantern $accents -2.52 0.66 -1.8 0.68 7
            Add-FieldKitLantern $accents -1.54 1.84 -4.1 0.48 -3
            Add-FieldKitLantern $accents 3.73 0.69 -2.4 0.82 -10
            Add-FieldKitLantern $accents 2.98 1.96 -3.3 0.46 8
            Add-FieldKitLantern $accents 3.06 -0.18 -1.9 0.64 7
        }
        '*Reef*' {
            Add-FieldKitShape $landscape Rock '#224E68' 0 -1.45 -2.1 7.2 0.30 2.0
            Add-FieldKitShape $landscape Rock '#2A7690' -3.08 -1.33 -1.3 1.65 0.52 1.18
            Add-FieldKitShape $landscape Rock '#437791' 3.16 -1.25 -1.8 1.78 0.57 1.09 9
            foreach ($side in -1, 1) {
                $x = $side * 3.11
                $color = if ($side -eq -1) { '#EA7D76' } else { '#AE81CF' }
                Add-FieldKitShape $landscape Rock $color $x -0.47 -1.04 0.14 0.71 0.13 ($side * -8)
                Add-FieldKitShape $landscape Rock $color ($x + 0.25) -0.57 -0.96 0.09 0.51 0.08 -29
                Add-FieldKitShape $landscape Rock $color ($x - 0.23) -0.61 -0.93 0.08 0.43 0.08 34
                Add-FieldKitShape $landscape Rock '#4EC0A1' ($x + $side * 0.65) -0.76 -0.89 0.08 0.46 0.11 ($side * 20)
                Add-FieldKitShape $landscape Rock '#57AB8E' ($x + $side * 0.88) -0.78 -1.07 0.10 0.35 0.11 ($side * -27)
            }
            for ($index = 0; $index -lt 11; $index++) {
                $side = if ($index % 2) { -1 } else { 1 }
                $x = $side * (2.2 + (($index * 47) % 13) * 0.15)
                $y = -0.25 + (($index * 11) % 17) * 0.12
                $size = 0.032 + 0.013 * ($index % 4)
                Add-FieldKitShape $accents Orb '#84D5D8' $x $y -3.45 $size $size $size
            }
            Add-FieldKitShape $accents Rock '#DDB86A' -2.34 1.2 -3.1 0.31 0.09 0.09 -8
            Add-FieldKitShape $accents Rock '#E5A971' -2.67 1.24 -3.12 0.13 0.13 0.06 30
            Add-FieldKitShape $accents Rock '#70AEE1' -1.72 1.5 -4 0.21 0.075 0.07 -5
            Add-FieldKitShape $accents Rock '#71C2DA' -1.95 1.52 -4.01 0.09 0.11 0.05 24
        }
        default {
            Add-FieldKitShape $landscape Orb '#825A93' -2.74 0.98 -2.7 0.83 0.83 0.83
            Add-FieldKitShape $landscape Ring '#CA9FBD' -2.74 0.98 -2.7 1.32 1 1.32 -20 33
            Add-FieldKitShape $landscape Ring '#A977A6' -2.74 0.98 -2.7 1.65 1 1.65 -20 33
            Add-FieldKitShape $landscape Orb '#E69A79' 3.89 1.47 -5.2 0.51 0.51 0.51
            Add-FieldKitShape $accents Rock '#5475A3' 3.31 -0.55 -3.3 0.55 0.33 0.41 32 20
            Add-FieldKitShape $accents Rock '#78648F' -3.5 -0.81 -2.4 0.38 0.27 0.39 -34 18
            Add-FieldKitShape $accents Rock '#8C718A' 2.44 -1.09 -2.1 0.25 0.19 0.18 40
            for ($index = 0; $index -lt 24; $index++) {
                $x = -5.55 + (($index * 71) % 100) * 0.112
                $y = -1.33 + (($index * 53) % 100) * 0.035
                $tiny = 0.022 + ($index % 5) * 0.007
                Add-FieldKitShape $landscape Rock '#88ACCF' $x $y -5.5 $tiny $tiny $tiny -Glow
            }
        }
    }

    $visual = [Windows.Media.Media3D.ModelVisual3D]::new()
    $visual.Content = $world
    $viewport.Children.Add($visual)
    $viewport.Tag = @{ Parallax = $parallax; Drift = $drift; Mode = $Mode }
    return $viewport
}

function Update-FieldKitScene($Viewport, [double]$AimX, [double]$AimY, [double]$Phase) {
    if ($null -eq $Viewport -or $null -eq $Viewport.Tag) { return }

    $data = $Viewport.Tag
    $data.Parallax.OffsetX = 0.1 * [Math]::Max(-1.0, [Math]::Min(1.0, $AimX))
    $data.Parallax.OffsetY = 0.07 * [Math]::Max(-1.0, [Math]::Min(1.0, $AimY))
    $data.Drift.OffsetX = 0.11 * [Math]::Sin($Phase * 0.72)
    $data.Drift.OffsetY = 0.055 * [Math]::Sin($Phase * 0.93)
}
