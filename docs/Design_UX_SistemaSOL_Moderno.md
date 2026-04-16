# Proposta de Design UX/UI — Sistema SOL Modernizado
## CBMRS — Corpo de Bombeiros Militar do Rio Grande do Sul

**Documento:** Proposta de Design e Experiência do Usuário
**Versão:** 1.0 | **Data:** 2026-03-18

---

## 1. Diagnóstico do Sistema Atual

### 1.1 Problemas Identificados (baseado nas 225 telas analisadas)

| Categoria | Problema Atual | Impacto no Usuário |
|---|---|---|
| **Cores** | Laranja/vermelho/amarelo dominam 100% da tela | Fadiga visual; dificulta leitura de dados |
| **Formulários** | Todos os campos visíveis de uma vez (15–20 por tela) | Sobrecarga cognitiva; erros de preenchimento |
| **Progresso** | Nenhum indicador de onde o usuário está no processo | Desorientação no wizard de 8 passos |
| **Status** | Texto longo ("Aguardando correção de CIA") em células de tabela | Difícil de escanear listas grandes |
| **Tabelas** | 7–9 colunas visíveis, sem responsividade | Scrollbar horizontal em telas menores |
| **Ações** | Menu de 3 pontos escondido (kebab menu) | Funcionalidades invisíveis ao usuário |
| **Feedback** | Navegação de página inteira a cada ação | Sensação de lentidão; perde contexto |
| **Tablet** | Interface desktop forçada em tablet de campo | Dificuldade para inspetor em vistoria |
| **Vazio** | Tabelas vazias sem orientação | Usuário não sabe o que fazer a seguir |
| **Notificações** | Nenhum centro de notificações visível | Usuário perde prazos e comunicados |

---

## 2. Sistema de Design Proposto

### 2.1 Identidade Visual

A identidade do CBM-RS (brasão, cores institucionais) é **preservada**, mas reposicionada: aparece no header e em elementos de destaque, não como cor de fundo de formulários.

```
PALETA DE CORES
───────────────────────────────────────────────────────────

Cor Primária        #B71C1C  (vermelho CBM — usado em header, botões primários)
Cor Primária clara  #EF5350  (hover, variações)
Cor Primária escura #7F0000  (pressed, sombras)

Cor de Destaque     #FF6D00  (laranja CBM — badges, links, ícones de ação)

Superfícies
  Fundo geral       #F4F6F8  (cinza muito claro — evita branco puro)
  Card              #FFFFFF  (branco — destaca sobre fundo)
  Sidebar           #1A237E  (azul escuro — contraste com vermelho)
  Sidebar hover     #283593

Semânticas
  Sucesso           #2E7D32  (#E8F5E9 fundo claro)
  Atenção           #E65100  (#FFF3E0 fundo claro)
  Erro              #C62828  (#FFEBEE fundo claro)
  Informação        #1565C0  (#E3F2FD fundo claro)
  Neutro            #546E7A  (#ECEFF1 fundo claro)

Texto
  Primário          #212121  (quase preto)
  Secundário        #616161  (cinza médio)
  Placeholder       #9E9E9E  (cinza claro)
  Invertido         #FFFFFF  (sobre fundos escuros)
```

### 2.2 Tipografia

```
Fonte principal:  Inter (Google Fonts — open source, excelente legibilidade)
Fonte monospace:  JetBrains Mono (números de processos, códigos)

Escala tipográfica:
  Display   32px / Bold    — títulos de página
  H1        24px / SemiBold — seções principais
  H2        20px / SemiBold — subseções
  H3        16px / SemiBold — títulos de card
  Body1     16px / Regular  — texto principal
  Body2     14px / Regular  — texto secundário
  Caption   12px / Regular  — labels, metadados
  Code      14px / Mono     — números de processo (A00003231AT001)
```

### 2.3 Componentes-chave

```
STATUS BADGE (substitui texto longo em tabelas)
┌─────────────────────────────────────────────────┐
│  ● Em análise       fundo #E3F2FD  texto #1565C0│
│  ● Aguard. pagamento fundo #FFF3E0  texto #E65100│
│  ● Deferido         fundo #E8F5E9  texto #2E7D32│
│  ● Indeferido       fundo #FFEBEE  texto #C62828│
│  ● Aguard. CIA      fundo #F3E5F5  texto #6A1B9A│
│  ● Aguard. vistoria fundo #E0F2F1  texto #00695C│
│  ● Cancelado        fundo #ECEFF1  texto #546E7A│
└─────────────────────────────────────────────────┘

PROGRESS STEPPER (wizard de 8 passos)
  ①━━━②━━━③━━━④━━━⑤━━━⑥━━━⑦━━━⑧
 [✓]    [✓]    [●]    [ ]    [ ]    [ ]    [ ]    [ ]
Envol. Local. Carac. Med.S. Riscos Elem.G Aprv. Pgto.
(concluído)(atual)                        (pendente)

CARD DE LICENCIAMENTO (substitui linha de tabela)
┌──────────────────────────────────────────────────┐
│ A 00000361 AA 001          ● Em análise          │
│ PPCI — Comércio varejista de alimentos           │
│ Rua XV de Novembro, 450 — Porto Alegre / RS      │
│ Criado em 15/10/2024        Prazo: 5 dias        │
│ ─────────────────────────────────────────────    │
│ [Consultar]  [Editar]  [Solicitar FACT]          │
└──────────────────────────────────────────────────┘
```

---

## 3. Estrutura de Navegação Redesenhada

### 3.1 Layout Geral

```
┌─────────────────────────────────────────────────────────────────────┐
│ HEADER FIXO                                                         │
│  [≡] [Logo CBM-RS] SOL · Sistema Online de Licenciamento  [🔔3][👤]│
└─────────────────────────────────────────────────────────────────────┘
┌───────────────┐┌───────────────────────────────────────────────────┐
│  SIDEBAR      ││  ÁREA DE CONTEÚDO PRINCIPAL                       │
│  (colapsável) ││                                                   │
│               ││  [Breadcrumb: Home / Meus Licenciamentos]         │
│  🏠 Início    ││                                                   │
│               ││  Conteúdo da tela atual                           │
│  📋 Meus      ││  (cards, formulários, tabelas, wizards)           │
│    Licenc.    ││                                                   │
│               ││                                                   │
│  👥 Troca     ││                                                   │
│    Envolvidos ││                                                   │
│               ││                                                   │
│  📝 FACT      ││                                                   │
│               ││                                                   │
│  ⚖️ Recursos  ││                                                   │
│               ││                                                   │
│  🔍 Consulta  ││                                                   │
│    Pública    ││                                                   │
│               ││                                                   │
│  ❓ Ajuda     ││                                                   │
└───────────────┘└───────────────────────────────────────────────────┘
```

A sidebar **colapsa para ícones** em telas menores — o conteúdo ganha espaço sem perder a navegação.

---

## 4. Mockups das Telas Principais

### TELA 1 — Dashboard (Home — Usuário Externo)

```
┌─────────────────────────────────────────────────────────────────────┐
│ [Logo CBM-RS]  SOL · Sistema Online de Licenciamento    [🔔3] [👤] │
└─────────────────────────────────────────────────────────────────────┘
┌──────────┐ ┌───────────────────────────────────────────────────────┐
│🏠 Início │ │  Bom dia, João Silva                                  │
│          │ │  Aqui está um resumo dos seus processos               │
│📋 Meus   │ │                                                       │
│  Licenc. │ │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│          │ │  │      3      │ │      1      │ │      2      │    │
│👥 Troca  │ │  │ Licenç.     │ │ Aguard.     │ │  Pendências │    │
│          │ │  │ Ativos      │ │ Pagamento   │ │  de Prazo   │    │
│📝 FACT   │ │  └─────────────┘ └─────────────┘ └─────────────┘    │
│          │ │  ┌─────────────┐                                     │
│⚖️ Recurs.│ │  │      1      │                                     │
│          │ │  │ Recurso     │                                     │
│🔍 Consul.│ │  │ em Andamento│                                     │
│          │ │  └─────────────┘                                     │
│❓ Ajuda  │ │                                                       │
│          │ │  Atividade Recente                                    │
│          │ │  ┌───────────────────────────────────────────────┐   │
│          │ │  │ hoje      CIA recebida — A00003231AT001     ⚠ │   │
│          │ │  │           Prazo para resposta: 15 dias          │   │
│          │ │  │ ontem     Vistoria agendada — A00000361AA001  ℹ │   │
│          │ │  │           Data prevista: 25/03/2026              │   │
│          │ │  │ 15/03     Boleto pago — A00002169AA001        ✓ │   │
│          │ │  │           Compensação confirmada                 │   │
│          │ │  └───────────────────────────────────────────────┘   │
│          │ │                                                       │
│          │ │  ┌──────────────────────────────────────────────┐    │
│          │ │  │  + Iniciar novo licenciamento PPCI           │    │
│          │ │  └──────────────────────────────────────────────┘    │
└──────────┘ └───────────────────────────────────────────────────────┘
```

**Diferença do sistema atual:** O sistema atual abre direto em uma lista vazia sem contexto. O novo dashboard oferece visibilidade imediata do estado de todos os processos e direciona o usuário para a próxima ação sem que ele precise procurar.

---

### TELA 2 — Lista de Licenciamentos (Meus Licenciamentos)

