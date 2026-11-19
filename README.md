# is_flight_rules

A trajectory's flight rules: what may leave this machine, to where, and as
which sign-in, and the model its loop starts on.

```dart
final flightRules = FlightRules.of(
  whatMayLeaveThisMachine: rules,
  startingModel: ModelAndSignIn(
    signIn: ModelSignInName.parse('claude-team')!,
    model: ModelName.parse('claude-opus-5-5')!,
  ),
); // null unless the rules let a model call go out as claude-team
```

`startingModel`'s sign-in is always one the rules let a model call go out as,
so a trajectory is never started on a model whose first call is refused.
`FlightRules.fromJson` reads `{"whatMayLeaveThisMachine": …,
"startingModel": {"signIn": …, "model": …}}`; both keys are required.

## What may leave this machine

The rules never say whether an action reads or writes. Files and programs on
the machine carry nothing off it by themselves, so only the ways words can
leave are named.

```dart
final rules = WhatMayLeaveThisMachine(
  modelSignInsCallsMayGoOutAs: [ModelSignInName.parse('claude-team')!],
  sitesTheWebDriverMayReach: [
    SiteAndSignIn(Origin.parse('https://graph.microsoft.com')!,
        GoesAsBotLeasedFrom(BotPool.parse('teams-agents')!)),
    SiteAndSignIn(Origin.parse('https://docs.example.com')!,
        const GoesAsNobody()),
  ],
  programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
);

final pooled = {researcher1, reviewer2};
rules.grantFor(docsOrigin, null, leasedNow: {}, pooled: pooled);
    // granted as nobody
rules.grantFor(docsOrigin, researcher1, leasedNow: {}, pooled: pooled);
    // null: not as a bot
rules.grantFor(teamsOrigin, researcher1,
    leasedNow: {teamsAgents: researcher1}, pooled: pooled);
    // the leased grant
rules.grantFor(teamsOrigin, researcher1, leasedNow: {}, pooled: pooled);
    // null: lease ended
```

`grantFor` returns the grant that allowed the request, not just yes or no,
so the airlock can record which lease a decision relied on: one from a
`GoesAsBotLeasedFrom` grant relied on that pool's lease, any other on none.
A sign-in in `pooled` is never granted by name, so no rules, old or new,
can let a trajectory post as a bot leased to another.

- `modelSignInsCallsMayGoOutAs`: the model sign-ins a model call for this
  trajectory may go out as, by name. The airlock makes the call; the loop
  holds no credential, and the credential behind each name never appears
  here.
- `sitesTheWebDriverMayReach`: each grant is a site *and* who the request goes
  as: a sign-in, the bot this trajectory leases from a pool, or nobody. A
  site is never granted alone. Rules are copied when a mission is admitted,
  before any bot is leased, so a grant names the pool, and matches only
  while the trajectory holds a lease from it.
- `programsNetwork`: whether the trajectory's programs have a network of their
  own. With `sharesThisMachinesNetwork` the site list limits only the web
  driver.

`fromJson` is strict: an unknown key at any level, or a part that is not what
it names, is a `FormatException` naming the part.
