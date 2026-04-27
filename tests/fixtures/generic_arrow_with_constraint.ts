type GetTemplateTuple<T> = T;
type Message = string;

// Generic arrow with extends constraint (must work in JSX mode too)
export const printMessage = (...args: ArgTypes) => {
  return args;
};

// Generic arrow with extends and default
export const wrap = (value: T) => {
  return ((value as unknown) as U);
};

// Generic arrow with trailing comma (JSX disambiguator)
export const identity = (value: T) => value;

// Nested generic constraint
export const pick = (obj: T, key: K) => {
  return obj[key];
};