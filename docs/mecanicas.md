# Mecânicas — Elementistas

Documento de design escrito com nossas próprias palavras. A referência de gênero são jogos co-op de magos elementais (como Magicka 2), estudados **apenas por observação**. Nenhum código, asset, texto ou nome do jogo original é usado aqui. Todos os números são nossos e ficam em `scripts/core/elements.gd`.

## Classes (`scripts/core/classes.gd`)
Cada jogador escolhe a classe no lobby (fica salva no PC). Todas usam a mesma fila de elementos e os mesmos feitiços; mudam atributos, arma e habilidade (**Ctrl**). O grupo pode repetir classes.

| | Mago | Assassino | Lutador |
|---|---|---|---|
| Vida / velocidade | 200 / 5 | 140 / 6,5 | 320 / 4,5 |
| Armadura | — | — | 25% de todo dano |
| Força dos feitiços | 100% | 70% | 80% |
| Recarga dos especiais | 1× | 1,5× | 1,5× |
| Arma (botão esquerdo) | cajado: 20, a cada 0,6 s | adagas: 14, a cada 0,3 s | arma pesada: 35, a cada 0,9 s, cone largo, empurra forte |
| Elementos na arma | 1 golpe (×0,8) | **3 golpes** (×1,0) | 1 golpe (×1,2) |
| Bônus | — | **pelas costas: 2×** | — |
| Habilidade (Ctrl) | **Escudo arcano**: metade do dano por 4 s e empurra quem está a até 4 m (12 s de recarga) | **Passo sombrio**: avança até 6 m e fica **invisível** por 3 s, ignorado pelos inimigos; o próximo golpe vale 2×; atacar revela (8 s) | **Investida**: corre 7 m; quem estiver no caminho leva 30 + os elementos da fila e é empurrado, aliados também (7 s) |

## Elementos e teclas
As teclas abaixo são o padrão; cada jogador pode trocá-las em **Configurações**, no lobby. As escolhas ficam salvas em `user://settings.cfg`.

| Tecla | Elemento | Dano base* | Efeito |
|---|---|---|---|
| Q | Água | 4 | molha, apaga fogo |
| E | Vida | −30 (cura) | — |
| R | Escudo | 0 | barreira / proteção |
| F | Frio | 10 | resfria (lentidão), apaga fogo |
| Z | Raio | 30 | dano dobrado em alvo molhado |
| X | Arcano | 35 | — |
| C | Terra | 40 | — |
| V | Fogo | 15 | incendeia (8/s por 4s) ou seca alvo molhado |
| — | Vapor (Água+Fogo) | 20 | molha |
| — | Gelo (Água+Frio) | 25 | resfria |

\* Por acerto (projétil e área) ou por segundo (spray, beam e arco).

## Fila (até 5 elementos)
Ao adicionar um elemento, nesta ordem:
1. Se houver um **oposto** na fila, os dois somem. Pares opostos:
   - Água↔Raio
   - Vida↔Arcano
   - Fogo↔Frio
   - Terra↔Raio
   - Escudo↔Escudo
   - Fogo↔Gelo
   - Frio↔Vapor
2. Se houver um **par de fusão**, os dois viram um só: Água+Fogo = Vapor; Água+Frio = Gelo.
3. Caso contrário, o elemento entra no fim da fila, se ela tiver espaço.

## Forma do feitiço (prioridade de cima para baixo)
1. Tem Escudo → **Barreira**
2. Tem Terra ou Gelo → **Projétil**
3. Tem Arcano ou Vida → **Raio contínuo (beam)**
4. Tem Raio → **Arco elétrico** (salta para até 3 alvos)
5. Resto (Água, Fogo, Frio, Vapor) → **Spray** em cone

## Modos de lançar
- **À frente** (botão direito):
  - **Projétil** (Terra/Gelo) **carrega** enquanto o botão está segurado: de 0,6× a 2× de dano em 1,2 s, mais rápido, maior e com mais empurrão. Solta sozinho após 3 s.
  - **Spray, beam e arco** ficam ativos enquanto o botão estiver segurado, até 3 s.
  - **Barreira** sai na hora (veja abaixo).
- **Área** (Shift + botão direito): aplica os elementos a todos num raio de 4 m; com Água, empurra. Com Escudo, cria um anel de barreiras.
- **Em si mesmo** (Espaço ou botão do meio): aplica os elementos no próprio mago (Vida cura, Fogo queima!).
  - **Escudo sozinho**: metade do dano por 5 s.
  - **Escudo + elementos** (**proteção elemental**): imune a esses elementos por 10 s, por exemplo Escudo + Fogo antes de usar a parede de fogo.
- **Golpe com a arma** (botão esquerdo): 20 de dano em cone curto à frente, com empurrão e recarga de 0,6 s. Se houver elementos na fila, o golpe os carrega (×0,8) e consome a fila.
- **Andar**: WASD ou setas (para cima = para o fundo da tela). "Andar até o cursor" fica no botão lateral do mouse (configurável).

