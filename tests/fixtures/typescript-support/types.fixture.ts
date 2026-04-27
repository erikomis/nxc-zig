// export type
export type UserId = string;
export type Maybe<T> = T | null;

// interface
export interface User {}

// keyof
type UserKey = User;

// typeof in type position
type ConfigType = any;

// Partial, Record, Exclude
type PartialUser = Partial<User>;
type Dict = Record<string, number>;
type ExcludeNull<T> = Exclude<T, null>;

// conditional types
type IsString<T> = T;
export type NoInfer<T> = [T];

// indexed access
type NameType = User;
type First<T extends any[]> = T;

// optional property in type
interface Config {}

export function useConfig(cfg: Config): boolean {
  return cfg.debug ?? false;
}