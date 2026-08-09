// lounge.ts — LoungeDO (SESH-RL-001-R2).
//
// The public community feed. A Durable Object because the feed index is a
// read-modify-write structure: two concurrent posts against KV would routinely
// clobber each other's ordering. The DO serializes every write.
//
// Storage layout:
//   post:<id>            one record per post
//   idx                  bounded, newest-first [{ id, ts }] — the feed order
//   cmt:<postID>         bounded comment list
//   rx:<postID>:<uid>    viewer reaction
//   vote:<postID>:<uid>  viewer's poll choice
//   hide:<uid>:<postID>  "not interested"
//   rep:<id>             moderation report
//   follow:<uid>         uids this viewer follows
//   block:<uid>          uids this viewer blocked
//
// §12 privacy/moderation is enforced *here*, at query level — never only in the
// UI. A post that fails a visibility or moderation check is never serialized
// into a response at all.

import { displayHandle, displayName, str } from "./util";

const FEED_INDEX_LIMIT = 500;
const COMMENT_LIMIT = 200;
const PAGE_SIZE = 12;

type Visibility = "public" | "friends" | "private";
type Moderation = "ok" | "pending" | "hidden" | "removed";

interface MediaRecord {
  id: string;
  url: string;
  posterURL?: string | null;
  isVideo?: boolean;
  aspectRatio?: number;
  /** VoiceOver description supplied by the author (§12 accessibility). */
  altText?: string | null;
}

interface PollChoice { id: string; label: string; votes: number }

interface PollRecord {
  question: string;
  choices: PollChoice[];
  totalVotes: number;
  endsAt?: string | null;
  viewerChoiceID?: string | null;
}

interface LiveRecord {
  roomID: string;
  title: string;
  participantCount: number;
  participantAvatars?: string[];
  vibeTags?: string[];
  stillURL?: string | null;
  isLive: boolean;
}

interface AuthorRecord {
  id: string;
  handle: string;
  displayName: string;
  avatarURL?: string | null;
  isFollowed?: boolean;
}

interface PostRecord {
  id: string;
  author: AuthorRecord;
  kind: string;
  createdAt: string;
  text: string;
  media: MediaRecord[];
  track?: unknown;
  poll?: PollRecord | null;
  live?: LiveRecord | null;
  strainName?: string | null;
  method?: string | null;
  mood?: string | null;
  vibeTags: string[];
  reactionCount: number;
  commentCount: number;
  viewerHasReacted: boolean;
  visibility: Visibility;
  moderation: Moderation;
  /// Explicit audience for friends-only posts (uids). Empty means "author's
  /// followers", resolved at query time.
  audience: string[];
  layout: {
    characterCount: number;
    primaryAspect: number | null;
    hasMedia: boolean;
    supportedTemplates: string[];
    templateID: string | null;
  };
}

interface IndexEntry { id: string; ts: number }

const POLL_CHOICE_LIMIT = 6;
const POLL_LABEL_LIMIT = 60;

/** Whitelist client-supplied visibility — junk values must not fall through
 *  `canView` into world-readable. */
function sanitizeVisibility(v: unknown): Visibility {
  return v === "friends" || v === "private" ? v : "public";
}

/** Rebuild a client-supplied poll server-side: capped choices, clamped labels,
 *  and counts forced to zero so results can't be faked at create time. */
function sanitizePoll(raw: unknown): PollRecord | null {
  if (!raw || typeof raw !== "object") return null;
  const p = raw as Record<string, unknown>;
  const rawChoices = Array.isArray(p.choices) ? (p.choices as unknown[]) : [];
  const choices: PollChoice[] = rawChoices.slice(0, POLL_CHOICE_LIMIT).map((c, i) => {
    const rec = (c && typeof c === "object" ? c : {}) as Record<string, unknown>;
    return {
      id: str(rec.id, 80) || `choice_${i}`,
      label: str(rec.label, POLL_LABEL_LIMIT),
      votes: 0,
    };
  });
  if (choices.length === 0) return null;
  const endsAt = str(p.endsAt, 40);
  return {
    question: str(p.question, 300),
    choices,
    totalVotes: 0,
    endsAt: endsAt && !Number.isNaN(Date.parse(endsAt)) ? endsAt : null,
    viewerChoiceID: null,
  };
}

