type LengthAwareIterable<T = any> = Iterable<T> & object;
type LengthAwareAsyncIterable<T = any> = AsyncIterable<T> & object;

const isLengthAwareAsyncIterable = (value: unknown) => {
  return !!value && typeof value === "object" && "length" in value;
};

const isLengthAwareIterable = (value: unknown) => {
  return !!value && typeof value === "object" && "length" in value;
};

export const LengthAwareAsyncIterable = () => isLengthAwareAsyncIterable<T>;
export const LengthAwareIterable = () => isLengthAwareIterable<T>;