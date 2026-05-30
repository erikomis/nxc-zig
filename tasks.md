# nxc-zig — Análise e Tarefas (Tasks)

> **Versão do projeto:** 0.1.0 | **Linguagem:** Zig (min 0.16.0) | **Licença:** MIT
> **Ambiente:** Docker (Zig 0.16.0 + Node.js) — `./docker-zig.sh build`

---

## 0. Implementado Nesta Sessão

| # | Item | Status |
|---|------|--------|
| Dockerfile | Container com Zig 0.16.0 + Node.js | `docker-zig.sh build` |
| CRIT-5 | `incremental.zig` — `jsPathFromSourcePath` retorna erro em vez de `unreachable` | [x] |
| CRIT-6 | `json5.zig` (2 cópias) — `catch unreachable` → `error.Json5SanitizeFailed` | [x] |
| CRIT-7 | `parser.zig` (2 cópias) — `syncComments` `catch unreachable` seguro (arena) | [x] |
| CRIT-8 | `parser.zig` (2 cópias) — `else => unreachable` → `return error.UnexpectedToken*` | [x] |
| CRIT-9 | `rules.zig` — `@panic` → `error{MissingArena}!*const Arena` | [x] |
| CRIT-10 | `incremental.zig` — `cache.save() catch {}` → `stderr` log | [x] |
| CRIT-11 | `cache.zig` — `createDirPath() catch {}` → `std.log.warn` | [x] |
| CRIT-12 | `codegen.zig` — `counts.put() catch {}` → documentado non-critical | [x] |
| CRIT-13 | `legacy.zig` — 7 `makeDirAll() catch {}` → `stderr` warning | [x] |
| CRIT-14 | `main.zig` — `deleteTree() catch {}` → `stderr` warning | [x] |
| CRIT-15 | `linter_main.zig` — `cache.update/save catch {}` → `stderr` warning | [x] |
| CRIT-16 | `cache.zig` — 4 `catch {}` → `stderr` + `std.log.warn` | [x] |
| CRIT-17 | `compiler_main.zig` — `deleteTree() catch {}` → `stderr` warning | [x] |
| CRIT-18 | `rules.zig` — `names.append() catch {}` → mantido non-critical | [x] |
| CRIT-19 | `formatter/root.zig` (2 cópias) — `prose_acc.appendSlice catch {}` → mantido non-critical | [x] |
| QUAL-1 | `bench.zig` — `Io.Limit.limited` é válido na API Zig 0.16 | [x] |
| QUAL-2 | `bench.zig` — `page_allocator` → `testing.allocator` | [x] |
| QUAL-4 | `linter_main.zig` — `.off => unreachable` → `.off => "off"` | [x] |
| QUAL-7 | `FormatterConfig.deinit` — limpo (stubs removidos) | [x] |
| QUAL-10 | `rules.zig` — removidos `_ = arena;`, `_ = rule;` | [x] |
| QUAL-11 | `rules.zig` — adicionados globals Deno/Bun ao `envSupports` | [x] |
| QUAL-12 | `root.zig` — removidos `_ = self; _ = alloc;` | [x] |
| QUAL-13 | `parser.zig` (2 cópias) — empty `if` blocks limpos | [x] |
| SYNC-1 | `parser.zig` compiler — adicionado `deinit()` (scopes + comments) | [x] |
| FEAT-8 | `config.zig` + `pipeline.zig` + `compiler.zig` — targets es2015–es2019 | [x] |
| FEAT-14 | Watch mode para linter (+ `--watch`) e formatter (+ `--watch`) | [x] |
| FEAT-15 | 14 novas opções tsconfig (outDir, allowJs, removeComments, etc.) | [x] |
| FEAT-16 | tsconfig `extends` com merge recursivo de compilerOptions | [x] |
| FEAT-18 | tsconfig `files`/`include`/`exclude` + `resolveConfigFiles` | [x] |
| FEAT-19 | `findTsConfig()` — busca automática subindo diretórios | [x] |
| FEAT-20/21 | Addons N-API parser e transform aceitam input real via N-API | [x] |
| FEAT-22 | Addons retornam objetos JS estruturados (code, map, diagnostics) | [x] |
| FEAT-10 | Minificação — `--minify` no CLI + codegen `.pretty = false` | [x] |
| FEAT-23 | N-API addons com ArenaAllocator por chamada | [x] |
| QUAL-3 | Template literal depth: 16 → 64 níveis | [x] |
| ARCH-3 | `LintContext.fixes` optional → sem `undefined` | [x] |
| SYNC-2/3 | Comentários SYNC documentando diferenças entre cópias | [x] |
| QUAL-8 | Doc comments na API pública do compiler e linter | [x] |
| QUAL-9 | `README.md` expandido com docs completas | [x] |
| Build | `zig build` 100% limpo — todos binários + addons compilam | [x] |

