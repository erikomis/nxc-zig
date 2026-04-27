// Combines all major TypeScript features in one file
// Enums
export enum Direction {
  Up = "UP",
  Down = "DOWN"
}

// Namespace
export namespace Utils {
  export function noop(): void {}
}

// Interfaces with optional and index signature
export interface Store<T> {}

// Type aliases with conditionals and indexed access
export type Nullable<T> = T | null;
export type Unwrap<T> = T;
export type NoInfer<T> = [T];

// Generic class with constructor param properties
export class BaseService<T> {
  constructor(name, items = []) {}
  getAll() {
    return this.items;
  }
}


// Decorator
function singleton(target: any) {
  return target;
}

export class AppService extends BaseService {
  constructor() {
    super("app");
  }
  async run(cb) {
    await cb();
  }
}


// Constructor type
interface ServiceCtor<T> {}

export function createService<T>(Ctor: ServiceCtor<T>, name: string): T {
  return new Ctor(name);
}

// Type assertions
const raw: unknown = {};
export const typed = (raw as Store<string>);

// Non-null assertion
export function ensure<T>(val: T | null): T {
  return val!;
}

// Optional chaining + nullish coalescing
export function safeGet(store: Store<string>): string {
  return store?.data ?? "fallback";
}

// Object spread + conditional spread
export function patch<T extends object>(base: T, patchValue: Partial<T>): T {
  return { ...base, ...(patchValue ? patchValue : {}) };
}

// Arrow functions
export const double = (n: number) => n * 2;
export const triple = (n) => n * 3;

// Array methods with typed arrows
const records: Store<number>[] = [];
export const ids = records.map((r) => r.id);
export const hasData = records.filter((r) => r.data != null).map(({ id }) => id);

// Regex
export const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const digits = /\d+/g;