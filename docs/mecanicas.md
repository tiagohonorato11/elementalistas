# Mecânicas — Elementistas

Documento de design escrito com nossas próprias palavras. A referência de gênero são jogos co-op de magos elementais (como Magicka 2), estudados **apenas por observação**. Nenhum código, asset, texto ou nome do jogo original é usado aqui. Todos os números são nossos e ficam em `scripts/core/elements.gd`.

## Elementos e teclas
| Tecla | Elemento | Dano base* | Efeito |
|---|---|---|---|
| Q | Água | 4 | molha, apaga fogo |
| W | Vida | −30 (cura) | — |
| E | Escudo | 0 | barreira / proteção |
| R | Frio | 10 | resfria (lentidão), apaga fogo |
| A | Raio | 30 | dano dobrado em alvo molhado |
| S | Arcano | 35 | — |
| D | Terra | 40 | — |
| F | Fogo | 15 | incendeia (8/s por 4s) ou seca alvo molhado |
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
- **Andar**: segurar o botão esquerdo (o mago vai em direção ao mouse) ou usar as setas. Isso substitui o WASD do plano, porque W, A, S e D são teclas de elemento.

## Ainda por fazer
- [ ] Encantar arma
- [ ] Barreiras elementais (parede de fogo etc.)
- [ ] Carga de projétil (segurar para mais força)
- [ ] Feitiços especiais com receitas próprias
- [ ] Rede (Fase 3), inimigos e ondas (Fase 4), fogo amigo e reviver

## Checklist de teste manual (Fase 2)
- [ ] Q + F mostra "Vapor" no HUD; Q + A esvazia a fila
- [ ] D + botão direito: projétil acerta o boneco (−40)
- [ ] F + botão direito segurado: spray em cone; o boneco fica "queimando"
- [ ] Q no boneco e depois A: dano dobrado
- [ ] E + botão direito: barreira à frente que some em 6 s
- [ ] W + Espaço: cura o próprio mago
