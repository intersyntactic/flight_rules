# The rules table: per-person, per-conversation permissions

Status: for review by Nick and airlock-api-b2. Nothing is built yet. Rules
are live, and a withdrawn choice falls back and tells the person (Nick, 28
Nov). Fetch and web-request grants are live rows too, since threads stay
open for days to weeks (Nick, 28 Nov).

## What Nick asked for (27 Nov 2026)

- Call settings **bind**. The model, sign-in and effort a person chooses are
  what the airlock sends every call with. The loop can only ask for a change.
- Rules for messages between missions **differ per mission**.
- The most general shape. A simple default, with permissions that can be
  decided down to a fine grain: different people can have different settings
  in different situations.
- A "situation" is **a conversation or channel**.
- One human on Slack and on Teams is **one person**.
- Custom rules are **rows in a table**.

## The idea in one paragraph

The rules become a table. Each row grants one thing, to someone, somewhere,
perhaps after something else has happened first. Rows only ever add: no row
takes away what another gave. So an action is allowed exactly when some row
covers it, and nothing has to decide which row wins. When the airlock allows
something, it records the row that allowed it, so the logbook can always
answer "why was this allowed, and for whom?". This is how web requests already
work: `webRequestsGrantFor` returns the grant, not a yes.

## The columns

| Column | Holds | Cases |
|---|---|---|
| who | whose action the row covers | `anyone` (any named person in the conversation), or a person from the people list |
| where | which conversation | `anywhere`, or a mission (a channel) |
| allows | what the row lets them do | choose call settings, send to another mission, fetch, or make web requests |
| needs first | what must happen first | nothing, an okay from someone, or a Projection |

