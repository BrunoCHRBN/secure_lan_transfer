# Diretrizes de Design Frontend: Anti-AI Slop & Minimalismo Humano

Este documento serve como a "Skill de Design" e a única fonte de verdade estética para a interface deste projeto. Qualquer código frontend gerado deve seguir rigorosamente as restrições abaixo para evitar interfaces genéricas ("AI slop") e garantir um visual premium, limpo e profissional.

---

## 1. Princípios de Design (The Core Constraints)

### 🚫 Proibições Estritas (Anti-AI Tells)
- **Sem Gradientes Clichês:** É proibido o uso de gradientes genéricos (ex: roxo-para-rosa, azul-para-roxo) em fundos, botões ou textos, a menos que explicitamente solicitado. Priorize cores sólidas e blocos de contraste nítidos.
- **Sem Bordas de "Bolha" (Bubbly UI):** Evite arredondamentos exagerados (`rounded-2xl` ou `rounded-3xl` em botões pequenos). O limite padrão para elementos de interface é sutil (4px a 8px).
- **Sem Sombras Densas (Muddy Shadows):** Proibido o uso de `box-shadow` escuras e pesadas. Use sombras quase invisíveis (opacidade entre 2% e 5%) ou substitua-as por bordas finas de 1px.
- **Sem Enfeites Inúteis:** Proibido adicionar formas geométricas flutuantes, linhas decorativas sem nexo ou elementos abstratos no fundo apenas para "preencher espaço". Se não tem função de usabilidade, não deve existir.

###  Diretrizes de Substituição Estética

| Elemento Clichê (AI Slop) | Substituto Humano / Premium (Clean UI) |
| :--- | :--- |
| Gradiente vibrante no fundo | Fundo sólido neutro (fosco, off-white ou dark grafite) |
| `rounded-3xl` em botões e cards | `rounded-md` (6px) ou `rounded-sm` (4px) |
| `shadow-lg` ou `shadow-xl` escura | `border border-zinc-200/80` (Light) ou `border-zinc-800` (Dark) |
| Texto cinza claro sem contraste | Texto com contraste acessível (WCAG AA/AAA) |
| Ícones genéricos coloridos | Ícones lineares minimalistas (ex: Lucide, Heroicons) com 1px ou 1.5px de espessura |

---

## 2. Sistema de Design Técnico

###  Paleta de Cores (Foco em Alta Fidelidade)
A interface deve seguir uma distribuição matemática estrita de cor: **60% Neutra (fundo), 30% Estrutural (textos/bordas), 10% Destaque (ações/links).**

*   **Modo Claro (Light Mode):**
    - Fundo Principal (`bg`): Pure White (`#FFFFFF`) ou Zinc-50 (`#FAFAFA`)
    - Superfícies/Cards: White (`#FFFFFF`) com borda fina Zinc-200 (`#E4E4E7`)
    - Texto Principal (`text`): Zinc-900 (`#18181B`)
    - Texto Secundário: Zinc-500 (`#71717A`)
*   **Modo Escuro (Dark Mode):**
    - Fundo Principal (`bg`): Zinc-950 (`#09090B`) ou Pure Black (`#000000`)
    - Superfícies/Cards: Zinc-900 (`#18181B`) com borda fina Zinc-800 (`#27272A`)
    - Texto Principal (`text`): Zinc-50 (`#FAFAFA`)
    - Texto Secundário: Zinc-400 (`#A1A1AA`)
*   **Cor de Destaque (Accent):**
    - Indigo-600 (`#4F46E5`) / Dark: Indigo-500, **OU** use apenas contraste puro (Preto no Branco / Branco no Preto).

###  Tipografia e Ritmo
- **Fonte Padrão:** Use fontes de sistema limpas e geométricas (Inter, SF Pro Display, Roboto).
- **Proporção de Escala:** Use a escala geométrica de `1.25x` (Major Third) para títulos.
- **Espaçamento (White Space):** Nunca esprema elementos. Se houver dúvida, aumente o padding (`p-6` a `p-8` em cards, `space-y-6` em layouts verticais). Deixe a interface respirar.

---

## 3. Arquitetura de Componentes Padrão (Tailwind CSS)

Ao gerar componentes, utilize estritamente estas combinações de classes:

### Botão Primário (Button)
```html
<!-- Light Mode Premium Button -->
<button class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-950 disabled:pointer-events-none disabled:opacity-50">
  Texto da Ação
</button>
```

### Card de Conteúdo (Card)
```html
<!-- Premium Minimalist Card -->
<div class="rounded-lg border border-zinc-200 bg-white p-6 shadow-sm dark:border-zinc-800 dark:bg-zinc-950">
  <h3 class="text-lg font-semibold leading-none tracking-tight text-zinc-900 dark:text-zinc-50">Título</h3>
  <p class="mt-2 text-sm text-zinc-500 dark:text-zinc-400">Descrição curta e direta aqui.</p>
</div>
```

---

## 4. UX Writing (Anti-AI Copy)

A IA tende a escrever textos corporativos falsos e entediantes. **Monitore e remova** os seguintes termos e abordagens do código final:

- **Palavras Banidas:** "Revolucionário", "Sinergia", "Potencialize", "Ecossistema", "Solução de ponta", "Simplificado", "Mergulhe profundamente", "Descubra o poder".
- **Abordagem Humana:** Use voz ativa. Escreva textos curtos. Em vez de *"Nossa plataforma inovadora simplifica sua gestão financeira"*, use *"Controle seus gastos e receitas em uma única tela"*.

---

## 5. Protocolo de Output da IA

Sempre que gerar ou alterar um código frontend com base neste arquivo, insira obrigatoriamente um comentário de uma linha no topo do arquivo modificado explicitando a decisão humana de design tomada.

*Exemplo:*
`// Design Decision: Removido box-shadow e aplicado border 1px Zinc-200 para estética minimalista profissional.`
