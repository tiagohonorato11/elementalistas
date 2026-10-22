# Elementistas

Jogo de magos elementais em Godot 4, inspirado no gênero de Magicka 2, com dois modos: **Arena** (cooperativo, ondas de inimigos) e **MOBA** (dois times de até 3, com torres, inibidores, nexus, tropas, selva e bots). É uma reimplementação clean-room: todo código e todos os assets são originais.

## Como rodar
**Jeito mais fácil:** dê dois cliques em `Elementistas.exe`, na raiz do projeto. Ele é regerado sozinho a cada commit; para gerar na hora, rode `sh tools/build.sh` (≈3 s). O `.exe` não vai para o Git (109 MB).

Pelo editor:
1. Instale o **Godot 4.3 ou mais novo** (versão padrão, não a .NET): https://godotengine.org/download
2. Abra o Godot → **Import** → selecione o arquivo `project.godot` desta pasta.
3. Aperte **F5** para jogar.

Antes da partida, no lobby, cada um escolhe a **classe** e **3 elementos**. Controles padrão: **botão direito** no chão para andar, mira no mouse, **D F G** carregam os elementos (até 3) e **Q W E R** usam as skills da classe, que consomem a carga (o **R**, ultimate, é volátil: muda conforme a combinação da carga, e 3 iguais geram a versão MEGA). As skills gastam mana e têm recarga. As teclas aparecem na tela e podem ser trocadas em **Configurações**, no lobby. Detalhes em `docs/mecanicas.md`.

Modos: **Arena** (ondas, cooperativo), **MOBA** (3v3 com bots), **Treino** (arena de testes) e **Mundo (RPG)**: um mapa aberto com vila, regiões de monstros, níveis, loja e missões, que vai crescer aos poucos.

Para testar skills, classes e elementos com calma, escolha o modo **Treino** no lobby: bonecos de teste com medidor de dano e um painel (tecla **Tab**) com mana infinita, sem recarga, imortal e troca de classe/elementos na hora.

## Jogar com amigos no mesmo Wi-Fi
1. Todos precisam do jogo no PC: mande o `Elementistas.exe` da raiz (todos com a mesma versão).
2. Quem hospeda clica em **Hospedar partida**. Na primeira vez, o Windows pergunta sobre o firewall: clique em **Permitir**, marcando também redes públicas se a sua rede estiver como "Pública".
3. Os amigos abrem o jogo: a partida aparece sozinha em "Partidas encontradas no Wi-Fi". Se não aparecer, digitem o IP mostrado na tela do host.
4. Com todos conectados, o host escolhe o **modo** e clica em **Começar partida**. Até 6 jogadores.
   - **Arena:** todos juntos contra ondas de inimigos, com fogo amigo ligado.
   - **MOBA:** cada um escolhe o time; com "Completar os times com bots", os times viram 3v3.

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

Teste das skills (Q W E R das 3 classes, mana, recarga, ultimates e versões MEGA):
```
godot --headless --path . res://tests/skills_smoke.tscn
```

Teste dos controles (teclas D F G e Q W E R de verdade, andar clicando, setas):
```
godot --headless --path . res://tests/controls_smoke.tscn
```

Testes do MOBA (montagem, tropas, bots, loja, selva, vitória; e o mesmo pela rede):
```
godot --headless --path . res://tests/moba_smoke.tscn
godot --headless --path . res://tests/moba_net_smoke.tscn -- --role=host
godot --headless --path . res://tests/moba_net_smoke.tscn -- --role=client
```

Testes do modo Mundo (mapa, monstros, missões, loja, reaparecer; e o mesmo pela rede):
```
godot --headless --path . res://tests/world_smoke.tscn
godot --headless --path . res://tests/world_net_smoke.tscn -- --role=host
godot --headless --path . res://tests/world_net_smoke.tscn -- --role=client
```

Testes do modo Treino (bonecos, painel, troca de classe; e o mesmo pela rede):
```
godot --headless --path . res://tests/practice_smoke.tscn
godot --headless --path . res://tests/practice_net_smoke.tscn -- --role=host
godot --headless --path . res://tests/practice_net_smoke.tscn -- --role=client
```

Teste da interface (números de dano, mira, skill negada, ícones, dicas, ajuda, placar, tremor):
```
godot --headless --path . res://tests/ui_smoke.tscn
```

Teste do fluxo da partida (5 ondas → vitória → reinício → derrota):
```
godot --headless --path . res://tests/flow_smoke.tscn
```

