export class Repository<T> {
  constructor(private Entity: T) {}
  create() {
    return new this.Entity();
  }
}

export class ProtectedRepository<T> {
  constructor(protected Entity: T) {}
  create() {
    return new this.Entity();
  }
}

export class ReadonlyRepository<T> {
  constructor(readonly Entity: T) {}
  create() {
    return new this.Entity();
  }
}
