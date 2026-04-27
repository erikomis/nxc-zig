type FindOperatorType = any | any;

type ObjectLiteral = Record<string, unknown>;

const map: Partial<Record<FindOperatorType, any>> = {
  equal: () => ["="],
  like: () => ["LIKE", { value: "%abc%" }],
};