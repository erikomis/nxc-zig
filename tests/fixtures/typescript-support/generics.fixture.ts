// generic function
export function identity<T>(value: T): T {
  return value;
}

// generic function with constraint
export function getKey<T extends object, K extends T>(obj: T, key: K): T {
  return obj[key];
}

// generic async function with callback type
export async function transactional<T>(cb: any): Promise<T> {
  return cb();
}

// generic class
export class Repository<T> {
  constructor(items = []) {}
  add(item) {
    this.items.push(item);
  }
  getAll() {
    return this.items;
  }
}



// generic class with constructor type
interface Ctor<T> {}

export function create<T>(C: Ctor<T>): T {
  return new C();
}

// NoInfer utility type usage
export type NoInfer<T> = [T];

export function setDefault<T>(value: T, fallback: NoInfer<T>): T {
  return value ?? fallback;
}