```
┌───────────────────────────────────────────────────────────────────┐
│  Meus Licenciamentos                    [+ Novo Licenciamento]    │
│                                                                   │
│  🔍 [Buscar por número, endereço, status...              ] [⚙]   │
│                                                                   │
│  Filtros ativos:  [Em análise ×]  [Porto Alegre ×]  [+ Filtro]  │
│                                                                   │
│  4 licenciamentos encontrados          [≡ Lista] [⊞ Cards]       │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ A 00003231 AT 001                   ● Aguardando CIA        │ │
│  │ PPCI · Apresentação de eventos                              │ │
│  │ Rua Argentina, 100 · Canoas/RS                              │ │
│  │ Atualizado há 2 dias  ⚠ Prazo CIA: 13 dias restantes        │ │
│  │ [Consultar]  [Ver CIA]  [Solicitar Recurso]                 │ │
│  └─────────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ A 00000361 AA 001                   ● Em análise            │ │
│  │ PPCI · Comércio de alimentos                                │ │
│  │ Av. Rio Grande do Sul, 450 · Porto Alegre/RS               │ │
│  │ Atualizado há 5 dias                                        │ │
│  │ [Consultar]  [Ver Marcos]                                   │ │
│  └─────────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ A 00002169 AA 001                   ● Aguard. pagamento     │ │
│  │ PPCI · Distribuidora                                        │ │
│  │ Av. Rio Grande do Sul, 1200 · Canoas/RS                    │ │
│  │ Vencimento boleto: 28/03/2026  ⚠ 10 dias                   │ │
│  │ [Consultar]  [Emitir Boleto]  [Solicitar Isenção]          │ │
│  └─────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

**Diferença do sistema atual:** A lista atual usa tabela com 7 colunas e status em texto longo. O novo design usa cards com informação contextual — o prazo aparece só quando relevante, as ações aparecem só quando aplicáveis ao status, e o usuário vê imediatamente o que requer atenção.

---

### TELA 3 — Detalhe do Licenciamento (visão geral do processo)

```
┌───────────────────────────────────────────────────────────────────┐
│  ← Meus Licenciamentos                                            │
│                                                                   │
│  A 00003231 AT 001 · PPCI                        ● Em análise    │
│  Apresentação de Eventos · Rua Argentina 100, Canoas             │
│                                                                   │
│  ┌────────────┬─────────────┬───────────┬────────────────────┐   │
│  │ Informações│  Envolvidos │  Marcos   │      Documentos    │   │
│  └────────────┴─────────────┴───────────┴────────────────────┘   │
│                                                                   │
│  LINHA DO TEMPO DO PROCESSO                                       │
│  ──────────────────────────────────────────────────────────────  │
│  ✓ Submissão          15/10/2024   Licenciamento criado          │
│  │                                                               │
│  ✓ Pagamento          22/10/2024   Taxa paga (3,4 UPF)          │
│  │                                                               │
│  ✓ Em análise         05/11/2024   Distribuído p/ Analista Silva │
│  │                                                               │
│  ● CIA emitida        12/11/2024   4 não-conformidades           │
│  │                    ⚠ Prazo para resposta: 13 dias restantes   │
│  │                    [Ver CIA completa]  [Solicitar Recurso]    │
│  │                                                               │
│  ○ Correção aguardada ...                                        │
│  │                                                               │
│  ○ Homologação        ...                                        │
│  │                                                               │
│  ○ Vistoria           ...                                        │
│  │                                                               │
│  ○ APPCI              ...                                        │
│                                                                   │
│  ──────────────────────────────────────────────────────────────  │
│  PRÓXIMA AÇÃO NECESSÁRIA                                          │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ ⚠ Você recebeu uma CIA com 4 não-conformidades              │ │
│  │   O prazo para resposta vence em 13 dias (25/03/2026)       │ │
│  │   [Ver CIA e responder]    [Solicitar Recurso]              │ │
│  └─────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

**Diferença do sistema atual:** O atual mostra apenas uma tabela de marcos sem contexto do fluxo geral. O novo mostra onde o processo está na jornada completa, o que já foi feito, o que está pendente, e qual a próxima ação — tudo em uma tela.

---

### TELA 4 — Wizard de Submissão PPCI (Passo 3 de 8)

```
┌───────────────────────────────────────────────────────────────────┐
│  Novo Licenciamento PPCI                                          │
│                                                                   │
│  ① Envolvidos  ② Localização  ③ Características  ④...  ⑧        │
│  ────✓──────────────✓──────────────●──────────────────────────── │
│                                                                   │
│  ┌───────────────────────────────────┐  ┌───────────────────┐   │
│  │  CARACTERÍSTICAS DA EDIFICAÇÃO    │  │   RESUMO          │   │
│  │                                   │  │                   │   │
│  │  Área total *                     │  │ Tipo: PPCI        │   │
│  │  ┌───────────────┐                │  │                   │   │
│  │  │  2.500,00 m²  │                │  │ RT:               │   │
│  │  └───────────────┘                │  │ João Silva        │   │
│  │                                   │  │                   │   │
│  │  Altura da edificação *           │  │ Endereço:         │   │
│  │  ┌───────────────┐                │  │ Rua Argentina     │   │
│  │  │    12,00 m    │                │  │ 100, Canoas       │   │
│  │  └───────────────┘                │  │                   │   │
│  │  ℹ Equivale a ≈ 4 pavimentos      │  │ Área: 2.500 m²    │   │
│  │                                   │  │ Altura: 12 m      │   │
│  │  Ocupação principal *             │  │                   │   │
│  │  ┌─────────────────────────────┐  │  │ ● Passo 3/8       │   │
│  │  │ F-6 Locais de reunião...  ▼ │  │  │ 62% concluído     │   │
│  │  └─────────────────────────────┘  │  │ ░░░░░░████████    │   │
│  │                                   │  └───────────────────┘   │
│  │  Número de pavimentos             │                           │
│  │  ┌───┐  ┌───┐  ┌───┐  ┌───┐      │                           │
│  │  │ 1 │  │ 2 │  │ 3 │  │ 4+│      │                           │
│  │  └───┘  └───┘  └───┘  └───┘      │                           │
│  │                  ████             │                           │
│  │                                   │                           │
│  │  Possui subsolo?                  │                           │
│  │  ( ) Não  (●) Sim                 │                           │
│  │      Quantidade: [ 1 ]            │                           │
│  │                                   │                           │
│  │  ✓ Salvo automaticamente 14:32   │                           │
│  └───────────────────────────────────┘                           │
│                                                                   │
│  [← Voltar: Localização]              [Próximo: Med. Segurança →]│
└───────────────────────────────────────────────────────────────────┘
```

**Diferença do sistema atual:** O wizard atual não tem indicador de progresso visível, não mostra resumo lateral, não salva automaticamente (perda de dados se fechar), e todos os campos do passo aparecem em uma página longa com scroll. O novo divide melhor, salva em tempo real e mostra contexto.

---

### TELA 5 — Ciência de CIA (modal redesenhado)

