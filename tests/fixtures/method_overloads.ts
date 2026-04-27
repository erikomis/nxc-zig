// Class method overloads
class Resolver {
  resolve(): string;
  resolve(x: number): string;
  resolve(value?: string | number): string {
    return String(value);
  }

  static create(): Resolver;
  static create(id: number): Resolver;
  static create(id?: number): Resolver {
    return new Resolver();
  }

  get name(): string {
    return "resolver";
  }
}

// Constructor overloads
class Point {
  x: number = 0;
  y: number = 0;
  constructor(): void;
  constructor(x: number, y: number): void;
  constructor(xOrCoords?: number, y?: number) {
    // implementation
  }
}

// Interface (should be fully stripped)
interface Formatter {
  format(value: string): string;
}

// Standalone function overloads
function parse(value: string): string[];
function parse(value: number): number[];
function parse(value: string | number): (string | number)[] {
  return [value];
}

export async function load(id: string): Promise<string>;
export async function load(id: number): Promise<string>;
export async function load(id: string | number): Promise<string> {
  return String(id);
}
