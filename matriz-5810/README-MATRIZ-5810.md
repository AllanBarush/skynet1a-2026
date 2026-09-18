# Matriz 5810 — consolidación de sesiones de Claude Code

Deja la Dell Precision Tower 5810 como **matriz**: la única máquina que baja
las sesiones de todas las demás y las fusiona.

**Regla que no se rompe:** la 5810 solo baja. Nunca sube.

---

## Uso

En la 5810, en PowerShell, en tu carpeta de usuario:

```powershell
# 1. Ver qué va a pasar, sin tocar nada
.\BOOTSTRAP-5810.ps1 -SoloReporte

# 2. Consolidar de verdad
.\BOOTSTRAP-5810.ps1
```

Al terminar, **reinicia Claude Code**.

El reporte queda en `%USERPROFILE%\MATRIZ-5810-PROCEDENCIA.txt`.

---

## Qué hace, paso por paso

| # | Paso | Nota |
|---|------|------|
| 1 | Instala rclone con winget si falta | Reconstruye el PATH; si aun así no aparece, pide reabrir PowerShell |
| 2 | Crea el remoto `gdrive` | **`scope=drive.readonly`** por defecto |
| 3 | Verifica `rclone lsd gdrive:CLON-PC` | Aborta si no se ve |
| 4 | Baja las herramientas de `_CONSOLIDAR` | Solo los 3 archivos que hacen falta. Caen en la raíz de tu carpeta de usuario y **se sobrescriben** si ya existen ahí: no edites esas copias, la de Drive manda |
| 5 | Desactiva cualquier `subir-claude-a-drive.cmd` | Lo renombra a `.BLOQUEADO-EN-LA-MATRIZ` |
| 6 | Corre `consolidar-en-5810.ps1` **sin modificarlo** | El comportamiento que ya conoces |
| 7 | Genera el reporte de procedencia | Carpeta → máquina de origen |

---

## Las dos cosas que este bootstrap agrega

### 1. La regla deja de depender de la disciplina

El remoto se crea con `scope=drive.readonly`. Con ese scope, Google rechaza
toda escritura al nivel de la API. Aunque alguien corra el script equivocado
en la 5810, no hay subida posible.

Efecto secundario buscado: `subir-claude-a-drive.cmd` deja de funcionar en
esta máquina. Es exactamente lo que quieres en la matriz.

Si algún día necesitas escritura desde la 5810:

```powershell
rclone config update gdrive scope drive
rclone config reconnect gdrive:
```

### 2. El reporte de procedencia

El script original imprime un total de sesiones, pero **no dice de qué
máquina vino cada carpeta**. El reporte nuevo trae cuatro secciones:

- Sesiones por máquina de origen
- Carpetas presentes en varias máquinas, que se fusionaron en una sola
- Detalle de cada carpeta con su máquina y su conteo
- Usuarios de Windows detectados en las rutas codificadas

---

## Qué avisa el bootstrap cuando algo no cuadra

No se limita a correr: verifica y te dice.

- **Si `consolidar-en-5810.ps1` cambió en Drive** desde que se auditó, lo avisa
  comparando el sha256. No bloquea, pero los hallazgos de abajo podrían ya no
  aplicar.
- **Si la consolidación falla**, lo dice con el código de salida en vez de
  imprimir "terminada". El script se lanza como proceso aparte, así que un fallo
  suyo no detiene al bootstrap por sí solo: hay que revisar el código de salida
  a propósito.
- **Si una máquina de Drive no aporta nada reconocible**, aparece en una sección
  propia. El escaneo entiende `06-Claude-Trabajo\projects` y
  `06-Claude-Trabajo\dot-claude\projects`. Un respaldo con otra forma se
  saltaría en silencio, y un reporte limpio se leería como "esa máquina no traía
  sesiones". Por eso se nombra explícitamente.

---

## Auditoría del script original

Se revisó `consolidar-en-5810.ps1` (5367 bytes, sha256
`cc01620a97aa6d0922e319c9a59b1094fd9ca520d0a5a4f87abc444746c8f8d2`).

### Lo que está bien

- `rclone copy gdrive:CLON-PC <local>` es descarga pura. `copy` no borra en
  destino ni escribe en origen. La regla se respeta.
- `robocopy /E /XC /XN /XO` copia únicamente archivos que no existen en
  destino. Es el idiom documentado por Microsoft para "solo lo nuevo".
