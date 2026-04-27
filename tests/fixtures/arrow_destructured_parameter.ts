type Request = object;

type Response = object;

type Context = object;

const routeHandler = ({ req, res }: Context) => {
  return res.status(200).json({
    body: req.body,
    params: req.params,
  });
};

const handler1 = ({ req, res }: Context) => {
  return res.json(req.body);
};

const handler2 = ({ req, res }: object) => {
  return res.status(201).json(req.params);
};

const handler3 = ({ req }: object) => {
  return req.body;
};

const handler4 = ({ req, res } = defaultContext: Context) => {
  return res.json(req.query);
};

const handler5 = ({ req, res }: Context) => {
  return res.status(204).json(null);
};