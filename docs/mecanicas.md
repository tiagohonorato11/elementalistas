# Mecânicas — Elementistas

Documento de design escrito com nossas próprias palavras. A referência de gênero são jogos co-op de magos elementais (como Magicka 2), estudados **apenas por observação**. Nenhum código, asset, texto ou nome do jogo original é usado aqui. Todos os números são nossos e ficam em `scripts/core/` (`elements.gd`, `classes.gd`, `ultimates.gd`).

## Antes da partida: classe e 3 elementos (lobby)
Cada jogador escolhe a **classe** e **3 elementos diferentes** entre os 11 (fica salvo no PC, por classe). O 1º fica na tecla **D**, o 2º no **F** e o 3º no **G**.
- **Opostos não podem ser escolhidos juntos** (eles se anulariam): Fogo×Frio, Água×Raio, Vida×Arcano, Terra×Raio, Vazio×Escudo e Fumaça×Água. No lobby, os opostos ficam bloqueados. A Gravidade não tem oposto.
- Padrões: Mago = Fogo, Raio, Arcano; Assassino = Arcano, Frio, Terra; Lutador = Fogo, Terra, Escudo.
- Os bots sorteiam uma escolha válida.

## Carga (D F G) e skills (Q W E R)
- **D F G** somam o elemento escolhido numa **carga de até 3** (pode repetir: Fogo, Fogo, Raio).
  - Fusões continuam: Água + Fogo = **Vapor**; Água + Frio = **Gelo**.
- A **próxima skill** (Q, W, E ou R) usa **todos** os elementos da carga e a esvazia. Sem carga, Q/W/E saem na versão básica; o **R precisa de carga**.
- Cada elemento da carga aplica o seu efeito (dano e estado, tabela abaixo), além do dano próprio da skill.
- Toda skill gasta **mana** e tem **recarga**. A mana se regenera sozinha (6× mais rápido na fonte do MOBA).
- **Golpe básico** (botão esquerdo): não usa a carga; dano em cone à frente com empurrão.
- O **W** depende do que está **sob o mouse** (até 10 m): inimigo → enfraquece; aliado, ninguém ou você mesmo → fortalece. **Aliado caído:** o W o levanta (Arena).

## Classes (`scripts/core/classes.gd`)
| | Mago | Assassino | Lutador |
|---|---|---|---|
| Vida / velocidade | 200 / 5 | 140 / 6,5 | 320 / 4,5 |
| Mana / regeneração | 160 / 5 por s | 110 / 6 por s | 100 / 4 por s |
| Armadura | — | — | 25% de todo dano |
| Força dos elementos | 100% | 80% | 80% |
| Golpe (botão esquerdo) | cajado: 20, a cada 0,6 s | adagas: 14, a cada 0,3 s; **pelas costas 2×** | arma pesada: 35, a cada 0,9 s, empurra forte |

**Mago**
| Tecla | Skill | Efeito | Mana / recarga |
|---|---|---|---|
| Q | **Orbe** | projétil (30) que leva a carga; com Terra vira pedra, com Gelo vira cristal | 15 / 1,5 s |
| W | **Bênção / Maldição** | aliado ou você: cura 30 e protege contra os elementos da carga; inimigo: a carga + lento 40% e +20% de dano recebido por 4 s | 30 / 8 s |
| E | **Raio laser** | feixe contínuo de 1,5 s (35/s) na direção do mouse, com a carga | 35 / 6 s |
| R | **Ultimate** | ver tabela abaixo | 80 / 60 s |

**Assassino**
| Tecla | Skill | Efeito | Mana / recarga |
|---|---|---|---|
| Q | **Adaga** | projétil rápido (24) com a carga; **pelas costas 2×** | 12 / 2 s |
| W | **Véu / Marca** | aliado ou você: **invisível** por 2,5 s (os inimigos ignoram; agir revela); inimigo: a carga + **marcado** (+30% de dano recebido) por 4 s | 25 / 10 s |
| E | **Passo sombrio** | salta até 6 m na direção do mouse e solta a carga (+25) em quem estiver a 2,5 m de onde cai | 25 / 8 s |
| R | **Ultimate** | força 80% | 70 / 60 s |

