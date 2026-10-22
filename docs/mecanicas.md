# Mecânicas — Elementistas

Documento de design escrito com nossas próprias palavras. A referência de gênero são jogos co-op de magos elementais (como Magicka 2), estudados **apenas por observação**. Nenhum código, asset, texto ou nome do jogo original é usado aqui. Todos os números são nossos e ficam em `scripts/core/` (`elements.gd`, `classes.gd`, `ultimates.gd`).

## Antes da partida: classe e 3 elementos (lobby)
Cada jogador escolhe a **classe** e **3 elementos diferentes** entre os 12 (fica salvo no PC, por classe). O 1º fica na tecla **D**, o 2º no **F** e o 3º no **G**.
- **Opostos não podem ser escolhidos juntos** (eles se anulariam): Fogo×Frio, Água×Raio, Vida×Arcano, Terra×Raio, Vazio×Escudo e Fumaça×Água. No lobby, os opostos ficam bloqueados. A Gravidade e o Sangue não têm oposto.
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
  - Em quem recebe o W de apoio, a carga vale assim: **Vida** cura +30, **Escudo** dá uma **barreira** de 40 (absorve dano por 5 s), **Sangue** dá **roubo de vida** (20% por 6 s); os outros elementos viram proteção elemental.
- **Roubo de vida:** qualquer skill de dano com **Sangue** na carga cura quem lançou em 25% do dano causado (por Sangue). O bônus de roubo de vida vale também para o golpe básico.

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
| Q | **Orbe volátil** | projétil (30) que leva a carga. **Com carga:** cada elemento deixa a orbe 30% maior e ela **explode em área** (1,5 m + 0,75 m por elemento; Fogo +1 m) com 60% do dano e a carga em quem estiver perto. Terra empurra mais, Gravidade puxa para o centro, Raio salta para mais 2 inimigos | 15 / 1,5 s |
| W | **Bênção / Maldição** | toque: aliado ou você: cura 30 e protege contra os elementos da carga; inimigo: a carga + lento 40% e +20% de dano recebido por 4 s | 30 / 8 s |
| W (segurar 1,5 s) | **Bolha de escudo** | bolha de 3 m no Mago por 4 s: barreira de 60 nele e nos aliados dentro; a carga dá um poder (tabela abaixo). Enquanto segura, anda na metade da velocidade | 30 / 8 s |
| E | **Mini meteoro** | cai no cursor (até 14 m) após 0,6 s: 40 + a carga num raio de 3,5 m e deixa uma **zona de 3 s** com o efeito de cada elemento (tabela abaixo) | 35 / 7 s |
| R | **Ultimate** | ver tabela abaixo | 80 / 60 s |

**Bolha de escudo (W segurado) com a carga**
| Elemento | Poder da bolha |
|---|---|
| Fogo, Frio, Raio, Vapor, Gelo | aplica o elemento (fraco, 4× por segundo) nos inimigos dentro |
| Água | limpa queimadura, cegueira e sangramento dos aliados dentro |
| Vida | cura 8/s os aliados dentro |
| Terra | barreira mais forte (100) |
| Escudo | dura o dobro e **apaga** projéteis inimigos que entram |
| Arcano | **reflete** projéteis inimigos de volta |
| Vazio | **apaga** projéteis inimigos que entram |
| Gravidade | empurra os inimigos para fora |
| Fumaça | aliados dentro ficam invisíveis |
| Sangue | aliados dentro roubam vida |

**Zonas do Mini meteoro** (`scripts/gameplay/zone.gd`): 2 iguais = 1,5×, 3 iguais = 2×; elementos diferentes somam os efeitos. Afetam só inimigos (os bons, só aliados).
| Elemento | Zona |
|---|---|
| Gravidade | **magnetismo**: puxa os inimigos para o centro por 3 s |
| Fogo | **chão em brasa**: 12 de dano por segundo e queima |
| Frio | lentidão de 50%; quem fica 2,5 s dentro **congela** |
| Gelo | **estilhaços** ao cair: 30 de dano e empurra |
| Raio | **campo elétrico**: um raio (20) a cada 0,5 s num inimigo dentro |
| Água | **onda** ao cair: molha e empurra para fora; mantém molhado (combo com Raio) |
| Vapor | **nuvem escaldante**: 10/s e lentidão |
| Terra | **cratera**: +40 no impacto e atordoa 0,75 s |
| Arcano | **fenda instável**: explode de novo (50) depois de 1,5 s |
| Vida | **fonte**: cura 10/s os aliados |
| Escudo | **domo**: aliados dentro levam metade do dano |
| Vazio | **buraco do vazio**: tira proteções e drena 10 de mana/s |
| Fumaça | **nuvem**: cega os inimigos e esconde os aliados |
| Sangue | **poça**: 4/s e sangramento (quem lançou rouba vida) |