Not every kind of row has every column. A row is a sealed case per kind of
`allows`, each carrying only the columns it uses: fetch and web-request rows
have no `who` and no `needs first` (see [Fetch and web-request
rows](#fetch-and-web-request-rows)).

Each column is a closed set of cases (a sealed class), so a row the code
can't enforce can't be written. A new kind of permission is a code change,
because the airlock can only enforce what it has code to check.

### who

- `Anyone`: any **named** person in the conversation. An event that names no
  person (`TranslatedEvent.from` is null) is covered by no row at all, not
  even `Anyone`. It gets the trajectory's `startingModel` and can't choose
  anything else.
- `Person(name)`: a person from the people list, under any of their accounts.

There is no row keyed by a bare `ActorId`: Nick wants one person, not one per
account.

In the file, `anyone` is the bare word and a person is always an object,
`who: {person: hart}`. `anyone` is a valid `PersonName`, so writing a person
as a bare name too would let a person called `anyone` collide with the
keyword. With the two written differently, no name is reserved and none can
collide.

### The commander

Nick ruled on 28 Nov (loop-launcher's task 57) that each mission has exactly
one commander, named in a `commander` field of its rules. Left unset, it is
the coordinator bot of whoever started the mission (such as CAM). Every
crossing to another mission goes out through the commander. The
`SendToMission` rows decide whether it may go and what it needs first.

The commander is an agent, not a person, so it never appears in `who`. A
crossing row's `who` names the people whose words may be sent, and its
`OkayFrom` names the people who must okay them. Who may change the
commander is whoever edits the rules file, and since rules are live, the
change reaches open threads at their next crossing.

The airlock's decision on a crossing records the commander that sent it,
as its `ActorId` (an `agent:` id), beside the row's name and the
`PersonName`s it resolved for `who` and `OkayFrom`. The `commander` field can
change between rules versions, so the record names the agent itself, not
"the commander", and still answers "who sent this" after the field changes.

### where

A mission is a channel (or a chat with no threads), and each thread in it is
one trajectory, as the docking station's README puts it.

- `Anywhere`
- `InMission(AddressInExternalSystem)`: any thread of that channel.
- `InThread(AddressInExternalSystem)`: one thread. A thread's address
  exists only once someone has posted in it, so this row is always written
  after its trajectory is admitted. Live rules are what make it reach the
  thread: the airlock reads the newest rules at every action.

The docking station's rules file is already a table with only this column:
`default` is an `Anywhere` row, and `byMissionAddress` holds `InMission`
rows. This design adds the other three columns. A row whose `InMission`
names a channel the docking station doesn't let in makes the file
unreadable, as it does today.

### Each row has a name

Every row carries a `RuleName`, unique in the file, such as
`hart-opus-anywhere`. The airlock records that name as what allowed an
action, so "why was this allowed?" leads back to a line someone wrote, wherever
the row was copied to.

### When rules change: live (Nick, 28 Nov)

Today the docking station reads the rules file once, at service start, and
copies the rules into each trajectory's admission, so a change, including a
grant taken away, reaches only threads started after a restart. That was
the alternative, called frozen. It was turned down because a permission
taken away has to reach the threads already open.

Instead, the rules file is written to the logbook as a versioned entry, and
the airlock decides each action against the newest version. It matches
`where` itself, with a function in flight_rules that the docking station
calls too: a thread's mission is its `containingAddress`, or its own
address for a chat with no threads, the rule the docking station's
`AddressesLetIn` keeps today. One function, so the two can't disagree about
which mission a thread is in. A change
reaches every open thread at its next action. The record names the version
and the row.

"Newest" means the newest rules entry **before the action's proposal in
logbook order**, never the newest when the airlock happens to decide, so
replaying the logbook decides the same way every time. A version is that
entry's `EntryId`, with no counter of its own, and a decision lists it in
`reliedOn`. The airlock keeps the newest rules in memory, updating them
when a rules entry passes as it follows the chain, so deciding costs a
match over the rows, not a logbook read.

- **Only the table and the people list are live.** A trajectory's makeup
  (`programsItMayRun`, `programsItNeeds`, `givenTools`) stays fixed at
  admission, so a new version can't take away a program partway through a
  step. Fetch and web-request grants are rows in the table, so they are
  live: taking one away refuses the next request, which harms nothing
  already running.
- **The rules entry is its own logbook kind**, which the sender table lets
  only the docking station's user write. The airlock decides each action
  against the newest rules entry written before that action's proposal. The
  logbook keeps one order, so "newest" always has one answer.
- **A row is the same row across versions when it has the same name.** At
  each call the airlock looks up the row the decision named, by name, in
  the newest version, and checks it still covers that person and those
  settings. Fixing a typo keeps every choice made under the row. Narrowing
  the row withdraws only the choices it no longer covers. Removing or
  renaming it withdraws them all.
- **`FromStartingModel` names the rules version it came from**, since
  `startingModel` can change between versions too.
- **A call whose choice is withdrawn falls back and tells the person**
  (Nick, 28 Nov). It goes as the newest `startingModel`, recorded as
  `FromStartingModel`. The airlock can't reply, so its decision records
  that the choice was withdrawn. The program that posts the trajectory's
  replies reads that and tells the person; whether that's the loop or the
  docking station is still to settle with them. The alternative, refusing
  the call until someone chooses again, was turned down: a trajectory that
  stalls until someone happens to look is worse than one that keeps going
  on the default and says why.
- **Readers accept the previous rules format too** (airlock-api's task 126,
  in this batch on Nick's ruling of 28 Nov), since under live rules the
  file changes while threads run.
- **A new version is written by an operator command**, not by watching the
  file: a one-shot command (beside `close_trajectory`) reads the file,
  reads it back strictly, and writes it as the next version. It refuses to
  write a version it can't read back. The docking station also reads the
  newest rules from the logbook rather than from the file, so it and the
  airlock never decide on different versions.
- **No rules entry yet means refuse.** The docking station writes version 1
  before it admits anything. An action with no rules entry before its
  proposal is refused, whatever it is.
- **A newest entry the airlock can't read means refuse, not fall back.**
  Skipping it to decide on the version before would bring back any grant it
  took away. Refusing everything until a readable version is written fails
  safe. The command refusing unreadable versions, and the sender table
  letting only the docking station write the kind, keep this from happening
  by accident.
- **Each rules entry names its format, and the command writes only a format
  every live reader knows.** Reading its own write back can't catch a
  reader that is behind: a docking station that writes format 2 while the
  airlock reads only format 1 would turn every action off until the airlock
  is upgraded. So the command takes a setting for which format it writes,
  defaulting to the oldest format every live reader knows, as decisions do
  with `decisionFormat`. Readers learn a format first; writers move to it
  after.

### allows

- `ChooseCallSettings(signIn, models, effortUpTo)`: the person may choose
  that sign-in, with any of `models` (or any model), at an effort up to
  `effortUpTo` (or any). Effort compares by `Effort.rank`, so a level this
  code doesn't know ranks above every limit and is refused. These rows
  replace `modelSignInsCallsMayGoOutAs`: the sign-ins calls may go out as
  are the ones the rows name.
- `SendToMission(to)`: a message may cross to the mission `to`, or to any
  mission, sent by the mission's commander.
- `Fetch(GrantToFetch)` and `MakeWebRequests(GrantToMakeWebRequests)`: the
  grants `WhatMayLeaveThisMachine` holds today, unchanged, moved into rows.

### needs first

- `Nothing`
- `OkayFrom(who)`: someone `who` covers, in the sending conversation, okays
  that exact text going out. This is loop-launcher's "decided like a
  declassification".
- `Projection`: the text is drawn up by a Projection, not relayed.

Call-settings rows take only `Nothing`: the person choosing is the one
acting.

## The people list

```
people:
  hart: [slack:T01/U9, teams:acme/4f2…]
```

A person's name, with every account that is theirs. The list lives in the
rules file. Only whoever edits that file can link two accounts, because
linking an account to `hart` hands it Hart's permissions. An account may
appear under at most one person. A row naming a person not on the list
makes the file unreadable, as an unknown program does today. A decision
records both the `ActorId` and the `PersonName` it resolved to, so the
logbook answers "for whom" even after the list changes.

The types are `PersonName` and `PersonAccounts` in is_shapes 0.6.1
(https://github.com/intersyntactic/shapes/pull/25), beside `ActorId`.
`PersonAccounts` can't be built with an account under two people, or with a
person who has no accounts, since a row naming that person could never
match. Its `fromJson` reads the value of `people`, and names the faulty part
relative to it, so the rules reader prefixes `people.`.

## Binding call settings

1. A person chooses settings in the conversation: the More options dialog,
   or the agent proposing "switch to Opus" and the person accepting. The
   docking station writes a **settings choice**, a logbook kind of its own,
   holding the exact settings and the person's `ActorId` from the event they
   wrote. The logbook's sender table lets only the docking station's user
   write that kind, so the loop can't write one. An acceptance carries the
   exact settings it accepts, so a "yes" can't bind something the loop
   swapped in.
2. The airlock reads choosers only from that kind. It finds the person for
   the account, then a `ChooseCallSettings` row that covers them. If one
   does, it writes its decision: the settings, the chooser's `ActorId`, the
   `PersonName` it resolved to, the row's name, and the choice it answers.
   If none does, nothing changes.
3. Every model call takes its sign-in, model and effort from the newest
   allowed choice, or from `startingModel` when there is none. The loop no
   longer sends them: `ModelCall` shrinks to its request (airlock-api's
   breaking change).
4. At each call, `allowsModelCall(signIn) → bool` becomes
   `callSettingsGrantFor(…) → CallSettingsGrant?`, a sealed result:
   - `FromStartingModel`: no choice was made, and the call goes as the
     rules file's `startingModel`, granted by whoever wrote the file.
   - `ChosenUnderRow(decision)`: the call points at the airlock's decision
     on the newest choice, which already names its row. It doesn't search
     the rows again. Rows overlap (in the examples below, both
     `everyone-sonnet` and `hart-claude-anything` cover Hart choosing
     Sonnet), so a second search could name a different row than the
     decision did.
   - `WithdrawnToStartingModel(decision, version)`: the decision's row no
     longer covers the choice in the newest rules version, so the call goes
     as that version's `startingModel`, and the record says which choice
     was withdrawn so the person can be told.

   It never returns null for a model call: a withdrawn choice falls back.
   So every call's record says which applied, and "why" has one answer.

## Examples

```
rules:
  - name: everyone-sonnet
    who: anyone   where: anywhere
    allows: choose claude-team, models: [claude-sonnet-5-5], effort up to high
  - name: hart-claude-anything
    who: {person: hart}   where: anywhere
    allows: choose claude-team, any model, any effort
  - name: hart-gpt-in-finance
    who: {person: hart}   where: in mission teams:19:finance@thread.v2
    allows: choose openai-team, models: [gpt-5]
  - name: legal-to-finance
    who: anyone   where: in mission teams:19:legal@thread.v2
    allows: send to mission teams:19:finance@thread.v2
    needs first: okay from hart
  - name: finance-reads-ledger
    where: in mission teams:19:finance@thread.v2
    allows: fetch from addresses under https://ledger.example/api/, as nobody
```

## What changes, and who does it

| Where | Change | Session |
|---|---|---|
| shapes | `PersonName`, `PersonAccounts` (additive, 0.6.1, needs no window) | shapes-6e |
| flight_rules | the row types, `callSettingsGrantFor`; rows replace `modelSignInsCallsMayGoOutAs`, `fetchesMayReach` and `webRequestsMayReach`; the grant lookups return the row's name and version | flight-rules-55 |
| airlock_api, airlock | the settings entry, binding, `ModelCall` without model and sign-in; `Deny` gets a sealed reason in place of its `String` (`NoRowCovers`, `GrantWithdrawn`, `NoRulesEntry`, `UnreadableRules`, and a catch-all for today's refusals), and `Allow` names its row and rules entry, in is_airlock_api 0.27.0 behind `decisionFormat` | airlock-api-b2, airlock-d5 |
| docking_station | the rules file's people list and named rows; writing each version of the file to the logbook | docking-station-97 |
| infra | a new rules-file format, so an infra window and a fresh logbook (the one-shape rule) | infra-95 |

All of these are breaking, so they should ship as one batch, in one window.

## Fetch and web-request rows

Nick, 28 Nov: threads stay open for days to weeks. A grant fixed at
admission would then outlive its being taken away by that long, and web
requests are the channel words most easily leave by. So these grants are
live, and they are rows.

**Live** needs only the versioned rules entry: the airlock checks each fetch
and web request against the newest version, as it does a model call.

**Rows**, rather than a live copy of today's lists, so that `where` has one
encoding and one matching function. Keeping the lists would need a second
way to say "only in this mission" (the per-mission override map), and a
second function to match it.

- **No `who`, no `needs first`.** A tool's fetch is the agent's act, not a
  person's, so no person is there to cover or to okay it. These row kinds
  don't carry the columns, so a fetch row naming a person can't be written.
- **The decision names the row and the version.** `fetchGrantFor` and
  `webRequestsGrantFor` already return the grant rather than a yes; they
  return the row's `RuleName` and the rules version beside it, so the
  logbook answers "why was this allowed?" as it does for every other row.
- **`ToOwnReplyEndpoint` stays relative to the thread.** It names wherever
  replies to the event that started the trajectory go, so one row covers
  every thread its `where` covers, each reaching its own endpoint.
- **A refusal says the grant was withdrawn**, so the loop can tell "stop
  trying" from an ordinary refusal (the model still sees the tool, and
  will keep calling it), and the person learns why a tool that worked
  yesterday doesn't today. When no row covers a request, the airlock takes
  this trajectory's **last** Allow of the same kind (fetch, or web request)
  and matches the request against the rules version that Allow relied on.
  If a row there covers it, the refusal is `GrantWithdrawn`, naming that
  row and that Allow's entry, so the logbook itself proves it used to work.
  No row to key on survives the withdrawal, which is why the check goes by
  kind, and why the last Allow is enough: it's the rules the thread last
  worked under. The airlock keeps, per trajectory and kind, only the rows
  of that one version.
- **Tools stay frozen while their grants go live.** A tool given at
  admission whose grant is taken away is still given, and every request it
  makes is refused. That is the wanted result: the tool can't reach what it
  may no longer reach, and nothing is pulled out from under a running step.

What this costs:

- **A thread can gain reach while it runs.** A row added today reaches
  every open thread its `where` covers. Rows only add, so this follows from
  live rules, as it does for call settings, but it's new for fetches.
- **A mission can no longer reach less than the default.** Today
  `byMissionAddress` replaces a mission's rules whole, so a mission can
  narrow them. Rows only add, so an `Anywhere` fetch row reaches every
  mission. A file that narrows has to be rewritten as `InMission` rows for
  every mission but the narrowed one, so a new channel reaches nothing until
  someone writes its row. That fails closed, which suits fetches, but it's
  more to write. The live file has no per-mission overrides at all (infra,
  28 Nov), so converting it needs only the default's rows.
- **Admission no longer lists everything a thread could reach.** "What could
  this thread reach at time T?" is answered instead by the rows whose
  `where` covers it in the rules version that was newest at T. That's one
  logbook read, not a field on the admission.