```
┌───────────────────────────────────────────────────────────────────┐
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                                                             │ │
│  │  📋 Comunicado de Inconformidade na Análise (CIA)           │ │
│  │                                                             │ │
│  │  Licenciamento: A 00003231 AT 001                          │ │
│  │  Emitido em: 12/11/2024 às 14:35                           │ │
│  │  Analista: Bombeiro 1ª Classe Roberto Ferreira             │ │
│  │                                                             │ │
│  │  ─────────────────────────────────────────────────────     │ │
│  │  Este documento contém 4 não-conformidades identificadas   │ │
│  │  na análise do seu projeto.                                │ │
│  │                                                             │ │
│  │  Após confirmar a ciência, o prazo de 30 dias para         │ │
│  │  apresentar correções ou recurso começa a contar.          │ │
│  │                                                             │ │
│  │  ⚠ Ao clicar em "Confirmar ciência", o prazo inicia       │ │
│  │    imediatamente e não pode ser desfeito.                  │ │
│  │                                                             │ │
│  │  [👁 Visualizar CIA completa antes de confirmar]           │ │
│  │                                                             │ │
│  │  ─────────────────────────────────────────────────────     │ │
│  │                                                             │ │
│  │          [Fechar sem confirmar]  [Confirmar ciência]       │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

**Diferença do sistema atual:** O modal atual tem apenas "Não" e "Sim" sem explicar as consequências. O novo deixa claro o que acontece ao confirmar (prazo inicia), permite visualizar o documento antes de confirmar, e elimina a ambiguidade do botão.

---

### TELA 6 — Dashboard Analista (Usuário Interno)

```
┌───────────────────────────────────────────────────────────────────┐
│ [Logo CBM-RS]  SOL — Usuário Interno · 8º BBM     [🔔5]  [👤Ana]│
└───────────────────────────────────────────────────────────────────┘
┌──────────────┐┌──────────────────────────────────────────────────┐
│  MENU INT.   ││  Dashboard — Análise Técnica                     │
│              ││                                                  │
│ 📊 Dashboard ││  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│              ││  │    12    │ │    3     │ │       47h        │ │
│ 📋 Fila de   ││  │ Em       │ │ Prazo    │ │ Tempo médio      │ │
│    Análise   ││  │ análise  │ │ urgente  │ │ de análise       │ │
│              ││  └──────────┘ └──────────┘ └──────────────────┘ │
│ ✓ Homolog.   ││                                                  │
│              ││  FILA DE ANÁLISE — ordenada por prioridade       │
│ 🔍 Consulta  ││  ┌────────────────────────────────────────────┐  │
│              ││  │ ● URGENTE  A00003231AT001  F-6  Canoas     │  │
│ 🏛 Recurso   ││  │   Reaberto por recurso · 2ª análise        │  │
│              ││  │   Aguardando há 8 dias   [Iniciar análise] │  │
│ 📝 FACT      ││  ├────────────────────────────────────────────┤  │
│              ││  │ ● NORMAL   A00000361AA001  C-1  Poa        │  │
│ ⚙ Admin     ││  │   1ª análise · Área 2.500m² · Risco Médio  │  │
│              ││  │   Aguardando há 3 dias   [Iniciar análise] │  │
│              ││  ├────────────────────────────────────────────┤  │
│              ││  │ ● NORMAL   A00002169AA001  B-2  Canoas     │  │
│              ││  │   1ª análise · Área 800m²  · Risco Baixo   │  │
│              ││  │   Aguardando há 1 dia    [Iniciar análise] │  │
│              ││  └────────────────────────────────────────────┘  │
│              ││                                                  │
│              ││  MINHA PRODUÇÃO — março/2026                     │
│              ││  ████████████████░░░░  16/20 análises concluídas │
└──────────────┘└──────────────────────────────────────────────────┘
```

**Diferença do sistema atual:** O analista atual não tem dashboard — acessa uma lista plana sem priorização. O novo mostra carga de trabalho, urgências e produtividade, e permite ao analista priorizar visualmente sem precisar abrir cada processo.

---

### TELA 7 — Interface de Análise Técnica (NCS)

```
┌───────────────────────────────────────────────────────────────────┐
│  ← Fila de Análise                                                │
│  Análise Técnica · A 00003231 AT 001                              │
│  F-6 Locais de reunião · 2.500m² · 12m altura · Canoas           │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Progresso da análise:  5 de 10 seções concluídas          │ │
│  │  ██████████░░░░░░░░░░  50%                                  │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  SEÇÕES  [✓ RT] [✓ RU] [✓ Prop.] [✓ Edif.] [● Ocup.] [Geral]… │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Ocupação — Classificação e Riscos                          │ │
│  │                                                             │ │
│  │  NCS-001 · Carga de Incêndio                                │ │
│  │  Declarado: 300 MJ/m²   Esperado para F-6: 500–800 MJ/m²  │ │
│  │  ( ) Conforme  (●) Não conforme  ( ) Não aplicável         │ │
│  │  Justificativa: [Valor declarado incompatível com...    ]   │ │
│  │                                                             │ │
│  │  NCS-002 · Grau de Risco                                    │ │
│  │  Declarado: Baixo   Esperado para F-6 > 2000m²: Alto       │ │
│  │  ( ) Conforme  (●) Não conforme  ( ) Não aplicável         │ │
│  │  Justificativa: [Grau de risco subdeclarado consideran...]  │ │
│  │                                                             │ │
│  │  NCS-003 · Subsolo                                          │ │
│  │  Declarado: Sim (1 subsolo)                                 │ │
│  │  (●) Conforme  ( ) Não conforme  ( ) Não aplicável         │ │
│  │                                                             │ │
│  │  ✓ Salvo automaticamente                   [Concluir seção]│ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  [Emitir CIA (2 NC)]    [Emitir CA]    [Deferir (sem NC)]       │
└───────────────────────────────────────────────────────────────────┘
```

**Diferença do sistema atual:** A análise atual apresenta todos os parâmetros NCS em uma única tela longa sem indicação de progresso. O novo divide por seção com progresso visível, salva automaticamente e contextualiza cada parâmetro com o valor esperado versus o declarado.

---

### TELA 8 — Interface de Vistoria (tablet — modo campo)

```
┌───────────────────────────────────────────────────────┐
│  [≡]  Vistoria · A 00003231 AT 001         [📶] [🔋] │
│                                                       │
│  F-6 · Canoas · Rua Argentina 100                    │
│  Inspetor: Sgt. Marcos Lima · Prevista: 09:00        │
│                                                       │
│  ┌─────────────────────────────────────────────────┐ │
│  │  LAUDOS A INSERIR              2/5 concluídos   │ │
│  │  ████████░░░░░░░░░░░                            │ │
│  │                                                 │ │
│  │  ✓ Laudo ART de Execução                       │ │
│  │  ✓ Laudo do RT de Execução                     │ │
│  │  ○ Laudo Complementar          [+ Inserir]     │ │
│  │  ○ Anexo D                     [+ Inserir]     │ │
│  │  ○ Laudo Parcial               [+ Inserir]     │ │
│  └─────────────────────────────────────────────────┘ │
│                                                       │
│  ┌─────────────────────────────────────────────────┐ │
│  │  PLANTAS PARA VISUALIZAÇÃO                      │ │
│  │                                                 │ │
│  │  [📄 Planta Pavimento Térreo]  → Abrir no Xodo │ │
│  │  [📄 Planta 1º Pavimento   ]  → Abrir no Xodo │ │
│  │  [📄 Planta de Situação    ]  → Abrir no Xodo │ │
│  └─────────────────────────────────────────────────┘ │
│                                                       │
│  ┌─────────────────────────────────────────────────┐ │
│  │  RELATÓRIO DE VISTORIA                          │ │
│  │                                                 │ │
│  │  Data realização: [18/03/2026         ]        │ │
│  │                                                 │ │
│  │  Observações:                                   │ │
│  │  ┌─────────────────────────────────────────┐   │ │
│  │  │ Sistema de sprinklers instalado         │   │ │
│  │  │ conforme projeto aprovado...            │   │ │
│  │  └─────────────────────────────────────────┘   │ │
│  │                                                 │ │
│  │  [  Reprovar  ]          [  Aprovar  ]         │ │
│  └─────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────┘
```

**Diferença do sistema atual:** A interface de campo atual é a mesma do desktop — pequena, difícil de tocar. O novo design usa elementos maiores (touch targets ≥ 44px), fluxo linear claro e funciona offline com sincronização posterior.

---

### TELA 9 — Central de Notificações

```
┌───────────────────────────────────────────────────────────────────┐
│  Central de Notificações                          Marcar tudo lida│
│                                                                   │
│  URGENTE                                                          │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ ● CIA recebida — A00003231AT001                             │ │
│  │   Prazo para resposta vence em 13 dias (25/03/2026)        │ │
│  │   Ação necessária: confirmar ciência e preparar resposta   │ │
│  │   [Ver CIA]                                  12/03 14:35   │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  INFORMATIVO                                                      │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ ℹ Vistoria agendada — A00000361AA001                        │ │
│  │   Data prevista: 25/03/2026 às 09:00 · Turno: Manhã        │ │
│  │   Inspetor: Sgt. Marcos Lima · 8º BBM                      │ │
│  │   [Ver detalhes]                             10/03 09:00   │ │
│  ├─────────────────────────────────────────────────────────────┤ │
│  │ ✓ Pagamento confirmado — A00002169AA001                     │ │
│  │   Compensação bancária confirmada. Processo avança para    │ │
│  │   distribuição de análise.                                  │ │
│  │   [Ver licenciamento]                        08/03 16:22   │ │
│  └─────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

**Diferença do sistema atual:** O sistema atual não tem central de notificações — o usuário precisa entrar em cada processo para ver o que aconteceu. O novo agrega tudo em um local com priorização por urgência.

---

### TELA 10 — Distribuição de Vistoria (Cmd. Pelotão)

```
┌───────────────────────────────────────────────────────────────────┐
│  Distribuição de Vistoria                                         │
│                                                                   │
│  ┌─────────────────────────────┐  ┌──────────────────────────┐   │
│  │  AGUARDANDO DISTRIBUIÇÃO    │  │  INSPETORES DISPONÍVEIS  │   │
│  │  3 vistorias pendentes      │  │  Ordenado por menor carga │   │
│  │                             │  │                          │   │
│  │  ┌────────────────────────┐ │  │  ┌──────────────────────┐│   │
│  │  │ A00003231AT001  ● URG. │ │  │  │ ● Sgt. Lima    1 vis.││   │
│  │  │ F-6 · Canoas           │ │  │  │ ░░░░░░░░░░░░░░░░░░░░ ││   │
│  │  │ 2.500m²  ·  12m        │ │  │  │ [Ver vistorias]      ││   │
│  │  │ Aguard. há 5 dias      │ │  │  ├──────────────────────┤│   │
│  │  │ [Ver completo]         │ │  │  │ ● Cb. Souza    3 vis.││   │
│  │  │                        │ │  │  │ ░░░░░░░░░░░░░░░░░░░  ││   │
│  │  │ Distribuir para:       │ │  │  │ [Ver vistorias]      ││   │
│  │  │ ┌──────────────────┐   │ │  │  ├──────────────────────┤│   │
│  │  │ │ Selecionar insp.▼│   │ │  │  │ ● Sd. Costa    5 vis.││   │
│  │  │ └──────────────────┘   │ │  │  │ ████████████████░░░  ││   │
│  │  │ Data prevista: [    ]  │ │  │  │ [Ver vistorias]      ││   │
│  │  │ Turno: [M][T][N]       │ │  │  └──────────────────────┘│   │
│  │  │ [Distribuir →]         │ │  │                          │   │
│  │  └────────────────────────┘ │  └──────────────────────────┘   │
│  └─────────────────────────────┘                                  │
└───────────────────────────────────────────────────────────────────┘
```

---

## 5. Impacto nos Processos Existentes

### 5.1 Tabela de Impacto por Processo

| Processo | Impacto no Fluxo | Tipo de Mudança | Ganho para o Usuário |
|---|---|---|---|
| **P01 Login** | Nenhum — fluxo OAuth2 preservado | Visual apenas | Tela de login mais limpa com logo CBM centralizado |
| **P02 Cadastro RT** | Wizard com progresso visível e salvamento automático | Visual + UX | Elimina perda de dados ao fechar a aba; validação em tempo real |
| **P03 Wizard PPCI** | Stepper com 8 passos visíveis; sidebar de resumo; navegação livre entre passos concluídos | UX significativa | Usuário sabe onde está, pode voltar sem perder dados, vê resumo sempre visível |
| **P04 Análise Técnica** | Interface NCS por seção com progresso; valor esperado vs declarado visível; salvamento automático | UX significativa | Analista faz análise mais rápida com contexto; menos erro de omissão de parâmetro |
| **P05 Ciência CIA/CIV** | Modal redesenhado com explicação de consequências; botão "Visualizar antes de confirmar" | UX mínima | Elimina confirmações acidentais; usuário entende o que está assinando |
| **P06 Isenção de Taxa** | Checkbox + upload integrados na tela de pagamento; feedback imediato do status | Visual + UX | Fluxo mais claro; menos suporte necessário |
| **P07 Vistoria Presencial** | Interface tablet-first; checklist de laudos com progresso; integração Xodo direta | UX significativa | Inspetor em campo opera com muito mais facilidade; menos erros de omissão de laudo |
| **P08 APPCI/PrPCI** | Documento visualizado inline (PDF viewer); upload de PrPCI com drag-and-drop | Visual + UX | Menos cliques; preview antes de enviar |
| **P09 Troca de Envolvidos** | Formulário em etapas com status de autorização por envolvido visível em tempo real | UX mínima | RT vê quem já autorizou e quem está pendente sem precisar atualizar a página |
| **P10 Recurso CIA/CIV** | Formulário em 5 seções com stepper; visualizador do documento sendo recorrido inline | UX moderada | RT vê a CIA/CIV ao lado enquanto preenche o recurso |
| **P11 Pagamento Boleto** | Emissão com 1 clique; QR Code PIX inline; status em tempo real via WebSocket | UX + funcional | Confirmação imediata via PIX; elimina espera de 1–2 dias de compensação boleto |
| **P12 Extinção** | Checklist de aceites com status por envolvido; linha do tempo do processo | UX mínima | Transparência sobre quem ainda precisa aceitar |
| **P13 Jobs Automáticos** | Painel admin com status dos jobs, histórico de execuções, logs de erro | Visual | Sem impacto para usuário final; melhora operação do sistema |
| **P14 Renovação** | Reaproveita componentes do wizard original; destaca diferenças do processo de renovação | UX mínima | Usuário familiarizado reconhece o fluxo; diferenças ficam evidentes |

