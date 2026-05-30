# nxc

> ESM-first TypeScript compiler written in Zig. ~44.000 lines.

Fast TypeScript-to-JavaScript transpilation with source maps, JSX, decorators, CommonJS interop, `.d.ts` generation, incremental compilation, watch mode, N-API addons, and a built-in linter (30+ rules) + Prettier-compatible formatter (25+ options).

---

## Features

### Compiler

| Feature | Status |
|---------|--------|
| TypeScript/TSX → JavaScript (ESM output) | Done |
| CommonJS output (`--module commonjs`) | Done |
| JSX transform (classic + automatic runtime) | Done |
| Legacy decorators transform + metadata | Done |
| Stage-3 decorators pass-through | Done |
| ESM interop (`__importDefault`, `__importStar`, `__exportStar`) | Done |
| Source maps (VLQ-encoded) | Done |
| `.d.ts` declaration generation | Done |
| Incremental compilation with on-disk cache | Done |
| Minification (`--minify`) | Done |
| Const enum inlining | Done |
| ES targets: es2015 → esnext (9 targets) | Done |
| tsconfig.json (extends, include/exclude, paths, references) | Done |
| `nxc.config.js` support | Done |
| Watch mode (poll-based) | Done |

### Linter

| Feature | Status |
|---------|--------|
| 30+ built-in AST-based rules | Done |
| Auto-fix for applicable rules | Done |
| Plugin system (custom rules) | Done |
| Environment-aware (node, deno, bun) | Done |
| Persistent JSON cache | Done |
| Rule severity overrides (off/warn/error) | Done |
| Formatter rules (quotes, semi, trailing-comma, etc.) | Done |
| Watch mode | Done |

### Formatter

| Feature | Status |
|---------|--------|
| Prettier-compatible output | Done |
| 25+ configuration options | Done |
| Idempotent formatting | Done |
| JSX/TSX support | Done |
| Plugin system | Done |
| Range formatting (rangeStart/rangeEnd) | Done |
| Pragma support (@format / @noformat) | Done |
| Embedded language formatting | Done |

### N-API Addons

| Addon | Exports | `.node` output |
|-------|---------|----------------|
| `linter/src/addon.zig` | `lint(source, config)` | `lint.node` |
| `formatter/src/addon.zig` | `format(source, options)` | `formatter.node` |
| `compiler/addons/parser.zig` | `parse(source)` | `parser.node` |
| `compiler/addons/transform.zig` | `transform(source)` | `transform.node` |

All addons use arena allocators and return structured JS objects with diagnostics, code, and source maps.

---

## Quick Start

### Docker (no local Zig needed)

```bash
docker build -t nxc-zig .
./docker-zig.sh build          # build all binaries + addons
./docker-zig.sh build test     # build + run all tests
```

### Local (Zig 0.16.0+)

```bash
zig build               # compiler, linter, formatter + .node addons
zig build test          # run all 121+ test scenarios
zig build run -- src/   # compile a directory
```

---

## CLI Reference

### `nxc-compiler` — TypeScript → JavaScript

```bash
# Single file → stdout
nxc-compiler src/file.ts

# Directory → dist/
nxc-compiler --out-dir dist src/

# With tsconfig
nxc-compiler --config tsconfig.json

# JSX automatic runtime
nxc-compiler --jsx auto --jsx-import-source react src/app.tsx

# CommonJS output
nxc-compiler --module commonjs src/

# Minification
nxc-compiler --minify src/

# Generate .d.ts
nxc-compiler --declaration src/

# Watch mode
nxc-compiler --watch src/

# Source maps
nxc-compiler --source-map src/
```

### `nxc-linter` — Code quality

```bash
nxc-linter src/                    # lint directory
nxc-linter --fix src/              # auto-fix where possible
nxc-linter --config nxc.config.js  # with config
nxc-linter --cache --verbose       # persistent cache
nxc-linter --watch src/            # watch mode
nxc-linter --json                  # JSON output
```

### `nxc-formatter` — Code formatting

```bash
nxc-formatter src/file.ts              # stdout
nxc-formatter --write src/file.ts      # in-place
nxc-formatter --check src/             # check only (exit 1 if changes needed)
nxc-formatter --config nxc.config.js   # with config
nxc-formatter --watch src/             # watch mode
```

