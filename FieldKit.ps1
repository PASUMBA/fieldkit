param([switch]$SelfTest, [switch]$SmokeTest, [switch]$PreviewOnly)
. (Join-Path $PSScriptRoot 'FieldKitProgress.ps1')
. (Join-Path $PSScriptRoot 'FieldKitScenes.ps1')
$ErrorActionPreference = 'Stop'
function Read-Motion([string]$line) {
    if ($line -notmatch '^\d{1,10},(-?\d{1,2}\.\d{1,6}),(-?\d{1,2}\.\d{1,6}),(-?\d{1,2}\.\d{1,6})\r?$') { return }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    [double[]]@([double]::Parse($Matches[1],$culture), [double]::Parse($Matches[2],$culture), [double]::Parse($Matches[3],$culture))
}
function Get-Aim([double[]]$sample,[double[]]$origin,[double[]]$right,[double[]]$up,[switch]$Raw) {
    $rr=0.0; $uu=0.0; $ru=0.0; $sr=0.0; $su=0.0
    for ($i=0; $i -lt 3; $i++) {
        $r=$right[$i]-$origin[$i]
        $u=$up[$i]-$origin[$i]
        $d=$sample[$i]-$origin[$i]
        $rr+=$r*$r; $uu+=$u*$u; $ru+=$r*$u; $sr+=$d*$r; $su+=$d*$u
    }
    $det=$rr*$uu-$ru*$ru
    if ($rr -lt 0.0025 -or $uu -lt 0.0025 -or $det -lt 0.16*$rr*$uu) { return }
    $x=($sr*$uu-$su*$ru)/$det
    $y=($su*$rr-$sr*$ru)/$det
    if ($Raw) { $x; $y; return }
    [Math]::Max(-1.0,[Math]::Min(1.0,$x))
    [Math]::Max(-1.0,[Math]::Min(1.0,$y))
}
function New-AimCalibration($center,$left,$right,$up,$down) {
    $horizontal = @(for ($i=0;$i -lt 3;$i++) { $center[$i]+$right[$i]-$left[$i] })
    $vertical = @(for ($i=0;$i -lt 3;$i++) { $center[$i]+$up[$i]-$down[$i] })
    $l = @(Get-Aim $left $center $horizontal $vertical -Raw)
    if ($l.Count -ne 2) { return }
    $r = @(Get-Aim $right $center $horizontal $vertical -Raw)
    $u = @(Get-Aim $up $center $horizontal $vertical -Raw)
    $d = @(Get-Aim $down $center $horizontal $vertical -Raw)
    if ($l[0] -ge -0.12 -or $r[0] -le 0.12 -or $u[1] -le 0.12 -or $d[1] -ge -0.12) { return }
    @{ Horizontal=$horizontal; Vertical=$vertical; Left=-$l[0]; Right=$r[0]; Up=$u[1]; Down=-$d[1] }
}
function Get-CalibratedAim($sample,$center,$profile) {
    $projected = @(Get-Aim $sample $center $profile.Horizontal $profile.Vertical -Raw)
    $x = $projected[0] / $(if ($projected[0] -lt 0) {$profile.Left} else {$profile.Right})
    $y = $projected[1] / $(if ($projected[1] -lt 0) {$profile.Down} else {$profile.Up})
    [Math]::Max(-1.0,[Math]::Min(1.0,$x))
    [Math]::Max(-1.0,[Math]::Min(1.0,$y))
}
function Get-Position([double[]]$sample,[double[]]$origin,[double[]]$target) {
    $dot = 0.0
    $lengthSquared = 0.0
    for ($i = 0; $i -lt 3; $i++) {
        $axis = $target[$i] - $origin[$i]
        $dot += ($sample[$i] - $origin[$i]) * $axis
        $lengthSquared += $axis * $axis
    }
    if ($lengthSquared -lt 0.0025) { return }
    [Math]::Max(0.0,[Math]::Min(1.0,$dot / $lengthSquared))
}
if ($SelfTest) {
    $parsed = @(Read-Motion '28773,0.1456,0.5597,0.8310')
    if ($parsed.Count -ne 3 -or $parsed[1] -ne 0.5597) { throw 'Valid CSV did not parse' }
    foreach ($invalid in @('ERROR: No accelerometer data','14,0.1,NaN,0.3','12,0.1,0.2')) {
        if ($null -ne (Read-Motion $invalid)) { throw 'Malformed CSV parsed' }
    }
    $origin = @(0.0,0.0,1.0)
    $target = @(0.4,0.0,0.9)
    if ([Math]::Abs((Get-Position @(0.2,0.0,0.95) $origin $target) - 0.5) -gt 0.000001) { throw 'Position calibration failed' }
    if ($null -ne (Get-Position $origin $origin $origin)) { throw 'Identical poses passed calibration' }
    if ((Get-Position @(-0.5,0.0,1.0) $origin $target) -ne 0) { throw 'Out-of-range position was not clamped' }
    $right = @(0.50,0.0,0.87)
    $up = @(0.0,0.50,0.87)
    foreach ($x in @(-0.7,0.7)) {
        foreach ($y in @(-0.6,0.6)) {
            $aim = @(Get-Aim @((0.50*$x),(0.50*$y),(1-0.13*($x+$y))) $origin $right $up)
            if ($aim.Count -ne 2 -or [Math]::Abs($aim[0]-$x) -gt 0.00001 -or [Math]::Abs($aim[1]-$y) -gt 0.00001) { throw 'Two-axis aiming calibration failed' }
        }
    }
    if ($null -ne (Get-Aim $right $origin $right $right)) { throw 'Duplicate aiming directions passed calibration' }
    $profile=New-AimCalibration $origin @(-0.25,0,0.97) $right $up @(0,-0.3,0.95)
    if (!$profile) { throw 'Distinct calibration poses were rejected' }
    $aim=@(Get-CalibratedAim @(-0.125,-0.15,0.96) $origin $profile)
    if ($aim[0] -gt -0.35 -or $aim[1] -gt -0.35) { throw 'Left/down motion failed' }
    if (New-AimCalibration $origin $right $right $up @(0,-0.3,0.95)) { throw 'Duplicate poses were accepted' }
    'FieldKit checks passed.'
    return
}

