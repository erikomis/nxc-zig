export function buildQuery(isAdmin: boolean, store: object) {
  return {
    ...(isAdmin ? {} : { store: { id: store.id } }),
  };
}