/** Worker-hosted media capability URLs (`/api/lounge/media/<uuid>`) are always
 *  acceptable; anything else must at least parse as an http(s) URL. */
const WORKER_MEDIA_RE = /^https?:\/\/[^/]+\/api\/lounge\/media\/[0-9a-fA-F-]{8,64}$/;

function acceptableMediaURL(url: string): boolean {
  if (WORKER_MEDIA_RE.test(url)) return true;
  try {
    const u = new URL(url);
    return u.protocol === "https:" || u.protocol === "http:";
  } catch { return false; }
}

/** Keep only the media fields the app renders, with clamped strings. */
function sanitizeMedia(raw: unknown): MediaRecord[] {
  if (!Array.isArray(raw)) return [];
  return (raw as unknown[]).slice(0, 4).flatMap((m) => {
    const rec = (m && typeof m === "object" ? m : {}) as Record<string, unknown>;
    const url = str(rec.url, 500);
    if (!url || !acceptableMediaURL(url)) return [];
    const aspect = typeof rec.aspectRatio === "number" && Number.isFinite(rec.aspectRatio)
      ? Math.min(Math.max(rec.aspectRatio, 0.1), 10) : undefined;
    return [{
      id: str(rec.id, 80) || crypto.randomUUID(),
      url,
      posterURL: str(rec.posterURL, 500) || null,
      isVideo: rec.isVideo === true,
      altText: str(rec.altText, 300) || null,
      ...(aspect !== undefined ? { aspectRatio: aspect } : {}),
    }];
  });
}

const LIVE_TITLE_LIMIT = 80;
const LIVE_VIBE_TAG_LIMIT = 4;
const LIVE_VIBE_TAG_CHARS = 24;
const LIVE_STALE_MS = 24 * 60 * 60 * 1000;

/** Rebuild a client-supplied live block server-side (SESH-RL-001-R2 Phase 4):
 *  clamped title/tags, participantCount forced non-negative, isLive forced true
 *  at create time, and a room auto-provisioned when the client sent none so
 *  every live post is joinable. */
function sanitizeLive(raw: unknown, postID: string): LiveRecord {
  const rec = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const vibeTags = Array.isArray(rec.vibeTags)
    ? (rec.vibeTags as unknown[])
        .flatMap((t) => (typeof t === "string" && t ? [t.slice(0, LIVE_VIBE_TAG_CHARS)] : []))
        .slice(0, LIVE_VIBE_TAG_LIMIT)
    : [];
  const rawCount = rec.participantCount;
  const participantCount = typeof rawCount === "number" && Number.isFinite(rawCount)
    ? Math.max(0, Math.floor(rawCount)) : 0;
  return {
    roomID: str(rec.roomID, 100) || `lounge_${postID}`,
    title: str(rec.title, LIVE_TITLE_LIMIT),
    participantCount,
    participantAvatars: Array.isArray(rec.participantAvatars)
      ? (rec.participantAvatars as unknown[])
          .flatMap((a) => (typeof a === "string" ? [a.slice(0, 500)] : []))
          .slice(0, 8)
      : [],
    vibeTags,
    stillURL: str(rec.stillURL, 500) || null,
    isLive: true,
  };
}

/** Defensive staleness cap: a live post older than 24h is treated as ended even
 *  if the author never called /live/end. */
function liveIsStale(post: PostRecord): boolean {
  const ts = Date.parse(post.createdAt);
  return Number.isFinite(ts) && Date.now() - ts > LIVE_STALE_MS;
}