**Lutador**
| Tecla | Skill | Efeito | Mana / recarga |
|---|---|---|---|
| Q | **Golpe giratório** | 35 + a carga em todos a até 2,8 m, com empurrão | 15 / 4 s |
| W | **Grito / Desafio** | aliado ou você: cura 20, +30% de velocidade e −30% de dano recebido por 4 s; inimigo: a carga + lento 40% | 25 / 10 s |
| E | **Investida** | corre 7 m; quem estiver no caminho leva 30 + a carga e é empurrado | 25 / 7 s |
| R | **Ultimate** | força 80% | 60 / 60 s |

## Ultimate (R): depende da carga (`scripts/core/ultimates.gd`)
O **elemento que mais aparece na carga** decide o ultimate (no empate, o que entrou primeiro). Os outros elementos da carga vão junto como **reforço** (por exemplo, Terra, Terra, Fogo = Terremoto que também queima). O HUD mostra qual sairia.

| Elemento dominante | Ultimate | Efeito |
|---|---|---|
| Fogo | **Meteoro** | cai no cursor (até 14 m) após 1 s: Fogo×2 + Terra×2 num raio de 4,5 m e empurrão; atinge aliados na Arena |
| Raio | **Tempestade** | por 5 s, um raio duplo a cada 0,5 s num inimigo a até 14 m |
| Frio / Gelo | **Inverno** | congela por 3,5 s os inimigos a até 10 m |
| Vida | **Bênção** | revive e cura o seu time |
| Terra | **Terremoto** | 60 de dano e **atordoa** 1,5 s os inimigos a até 7 m |
| Arcano | **Cataclismo** | depois de 1 s, explosão de 120 no cursor (raio 4 m) |
| Água / Vapor | **Maremoto** | onda à frente (9 m) que molha forte e empurra |
| Escudo | **Fortaleza** | anel de 8 barreiras e escudo (metade do dano por 5 s) no time a até 8 m |
| Vazio | **Eclipse** | 30 de dano + Vazio×2 nos inimigos a até 9 m: some escudo, proteção e bônus e eles perdem mana |
| Gravidade | **Singularidade** | suga os inimigos a até 8 m do cursor para o centro, 40 de dano e atordoa 1 s |
| Fumaça | **Cortina de fumaça** | cega os inimigos a até 8 m e deixa o seu time por perto invisível por 3 s |

## Elementos
| Elemento | Dano base* | Efeito |
|---|---|---|
| Água | 4 | molha, apaga fogo |
| Vida | −30 (cura) | levanta caídos |
| Escudo | 0 | barreiras / proteção |
| Frio | 10 | resfria (lentidão), apaga fogo |
| Raio | 30 | dano dobrado em alvo molhado |
| Arcano | 35 | — |
| Terra | 40 | estilhaça congelado (2×) |
| Fogo | 15 | incendeia (8/s por 4 s) ou seca alvo molhado |
| Vapor (Água+Fogo) | 20 | molha |
| Gelo (Água+Frio) | 25 | resfria |
| Vazio | 25 | desfaz escudo, proteção elemental, aceleração e fortificação; drena 15 de mana |
| Gravidade | 20 | **puxa** o alvo para quem lançou (em vez de empurrar) e deixa **pesado** (−30% de velocidade por 2 s) |
| Fumaça | 5 | **cega** por 3 s; Água tira a fumaça |

\* Por acerto, ou por segundo no Raio laser. Multiplicado pela força da classe e pelo nível/itens.