Add-Type -AssemblyName PresentationFramework
[xml]$layout = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="FieldKit" Width="1150" Height="770" MinWidth="860" MinHeight="590"
        WindowStartupLocation="CenterScreen" Background="#EDF3F0" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#183932"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="11,7"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Background" Value="#E1EFE9"/>
      <Setter Property="Foreground" Value="#183932"/>
      <Setter Property="BorderBrush" Value="#AACCC0"/>
    </Style>
  </Window.Resources>
  <Grid Margin="22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <Grid x:Name="ArcadeHeader" Margin="0,0,0,16">
      <StackPanel>
        <TextBlock Text="FieldKit" FontSize="34" FontWeight="Bold"/>
        <TextBlock Text="Motion-controlled arcade" FontSize="15" Foreground="#40655C"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
        <TextBlock x:Name="ConnectionStatus" Text="USB disconnected" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold" Margin="0,0,14,0"/>
        <Button x:Name="HomeButton" Content="Movement library"/>
      </StackPanel>
    </Grid>
    <Grid x:Name="Arcade" Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="305"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Border Background="White" CornerRadius="16" Padding="17" Margin="0,0,14,0">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <TextBlock Text="1. Connect the glove" FontSize="19" FontWeight="SemiBold"/>
            <WrapPanel Margin="0,8,0,5">
              <ComboBox x:Name="Ports" Width="90" FontSize="15" Margin="0,0,6,0"/>
              <Button x:Name="RefreshPorts" Content="Refresh"/>
              <Button x:Name="Connect" Content="Connect"/>
            </WrapPanel>
            <Button x:Name="Preview" Content="Keyboard preview" HorizontalAlignment="Left" Margin="0,4,0,6"/>
            <TextBlock x:Name="Samples" Text="No samples" TextWrapping="Wrap" FontSize="13" Foreground="#40655C"/>
            <Separator Margin="0,14"/>
            <TextBlock Text="2. Set your movement" FontSize="19" FontWeight="SemiBold"/>
            <TextBlock Text="Capture center first. Return to center before each tilt. Hold each pose until its button gets a check mark." TextWrapping="Wrap" Margin="0,6,0,9"/>
            <WrapPanel>
              <Button x:Name="SetRest" Content="Set center" IsEnabled="False"/>
              <Button x:Name="SetLeft" Content="Left" IsEnabled="False"/><Button x:Name="SetGoal" Content="Right" IsEnabled="False"/><Button x:Name="SetUp" Content="Up" IsEnabled="False"/><Button x:Name="SetDown" Content="Down" IsEnabled="False"/>
            </WrapPanel>
            <TextBlock x:Name="CalibrationStatus" Text="Waiting for motion data" TextWrapping="Wrap" Margin="0,8,0,7" Foreground="#40655C"/>
            <ProgressBar x:Name="Travel" Height="8" Maximum="100" Foreground="#16856F" Background="#D9E9E3"/>
            <TextBlock Text="Hold time (seconds)" Margin="0,12,0,2"/>
            <ComboBox x:Name="HoldTime" SelectedIndex="1" Width="90" HorizontalAlignment="Left">
              <ComboBoxItem Content="0.5"/><ComboBoxItem Content="1.0"/><ComboBoxItem Content="1.5"/><ComboBoxItem Content="2.0"/>
            </ComboBox>
          </StackPanel>
        </ScrollViewer>
      </Border>
      <Border Grid.Column="1" Background="#123C36" CornerRadius="16" Padding="20">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel>
            <TextBlock x:Name="ArenaTitle" Text="Asteroid Blaster" FontSize="27" Foreground="#F0FBF6" FontWeight="Bold"/>
            <WrapPanel Margin="0,4,0,5">
              <ComboBox x:Name="Game" SelectedIndex="0" Width="160" Margin="0,0,10,0" AutomationProperties.Name="Game">
                <ComboBoxItem Content="Asteroid Blaster"/><ComboBoxItem Content="Backwater Ferry"/><ComboBoxItem Content="Lantern Lift"/><ComboBoxItem Content="Reef Rescue"/>
              </ComboBox>
              <TextBlock Text="Daily level" VerticalAlignment="Center" Foreground="#D1EFE5" Margin="0,0,6,0"/>
              <ComboBox x:Name="Level" SelectedIndex="0" Width="155" AutomationProperties.Name="Daily level">
                <ComboBoxItem Content="1 · Wide targets"/><ComboBoxItem Content="2 · Standard"/><ComboBoxItem Content="3 · Precision"/>
              </ComboBox>
            </WrapPanel>
            <TextBlock x:Name="Today" Text="No rounds logged today" Foreground="#D1EFE5" TextWrapping="Wrap" Margin="0,0,0,5"/>
            <TextBlock x:Name="MovementBadge" Foreground="#C8E6DE" TextWrapping="Wrap" FontSize="13" Margin="0,0,0,5"/><TextBlock x:Name="ArenaTip" Text="Tilt to aim anywhere in the arena. Hold the crosshair on an asteroid to fire." FontSize="15" Foreground="#B5DFD3" TextWrapping="Wrap"/>
          </StackPanel>
          <Viewbox Grid.Row="1" Stretch="Uniform" Margin="0,10">
            <Canvas x:Name="Arena" Width="600" Height="320" ClipToBounds="True" Background="#0A1730">
                            <Border x:Name="SceneHost" Width="600" Height="320" IsHitTestVisible="False"/><Canvas x:Name="Stars" Width="600" Height="320" IsHitTestVisible="False"><Ellipse Width="248" Height="248" Stroke="#365781" StrokeThickness="2" Fill="#172C50" Opacity="0.48" Canvas.Left="422" Canvas.Top="185"/><Ellipse Width="88" Height="28" Stroke="#55749B" Opacity="0.45" Canvas.Left="473" Canvas.Top="220"/><Path Stroke="#263D62" StrokeThickness="1" Data="M 300,160 L 28,32 M 300,160 L 572,32 M 300,160 L 28,288 M 300,160 L 572,288"/><Ellipse Width="390" Height="214" Stroke="#304A73" StrokeDashArray="2 7" Canvas.Left="105" Canvas.Top="53"/>
                <Ellipse Fill="#BED4FF" Width="4" Height="4" Canvas.Left="155" Canvas.Top="55"/>
                <Ellipse Fill="#6583AC" Width="3" Height="3" Canvas.Left="270" Canvas.Top="100"/>
                <Ellipse Fill="#C3D3F9" Width="4" Height="4" Canvas.Left="432" Canvas.Top="45"/>
                <Ellipse Fill="#8299BF" Width="3" Height="3" Canvas.Left="540" Canvas.Top="197"/>
                <Ellipse Fill="#AEC4E9" Width="3" Height="3" Canvas.Left="71" Canvas.Top="190"/>
                <Ellipse Fill="#8299BF" Width="3" Height="3" Canvas.Left="390" Canvas.Top="229"/>
              </Canvas>
              <Rectangle x:Name="FerryLine" Width="556" Height="2" Fill="#60779A" Canvas.Left="22" Canvas.Top="160" Visibility="Collapsed"/>
              <Line x:Name="Sight" Stroke="#5274A6" StrokeThickness="1" StrokeDashArray="5 6" X1="300" Y1="308"/>
              <Line x:Name="Laser" StrokeThickness="6" Stroke="#72FFD9" X1="300" Y1="308" Visibility="Collapsed"/>
              <TextBlock x:Name="LeftLabel" Text="REST" Visibility="Collapsed" Canvas.Left="28" Canvas.Top="280" FontSize="18" Foreground="#B5DFD3"/>
              <TextBlock x:Name="RightLabel" Text="TARGET RANGE" Visibility="Collapsed" Canvas.Right="28" Canvas.Top="280" FontSize="18" Foreground="#B5DFD3"/>
              <Ellipse x:Name="Orb" Stroke="#FFF0AA" StrokeThickness="3" Fill="#8B6032" Visibility="Collapsed"/><Path x:Name="Crystal" Stroke="#8CFFDA" StrokeThickness="3" Fill="#227B7A" Stretch="Fill" Data="M 12,0 L 22,11 12,24 2,11 Z" Visibility="Collapsed"/><Ellipse x:Name="PlayerOrb" Width="29" Height="29" Fill="#DCCAFF" Stroke="#FFFFFF" StrokeThickness="2" Visibility="Collapsed"/>              <Path x:Name="Bubble" Width="76" Height="76" Stretch="Fill" Data="M 12,0 L 48,3 73,23 69,47 56,72 23,70 0,48 2,20 Z" Stroke="#FFD28C" StrokeThickness="3" Visibility="Collapsed">
                <Path.Fill><RadialGradientBrush GradientOrigin="0.25,0.16"><GradientStop Color="#EDB377" Offset="0"/><GradientStop Color="#805343" Offset="0.62"/><GradientStop Color="#402C43" Offset="1"/></RadialGradientBrush></Path.Fill>
              </Path>
              <Rectangle x:Name="Dock" Width="76" Height="76" RadiusX="14" RadiusY="14" Stroke="#F8CF75" StrokeThickness="4" Fill="#675A38" Visibility="Collapsed"/>
              <Path x:Name="Aim" Width="38" Height="38" Stretch="Uniform" Data="M 19,1 L 19,10 M 19,28 L 19,37 M 1,19 L 10,19 M 28,19 L 37,19 M 19,7 A 12,12 0 1 1 18.9,7 Z" Stroke="#F7FFF9" StrokeThickness="2"/>
              <TextBlock x:Name="Boat" Text="FERRY" FontWeight="Bold" Width="62" TextAlignment="Center" Height="27" FontSize="17" Background="#CAEAD9" Visibility="Collapsed"/>
              <Ellipse x:Name="Impact" Stroke="#76FFD9" StrokeThickness="3" Width="58" Height="58" Visibility="Collapsed"/><TextBlock x:Name="CanvasHint" Text="Connect and calibrate to start" Canvas.Left="24" Canvas.Top="35" FontSize="20" Foreground="#D1EFE5"/>
            </Canvas>
          </Viewbox>
          <Grid Grid.Row="2">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <TextBlock x:Name="RoundStatus" Text="Ready when you are" FontSize="16" Foreground="#F0FBF6" Margin="0,0,0,8" TextWrapping="Wrap"/>
            <StackPanel Grid.Row="1"><ProgressBar x:Name="HoldProgress" Height="10" Maximum="100" Background="#34665E" Foreground="#F8CF75"/><WrapPanel Margin="0,10,0,0"><Button x:Name="Start" Content="Start round" IsEnabled="False"/><Button x:Name="Stop" Content="End round" IsEnabled="False"/><Button x:Name="Progress" Content="Therapy progress"/></WrapPanel></StackPanel>
          </Grid>
        </Grid>
      </Border>
    </Grid>
    <Border x:Name="Landing" Grid.RowSpan="2" Background="#E7EFEF" CornerRadius="20">
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="24">
          <Border CornerRadius="18" Padding="27" Margin="0,0,0,18">
            <Border.Background><LinearGradientBrush EndPoint="1,1"><GradientStop Color="#152746" Offset="0"/><GradientStop Color="#135C58" Offset="1"/></LinearGradientBrush></Border.Background>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="230"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="FieldKit" Foreground="White" FontSize="48" FontWeight="Bold"/>
                <TextBlock Text="Movement arcade" Foreground="#A9F0D3" FontWeight="SemiBold" FontSize="23"/>
                <TextBlock Text="Use your USB glove to play through a movement chosen with your therapist." FontSize="16" Foreground="#E0F4EF" TextWrapping="Wrap" Margin="0,8,0,0"/>
              </StackPanel>
              <Viewbox Grid.Column="1" Margin="15,0,0,0" IsHitTestVisible="False">
                <Canvas Width="220" Height="100">
                  <Ellipse Width="69" Height="69" Fill="#377E88" Stroke="#9EE9DD" StrokeThickness="2" Canvas.Left="78" Canvas.Top="16"/>
                  <Ellipse Width="156" Height="53" Stroke="#69B8BD" StrokeThickness="2" Canvas.Left="34" Canvas.Top="27"><Ellipse.RenderTransform><RotateTransform Angle="-22" CenterX="78" CenterY="26"/></Ellipse.RenderTransform></Ellipse>
                  <Ellipse Width="13" Height="13" Fill="#FFE0A2" Canvas.Left="166" Canvas.Top="16"/><Ellipse Width="9" Height="9" Fill="#95D8F1" Canvas.Left="43" Canvas.Top="77"/><Ellipse Width="5" Height="5" Fill="White" Canvas.Left="33" Canvas.Top="28"/>
                </Canvas>
              </Viewbox>
            </Grid>
          </Border>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="15"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Background="White" CornerRadius="14" Padding="17">
              <StackPanel>
                <TextBlock Text="Injury or practice context" FontSize="18" FontWeight="SemiBold"/>
                <ComboBox x:Name="Injury" SelectedIndex="0" FontSize="15" Margin="0,7,0,9">
                  <ComboBoxItem Content="Demo or general practice"/><ComboBoxItem Content="Wrist sprain or soft-tissue injury"/><ComboBoxItem Content="Wrist fracture recovery"/><ComboBoxItem Content="Elbow or forearm injury"/><ComboBoxItem Content="Post-operative or tendon rehab"/>
                </ComboBox>
                <TextBlock x:Name="ContextText" Text="Try the movement controls with the glove or keyboard preview." TextWrapping="Wrap" Foreground="#40655C"/>
              </StackPanel>
            </Border>
            <Border Grid.Column="2" Background="White" CornerRadius="14" Padding="17">
              <StackPanel>
                <TextBlock Text="Choose your exercise" FontSize="18" FontWeight="SemiBold"/>
                <ComboBox x:Name="Exercise" SelectedIndex="0" FontSize="15" Margin="0,7,0,9">
                  <ComboBoxItem Content="Multi-direction coordination"/><ComboBoxItem Content="Side-to-side wrist motion"/><ComboBoxItem Content="Wrist bend and straighten"/><ComboBoxItem Content="Forearm rotation"/>
                </ComboBox>
                <TextBlock x:Name="ExerciseText" TextWrapping="Wrap" Foreground="#40655C" Text="Asteroid Blaster · Reach targets in several directions, then hold to fire."/>
              </StackPanel>
            </Border>
          </Grid>
          <WrapPanel Margin="0,14,0,18">
            <Button x:Name="Begin" Content="Open Asteroid Blaster" Background="#14685B" Foreground="White" Padding="20,9" FontWeight="SemiBold"/>
            <Button x:Name="HomeProgress" Content="View progress" Padding="15,9"/>
          </WrapPanel>
          <UniformGrid Columns="4">
            <Button x:Name="CardSpace" Content="Asteroid Blaster" Background="#D9E5F6" Padding="6,10"/>
            <Button x:Name="CardFerry" Content="Backwater Ferry" Background="#CCEBDD" Padding="6,10"/>
            <Button x:Name="CardLantern" Content="Lantern Lift" Background="#F0E1D2" Padding="6,10"/>
            <Button x:Name="CardReef" Content="Reef Rescue" Background="#D1E9EB" Padding="6,10"/>
          </UniformGrid>
        </StackPanel>
      </ScrollViewer>
    </Border>
  </Grid>
