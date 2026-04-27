// Class with class decorator + constructor param decorators
@Singleton()
class ServiceA {
  constructor(@Dep('TOKEN_A') private tokenA: string, @Dep('TOKEN_B') private tokenB: string) {}
}

// Class WITHOUT class decorator, only constructor param decorators
class ServiceB {
  constructor(@Dep('TOKEN') private token: string) {}
}

// Export class with constructor param decorators
@Singleton()
export class ServiceC {
  constructor(@Dep('TOKEN') private dep: string) {}
}

// Export class without class decorator
export class ServiceD {
  constructor(@Dep('TOKEN') private dep: string) {}
}

// Multiple decorators on same param
class ServiceE {
  constructor(@DecA() @DecB() private value: string) {}
}

// Mix: class decorator + method decorator + constructor param decorator
@Service()
class ServiceF {
  @Log()
  method() {}
  constructor(@Dep('CTX') private dep: string) {}
}