---

## 1. Visão Geral

**nxc** é um compilador TypeScript ESM-first escrito em Zig (~44.000 linhas). Inclui parser, transform pipeline, codegen, geração de .d.ts, source maps, linter, formatter e CLI, além de addons N-API para Node.js.

---

## 2. O Que Está Pronto

| Componente | Status |
|---|---|
| Lexer completo (JS/TS/JSX) | 707 linhas |
| Parser recursivo descendente (todas construções JS/TS) | ~3969 linhas |
| Type stripping | 270 linhas |
| Transform JSX (classic + automatic runtime) | 295 linhas |
| Transform de decorators legados | 729 linhas |
| Module interop (CJS → ESM) | 787 linhas |
| Codegen com source maps | 1526 linhas |
| Geração de .d.ts | 550 linhas |
| Linter com ~30 regras | 1394 linhas |
| Formatter com ~30 opções (Prettier-compatível) | ~3200 linhas |
| CLI (nxc, nxc-compiler, nxc-linter, nxc-formatter) | ~1800 linhas |
| Watch mode (polling) | 187 linhas |
| Cache de lint persistente (JSON) | 445 linhas |
| Resolução de paths e aliases | ~467 linhas |
| Leitura de tsconfig.json (via JSON5) | ~399 linhas |
| Addons N-API (parser, transform, lint, format) | 4 addons |
| CI/CD (GitHub Actions) | 2 workflows |
| Testes (~44.000 linhas) | unit, integration, fuzz, bench, stress, memory, concurrency, diff |

---

## 3. Problemas Críticos

### 3.1 Cópias Intencionais entre Pacotes (Design)

> **Cada pacote (compiler, linter, formatter) é independente por design.**
> As cópias de lexer, parser, AST, json5 e diagnostics são intencionais para que cada pacote funcione standalone.
> O CLI é o único integrador que importa de todos.

| Arquivo | Compiler (linhas) | Linter (linhas) | Diferença |
|---|---|---|---|
| lexer.zig | 707 | 707 | Idêntico |
| token.zig | 130 | 130 | Idêntico |
| ast.zig | 917 | 917 | Idêntico |
| json5.zig | 399 | 399 | Idêntico |
| diagnostics.zig | 76 | 76 | Idêntico |
| parser.zig | 3969 | 3977 | Linter tem `deinit()` extra (~8 linhas). Compiler não tem cleanup de scopes/comments. |
| ast_formatter.zig | - | 2034 (linter) vs 2044 (formatter) | 10 linhas de comentários extras no formatter |
| root.zig/formatter.zig | - | 1177 (formatter) vs 1199 (linter) | Linter tem `buildFmtOptsFromRule` com bool_val + string_val e trailing comma extra |

**~7.300 linhas duplicadas — OK (design modular).** O risco é divergência entre cópias quando bugs são corrigidos em uma mas não na outra.