- El merge de transcripts salta cualquier archivo que ya exista. No machaca
  nada de lo que ya está en el disco de la 5810.
- `.claude.json` no se toca. Quedan copias `.claude.json.DE-<maquina>`.
- No renombra carpetas de proyecto, a propósito.

### Lo que no está bien

**1. No reporta procedencia.** Es el hueco que más importa: no hay forma de
saber de qué máquina vino cada carpeta. Resuelto por el paso 7.

**2. El conteo de sesiones es frágil, y el arreglo obvio es peor.**
`Get-ChildItem -Filter *.jsonl` sin `-Recurse` solo cuenta los `.jsonl` sueltos
en la raíz de cada carpeta de proyecto.

La tentación es agregar `-Recurse`. Sería un error. Claude Code guarda bajo
`<proyecto>/<sesión>/subagents/.../agent-*.jsonl` los transcripts de subagente,
marcados `isSidechain`, que **no son sesiones**. Medido en una instalación viva:
1 sesión real contra 17 archivos `.jsonl`. Recursivo infla el número 17 veces.

El reporte nuevo cuenta sesiones solo en la raíz, que es lo correcto, y reporta
los transcripts de subagente en una columna aparte para no esconderlos.

**3. La detección de usuarios ajenos tiene un hueco.** El regex solo marca a
un usuario ajeno cuando el segmento que sigue al nombre es uno de estos seis:
`OneDrive`, `AppData`, `iCloud`, `Documents`, `Documentos`, `Desktop`. Una
carpeta como `C--Users-Ricardo-Villa-Downloads-...` se copia en silencio, sin
aviso. El reporte nuevo no depende de esa lista: lee el usuario de la ruta
codificada sin importar qué siga.

**4. "Aditivo" protege tu disco, no tu restauración.** Tanto el merge de
transcripts como `robocopy /XC /XN /XO` descartan en silencio todo archivo del
respaldo cuyo nombre ya exista localmente, sin mirar tamaño ni contenido. Para
los transcripts no importa: se llaman por UUID y no chocan. Donde sí importa es
en `plugins`, `skill-hub` y `backups`, donde los nombres sí se repiten: si la
5810 ya tiene un archivo con ese nombre, la versión del respaldo se pierde sin
aviso. Es el comportamiento correcto para "no machacar", pero conviene saber
que el sentido de la protección apunta al disco local, no al respaldo.

**5. `TrimStart('')` no hace lo que parece.** En .NET, `TrimStart` con un
arreglo vacío quita espacios en blanco, no la diagonal invertida. La intención
era `TrimStart('\')`. Funciona de todos modos porque `Join-Path` colapsa el
separador duplicado. Es un bug latente, no un bloqueo. No se modificó.

**6. El reporte se sobrescribe en cada corrida.** `Set-Content` al inicio borra
el reporte anterior. Si quieres conservar el historial, respalda el archivo
antes de volver a correr.

---

## Cosas que ya se sabían y siguen siendo ciertas

- Los respaldos no tienen la misma forma. `ALLAN-COMPU-PROVISIONAL` dejó
  sesiones en `06-Claude-Trabajo/projects/` y también en
  `06-Claude-Trabajo/dot-claude/projects/`. Ambos scripts revisan los dos.
- `ALLAN-COMPU-PROVISIONAL` trae sesiones del usuario de Windows
  "Ricardo Villa". Se copian y se avisan. Tú decides si las borras.
- Las carpetas de proyecto codifican la ruta absoluta
  (`C--Users-ALLAN-iCloudDrive-...`). Si abres un proyecto en la 5810 y no ves
  sus sesiones, es por eso. Se arregla renombrando esa carpeta a la ruta real
  de la 5810. No se hace automático porque renombrar mal las deja invisibles.
- `.claude.json` no se fusiona. Jala los servidores MCP a mano desde las copias.
- Todo es aditivo e idempotente.

---

## Aviso con fecha

rclone avisa que su `client_id` compartido deja de funcionar durante 2026.
Cuando pase, la autorización empezará a fallar con errores de cuota. Hay que
crear un `client_id` propio en Google Cloud Console y ponerlo en el remoto:

```powershell
rclone config update gdrive client_id "<TU_ID>" client_secret "<TU_SECRETO>"
rclone config reconnect gdrive:
```

Procedimiento: https://rclone.org/drive/#making-your-own-client-id
