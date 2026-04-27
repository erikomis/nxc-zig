type Request = object;

type Response = object;

type Context = object;

const routeHandler = async ({ req, res }: Context) => {
  return res.status(200).json({
    body: req.body,
    params: req.params,
  });
};

const handler1 = async ({ req, res }: Context) => {
  return res.json(req.body);
};

const handler2 = async ({ req, res }: object) => {
  return res.status(201).json(req.params);
};

const handler3 = async ({ req }: object) => {
  return req.body;
};

const handler4 = async ({ req, res } = defaultContext: Context) => {
  return res.json(req.query);
};

const handler5 = async ({ req, res }: Context) => {
  return res.status(204).json(null);
};