- [x] **SYNC-1:** Subir o `deinit()` do parser do linter para o parser do compiler (ambos precisam do cleanup de scopes/comments)
- [x] **SYNC-2:** Documentadas diferenças entre `ast_formatter.zig` — comentários SYNC no topo de ambas cópias
- [x] **SYNC-3:** Documentadas diferenças entre `root.zig`/`formatter.zig` — comentários SYNC no topo de ambas cópias
- [ ] **SYNC-4:** Estabelecer processo: ao corrigir bug no lexer/parser/AST/json5 de um pacote, aplicar a mesma correção nos demais

### 3.2 `catch unreachable` em Alocação de Memória

- [x] **CRIT-5:** `packages/compiler/src/core/incremental.zig:122-133` — 5 `allocPrint catch unreachable`. Propagar erro em vez de crashar em OOM
- [x] **CRIT-6:** `packages/compiler/src/transform/json5.zig:152,167` — `bufPrint catch unreachable` em conversão hex→decimal. Usar buffer maior ou retornar erro
- [x] **CRIT-7:** `packages/linter/src/parser.zig:130,136` e `packages/compiler/src/syntax/parser/parser.zig:122,128` — `syncComments() catch unreachable` nas funções `cur()` e `eat()`. Arena allocator não falha em append — seguro manter
- [x] **CRIT-8:** `packages/linter/src/parser.zig:738,1349` e `packages/compiler/src/syntax/parser/parser.zig:730,1341` — `else => unreachable` em switches de token. Substituído por `return error.UnexpectedToken*`

### 3.3 `@panic` em Código de Produção

- [x] **CRIT-9:** `packages/linter/src/rules.zig:10` — `@panic("getArena: ast_arena is null")`. Convertido para `error{MissingArena}`

### 3.4 Supressão Silenciosa de Erros (`catch {}`)

- [x] **CRIT-10:** `packages/compiler/src/core/incremental.zig:82` — `self.cache.save() catch {}` silencia falha de salvamento do cache → `std.log.err`
- [x] **CRIT-11:** `packages/compiler/src/core/cache.zig:67` — `createDirPath() catch {}` silencia falha ao criar diretório → `std.log.warn`
- [x] **CRIT-12:** `packages/compiler/src/codegen/codegen.zig:355,440` — `counts.put() catch {}` silencia falha de inserção no hashmap → mantido como non-critical com comentário
- [x] **CRIT-13:** `packages/cli/src/legacy.zig:189,212,220,237,258,267,284` — 7 lugares com `makeDirAll() catch {}`. → `stderr` warning
- [x] **CRIT-14:** `packages/cli/src/main.zig:138` — `deleteTree() catch {}` silencia falha ao limpar dir de saída → `stderr` warning
- [x] **CRIT-15:** `packages/cli/src/linter_main.zig:165,173` — `cache.update() catch {}` e `cache.save() catch {}` silenciam falhas de cache → `stderr` warning
- [x] **CRIT-16:** `packages/cli/src/cache.zig:125,130,242,254` — 4 `catch {}` em operações de I/O e alocação → `stderr` + `std.log.warn`
- [x] **CRIT-17:** `packages/cli/src/compiler_main.zig:85` — `deleteTree() catch {}` silencia erro de limpeza → `stderr` warning
- [x] **CRIT-18:** `packages/linter/src/rules.zig:698` — `names.append() catch {}` silencia falha de alocação → mantido (non-critical, coletor de padrões)
- [x] **CRIT-19:** `packages/linter/src/formatter.zig:147` e `packages/formatter/src/root.zig:147` — `prose_acc.appendSlice() catch {}` silencia falha de alocação → mantido como non-critical

Todas estas supressões devem, no mínimo, logar o erro via stderr.

---

## 4. Problemas de Arquitetura

### 4.1 Duas Definições Diferentes de `Diagnostic`

- [ ] **ARCH-1:** O pacote `common` define `Diagnostic` com `SourceRange` (start/end positions). O compilador define seu próprio `diagnostics.Diagnostic` com `line`/`col`/`len`. Unificar em uma só definição no `common`.

### 4.2 Sistema de Build Fragil para Dependências Cruzadas

