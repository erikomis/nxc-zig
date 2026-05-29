# nxc

ESM-first TypeScript compiler written in Zig. Fast TypeScript-to-JavaScript transpilation with source maps, JSX support, decorators, and a built-in linter/formatter.

## Features

- **Compile** TypeScript/TSX to JavaScript (ESM output)
- **Lint** with 30+ built-in rules (no-console, no-eval, prefer-const, etc.)
- **Format** with Prettier-compatible options
- **JSX** transform (classic `React.createElement` and automatic `_jsx` runtime)
- **Decorators** legacy transform with metadata support
- **ESM interop** for CommonJS compatibility
- **Source maps** generation
- **`.d.ts`** declaration file generation
- **Incremental** compilation with cache
- **Watch mode** (poll-based)
- **N-API** native addons for Node.js

## Requirements

- Zig 0.16.0+
- Node.js (optional, for `nxc.config.js` support)

## Quick Start

### Docker (no local Zig needed)

```bash
docker build -t nxc-zig .
./docker-zig.sh build          # build all binaries
./docker-zig.sh build test     # run tests
```

### Local

```bash
zig build          # build compiler, linter, formatter + N-API addons
zig build test     # run all tests
```

## Usage

### Compile

```bash
# Compile a single file to stdout
nxc-compiler src/file.ts

# Compile a directory to dist/
nxc-compiler --out-dir dist src/

# Compile with JSX automatic runtime
nxc-compiler --jsx auto src/app.tsx

# Compile using tsconfig.json
nxc-compiler --config tsconfig.json src/

# Watch mode
nxc-compiler --watch src/
```

### Lint

```bash
nxc-linter src/file.ts
nxc-linter --fix src/
nxc-linter --config nxc.config.js src/
nxc-linter --cache --verbose src/
```

### Format

```bash
nxc-formatter src/file.ts              # output to stdout
nxc-formatter --write src/file.ts      # format in-place
nxc-formatter --out-file out.ts src/in.ts
```

### Unified CLI

```bash
nxc compile src/ --out-dir dist/
nxc lint src/file.ts --fix
nxc format src/file.ts --write
```

## Configuration

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "jsx": "react-jsx",
    "jsxImportSource": "react",
    "paths": { "@/*": ["./src/*"] },
    "declaration": true,
    "sourceMap": true,
    "esModuleInterop": true,
    "experimentalDecorators": true
  }
}
```

Supported targets: `es2015`, `es2016`, `es2017`, `es2018`, `es2019`, `es2020`, `es2022`, `es2024`, `esnext`

### nxc.config.js

```js
export default defineConfig({
  env: { node: true },
  formatter: {
    singleQuote: true,
    semi: false,
    trailingComma: 'all',
    tabWidth: 2,
    printWidth: 80,
  },
  rules: {
    'no-console': 'warn',
    'no-debugger': 'error',
    'no-unused-vars': 'error',
  },
})
```

## Architecture

The project is organized into independent packages:

| Package | Purpose |
|---------|---------|
| `packages/compiler` | TypeScript parser, transform pipeline, codegen |
| `packages/linter` | AST-based lint rules engine |
| `packages/formatter` | Prettier-compatible code formatter |
| `packages/cli` | CLI entry points (`nxc`, `nxc-compiler`, `nxc-linter`, `nxc-formatter`) |
| `packages/common` | Shared types (Diagnostic, Severity, FormatterOptions) |

Each package is self-contained (has its own lexer, parser, AST) to enable standalone use. The CLI is the only package that imports from all others.

## License

MIT
