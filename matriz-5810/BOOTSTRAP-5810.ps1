<#
=====================================================================
  BOOTSTRAP MATRIZ - DELL PRECISION TOWER 5810
  Deja esta maquina como MATRIZ de sesiones de Claude Code.

  REGLA QUE NO SE ROMPE: esta maquina solo BAJA de Google Drive.
  Aqui esa regla no depende de la disciplina: el remoto se crea con
  scope=drive.readonly, asi que Google rechaza cualquier escritura
  aunque alguien corra el script equivocado por error.

  Hace, de principio a fin:
    1. Instala rclone si falta (winget)
    2. Crea/valida el remoto gdrive en modo SOLO LECTURA
    3. Verifica que se vea CLON-PC
    4. Baja consolidar-en-5810.ps1 y CONSOLIDAR-5810.cmd de _CONSOLIDAR
    5. Neutraliza cualquier copia del script que SUBE
    6. Corre la consolidacion original (sin modificarla)
    7. Genera el REPORTE DE PROCEDENCIA: que carpeta vino de que maquina
       (esto el script original NO lo hace)

  Es aditivo e idempotente. Se puede correr las veces que quieras.
=====================================================================
#>

[CmdletBinding()]
param(
  # 'drive.readonly' = esta maquina fisicamente no puede subir. Recomendado.
  # 'drive'          = lectura y escritura. Solo si sabes por que lo quieres.
  [ValidateSet('drive.readonly','drive')]
  [string]$Scope = 'drive.readonly',

  # Baja y reporta, pero NO fusiona nada en .claude. Para ver antes de tocar.
  [switch]$SoloReporte,

  # Salta el paso de winget (si ya tienes rclone puesto a mano)
  [switch]$SaltarInstalacion
)

# 'Continue' a proposito: con 'Stop', un comando nativo con 2>&1 hace que
# PowerShell 5.1 lance NativeCommandError y aborte. Los errores se revisan
# explicitamente con $LASTEXITCODE.
$ErrorActionPreference = 'Continue'

$Remoto     = 'gdrive'
$DriveRoot  = "${Remoto}:CLON-PC"
$Stage      = Join-Path $env:USERPROFILE 'claude-consolidacion'
$Target     = Join-Path $env:USERPROFILE '.claude'
$Reporte    = Join-Path $env:USERPROFILE 'MATRIZ-5810-PROCEDENCIA.txt'

function Titulo($t) {
  Write-Host ''
  Write-Host ('=' * 68) -ForegroundColor Cyan
  Write-Host "  $t" -ForegroundColor Cyan
  Write-Host ('=' * 68) -ForegroundColor Cyan
}
function Ok($m)    { Write-Host "  [OK]    $m" -ForegroundColor Green }
function Aviso($m) { Write-Host "  [AVISO] $m" -ForegroundColor Yellow }
function Malo($m)  { Write-Host "  [ALTO]  $m" -ForegroundColor Red }
function Info($m)  { Write-Host "          $m" -ForegroundColor Gray }

Titulo 'MATRIZ 5810 - CONSOLIDACION DE SESIONES DE CLAUDE CODE'
Write-Host "  Maquina    : $env:COMPUTERNAME"
Write-Host "  Usuario    : $env:USERNAME"
Write-Host "  Destino    : $Target"
Write-Host "  Modo Drive : $Scope"
if ($SoloReporte) { Aviso 'MODO SOLO REPORTE: no se fusionara nada en .claude' }

# ------------------------------------------------------------------
# 1) rclone
# ------------------------------------------------------------------
Titulo '1/7  rclone'
$rclone = Get-Command rclone -ErrorAction SilentlyContinue
if (-not $rclone) {
  if ($SaltarInstalacion) { Malo 'No hay rclone y se pidio saltar la instalacion.'; exit 1 }
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Malo 'No hay rclone ni winget. Instala rclone a mano: https://rclone.org/downloads/'
    exit 1
  }
  Info 'Instalando rclone con winget...'
  winget install --id Rclone.Rclone --exact --accept-source-agreements --accept-package-agreements
  # winget no refresca el PATH de la sesion actual; lo reconstruimos.
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path','User')
  $rclone = Get-Command rclone -ErrorAction SilentlyContinue
  if (-not $rclone) {
    Malo 'rclone se instalo pero no aparece en el PATH de esta ventana.'
    Info  'Cierra PowerShell, abrelo de nuevo y vuelve a correr este script.'
    exit 1
  }
}
Ok ("rclone listo: " + (rclone version | Select-Object -First 1))