### 5.2 Mudanças que Afetam o Fluxo de Processo (não apenas visual)

#### Salvamento Automático (impacta P02, P03, P07)
```
ATUAL:  Usuário preenche formulário → clica Salvar → se fechar aba, perde tudo
NOVO:   Sistema salva a cada campo preenchido (debounce 2s) → nunca perde dados
IMPACTO: Elimina o padrão "NRO_PASSO" como único controle de progresso;
         o passo é atualizado em tempo real, não só ao clicar Próximo
```

#### Navegação Livre no Wizard (impacta P03, P14)
```
ATUAL:  Usuário só avança para o próximo passo (linear obrigatório)
NOVO:   Passos já concluídos ficam clicáveis para revisão/edição
IMPACTO: Usuário pode corrigir o endereço (passo 2) após já ter preenchido
         medidas de segurança (passo 4) sem perder o que preencheu depois
```

#### PIX como Método Primário (impacta P03, P06, P08, P11, P14)
```
ATUAL:  Apenas boleto (30 dias para compensar) → job de polling diário
NOVO:   PIX QR Code gerado na tela → confirmação em segundos via webhook
IMPACTO: O passo de pagamento deixa de ser um gargalo de 1–2 dias;
         o processo avança imediatamente após o pagamento
         O job J02 (confirmação PROCERGS) é simplificado ou eliminado
```

#### Notificações em Tempo Real (impacta todos os processos)
```
ATUAL:  Usuário precisa entrar no sistema para descobrir o que aconteceu
NOVO:   WebSocket push + e-mail → usuário recebe notificação imediata
IMPACTO: Prazos de CIA/CIV são mais respeitados (usuário é alertado);
         reduz chamados de suporte "meu processo não avança"
```

#### Visualização Inline de Documentos (impacta P04, P05, P07, P10)
```
ATUAL:  Clicar no documento abre nova aba/download
NOVO:   PDF renderizado inline no browser (PDF.js)
IMPACTO: Usuário vê o documento enquanto decide o que fazer;
         sem perda de contexto da tela principal
```

---

## 6. Impacto que NÃO Ocorre (o que permanece igual)

É importante deixar claro o que **não muda** com o redesign:

| O que permanece | Motivo |
|---|---|
| Todas as regras de negócio (RNs) | Design é a apresentação; as regras ficam no backend |
| Fluxo de aprovação e estados do processo | A máquina de estados do licenciamento não muda |
| Documentos emitidos (APPCI, CIA, CIV, DA) | Layout dos PDFs gerados pode ser modernizado, mas estrutura e dados são os mesmos |
| Hierarquia de papéis (RT, Analista, Inspetor) | As permissões são as mesmas |
| Integrações (PROCERGS/Banrisul, Gov.br) | Backend inalterado |
| Dados e banco de dados | Sem impacto |
| Numeração dos processos | Sem impacto |

---

## 7. Acessibilidade e Conformidade (WCAG 2.1 AA)

O redesign deve atender o nível AA da WCAG 2.1, obrigatório para sistemas de governo:

| Requisito | Implementação |
|---|---|
| Contraste de cores | Mínimo 4,5:1 para texto normal; 3:1 para texto grande |
| Navegação por teclado | Todos os elementos focáveis via Tab; foco visível |
| Leitores de tela | Atributos `aria-label`, `role`, `aria-live` nos componentes Angular Material |
| Textos alternativos | Todos os ícones com `aria-label` descritivo |
| Tamanho de alvo toque | Mínimo 44×44px (especialmente para interface tablet do inspetor) |
| Formulários | Labels explícitos; mensagens de erro descritivas; não depender só de cor |
| Tempo limite | Sessão com aviso 5 minutos antes do timeout + opção de estender |

---

## 8. Implementação Técnica do Design

### 8.1 Biblioteca de Componentes

```
Angular Material 18 (recomendado)
├── mat-stepper        → wizard PPCI (P03, P14)
├── mat-card           → cards de licenciamento
├── mat-chip           → filtros, status badges
├── mat-badge          → contador de notificações
├── mat-progress-bar   → progresso de análise, upload
├── mat-timeline       → linha do tempo do processo (custom)
├── mat-bottom-sheet   → ações no tablet (P07)
├── mat-snackbar       → feedback de salvamento automático
├── mat-dialog         → modais de ciência (P05)
└── mat-table          → tabelas internas (fila de análise)
```

### 8.2 Design Tokens (variáveis CSS)

```css
:root {
  /* Cores */
  --color-primary:     #B71C1C;
  --color-accent:      #FF6D00;
  --color-sidebar:     #1A237E;
  --color-surface:     #FFFFFF;
  --color-background:  #F4F6F8;

  /* Status */
  --status-em-analise: #1565C0;
  --status-deferido:   #2E7D32;
  --status-indeferido: #C62828;
  --status-pendente:   #E65100;
  --status-cancelado:  #546E7A;

  /* Espaçamento (base 8px) */
  --space-xs:   4px;
  --space-sm:   8px;
  --space-md:   16px;
  --space-lg:   24px;
  --space-xl:   32px;
  --space-2xl:  48px;

  /* Bordas */
  --radius-sm:  4px;
  --radius-md:  8px;
  --radius-lg:  16px;
  --radius-card: 12px;

  /* Sombras */
  --shadow-card: 0 2px 8px rgba(0,0,0,0.08);
  --shadow-modal: 0 8px 32px rgba(0,0,0,0.16);
}
```

### 8.3 Responsividade

```
Mobile  (< 600px):  Sidebar oculta → menu bottom navigation
Tablet  (600–960px): Sidebar colapsada (ícones) → interface campo P07
Desktop (> 960px):  Sidebar expandida + layout de 2 colunas
Wide    (> 1440px): Layout de 3 colunas (lista + detalhe + ações)
```

---

## 9. Métricas de Sucesso do Redesign

Para validar que o novo design realmente melhora a experiência, medir antes e depois:

| Métrica | Como medir | Meta |
|---|---|---|
| Tempo para submeter PPCI | Cronometrar usuário real (P03) | Reduzir 30% vs atual |
| Taxa de abandono do wizard | Analytics — quantos chegam ao passo 8 | Aumentar de X% para >85% |
| Chamados de suporte "como faço" | Registro de suporte | Reduzir 50% |
| Erros de prazo CIA/CIV | Processos com prazo vencido | Reduzir 70% (notificações) |
| Tempo médio de análise (P04) | Diferença data distribuição → conclusão | Reduzir 20% |
| Satisfação do usuário | Formulário NPS após uso | Score ≥ 7,0 |
| Acessibilidade | Auditoria Lighthouse | Score ≥ 90 |

---

*Este documento de design deve ser validado com usuários reais (RT, analistas, inspetores, gestores) antes da implementação. Recomenda-se conduzir sessões de usabilidade com protótipos navegáveis (Figma) para cada perfil de usuário antes de iniciar o desenvolvimento frontend.*

---

## 10. Novas Telas — Requisitos Normativos (RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª Ed./2022)

As seções a seguir detalham mockups e comportamentos de telas derivadas diretamente de obrigações normativas das Resoluções Técnicas do CBMRS. Cada tela indica a cláusula que a fundamenta.

---

### NOVA TELA 1 — Wizard P03: Modal de Confirmação de Campos Imutáveis (Passo 2)

**Contexto:** Antes de avançar do Passo 2 (Localização e Isolamento de Riscos) para o Passo 3, o sistema exibe obrigatoriamente este modal. Uma vez confirmado, os campos de endereço e isolamento de riscos ficam bloqueados para edição. Qualquer alteração posterior exige extinção e reabertura do processo.

**Fundamentação:** item 6.3.2.1 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

#### Modal de Confirmação Obrigatória

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                                                                 │  │
│  │  ╔═══════════════════════════════════════════════════════════╗  │  │
│  │  ║   ATENCAO — CONFIRMACAO OBRIGATORIA                       ║  │  │
│  │  ╚═══════════════════════════════════════════════════════════╝  │  │
│  │                                                                 │  │
│  │  Os dados informados neste passo NÃO PODERÃO ser alterados     │  │
│  │  após o envio. Qualquer correção exigirá a extinção do         │  │
│  │  processo atual e a abertura de um novo licenciamento.         │  │
│  │                                                                 │  │
│  │  Verifique com atenção os campos abaixo antes de continuar:    │  │
│  │                                                                 │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │  CAMPOS QUE SERAO BLOQUEADOS APOS O ENVIO               │  │
│  │  │  ─────────────────────────────────────────────────────  │  │
│  │  │                                                         │  │
│  │  │  Endereço         Rua Argentina, 100                    │  │
│  │  │  CEP               96200-000                            │  │
│  │  │  Município         Canoas / RS                          │  │
│  │  │  Isolamento de     Isolamento por distância —           │  │
│  │  │  Riscos            Afastamento frontal 5,00 m           │  │
│  │  │                                                         │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  │                                                                 │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │  [_] Confirmo que os dados acima estão corretos e       │  │
│  │  │      entendo que NÃO PODERÃO ser alterados após o envio │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  │                                                                 │  │
│  │  Fundamentação normativa:                                       │  │
│  │  "Conforme item 6.3.2.1 da RT de Implantação SOL-CBMRS         │  │
│  │  4ª Edição/2022"                                                │  │
│  │                                                                 │  │
│  │  ─────────────────────────────────────────────────────────     │  │
│  │                                                                 │  │
│  │  [ Voltar e Revisar ]         [ Confirmar e Enviar (○) ]       │  │
│  │                                  (desabilitado até marcar       │  │
│  │                                   o checkbox acima)            │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

Legenda:
  [_]  checkbox desmarcado — impede o envio enquanto vazio
  (○)  botão desabilitado (cinza, não clicável)
  Ao marcar o checkbox, o botão "Confirmar e Enviar" torna-se clicável (●)