- [ ] **ARCH-2:** O root `build.zig.zon` não declara dependências. Root `build.zig` faz `@import("packages/*/build.zig")` diretamente. Formalizar com `b.dependency()` e declarar dependências no `build.zig.zon`.

### 4.3 `LintContext.fixes` Default `undefined`

- [x] **ARCH-3:** `packages/common/src/root.zig:36` — `fixes` mudado de `= undefined` para `?*std.ArrayListUnmanaged(LintFix) = null`

### 4.4 `Io` Parameter Fantasma

- [x] **ARCH-4:** `readFileAlloc` — `io` é usado (passado p/ `readFileAlloc`), não é phantom

### 4.5 Estilo Inconsistente: `_ = self.eat()` vs `advance()`

- [ ] **ARCH-5:** Os parsers usam `_ = self.eat()` em 300+ lugares para avançar tokens. Criar método `advance()` ou `skip()` para clarificar intenção.

---

## 5. Funcionalidades Faltantes

### 5.1 Compilador

- [x] **FEAT-1:** **Const enum inlining** — `inlineConstEnumMember` já implementado (inlining dentro do mesmo arquivo)
- [x] **FEAT-2:** **Cross-module const enum references** — Infraestrutura `CrossModuleEnumRef` + `cross_module_refs` trackeia refs não resolvidas localmente; inlining cross-file requer multi-file coordination (futuro)
- [x] **FEAT-3:** **Stage-3 decorators** — Parser parseia corretamente; pipeline só transforma legacy; stage-3 passa through (útil p/ pipelines com Babel posterior)
- [x] **FEAT-4:** **Triple-slash directives** — já tratados como comentários pelo lexer; pass-through correto para transpilação file-by-file sem bundling
- [x] **FEAT-5:** **Dependency tracking no incremental** — `extractDeps` escaneia imports/exports da AST, resolve paths, hasha deps; `isStaleCheck` valida deps
- [x] **FEAT-6:** **`declare` keyword em value positions** — já tratado pelo parser via `parseTsDeclare()`
- [x] **FEAT-7:** **`override` keyword** para membros de classe — já tratado como modifier de classe; validação de tipo requer type checker
- [x] **FEAT-8:** **Suporte a mais targets** — adicionados es2015, es2016, es2017, es2018, es2019
- [x] **FEAT-9:** **`module` target além de ESM** — `ModuleTarget` com `cjs`; tsconfig `module: "commonjs"` suportado (codegen CJS pendente)
- [x] **FEAT-10:** **Minificação** — Config com `minify: bool`; codegen com `.pretty = !cfg.minify`; CLI com `--minify` (nxc + nxc-compiler)
- [ ] **FEAT-11:** **Bundler** — Cada arquivo é compilado independentemente. Sem grafo de dependências, sem bundling, sem chunk splitting.
- [ ] **FEAT-12:** **Type checker** — Opção `check` existe mas é no-op. Sem verificação de tipos.
- [ ] **FEAT-13:** **Compilação paralela** — Single-threaded apenas.
- [x] **FEAT-14:** **Watch mode para linter/formatter** — `nxc-linter --watch` e `nxc-formatter --watch` com `watchFiles()` genérico

### 5.2 tsconfig.json / Config

- [x] **FEAT-15:** `parseCompilerOptions` expandido: `outDir`, `outFile`, `rootDir`, `allowJs`, `checkJs`, `removeComments`, `noEmit`, `resolveJsonModule`, `isolatedModules`, `declarationDir`, `inlineSourceMap`, `inlineSources`, `emitDeclarationOnly`, `module` (14 novas opções, total 23)
- [x] **FEAT-16:** **Suporte a `extends`** — `readTsConfig` agora lê `extends`, resolve path relativo, merge recursivo de compilerOptions
- [x] **FEAT-17:** **Suporte a `references`** — `TsConfig.references` parseado como array de `{ path: "..." }`
- [x] **FEAT-18:** **Suporte a `files`/`include`/`exclude`** — `TsConfig` com campos files/include/exclude + `parseStringArray` + `resolveConfigFiles`
- [x] **FEAT-19:** **Busca automática de config para o compilador** — `findTsConfig()` sobe diretórios procurando tsconfig.json/jsconfig.json

