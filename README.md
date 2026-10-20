# Elementistas

Jogo co-op de magos elementais em Godot 4, inspirado no gênero de Magicka 2. É uma reimplementação clean-room: todo código e todos os assets são originais.

## Como rodar
**Jeito mais fácil:** dê dois cliques em `Elementistas.exe`, na raiz do projeto. Ele é regerado sozinho a cada commit; para gerar na hora, rode `sh tools/build.sh` (≈3 s). O `.exe` não vai para o Git (109 MB).

Pelo editor:
1. Instale o **Godot 4.3 ou mais novo** (versão padrão, não a .NET): https://godotengine.org/download
2. Abra o Godot → **Import** → selecione o arquivo `project.godot` desta pasta.
3. Aperte **F5** para jogar.

Os controles aparecem no canto da tela e podem ser trocados em **Configurações**, no lobby. Detalhes em `docs/mecanicas.md`.

## Jogar com amigos no mesmo Wi-Fi
1. Todos precisam do jogo no PC: mande o `Elementistas.exe` da raiz (todos com a mesma versão).
2. Quem hospeda clica em **Hospedar partida**. Na primeira vez, o Windows pergunta sobre o firewall: clique em **Permitir**, marcando também redes públicas se a sua rede estiver como "Pública".
3. Os amigos abrem o jogo: a partida aparece sozinha em "Partidas encontradas no Wi-Fi". Se não aparecer, digitem o IP mostrado na tela do host.
4. Com todos conectados, o host clica em **Começar partida**. Até 4 jogadores, com fogo amigo ligado.

Para testar sozinho com várias janelas: no editor, *Debug → Customize Run Instances* → 2 instâncias. Em uma, hospede; na outra, entre com o IP `127.0.0.1`.

## Testes
Com o Godot no PATH, depois de abrir o projeto no editor uma vez:
```
godot --headless --path . --script res://tests/run_tests.gd
```
Se der certo, aparece `N verificações, 0 falhas`.

Teste de rede, com dois processos no mesmo PC:
```
godot --headless --path . res://tests/net_smoke.tscn -- --role=host
godot --headless --path . res://tests/net_smoke.tscn -- --role=client
```

Teste dos feitiços (carga, golpe, barreiras, proteção, congelar, especiais):
```
godot --headless --path . res://tests/spells_smoke.tscn
```

Teste do fluxo da partida (5 ondas → vitória → reinício → derrota):
```
godot --headless --path . res://tests/flow_smoke.tscn
```

## Estrutura
- `scripts/core/`: regras puras (elementos, fila, forma do feitiço, vida). Ficam fora da cena para serem testáveis e, na Fase 3, rodarem só no host.
- `scripts/gameplay/`: mago, inimigos, ondas (game_state), projétil, barreira, HUD e arena (montada por código, em gray-box).
- `scripts/ui/`: teclas configuráveis (autoload `Keybinds`) e tela de configurações.
- `scripts/net/`: rede: lobby, conexão ENet, descoberta na LAN e sincronização.
- `docs/mecanicas.md`: documento de design.

## Status
- ✅ Fases 0–1: documento de mecânicas e projeto.
- ✅ Fase 2: feitiços completos (carga, barreiras elementais, proteção, golpe, 5 especiais, congelar/estilhaçar, empurrão).
- 🟡 Fase 3: co-op em LAN funcionando (lobby, descoberta, até 4 jogadores, host decide o dano).
- ✅ Fase 4: arena com obstáculos, 4 inimigos, 5 ondas, cair/reviver, vitória/derrota.
- ⬜ Fases 5–6: arte, som, polimento.