**Assassino**
| Tecla | Skill | Efeito | Mana / recarga |
|---|---|---|---|
| Q | **Adaga** | projétil rápido (24) com a carga; **pelas costas 2×** | 12 / 2 s |
| W | **Véu / Marca** | aliado ou você: **invisível** por 2,5 s (os inimigos ignoram; agir revela); inimigo: a carga + **marcado** (+30% de dano recebido) por 4 s. **Vida e Escudo na carga são sempre para o Assassino** (cura 30 / barreira de 40), mesmo mirando num inimigo | 25 / 10 s |
| E | **Passo sombrio** | salta até 6 m na direção do mouse e solta a carga (+25) em quem estiver a 2,5 m de onde cai | 25 / 8 s |
| R | **Ultimate** | força 80% | 70 / 60 s |

**Lutador**
| Tecla | Skill | Efeito | Mana / recarga |
|---|---|---|---|
| Q | **Golpe giratório** | 35 + a carga em todos a até 2,8 m, com empurrão | 15 / 4 s |
| W | **Grito / Desafio** | aliado ou você: cura 20, +30% de velocidade e −30% de dano recebido por 4 s; inimigo: a carga + lento 40% | 25 / 10 s |
| E | **Investida** | corre 7 m; quem estiver no caminho leva 30 + a carga e é empurrado | 25 / 7 s |
| R | **Ultimate** | força 80% | 60 / 60 s |

## Ultimate (R): volátil, depende da combinação (`scripts/core/ultimates.gd`)
Vale para as 3 classes. O HUD mostra qual sairia.
- **3 elementos iguais:** a versão **MEGA** daquele elemento (segunda tabela).
- **Senão:** o **elemento que mais aparece** decide o ultimate (no empate, o que entrou primeiro). Os outros elementos vão junto como **reforço** e cada um **deixa a sua zona** (a do Mini meteoro, 4 m por 3 s) no local do ultimate. Ex.: Fogo, Fogo, Gravidade = Meteoro que, ao cair, deixa um magnetismo que suga todo mundo.

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
| Sangue | **Lua de sangue** | 35 de dano e sangramento nos inimigos a até 9 m; você cura metade do dano |

**MEGA (3 iguais)**
| Carga | Ultimate | Efeito |
|---|---|---|
| Fumaça ×3 | **Mega fumaça** | nuvem de 12 m por 3 s: os inimigos ficam **cegos** e **sem visão** (a tela e o minimapa deles escurecem); o seu time some na nuvem |
| Fogo ×3 | **Chuva de meteoros** | 5 meteoros, um no cursor e os outros em volta, um a cada 0,3 s |
| Raio ×3 | **Tempestade suprema** | 8 s de raios (a cada 0,3 s) que saltam para mais 2 inimigos |
| Frio / Gelo ×3 | **Era do gelo** | congela por 3 s os inimigos a até 15 m e deixa o chão gelado (lento) por 4 s |
| Vida ×3 | **Renascer** | revive o time com a vida cheia e +30% de velocidade por 4 s |
| Terra ×3 | **Fenda** | rachadura de 16 m à frente: 100 de dano, atordoa 2 s e ergue muros de pedra dos lados |
| Arcano ×3 | **Supernova** | carrega 1,5 s e explode (180) tudo a até 10 m de você |
| Água / Vapor ×3 | **Tsunami** | onda gigante (18 m, bem larga) que molha, causa 30 e arrasta |
| Escudo ×3 | **Bastião** | o time a até 10 m fica **invulnerável** por 3 s |
| Vazio ×3 | **Apagão** | inimigos a até 12 m: 30 de dano, **silenciados** (sem skills) por 3 s, sem mana e sem proteções |
| Gravidade ×3 | **Buraco negro** | vórtice de 10 m no cursor por 4 s: suga e causa 25/s |
| Sangue ×3 | **Banquete de sangue** | 50 de dano e 6 s de sangramento nos inimigos a até 10 m; você cura **todo** o dano e o time perto ganha 30% de roubo de vida |

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
| Sangue | 10 | **sangramento**: 6 de dano por segundo por 4 s. Em si mesmo (W): **roubo de vida**. Nas skills de dano: quem lançou rouba 25% do dano |