```

#### Estado dos Campos Após Confirmação (Passo 2 — campos bloqueados)

```
┌───────────────────────────────────────────────────────────────────────┐
│  Novo Licenciamento PPCI — Passo 2: Localização e Isolamento          │
│                                                                       │
│  ① Envolvidos  ② Localização  ③ Características  ④...  ⑧             │
│  ────✓──────────────✓──────────────●──────────────────────────────── │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  LOCALIZACAO DA EDIFICACAO                                      │  │
│  │                                                                 │  │
│  │  Endereço                                         [🔒]         │  │
│  │  ┌───────────────────────────────────────────┐                 │  │
│  │  │  Rua Argentina, 100                       │  (bloqueado)    │  │
│  │  └───────────────────────────────────────────┘                 │  │
│  │  ┌─────────────────────────────────────────────────────────┐   │  │
│  │  │ ! Imutavel — alterações exigem extinção do processo     │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  │                                                                 │  │
│  │  CEP                                              [🔒]         │  │
│  │  ┌───────────────────┐                                         │  │
│  │  │  96200-000        │  (bloqueado)                            │  │
│  │  └───────────────────┘                                         │  │
│  │  ┌─────────────────────────────────────────────────────────┐   │  │
│  │  │ ! Imutavel — alterações exigem extinção do processo     │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  │                                                                 │  │
│  │  Município                                        [🔒]         │  │
│  │  ┌───────────────────────────────────────────┐                 │  │
│  │  │  Canoas / RS                              │  (bloqueado)    │  │
│  │  └───────────────────────────────────────────┘                 │  │
│  │  ┌─────────────────────────────────────────────────────────┐   │  │
│  │  │ ! Imutavel — alterações exigem extinção do processo     │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  │                                                                 │  │
│  │  Isolamento de Riscos                             [🔒]         │  │
│  │  ┌───────────────────────────────────────────┐                 │  │
│  │  │  Isolamento por distância —               │  (bloqueado)    │  │
│  │  │  Afastamento frontal 5,00 m               │                 │  │
│  │  └───────────────────────────────────────────┘                 │  │
│  │  ┌─────────────────────────────────────────────────────────┐   │  │
│  │  │ ! Imutavel — alterações exigem extinção do processo     │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  [← Voltar: Envolvidos]                 [Próximo: Características →]  │
└───────────────────────────────────────────────────────────────────────┘

Legenda:
  [🔒]   ícone de cadeado — campo imutável, input desabilitado (background cinza)
  ! ...  badge laranja escuro "Imutavel — alterações exigem extinção do processo"
         exibido imediatamente abaixo de cada campo bloqueado
```

**Comportamento técnico:** O campo HTML fica com `disabled="true"` e `readonly`. No backend, o endpoint de atualização do passo rejeita com HTTP 409 qualquer tentativa de alterar esses campos após a confirmação. Tooltip ao hover do cadeado: "Campo bloqueado após confirmação. Conforme item 6.3.2.1 da RT de Implantação SOL-CBMRS."

---

### NOVA TELA 2 — Wizard P07: Checklist de Laudos Técnicos para Solicitação de Vistoria

**Contexto:** Passo específico do wizard de solicitação de vistoria, onde o RT deve enviar os laudos técnicos obrigatórios previstos no item 6.4.3 da RT de Implantação SOL-CBMRS 4ª Ed./2022. O botão de solicitação só é habilitado após todos os laudos obrigatórios (não marcados como "Não aplicável") serem enviados.

**Fundamentação:** item 6.4.3 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

```
┌───────────────────────────────────────────────────────────────────────┐
│  Solicitação de Vistoria — A 00003231 AT 001                          │
│                                                                       │
│  Passo: Laudos Técnicos Obrigatórios              3/4 concluídos      │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  LAUDOS TECNICOS — Item 6.4.3 da RT de Implantação SOL-CBMRS   │  │
│  │                                                                 │  │
│  │  Laudo M.1 — Compartimentação Horizontal e/ou Vertical         │  │
│  │  ┌───────────────────────────────────────────────────────────┐ │  │
│  │  │ Status:  [✓ Enviado]   laudo_compartimentacao_v2.pdf      │ │  │
│  │  │          Enviado em 15/03/2026 às 10:22                   │ │  │
│  │  │          [ Substituir arquivo ]                           │ │  │
│  │  └───────────────────────────────────────────────────────────┘ │  │
│  │                                                                 │  │
│  │  Laudo M.2 — Isolamento de Riscos                               │  │
│  │  ┌───────────────────────────────────────────────────────────┐ │  │
│  │  │ Status:  [✓ Enviado]   laudo_isolamento_riscos.pdf        │ │  │
│  │  │          Enviado em 15/03/2026 às 10:45                   │ │  │
│  │  │          [ Substituir arquivo ]                           │ │  │
│  │  └───────────────────────────────────────────────────────────┘ │  │
│  │                                                                 │  │
│  │  Laudo M.3 — Segurança Estrutural em Incêndio          (*)     │  │
│  │  ┌───────────────────────────────────────────────────────────┐ │  │
│  │  │ Status:  [! Nao enviado — obrigatorio]                    │ │  │
│  │  │                                                           │ │  │
│  │  │  Arraste o arquivo aqui ou  [ Selecionar arquivo ]        │ │  │
│  │  │  Formatos aceitos: PDF · Tamanho máximo: 20 MB            │ │  │
│  │  └───────────────────────────────────────────────────────────┘ │  │
│  │                                                                 │  │
│  │  Laudo M.4 — Controle de Materiais de Acabamento e Revestimento│  │
│  │  ┌───────────────────────────────────────────────────────────┐ │  │
│  │  │ Status:  [-- Nao aplicavel]                               │ │  │
│  │  │          Marcado como não aplicável em 14/03/2026         │ │  │
│  │  │          Justificativa: Edificação < 750 m² (RT N.01/2024)│ │  │
│  │  │          [ Alterar marcação ]                             │ │  │
│  │  └───────────────────────────────────────────────────────────┘ │  │
│  │                                                                 │  │
│  │  Laudo M.5 — Equipamentos de Utilização de Público             │  │
│  │  ┌───────────────────────────────────────────────────────────┐ │  │
│  │  │ Status:  [✓ Enviado]   laudo_equip_publico.pdf            │ │  │
│  │  │          Enviado em 16/03/2026 às 08:10                   │ │  │
│  │  │          [ Substituir arquivo ]                           │ │  │
│  │  └───────────────────────────────────────────────────────────┘ │  │
│  │                                                                 │  │
│  │  ─────────────────────────────────────────────────────────     │  │
│  │                                                                 │  │
│  │  Progresso: 3 de 4 laudos obrigatórios enviados                │  │
│  │  ████████████████████████████████░░░░░░░░  75%                 │  │
│  │                                                                 │  │
│  │  (*) Laudos obrigatórios devem ser enviados antes de           │  │
│  │      solicitar a vistoria. Laudos "Não aplicável" exigem       │  │
│  │      justificativa técnica que será validada pelo analista.    │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  [← Voltar]                         [ Solicitar Vistoria (○) ]       │
│                                       (desabilitado — 1 laudo         │
│                                        obrigatório pendente)          │
│                                                                       │
│  ! Para habilitar "Solicitar Vistoria", envie o Laudo M.3.            │
└───────────────────────────────────────────────────────────────────────┘

Legenda de status de cada laudo:
  [✓ Enviado]               fundo verde claro  — laudo presente e aceito
  [! Nao enviado — obr.]    fundo vermelho claro — impede o envio
  [-- Nao aplicavel]        fundo cinza claro   — não bloqueia, exige justificativa
  (○)  botão desabilitado (cinza, cursor not-allowed)
  (●)  botão habilitado após todos os laudos obrigatórios enviados
```

**Comportamento técnico:** O backend valida no endpoint `POST /vistoria/solicitar` se todos os laudos com `obrigatorio = true` e `naoAplicavel = false` possuem arquivo associado. Caso contrário, retorna HTTP 422 com lista dos laudos pendentes. O frontend bloqueia o botão preventivamente via estado local, mas a validação final é sempre server-side.

---

### NOVA TELA 3 — Wizard P07: Campo Anexo D (Termo de Responsabilidade das Saídas de Emergência)

**Contexto:** Campo específico presente no wizard de solicitação de vistoria, exibido como pergunta condicional. Se a edificação possuir portas de correr, enrolar ou gradil de segurança patrimonial junto à saída final de emergência, o sistema exibe o Termo de Responsabilidade completo com aceite e assinatura digital.

**Fundamentação:** item 6.4.4 da RT de Implantação SOL-CBMRS 4ª Ed./2022 e RT CBMRS N.º 11 Parte 01/2016.

```
┌───────────────────────────────────────────────────────────────────────┐
│  Solicitação de Vistoria — A 00003231 AT 001                          │
│  Passo: Anexo D — Saídas de Emergência                                │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  TERMO DE RESPONSABILIDADE — SAIDAS DE EMERGENCIA               │  │
│  │  Conforme item 6.4.4 da RT de Implantação SOL-CBMRS e           │  │
│  │  RT CBMRS N.º 11 Parte 01/2016                                  │  │
│  │                                                                 │  │
│  │  A edificação possui portas de correr, enrolar ou gradil de    │  │
│  │  segurança patrimonial localizadas junto à saída final          │  │
│  │  de emergência?                                                 │  │
│  │                                                                 │  │
│  │    (●) Sim      ( ) Não                                         │  │
│  │                                                                 │  │
│  │  ─────────────────────────────────────────────────────────     │  │
│  │                                                                 │  │
│  │  [AREA EXPANDIDA — exibida somente quando "Sim" selecionado]   │  │
│  │                                                                 │  │
│  │  ┌─────────────────────────────────────────────────────────┐   │  │
│  │  │  TEXTO DO TERMO DE RESPONSABILIDADE               [▲▼]  │   │  │
│  │  │  (área com rolagem — scroll interno)                    │   │  │
│  │  │  ─────────────────────────────────────────────────      │   │  │
│  │  │  Eu, [Nome do RT], inscrito no [CREA/CAU] sob           │   │  │
│  │  │  n.º [Número], como Responsável Técnico pelo            │   │  │
│  │  │  licenciamento n.º A 00003231 AT 001, declaro           │   │  │
│  │  │  ciência das normas estabelecidas pela RT CBMRS         │   │  │
│  │  │  N.º 11 Parte 01/2016 no que diz respeito às           │   │  │
│  │  │  saídas de emergência da edificação localizada em       │   │  │
│  │  │  Rua Argentina, 100 — Canoas/RS, e assumo integral      │   │  │
│  │  │  responsabilidade técnica pela correta operação das     │   │  │
│  │  │  portas de correr / enrolar / gradil de segurança       │   │  │
│  │  │  patrimonial instaladas junto à saída final de          │   │  │
│  │  │  emergência, garantindo que tais dispositivos           │   │  │
│  │  │  permanecerão desbloqueados durante o horário de        │   │  │
│  │  │  funcionamento do estabelecimento e poderão ser         │   │  │
│  │  │  abertos por qualquer pessoa em caso de emergência,     │   │  │
│  │  │  conforme disposições da norma supracitada.             │   │  │
│  │  │                                                         │   │  │
│  │  │  [... role para ler o termo completo ...]               │   │  │
│  │  │                                                         │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  │                                                                 │  │
│  │  ┌─────────────────────────────────────────────────────────┐   │  │
│  │  │  [_] Declaro ciência e responsabilidade pelo conteúdo   │   │  │
│  │  │      do Termo de Responsabilidade acima                 │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  │                                                                 │  │
│  │  Assinatura Digital (via Gov.br)                                │  │
│  │  ┌─────────────────────────────────────────────────────────┐   │  │
│  │  │                                                         │   │  │
│  │  │   [ Assinar com Gov.br (○) ]                            │   │  │
│  │  │   (desabilitado até marcar o checkbox acima)            │   │  │
│  │  │                                                         │   │  │
│  │  │   Após assinatura:                                      │   │  │
│  │  │   [✓ Assinado digitalmente por João Silva — 18/03/2026] │   │  │
│  │  │      Certificado ICP-Brasil via Gov.br                  │   │  │
│  │  │      Hash: a3f9...c821  [ Verificar assinatura ]        │   │  │
│  │  │                                                         │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  [← Voltar]                              [Próximo: Laudos Técnicos →] │
└───────────────────────────────────────────────────────────────────────┘

