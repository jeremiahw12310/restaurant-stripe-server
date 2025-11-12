### Community — Option A Wireframes & UX Flows

Constraints: Feed‑centric. No Explore/Trending. No external links (only the whitelisted "Order Online"). Flagged‑only moderation with ChatGPT auto‑triage.

#### Feed (For You | Latest | Following)

Layout

```
[NavBar: Community]      [Search icon (future)]
[Segmented: For You | Latest | Following]

[AnnouncementBanner (optional, admin‑pinned)]

[PostCard]
  [Avatar]  [Display Name]   [Timestamp • Topic(optional)]
  [Text (hashtags/mentions highlighted)]
  [MediaGrid (0‑4)]
  [Order Online chip (if present)]
  [ReactionBar: ❤️ count   💬 count   ⋯]

[Skeletons x 3 while loading]
```

Interactions
- Pull‑to‑refresh; infinite scroll.
- Tap avatar/name → Profile.
- Tap chip → opens Order Online (whitelisted only).
- Long‑press post → Report / Copy link (internal id) / Delete (own).
- Tap ❤️ → optimistic like with heart burst animation; reconcile on response.
- Tap 💬 → open Comments sheet.

Empty states
- For You (cold start): "Follow people or post to personalize your feed" [Create Post].
- Following: "You’re not following anyone yet" [Discover from suggestions (future)].

#### Composer (full‑screen modal)

Layout

```
[Cancel]                       [Post]

[TextEditor]
[Media picker row]
[Poll builder (Add poll)]

[Order Online chip selector]
  (Only the app’s whitelisted URL; all other links are stripped.)

[Upload/Submit progress bar (animated)]
```

Behaviors
- Autosave drafts.
- Strip/neutralize non‑whitelisted URLs client‑side; server validates again.
- Optimistic insert into Feed on Post; show progress bar; reconcile or show retry toast.

#### Comments (sheet)

```
[Post header]
[Text field]  [Send]

[Top comment]
  [Avatar] [Name] [Timestamp]
  [Text]
  [❤️] [Reply]

[Load more replies]
```

Behaviors
- 1‑level threading; optimistic send; inline retry.
- Long‑press on own comment: Edit (within 5–15 min) / Delete.
- Long‑press on others: Report / Copy.

#### My (Profile lite)

Tabs: Posts | Drafts | Saved

```
[Header: Avatar, Name, Badges]
[Stats: Posts, Likes]

[Segmented: Posts | Drafts | Saved]
[List of PostCards]
```

#### Admin (role‑gated)

Moderation Queue (flagged only)

```
[Filters: Status, Reason, Confidence]
[Queue Row]
  [Preview] [Reporter count] [Model verdict+confidence]
  [Actions: Hide/Unhide | Warn | Ban | Shadow‑ban]
  [Notes]

[Audit Log]
[Announcements: Create/Pin/Expire]
```

#### Navigation
- Tab bar → Community.
- Segmented control inside Feed.
- Floating "Post" button in Feed.

#### Motion & Visual
- Card entrance fade/slide; heart burst on like; progress bar on send/upload.
- Theme: typography, color, spacing aligned with Home/Chatbot tokens.

#### Acceptance (MVP)
- Feed segments work with skeletons and infinite scroll.
- Composer enforces link policy and optimistic posting.
- Reactions are instant with burst animation.
- Comments thread with optimistic send and retry.
- Reports route to LLM, high‑confidence violations auto‑hidden, queue visible to Admin.








