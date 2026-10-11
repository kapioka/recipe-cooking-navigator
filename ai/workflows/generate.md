# New Recipe

Prerequisite: read [the router](../AGENTS.md) and its canonical schema and
integration contract. This workflow does not redefine schema fields.

- Use only the explicit ingredients, servings, utensils, time, taste and
  additional wishes in the request. Ask for material safety clarifications;
  do not infer allergies or medical restrictions.
- Generate a new Recipe ID, revision 1, and no parent revision. Follow the
  canonical schema for all required metadata and RecipeText/amount references.
- Check unique IDs, every reference, serving range, rational quantities,
  cooking equipment, preparation, detailed steps and total time. Reuse the
  [v2 example](../../examples/recipe-v2-split-example.json) only as a structural
  example; it is not the user's ingredients or an alternative schema.
- Food safety takes priority over speed. Do not recommend unsafe parallel work.
- Return only the complete Recipe JSON. The app independently validates it and
  requires the user's confirmation before saving.