\* Por acerto. Multiplicado pela força da classe e pelo nível/itens.

## Estados e interações
- **Molhado** (Água, Vapor): Raio causa 2×. Fogo seca em vez de incendiar.
- **Queimando** (Fogo): 8 de dano por segundo por 4 s. Água e Frio apagam.
- **Resfriado** (Frio, Gelo): metade da velocidade.
- **Congelado** (Frio/Gelo em alvo molhado, ou o Inverno): não anda nem age. **Terra estilhaça** (2×); **Fogo descongela**.
- **Atordoado** (Terremoto): não anda nem age, sem o gelo.
- **Lento** (Maldição, Desafio), **marcado** (Maldição, Marca: leva mais dano), **acelerado** e **fortificado** (Grito).
- **Cego** (Fumaça): inimigos e tropas não conseguem atacar; personagens causam metade do dano.
- **Pesado** (Gravidade): −30% de velocidade.
- **Sangrando** (Sangue): 6 de dano por segundo. A bolha com Água limpa.
- **Roubo de vida** (Sangue no W, bolha, Banquete): cura uma parte do dano que você causa.
- **Barreira** (bolha do Mago, Escudo no W, Bastião): absorve dano antes da vida. O Vazio desfaz.
- **Silenciado** (Apagão): não usa skills (o golpe básico continua).
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
- **D F G:** carregar elementos. **Q W E R:** skills. **Botão esquerdo:** golpe. **B:** loja (MOBA). **F1:** ajuda. **Esc:** sair.
- **Q, E e R saem ao soltar a tecla:** enquanto ela está apertada, o chão mostra a mira (faixa, área no cursor com o anel de alcance, área em volta ou leque). Um toque rápido lança na hora. O W do Mago continua: toque = Bênção/Maldição, segurar 1,5 s = bolha.

## Clareza na tela
- **Anéis da carga:** cada elemento carregado acende um anel da cor dele em volta do personagem (todos veem; o Assassino invisível esconde os dele).
- **Mira:** a área de cada skill aparece no chão ao segurar a tecla, na cor da carga; dourada quando o R vai sair MEGA.
- **Alvo do W:** a unidade sob o mouse ganha um anel verde (aliado) ou vermelho (inimigo).
- **Ícones desenhados** para as skills e os elementos; a recarga escurece o ícone como um relógio; o R fica dourado com "MEGA" quando a carga tem 3 iguais.
- **Skill negada** (recarga, sem mana, silenciado, R sem carga): som de erro e o ícone pisca em vermelho.
- **Dicas:** parar o mouse num ícone mostra o que a skill faz e o que a carga atual muda (área da Orbe, zonas do Mini meteoro, poder da bolha, ultimate e zonas).
- **Números de dano** sobem dos alvos na cor do último elemento; a cura sobe em verde. Avisos: Congelado!, Atordoado!, Cego!, Silenciado!, Sangrando!, Marcado!
- **Impactos:** meteoros, explosões e ultimates tremem a tela (mais forte perto); as áreas enormes (MEGA) dão um clarão.
- **Sons próprios:** bolha, Mini meteoro, zonas, ultimate e as versões MEGA.