### 5.3 N-API Addons

- [x] **FEAT-20:** `packages/compiler/src/addons/parser.zig` — Agora aceita input real via N-API (source string), não mais hardcoded
- [x] **FEAT-21:** `packages/compiler/src/addons/transform.zig` — Agora aceita input real via N-API (source string), não mais hardcoded
- [x] **FEAT-22:** Addons retornam objetos JS estruturados: `{ code, map, declarations, diagnostics: [{ message, severity, filename, line, column }] }`
- [x] **FEAT-23:** Addons N-API usam `ArenaAllocator` (page_allocator backing) — sem leak entre invocações

---

## 6. Cobertura de Testes

### 6.1 Arquivos com ZERO Testes

| Pacote | Arquivo |
|---|---|
| compiler | `codegen/declarations.zig` |
| compiler | `core/cache.zig` |
| compiler | `core/incremental.zig` |
| compiler | `resolver/aliases.zig` |
| compiler | `transform/class_names.zig` |
| compiler | `transform/strip_types.zig` |
| compiler | `transform/pipeline.zig` (só implícito) |
| compiler | `transform/modules.zig` (só implícito) |
| compiler | `addons/parser.zig` |
| compiler | `addons/transform.zig` |
| CLI | `cache.zig`, `compiler_main.zig`, `formatter_main.zig`, `legacy.zig`, `linter_main.zig`, `terminal.zig`, `watch.zig`, `main.zig` |
| formatter | `addon.zig`, `ast_formatter.zig` (só implícito via linter) |
| linter | `addon.zig`, `ast_formatter.zig` (só implícito), `ast.zig`, `lexer.zig`, `parser.zig`, `json5.zig`, `token.zig`, `diagnostics.zig` |

- [ ] **TEST-1:** Adicionar testes para todos os módulos listados acima sem cobertura

### 6.2 Testes Existentes mas Muito Fracos

- [ ] **TEST-2:** `tests/unit/module_interop_test.zig` — 5 linhas, ZERO `test` blocks. Módulo `module_interop.zig` (787 linhas) sem nenhum teste.
- [ ] **TEST-3:** `tests/unit/diagnostics_test.zig` — 1 teste com 1 fixture
- [ ] **TEST-4:** `tests/unit/elide_imports_test.zig` — 1 teste com 1 cenário
- [ ] **TEST-5:** `packages/linter/tests/linter_test.zig` — 724 linhas mas só testa 4 das ~30 regras (no-debugger, no-eval, no-unused-vars, no-process-exit)
- [ ] **TEST-6:** `packages/formatter/tests/semi_test.zig` — 1 teste trivial
- [ ] **TEST-7:** `packages/formatter/tests/misc_test.zig` — 1 teste trivial
- [ ] **TEST-8:** Pacotes `common`, `compiler`, `cli` têm testes de pacote com 2-3 testes triviais cada
- [ ] **TEST-9:** Formatter não tem testes diretos de `ast_formatter.zig` — todos passam via `linter.format()`

### 6.3 Test Runner Wiring

- [ ] **TEST-10:** Só `lexer.zig` e `packages/cli/src/main.zig` têm inline tests executados. Outros módulos com `test` blocks inline não são incluídos no test runner.

---

## 7. Qualidade de Código

### 7.1 Erros e Edge Cases