Comportamento condicional:
  "Não" selecionado → área expandida oculta; campo avança normalmente
  "Sim" selecionado → área expandida exibida com animação de expansão;
                      checkbox e assinatura Gov.br obrigatórios antes de avançar

Legenda:
  [_]  checkbox desmarcado — bloqueia o botão de assinatura
  (○)  botão Gov.br desabilitado; (●) habilitado após checkbox marcado
```

**Comportamento técnico:** A integração Gov.br segue o fluxo OAuth2 de assinatura digital (endpoint `/api/assinatura/govbr/iniciar`). O documento é enviado ao serviço de assinatura e o retorno é um PDF assinado com certificado ICP-Brasil, que fica arquivado vinculado ao marco `ANEXO_D_ASSINADO` do licenciamento.

---

### NOVA TELA 4 — Upload do PrPCI antes do Download do APPCI (P08)

**Contexto:** Tela intermediária exibida quando o RT tenta baixar o APPCI. O sistema bloqueia o download e apresenta o checklist de componentes obrigatórios do PrPCI. O download do APPCI só é liberado após o upload completo do PrPCI.

**Fundamentação:** item 6.5.1 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

```
┌───────────────────────────────────────────────────────────────────────┐
│  Emissão de APPCI — A 00003231 AT 001                                 │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  ETAPA NECESSARIA ANTES DE BAIXAR O APPCI                       │  │
│  │  Conforme item 6.5.1 da RT de Implantação SOL-CBMRS             │  │
│  │                                                                 │  │
│  │  Para liberar o download do APPCI, é obrigatório enviar o       │  │
│  │  Projeto de Proteção Contra Incêndio (PrPCI) completo.          │  │
│  │  O PrPCI ficará arquivado no sistema para fiscalização e        │  │
│  │  vistorias extraordinárias.                                     │  │
│  │                                                                 │  │
│  │  Progresso do PrPCI: 6 de 8 componentes enviados                │  │
│  │  ██████████████████████████████░░░░░░░░  75%                    │  │
│  │                                                                 │  │
│  │  COMPONENTES DO PrPCI                                           │  │
│  │  ─────────────────────────────────────────────────────────     │  │
│  │                                                                 │  │
│  │  1. Memoriais Descritivos                                       │  │
│  │     [✓ Enviado]  memorial_descritivo_ppci.pdf  (2,1 MB)        │  │
│  │                                                                 │  │
│  │  2. Memórias de Cálculo                                         │  │
│  │     [✓ Enviado]  memorias_calculo_hidraulico.pdf  (4,7 MB)     │  │
│  │                                                                 │  │
│  │  3. Certificações de Materiais e Equipamentos                   │  │
│  │     [✓ Enviado]  certificacoes_equipamentos.pdf  (1,3 MB)      │  │
│  │                                                                 │  │
│  │  4. Relatórios Técnicos de Ensaios                              │  │
│  │     [✓ Enviado]  relatorios_ensaios_sprinkler.pdf  (3,8 MB)   │  │
│  │                                                                 │  │
│  │  5. Especificações Técnicas                                     │  │
│  │     [✓ Enviado]  especificacoes_tecnicas.pdf  (1,9 MB)         │  │
│  │                                                                 │  │
│  │  6. Certificados de Treinamento de Brigadistas                  │  │
│  │     [✓ Enviado]  certificados_brigada_incendio.pdf  (0,8 MB)   │  │
│  │                                                                 │  │
│  │  7. Plano de Emergência                                         │  │
│  │     [! Pendente — obrigatorio]                                  │  │
│  │      Arraste o arquivo aqui ou  [ Selecionar arquivo ]          │  │
│  │      Formatos: PDF · Tamanho máximo: 20 MB                      │  │
│  │                                                                 │  │
│  │  8. Laudos Técnicos + ART/RRT                                   │  │
│  │     [! Pendente — obrigatorio]                                  │  │
│  │      Arraste o arquivo aqui ou  [ Selecionar arquivo ]          │  │
│  │      Formatos: PDF · Tamanho máximo: 20 MB                      │  │
│  │                                                                 │  │
│  │  ─────────────────────────────────────────────────────────     │  │
│  │                                                                 │  │
│  │  Nota: O PrPCI ficará arquivado no sistema e estará             │  │
│  │  disponível para consulta em fiscalizações e vistorias          │  │
│  │  extraordinárias realizadas pelo CBMRS.                        │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                                                                 │  │
│  │  [ Baixar APPCI (○) ]                                           │  │
│  │  (desabilitado — 2 componentes do PrPCI pendentes)              │  │
│  │                                                                 │  │
│  │  Após o envio completo do PrPCI, o botão será habilitado.       │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

Legenda:
  [✓ Enviado]          fundo verde claro — componente presente
  [! Pendente — obr.]  fundo vermelho claro — bloqueia o download
  (○)  botão desabilitado; (●) habilitado após 8/8 componentes enviados
```

**Comportamento técnico:** O endpoint `GET /appci/{id}/download` verifica se o PrPCI está completo (`prpci.status == COMPLETO`) antes de gerar o arquivo. Se incompleto, retorna HTTP 412 (Precondition Failed) com lista de componentes pendentes. O frontend intercepta esse retorno e exibe esta tela em vez de iniciar o download.

---

### NOVA TELA 5 — Badge "EM RECURSO — Bloqueado para Edição" (P10)

**Contexto:** Enquanto um recurso estiver em andamento (P10), o processo entra em estado especial de bloqueio. O sistema impede qualquer upload, edição ou movimentação que possa interferir no julgamento do recurso.

**Fundamentação:** regras de negócio RN-089 (P10) — recurso bloqueia ações paralelas sobre o processo.

#### Visão na Lista de Licenciamentos

```
┌───────────────────────────────────────────────────────────────────────┐
│  Meus Licenciamentos                        [+ Novo Licenciamento]    │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │ A 00003231 AT 001              ██ EM RECURSO — Edição bloqueada  │  │
│  │ PPCI · Apresentação de eventos — Rua Argentina 100, Canoas       │  │
│  │ Recurso protocolado em 10/03/2026                                │  │
│  │ Prazo de julgamento: 18 dias úteis restantes (vence 07/04/2026) │  │
│  │                                                                  │  │
│  │ [Consultar processo]   [Ver recurso]   [Editar (○ bloqueado)]   │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  Legenda do badge: fundo #7F0000 (vermelho escuro), texto branco,     │
│  borda sólida 2px, ícone de martelo juridico à esquerda do texto.     │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

#### Tela de Detalhe com Banner de Recurso Ativo

```
┌───────────────────────────────────────────────────────────────────────┐
│  ← Meus Licenciamentos                                                │
│                                                                       │
│  ╔═══════════════════════════════════════════════════════════════════╗ │
│  ║  AVISO — PROCESSO EM FASE DE RECURSO                              ║ │
│  ║                                                                   ║ │
│  ║  Este processo está em fase de recurso (P10). Qualquer            ║ │
│  ║  alteração, upload ou movimentação cancelará o recurso            ║ │
│  ║  em andamento. Aguarde o resultado do julgamento.                 ║ │
│  ║                                                                   ║ │
│  ║  Prazo: 18 dias úteis restantes (vencimento: 07/04/2026)         ║ │
│  ║  [ Ver detalhes do recurso ]                                      ║ │
│  ╚═══════════════════════════════════════════════════════════════════╝ │
│                                                                       │
│  A 00003231 AT 001 · PPCI                   ██ EM RECURSO             │
│  Apresentação de Eventos · Rua Argentina 100, Canoas                  │
│                                                                       │
│  ┌────────────┬─────────────┬───────────┬────────────────────────┐   │
│  │ Informações│  Envolvidos │  Marcos   │      Documentos        │   │
│  └────────────┴─────────────┴───────────┴────────────────────────┘   │
│                                                                       │
│  LINHA DO TEMPO DO PROCESSO                                           │
│  ──────────────────────────────────────────────────────────────────  │
│  ✓ Submissão            15/10/2024   Licenciamento criado            │
│  │                                                                   │
│  ✓ Pagamento            22/10/2024   Taxa paga                       │
│  │                                                                   │
│  ✓ CIA emitida          12/11/2024   4 não-conformidades             │
│  │                                                                   │
│  ✓ Ciência confirmada   15/11/2024   Prazo de resposta iniciado      │
│  │                                                                   │
│  ⚖ Recurso protocolado  10/03/2026   Em julgamento pela CIA/CIV      │
│  │  Prazo: 18 dias úteis restantes                                   │
│  │  [Ver recurso completo]                                           │
│  │                                                                   │
│  ○ Resultado do recurso  ...                                         │
│  │                                                                   │
│  ○ Continuidade do processo  ...                                     │
│                                                                       │
│  ACOES DISPONIVEIS                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  [Consultar processo]     [Ver recurso]                         │  │
│  │                                                                 │  │
│  │  [ Upload de documentos (○) ]   [ Editar dados (○) ]           │  │
│  │    Tooltip: "Bloqueado durante     Tooltip: "Bloqueado durante  │  │
│  │    fase de recurso. Aguarde        fase de recurso. Aguarde     │  │
│  │    o resultado do julgamento."     o resultado do julgamento."  │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

Legenda:
  ██ EM RECURSO   badge vermelho escuro (#7F0000), texto branco, ícone ⚖
  ╔═ AVISO ═╗     banner topo, fundo #FFEBEE (vermelho muito claro),
                  borda esquerda sólida 4px #C62828
  (○)  botão desabilitado com cursor "not-allowed" e tooltip explicativo
  ⚖   ícone de balança na timeline indicando fase jurídica
  Contador de prazo em vermelho quando <= 5 dias úteis restantes
```