## Som e música (`scripts/audio/`)
- **Efeitos com variação:** os sons frequentes têm de 3 a 5 versões; o jogo sorteia uma (nunca a mesma duas vezes seguidas) e varia o tom. Cada elemento tem o próprio som de área (respingo, labareda, gelo, pedra, raio, magia em tons diferentes).
- **Menos cansativo:** o toque da carga, os passos (os dos outros bem mais baixos) e os golpes ficaram mais baixos; dano contínuo pequeno não vira batucada; há um limite de efeitos ao mesmo tempo.
- **Ambiente vivo:** vento de fundo longo e sons soltos (pássaros, grilos, folhas, pio distante) em tempos e lugares aleatórios em volta de você; na luta, a natureza fica mais quieta.
- **Música em rodízio:** 4 músicas calmas, 3 de combate e 2 de chefe (CC0). Na calma toca uma música por vez, com pausas de 25 a 50 s só com o ambiente. O combate só entra quando a luta engrena (3 golpes em 8 s), segura 18 s e, ao acabar, vem uma pausa antes da próxima música calma.
- **Tela de ajuda (F1):** controles, fusões, opostos, elementos com as zonas e todos os ultimates (normal e MEGA).
- **Placar** no fim da partida: dano, cura e abates de cada jogador.

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

## Modo Mundo (RPG) (`scripts/world/`)
Terceiro modo, um mapa aberto estilo MMORPG que vai crescer aos poucos. Escolha **Modo: Mundo (RPG)** no lobby (sozinho ou com até 4 amigos). Não há fim de partida nem fogo amigo.

**Mapa** (`world_map.gd`, 96 × 72 m):
| Região | Onde | O que tem |
|---|---|---|
| Vila | sul | zona segura: fonte que cura (40/s) e recupera mana, casas, taverna, igreja, moinho; **Anciã Lira** (missões) e **Ferreiro Bruno** (loja) |
| Campos | oeste | 3 grupos de **Carniçais** (140 de vida, fracos) |
| Cemitério | leste | **Esqueletos** (200) e **Esqueletos arqueiros** (130, atiram gelo de longe) |
| Bosque | noroeste | **Golem do bosque** (900; só reage se for atacado) |
| Covil | norte | **Guardião do covil** (2200), o chefe, entre paredes de pedra |

- **Monstros:** ficam no acampamento e **atacam quem chega perto** (Carniçal a 7 m, Esqueleto a 6 m, arqueiro a 9 m, Guardião a 8 m). Se você fugir para longe, voltam e se curam. Um grupo inteiro derrotado **renasce** depois de 25 s (Campos), 30 s (Cemitério), 60 s (Golem) ou 120 s (Guardião).
- **Ouro e xp:** todo mundo a até 14 m de um monstro que cai ganha o ouro e a xp dele. Os níveis (até 12) e a loja (tecla **B** perto do Ferreiro) são os mesmos do MOBA.
- **Cair:** você volta na vila depois de 5 s + 1,5 s por nível, com a vida cheia (sem perder nada).

**Missões** (`quests.gd`): corrente em ordem, uma de cada vez. Chegue perto da Anciã (o "!" mostra missão nova e o "?" que dá para entregar) e use o botão da conversa para aceitar ou entregar.
| Missão | Objetivo | Recompensa |
|---|---|---|
| Carniçais nos campos | 5 Carniçais | 120 de ouro, 150 de xp |
| Ossos inquietos | 6 esqueletos | 160 de ouro, 220 de xp |
| O Golem do bosque | o Golem | 220 de ouro, 320 de xp |
| O Guardião do covil | o Guardião | 450 de ouro, 600 de xp |

O HUD mostra a região onde você está, nível, ouro e a missão atual.

**Próximos passos possíveis:** salvar o personagem (nível, ouro, itens, missões) entre partidas; mais regiões e monstros; masmorra; itens que caem dos monstros; mais personagens na vila; eventos e chefes de mundo.

## Modo Treino (`scripts/practice/`)
Arena de testes, como a ferramenta de treino de um MOBA: escolha **Modo: Treino** no lobby (sozinho ou hospedando para amigos testarem junto). Não há ondas nem fim de partida, e não há fogo amigo.

**Bonecos de teste** (não andam atrás de ninguém; time inimigo):
| Boneco | Vida | Particularidade |
|---|---|---|
| Comum | 1000 | alvo simples |
| Blindado | 1500 | 40% de armadura e resiste a empurrões |
| Que revida | 1000 | bate (20) a cada 1,5 s em quem estiver a até 2,5 m; não bate cego, atordoado nem em quem está invisível |

- Mostram em cima o **dano total recebido** e o **DPS dos últimos 5 s**, e os estados.
- Têm 100 de mana (para testar o Vazio).
- Depois de **4 s sem levar dano**, voltam à vida e mana cheias. Se caem, renascem em 2 s no mesmo lugar.

