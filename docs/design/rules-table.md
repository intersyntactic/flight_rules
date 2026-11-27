# The rules table: per-person, per-conversation permissions

Status: draft for review by Nick and airlock-api-b2. Nothing is built yet.

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
| allows | what the row lets them do | choose call settings, or send to another mission |
| needs first | what must happen first | nothing, an okay from someone, or a Projection |

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
account. Roles (such as a mission commander) wait for Nick's ruling on loop-launcher's
task 57: whether the commander is a fixed role per mission, and who
appoints it.

### where

A mission is a channel (or a chat with no threads), and each thread in it is
one trajectory, as the docking station's README puts it.

- `Anywhere`
- `InMission(AddressInExternalSystem)`: any thread of that channel.
There is no single-thread case. A thread's address exists only once someone
has posted in it, and that first post is what admits its trajectory, so a
row for one thread could only ever be written too late.

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

### When rules change: frozen or live (Nick's call)

Today the docking station reads the rules file once, at service start, and
copies the rules into each trajectory's admission. A trajectory runs on
those rules until it closes. Two ways forward:

- **Frozen (as today).** The docking station copies the rows whose `where`
  covers the trajectory, and the people list, into its `FlightRules` at
  admission. It's simple and every admission records its whole rules. But a
  change, whether a grant to Hart, a grant taken away, or an account linked,
  reaches only threads started after the service restarts. An open thread
  keeps the old rows, including a grant that was taken away.
- **Live.** The rules file is written to the logbook as a versioned entry,
  and the airlock decides each action against the newest version, matching
  `where` itself (with a function shared with the docking station). A
  change reaches every open thread at its next action. The record names the
  version and the row. A row for a single thread also works again under
  live, since a row written after the thread exists reaches it. So
  choosing frozen or live settles that too.

### allows

- `ChooseCallSettings(signIn, models, effortUpTo)`: the person may choose
  that sign-in, with any of `models` (or any model), at an effort up to
  `effortUpTo` (or any). Effort compares by `Effort.rank`, so a level this
  code doesn't know ranks above every limit and is refused. These rows
  replace `modelSignInsCallsMayGoOutAs`: the sign-ins calls may go out as
  are the ones the rows name.
- `SendToMission(to)`: a message may cross to the mission `to`, or to any
  mission. Who sends it is the open commander question.

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

The types, a `PersonName` and the list, belong beside `ActorId` in is_shapes,
whose doc already plans "a table beside them" for joining accounts. That
is a change in the shapes repo, so it's a brief to that repo's session, not
work done from here.

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
   - null: refused. Under frozen rules that can't happen once a choice is
     allowed. Under live rules it happens when the row the decision named
     is gone from the newest version.

   So every call's record says which applied, and "why" has one answer.

## Examples

```
rules:
  - name: everyone-sonnet
    who: anyone   where: anywhere
    allows: choose claude-team, models: [claude-sonnet-5-5], effort up to high
  - name: hart-claude-anything
    who: hart     where: anywhere
    allows: choose claude-team, any model, any effort
  - name: hart-gpt-in-finance
    who: hart     where: in mission teams:19:finance@thread.v2
    allows: choose openai-team, models: [gpt-5]
  - name: legal-to-finance
    who: anyone   where: in mission teams:19:legal@thread.v2
    allows: send to mission teams:19:finance@thread.v2
    needs first: okay from hart
```

## What changes, and who does it

| Where | Change | Session |
|---|---|---|
| shapes | `PersonName`, the people list | the shapes session (none listed as running on 27 Nov) |
| flight_rules | the row types, `callSettingsGrantFor`; rows replace `modelSignInsCallsMayGoOutAs` | flight-rules-55 |
| airlock_api, airlock | the settings entry, binding, `ModelCall` without model and sign-in | airlock-api-b2, airlock-d5 |
| docking_station | the rules file's people list and named rows; matching `where` at admission (frozen) or writing the file to the logbook (live) | docking-station-97 |
| infra | a new rules-file format, so an infra window and a fresh logbook (the one-shape rule) | infra-95 |

All of these are breaking, so they should ship as one batch, in one window.

## Open

1. Roles: is the commander a fixed role per mission, and who appoints it?
   (Nick, via loop-launcher's task 57.) Until then, crossing rows can name
   only `anyone` or a person.
2. Frozen or live (above). Under frozen, `where` never reaches the airlock;
   under live, the airlock matches it.
3. Do fetch and web-request grants move into the table too? They have no
   `who`, because a tool's fetch is the agent's, not a person's. This draft
   leaves them where they are.