---

### NOVA TELA 6 — Estado SUSPENSO: Como o Processo Aparece ao Cidadão

**Contexto:** Um processo é suspenso automaticamente quando há CIA ou CIV pendente sem movimentação por período superior ao previsto (6 meses para CIA sem resposta; 2 anos para CIV sem agendamento de nova vistoria, conforme regras de negócio do sistema). O cidadão visualiza o estado suspenso tanto no dashboard quanto na tela de detalhe.

#### Visão no Dashboard

```
┌───────────────────────────────────────────────────────────────────────┐
│  Meus Licenciamentos                        [+ Novo Licenciamento]    │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  A 00003231 AT 001          ⏸ SUSPENSO                          │  │
│  │  PPCI · Comércio de alimentos — Rua XV, 450, Porto Alegre       │  │
│  │                                                                  │  │
│  │  Suspenso em 10/09/2025 · Motivo: CIA sem resposta por 6 meses  │  │
│  │                                                                  │  │
│  │  Prazo original vencido em: 10/03/2025   (vermelho)             │  │
│  │                                                                  │  │
│  │  [Consultar processo]          [ Reativar processo ]            │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  Linha acinzentada: fundo #ECEFF1 (cinza claro), texto #546E7A,       │
│  badge ⏸ SUSPENSO com fundo #546E7A e texto branco.                  │
│  Prazo vencido destacado em #C62828 (vermelho).                       │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

#### Tela de Detalhe — Processo Suspenso

```
┌───────────────────────────────────────────────────────────────────────┐
│  ← Meus Licenciamentos                                                │
│                                                                       │
│  ╔═══════════════════════════════════════════════════════════════════╗ │
│  ║  PROCESSO SUSPENSO                                                ║ │
│  ║                                                                   ║ │
│  ║  Este processo foi suspenso por inatividade.                      ║ │
│  ║  Acesse o sistema para reativá-lo e corrija a pendência.          ║ │
│  ║                                                                   ║ │
│  ║  Suspenso em: 10/09/2025                                          ║ │
│  ║  Motivo: CIA sem movimentação por 6 meses                         ║ │
│  ║                                                                   ║ │
│  ║  [  Reativar processo  ]  ← leva ao passo de correção da CIA      ║ │
│  ╚═══════════════════════════════════════════════════════════════════╝ │
│                                                                       │
│  A 00003231 AT 001 · PPCI                      ⏸ SUSPENSO            │
│  Apresentação de Eventos · Rua Argentina 100, Canoas                  │
│                                                                       │
│  ─── Tooltip do badge (ao passar o cursor) ──────────────────────    │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │  Suspenso em 10/09/2025                                       │   │
│  │  Motivo: CIA sem movimentação por 6 meses                     │   │
│  │  Para reativar, corrija a CIA pendente ou solicite recurso    │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                       │
│  LINHA DO TEMPO DO PROCESSO                                           │
│  ──────────────────────────────────────────────────────────────────  │
│  ✓ Submissão            15/10/2024                                   │
│  ✓ Pagamento            22/10/2024                                   │
│  ✓ CIA emitida          12/11/2024   4 não-conformidades             │
│  ✓ Ciência confirmada   15/11/2024   Prazo de resposta iniciado      │
│  ⏸ Processo suspenso    10/09/2025   Sem resposta à CIA por 6 meses  │
│                                                                       │
│  PROXIMA ACAO                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  Para reativar o processo, você precisa:                        │  │
│  │  1. Corrigir as 4 não-conformidades da CIA, ou                  │  │
│  │  2. Solicitar recurso administrativo contra a CIA               │  │
│  │                                                                 │  │
│  │  [  Reativar processo — ir para CIA pendente  ]                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

Legenda de estados de suspensão e seus motivos:
  CIA sem movimentação por 6 meses  → motivo: "CIA/Nº [X] sem resposta"
  CIV sem agendamento por 2 anos    → motivo: "CIV sem agendamento de vistoria"