## Estados e interações
- **Molhado** (Água, Vapor): Raio causa 2×. Fogo seca em vez de incendiar.
- **Queimando** (Fogo): 8 de dano por segundo por 4 s. Água e Frio apagam.
- **Resfriado** (Frio, Gelo): metade da velocidade.
- **Congelado** (Frio/Gelo em alvo molhado, ou o Inverno): não anda nem age. **Terra estilhaça** (2×); **Fogo descongela**.
- **Atordoado** (Terremoto): não anda nem age, sem o gelo.
- **Lento** (Maldição, Desafio), **marcado** (Maldição, Marca: leva mais dano), **acelerado** e **fortificado** (Grito).
- **Cego** (Fumaça): inimigos e tropas não conseguem atacar; personagens causam metade do dano.
- **Pesado** (Gravidade): −30% de velocidade.
- **Proteção elemental** (Bênção com carga): imune aos elementos da carga por 10 s.
- **Empurrão**: projéteis (mais com Terra), golpe, Golpe giratório, Investida, Maremoto, Cataclismo e Meteoro. O Brutamontes resiste (30%).
- Estruturas não queimam, não congelam, não são atordoadas nem ficam lentas.

## Barreiras (Fortaleza)
| Carga | Resultado |
|---|---|
| Só Escudo | paredes que bloqueiam movimento e projéteis por 6 s |
| Escudo + Terra | muros de pedra: mais grossos, duram 12 s |
| Escudo + outros | **paredes elementais**: aplicam os elementos (por segundo) em quem encostar, aliados também; com Vida, curam |

## Controles (padrão)
Todas as teclas podem ser trocadas em **Configurações**, no lobby (salvas em `user://settings.cfg`).
- **Andar:** **botão direito** no chão: o personagem vai até lá pelo caminho mais curto, contornando obstáculos; segurando, segue o cursor. As setas também andam.
- **Mira:** sempre no ponteiro do mouse.
- **D F G:** carregar elementos. **Q W E R:** skills. **Botão esquerdo:** golpe. **B:** loja (MOBA). **Esc:** sair.

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
- **Cair e reviver:** com a vida em 0, o personagem cai, não age e não recebe dano. Um aliado o levanta com o **W** (mouse sobre ele), com qualquer elemento **Vida** nele ou com o ultimate **Bênção**.
- **Vitória:** limpar a onda 5. **Derrota:** todos caídos ao mesmo tempo. O host aperta **R** para jogar de novo (só na tela de fim).

## Modo MOBA (`scripts/moba/`)
Escolhido no lobby (**Modo: MOBA (3v3)**). Cada jogador escolhe o time Azul ou Vermelho; com **Completar os times com bots**, o host completa os dois times até 3 campeões controlados pelo computador. Em "Jogar sozinho" no modo MOBA, você joga com 2 bots aliados contra 3 bots.

**Mapa** (desenho original, `moba_map.gd`): 132 × 72 m, com a base de cada time numa ponta, **duas rotas** (norte e sul) e uma **selva** entre elas. O lado Vermelho é o espelho do Azul.

**Estruturas** (`structure.gd`), por time:
| Estrutura | Vida | Fica protegida até cair... |
|---|---|---|
| Torre externa (1 por rota) | 2200 | — |
| Torre interna (1 por rota) | 2200 | a torre externa da rota |
| Inibidor (1 por rota) | 1600 | a torre interna da rota |
| Torre do nexus | 2200 | qualquer um dos inibidores |
| Nexus | 3200 | a torre do nexus |

- **Torres** atiram a cada 1 s num inimigo a até 10 m: tropas primeiro (40% da vida delas), campeões (90) só sem tropas por perto. Ignoram a selva e o Assassino invisível.
- **Inibidor** destruído: o time inimigo ganha uma **supertropa** por leva naquela rota; ele renasce depois de 90 s.
- **Nexus** destruído: o outro time vence.
- Estruturas não queimam, não congelam e não são curadas por Vida.

**Tropas** (`minion.gd`): a cada 30 s (a primeira aos 15 s), cada time solta 3 tropas corpo a corpo e 2 atiradoras em cada rota. Elas seguem a rota e atacam o inimigo mais próximo: outras tropas primeiro, depois campeões e por fim estruturas desprotegidas.