/** §6.3 template compatibility, mirrored from LoungeLayoutEngine.swift. */
function supportedTemplates(post: PostRecord): string[] {
  const chars = post.text ? post.text.length : 0;
  const shortText = chars <= 180;
  const longForm = chars > 280;
  const pollNeedsFull =
    !!post.poll && (post.poll.choices.length >= 4 || post.poll.choices.some((c) => c.label.length > 24));
  switch (post.kind) {
    case "highThought":
      return shortText ? ["bubbleNarrow", "bubbleMedium", "bubbleFull"] : ["bubbleFull", "textCardFull"];
    case "rant":
      return longForm ? ["textCardFull"] : ["textCardWide", "textCardFull"];
    case "photo":
    case "munchies":
      return ["mediaWide", "mediaFull"];
    case "video":
      return ["mediaFull"];
    case "music":
      return ["playerMedium", "playerFull"];
    case "poll":
      return pollNeedsFull ? ["pollFull"] : ["pollMedium", "pollFull"];
    case "live":
      return ["liveFeature", "liveMedium"];
    case "review":
      return ["textCardFull", "textCardWide"];
    case "checkIn":
      return ["smallCard", "bubbleNarrow"];
    default:
      return ["textCardFull"];
  }
}

function hydrateLayout(post: PostRecord): PostRecord {
  const chars = post.text ? post.text.length : 0;
  post.layout = {
    characterCount: chars,
    primaryAspect: post.media.length > 0 ? post.media[0].aspectRatio ?? 1 : null,
    hasMedia: post.media.length > 0,
    supportedTemplates: supportedTemplates(post),
    templateID: post.layout?.templateID ?? null,
  };
  return post;
}

export class LoungeDO {
  private state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  // ---- storage helpers ----------------------------------------------------

  private async index(): Promise<IndexEntry[]> {
    return (await this.state.storage.get<IndexEntry[]>("idx")) ?? [];
  }

  private async setIndex(entries: IndexEntry[]): Promise<void> {
    await this.state.storage.put("idx", entries.slice(0, FEED_INDEX_LIMIT));
  }

  private async post(id: string): Promise<PostRecord | null> {
    return (await this.state.storage.get<PostRecord>(`post:${id}`)) ?? null;
  }

  private async list(key: string): Promise<string[]> {
    return (await this.state.storage.get<string[]>(key)) ?? [];
  }

  // ---- visibility (§12) ---------------------------------------------------

  /**
   * True when `viewer` may see `post`. Blocks are symmetric, private logs are
   * never public, and friends-only posts require an explicit audience match or
   * a follow edge.
   */
  private async canView(post: PostRecord, viewer: string,
                        following: string[], blocked: string[]): Promise<boolean> {
    if (post.moderation === "hidden" || post.moderation === "removed") {
      return post.author.id === viewer;      // authors still see their own pending/hidden
    }
    if (post.visibility === "private") return post.author.id === viewer;
    if (blocked.includes(post.author.id)) return false;

    const authorBlocks = await this.list(`block:${post.author.id}`);
    if (authorBlocks.includes(viewer)) return false;

    if (post.visibility === "friends" && post.author.id !== viewer) {
      if (post.audience.length > 0) return post.audience.includes(viewer);
      const authorFollows = await this.list(`follow:${post.author.id}`);
      return authorFollows.includes(viewer) && following.includes(post.author.id);
    }
    return true;
  }

  // ---- routing ------------------------------------------------------------

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const uid = request.headers.get("x-uid") || "";
    // Authored content is read by OTHER people, so a second-person placeholder
    // ("You" / "@you") must never end up on a post or comment as its author.
    const handle = displayHandle(request.headers.get("x-handle"), uid);
    const name = displayName(request.headers.get("x-name"), request.headers.get("x-handle"), uid);
    const idem = request.headers.get("x-idempotency-key");

    const ok = (data: unknown = {}) =>
      new Response(JSON.stringify(data), { headers: { "Content-Type": "application/json" } });
    const bad = (error: string, status = 400) =>
      new Response(JSON.stringify({ error }), { status, headers: { "Content-Type": "application/json" } });

    if (!uid) return bad("unauthorized", 401);

    let body: Record<string, unknown> = {};
    if (request.method === "POST") {
      try { body = await request.json(); } catch { body = {}; }
    }

