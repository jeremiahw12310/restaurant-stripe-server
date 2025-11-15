### Community Backend API Spec (Production Base: https://restaurant-stripe-server-1.onrender.com)

All endpoints are JSON and should return errors in the form `{ "error": { "code": string, "message": string } }`.

#### Auth
- All write actions require an authenticated user. Include session/auth headers per app standard.

#### Feed
- GET `/community/feed?segment=forYou|latest|following&cursor=string`
  - 200: `{ posts: PostDTO[], nextCursor?: string }`

#### Posts
- POST `/community/posts`
  - Body: `{ text: string, allowedLink?: { type: "orderOnline", url: string } }`
  - 201: `PostDTO`
  - Validation: Strip non-whitelisted links. Only allow `type=orderOnline` and `url === Config.orderOnlineURL`.
- GET `/community/posts/:id`
  - 200: `PostDTO`
- DELETE `/community/posts/:id` (owner or moderator)
  - 204

#### Reactions
- POST `/community/posts/:id/reactions`
  - Toggle like idempotently for current user
  - 200: `{ likedByMe: boolean, likeCount: number }`

#### Comments
- GET `/community/posts/:id/comments?cursor=string`
  - 200: `{ comments: CommentDTO[], nextCursor?: string }`
- POST `/community/posts/:id/comments`
  - Body: `{ text: string }`
  - 201: `CommentDTO`
- DELETE `/community/comments/:id` (owner or moderator)
  - 204

#### Reports (Flagged-only moderation)
- POST `/community/reports`
  - Body: `{ target: { type: "post"|"comment", id: string }, reason: string }`
  - 202: `{ status: "queued" }`
  - Side-effect: enqueue LLM review; on high-confidence violation auto-hide, else queue for human.

#### Moderation (role: moderator|admin)
- GET `/community/mod/queue?status=open|auto_hidden|escalated&cursor=string`
  - 200: `{ items: ModerationItemDTO[], nextCursor?: string }`
- POST `/community/mod/:id/action`
  - Body: `{ action: "hide"|"unhide"|"warn"|"ban"|"shadowBan", reason?: string }`
  - 200: `{ status: "ok" }`

#### Announcements (role: admin)
- GET `/community/announcements`
- POST `/community/announcements`
  - Body: `{ title: string, body: string, media?: string[], pinned?: boolean, startsAt?: ISO, expiresAt?: ISO }`

---

### DTOs

PostDTO
```
{
  id: string,
  authorId: string,
  authorName: string,
  createdAt: ISO8601,
  text: string,
  media: string[],
  likeCount: number,
  commentCount: number,
  likedByMe: boolean,
  allowedLink?: { type: "orderOnline", url: string },
  pinned?: boolean
}
```

CommentDTO
```
{
  id: string,
  postId: string,
  authorId: string,
  authorName: string,
  createdAt: ISO8601,
  text: string,
  likeCount: number,
  likedByMe: boolean,
  parentId?: string
}
```

ModerationItemDTO
```
{
  id: string,
  target: { type: "post"|"comment", id: string },
  reporterCount: number,
  llmVerdict?: { verdict: "allowed"|"borderline"|"violation", confidence: number, categories: string[] },
  status: "open"|"auto_hidden"|"escalated"|"resolved",
  preview: { text: string, authorName: string, createdAt: ISO8601 }
}
```

---

### Notes
- Pagination uses opaque `cursor` tokens.
- Server must re-validate link policy.
- LLM moderation uses the prompt/output schema in `LLM_MODERATION_PROMPT.md`.










