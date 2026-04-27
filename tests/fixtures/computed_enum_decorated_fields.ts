enum BlankSideEnum {
  BACK = 0,
  FRONT = 1
}

function Expose() {
  return function() {};
}

function ApiValidateNested(_factory: any) {
  return function() {};
}

class AreaValue {}

export class Area {
  @Expose()
  @ApiValidateNested(() => AreaValue)
  [BlankSideEnum.FRONT]?: AreaValue;
  @Expose()
  @ApiValidateNested(() => AreaValue)
  [BlankSideEnum.BACK]?: AreaValue;
}