# ------------------------------------------------------------------
# 2) Remoto de Google Drive (solo lectura)
# ------------------------------------------------------------------
Titulo '2/7  Conexion a Google Drive (cuenta ab@riskmathics.com)'
$remotos = (rclone listremotes) -join "`n"
if ($remotos -match ("(?m)^" + [regex]::Escape($Remoto) + ":")) {
  Ok "El remoto '$Remoto' ya existe. No se vuelve a autorizar."
  $scopeActual = (rclone config show $Remoto | Select-String -Pattern '^scope\s*=' | Select-Object -First 1)
  if ($scopeActual) { Info ("scope guardado -> " + ($scopeActual.ToString().Trim())) }
  Info "Si falla la lectura, reautoriza con:  rclone config reconnect ${Remoto}:"
} else {
  Aviso 'Se va a abrir el navegador. Autoriza con ab@riskmathics.com.'
  Aviso 'Si pregunta por Shared Drive / Team Drive, responde: n'
  Info  ''
  Info  'Creando remoto en modo SOLO LECTURA...'
  # rclone config create imprime el remoto COMPLETO en stdout al terminar,
  # token y refresh_token incluidos. El refresh_token no expira solo: quien lo
  # tenga lee el Drive hasta que se revoque. Se descarta stdout para que no
  # quede en pantalla ni en un copiado accidental. Los avisos del navegador
  # van por stderr y se siguen viendo.
  rclone config create $Remoto drive scope=$Scope | Out-Null
  if ($LASTEXITCODE -ne 0) { Malo 'Fallo la creacion del remoto.'; exit 1 }
  Ok 'Remoto creado. El token quedo en rclone.conf, no se imprime aqui.'
}

# ------------------------------------------------------------------
# 3) Verificar que se vea CLON-PC
# ------------------------------------------------------------------
Titulo '3/7  Verificando acceso a CLON-PC'
$carpetas = rclone lsd $DriveRoot 2>&1
if ($LASTEXITCODE -ne 0) {
  Malo "No se pudo leer $DriveRoot"
  Info  $carpetas
  Info  "Reautoriza con:  rclone config reconnect ${Remoto}:"
  exit 1
}
$maquinasDrive = @()
foreach ($l in $carpetas) {
  $t = $l.ToString().Trim()
  if ($t -match '^-?\d+\s+\S+\s+\S+\s+-?\d+\s+(.+?)\s*$') { $maquinasDrive += $Matches[1] }
}
Ok ("Maquinas visibles en Drive: " + $maquinasDrive.Count)
foreach ($m in $maquinasDrive) { Info " - $m" }