**Painel de treino** (lado esquerdo; tecla **Tab** mostra/esconde, configurável):
- **Mana infinita**, **Sem recarga**, **Imortal** e **Bonecos andam** (vão e voltam 4 m para os lados, para treinar a mira). Valem para todos na partida.
- **Zerar recargas**, **Encher vida/mana**, **Limpar estados** (do seu personagem) e **Zerar medidor**.
- **+ comum / + blindado / + que revida** põem bonecos (até 10); **Tirar** remove todos.
- **Classe e elementos:** escolha a classe e 3 elementos (os opostos ficam bloqueados) e aperte **Trocar agora**: o personagem troca na hora, no mesmo lugar.
- Quem cai (sem Imortal) volta sozinho em 3 s.

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
- [ ] Ícones desenhados por um artista (hoje são símbolos simples feitos por código)
- [ ] Mais arenas e um chefe
- [ ] MOBA: balanceamento (os níveis sobem rápido), bots que também façam a selva

## Checklist de teste manual
- [ ] Mundo: na vila, a Anciã tem "!"; aceitar a missão; os Carniçais atacam quando você chega perto
- [ ] Mundo: derrotar 5 Carniçais, voltar e entregar; comprar no Ferreiro (B); cair e voltar na vila
- [ ] Segurar E mostra a área no cursor; soltar lança. Segurar R com 3 iguais: área dourada
- [ ] Mouse num inimigo: anel vermelho embaixo; num aliado: verde
- [ ] Números de dano sobem dos alvos; "Congelado!" aparece ao congelar
- [ ] Q em recarga: som de erro e o ícone pisca; F1 abre a ajuda; o placar aparece no fim
- [ ] Treino: os 3 bonecos aparecem; o dano e o DPS sobem ao acertar; Tab esconde o painel
- [ ] Treino: Mana infinita + Sem recarga deixam usar as skills sem parar; trocar de classe pelo painel
- [ ] No lobby: escolher a classe e 3 elementos; os opostos ficam bloqueados
- [ ] Botão direito no chão: o personagem anda até lá contornando os pilares; segurando, segue o cursor
- [ ] D D F: a carga mostra 3 elementos; um 4º não entra
- [ ] Q sem carga: Orbe básico; Q com Fogo: o inimigo queima; a skill entra em recarga e gasta mana
- [ ] Sem mana, a skill não sai (o ícone fica azul "sem mana")
- [ ] W com o mouse num inimigo: ele fica lento/marcado; W no vazio: cura você
- [ ] Um amigo cai (Arena): W com o mouse nele o levanta
- [ ] E (Mago): Mini meteoro no cursor; com Fogo o chão queima, com Gravidade puxa os inimigos
- [ ] Mago: segurar W 1,5 s cria a bolha de escudo (a barra "escudo %" enche no ícone)
- [ ] Mago: Q com 2–3 elementos sai maior e explode em área
- [ ] R com 3 iguais (ex.: Fumaça ×3): sai a versão MEGA; quem leva a Mega fumaça fica com a tela escura
- [ ] Assassino: W com Vida no inimigo cura o próprio Assassino; com Escudo, ele ganha barreira
- [ ] Sangue: inimigo sangra (gotas vermelhas); com Sangue na carga, quem acerta recupera vida
- [ ] R sem carga não sai; R com Fogo: Meteoro no cursor; o HUD mostra o ultimate da carga
- [ ] Assassino: W em si mesmo fica invisível; Q pelas costas causa o dobro; E salta
- [ ] Lutador: Q acerta tudo ao redor; E atropela
- [ ] Salamandra não sofre dano de Fogo; Água ou Frio a derrubam mais rápido
- [ ] Todos caídos: aparece "DERROTA"; o host aperta R e a partida recomeça
- [ ] MOBA: Jogar sozinho com o modo MOBA: 2 bots aliados e 3 inimigos; tropas saem aos 15 s
- [ ] MOBA: B na fonte abre a loja; comprar Botas aumenta a velocidade
- [ ] MOBA: atacar o Golem azul (selva, lado esquerdo): ele revida; derrotá-lo dá a Fúria do Golem
- [ ] MOBA: derrubar a torre externa libera a interna; o nexus só cai depois da torre do nexus
