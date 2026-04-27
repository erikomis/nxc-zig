interface BoxLike<T> {}

interface BoxCtor<T> {}

export function identity<T>(value: T): T {
  return value;
}

export class Box<T> {
  constructor(public value: T) {}
}

export function createBox<T>(Ctor: BoxCtor<T>, value: T) {
  return new Ctor(identity(value));
}