# ------------------------------------------------------------------
# 4) Bajar las herramientas de _CONSOLIDAR
# ------------------------------------------------------------------
Titulo '4/7  Bajando herramientas de _CONSOLIDAR'
rclone copy "$DriveRoot/_CONSOLIDAR" $env:USERPROFILE `
  --include 'consolidar-en-5810.ps1' --include 'CONSOLIDAR-5810.cmd' --include 'LEEME-5810.txt'
$ps1Local = Join-Path $env:USERPROFILE 'consolidar-en-5810.ps1'
if (-not (Test-Path $ps1Local)) { Malo "No llego $ps1Local"; exit 1 }
Ok "Herramientas en $env:USERPROFILE"

# El script se ejecuta con -ExecutionPolicy Bypass, asi que conviene saber si
# cambio desde que se audito. No bloquea: solo avisa.
$shaAuditado = 'cc01620a97aa6d0922e319c9a59b1094fd9ca520d0a5a4f87abc444746c8f8d2'
$shaAhora = (Get-FileHash -LiteralPath $ps1Local -Algorithm SHA256).Hash.ToLower()
if ($shaAhora -eq $shaAuditado) {
  Ok 'consolidar-en-5810.ps1 coincide con la version auditada.'
} else {
  Aviso 'consolidar-en-5810.ps1 CAMBIO en Drive desde la auditoria.'
  Info  "  auditado: $shaAuditado"
  Info  "  ahora   : $shaAhora"
  Info  '  Los hallazgos del README pueden ya no aplicar. Revisalo antes de seguir.'
}

# ------------------------------------------------------------------
# 5) Neutralizar el script que SUBE
# ------------------------------------------------------------------
Titulo '5/7  Blindaje: desactivando el script de SUBIDA'
$subidores = @()
$subidores += Get-ChildItem -Path $env:USERPROFILE -Filter 'subir-claude-a-drive.cmd' -File -ErrorAction SilentlyContinue
if (Test-Path $Stage) {
  $subidores += Get-ChildItem -Path $Stage -Filter 'subir-claude-a-drive.cmd' -File -Recurse -ErrorAction SilentlyContinue
}
if ($subidores.Count -gt 0) {
  foreach ($s in $subidores) {
    $bloqueado = "$($s.FullName).BLOQUEADO-EN-LA-MATRIZ"
    Move-Item $s.FullName $bloqueado -Force
    Aviso ("Desactivado: " + $s.FullName)
  }
} else {
  Ok 'No hay copias del script de subida en esta maquina.'
}
if ($Scope -eq 'drive.readonly') {
  Ok 'Ademas, el remoto es de solo lectura: Google rechaza cualquier subida.'
}

# ------------------------------------------------------------------
# 6) Consolidacion
# ------------------------------------------------------------------
if ($SoloReporte) {
  Titulo '6/7  Descarga sin fusionar (modo solo reporte)'
  Info 'Bajando todo a la zona de preparacion, sin tocar .claude...'
  rclone copy $DriveRoot $Stage --transfers 12 --checkers 20 --drive-chunk-size 32M --progress
  Ok 'Descarga lista. NO se fusiono nada.'
} else {
  Titulo '6/7  Corriendo la consolidacion original'
  Info 'Se ejecuta consolidar-en-5810.ps1 tal cual viene de Drive.'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $ps1Local
  $codigoHijo = $LASTEXITCODE
  if ($codigoHijo -ne 0) {
    Malo "La consolidacion fallo (codigo $codigoHijo). NO se completo la fusion."
    Info 'Revisa consolidacion-5810.log y consolidacion-5810-REPORTE.txt.'
    Aviso 'Se genera el reporte de procedencia de todos modos, con lo que alcanzo a copiarse.'
  } else {
    Ok 'Consolidacion terminada.'
  }
}

# ------------------------------------------------------------------
# 7) REPORTE DE PROCEDENCIA  (lo que el script original no entrega)
# ------------------------------------------------------------------
Titulo '7/7  Reporte de procedencia: que carpeta vino de que maquina'

if (-not (Test-Path $Stage)) { Malo "No existe $Stage. Nada que reportar."; exit 1 }

# Un transcript de SESION es un <uuid>.jsonl suelto en la raiz de la carpeta
# de proyecto. Lo que cuelga mas abajo (subagents\..., agent-*.jsonl,
# journal.jsonl) son transcripts de SUBAGENTE, marcados isSidechain, y no son
# sesiones. Contar en recursivo infla el numero; contar solo la raiz es lo
# correcto. Se reportan por separado para no esconder nada.
function Contar-Sesiones($dir) {
  @(Get-ChildItem -LiteralPath $dir -Filter *.jsonl -File -ErrorAction SilentlyContinue).Count
}
function Contar-Subagentes($dir) {
  $todos = @(Get-ChildItem -LiteralPath $dir -Filter *.jsonl -File -Recurse -ErrorAction SilentlyContinue).Count
  $raiz  = @(Get-ChildItem -LiteralPath $dir -Filter *.jsonl -File -ErrorAction SilentlyContinue).Count
  return ($todos - $raiz)
}

# mapa: carpeta de proyecto -> lista de { maquina, ruta, sesiones }
$mapa = @{}
$usuariosVistos = @{}

foreach ($maq in Get-ChildItem $Stage -Directory) {
  if ($maq.Name -eq '_CONSOLIDAR') { continue }
  $base = Join-Path $maq.FullName '06-Claude-Trabajo'
  if (-not (Test-Path $base)) { continue }

  # Los respaldos no tienen la misma forma: se revisan las dos ubicaciones.
  $candidatos = @(
    @{ Ruta = (Join-Path $base 'projects');                Etiqueta = 'projects/' },
    @{ Ruta = (Join-Path $base 'dot-claude\projects');     Etiqueta = 'dot-claude/projects/' }
  )

  foreach ($c in $candidatos) {
    if (-not (Test-Path $c.Ruta)) { continue }
    foreach ($pf in Get-ChildItem $c.Ruta -Directory) {
      $n = $pf.Name
      $ses = Contar-Sesiones $pf.FullName
      $sub = Contar-Subagentes $pf.FullName
      if (-not $mapa.ContainsKey($n)) { $mapa[$n] = @() }
      $mapa[$n] += [pscustomobject]@{
        Maquina  = $maq.Name
        Origen   = $c.Etiqueta
        Sesiones = $ses
        Subagentes = $sub
      }
      # Deteccion de usuario ajeno SIN depender de una lista de carpetas conocidas.
      if ($n -match '^[A-Za-z]--Users-(.+)$') {
        $resto = $Matches[1]
        $partes = $resto -split '-'
        $probable = if ($partes.Count -ge 2) { ($partes[0..1] -join '-') } else { $partes[0] }
        if (-not $usuariosVistos.ContainsKey($probable)) { $usuariosVistos[$probable] = 0 }
        $usuariosVistos[$probable] += $ses
      }
    }
  }
}

$lineas = New-Object System.Collections.Generic.List[string]
$lineas.Add("REPORTE DE PROCEDENCIA - MATRIZ 5810")
$lineas.Add("Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$lineas.Add("Maquina : $env:COMPUTERNAME   Usuario: $env:USERNAME")
$lineas.Add('')

# --- resumen por maquina ---
$lineas.Add('--- SESIONES POR MAQUINA DE ORIGEN ---')
$porMaquina = @{}
foreach ($k in $mapa.Keys) {
  foreach ($e in $mapa[$k]) {
    if (-not $porMaquina.ContainsKey($e.Maquina)) { $porMaquina[$e.Maquina] = 0 }
    $porMaquina[$e.Maquina] += $e.Sesiones
  }
}
foreach ($m in ($porMaquina.Keys | Sort-Object)) {
  $lineas.Add(("  {0,-32} {1,6} sesiones" -f $m, $porMaquina[$m]))
}
$lineas.Add('')

# --- maquinas que estan en Drive pero no aportaron nada reconocible ---
# El escaneo solo entiende <maquina>\06-Claude-Trabajo\projects y
# ...\dot-claude\projects. Si un respaldo tiene otra forma, hay que decirlo:
# un reporte limpio no debe leerse como "esa maquina no traia sesiones".
$sinReconocer = @()
foreach ($md in $maquinasDrive) {
  if ($md -eq '_CONSOLIDAR') { continue }
  if (-not $porMaquina.ContainsKey($md)) { $sinReconocer += $md }
}
if ($sinReconocer.Count -gt 0) {
  $lineas.Add('--- MAQUINAS EN DRIVE SIN SESIONES RECONOCIDAS ---')
  $lineas.Add('  Estan en CLON-PC pero su respaldo no tiene la forma esperada')
  $lineas.Add('  (06-Claude-Trabajo\projects o 06-Claude-Trabajo\dot-claude\projects).')
  $lineas.Add('  NO concluyas que no traian sesiones: revisa su carpeta a mano en')
  $lineas.Add("    $Stage")
  foreach ($md in $sinReconocer) { $lineas.Add("    - $md") }
  $lineas.Add('')
}

# --- carpetas que aparecen en mas de una maquina ---
$compartidas = $mapa.Keys | Where-Object { ($mapa[$_] | Select-Object -ExpandProperty Maquina -Unique).Count -gt 1 }
$lineas.Add('--- CARPETAS PRESENTES EN VARIAS MAQUINAS (se fusionaron) ---')
if ($compartidas) {
  foreach ($k in ($compartidas | Sort-Object)) {
    $ms = ($mapa[$k] | Select-Object -ExpandProperty Maquina -Unique) -join ' + '
    $lineas.Add(("  {0}`n      <- {1}" -f $k, $ms))
  }
} else {
  $lineas.Add('  (ninguna: cada carpeta vino de una sola maquina)')
}
$lineas.Add('')

