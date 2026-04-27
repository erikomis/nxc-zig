declare module "some-lib" {
  export function helper(): void;
}

declare namespace Utils {
  export function format(s: string): string;
}

declare var legacyGlobal: number;
declare let ambientLet: string;

declare function ambientFn(x: number): void;

declare class AmbientClass {
  method(): void;
}

declare function hybrid(value: string): string;
declare namespace hybrid {
  let version: string;
}

declare global {
  interface Array<T> {
    first(): T | undefined;
  }
}

export declare const exportedAmbientValue: number;
export declare let exportedAmbientLet: string;