## Barreiras
| Fila | Resultado |
|---|---|
| Escudo | parede que bloqueia movimento e projéteis por 6 s |
| Escudo + Terra | muro de pedra: mais grosso, dura 12 s |
| Escudo + outros elementos | **parede elemental**: aplica os elementos (por segundo) em quem encostar, aliados também. Escudo + Vida cura quem estiver perto |

## Estados e interações
- **Molhado** (Água, Vapor): Raio causa 2×. Fogo seca em vez de incendiar.
- **Queimando** (Fogo): 8 de dano por segundo por 4 s. Água e Frio apagam.
- **Resfriado** (Frio, Gelo): metade da velocidade.
- **Congelado** (Frio/Gelo em alvo molhado, ou o especial Inverno): não anda, não ataca e não lança.
  - **Terra estilhaça** o alvo congelado: 2× de dano e o gelo quebra.
  - **Fogo descongela.**
- **Empurrão**: Água (spray e área), projéteis (mais com Terra e com carga), golpe e Meteoro. O Brutamontes resiste (30%).

## Feitiços especiais (G com a receita na fila)
Monte os elementos na fila (a ordem não importa) e aperte **G**. Cada um tem recarga própria, mostrada no canto da tela.

| Especial | Receita (teclas padrão) | Efeito | Recarga |
|---|---|---|---|
| Meteoro | Fogo, Terra, Fogo, Terra (V C V C) | cai no cursor (até 14 m) após 1 s: Fogo×2 + Terra×2 num raio de 4,5 m e empurrão; atinge aliados | 20 s |
| Tempestade | Frio, Raio, Frio, Raio (F Z F Z) | por 5 s, um raio duplo a cada 0,5 s num inimigo próximo | 25 s |
| Inverno | Frio, Escudo, Frio (F R F) | congela por 3,5 s os inimigos num raio de 10 m | 30 s |
| Teleporte | Arcano, Raio, Arcano (X Z X) | salta até o cursor (até 10 m); falha se o destino estiver bloqueado | 8 s |
| Bênção | Vida, Escudo, Vida (E R E) | revive todos os magos caídos e cura 60 | 40 s |

## Inimigos (`scripts/gameplay/enemy.gd`)
| Tipo | Vida | Ataque | Particularidade |
|---|---|---|---|
| Lacaio | 120 | corpo a corpo, 15 | rápido |
| Arqueiro | 80 | projétil de Gelo à distância | mantém ~7 m de distância |
| Salamandra | 150 | corpo a corpo, 5 + Fogo | imune a Fogo; fraca a Água, Frio e Gelo (×1,5) |
| Brutamontes | 450 | corpo a corpo, 40 | lento; resiste à Terra (×0,5) |

Todos perseguem o mago vivo mais próximo pelo navmesh da arena e ignoram quem está caído.

## Partida (`scripts/gameplay/game_state.gd`)
- 5 s de preparação e depois **5 ondas** crescentes. Cada jogador além do primeiro adiciona 50% de inimigos.
- Entre ondas, há 6 s de pausa, e quem caiu volta com metade da vida.
- **Cair e reviver:** com a vida em 0, o mago cai, não age e não recebe dano. Um aliado o levanta lançando qualquer feitiço com **Vida** nele (beam, área etc.).
- **Vitória:** limpar a onda 5. **Derrota:** todos caídos ao mesmo tempo. O host aperta **R** para jogar de novo (só na tela de fim).

## Ainda por fazer
- [ ] Testar o reviver e os especiais em partida real com amigos
- [ ] Balancear (a Tempestade num inimigo sozinho é muito forte; o tiro sem carga ficou fraco)
- [ ] Mais arenas e um chefe

## Checklist de teste manual
- [ ] Q + V mostra "Vapor" no HUD; Q + Z esvazia a fila
- [ ] C + botão direito segurado ~1 s: projétil carregado acerta um inimigo (até −80) e o empurra
- [ ] V + botão direito segurado: spray em cone; o inimigo fica "queimando"
- [ ] Q no inimigo e depois Z: dano dobrado
- [ ] R + botão direito: barreira à frente que some em 6 s
- [ ] E + Espaço: cura o próprio mago
- [ ] Salamandra não sofre dano de Fogo; Água ou Frio a derrubam mais rápido
- [ ] Um amigo cai; E + botão direito (beam de Vida) nele o levanta com metade da vida
- [ ] Todos caídos: aparece "DERROTA"; o host aperta R e a partida recomeça
- [ ] R + V + botão direito: parede de fogo; inimigos que encostam queimam
- [ ] Q (spray) e depois F (spray) no mesmo inimigo: ele congela; C no congelado: estilhaça
- [ ] V + botão esquerdo: golpe com fogo
- [ ] V C V C + G: meteoro no cursor; X Z X + G: teleporte