# --- detalle completo ---
$lineas.Add('--- DETALLE: CADA CARPETA Y SU MAQUINA DE ORIGEN ---')
$lineas.Add('  ses. = sesiones reales | sub. = transcripts de subagente (no son sesiones)')
foreach ($k in ($mapa.Keys | Sort-Object)) {
  foreach ($e in $mapa[$k]) {
    $lineas.Add(("  {0,-28} {1,-22} {2,4} ses. {3,5} sub.  {4}" -f $e.Maquina, $e.Origen, $e.Sesiones, $e.Subagentes, $k))
  }
}
$lineas.Add('')

# --- usuarios de Windows detectados ---
$lineas.Add('--- USUARIOS DE WINDOWS DETECTADOS EN LAS RUTAS ---')
$lineas.Add('  (el nombre es una lectura de la ruta codificada, no una certeza)')
foreach ($u in ($usuariosVistos.Keys | Sort-Object)) {
  $lineas.Add(("  {0,-28} {1,5} sesiones" -f $u, $usuariosVistos[$u]))
}
$lineas.Add('')
$lineas.Add('  Si aqui aparece un usuario que no es tuyo (p.ej. Ricardo-Villa),')
$lineas.Add('  sus carpetas SI se copiaron. Para quitarlas, borra en:')
$lineas.Add("    $Target\projects")
$lineas.Add('  las carpetas que empiecen con ese nombre de usuario.')
$lineas.Add('')