Capturas de tela para conferir o visual (abre uma janela por alguns segundos):
```
godot --path . res://tests/screenshot.tscn -- --mode=arena --zoom=0.7 --out=C:/pasta/captura
godot --path . res://tests/screenshot.tscn -- --mode=moba --out=C:/pasta/captura
godot --path . res://tests/screenshot.tscn -- --mode=lobby --out=C:/pasta/captura
```

Teste do áudio (abre uma janela: no modo headless o som fica mudo):
```
godot --path . res://tests/audio_smoke.tscn
```

## Créditos
Modelos 3D, texturas e animações de personagens, esqueletos, construções e natureza: **KayKit, de Kay Lousberg** (www.kaylousberg.com), licença **CC0**. Detalhes em `assets/models/kaykit/CREDITOS.md`. Efeitos, terreno e todo o código são próprios do projeto.

Áudio: músicas CC0 do OpenGameArt (bojidar-bg, haeldb, cynicmusic, emmama), efeitos CC0 da **Kenney** (www.kenney.nl) e sons de feitiços/ambiente sintetizados pelo projeto. Detalhes em `assets/audio/CREDITOS.md`.

## Estrutura
- `scripts/core/`: regras puras (elementos, carga, escolha de elementos, classes e skills, ultimates, vida). Ficam fora da cena para serem testáveis e rodarem só no host.
- `scripts/gameplay/`: mago, inimigos, ondas (game_state), projétil, barreira, HUD e arena (montada por código, em gray-box).
- `scripts/moba/`: modo MOBA: mapa, estruturas, tropas, estado da partida, ouro/níveis/loja e bots.
- `scripts/practice/`: modo Treino: bonecos de teste, estado com as opções de teste e o painel.
- `scripts/world/`: modo Mundo (RPG): mapa com a vila e as regiões, estado (acampamentos, recompensas, fonte), missões e personagens da vila.
- `scripts/vfx/`: visual: partículas dos elementos, efeitos de feitiços e estados, modelos animados das unidades e barras de vida.
- `scripts/audio/`: som: autoload `Audio` (efeitos 3D, loops, música com troca calma/combate/chefe, volumes), sons das unidades e dos eventos da partida.
- `assets/`: modelos KayKit (CC0), áudio (CC0) e o shader do terreno.
- `scripts/ui/`: teclas configuráveis (autoload `Keybinds`), tela de configurações (teclas e volumes), minimapa e os ícones desenhados do HUD (`glyphs.gd`, `skill_icon.gd`).
- `scripts/net/`: rede: lobby, conexão ENet, descoberta na LAN e sincronização.
- `docs/mecanicas.md`: documento de design.

## Status
- ✅ Fases 0–1: documento de mecânicas e projeto.
- ✅ Fase 2: feitiços completos (carga, barreiras elementais, proteção, golpe, ultimates, congelar/estilhaçar, empurrão).
- 🟡 Fase 3: co-op em LAN funcionando (lobby, descoberta, até 4 jogadores, host decide o dano).
- ✅ Fase 4: arena com obstáculos, 4 inimigos, 5 ondas, cair/reviver, vitória/derrota.
- ✅ Classes: Mago, Assassino e Lutador, escolhidas no lobby.
- ✅ Skills estilo MOBA: 3 elementos (entre 12, incluindo Vazio, Gravidade, Fumaça e Sangue) escolhidos antes da partida (D F G), 4 skills por classe (Q W E R) com mana e recarga, 12 ultimates + 12 versões MEGA conforme a carga.
- ✅ Mago volátil: Orbe que cresce e explode em área, W segurado vira bolha de escudo, Mini meteoro que deixa zonas elementais.
- ✅ Modo MOBA 3v3: torres, inibidores, nexus, tropas, selva, Guardião, ouro, níveis, loja, reaparecer e bots.
- ✅ Fase 5 (visual e som): partículas por elemento, céu e iluminação, personagens e esqueletos animados (KayKit), torres/castelo, árvores e montanhas, barras de vida, ícones dos elementos, minimapa, efeitos sonoros 3D, ambiente e música que muda em combate e perto do Guardião.
- 🟡 Fase 6 (polimento): anéis da carga, mira no chão, alvo do W, ícones desenhados, dicas, números de dano, avisos de estado, tremor e clarão, sons próprios, ajuda (F1) e placar. Falta: arte final dos ícones e o que surgir nos testes com amigos.
