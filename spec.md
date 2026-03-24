# 📊 Especificação de Requisitos  
**Projeto:** EA de Distribuição Estatística Interativa – MetaTrader 5  

---

## 1. 🎯 Objetivo

Desenvolver um Expert Advisor (EA) para MetaTrader 5 que permita ao usuário:

- Inserir uma expressão (indicador, série ou fórmula)
- Calcular os valores dessa expressão com base no ativo e timeframe do gráfico atual
- Gerar e exibir a distribuição estatística (histograma) desses valores
- Visualizar percentis diretamente no gráfico

A ferramenta deve funcionar como um **ambiente interativo de análise estatística sobre séries temporais financeiras**.

---

## 2. 📦 Escopo

### Incluído
- Interface gráfica customizada sobre o gráfico (canvas)
- Campo de entrada textual para expressão
- Parser baseado na sintaxe do MQL5 (subconjunto controlado)
- Cálculo de séries e indicadores
- Geração de histograma com bins automáticos
- Exibição de percentis
- Configuração via parâmetros do EA
- Persistência de parâmetros básicos

### Não incluído
- Execução de ordens (não é EA de trade)
- Suporte a linguagem livre completa fora do padrão definido
- Curvas suavizadas (KDE)
- Comparação entre múltiplas distribuições
- Exportação de dados

---

## 3. ⚙️ Requisitos Funcionais

### 3.1 Inicialização

Ao adicionar o EA no gráfico:

- O sistema deve:
  - Detectar automaticamente:
    - Símbolo atual
    - Timeframe atual
  - Carregar os parâmetros configurados:
    - `BarsToAnalyze` (default: 5000)
  - Renderizar interface branca sobre o gráfico usando canvas

---

### 3.2 Interface do Usuário

A interface deve conter:

#### Área principal
- Histograma ocupando ~70% da tela

#### Área superior direita
- Label: `Função:`
- Campo de entrada (linha única)

#### Área inferior direita
- Lista de exemplos:
  - `Close`
  - `Open`
  - `High-Low`
  - `RSI(14)`
  - `ATR(14)`
  - `SMA(20)`
  - `StdDev(20)`
  - `Volume`

#### Área inferior
- Estatísticas:
  - Média
  - Mediana
  - Desvio padrão
  - Mínimo
  - Máximo

#### Área de status
- Mensagens de erro ou sucesso

---

### 3.3 Entrada do Usuário

- Campo aceita:
  - Apenas **uma linha**
  - Expressões longas
- O cálculo deve ser disparado exclusivamente ao pressionar **Enter**

---

### 3.4 Parser de Expressão

- Deve seguir a sintaxe da linguagem MQL5 (subconjunto controlado)
- Deve suportar:

#### Séries base
- `Open`, `High`, `Low`, `Close`, `Volume`

#### Derivadas
- `High-Low`
- `Close-Open`
- `(Close-Close[1])/Close[1]`

#### Indicadores
- `SMA(n)`
- `EMA(n)`
- `ATR(n)`
- `RSI(n)`
- `StdDev(n)`
- `Bands(n, deviation)`

#### Operadores
- `+`, `-`, `*`, `/`
- Parênteses

---

### 3.5 Janela de Cálculo

- Deve utilizar:
  - Últimos `N` candles fechados
- Onde:
  - `N = BarsToAnalyze`
  - Default: `5000`
- Candle em formação **não deve ser considerado**

---

### 3.6 Cálculo da Série

- Para cada candle:
  - Avaliar a expressão
- Gerar um vetor numérico:

- Ignorar valores:
- inválidos
- `NaN`
- `EMPTY_VALUE`

---

### 3.7 Distribuição (Histograma)

- Deve gerar histograma de frequência
- Número de bins:
- Calculado automaticamente

- Deve calcular:
- Frequência absoluta

---

### 3.8 Percentis

- Deve exibir linhas verticais para:
- P10
- P25
- P50 (mediana)
- P75
- P90

---

### 3.9 Estatísticas

Devem ser exibidas:

- Média
- Mediana
- Desvio padrão
- Valor mínimo
- Valor máximo

---

### 3.10 Execução

- Recalcular apenas quando:
- Usuário pressiona **Enter**

---

### 3.11 Persistência

O sistema deve lembrar:

- `BarsToAnalyze`
- Última expressão digitada (opcional)

---

### 3.12 Mensagens de Erro

O sistema deve tratar e exibir mensagens claras para:

- Expressão inválida
- Função não suportada
- Divisão por zero
- Histórico insuficiente
- Dados insuficientes

Exemplo:
Erro: ATR(2000) requer mais barras do que o disponível

---

## 4. 🚀 Requisitos Não Funcionais

### 4.1 Performance
- Tempo máximo de resposta:
- ≤ 1 segundo para:
  - 5000 barras
  - expressões simples

---

### 4.2 Usabilidade
- Interface limpa (fundo branco)
- Feedback imediato após Enter

---

### 4.3 Robustez
- Não deve travar o terminal
- Deve lidar com inputs inválidos sem crash

---

### 4.4 Compatibilidade
- Deve funcionar em qualquer símbolo/timeframe suportado pelo MT5

---

### 4.5 Escalabilidade
- Deve permitir aumento de `BarsToAnalyze` sem refatoração estrutural

---

## 5. 📐 Regras de Negócio

### 5.1 Dados
- Apenas candles **fechados** são considerados

---

### 5.2 Volume
- Deve usar:
- Volume disponível no ativo
- (tick volume se real não existir)

---

### 5.3 Avaliação da Expressão
- Avaliada candle a candle
- Índices como `[1]` referem-se ao histórico relativo

---

### 5.4 Exclusão de Dados
Valores devem ser descartados se:

- inválidos
- `NaN`
- infinitos
- `EMPTY_VALUE`

---

### 5.5 Histograma
- Deve cobrir todo o range:
min(values) → max(values)

---

## 6. 🔄 Fluxos

### 6.1 Fluxo Principal

1. Usuário adiciona EA  
2. Sistema renderiza interface  
3. Usuário digita expressão  
4. Usuário pressiona Enter  
5. Sistema valida expressão  
6. Sistema coleta dados  
7. Sistema calcula série  
8. Sistema gera distribuição  
9. Sistema plota histograma  
10. Sistema exibe estatísticas  

---

### 6.2 Fluxo de Erro

1. Usuário digita expressão inválida  
2. Pressiona Enter  
3. Sistema detecta erro  
4. Exibe mensagem clara  
5. Não realiza plot  

---

## 7. ✅ Critérios de Aceite

### 7.1 Funcionalidade básica
- [ ] Usuário consegue inserir expressão e pressionar Enter  
- [ ] Histograma é gerado corretamente  

---

### 7.2 Precisão
- [ ] Valores calculados batem com indicadores do MT5  
- [ ] Percentis são corretos  

---

### 7.3 Performance
- [ ] Tempo de resposta ≤ 1 segundo para 5000 barras  

---

### 7.4 Interface
- [ ] Tela branca renderizada corretamente  
- [ ] Campo de entrada funcional  
- [ ] Histograma visível e legível  

---

### 7.5 Robustez
- [ ] Sistema não trava com input inválido  
- [ ] Erros são exibidos corretamente  

---

### 7.6 Reprodutibilidade
- [ ] Mesma expressão gera mesmo resultado no mesmo dataset  

---

## 8. 📌 Observação Final

- O parser deve suportar apenas um subconjunto da sintaxe MQL5
- Não se trata de execução de código MQL5 real, mas sim de interpretação controlada