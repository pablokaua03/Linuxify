<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/English-1e1e2e?style=for-the-badge&labelColor=cba6f7" alt="English"></a>
  <a href="README.pt-BR.md"><img src="https://img.shields.io/badge/Portugu%C3%AAs-1e1e2e?style=for-the-badge&labelColor=a6e3a1" alt="Português"></a>
  <a href="README.es.md"><img src="https://img.shields.io/badge/Espa%C3%B1ol-1e1e2e?style=for-the-badge&labelColor=fab387" alt="Español"></a>
  <a href="README.ru.md"><img src="https://img.shields.io/badge/%D0%A0%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9-1e1e2e?style=for-the-badge&labelColor=89b4fa" alt="Русский"></a>
</p>

<p align="center"><img src="assets/logo-256.png" width="128" alt="Linuxify logo"></p>
<h1 align="center">Linuxify</h1>
<p align="center"><b>Haz que Windows 11 se vea y se sienta como un escritorio Linux con tiling — y actívalo o desactívalo con un clic.</b></p>

<p align="center">
  <img src="docs/panel-general.png" width="49%" alt="Panel - General">
  <img src="docs/panel-terminal.png" width="49%" alt="Panel - Terminal">
</p>
<p align="center"><img src="docs/desktop-widget.png" width="70%" alt="Widget de escritorio"></p>

## ¿Qué es?

Linuxify es una pequeña app de bandeja con un panel moderno que une varias herramientas de código abierto:

- [GlazeWM](https://github.com/glzr-io/glazewm) — gestor de ventanas en mosaico
- [Zebar](https://github.com/glzr-io/zebar) — barra de estado superior
- [Windhawk](https://windhawk.net) — mods de la barra de tareas
- tema Catppuccin Mocha para Windows Terminal, prompt [Starship](https://starship.rs) y banner de [fastfetch](https://github.com/fastfetch-cli/fastfetch)

Linuxify guarda una copia de los archivos de configuración que reemplaza, y el *modo Linux* se puede desactivar en cualquier momento para volver a tu Windows normal.

## Funciones

- **Modo Linux con un clic** — haz clic en el icono de la bandeja (o pulsa **Ctrl+Alt+L**) para iniciar/detener GlazeWM + Zebar y aplicar/quitar el tema de la terminal.
- **Panel moderno** — ventana estilo Windows 11 con cristal acrílico, barra de título oscura, navegación lateral, tarjetas redondeadas, interruptores propios e indicadores de estado. El cristal se puede desactivar o ajustar (*General > Cristal del panel*).
- **Control por herramienta** — activa/desactiva GlazeWM, Zebar, Windhawk y el tema de terminal por separado, e instálalos o desinstálalos con winget desde el panel.
- **Pestaña Terminal** — pega cualquier banner ASCII, elige esquema de colores, color del ASCII, fuente, tamaño, opacidad y acrílico, con vista previa en vivo. *Restaurar original* recupera tu `settings.json` anterior y el logo por defecto.
- **Excepciones de GlazeWM** — elige apps que nunca deben organizarse en mosaico (juegos, launchers, herramientas). Añade por nombre de proceso o desde la lista de ventanas abiertas.
- **Transparencia de ventanas** — haz translúcida cualquier ventana con un control en vivo y guárdalo como regla por app, que se vuelve a aplicar automáticamente.
- **Widget de terminal en el escritorio** — tarjeta opcional de fastfetch fijada al escritorio, con esquina, tamaño (60–120%) y botón de cierre.
- **4 idiomas** — Español, English, Português (BR) y Русский en el panel, menú de bandeja, instalador y desinstalador. Por defecto sigue el idioma de Windows.
- **Reversible** — los archivos de configuración que Linuxify reemplaza se copian antes a `backup\` y el desinstalador los devuelve. Windows Terminal se fusiona, no se sobrescribe: tus perfiles y ajustes se quedan, y lo que cambies con el modo Linux activado se guarda en `backup\` antes de desactivarlo. Linuxify también añade entradas de inicio y una línea en tu perfil de PowerShell; el desinstalador las quita.

## Requisitos

- Windows 11 (la única versión en la que Linuxify está probado; Windows 10 puede funcionar, pero no está probado)
- Windows PowerShell 5.1 (incluido)
- [winget](https://learn.microsoft.com/windows/package-manager/winget/) (Instalador de aplicación) para instalar las dependencias automáticamente
- Recomendado: [JetBrainsMono Nerd Font](https://www.nerdfonts.com/) (el instalador puede instalarla)

## Instalación

1. Descarga `Linuxify-vX.Y.Z.zip` desde [Releases](../../releases) y extráelo donde quieras.
2. Haz doble clic en **`Install.cmd`**.
3. Responde **s** para instalar/actualizar las dependencias con winget (GlazeWM, Zebar, Windhawk, fastfetch, Starship y la Nerd Font opcional).

El instalador copia Linuxify a `%LOCALAPPDATA%\Linuxify`, guarda una copia de las configuraciones que reemplaza, escribe las de Linuxify, añade la bandeja al inicio (`HKCU\...\Run`, con `-Boot` para esperar la barra de tareas) y la inicia.

Opciones: `install.ps1 -Yes` (sin preguntas), `-NoDeps` (sin winget), `-NoStart` (no inicia la bandeja).

El zip incluye `Linuxify.exe` (la bandeja compilada con ps2exe). Sin él, la bandeja se ejecuta desde `Linuxify.ps1`.

## Uso

| Acción | Cómo |
|---|---|
| Alternar modo Linux | Clic en el icono de la bandeja o **Ctrl+Alt+L** |
| Abrir el panel | Clic derecho en el icono > *Abrir panel...* |
| Cambiar idioma | Panel > *General* > *Idioma* |
| Efecto cristal | Panel > *General* > *Cristal del panel* (interruptor + intensidad) |
| Widget de escritorio | Panel > *General* > *Terminal en el escritorio* |
| Desinstalar | `Uninstall.cmd` o bandeja > *Desinstalar todo...* |

### Pestañas del panel

- **General** — modo Linux, tarjetas de herramientas (estado, on/off, instalar/desinstalar), iniciar con Windows, idioma, widget y cristal.
- **Terminal** — banner ASCII (guardado en `~/.config/fastfetch/logo.txt`), esquema de colores, color del ASCII, fuente, opacidad y acrílico.
- **Excepciones** — apps que GlazeWM ignora. Los juegos encontrados por el scan quedan en la regla `# Jogos (Linuxify)` de `~/.glzr/glazewm/config.yaml`.
- **Transparencia** — opacidad en vivo de cualquier ventana, reglas guardadas por app y "aplicar automáticamente".

## Archivos de configuración

| Archivo | Para qué |
|---|---|
| `%LOCALAPPDATA%\Linuxify\panel.json` | Preferencias del panel (idioma, cristal, color ASCII, banner) |
| `%LOCALAPPDATA%\Linuxify\desktop.json` | Widget de escritorio (activo, esquina, tamaño) |
| `%LOCALAPPDATA%\Linuxify\transparency.json` | Reglas de transparencia por app |
| `%LOCALAPPDATA%\Linuxify\backup\` | Copias de los archivos de configuración que Linuxify reemplazó |
| `~/.glzr/glazewm/config.yaml` | Configuración de GlazeWM (mosaico, reglas, excepciones) |
| `~/.config/fastfetch/logo.txt` | Banner ASCII actual (`logo-default.txt` es el predeterminado) |

Las traducciones están en `lang/*.json` (UTF-8). Nuevos idiomas son bienvenidos — copia `lang/en.json`, traduce los valores y abre un PR.

## Desinstalar

Haz doble clic en **`Uninstall.cmd`** (o bandeja > *Desinstalar todo...*). Desactiva el modo Linux, quita el inicio automático y restaura las configuraciones respaldadas. `uninstall.ps1 -RemoveApps` también desinstala los paquetes de winget. De tu perfil de PowerShell solo quita las líneas que añadió Linuxify. Las copias quedan en `%LOCALAPPDATA%\Linuxify\backup` hasta que las borres.

## Solución de problemas

- **Ctrl+Alt+L no hace nada** — otra app usa el atajo; usa el icono de la bandeja.
- **No aparece el icono al iniciar sesión** — el inicio espera a Explorer y al área de notificación cerca de un minuto y reintenta el icono. El detalle está en `%LOCALAPPDATA%\Linuxify\startup.log`. Si una instalación antigua sigue usando el comando anterior, desactiva y activa *Iniciar con Windows* una vez (el próximo inicio también lo reescribe). Reiniciar Explorer devuelve el icono.
- **Un juego o app se organiza en mosaico** — añádelo en *Excepciones* o pon el proceso en la regla de juegos.
- **Los iconos salen como cuadrados en la terminal** — instala una Nerd Font y selecciónala en la pestaña *Terminal*.
- **Sin efecto cristal** — requiere Windows 11 y los efectos de transparencia activados en Windows; también puedes desactivarlo en *General*.

## Changelog

### Sin publicar
- Windows Terminal: al activar el modo Linux, el aspecto Linux se añade a tu configuración *actual* en lugar de copiar encima un archivo de la época de la instalación; los perfiles y ajustes que cambiaste después de instalar se conservan. Lo que se cambie con el modo Linux activado se guarda en `backup\wt-while-on-*.json` antes de desactivarlo. La configuración con comentarios no se toca.
- Desinstalar: restaura solo la primera copia de cada archivo, quita de tu perfil de PowerShell únicamente las líneas del propio Linuxify (tu línea `starship init` ya no se borra) y ya no escribe un script en `%TEMP%` para ejecutarlo como administrador. `-RemoveApps` quita exactamente los paquetes que añade el instalador. `backups.txt` se borra al final.
- Las ediciones del perfil y de la lista de copias conservan la codificación del archivo (Windows PowerShell 5.1 escribía en ANSI).
- `scripts\New-Release.ps1` genera el zip de la versión y `SHA256SUMS`. El CI ejecuta PSScriptAnalyzer y pruebas Pester.

### v0.2.4
- Corregido el error al iniciar sesión `A parameter cannot be found that matches parameter name 'Boot'`. El inicio solo pasa `-Boot` a `Linuxify.exe` cuando ese exe lo admite; si no, ejecuta `Linuxify.ps1 -Boot` oculto. Un comando de inicio antiguo se reescribe la próxima vez que arranque la bandeja.
- La comprobación de la barra de tareas usa `FindWindowW` y ya no bloquea el icono de la bandeja si falla.
- Si el inicio falla, el mensaje y `%LOCALAPPDATA%\Linuxify\startup.log` indican en qué paso falló.

### v0.2.3
- Al iniciar sesión, la bandeja espera a Explorer y al área de notificación (`-Boot` en el comando de inicio) antes de mostrar el icono. Si no puede crear el icono, lo reintenta y escribe el error, con fecha y hora, en `%LOCALAPPDATA%\Linuxify\startup.log`.
- Si Explorer se reinicia, el icono de la bandeja vuelve.
- *Iniciar con Windows* (instalador, panel y menú de bandeja) escribe el comando nuevo. Una instalación antigua se actualiza la próxima vez que se abra la bandeja.

## Créditos

[GlazeWM](https://github.com/glzr-io/glazewm) y [Zebar](https://github.com/glzr-io/zebar) de glzr.io, [Windhawk](https://windhawk.net) de Ramen Software, [Starship](https://starship.rs), [fastfetch](https://github.com/fastfetch-cli/fastfetch), [Catppuccin](https://catppuccin.com).

## Licencia

MIT — ver [LICENSE](LICENSE).