</Window>
"@
$window = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($layout))
$ui = @{}
foreach ($name in 'Landing','Arcade','ArcadeHeader','HomeButton','HomeProgress','Injury','Exercise','ContextText','ExerciseText','Begin','MovementBadge','CardSpace','CardFerry','CardLantern','CardReef','ConnectionStatus','Ports','RefreshPorts','Connect','Preview','Samples','SetRest','SetGoal','SetLeft','SetUp','SetDown','CalibrationStatus','Travel','HoldTime','Game','Level','Today','Progress','Start','Stop','ArenaTitle','ArenaTip','Arena','SceneHost','Stars','Sight','Laser','Impact','FerryLine','LeftLabel','RightLabel','Bubble','Dock','Orb','Crystal','PlayerOrb','Aim','Boat','CanvasHint','RoundStatus','HoldProgress') {
    $ui[$name] = $window.FindName($name)
}
$clock = [Diagnostics.Stopwatch]::StartNew()
$state = @{
    Port = $null; Preview = $false; Buffer = ''; Last = -10000L; Samples = 0; Filter = $null
    LiveOrigin = $null; Origin = $null; Target = $null; Capture = $null; Position = 0.0; Round = $false
    Hits = 0; Returning = $false; HoldingSince = -1L; PreviewPosition = 0.0
    Scene=$null; SceneMode=-1; Left = $null; Up = $null; Down = $null; AimCalibration = $null; Level = 1; RoundStart = 0L; AimX = 0.0; AimY = 0.0; PreviewY = 0.0; ShotUntil = -1L; ShotX = 300.0; ShotY = 160.0; SpaceTargets = @(@(-0.65,0.44),@(0.68,0.56),@(-0.48,-0.48),@(0.56,-0.43),@(0.0,0.25)); Goals = @(0.45,0.78,0.60,0.90,0.65); NeededMs = 1000
}
$routes = @(
    @{ Name='Asteroid Blaster'; Motion='Multi-direction coordination'; Tip='Aim in any direction. Hold the reticle on an asteroid to fire.'; Detail='A two-axis game for a movement pattern chosen with your therapist.'; Color='#071127' },
    @{ Name='Backwater Ferry'; Motion='Side-to-side wrist motion'; Tip='Steer to the dock, hold to board, then return to center.'; Detail='Practise a selected side-to-side wrist movement, called radial or ulnar deviation.'; Color='#103F49' },
    @{ Name='Lantern Lift'; Motion='Wrist bend and straighten'; Tip='Lift the light into the lantern ring. Hold to light it, then lower to center.'; Detail='Practise a selected wrist bend or straighten movement, called flexion or extension.'; Color='#211539' },
    @{ Name='Reef Rescue'; Motion='Forearm rotation'; Tip='Glide the diver to the crystal. Hold to collect it, then return to the start.'; Detail='Practise an approved turn of the palm, called pronation or supination.'; Color='#083642' }
)
$contexts = @(
    'Try the controls with your glove or the keyboard preview.',
    'Choose only a wrist movement that has been cleared for your current stage.',
    'Use the movement and range your clinician has cleared for your stage of fracture recovery.',
    'Forearm rotation is available if turning the palm has been cleared for you.',
    'Follow the movement and range in your post-operative protocol. Finger-specific exercises need a different input.'
)
function Select-Exercise([int]$index) {
    $route=$routes[$index]
    $ui.ExerciseText.Text="$($route.Name) · $($route.Detail)"
    $ui.Begin.Content="Open $($route.Name)"
}
function Open-Arcade([int]$index) {
    $ui.Landing.Visibility='Collapsed'
    $ui.Arcade.Visibility='Visible'
    $ui.ArcadeHeader.Visibility='Visible'
    $ui.Exercise.SelectedIndex=$index
    $ui.Game.SelectedIndex=$index
}
$ui.Injury.Add_SelectionChanged({ $ui.ContextText.Text=$contexts[$ui.Injury.SelectedIndex] })
$ui.Exercise.Add_SelectionChanged({ Select-Exercise $ui.Exercise.SelectedIndex })
$ui.Begin.Add_Click({ Open-Arcade $ui.Exercise.SelectedIndex })
$ui.CardSpace.Add_Click({ $ui.Exercise.SelectedIndex=0 })
$ui.CardFerry.Add_Click({ $ui.Exercise.SelectedIndex=1 })
$ui.CardLantern.Add_Click({ $ui.Exercise.SelectedIndex=2 })
$ui.CardReef.Add_Click({ $ui.Exercise.SelectedIndex=3 })
$ui.HomeButton.Add_Click({
    if ($state.Round) { Record-Round; Stop-Round }
    $ui.Arcade.Visibility='Collapsed'
    $ui.ArcadeHeader.Visibility='Collapsed'
    $ui.Landing.Visibility='Visible'
})
$ui.HomeProgress.Add_Click({ Show-Progress })
function Update-Route {
    $index=$ui.Game.SelectedIndex
    $route=$routes[$index]
    $ui.ArenaTitle.Text=$route.Name
    $ui.ArenaTip.Text=$route.Tip
    $ui.MovementBadge.Text=if ($index -eq 0) {
        "$($route.Motion) · Capture all five poses"
    } else {
        "$($route.Motion) · Capture Center, then use Right to capture your movement endpoint"
    }
    $ui.Exercise.SelectedIndex=$index
    $ui.Arena.Background=$route.Color
    $state.Scene=New-FieldKitScene $route.Name
    $ui.SceneHost.Child=$state.Scene
}
function Update-Ports {
    $previous = $ui.Ports.SelectedItem
    $ui.Ports.Items.Clear()
    foreach ($port in [IO.Ports.SerialPort]::GetPortNames() | Sort-Object) { [void]$ui.Ports.Items.Add($port) }
    if ($previous -and $ui.Ports.Items.Contains($previous)) { $ui.Ports.SelectedItem = $previous }
    elseif ($ui.Ports.Items.Contains('COM26')) { $ui.Ports.SelectedItem = 'COM26' }
    elseif ($ui.Ports.Items.Count -gt 0) { $ui.Ports.SelectedIndex = 0 }
}
function Stop-Round {
    $state.Round = $false
    $state.HoldingSince = -1
    $state.Returning = $false
    $ui.HoldProgress.Value = 0
    $ui.Stop.IsEnabled = $false
    $ui.Bubble.Visibility = 'Collapsed'
    $ui.Dock.Visibility = 'Collapsed'
    $ui.Orb.Visibility = 'Collapsed'
    $ui.Crystal.Visibility = 'Collapsed'
}
function Reset-Input {
    Stop-Round
    $state.Buffer = ''
    $state.Last = -10000L
    $state.Samples = 0
    $state.Filter = $null
    $state.LiveOrigin = $null
    $state.Origin = $null
    $state.Target = $null
    $state.Up = $null
    $state.Left = $null
    $state.Down = $null
    $state.AimCalibration = $null
    $ui.SetRest.Content='Set center'
    $ui.SetLeft.Content='Left'
    $ui.SetGoal.Content='Right'
    $ui.SetUp.Content='Up'
    $ui.SetDown.Content='Down'
    $state.Capture = $null
    $state.Position = 0.0
    $ui.Samples.Text = 'No samples'
    $ui.CalibrationStatus.Text = 'Waiting for motion data'
}
function Close-Port {
    if ($state.Port) {
        try { $state.Port.Dispose() } catch {}
        $state.Port = $null
    }
    $ui.Connect.Content = 'Connect'
    $ui.Ports.IsEnabled = $true
    $ui.RefreshPorts.IsEnabled = $true
}
function Add-Sample([double[]]$vector,[long]$now) {
    $state.Last = $now
    $state.Samples++
    if ($null -eq $state.Filter) { $state.Filter = $vector.Clone(); $state.LiveOrigin = $vector.Clone() }
    for ($i=0; $i -lt 3; $i++) { $state.Filter[$i] = 0.70 * $state.Filter[$i] + 0.30 * $vector[$i] }
    if ($state.Capture) { $state.Capture.Values.Add($vector) }
}
function Start-Capture([string]$pose) {
    Stop-Round
    $state.Capture = @{ Pose=$pose; Until=$clock.ElapsedMilliseconds+700; Values=[Collections.Generic.List[object]]::new() }
    $ui.CalibrationStatus.Text = "Hold still. Capturing $pose..."
}
function Complete-Capture {
    $capture = $state.Capture
    $state.Capture = $null
    if ($capture.Values.Count -lt 8) { $ui.CalibrationStatus.Text = 'Too few samples. Try again.'; return }
    [double[]]$mean = @(0.0,0.0,0.0)
    foreach ($sample in $capture.Values) {
        for ($i=0; $i -lt 3; $i++) { $mean[$i] += $sample[$i] / $capture.Values.Count }
    }
    $spread = 0.0
    foreach ($sample in $capture.Values) {
        for ($i=0; $i -lt 3; $i++) { $spread += [Math]::Pow($sample[$i]-$mean[$i],2) / $capture.Values.Count }
    }
    if ($spread -gt 0.0036) { $ui.CalibrationStatus.Text = 'Movement detected. Hold the pose and try again.'; return }
    if ($capture.Pose -eq 'center') {
        $state.Origin = $mean
        foreach ($key in 'Left','Target','Up','Down','AimCalibration') { $state[$key]=$null }
        $ui.SetRest.Content='Center ✓'
        $ui.SetLeft.Content='Left'
        $ui.SetGoal.Content='Right'
        $ui.SetUp.Content='Up'
        $ui.SetDown.Content='Down'
        $ui.CalibrationStatus.Text='Center captured. Tilt and capture each direction.'
        return
    }
    if ($null -eq (Get-Position $mean $state.Origin $mean)) {
        $ui.CalibrationStatus.Text = 'That pose is close to center. Tilt a little farther and retry.'
        return
    }
    $controls = @{left='SetLeft';right='SetGoal';up='SetUp';down='SetDown'}
    $keys = @{left='Left';right='Target';up='Up';down='Down'}
    $state[$keys[$capture.Pose]]=$mean
    $ui[$controls[$capture.Pose]].Content="$($capture.Pose) ✓"
    $state.AimCalibration=$null
    $missing=@(foreach ($key in 'left','right','up','down') { if (!$state[$keys[$key]]) { $key } })
    if ($missing.Count -gt 0) {
        $ui.CalibrationStatus.Text = 'Still to capture: ' + ($missing -join ', ') + '.'
        return
    }
    $state.AimCalibration=New-AimCalibration $state.Origin $state.Left $state.Target $state.Up $state.Down
    $ui.CalibrationStatus.Text = if ($state.AimCalibration) {
        'Calibrated. Try all four directions before starting.'
    } else {
        'Some poses overlap. Recapture opposite directions using opposite edges of the board.'
    }
}
function Get-LocalSessionDate($session) {
    ([DateTimeOffset]::Parse([string]$session.Date,[Globalization.CultureInfo]::InvariantCulture)).ToLocalTime()
}
function Show-Today {
    $today = @(Get-FieldKitSessions | Where-Object { (Get-LocalSessionDate $_).Date -eq [DateTime]::Today })
    $cleared = @($today | Where-Object Completed | Group-Object -Property Game,Level).Count
    $ui.Today.Text = "Today: $($today.Count) rounds logged · $cleared of 12 game levels cleared"
}
function Record-Round {
    if (!$state.Round -or $state.Preview) { return }
    $seconds=[int][Math]::Max(1.0,[Math]::Round(($clock.ElapsedMilliseconds-$state.RoundStart)/1000.0))
    try {
        Save-FieldKitSession ([string]$ui.ArenaTitle.Text) $state.Level $state.Hits $state.Goals.Count $seconds
        Show-Today
    } catch {
        $ui.Today.Text='Progress could not be saved. Check available disk space.'
    }
}
function Show-Progress {
    [xml]$view=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="FieldKit therapy progress" Width="760" Height="420" MinWidth="620" MinHeight="330" WindowStartupLocation="CenterOwner"
        Background="#EDF3F0" FontFamily="Segoe UI">
  <DockPanel Margin="20">
    <StackPanel DockPanel.Dock="Top" Margin="0,0,0,12">
      <TextBlock Text="Therapy progress" FontSize="27" FontWeight="Bold" Foreground="#183932"/>
      <TextBlock x:Name="Overview" FontSize="14" TextWrapping="Wrap" Margin="0,5,0,5"/>
      <TextBlock Text="Only rounds played with the USB glove are logged on this PC." Foreground="#40655C" TextWrapping="Wrap"/>
    </StackPanel>
    <Button x:Name="Done" DockPanel.Dock="Bottom" Content="Close" HorizontalAlignment="Right" Padding="14,5" Margin="0,12,0,0" IsCancel="True"/>
    <DataGrid x:Name="Rounds" IsReadOnly="True" AutoGenerateColumns="False" CanUserAddRows="False" HeadersVisibility="Column" Background="White">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Date and time" Binding="{Binding Played}" Width="2*"/>
        <DataGridTextColumn Header="Game" Binding="{Binding Game}" Width="2*"/>
        <DataGridTextColumn Header="Level" Binding="{Binding Level}" Width="*"/>
        <DataGridTextColumn Header="Targets" Binding="{Binding Targets}" Width="*"/>
        <DataGridTextColumn Header="Time" Binding="{Binding Duration}" Width="*"/>
        <DataGridTextColumn Header="Result" Binding="{Binding Outcome}" Width="*"/>
      </DataGrid.Columns>
    </DataGrid>
  </DockPanel>
</Window>
"@
    $dialog=[Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($view))
    $dialog.Owner=$window
    $history=@(Get-FieldKitSessions | Sort-Object -Property Date -Descending)
    $completed=@($history | Where-Object Completed).Count
    $days=@($history | ForEach-Object {(Get-LocalSessionDate $_).Date} | Sort-Object -Unique).Count
    $dialog.FindName('Overview').Text = if ($history.Count) {
        "$days practice days · $($history.Count) rounds logged · $completed completed"
    } else { 'No rounds yet. Complete a glove round or choose End round to log an attempt.' }
    $dialog.FindName('Rounds').ItemsSource = @(
        foreach ($session in $history) {
            [pscustomobject]@{
                Played=(Get-LocalSessionDate $session).ToString('dd MMM yyyy HH:mm')
                Game=$session.Game
                Level=$session.Level
                Targets="$($session.Hits)/$($session.Total)"
                Duration=([TimeSpan]::FromSeconds($session.DurationSeconds)).ToString('mm\:ss')
                Outcome=if ($session.Completed) {'Complete'} else {'Ended'}
            }
        }
    )
    [void]$dialog.ShowDialog()
}
function Get-TargetSize([bool]$ferry,[int]$hit) {
    $base = if ($ferry) {76} else {@(62,48,70,54,59)[$hit]}
    $base * @(1.28,1.0,0.75)[$state.Level-1]
}
function Get-GamePoint([int]$mode,[double]$position) {
    switch ($mode) {
        0 { 300+245*$state.AimX; 155-110*$state.AimY }
        1 { 60+480*$position; 160 }
        2 { 300; 265-207*$position }
        3 { 65+470*$position; 243-95*$position }
    }
}
function Move-Arena([double]$position) {
    $mode=$ui.Game.SelectedIndex
    $point=@(Get-GamePoint $mode $position)
    $x=$point[0]; $y=$point[1]
    $ui.Aim.Visibility = if ($mode -eq 0) {'Visible'} else {'Collapsed'}
    $ui.Sight.Visibility=$ui.Aim.Visibility
    $ui.Stars.Visibility='Collapsed'
    $ui.Boat.Visibility = if ($mode -eq 1) {'Visible'} else {'Collapsed'}
    $ui.FerryLine.Visibility=$ui.Boat.Visibility
    $ui.LeftLabel.Visibility=$ui.Boat.Visibility
    $ui.RightLabel.Visibility=$ui.Boat.Visibility
    $ui.PlayerOrb.Visibility = if ($mode -ge 2) {'Visible'} else {'Collapsed'}
    $ui.PlayerOrb.Fill = if ($mode -eq 2) {'#FFDA84'} else {'#9FF6EA'}
    [Windows.Controls.Canvas]::SetLeft($ui.PlayerOrb,$x-14.5)
    [Windows.Controls.Canvas]::SetTop($ui.PlayerOrb,$y-14.5)
    [Windows.Controls.Canvas]::SetLeft($ui.Aim,$x-19)
    [Windows.Controls.Canvas]::SetTop($ui.Aim,$y-19)
    [Windows.Controls.Canvas]::SetLeft($ui.Boat,$x-31)
    [Windows.Controls.Canvas]::SetTop($ui.Boat,147)
    if ($state.Scene) {
        Update-FieldKitScene $state.Scene (($x-300)/245.0) ((155-$y)/110.0) ($clock.ElapsedMilliseconds/1000.0)
    }
    $ui.Sight.X2=$x; $ui.Sight.Y2=$y
    $ui.Laser.X2=$state.ShotX; $ui.Laser.Y2=$state.ShotY
    $hitFlash=$clock.ElapsedMilliseconds -lt $state.ShotUntil
    $ui.Laser.Visibility = if ($mode -eq 0 -and $hitFlash) {'Visible'} else {'Collapsed'}
    $ui.Impact.Visibility=if ($hitFlash) {'Visible'} else {'Collapsed'}
    if ($hitFlash) {
        $ui.Impact.Opacity=[Math]::Max(0.0,[Math]::Min(1.0,($state.ShotUntil-$clock.ElapsedMilliseconds)/260.0))
        [Windows.Controls.Canvas]::SetLeft($ui.Impact,$state.ShotX-29)
        [Windows.Controls.Canvas]::SetTop($ui.Impact,$state.ShotY-29)
    }
    if (!$state.Round -or $state.Returning) { return }
    $marker=$ui[@('Bubble','Dock','Orb','Crystal')[$mode]]
    $isSpace=$mode -eq 0
    if ($isSpace) {
        $target=$state.SpaceTargets[$state.Hits]
        $targetPoint=@(300+245*$target[0];155-110*$target[1])
    } else {
        $targetPoint=@(Get-GamePoint $mode $state.Goals[$state.Hits])
    }
    $size=Get-TargetSize (!$isSpace) $state.Hits
    $marker.Visibility='Visible'
    $marker.Width=$size; $marker.Height=$size
    $marker.Stroke = if ($state.HoldingSince -ge 0) {'#9FF6DC'} else {'#FFDC9B'}
    $marker.Opacity=if ($state.HoldingSince -ge 0) {1.0} else {0.82+0.13*[Math]::Sin($clock.ElapsedMilliseconds/340.0)}
    [Windows.Controls.Canvas]::SetLeft($marker,$targetPoint[0]-$size/2)
    [Windows.Controls.Canvas]::SetTop($marker,$targetPoint[1]-$size/2)
}
function Update-Game([long]$now) {
    Move-Arena $state.Position
    if (!$state.Round) { return }
    if ($state.Returning) {
        if ($state.Position -le 0.12) {
            $state.Returning = $false
            $ui.RoundStatus.Text = "Target $($state.Hits+1) of $($state.Goals.Count). Line up and hold."
        }
        return
    }
    $ferry = $ui.Game.SelectedIndex -ne 0
    if ($ferry) {
        $aligned = [Math]::Abs($state.Position - $state.Goals[$state.Hits]) -le ((Get-TargetSize $true $state.Hits)/960)
    } else {
        $target = $state.SpaceTargets[$state.Hits]
        $radius = (Get-TargetSize $false $state.Hits)/2
        $aligned = [Math]::Pow(245*($state.AimX-$target[0]),2) + [Math]::Pow(110*($state.AimY-$target[1]),2) -le $radius*$radius
    }
    if (!$aligned) {
        $state.HoldingSince = -1
        $ui.HoldProgress.Value = 0
        return
    }
    if ($state.HoldingSince -lt 0) { $state.HoldingSince = $now }
    $elapsed = $now - $state.HoldingSince
    $ui.HoldProgress.Value = [Math]::Min(100,100*$elapsed/$state.NeededMs)
    if ($elapsed -lt $state.NeededMs) { return }
    $state.ShotUntil = $now + 260
    $shot=@(Get-GamePoint $ui.Game.SelectedIndex $state.Position)
    $state.ShotX=$shot[0]
    $state.ShotY=$shot[1]
    $state.Hits++
    $state.HoldingSince = -1
    $ui.HoldProgress.Value = 0
    $ui.Bubble.Visibility = 'Collapsed'
    $ui.Dock.Visibility = 'Collapsed'
    $ui.Orb.Visibility = 'Collapsed'
    $ui.Crystal.Visibility = 'Collapsed'
    if ($state.Hits -eq $state.Goals.Count) {
        Record-Round
        Stop-Round
        $ui.CanvasHint.Text = 'Round complete'
        $ui.RoundStatus.Text = "Completed $($state.Hits) of $($state.Goals.Count) targets."
    } else {
        $state.Returning = $ferry
        $ui.RoundStatus.Text = if ($ferry) {"$($state.Hits) cleared. Return to rest."} else {"$($state.Hits) of 5 asteroids cleared. Aim at the next target."}
    }
}
$ui.RefreshPorts.Add_Click({ Update-Ports })
$ui.Progress.Add_Click({ Show-Progress })
$ui.Connect.Add_Click({
    if ($state.Port) {
        Close-Port
        Reset-Input
        $ui.ConnectionStatus.Text = 'USB disconnected'
        return
    }
    if (!$ui.Ports.SelectedItem) { $ui.ConnectionStatus.Text = 'No USB serial port selected'; return }
    $state.Preview = $false
    $ui.Preview.Content = 'Keyboard preview'
    Reset-Input
    try {
        $serial = [IO.Ports.SerialPort]::new([string]$ui.Ports.SelectedItem,115200)
        $serial.DtrEnable = $true
        $serial.Open()
        $state.Port = $serial
        $state.Last = -10000L
        $ui.Connect.Content = 'Disconnect'
        $ui.Ports.IsEnabled = $false
        $ui.RefreshPorts.IsEnabled = $false
        $ui.ConnectionStatus.Text = "Waiting for $($serial.PortName) data"
    } catch {
        if ($serial) { $serial.Dispose() }
        $ui.ConnectionStatus.Text = 'Could not open USB serial'
        $ui.Samples.Text = 'Close Arduino Serial Monitor, then reconnect.'
    }
})
$ui.Preview.Add_Click({
    Close-Port
    Reset-Input
    $state.Preview = !$state.Preview
    $state.PreviewPosition = 0.0
    $state.PreviewY = 0.0
    if ($state.Preview) {
        $state.Origin = [double[]]@(0,0,1)
        $state.Target = [double[]]@(0.5,0,0.87)
        $state.Up = [double[]]@(0,0.5,0.87)
        $state.AimCalibration=New-AimCalibration $state.Origin @(-0.5,0,1.13) $state.Target $state.Up @(0,-0.5,1.13)
        $ui.CalibrationStatus.Text = 'Preview profile loaded. Use the arrow keys.'
        $ui.Preview.Content = 'Exit preview'
        $window.Focus()
    } else {
        $ui.ConnectionStatus.Text = 'USB disconnected'
        $ui.Preview.Content = 'Keyboard preview'
    }
})
$window.Add_PreviewKeyDown({
    param($sender,$eventArgs)
    if (!$state.Preview) { return }
    switch ([string]$eventArgs.Key) {
        'Left'  { $state.PreviewPosition = [Math]::Max($(if ($ui.Game.SelectedIndex -ne 0) {0.0} else {-1.0}),$state.PreviewPosition-0.05) }
        'Right' { $state.PreviewPosition = [Math]::Min(1.0,$state.PreviewPosition+0.05) }
        'Up'    { $state.PreviewY = [Math]::Min(1.0,$state.PreviewY+0.05) }
        'Down'  { $state.PreviewY = [Math]::Max(-1.0,$state.PreviewY-0.05) }
        'Home'  { $state.PreviewPosition = 0.0; $state.PreviewY = 0.0 }
        default { return }
    }
    $eventArgs.Handled = $true
})
$ui.SetRest.Add_Click({ Start-Capture 'center' })
$ui.SetGoal.Add_Click({ Start-Capture 'right' })
$ui.SetUp.Add_Click({ Start-Capture 'up' })
$ui.SetLeft.Add_Click({ Start-Capture 'left' })
$ui.SetDown.Add_Click({ Start-Capture 'down' })
$ui.Game.Add_SelectionChanged({
    Stop-Round
    $ui.CanvasHint.Text = 'Select Start round to play'
    $ui.RoundStatus.Text = 'Ready when you are'
    Update-Route
})
$ui.Start.Add_Click({
    $state.Hits = 0
    $state.Level = $ui.Level.SelectedIndex+1
    $state.RoundStart = $clock.ElapsedMilliseconds
    $state.Round = $true
    $state.Returning = $false
    $state.HoldingSince = -1
    $state.NeededMs = 1000 * [double]::Parse($ui.HoldTime.SelectedItem.Content,[Globalization.CultureInfo]::InvariantCulture)
    $ui.CanvasHint.Text = ''
    $ui.RoundStatus.Text = "Target 1 of $($state.Goals.Count). Line up and hold."
    $ui.Stop.IsEnabled = $true
})
$ui.Stop.Add_Click({
    Record-Round
    Stop-Round
    $ui.CanvasHint.Text = 'Select Start round to play'
    $ui.RoundStatus.Text = "Round ended. $($state.Hits) targets cleared."
})
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(30)
$timer.Add_Tick({
    $now = $clock.ElapsedMilliseconds
    if ($state.Port) {
        try {
            $state.Buffer += $state.Port.ReadExisting()
            $lines = $state.Buffer.Split([char]10)
            $state.Buffer = $lines[-1]
            if ($state.Buffer.Length -gt 512) { $state.Buffer = '' }
            for ($i=0; $i -lt $lines.Length-1; $i++) {
                $vector = Read-Motion $lines[$i]
                if ($null -ne $vector) { Add-Sample $vector $now }
                elseif ($lines[$i] -match '^ERROR:') { $ui.Samples.Text = $lines[$i].Trim() }
            }
        } catch {
            Close-Port
            Reset-Input
            $ui.ConnectionStatus.Text = 'USB connection lost'
            $ui.Samples.Text = 'Reconnect the cable, refresh ports, and connect again.'
            Update-Ports
        }
    } elseif ($state.Preview) {
        Add-Sample @((0.50*$state.PreviewPosition),(0.50*$state.PreviewY),(1-0.13*($state.PreviewPosition+$state.PreviewY))) $now
    }
    $fresh = $now - $state.Last -lt 1000
    if ($fresh) {
        $ui.ConnectionStatus.Text = if ($state.Preview) {'Keyboard preview'} else {"Live USB • $($state.Port.PortName)"}
        $ui.Samples.Text = ('X {0:+0.00;-0.00;0.00}  Y {1:+0.00;-0.00;0.00}  Z {2:+0.00;-0.00;0.00} g' -f $state.Filter[0],$state.Filter[1],$state.Filter[2]) + "`n$($state.Samples) samples received"
    } elseif ($state.Port -and $state.Samples -gt 0) {
        $ui.ConnectionStatus.Text = 'USB connected • data paused'
        if ($state.Round) { Stop-Round; $ui.RoundStatus.Text = 'Input paused. Start a new round when it returns.' }
    }
    if ($state.Capture -and $now -ge $state.Capture.Until) { Complete-Capture }
    $ui.SetRest.IsEnabled = $fresh -and !$state.Capture -and !$state.Preview
    $ui.SetGoal.IsEnabled = $ui.SetRest.IsEnabled -and $null -ne $state.Origin
    $ui.SetUp.IsEnabled = $ui.SetGoal.IsEnabled
    $ui.SetDown.IsEnabled = $ui.SetGoal.IsEnabled
    $ui.SetLeft.IsEnabled = $ui.SetGoal.IsEnabled
    $ferry = $ui.Game.SelectedIndex -ne 0
    $calibrated = $null -ne $state.Target -and ($ferry -or $null -ne $state.AimCalibration)
    $ui.Level.IsEnabled = !$state.Round
    $ui.Start.IsEnabled = $fresh -and $calibrated -and !$state.Capture -and !$state.Round
    if ($fresh -and $calibrated) {
        $state.Position = Get-Position $state.Filter $state.Origin $state.Target
        if (!$ferry) {
            $aim = @(Get-CalibratedAim $state.Filter $state.Origin $state.AimCalibration)
            $state.AimX=$aim[0]; $state.AimY=$aim[1]
        }
        $ui.Travel.Value = if ($ferry) {100*$state.Position} else {100*[Math]::Min(1,[Math]::Sqrt($state.AimX*$state.AimX+$state.AimY*$state.AimY))}
    } else {
        $state.Position = 0
        $ui.Travel.Value = 0
    }
    if ($fresh -and !$calibrated) {
        $baseline = if ($state.Origin) { $state.Origin } else { $state.LiveOrigin }
        $distance = 0.0
        for ($axis = 0; $axis -lt 3; $axis++) {
            $distance += [Math]::Pow($state.Filter[$axis] - $baseline[$axis],2)
        }
        $state.Position = [Math]::Min(1.0,[Math]::Sqrt($distance) / 0.55)
        $ui.Travel.Value = $state.Position * 100
        if (!$ferry) {
            $right = $state.Target
            if (!$right) {
                $axes = @(0,1,2) | Sort-Object { [Math]::Abs($baseline[$_]) }
                $right = [double[]]$baseline.Clone()
                $right[$axes[0]] += 0.35
                $up = [double[]]$baseline.Clone()
                $up[$axes[1]] += 0.35
            } else {
                $r = for ($axis = 0; $axis -lt 3; $axis++) { $right[$axis] - $baseline[$axis] }
                $up = @(
                    $baseline[0] + $baseline[1]*$r[2] - $baseline[2]*$r[1]
                    $baseline[1] + $baseline[2]*$r[0] - $baseline[0]*$r[2]
                    $baseline[2] + $baseline[0]*$r[1] - $baseline[1]*$r[0]
                )
            }
            $aim = @(Get-Aim $state.Filter $baseline $right $up)
            if ($aim.Count -eq 2) { $state.AimX=$aim[0]; $state.AimY=$aim[1] }
        }
        $ui.CanvasHint.Text = if ($ferry) {'Live USB. Set center and right.'} else {'Live preview. Capture all five poses.'}
    } elseif ($fresh -and $calibrated -and $ui.CanvasHint.Text -like 'Live *') {
        $ui.CanvasHint.Text = 'Select Start round to play'
    }
    Update-Game $now
})
$window.Add_Closed({ $timer.Stop(); Close-Port })
Update-Ports
Show-Today
Update-Route
Select-Exercise 0
if (!$SmokeTest) {
    $ui.Arcade.Visibility='Collapsed'
    $ui.ArcadeHeader.Visibility='Collapsed'
} else {
    $ui.HomeButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    if ($ui.Landing.Visibility -ne 'Visible') { throw 'Movement library failed to open' }
    for ($routeIndex=0;$routeIndex -lt $routes.Count;$routeIndex++) {
        $ui.Injury.SelectedIndex=$routeIndex+1
        $ui.Exercise.SelectedIndex=$routeIndex
        $ui.Begin.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ($ui.Arcade.Visibility -ne 'Visible' -or $ui.ArenaTitle.Text -ne $routes[$routeIndex].Name -or $ui.SceneHost.Child -isnot [Windows.Controls.Viewport3D]) {
            throw "Movement route $routeIndex failed"
        }
        $ui.HomeButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    }
    Open-Arcade 0
}
$timer.Start()
if ($SmokeTest) {
    $check = @{ Step='connect'; Since=0L; Result=$null; HardwareSamples=0; Game=0; LastHits=0 }
    $tester = [Windows.Threading.DispatcherTimer]::new()
    $tester.Interval = [TimeSpan]::FromMilliseconds(70)
    $tester.Add_Tick({
        try {
            $time = $clock.ElapsedMilliseconds
            if ($time -gt 65000) { throw "Timed out during $($check.Step), game $($check.Game), hits $($state.Hits), aim $($state.AimX),$($state.AimY), position $($state.Position)" }
            switch ($check.Step) {
                'connect' {
                    if ($PreviewOnly) {
                        $ui.Preview.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                        $ui.HoldTime.SelectedIndex = 0
                        $check.Step = 'start-game'
                        return
                    }
                    if (!$ui.Ports.SelectedItem) { throw 'No USB serial port available' }
                    $ui.Connect.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                    if (!$state.Port) { throw "Serial open failed: $($ui.Samples.Text)" }
                    $check.Step = 'samples'
                }
                'samples' {
                    if ($state.Samples -ge 12) {
                        $magnitude = [Math]::Sqrt(($state.Filter | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum)
                        if ($magnitude -lt 0.5 -or $magnitude -gt 1.5) { throw "Unexpected accelerometer magnitude: $magnitude g" }
                        $check.HardwareSamples = $state.Samples
                        $ui.SetRest.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                        $check.Step = 'rest'
                    } elseif ($time -gt 6500) { throw "No live motion rows: $($ui.Samples.Text)" }
                }
                'rest' {
                    if (!$state.Capture) {
                        if (!$state.Origin) { throw "Rest capture failed: $($ui.CalibrationStatus.Text)" }
                        $ui.Preview.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                        $ui.HoldTime.SelectedIndex = 0
                        $check.Step = 'start-game'
                    }
                }
                'start-game' {
                    if ($ui.Start.IsEnabled) {
                        $ui.Game.SelectedIndex = $check.Game
                        $ui.Level.SelectedIndex = $check.Game % 3
                        $ui.Start.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                        $check.LastHits = 0
                        $check.Step = 'play'
                    }
                }
                'play' {
                    if ($state.Round) {
                        if ($state.Returning) { $state.PreviewPosition = 0.0 }
                        elseif ($check.Game -ne 0) { $state.PreviewPosition = $state.Goals[$state.Hits] }
                        else { $state.PreviewPosition = $state.SpaceTargets[$state.Hits][0]; $state.PreviewY = $state.SpaceTargets[$state.Hits][1] }
                    } else {
                        if ($state.Hits -ne 5 -or $ui.CanvasHint.Text -ne 'Round complete') { throw 'Game did not complete all five targets' }
                        if ($check.Game -lt 3) {
                            $check.Game++
                            $state.PreviewPosition = 0.0
    $state.PreviewY = 0.0
                            $check.Step = 'start-game'
                        } else {
                            $check.Result = "PASS: $($check.HardwareSamples) live USB samples; captured real rest pose; completed five targets in all four games in preview."
                            if ($PreviewOnly) { $check.Result = "PASS: Completed all four five-target games in keyboard preview." }
                            $tester.Stop()
                            $window.Close()
                        }
                    }
                }
            }
        } catch {
            $check.Result = "FAIL: $($_.Exception.Message)"
            $tester.Stop()
            $window.Close()
        }
    })
    $tester.Start()
}
if (!$SmokeTest) {
    $window.Add_Loaded({
        if ($ui.Ports.Items.Contains('COM26')) {
            $ui.Ports.SelectedItem = 'COM26'
            $ui.Connect.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        }
    })
}
[void]$window.ShowDialog()
if ($SmokeTest) {
    $check.Result
    if ($check.Result -notlike 'PASS:*') { exit 1 }
}


















