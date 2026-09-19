# Cost is notional at API rates

The plugin shows cost figures on Sources whose subscriptions are not billed per
token, so every figure is what the tokens would have cost at the provider's
published API rates, not what was paid. Rates come from LiteLLM's table,
refreshed daily into one shared cache, with cached input and cache write priced
at their own rates; a model the table does not name contributes zero to cost
while its tokens still count. Every cost-bearing tab says so in its copy
("at API rates, not what you pay"), because a dollar figure on a subscription
reads as an amount owed.

opencode Go reports no cost, and that is deliberate. Its endpoint offers only
Window percentages, and the obvious alternative - reading the token and cost
figures in its local database - was rejected twice over: opencode's own cost
field prices at models.dev rates, which would mix two rate sources inside one
widget, and reading the database would make `sqlite3` a Requirement of every
Script for one Source's benefit (ADR 0005). It stays a percentages-only Source.
Revisit if its endpoint ever reports tokens.