**Selva** (time neutro): 2 Carniçais e 1 Golem de cada lado e o **Guardião** no fosso central. Ficam parados até levar dano, perseguem quem estiver perto e, se você fugir para longe do acampamento, voltam e se curam.
- Golem: dá a **Fúria do Golem** (+20% de dano por 60 s) a quem estiver perto. Renasce em 90 s.
- Guardião (3200 de vida): o time de quem estava mais perto ganha a **Bênção do Guardião** (+25% de dano e +0,5 de velocidade por 120 s) e 150 de ouro cada. Renasce em 3 min.

**Ouro, níveis e loja** (`progression.gd`):
- Começa com 300 de ouro e ganha 2 por segundo. Tropas, monstros e campeões que morrem perto de você (até 14 m) dão ouro e xp. Torres e inibidores dão ouro para o time todo.
- Até o nível 12; cada nível dá +8% de vida, +8% de mana e +6% de dano.
- **Loja** (tecla **B**, na fonte da base ou esperando para reaparecer), até 6 itens:

| Item | Custo | Efeito |
|---|---|---|
| Amuleto de vida | 300 | +90 de vida |
| Foco elemental | 350 | +12% de dano |
| Botas velozes | 250 | +0,8 de velocidade |
| Ampulheta | 400 | −15% nas recargas e +40 de mana |
| Couraça | 350 | +10% de armadura |

**Fonte e reaparecer:** a fonte da base cura 60 de vida por segundo e causa 400 de dano por segundo a inimigos. Quem cai volta na fonte depois de 5 s + 1,5 s por nível (no MOBA não há reviver). A fonte também recupera mana rápido.

**Sem fogo amigo no MOBA:** skills e golpes não ferem aliados; em aliados só a **Vida** tem efeito (cura). Na Arena o fogo amigo continua ligado.

**Bots** (`bot_brain.gd`): seguem a sua rota atrás das próprias tropas, lutam com as skills da classe carregando elementos da escolha deles (o Mago mantém distância; o W cura quando estão feridos; o R sai às vezes contra campeões), não entram sozinhos no alcance de torres inimigas, voltam à base com pouca vida e compram itens.

## Ainda por fazer
- [ ] Testar as skills e os ultimates em partida real com amigos
- [ ] Balancear mana, recargas e dano das skills (números iniciais)
- [ ] Ícones desenhados para as skills (hoje são caixas com o nome)
- [ ] Mais arenas e um chefe
- [ ] MOBA: balanceamento (os níveis sobem rápido), bots que também façam a selva

## Checklist de teste manual
- [ ] No lobby: escolher a classe e 3 elementos; os opostos ficam bloqueados
- [ ] Botão direito no chão: o personagem anda até lá contornando os pilares; segurando, segue o cursor
- [ ] D D F: a carga mostra 3 elementos; um 4º não entra
- [ ] Q sem carga: Orbe básico; Q com Fogo: o inimigo queima; a skill entra em recarga e gasta mana
- [ ] Sem mana, a skill não sai (o ícone fica azul "sem mana")
- [ ] W com o mouse num inimigo: ele fica lento/marcado; W no vazio: cura você
- [ ] Um amigo cai (Arena): W com o mouse nele o levanta
- [ ] E (Mago): Raio laser por 1,5 s
- [ ] R sem carga não sai; R com Fogo: Meteoro no cursor; o HUD mostra o ultimate da carga
- [ ] Assassino: W em si mesmo fica invisível; Q pelas costas causa o dobro; E salta
- [ ] Lutador: Q acerta tudo ao redor; E atropela
- [ ] Salamandra não sofre dano de Fogo; Água ou Frio a derrubam mais rápido
- [ ] Todos caídos: aparece "DERROTA"; o host aperta R e a partida recomeça
- [ ] MOBA: Jogar sozinho com o modo MOBA: 2 bots aliados e 3 inimigos; tropas saem aos 15 s
- [ ] MOBA: B na fonte abre a loja; comprar Botas aumenta a velocidade
- [ ] MOBA: atacar o Golem azul (selva, lado esquerdo): ele revida; derrotá-lo dá a Fúria do Golem
- [ ] MOBA: derrubar a torre externa libera a interna; o nexus só cai depois da torre do nexus