    switch (true) {
      // ---- feed -----------------------------------------------------------
      case path === "/feed": {
        const tab = url.searchParams.get("tab") || "forYou";
        const filter = url.searchParams.get("filter") || "all";
        const cursor = url.searchParams.get("cursor");
        const session = url.searchParams.get("session") || crypto.randomUUID();

        const entries = await this.index();
        const following = await this.list(`follow:${uid}`);
        const blocked = await this.list(`block:${uid}`);

        // Cursor is "<ts>:<id>" — resume strictly after that entry, which keeps
        // ordering stable even if new posts land at the head mid-scroll (§11).
        let start = 0;
        if (cursor) {
          const [rawTs, rawID] = cursor.split(":");
          const ts = Number(rawTs);
          const at = entries.findIndex((e) => e.ts === ts && e.id === rawID);
          if (at >= 0) {
            start = at + 1;
          } else if (Number.isFinite(ts)) {
            // The cursor entry was evicted from the bounded index. Restarting
            // from 0 would loop duplicates forever — fall back to timestamp
            // order (index is newest-first) and report exhaustion when nothing
            // older remains.
            const older = entries.findIndex((e) => e.ts < ts);
            if (older >= 0) {
              start = older;
            } else {
              return ok({ posts: [], nextCursor: null, sessionID: session });
            }
          }
        }

        const posts: PostRecord[] = [];
        let i = start;
        let last: IndexEntry | null = null;

        for (; i < entries.length && posts.length < PAGE_SIZE; i++) {
          const entry = entries[i];
          const record = await this.post(entry.id);
          if (!record) continue;

          if (await this.state.storage.get(`hide:${uid}:${record.id}`)) continue;
          if (!(await this.canView(record, uid, following, blocked))) continue;

          if (tab === "following" && !following.includes(record.author.id)) continue;
          if (tab === "live" && !(record.kind === "live" && record.live?.isLive && !liveIsStale(record))) continue;
          if (filter !== "all" && !matchesFilter(record.kind, filter)) continue;

          posts.push(await this.decorate(record, uid, session));
          last = entry;
        }

        const more = i < entries.length;
        return ok({
          posts,
          nextCursor: more && last ? `${last.ts}:${last.id}` : null,
          sessionID: session,
        });
      }

      // ---- single post + comments ----------------------------------------
      case path.startsWith("/post/"): {
        const id = decodeURIComponent(path.slice("/post/".length));
        const record = await this.post(id);
        if (!record) return bad("not_found", 404);

        const following = await this.list(`follow:${uid}`);
        const blocked = await this.list(`block:${uid}`);
        if (!(await this.canView(record, uid, following, blocked))) return bad("not_found", 404);

        const comments = (await this.state.storage.get<unknown[]>(`cmt:${id}`)) ?? [];
        return ok({ post: await this.decorate(record, uid, ""), comments });
      }

      // ---- create ---------------------------------------------------------
      case path === "/create": {
        // Idempotent replay from the offline outbox: return the post created
        // by the first attempt instead of duplicating it.
        const idemKey = idem ? `idem:${idem.slice(0, 128)}` : null;
        if (idemKey) {
          const existingID = await this.state.storage.get<string>(idemKey);
          if (existingID) {
            const prev = await this.post(existingID);
            // Decorate so the shape matches the feed/detail responses — the
            // Swift LoungePost decoder requires the decorated author fields.
            if (prev) return ok({ post: await this.decorate(prev, uid, ""), replayed: true });
            return ok({ replayed: true });
          }
        }

        const id = crypto.randomUUID();
        const nowISO = new Date().toISOString();
        const kind = str(body.kind, 20) || "highThought";
        const record: PostRecord = hydrateLayout({
          id,
          author: { id: uid, handle, displayName: name, avatarURL: null },
          kind,
          createdAt: nowISO,
          text: str(body.text, 4000),
          media: sanitizeMedia(body.media),
          track: body.track ?? null,
          poll: sanitizePoll(body.poll),
          live: kind === "live" ? sanitizeLive(body.live, id) : null,
          strainName: str(body.strainName, 80) || null,
          method: str(body.method, 40) || null,
          mood: str(body.mood, 40) || null,
          vibeTags: Array.isArray(body.vibeTags) ? (body.vibeTags as string[]).slice(0, 6) : [],
          reactionCount: 0,
          commentCount: 0,
          viewerHasReacted: false,
          visibility: sanitizeVisibility(str(body.visibility, 10)),
          moderation: "ok",
          audience: Array.isArray(body.audience) ? (body.audience as string[]).slice(0, 200) : [],
          layout: { characterCount: 0, primaryAspect: null, hasMedia: false, supportedTemplates: [], templateID: null },
        });

        await this.state.storage.put(`post:${id}`, record);
        const entries = await this.index();
        entries.unshift({ id, ts: Date.parse(nowISO) });
        await this.setIndex(entries);
        if (idemKey) await this.state.storage.put(idemKey, id);
        // Decorate (isFollowed etc.) so the response decodes like every other
        // LoungePost the client consumes.
        return ok({ post: await this.decorate(record, uid, "") });
      }

      // ---- reactions ------------------------------------------------------
      case path === "/react": {
        const postID = str(body.postID, 80);
        const on = body.on === true;
        const record = await this.post(postID);
        if (!record) return bad("not_found", 404);
        if (!(await this.canView(record, uid,
          await this.list(`follow:${uid}`), await this.list(`block:${uid}`)))) {
          return bad("not_found", 404);
        }

        const key = `rx:${postID}:${uid}`;
        const had = !!(await this.state.storage.get(key));
        if (on && !had) {
          await this.state.storage.put(key, 1);
          record.reactionCount += 1;
        } else if (!on && had) {
          await this.state.storage.delete(key);
          record.reactionCount = Math.max(0, record.reactionCount - 1);
        }
        await this.state.storage.put(`post:${postID}`, record);
        return ok({ ok: true, reactionCount: record.reactionCount });
      }

      // ---- poll vote ------------------------------------------------------
      case path === "/vote": {
        const postID = str(body.postID, 80);
        const choiceID = str(body.choiceID, 80);
        const record = await this.post(postID);
        if (!record || !record.poll) return bad("not_found", 404);
        if (!(await this.canView(record, uid,
          await this.list(`follow:${uid}`), await this.list(`block:${uid}`)))) {
          return bad("not_found", 404);
        }
        if (record.poll.endsAt && Date.parse(record.poll.endsAt) <= Date.now()) {
          return bad("poll_closed", 409);
        }

        const key = `vote:${postID}:${uid}`;
        if (await this.state.storage.get(key)) return bad("already_voted", 409);

        const choice = record.poll.choices.find((c) => c.id === choiceID);
        if (!choice) return bad("bad_choice", 400);

        choice.votes += 1;
        record.poll.totalVotes += 1;
        await this.state.storage.put(key, choiceID);
        await this.state.storage.put(`post:${postID}`, record);
        return ok({ ...record.poll, viewerChoiceID: choiceID });
      }

      // ---- comments -------------------------------------------------------
      case path === "/comment": {
        const postID = str(body.postID, 80);
        const text = str(body.text, 1000).trim();
        if (!text) return bad("empty");
        const record = await this.post(postID);
        if (!record) return bad("not_found", 404);
        if (!(await this.canView(record, uid,
          await this.list(`follow:${uid}`), await this.list(`block:${uid}`)))) {
          return bad("not_found", 404);
        }

        const comment = {
          id: crypto.randomUUID(),
          author: { id: uid, handle, displayName: name, avatarURL: null },
          text,
          createdAt: new Date().toISOString(),
          reactionCount: 0,
        };
        const existing = (await this.state.storage.get<unknown[]>(`cmt:${postID}`)) ?? [];
        existing.push(comment);
        const kept = existing.slice(-COMMENT_LIMIT);
        await this.state.storage.put(`cmt:${postID}`, kept);

        // Count what is actually stored — the pre-slice length diverges once
        // the comment cap trims the list.
        record.commentCount = kept.length;
        await this.state.storage.put(`post:${postID}`, record);
        return ok(comment);
      }

      // ---- live sessions (Phase 4) ----------------------------------------
      case path === "/live/end": {
        const postID = str(body.postID, 80);
        const record = await this.post(postID);
        if (!record) return bad("not_found", 404);
        if (record.author.id !== uid) return bad("forbidden", 403);
        if (record.live && record.live.isLive) {
          record.live = { ...record.live, isLive: false };
          await this.state.storage.put(`post:${postID}`, record);
        }
        return ok({ post: await this.decorate(record, uid, "") });
      }

      // ---- moderation -----------------------------------------------------
      case path === "/report": {
        const postID = str(body.postID, 80);
        const reason = str(body.reason, 40);
        const id = crypto.randomUUID();
        await this.state.storage.put(`rep:${id}`, {
          id, postID, reason, detail: str(body.detail, 500),
          reporter: uid, at: new Date().toISOString(),
        });
        // Reporting always hides it for the reporter, review or not.
        await this.state.storage.put(`hide:${uid}:${postID}`, 1);

        // Escalate: a reported post goes to `pending` so ranking can drop it
        // while a human looks. Ranking must never reward violations (§12).
        const record = await this.post(postID);
        if (record && record.moderation === "ok") {
          record.moderation = "pending";
          await this.state.storage.put(`post:${postID}`, record);
        }
        return ok({ ok: true });
      }

      case path === "/hide": {
        const postID = str(body.postID, 80);
        const record = await this.post(postID);
        if (!record) return bad("not_found", 404);
        if (!(await this.canView(record, uid,
          await this.list(`follow:${uid}`), await this.list(`block:${uid}`)))) {
          return bad("not_found", 404);
        }
        await this.state.storage.put(`hide:${uid}:${postID}`, 1);
        return ok({ ok: true });
      }

      case path === "/block" || path === "/unblock": {
        // Also reached via router fan-out from the SocialDO block/unblock
        // endpoints, keeping this DO's `block:<uid>` edges (used by canView)
        // in sync with the social graph.
        const target = str(body.userID, 200);
        let blocks = await this.list(`block:${uid}`);
        if (path === "/block") {
          if (target && !blocks.includes(target)) blocks.push(target);
        } else if (target) {
          blocks = blocks.filter((b) => b !== target);
        }
        await this.state.storage.put(`block:${uid}`, blocks.slice(0, 500));
        return ok({ ok: true });
      }

      // ---- follow graph ---------------------------------------------------
      case path === "/follow" || path === "/unfollow": {
        const target = str(body.userID, 80);
        if (!target || target === uid) return bad("bad_target");
        let follows = await this.list(`follow:${uid}`);
        if (path === "/follow") {
          if (!follows.includes(target)) follows.push(target);
        } else {
          follows = follows.filter((f) => f !== target);
        }
        await this.state.storage.put(`follow:${uid}`, follows.slice(0, 2000));
        return ok({ ok: true, following: follows.length });
      }

      default:
        return bad("not_found", 404);
    }
  }

  /** Attaches per-viewer state and layout hints. Never leaks other viewers' state. */
  private async decorate(record: PostRecord, uid: string, session: string): Promise<PostRecord> {
    const copy: PostRecord = hydrateLayout({ ...record });
    // Staleness cap: never serialize a >24h-old session as still live.
    if (copy.live && copy.live.isLive && liveIsStale(copy)) {
      copy.live = { ...copy.live, isLive: false };
    }
    copy.viewerHasReacted = !!(await this.state.storage.get(`rx:${record.id}:${uid}`));
    if (copy.poll) {
      const choice = await this.state.storage.get<string>(`vote:${record.id}:${uid}`);
      copy.poll = { ...copy.poll, viewerChoiceID: choice ?? null };
    }
    const follows = await this.list(`follow:${uid}`);
    copy.author = { ...copy.author, isFollowed: follows.includes(copy.author.id) };
    if (session) copy.layout.templateID = `${session}:${record.id}`;
    return copy;
  }
}

/** §5.1 filter -> kind mapping, mirrored from LoungeFilter.admits. */
function matchesFilter(kind: string, filter: string): boolean {
  switch (filter) {
    case "all":          return true;
    case "highThoughts": return kind === "highThought";
    case "music":        return kind === "music";
    case "rants":        return kind === "rant";
    case "polls":        return kind === "poll";
    case "photos":       return kind === "photo" || kind === "video";
    case "reviews":      return kind === "review";
    case "munchies":     return kind === "munchies";
    case "live":         return kind === "live";
    default:             return true;
  }
}
