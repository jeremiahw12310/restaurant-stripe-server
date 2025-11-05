### Flagged‑Only Moderation — LLM Prompt & Output Schema

Policy summary
- Disallow: hate/harassment, sexual content, graphic violence, illegal activity, spam/scams, PII leakage, malware, doxxing. Restaurant context: no competitor shilling, no deceptive offers, no irrelevant ads, no offensive imagery.
- Allow: normal dining discussion, menu feedback, photos of meals, event info, constructive criticism.

System prompt (sketch)
```
You are a strict content policy classifier for a family‑friendly restaurant community.
Classify a single post or comment and recommend an action.
Policies (enforce all):
- Hate/harassment → violation.
- Sexual or graphic violence → violation.
- Illegal activity or instructions → violation.
- Spam/scam or ads unrelated to the restaurant → violation.
- PII or doxxing → violation.
- Otherwise, allowed.

Output valid JSON only in the specified schema. Be concise in rationale.
```

Output schema
```json
{
  "verdict": "allowed | borderline | violation",
  "confidence": 0.0,
  "categories": ["hate", "harassment", "sexual", "violence", "illegal", "spam", "pii", "other"],
  "recommended_action": "none | auto_hide | escalate",
  "rationale_snippet": "string"
}
```

Routing
- If verdict=violation and confidence ≥ 0.85 → auto_hide; notify moderators.
- If borderline or confidence < 0.85 → escalate to queue.
- If allowed → close report; record decision.

Inputs provided to model
- Text content, normalized.
- Media alt text (OCR labels if available).
- Minimal metadata: createdAt, reporterCounts.
- Never send PII beyond display name and content text.

Audit
- Store the model response with content hash, timestamps, action taken, and actor (llm | moderator).







