# is_flight_rules

A trajectory's flight rules: what may leave this machine, to where, and as
which sign-in. They never say whether an action reads or writes. Files and
programs on the machine carry nothing off it by themselves, so only the ways
words can leave are named.

```dart
final rules = WhatMayLeaveThisMachine(
  modelSignInsTheLoopIsGiven: [ModelSignInName.parse('claude-team')!],
  sitesTheWebDriverMayReach: [
    SiteAndSignIn(Origin.parse('https://graph.microsoft.com')!,
        GoesAsSignIn(SignIn.parse('teams-bot')!)),
    SiteAndSignIn(Origin.parse('https://docs.example.com')!,
        const GoesAsNobody()),
  ],
  programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
);

rules.allowsWebRequest(docsOrigin, null);      // true: granted as nobody
rules.allowsWebRequest(docsOrigin, teamsBot);  // false: not as that sign-in
```

- `modelSignInsTheLoopIsGiven`: the model sign-ins the agent loop is built
  with, by name. The credential behind each name never appears here.
- `sitesTheWebDriverMayReach`: each grant is a site *and* who the request goes
  as, a sign-in or nobody. A site is never granted alone.
- `programsNetwork`: whether the trajectory's programs have a network of their
  own. With `sharesThisMachinesNetwork` the site list limits only the web
  driver.

`fromJson` is strict: an unknown key at any level, or a part that is not what
it names, is a `FormatException` naming the part.
