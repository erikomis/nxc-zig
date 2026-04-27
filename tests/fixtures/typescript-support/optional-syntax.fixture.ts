// optional chaining
export function getNestedValue(obj: object): number {
  return obj?.a?.b ?? 0;
}

// optional computed member
export function getFirst(arr: string[]): string {
  return arr?.[0] ?? "";
}

// optional call
export function maybeCall(fn: any): void {
  fn?.();
}

// nullish coalescing
export function withDefault(value: string | null | undefined): string {
  return value ?? "default";
}

// optional parameter
export function greet(name: string): string {
  return `Hello ${name ?? "world"}`;
}

// optional property in interface
interface Options {}

export function run(opts = {}: Options): void {
  const t = opts.timeout ?? 5000;
  const r = opts.retries ?? 3;
  console.log(t, r);
}

// destructuring with defaults
export function readValues({ a = 0, b = 0 } = {}: object): number {
  return a + b;
}