### `nxc` — Unified CLI

```bash
nxc compile src/ --out-dir dist/
nxc lint src/ --fix
nxc format src/ --write
```

---

## Configuration

### tsconfig.json

nxc resolves `tsconfig.json` automatically (searches parent directories) and supports:

```jsonc
{
  "compilerOptions": {
    "target": "ES2022",          // es2015, es2016, es2017, es2018, es2019, es2020, es2022, es2024, esnext
    "module": "esnext",          // esnext, commonjs
    "jsx": "react-jsx",          // preserve, react, react-jsx, react-jsxdev
    "jsxImportSource": "react",
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "declarationDir": "./dist/types",
    "sourceMap": true,
    "inlineSourceMap": false,
    "inlineSources": false,
    "removeComments": true,
    "allowJs": false,
    "checkJs": false,
    "noEmit": false,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "esModuleInterop": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "paths": {
      "@/*": ["./src/*"],
      "~/*": ["./lib/*"]
    },
    "baseUrl": ".",
    "minify": false
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"],
  "files": ["src/types.d.ts"],
  "extends": "./tsconfig.base.json",
  "references": [
    { "path": "./packages/core" }
  ]
}
```

**23 of ~50 tsconfig options supported.**

### nxc.config.js

For linter and formatter configuration:

```js
export default defineConfig({
  env: {
    node: true,
    deno: false,
    bun: false,
  },
  formatter: {
    singleQuote: true,
    semi: false,
    trailingComma: 'all',
    bracketSpacing: true,
    tabWidth: 2,
    printWidth: 80,
    useTabs: false,
    quoteProps: 'as_needed',
    arrowParens: 'always',
    bracketSameLine: false,
    endOfLine: 'lf',
    jsxSingleQuote: false,
    singleAttributePerLine: false,
    operatorPosition: 'end',
    ternaryStyle: 'classic',
    proseWrap: 'preserve',
    objectWrap: 'preserve',
  },
  rules: {
    'no-console': 'warn',
    'no-debugger': 'error',
    'no-unused-vars': 'error',
    'no-var': 'error',
    'prefer-template': 'warn',
    'formatter/quotes': ['error', 'single'],
    'formatter/semi': ['error', true],
  },
})
```

### Formatter Options Reference

| Option | Type | Default | Values |
|--------|------|---------|--------|
| `semi` | bool | `true` | `true`, `false` |
| `singleQuote` | bool | `false` | `true`, `false` |
| `jsxSingleQuote` | bool | `false` | `true`, `false` |
| `trailingComma` | string | `"all"` | `"none"`, `"es5"`, `"all"` |
| `bracketSpacing` | bool | `true` | `true`, `false` |
| `bracketSameLine` | bool | `false` | `true`, `false` |
| `tabWidth` | number | `2` | Any positive integer |
| `useTabs` | bool | `false` | `true`, `false` |
| `printWidth` | number | `80` | Any positive integer |
| `arrowParens` | string | `"always"` | `"always"`, `"avoid"` |
| `endOfLine` | string | `"lf"` | `"lf"`, `"crlf"`, `"cr"`, `"auto"` |
| `quoteProps` | string | `"as_needed"` | `"as_needed"`, `"consistent"`, `"preserve"` |
| `proseWrap` | string | `"preserve"` | `"always"`, `"never"`, `"preserve"` |
| `objectWrap` | string | `"preserve"` | `"preserve"`, `"collapse"` |
| `operatorPosition` | string | `"end"` | `"end"`, `"start"` |
| `ternaryStyle` | string | `"classic"` | `"classic"`, `"linear"` |
| `singleAttributePerLine` | bool | `false` | `true`, `false` |
| `requirePragma` | bool | `false` | `true`, `false` |
| `insertPragma` | bool | `false` | `true`, `false` |
| `checkIgnorePragma` | bool | `false` | `true`, `false` |
| `embeddedLanguageFormatting` | string | `"auto"` | `"auto"`, `"off"` |
| `rangeStart` | number | `0` | Byte offset |
| `rangeEnd` | number | `∞` | Byte offset |

