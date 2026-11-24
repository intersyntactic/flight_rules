# is_flight_rules

A trajectory's flight rules: what may leave this machine, to where, and as
which sign-in, the model its loop starts on, the programs it may run and needs,
and the tools it is given.

```dart
final flightRules = FlightRules.of(
  whatMayLeaveThisMachine: rules,
  startingModel: ModelAndSignIn(
    signIn: ModelSignInName.parse('claude-team')!,
    model: ModelName.parse('claude-opus-5-5')!,
  ),
  programsItMayRun: [git, pandoc],
  programsItNeeds: [git],
  givenTools: [readDocument],
); // null unless the rules let a model call go out as claude-team,
   // every program it needs is one it may run, and no two given tools
   // share a name
```

`startingModel`'s sign-in is always one the rules let a model call go out as,
so a trajectory is never started on a model whose first call is refused.
Every program in `programsItNeeds` is one in `programsItMayRun`, so a
trajectory never needs a program it could not run. A program it may run can
be missing from a machine; one it needs can't, and the check against the
machine's programs happens when the trajectory starts.

`givenTools` are is_tools_api `OneActionTool`s, written inline, so the
admission that starts a trajectory records exactly what it was given, bound
values and all. They are keyed by name in the order listed, and no two share
a name, since a model calls a tool by name. A tool adds no reach: the
airlock still decides each action one proposes against the rest of the
rules.

`FlightRules.fromJson` reads `{"whatMayLeaveThisMachine": …,
"startingModel": {"signIn": …, "model": …}, "programsItMayRun": […],
"programsItNeeds": […], "givenTools": […]}`; every key is required, and a
tool `OneActionTool.parse` refuses makes the rules unreadable.

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
      FromAddressesUnder(AddressPrefix.of(Origin.parse('https://docs.example.com')!,
          PathPrefix.parse('/guides/')!)),
      const GoesAsNobody(),
    ),
    // One folder of a Microsoft Graph drive: its listing, and a file in it
    // by name.
    GrantToFetch(
      FromPathsMatching.of(Origin.parse('https://graph.microsoft.com')!, [
        PathPattern.parse('/v1.0/drives/b!abc/items/01F/children',
            optionsTakingWordLists: [QueryOptionName.parse(r'$select')!])!,
        PathPattern.parse('/v1.0/drives/b!abc/items/01F:/{name}:/content')!,
      ])!,
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

rules.fetchGrantFor(graph,
    WebPath.parse('/v1.0/drives/b!abc/items/01F:/Report.docx:/content')!,
    researcher1, leasedNow: {teamsAgents: researcher1}, pooled: pooled);
    // the folder grant
rules.fetchGrantFor(graph, WebPath.parse('/v1.0/drives/b!abc/items/01X')!,
    researcher1, leasedNow: {teamsAgents: researcher1}, pooled: pooled);
    // null: a file by its id, which names no folder
rules.webRequestsGrantFor(teams, replyPath, researcher1,
    leasedNow: {teamsAgents: researcher1}, pooled: pooled,
    replyEndpoint: startEntry.replyEndpoint);
    // the reply grant, while replyPath is under that endpoint
```

Each grant method returns the grant that allowed the request, not just yes
or no, so the airlock can record which entries a decision relied on: one
from a `GoesAsBotLeasedFrom` grant relied on that pool's lease, any other
on none beyond the rules. It returns too the `grantedPathPrefix` the
request was granted under, which the airlock hands to is_effects'
`GrantedRequest.under` so the driver keeps a redirect on the same site under it; for a reply grant
it is the endpoint's prefix, never one the rules wrote. A sign-in in `pooled` is never granted by name, so no rules, old or
new, can let a trajectory post as a bot leased to another.

- `modelSignInsCallsMayGoOutAs`: the model sign-ins a model call for this
  trajectory may go out as, by name. The airlock makes the call; the loop
  holds no credential, and the credential behind each name never appears
  here.
- `fetchesMayReach` and `webRequestsMayReach`: kept apart, so a grant to
  make requests to a site never lets the trajectory read from it, and the
  reverse. Each grant is where *and* who the request goes as: a
  sign-in, the bot this trajectory leases from a pool, or nobody. An address
  is never granted alone, and a path reaches under a prefix only when it
  goes deeper than it, so `/v1.0/drives/abc/` reaches neither
  `/v1.0/drives/abc` nor `/v1.0/drives/abcdef/`. `/` is the whole site.
- `FromPathsMatching.of(origin, patterns)`: a fetch grant for a site where
  no prefix can bound a read. Microsoft Graph, for one, names a file in a
  folder as `{folder}:/{name}:`, a segment that isn't `{folder}`, and a
  file read by its own id doesn't name its folder at all. A `PathPattern`
  spells one route a read may take, and every other route is refused
  rather than checked. Each segment is a literal, compared decoded as a
  prefix compares it, or `{name}`: one segment naming one thing, never
  empty, never with a `/`, `\` or `:` once decoded, never only dots, and
  optionally followed by a fixed suffix, as in `{name}:`. There is no
  wildcard and no "any depth"; a literal can't hold a `*`, so no pattern
  reads as one. A pattern names at least two segments and starts with a
  literal. Its query may carry only the options it lists, each once and
  each with a comma-separated list of words, so `$select=name,size` can
  narrow a listing and `$expand=children` can't widen it. A read is
  granted under its own path less its last segment, so a redirect on the
  same site stays on that read.
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
