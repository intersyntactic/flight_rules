## 0.6.0

- **Breaking:** `FlightRules` gains a required `givenTools`: the tools a trajectory is given, as is_tools_api `OneActionTool`s written inline, keyed by name in the order the rules list them. `FlightRules.of` returns null, and `fromJson` throws, when two share a name; `fromJson` also throws for a tool `OneActionTool.parse` refuses. On the wire, `"givenTools": [<tool>…]`, each tool in the shape `OneActionTool.toJson` writes. So 0.5.0's rules are not read.
- `FlightRules.of` returns null, and `fromJson` throws, when a given tool's action is one no grant could let out: for a `Fetch`, when `couldEverFetch` is false.
- `WhatMayLeaveThisMachine.couldEverFetch(site, path, signIn)`: whether some fetch grant reaches `path` on `site` and could let it go as `signIn`, by name or as a pool's leased bot. A false answer means `fetchGrantFor` refuses that fetch whatever the leases.
- Depends on is_tools_api ^0.4.0 and is_effects ^0.14.3, so a tool's `SignIn` and a grant's are one type.

## 0.5.0

- **Breaking:** `GrantToFetch.from` is a `WhereFetchesReadFrom`: `FromAddressesUnder(prefix)`, what an `AddressPrefix` granted before, or `FromPathsMatching.of(origin, patterns)`, only the paths one of its `PathPattern`s matches on `origin`. A pattern such as `/drives/D/items/F:/{name}:/content` spells its segments: literals, compared decoded, and `{name}`, one segment that is not empty, has no `/`, `\` or `:` once decoded and is not only dots, with an optional fixed suffix. There is no wildcard and no "any depth". A pattern names at least two segments, starts with a literal, and its query may carry only the `QueryOptionName`s it lists, each once, each with a comma-separated list of words. A read is granted under its own path less its last segment. On the wire `from` carries a `kind`: `addressesUnder` with a `prefix`, or `pathsMatching` with an `origin` and `patterns`, each `{"path": …, "optionsTakingWordLists": […]}`. So 0.4.0's rules are not read.

## 0.4.0

- **Breaking:** `sitesTheWebDriverMayReach` is split in two, so a grant to make web requests never lets a fetch through, and the reverse. `fetchesMayReach` holds `GrantToFetch(from, goesAs)`, decided by `fetchGrantFor(site, path, signIn, leasedNow:, pooled:)`. `webRequestsMayReach` holds `GrantToMakeWebRequests(to, goesAs)`, decided by `webRequestsGrantFor(site, path, signIn, leasedNow:, pooled:, replyEndpoint:)`, once for each request a tool builds. Each returns `(grant:, grantedPathPrefix:)`, the prefix being the one the request was granted under, for is_effects' `GrantedRequest.under(proposed, grantedPathPrefix)`: for a reply grant it is the endpoint's. `SiteAndSignIn` and `grantFor` are removed, and 0.3.0's rules are not read.
- `signInForReply(replyEndpoint:, leasedNow:, pooled:)`: the sign-in a reply to the trajectory's endpoint can go as, chosen the way `webRequestsGrantFor` prefers (by name before by lease, never a pooled bot by name), so the loop sending a reply and the airlock checking it can't disagree. Null when no reply grant can go as anyone.
- Every grant reaches only under an is_effects `AddressPrefix`: an origin and a `PathPrefix`, compared by canonical segments, so a path reaches under a prefix only when it goes deeper than it. `/` is the whole site, written on purpose.
- `ToOwnReplyEndpoint.of(onOneOf)`: a web-request grant to wherever replies to the event that started the trajectory go, on one of the origins named. It matches nothing for a trajectory no event started, and `of` returns null for an empty list. A fixed prefix goes in `ToAddressesUnder(prefix)`.
- **Breaking:** `FlightRules` gains two required keys: `programsItMayRun`, the programs a trajectory may run (`allowsProgram`), and `programsItNeeds`, the ones a machine must have for it to start. `FlightRules.of` returns null, and `fromJson` throws, when a needed program isn't one it may run.
- Depends on is_effects ^0.14.0.

## 0.3.0

- `GoesAsBotLeasedFrom(BotPool)`: a grant to the sign-in of whichever bot the trajectory leases from that pool, matching nothing without a lease. On the wire, `{"kind": "botLeasedFrom", "pool": …}`.
- `WhatMayLeaveThisMachine.grantFor(site, signIn, leasedNow:, pooled:)` returns the grant that allows a web request, or null, and replaces `allowsWebRequest`, which could not say which lease a decision relied on. A sign-in in `pooled` is never granted by name: only a current lease lets a trajectory go as a pooled bot.
- Depends on is_effects ^0.12.0.

## 0.2.0

- `FlightRules`: `whatMayLeaveThisMachine` and a required `startingModel` (an is_effects `ModelAndSignIn`) whose sign-in must be one model calls may go out as. A trajectory's rules copy is now a `FlightRules`.
- Depends on is_effects ^0.11.0.

## 0.1.2

- Depends on is_effects ^0.9.0.

## 0.1.1

- Depends on is_effects ^0.8.0.

## 0.1.0

- `WhatMayLeaveThisMachine`, `SiteAndSignIn`, `GoesAs`, `ProgramsNetwork`, read and written with checked_json.
