<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/English-1e1e2e?style=for-the-badge&labelColor=cba6f7" alt="English"></a>
  <a href="README.pt-BR.md"><img src="https://img.shields.io/badge/Portugu%C3%AAs-1e1e2e?style=for-the-badge&labelColor=a6e3a1" alt="Português"></a>
  <a href="README.es.md"><img src="https://img.shields.io/badge/Espa%C3%B1ol-1e1e2e?style=for-the-badge&labelColor=fab387" alt="Español"></a>
  <a href="README.ru.md"><img src="https://img.shields.io/badge/%D0%A0%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9-1e1e2e?style=for-the-badge&labelColor=89b4fa" alt="Русский"></a>
</p>

<p align="center"><img src="assets/logo-256.png" width="128" alt="Linuxify logo"></p>
<h1 align="center">Linuxify</h1>
<p align="center"><b>Deixe o Windows 11 com cara e jeito de desktop Linux com tiling — e ligue ou desligue tudo com um clique.</b></p>

<p align="center">
  <img src="docs/panel-general.png" width="49%" alt="Painel - Geral">
  <img src="docs/panel-terminal.png" width="49%" alt="Painel - Terminal">
</p>
<p align="center"><img src="docs/desktop-widget.png" width="70%" alt="Widget na área de trabalho"></p>

## O que é?

O Linuxify é um pequeno app de bandeja com um painel moderno que junta várias ferramentas open source:

- [GlazeWM](https://github.com/glzr-io/glazewm) — gerenciador de janelas em tiles
- [Zebar](https://github.com/glzr-io/zebar) — barra de status superior
- [Windhawk](https://windhawk.net) — mods da barra de tarefas
- tema Catppuccin Mocha para o Windows Terminal, prompt [Starship](https://starship.rs) e banner do [fastfetch](https://github.com/fastfetch-cli/fastfetch)

Tudo o que o Linuxify altera ganha backup antes, e o *modo Linux* pode ser desligado a qualquer momento para voltar ao Windows normal.

## Recursos

- **Modo Linux em um clique** — clique no ícone da bandeja (ou aperte **Ctrl+Alt+L**) para ligar/desligar GlazeWM + Zebar e aplicar/remover o tema do terminal.
- **Painel moderno** — janela no estilo Windows 11 com vidro acrílico, barra de título escura, menu lateral, cards arredondados, toggles próprios e indicadores de status. O vidro pode ser desligado ou ajustado (*Geral > Vidro no painel*).
- **Controle por ferramenta** — ligue/desligue GlazeWM, Zebar, Windhawk e o tema do terminal separadamente, e instale/desinstale pelo winget direto do painel.
- **Aba Terminal** — cole qualquer banner ASCII, escolha esquema de cores, cor do ASCII, fonte, tamanho, transparência e acrílico, com prévia ao vivo. *Restaurar original* volta o `settings.json` anterior e o logo padrão.
- **Exceções do GlazeWM** — escolha apps que nunca devem ser organizados em tiles (jogos, launchers, ferramentas). Adicione pelo nome do processo ou pela lista de janelas abertas.
- **Transparência de janelas** — deixe qualquer janela translúcida com um slider ao vivo e salve como regra por app, reaplicada automaticamente.
- **Widget de terminal no desktop** — card opcional do fastfetch preso na área de trabalho, com escolha de canto, tamanho (60–120%) e botão de fechar.
- **4 idiomas** — Português (BR), English, Español e Русский no painel, menu da bandeja, instalador e desinstalador. O padrão segue o idioma do Windows.
- **Seguro** — todo arquivo ganha backup antes de ser alterado; o desinstalador restaura os originais.

## Requisitos

- Windows 11 (Windows 10 1803+ funciona, com um desfoque mais simples)
- Windows PowerShell 5.1 (já vem no Windows)
- [winget](https://learn.microsoft.com/windows/package-manager/winget/) (Instalador de Aplicativo) para instalar as dependências automaticamente
- Recomendado: [JetBrainsMono Nerd Font](https://www.nerdfonts.com/) (o instalador pode instalar pra você)

## Instalação

1. Baixe `Linuxify-vX.Y.Z.zip` em [Releases](../../releases) e extraia em qualquer pasta.
2. Clique duas vezes em **`Install.cmd`**.
3. Responda **s** para instalar/atualizar as dependências com o winget (GlazeWM, Zebar, Windhawk, fastfetch, Starship e a Nerd Font opcional).

O instalador copia o Linuxify para `%LOCALAPPDATA%\Linuxify`, faz backup das suas configs, grava as configs do Linuxify, coloca a bandeja na inicialização (`HKCU\...\Run`, com `-Boot` para esperar a barra de tarefas) e a inicia.

Opções de linha de comando: `install.ps1 -Yes` (sem perguntas), `-NoDeps` (pula o winget), `-NoStart` (não inicia a bandeja).

O zip inclui o `Linuxify.exe` (a bandeja compilada com ps2exe). Sem ele, a bandeja roda pelo `Linuxify.ps1`.

## Uso

| Ação | Como |
|---|---|
| Alternar modo Linux | Clique no ícone da bandeja ou **Ctrl+Alt+L** |
| Abrir o painel | Botão direito no ícone > *Abrir painel...* |
| Trocar idioma | Painel > *Geral* > *Idioma* |
| Efeito vidro | Painel > *Geral* > *Vidro no painel* (liga/desliga + intensidade) |
| Widget no desktop | Painel > *Geral* > *Terminal na área de trabalho* |
| Desinstalar | `Uninstall.cmd` ou bandeja > *Desinstalar tudo...* |

### Abas do painel

- **Geral** — modo Linux, cards das ferramentas (status, liga/desliga, instalar/desinstalar), iniciar com o Windows, idioma, widget e vidro.
- **Terminal** — banner ASCII (salvo em `~/.config/fastfetch/logo.txt`), esquema de cores, cor do ASCII, fonte, transparência e acrílico.
- **Exceções** — apps que o GlazeWM ignora. Jogos encontrados pelo scan ficam na regra `# Jogos (Linuxify)` do `~/.glzr/glazewm/config.yaml`.
- **Transparência** — opacidade ao vivo de qualquer janela, regras salvas por app e "aplicar automaticamente".

## Arquivos de configuração

| Arquivo | Para quê |
|---|---|
| `%LOCALAPPDATA%\Linuxify\panel.json` | Preferências do painel (idioma, vidro, cor do ASCII, banner) |
| `%LOCALAPPDATA%\Linuxify\desktop.json` | Widget do desktop (ligado, canto, tamanho) |
| `%LOCALAPPDATA%\Linuxify\transparency.json` | Regras de transparência por app |
| `%LOCALAPPDATA%\Linuxify\backup\` | Backups de todos os arquivos alterados |
| `~/.glzr/glazewm/config.yaml` | Config do GlazeWM (tiles, regras, exceções) |
| `~/.config/fastfetch/logo.txt` | Banner ASCII atual (`logo-default.txt` é o padrão) |

As traduções ficam em `lang/*.json` (UTF-8). Novos idiomas são bem-vindos — copie `lang/en.json`, traduza os valores e abra um PR.

## Desinstalar

Clique duas vezes em **`Uninstall.cmd`** (ou bandeja > *Desinstalar tudo...*). Ele desliga o modo Linux, tira a inicialização automática e restaura as configs do backup. `uninstall.ps1 -RemoveApps` também remove os pacotes do winget. Os backups ficam em `%LOCALAPPDATA%\Linuxify\backup` até você apagar.

## Problemas comuns

- **Ctrl+Alt+L não faz nada** — outro app usa o atalho; use o ícone da bandeja.
- **Sem ícone na bandeja depois de entrar** — a inicialização espera o Explorer e a área de notificação por cerca de um minuto e tenta o ícone de novo. Os detalhes ficam em `%LOCALAPPDATA%\Linuxify\startup.log`. Se uma instalação antiga ainda usar o comando anterior, desligue e ligue *Iniciar com o Windows* uma vez (a próxima abertura também reescreve o comando). Reiniciar o Explorer traz o ícone de volta.
- **Um jogo ou app está sendo organizado em tiles** — adicione em *Exceções* ou coloque o processo na regra de jogos.
- **Ícones viram quadrados no terminal** — instale uma Nerd Font e selecione na aba *Terminal*.
- **Sem efeito de vidro** — precisa do Windows 11 (ou Windows 10 1803+ para o desfoque) e dos efeitos de transparência ligados nas configurações do Windows; também dá para desligar em *Geral*.

## Changelog

### v0.2.4
- Corrigido o erro na entrada do Windows `A parameter cannot be found that matches parameter name 'Boot'`. A inicialização só passa `-Boot` ao `Linuxify.exe` quando esse exe aceita; senão executa `Linuxify.ps1 -Boot` oculto. Um comando de inicialização antigo é reescrito na próxima vez que a bandeja abrir.
- A checagem da barra de tarefas usa `FindWindowW` e não bloqueia mais o ícone da bandeja se falhar.
- Se a inicialização falhar, a mensagem e o `%LOCALAPPDATA%\Linuxify\startup.log` dizem em qual passo foi.

### v0.2.3
- Na entrada do Windows a bandeja espera o Explorer e a área de notificação (`-Boot` no comando de inicialização) antes de mostrar o ícone. Se a criação do ícone falhar, tenta de novo e grava o erro, com data e hora, em `%LOCALAPPDATA%\Linuxify\startup.log`.
- Se o Explorer reiniciar, o ícone da bandeja volta.
- *Iniciar com o Windows* (instalador, painel e menu da bandeja) grava o comando novo. Uma instalação antiga é atualizada na próxima vez que a bandeja abrir.

## Créditos

[GlazeWM](https://github.com/glzr-io/glazewm) e [Zebar](https://github.com/glzr-io/zebar) por glzr.io, [Windhawk](https://windhawk.net) por Ramen Software, [Starship](https://starship.rs), [fastfetch](https://github.com/fastfetch-cli/fastfetch), [Catppuccin](https://catppuccin.com).

## Licença

MIT — veja [LICENSE](LICENSE).
