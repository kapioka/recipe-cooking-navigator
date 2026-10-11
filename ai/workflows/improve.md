# Improve a selected Recipe

Prerequisite: read [the router](../AGENTS.md), Recipe / Feedback v2 schemas and
the integration contract. Require one complete, explicit Feedback document.

- Use `recipe_snapshot` as the improvement base. Its revision may differ from
  the cooked snapshot in `cook_session`; do not confuse these two roles.
- Keep the base Recipe ID. Set `parent_revision` to the improvement base's
  revision and use `revision_request.next_revision` for the new revision.
- Apply the explicit goal and notes, respecting `preserve_successful_parts`.
  Taste scores are deviations from this user's ideal (0), not ratings to
  maximize. One cooking session does not establish a permanent preference.
- Keep Cook Session and Evaluation data out of the new Recipe. Do not write a
  Profile, rewrite past revisions, or claim to change latest/active in the app.
- Validate all new Recipe references, quantities and safety constraints against
  the canonical schema and contract. Stop on invalid/unsupported Feedback.
- Return exactly one complete Recipe JSON for user preview and confirmation.
