# is_flight_rules

A trajectory's flight rules: what may leave this machine, to where, and as
which sign-in, the model its loop starts on, and the programs it may run and
needs.

```dart
final flightRules = FlightRules.of(
  whatMayLeaveThisMachine: rules,
  startingModel: ModelAndSignIn(
    signIn: ModelSignInName.parse('claude-team')!,
    model: ModelName.parse('claude-opus-5-5')!,
  ),
  programsItMayRun: [git, pandoc],
  programsItNeeds: [git],
); // null unless the rules let a model call go out as claude-team,
   // and every program it needs is one it may run
```

`startingModel`'s sign-in is always one the rules let a model call go out as,
so a trajectory is never started on a model whose first call is refused.
Every program in `programsItNeeds` is one in `programsItMayRun`, so a
trajectory never needs a program it could not run. A program it may run can
be missing from a machine; one it needs can't, and the check against the
machine's programs happens when the trajectory starts. `FlightRules.fromJson`
reads `{"whatMayLeaveThisMachine": …, "startingModel": {"signIn": …,
"model": …}, "programsItMayRun": […], "programsItNeeds": […]}`; every key is
required.

## What may leave this machine

The rules never say whether an action reads or writes. Files carry nothing
off the machine by themselves, and running a program doesn't either: which
programs may run is `FlightRules`', beside the rest. Here only the ways words
can leave are named.

```dart
final rules = WhatMayLeaveThisMachine(
  modelSignInsCallsMayGoOutAs: [ModelSignInName.parse('claude-team')!],
  fetchesMayReach: [
    GrantToFetch(
      AddressPrefix.of(Origin.parse('https://graph.microsoft.com')!,
          PathPrefix.parse('/v1.0/drives/abc/')!),
      GoesAsBotLeasedFrom(BotPool.parse('teams-agents')!),
    ),
  ],
  webRequestsMayReach: [
    GrantToMakeWebRequests(
      ToOwnReplyEndpoint.of([Origin.parse('https://smba.trafficmanager.net')!])!,
      GoesAsBotLeasedFrom(BotPool.parse('teams-agents')!),
    ),
  ],
  programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
);

rules.fetchGrantFor(graph, WebPath.parse('/v1.0/drives/abc/items')!,
    researcher1, leasedNow: {teamsAgents: researcher1}, pooled: pooled);
    // the fetch grant
rules.fetchGrantFor(graph, WebPath.parse('/v1.0/drives/xyz/items')!,
    researcher1, leasedNow: {teamsAgents: researcher1}, pooled: pooled);
    // null: another drive
rules.webRequestsGrantFor(teams, replyPath, researcher1,
    leasedNow: {teamsAgents: researcher1}, pooled: pooled,
    replyEndpoint: startEntry.replyEndpoint);
    // the reply grant, while replyPath is under that endpoint
```

Each grant method returns the grant that allowed the request, not just yes
or no, so the airlock can record which entries a decision relied on: one
from a `GoesAsBotLeasedFrom` grant relied on that pool's lease, any other
on none beyond the rules. It returns too the `grantedPathPrefix` the
request was granted under, which the airlock puts on is_effects' `Request`
so the driver keeps a redirect on the same site under it; for a reply grant
it is the endpoint's prefix, never one the rules wrote. A sign-in in `pooled` is never granted by name, so no rules, old or
new, can let a trajectory post as a bot leased to another.

- `modelSignInsCallsMayGoOutAs`: the model sign-ins a model call for this
  trajectory may go out as, by name. The airlock makes the call; the loop
  holds no credential, and the credential behind each name never appears
  here.
- `fetchesMayReach` and `webRequestsMayReach`: kept apart, so a grant to
  make requests to a site never lets the trajectory read from it, and the
  reverse. Each grant is an address prefix *and* who the request goes as: a
  sign-in, the bot this trajectory leases from a pool, or nobody. An address
  is never granted alone, and a path reaches under a prefix only when it
  goes deeper than it, so `/v1.0/drives/abc/` reaches neither
  `/v1.0/drives/abc` nor `/v1.0/drives/abcdef/`. `/` is the whole site.
- `ToOwnReplyEndpoint`: rules are copied into every trajectory a mission
  starts, while each trajectory's conversation is its own, so a grant to
  reply names the role, and the airlock passes in the endpoint from the
  trajectory's start entry. The endpoint comes from an inbound event, so
  the grant names the origins it may be on, and never none.
- `programsNetwork`: whether the trajectory's programs have a network of
  their own. With `sharesThisMachinesNetwork` the web grants limit only the
  web driver.

`fromJson` is strict: an unknown key at any level, or a part that is not what
it names, is a `FormatException` naming the part.