---

## Architecture

```
packages/
├── common/          Shared types (Diagnostic, Severity, FormatterOptions, Plugin)
├── compiler/        23 modules: lexer → parser → AST → pipeline → codegen
│   ├── syntax/      lexer, token, parser, AST, diagnostics
│   ├── transform/   JSX, decorators, modules, JSON5, class_names, strip_types
│   ├── codegen/     JavaScript codegen, source maps, .d.ts declarations
│   ├── resolver/    path resolution, aliases
│   ├── core/        compiler entry, config, cache, incremental
│   └── addons/      N-API: parser.addon, transform.addon
├── linter/          Standalone linter (own lexer, parser, AST)
│   ├── 30+ AST-based rules + auto-fix
│   └── N-API: addon.zig
├── formatter/       Prettier-compatible formatter (shares linter's AST formatter)
│   └── N-API: addon.zig
└── cli/             CLI entry points + watch mode + legacy CLI
    ├── main.zig         nxc (unified)
    ├── compiler_main    nxc-compiler
    ├── linter_main      nxc-linter
    ├── formatter_main   nxc-formatter
    ├── watch.zig        file watching (poll)
    └── cache.zig        lint cache (JSON)
```

**Design note:** Each package (compiler, linter, formatter) is intentionally standalone — they duplicate the lexer, parser, and AST (~7.300 lines, 16.5%) so they work independently. The CLI is the only integrator.

---

## Performance Optimizations

| Optimization | Impact | Description |
|---|---|---|
| Single-pass fix application | High | Fixes applied in O(n) instead of O(n×m) |
| Codegen buffer pre-sizing | Medium | Initial capacity = source length |
| Dependency extraction via text scan | High | No full re-parse for incremental deps |
| Single-pass rule visitor | High | 30 rule traversals → 1 AST pass |
| Cache stale check direct iteration | Low | No string re-splitting per check |
| Progressive NodePool slabs | Low | 256 → 4096 instead of fixed 4096 |
| Config allocator unification | Low | Uses caller's allocator, not page_allocator |
| Merge scope early-return | Low | Skip hashmap allocation when no merge decls |

---

## Testing

- **Linter:** 75 test scenarios covering all 30+ rules (positive, negative, auto-fix, config, env, plugins, API)
- **Formatter:** 72 test scenarios covering all 25+ options (positive, negative, idempotency, edge cases, robustness)
- **Compiler:** Integration + unit tests for parser, codegen, JSX, decorators, compiler pipeline
- **Total:** 121+ linter/formatter tests, unit tests for all compiler modules

Run all tests:

```bash
zig build test
```

---

## API

### Linter

```zig
const linter = @import("linter");

// Quick lint with built-in rules
const result = try linter.lintWithDefaultRules(source, filename, alloc);
defer result.deinit(alloc);

// Lint with custom config
const cfg = try linter.parseConfig(config_source, alloc);
const result = try linter.lintWithConfig(source, filename, cfg, alloc);
defer result.deinit(alloc);
defer cfg.deinit(alloc);

// Lint with plugins
const result = try linter.lintWithPlugins(source, filename, &plugins, alloc);
defer result.deinit(alloc);
```

### Compiler

```zig
const compiler = @import("compiler");

// Parse TypeScript source
const parse_result = try compiler.parse(source, filename, alloc);
defer parse_result.deinit(alloc);

// Transform TypeScript → JavaScript
const transform_result = try compiler.transform(source, filename, io, alloc);
defer transform_result.deinit(alloc);

// Full compile with config
const cfg = compiler.Config{};
const result = try compiler.compile(source, filename, cfg, io, alloc);
defer result.deinit(alloc);
```

### Formatter

```zig
const linter = @import("linter");

// Format source
const formatted = try linter.format(source, .{ .singleQuote = true }, alloc);
defer alloc.free(formatted);

// Check formatting
const diags = try linter.checkFormat(source, .{ .semi = false }, alloc);
defer linter.freeCheckDiagnostics(alloc, diags);
```

---

## Requirements

- **Zig** 0.16.0+
- **Node.js** (optional, for `nxc.config.js` evaluation)

---

## License

MIT