# --- totales reales en destino ---
if (Test-Path (Join-Path $Target 'projects')) {
  $destProj = Get-ChildItem (Join-Path $Target 'projects') -Directory -ErrorAction SilentlyContinue
  $destSes = ($destProj | ForEach-Object { Contar-Sesiones $_.FullName } | Measure-Object -Sum).Sum
  $destSub = ($destProj | ForEach-Object { Contar-Subagentes $_.FullName } | Measure-Object -Sum).Sum
  $lineas.Add('=== TOTAL EN ESTA MAQUINA ===')
  $lineas.Add(("  Carpetas de proyecto : {0}" -f $destProj.Count))
  $lineas.Add(("  SESIONES             : {0}" -f $destSes))
  $lineas.Add(("  (transcripts de subagente, aparte: {0})" -f $destSub))
} else {
  $lineas.Add('=== TOTAL EN ESTA MAQUINA ===')
  $lineas.Add('  (todavia no se ha fusionado nada: corriste en modo -SoloReporte)')
}

$lineas | Set-Content -Path $Reporte -Encoding UTF8
$lineas | ForEach-Object { Write-Host $_ }

Write-Host ''
Ok "Reporte guardado en: $Reporte"
if (-not $SoloReporte) {
  Aviso 'Reinicia Claude Code para que lea las sesiones nuevas.'
  Info  'Tu .claude.json NO se toco. Las copias .claude.json.DE-<maquina>'
  Info  'estan en tu carpeta de usuario para que jales los MCP a mano.'
}