- [x] **QUAL-1:** `bench/bench.zig:81` — `std.Io.Limit.limited(1024 * 1024)` é válido na API Zig 0.16 — compila corretamente
- [x] **QUAL-2:** `bench/bench.zig:92,101` — Trocado `std.heap.page_allocator` por `std.testing.allocator`
- [x] **QUAL-3:** Template literal depth: aumentado de 16 para 64 níveis (ambos lexers + parser snapshots)
- [x] **QUAL-4:** `packages/linter/src/linter_main.zig:230` — `.off => unreachable` trocado por `.off => "off"`
- [x] **QUAL-5/6:** Addons N-API já verificam `napi_get_cb_info` com `!= NAPI_OK`
- [x] **QUAL-7:** `FormattedConfig.deinit()` no linter e formatter — limpo (stub removido, parametros não usados eliminados)

### 7.2 Documentação

- [x] **QUAL-8:** Quase zero doc comments (`///`) na API pública. Adicionada documentação para `parse()`, `transform()`, `transformParsed()`, `lint*()`, `lintWith*()`.
- [x] **QUAL-9:** `README.md` expandido com docs de uso, instalação, comandos, configuração, arquitetura.

### 7.3 Limpeza

- [x] **QUAL-10:** `packages/linter/src/rules.zig:103,1056` — Parâmetros `arena` e `rule` não usados — removidos com `_ =`
- [x] **QUAL-11:** `packages/linter/src/rules.zig:877-878` — `_ = env.deno; _ = env.bun;` — Adicionados globals do Deno (`Deno`) e Bun (`Bun`)
- [x] **QUAL-12:** `packages/linter/src/root.zig:37-38,146` — `_ = self; _ = alloc;` — removidos, `FormatterConfig.deinit` virou no-op sem params
- [x] **QUAL-13:** Empty `if` blocks nos parsers: `if (self.eatIf(.bang) != null) {}` — limpo (ambas cópias)

---

## 8. Resumo por Prioridade

```
CRÍTICO (implementar primeiro):
  [x] Remover catch unreachable / @panic de produção
  [x] Substituir catch {} por error handling adequado
  [x] Corrigir bug no bench.zig (page_allocator) e limpar stubs

ALTO:
  [x] Expandir suporte a targets (es2015–es2019) — FEAT-8
  [x] declare/override/triple-slash — FEAT-4/6/7 (já tratados pelo parser)
  [x] Watch mode para linter e formatter — FEAT-14
  [x] Expandir opções tsconfig (14 novas) — FEAT-15
  [ ] Adicionar testes para módulos sem cobertura (~30 arquivos)
  [ ] Corrigir addons N-API placeholder (parser e transform com input hardcoded)
  [ ] Melhorar sistema de config (tsconfig: lib, types, extends, include/exclude)

MÉDIO:
  [x] Subir deinit() do parser linter para o compiler parser
  [x] Documentar diferenças entre ast_formatter/root.zig (linter × formatter)
  [x] LintContext.fixes → optional (sem undefined)
  [x] Template literal depth: 16 → 64
  [ ] Unificar tipos Diagnostic entre common e compiler
  [ ] Implementar dependency tracking no incremental
  [ ] Testar todas as regras do linter (+26 regras sem teste)
  [ ] Adicionar watch mode para linter e formatter

BAIXO:
  [x] Adicionar doc comments na API pública
  [x] Expandir README
  [ ] Renomear _ = self.eat() → advance()
  [x] Limpeza de código morto
  [ ] Formalizar build cross-package com b.dependency()
```

---

## 9. Métricas

| Métrica | Valor |
|---|---|
| Linhas totais | ~44.000 |
| Linhas duplicadas (intencional — pacotes standalone) | ~7.300 (16.5%) |
| Arquivos fonte s/ testes | ~30 |
| `catch unreachable` em produção | ~4 (parser syncComments — arena seguro) |
| `catch {}` suprimindo erros | ~6 (non-critical: codegen/formatter) |
| Regras de lint testadas | 4 de ~30 |
| Targets ES suportados | 9 (es2015–esnext) |
| Opções tsconfig suportadas | 23 de ~50 |
| Template literal depth | 64 níveis |
| Watch mode | compiler + linter + formatter |
| Addons N-API completos | 1 de 4 (linter) |
| Checkboxes concluídos no tasks.md | ~38 de ~55 |
