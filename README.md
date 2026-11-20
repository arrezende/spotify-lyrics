# Letras PiP

App de barra de menus para macOS que mostra a letra da música que está tocando no Spotify
numa janela flutuante com o comportamento de um PiP de vídeo.

## Estado atual

- Janela `NSPanel` sem barra de título, nível `floating + 1`, em todos os Desktops e sobre apps em tela cheia.
- Arrasta por qualquer ponto, encaixa no canto mais próximo ao soltar, redimensiona pelo grip (três traços diagonais) no canto inferior direito.
- Controles no hover: offset da letra (−/+ 0,25 s), fundo transparente, minimizar e fechar.
- Minimizar colapsa a janela numa pílula de 36 pt (só título e artista); expande pelo chevron.
- Fundo transparente remove o vidro fosco e a borda, deixando só o texto com sombra forte.
- Play/pause, anterior e próxima: aparecem numa linha de botões ao passar o mouse (e no menu, com ⌘P e ← / →). Vão direto pro Spotify via AppleScript.
- Opacidade da janela em 100/90/75/60/40% pelo menu.
- "Descer até a borda da tela" (⌘D) ignora a faixa reservada pela Dock: a janela passa de 20 pt para 6 pt do chão. Com a Dock em autohide o macOS já libera o espaço e ela desce sem precisar da opção.
- Now playing via AppleScript no app do Spotify (sem OAuth, exige permissão de Automação uma vez).
- Letra via [LRCLIB](https://lrclib.net) (LRC sincronizado), com matching por título, artista e duração.
- Status item na barra de menus (`music.note.list`).

## Build

```bash
./build.sh          # gera build/LetrasPiP.app (swiftc direto, sem Xcode project)
```

## Flags de desenvolvimento

| Flag | Efeito |
|---|---|
| `--demo` | ignora o Spotify e simula uma faixa com letra sincronizada |
| `--hover` | força o estado de hover (para inspecionar os controles) |
| `--transparent` | inicia com fundo transparente |
| `--collapsed` | inicia minimizada na pílula |
| `--snapshot <path>` | renderiza a janela em PNG e encerra |
| `--selftest` | testa parsing de LRC e matching contra a API real |
| `--uitest` | testa resize, minimizar/expandir, transparência e opacidade |

## Arquivos

| Arquivo | Papel |
|---|---|
| `Sources/SpotifyBridge.swift` | AppleScript → snapshot da faixa (título, artista, posição, estado) |
| `Sources/PlayerModel.swift` | estado do app, polling, interpolação de posição, avanço de linha |
| `Sources/LyricsService.swift` | busca no LRCLIB, scoring de matching, parser LRC |
| `Sources/PiPPanel.swift` | a janela flutuante, snapping, grip de resize |
| `Sources/LyricsView.swift` | a UI SwiftUI |
| `Sources/Snapshot.swift` | auto-render para PNG (debug) |
| `Sources/SelfTest.swift` | testes offline |

## Limitações conhecidas

- Não toca áudio: controla o app oficial do Spotify. A Web API não faz streaming.
- AppleScript só enxerga Music e Spotify; browsers/YouTube não (MediaRemote está bloqueado desde o macOS 15.4).
- O LRCLIB é colaborativo: algumas faixas não têm letra sincronizada, e o offset manual existe por isso.