Banner superior:
  fundo #ECEFF1 (cinza muito claro), borda esquerda 4px #546E7A,
  botão "Reativar processo" em destaque primário (#B71C1C)
```

---

### NOVA TELA 7 — Botão de Interdição Imediata na Interface de Vistoria no Tablet (complemento da Tela 8 original)

**Contexto:** Complemento à Tela 8 (Interface de Vistoria — tablet). Um botão de interdição por risco iminente fica sempre visível no rodapé da tela, independentemente do scroll, permitindo ação imediata do inspetor sem necessidade de navegar pelos menus.

**Fundamentação:** item 6.4.8.4 da RT de Implantação SOL-CBMRS 4ª Ed./2022 e RT CBMRS N.º 05 Parte 06/2018.

#### Interface de Vistoria no Tablet com Botão de Interdição (rodapé fixo)

```
┌───────────────────────────────────────────────────────────────────────┐
│  [≡]  Vistoria · A 00003231 AT 001                      [📶] [🔋]    │
│                                                                       │
│  F-6 · Canoas · Rua Argentina 100                                     │
│  Inspetor: Sgt. Marcos Lima · Prevista: 09:00                         │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  LAUDOS A INSERIR                          2/5 concluídos       │  │
│  │  ████████░░░░░░░░░░░                                            │  │
│  │  ✓ Laudo ART de Execução                                        │  │
│  │  ✓ Laudo do RT de Execução                                      │  │
│  │  ○ Laudo Complementar              [+ Inserir]                  │  │
│  │  ○ Anexo D                         [+ Inserir]                  │  │
│  │  ○ Laudo Parcial                   [+ Inserir]                  │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  RELATORIO DE VISTORIA                                          │  │
│  │  Data realização: [18/03/2026      ]                            │  │
│  │  Observações:                                                   │  │
│  │  ┌───────────────────────────────────────────────────────┐     │  │
│  │  │ Sistema de sprinklers instalado conforme projeto...   │     │  │
│  │  └───────────────────────────────────────────────────────┘     │  │
│  │  [  Reprovar  ]                          [  Aprovar  ]         │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ═══════════════════════════════════════════════════════════════════  │
│  ╔═════════════════════════════════════════════════════════════════╗  │
│  ║   INTERDITAR — Risco Iminente                                   ║  │
│  ║   (botão vermelho escuro, fixo no rodapé, sempre visível)       ║  │
│  ╚═════════════════════════════════════════════════════════════════╝  │
└───────────────────────────────────────────────────────────────────────┘

Cor do botão: fundo #4A0000 (vermelho muito escuro), texto #FFFFFF,
              borda sólida 2px #7F0000, font-size 16px / Bold,
              padding 14px, touch target >= 56px de altura.
              position: fixed; bottom: 0; width: 100%;
              z-index: 1000 (sempre acima do conteúdo da página).
```

#### Modal de Confirmação de Interdição

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                                                                 │  │
│  │  INTERDITAR EDIFICACAO — Risco Iminente                         │  │
│  │  Conforme item 6.4.8.4 da RT de Implantação SOL-CBMRS e        │  │
│  │  RT CBMRS N.º 05 Parte 06/2018                                  │  │
│  │                                                                 │  │
│  │  Tipo de interdição: *                                          │  │
│  │                                                                 │  │
│  │  (●) Interdição Total                                           │  │
│  │      Impede o uso e ocupação total da edificação                │  │
│  │                                                                 │  │
│  │  ( ) Interdição Parcial                                         │  │
│  │      Restringe uso de área ou atividade específica              │  │
│  │      Área/atividade afetada: [_________________________]        │  │
│  │                                                                 │  │
│  │  Descreva o risco identificado: *                               │  │
│  │  ┌─────────────────────────────────────────────────────────┐   │  │
│  │  │                                                         │   │  │
│  │  │ [Campo de texto obrigatório — mínimo 50 caracteres]     │   │  │
│  │  │                                                         │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  │  0/50 caracteres mínimos                                        │  │
│  │                                                                 │  │
│  │  Data e hora da constatação: (preenchido automaticamente)       │  │
│  │  18/03/2026 às 09:47:32 (timestamp preciso — UTC-3)            │  │
│  │                                                                 │  │
│  │  Ao confirmar, serão notificados automaticamente:               │  │
│  │  · Chefe da SSeg                                                │  │
│  │  · Comando do Pelotão                                           │  │
│  │  · Notificação push + e-mail + marco no sistema                 │  │
│  │                                                                 │  │
│  │  ─────────────────────────────────────────────────────────     │  │
│  │                                                                 │  │
│  │  [ Cancelar ]                   [ Confirmar Interdição (●) ]   │  │
│  │                                  (habilitado após preencher     │  │
│  │                                   descrição com >= 50 chars)   │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

#### Tela de Confirmação Pós-Interdição

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                                                                 │  │
│  │  ╔═══════════════════════════════════════════════════════════╗  │  │
│  │  ║  INTERDICAO REGISTRADA COM SUCESSO                        ║  │  │
│  │  ╚═══════════════════════════════════════════════════════════╝  │  │
│  │                                                                 │  │
│  │  Tipo: Interdição Total                                         │  │
│  │  Registrada em: 18/03/2026 às 09:47:32                         │  │
│  │  Processo: A 00003231 AT 001                                   │  │
│  │  Inspetor: Sgt. Marcos Lima — Mat. 12345                       │  │
│  │                                                                 │  │
│  │  Notificações enviadas:                                         │  │
│  │  [✓] Chefe SSeg — push + e-mail (09:47:33)                     │  │
│  │  [✓] Comando do Pelotão — push + e-mail (09:47:33)             │  │
│  │  [✓] Marco registrado no sistema (09:47:32)                    │  │
│  │                                                                 │  │
│  │  [ Voltar à vistoria ]     [ Ver auto de interdição ]          │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

Comportamento técnico:
  POST /vistoria/{id}/interdicao  com payload:
    { tipo: "TOTAL" | "PARCIAL", descricaoRisco: "...", timestamp: ISO8601 }
  Resposta síncrona: marco INTERDICAO_REGISTRADA gravado
  Notificações: disparo assíncrono via EJB/fila JMS para SSeg e Pelotão
  O timestamp é gerado no servidor (não no cliente) para garantir
  precisão independentemente do relógio do tablet em campo.
```

---

### NOVA TELA 8 — Calculadora de Validade do APPCI na Tela de Emissão (P08)

**Contexto:** Antes de confirmar a emissão do APPCI, o sistema apresenta um card informativo com a validade calculada automaticamente com base no grupo de ocupação e grau de risco da edificação, e alerta sobre o prazo para solicitação de renovação.

**Fundamentação:** item 6.5.3.1 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

```
┌───────────────────────────────────────────────────────────────────────┐
│  Emissão de APPCI — A 00003231 AT 001                                 │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  VALIDADE CALCULADA DO APPCI                                    │  │
│  │  Conforme item 6.5.3.1 da RT de Implantação SOL-CBMRS           │  │
│  │                                                                 │  │
│  │  ┌───────────────────────────────────────────────────────────┐  │  │
│  │  │                                                           │  │  │
│  │  │   Validade calculada:  2 anos                             │  │  │
│  │  │   Data de emissão:     18/03/2026                         │  │  │
│  │  │   Data de vencimento:  18/03/2028                         │  │  │
│  │  │                                                           │  │  │
│  │  └───────────────────────────────────────────────────────────┘  │  │
│  │                                                                 │  │
│  │  Critério aplicado:                                             │  │
│  │  Edificações do grupo F (Locais de reunião de público) com      │  │
│  │  grau de risco médio ou alto têm validade de 2 anos,           │  │
│  │  conforme item 6.5.3.1 da RT de Implantação SOL-CBMRS.         │  │
│  │                                                                 │  │
│  │  ─────────────────────────────────────────────────────────     │  │
│  │                                                                 │  │
│  │  ╔═══════════════════════════════════════════════════════════╗  │  │
│  │  ║  ATENCAO — PRAZO PARA RENOVACAO                           ║  │  │
│  │  ║                                                           ║  │  │
│  │  ║  A renovação deve ser solicitada com pelo menos           ║  │  │
│  │  ║  2 (dois) meses de antecedência ao vencimento.           ║  │  │
│  │  ║                                                           ║  │  │
│  │  ║  Solicite a renovação até: 18/01/2028                     ║  │  │
│  │  ║  (2 meses antes de 18/03/2028)                           ║  │  │
│  │  ║                                                           ║  │  │
│  │  ║  O sistema enviará lembretes automáticos em:             ║  │  │
│  │  ║  · 6 meses antes do vencimento (18/09/2027)             ║  │  │
│  │  ║  · 3 meses antes do vencimento (18/12/2027)             ║  │  │
│  │  ║  · 2 meses antes do vencimento (18/01/2028)  ← prazo    ║  │  │
│  │  ╚═══════════════════════════════════════════════════════════╝  │  │
│  │                                                                 │  │
│  │  [ Ver como solicitar renovação (P14) ]                         │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  TABELA DE VALIDADE POR GRUPO E RISCO (referência)             │  │
│  │                                                                 │  │
│  │  Grupo  │ Risco Baixo │ Risco Médio │ Risco Alto               │  │
│  │  ───────┼─────────────┼─────────────┼──────────                │  │
│  │  A–E    │  3 anos     │  2 anos     │  1 ano                   │  │
│  │  F      │  2 anos     │  2 anos     │  1 ano    ← sua edif.    │  │
│  │  G–H    │  3 anos     │  2 anos     │  1 ano                   │  │
│  │                                                                 │  │
│  │  Fonte: item 6.5.3.1 da RT de Implantação SOL-CBMRS            │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  [← Voltar]                             [ Confirmar Emissão do APPCI ]│
└───────────────────────────────────────────────────────────────────────┘

Comportamento técnico:
  A validade é calculada no backend pelo endpoint GET /appci/{id}/preview
  com base nos campos: grupoOcupacao, grauRisco, dataEmissao.
  O resultado é exibido antes da confirmação para que o RT tome ciência.
  Ao confirmar, o APPCI é gerado com as datas de emissão e vencimento
  já calculadas e impressas no documento PDF.
  Os lembretes automáticos são agendados como Jobs no P13 (JobsAutomaticos)
  com disparo por e-mail e notificação push no sistema.
```

---

## 11. Impacto Normativo nas Telas

A tabela a seguir classifica cada tela — tanto as originais quanto as novas — indicando se deriva de obrigação normativa direta ou de melhoria de experiência do usuário (UX), e a cláusula de referência quando aplicável.

| Tela | Titulo | Origem | Clausula Normativa | Processo |
|---|---|---|---|---|
| Tela 1 (original) | Dashboard — Home | Melhoria UX | — | Todos |
| Tela 2 (original) | Lista de Licenciamentos | Melhoria UX | — | Todos |
| Tela 3 (original) | Detalhe do Licenciamento | Melhoria UX | — | Todos |
| Tela 4 (original) | Wizard PPCI — Passo 3 | Melhoria UX | — | P03 |
| Tela 5 (original) | Ciência de CIA | Melhoria UX | — | P05 |
| Tela 6 (original) | Dashboard Analista | Melhoria UX | — | P04 |
| Tela 7 (original) | Interface Análise Técnica | Melhoria UX | — | P04 |
| Tela 8 (original) | Vistoria no Tablet | Melhoria UX | — | P07 |
| Tela 9 (original) | Central de Notificações | Melhoria UX | — | Todos |
| Tela 10 (original) | Distribuição de Vistoria | Melhoria UX | — | P07 |
| **Nova Tela 1** | Modal Campos Imutáveis P03 | **Normativa** | RT Implantação SOL item 6.3.2.1 | P03 |
| **Nova Tela 1b** | Campos Bloqueados (pós-confirmação) | **Normativa** | RT Implantação SOL item 6.3.2.1 | P03 |
| **Nova Tela 2** | Checklist Laudos Técnicos P07 | **Normativa** | RT Implantação SOL item 6.4.3 | P07 |
| **Nova Tela 3** | Anexo D — Termo Saídas Emergência | **Normativa** | RT Implantação SOL item 6.4.4 · RT CBMRS N.º 11 Pt.01/2016 | P07 |
| **Nova Tela 4** | Upload PrPCI antes do APPCI | **Normativa** | RT Implantação SOL item 6.5.1 | P08 |
| **Nova Tela 5** | Badge EM RECURSO — Bloqueio | Misto (normativa + UX) | RN-089 · P10 | P10 |
| **Nova Tela 6** | Estado SUSPENSO — Visão Cidadão | Misto (normativa + UX) | Regras de prazo CIA/CIV | P04/P07 |
| **Nova Tela 7** | Botão Interdição — Tablet | **Normativa** | RT Implantação SOL item 6.4.8.4 · RT CBMRS N.º 05 Pt.06/2018 | P07 |
| **Nova Tela 7b** | Modal Confirmação Interdição | **Normativa** | RT Implantação SOL item 6.4.8.4 · RT CBMRS N.º 05 Pt.06/2018 | P07 |
| **Nova Tela 8** | Calculadora Validade APPCI | **Normativa** | RT Implantação SOL item 6.5.3.1 | P08 |

### 11.1 Resumo por Origem

| Categoria | Quantidade de telas/mockups | Percentual |
|---|---|---|
| Melhoria de UX pura | 10 | 43% |
| Derivadas de norma (RTCBMRS / RT Implantação SOL) | 10 | 43% |
| Mistas (normativa + UX) | 3 | 13% |
| **Total** | **23** | **100%** |

### 11.2 Normas Referenciadas nas Novas Telas

| Norma | Telas que a referenciam |
|---|---|
| RT de Implantação SOL-CBMRS 4ª Ed./2022 — item 6.3.2.1 | Nova Tela 1, Nova Tela 1b |
| RT de Implantação SOL-CBMRS 4ª Ed./2022 — item 6.4.3 | Nova Tela 2 |
| RT de Implantação SOL-CBMRS 4ª Ed./2022 — item 6.4.4 | Nova Tela 3 |
| RT CBMRS N.º 11 Parte 01/2016 | Nova Tela 3 |
| RT de Implantação SOL-CBMRS 4ª Ed./2022 — item 6.5.1 | Nova Tela 4 |
| RN-089 (P10 — bloqueio por recurso) | Nova Tela 5 |
| Regras de prazo CIA/CIV (6 meses / 2 anos) | Nova Tela 6 |
| RT de Implantação SOL-CBMRS 4ª Ed./2022 — item 6.4.8.4 | Nova Tela 7, Nova Tela 7b |
| RT CBMRS N.º 05 Parte 06/2018 | Nova Tela 7, Nova Tela 7b |
| RT de Implantação SOL-CBMRS 4ª Ed./2022 — item 6.5.3.1 | Nova Tela 8 |

---

*As novas telas (Seção 10) foram adicionadas em 2026-03-20 com base nas normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª Edição/2022. Devem ser validadas com analistas do CBMRS responsáveis pela interpretação normativa antes da implementação.*
