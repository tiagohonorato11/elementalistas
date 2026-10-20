# Mecânicas — Elementistas

Documento de design escrito com nossas próprias palavras. A referência de gênero são jogos co-op de magos elementais (como Magicka 2), estudados **apenas por observação**. Nenhum código, asset, texto ou nome do jogo original é usado aqui. Todos os números são nossos e ficam em `scripts/core/elements.gd`.

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
- **À frente** (botão direito): projétil e barreira saem na hora. Spray, beam e arco ficam ativos enquanto o botão estiver segurado, até 3 segundos.
- **Área** (Shift + botão direito): aplica os elementos a todos num raio de 4 m. Com Escudo, cria um anel de barreiras.
- **Em si mesmo** (botão do meio ou Espaço): aplica os elementos no próprio mago. Vida cura, Fogo queima! Escudo reduz o dano recebido pela metade por 5 s.
- **Andar**: WASD ou setas (para cima = para o fundo da tela), ou segurar o botão esquerdo (o mago vai em direção ao mouse). Os elementos ficam nas teclas em volta do WASD: Q E R F / Z X C V.

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
- [ ] Encantar arma
- [ ] Barreiras elementais (parede de fogo etc.)
- [ ] Carga de projétil (segurar para mais força)
- [ ] Feitiços especiais com receitas próprias
- [ ] Testar o reviver em partida real com amigos
- [ ] Mais arenas e um chefe

## Checklist de teste manual
- [ ] Q + V mostra "Vapor" no HUD; Q + Z esvazia a fila
- [ ] C + botão direito: projétil acerta um inimigo (−40)
- [ ] V + botão direito segurado: spray em cone; o inimigo fica "queimando"
- [ ] Q no inimigo e depois Z: dano dobrado
- [ ] R + botão direito: barreira à frente que some em 6 s
- [ ] E + Espaço: cura o próprio mago
- [ ] Salamandra não sofre dano de Fogo; Água ou Frio a derrubam mais rápido
- [ ] Um amigo cai; E + botão direito (beam de Vida) nele o levanta com metade da vida
- [ ] Todos caídos: aparece "DERROTA"; o host aperta R e a partida recomeça
