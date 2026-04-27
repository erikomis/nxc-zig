function injectable(target: any) {
  return target;
}
function inject(token: string) {
  return (_: any, __: string, i: number) => {};
}

export class UserService {
  constructor(db) {}
  async find(id) {
    return this.db.find(id);
  }
}