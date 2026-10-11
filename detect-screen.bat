<# : ---- Windows batch launcher (do not edit these lines) ----
@echo off
chcp 65001 >nul
set "R11_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:R11_SELF, [Text.Encoding]::UTF8))"
echo.
pause
exit /b
#>
# ======================================================================
#  «Размер 1:1» — определение точного физического размера мониторов.
#  Читает EDID (паспорт монитора) из реестра Windows — без прав администратора.
#  Результат: файл screen-data.js рядом с программой + копия в буфере обмена.
# ======================================================================
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = Split-Path -Parent $env:R11_SELF

function Parse-Edid([byte[]]$e) {
  if (-not $e -or $e.Length -lt 128) { return $null }
  if ($e[0] -ne 0 -or $e[1] -ne 255) { return $null }          # заголовок EDID 00 FF FF FF FF FF FF 00
  $o = 54                                                      # первый Detailed Timing Descriptor
  $x  = $e[$o+2]  + (($e[$o+4]  -band 0xF0) -shl 4)            # пикселей по горизонтали
  $y  = $e[$o+5]  + (($e[$o+7]  -band 0xF0) -shl 4)            # пикселей по вертикали
  $w  = $e[$o+12] + (($e[$o+14] -band 0xF0) -shl 4)            # ширина изображения, мм
  $h  = $e[$o+13] + (($e[$o+14] -band 0x0F) -shl 8)            # высота изображения, мм
  if ($w -lt 50 -or $h -lt 30) { $w = $e[21] * 10; $h = $e[22] * 10 }   # запасной вариант — сантиметры
  $name = ''
  foreach ($d in 54, 72, 90, 108) {                             # дескриптор 0xFC — имя модели
    if ($e[$d] -eq 0 -and $e[$d+1] -eq 0 -and $e[$d+3] -eq 0xFC) {
      $name = ([Text.Encoding]::ASCII.GetString($e, $d + 5, 13) -split "`n")[0].Trim()
    }
  }
  if (-not $name) {                                             # иначе — код производителя
    $m = ($e[8] -shl 8) + $e[9]
    $name = -join ((($m -shr 10) -band 31), (($m -shr 5) -band 31), ($m -band 31) | ForEach-Object { [char](64 + $_) })
  }
  $name = $name -replace '[^\w\s\.\-\+]', ''
  [pscustomobject]@{ n = $name; w = $w; h = $h; x = $x; y = $y }
}

$list = @()
# 1) Только подключённые сейчас мониторы (WMI) -> их EDID в реестре
$active = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
foreach ($m in $active) {
  $inst = $m.InstanceName -replace '_\d+$', ''
  $key  = "HKLM:\SYSTEM\CurrentControlSet\Enum\$inst\Device Parameters"
  $e = (Get-ItemProperty -LiteralPath $key -Name EDID -ErrorAction SilentlyContinue).EDID
  $p = Parse-Edid $e
  if ($p) { $list += $p }
}
# 2) Запасной путь: все мониторы из реестра (могут попасть и ранее подключавшиеся)
if ($list.Count -eq 0) {
  Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY' -ErrorAction SilentlyContinue | ForEach-Object {
    Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
      $e = (Get-ItemProperty -LiteralPath (Join-Path $_.PSPath 'Device Parameters') -Name EDID -ErrorAction SilentlyContinue).EDID
      $p = Parse-Edid $e
      if ($p) { $list += $p }
    }
  }
}
$list = @($list | Sort-Object n, w, h, x, y -Unique)

if ($list.Count -eq 0) {
  Write-Host 'Не удалось прочитать данные монитора. Используйте калибровку по банковской карте.' -ForegroundColor Yellow
  exit
}
Write-Host ''
Write-Host 'Найдены мониторы:' -ForegroundColor Green
foreach ($s in $list) {
  $diag = [math]::Round([math]::Sqrt($s.w * $s.w + $s.h * $s.h) / 25.4, 1)
  Write-Host ("  {0}: {1} x {2} мм ({3}`"), {4}x{5} px" -f $s.n, $s.w, $s.h, $diag, $s.x, $s.y)
}
$json = ConvertTo-Json @($list) -Compress
if ($json -notmatch '^\[') { $json = "[$json]" }
Set-Content -LiteralPath (Join-Path $dir 'screen-data.js') -Value "window.SCREEN_EDID = $json;" -Encoding UTF8
try { Set-Clipboard -Value "R11:$json" } catch { "R11:$json" | clip }
Write-Host ''
Write-Host 'Готово! Данные сохранены в screen-data.js и скопированы в буфер обмена.' -ForegroundColor Green
Write-Host 'Открываю программу... (если она уже открыта — нажмите в ней Ctrl+V)'
$html = Join-Path $dir 'razmer.html'
if (Test-Path $html) { Start-Process $html }
