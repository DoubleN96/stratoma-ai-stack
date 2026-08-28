# WhatsApp — communities as funnel units

Provision WhatsApp Communities from code: one command creates the community, sets
its photo and description, opens entry, promotes admins, posts and pins a welcome,
and removes the "General" chat so only the announcements group remains.

## First, the decision nobody explains properly

**Evolution API and Baileys are not competitors.** Evolution *is* Baileys wrapped in
an HTTP server — check its `package.json` and you will find the same library this
folder depends on. That single fact settles most of the argument:

| | Baileys (direct) | Evolution API (or similar) |
|---|---|---|
| What it is | the library | an HTTP server built on the library |
| Reach | everything WhatsApp allows | only what the server chose to expose |
| Communities | ✅ | ❌ `/community/*` returns 404 |
| Webhooks, multi-number | you build it | included |
| Calling it from n8n / a backend | no — it is a script | yes, plain HTTP |
| Session upkeep | yours to handle | handled |

So the sane split, and the one this repo uses:

- **Day-to-day messaging, inbound handling, group admin → Evolution.** It is what
  integrates with everything and needs no babysitting.
- **Community provisioning → a Baileys script**, because no HTTP layer exposes it.

Do not migrate one to the other. Run both, over the same account, **never at the
same time** — see the warning below.

## The one rule that will bite you

**Never open two Baileys sockets on the same WhatsApp account.** Not "avoid it" —
never. The second connection fights the first and takes the session down with it,
and recovering means scanning a QR from the phone that owns the number.

In practice: whatever daemon normally holds the session (a gateway, a poster, a
bot) must be **stopped** before running this script, and started again after.
Budget ~30s for a clean shutdown and confirm the process is really gone — matching
on the process name alone often matches the shell that launched it, which reads as
"still running" forever.

## Setup

```bash
npm install
cp community.example.json community.json   # then edit it
```

The `authDir` must point at an **already-paired** Baileys credentials folder. This
script does not pair; it reuses the session of whatever tool linked the number.

```bash
node create-community.mjs community.json photo.jpg
```

It prints a JSON record at the end — community JID, invite link, announcements
group JID. Keep it: that is what a rotation registry needs.

## What the flow gets right, and why

Each step exists because of something that failed in production first.

- **Announcements group only, "General" removed.** In a normal group members can
  see each other's phone numbers, which is a gift to anyone running "hi, I'm from
  the team, pay here" scams on your own audience. The announcements group has the
  same reach without exposing the list.
- **Join approval turned off.** Communities are created with approval ON. An
  approval queue in front of a funnel link is a funnel that leaks.
- **Admins join first, get promoted second.** Adding people programmatically
  mostly fails: accounts block being added by strangers, and WhatsApp rate-limits
  it aggressively. Send them the invite link, let them join, then re-run with
  `"promoteOnly": true`.
- **Description written on the parent.** In current Baileys builds the community
  description call throws on the response parse. Passing the description to
  `communityCreate`, or writing it with `groupUpdateDescription` on the parent
  JID, works.
- **Delays between calls.** They are not padding. Firing these calls back to back
  is exactly the pattern that gets an account flagged.

## Scaling: many communities, one rotating link

A single community has a member ceiling, so growth past it means several
communities with one public link that moves between them: the link points at the
community currently accepting people; when it fills, the link advances to the next.

Two things worth deciding before building it:

- **Cap each community well below the platform limit.** A lower cap is a
  moderation decision, not a delivery one — smaller rooms stay manageable.
- **Keep a registry** (a sheet, a table, a JSON file) with, per community: invite
  link, announcements JID, cap, current members, state. The rotator reads that;
  without it you are guessing.

An announcement then means posting to every announcements group, one per
community. That volume is the argument for a **dedicated number**: see below.

## Risk, stated plainly

This is not the official WhatsApp Business API. Baileys, Evolution and every
similar tool connect **as if they were WhatsApp Web**, which is against WhatsApp's
terms and can get the number banned. The library you pick does not change that —
**behaviour does**: volume, speed, and messaging people who never opted in.

Three practical consequences:

1. **Use a dedicated number for automation.** Not the one your business actually
   talks to customers with, and not one shared with a bot people depend on. When a
   number goes down it takes everything on it with it.
2. **Ramp slowly.** Creating communities in bursts looks exactly like abuse.
3. **If you ever need real volume to people who did not opt in, stop and use the
   official API.** It costs money and does not get banned. That trade is worth it
   long before a ban teaches you the same lesson.
