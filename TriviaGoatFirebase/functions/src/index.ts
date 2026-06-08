/* -------------------------------------------------------------------------- */
/* IMPORTS                                                                    */
/* -------------------------------------------------------------------------- */
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentUpdated,
  type FirestoreEvent,
  type Change,
  type DocumentSnapshot,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import * as logger from "firebase-functions/logger";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";

import { initializeApp } from "firebase-admin/app";
import {
  getFirestore,
  FieldValue,
  type Transaction,
} from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

import { createHash, randomBytes } from "node:crypto";
import { Resend } from "resend";

import {
  GoogleGenerativeAI,
  type GenerativeModel,
} from "@google/generative-ai";
/* -------------------------------------------------------------------------- */
/* INIT                                                                       */
/* -------------------------------------------------------------------------- */

initializeApp();

const db = getFirestore("b4-v2-default-clone");
const messaging = getMessaging();
setGlobalOptions({ region: "us-central1" });

/* -------------------------------------------------------------------------- */
/* SECRETS                                                                    */
/* -------------------------------------------------------------------------- */

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");
const RESEND_FROM_EMAIL = defineSecret("RESEND_FROM_EMAIL");

/* -------------------------------------------------------------------------- */
/* CONSTANTS                                                                  */
/* -------------------------------------------------------------------------- */

const OWNER_UID = "kqp5LxM5DvSDL3BUEpHmFeoNgw03";
const WEBSITE_ROOT_DOC = "website";
const ADMIN_CONFIG_COLLECTION = "adminConfig";
const PLATFORM_CONFIG_DOC = "platformSettings";
const ADMIN_AUDIT_LOGS_COLLECTION = "adminAuditLogs";

const DEFAULT_FEATURE_FLAGS: Record<string, boolean> = {
  global_battle_live: true,
  events_public_access: true,
  community_launch_surface: false,
  pro_paywall_entry: false,
  sponsor_rotation_surface: false,
  public_stats_sync: true,
};

const WEBSITE_LEADERBOARD_SNAPSHOTS_COLLECTION = db
  .collection("website")
  .doc(WEBSITE_ROOT_DOC)
  .collection("leaderboard")
  .doc("snapshots")
  .collection("snapshots");

const DAILY_MISSION_TOPICS: string[] = [
  "Daily Mission: General Knowledge Blitz",
  "Daily Mission: World Capitals",
  "Daily Mission: Science & Space",
  "Daily Mission: Ancient Civilizations",
  "Daily Mission: Famous Inventions",
  "Daily Mission: Pop Culture Classics",
  "Daily Mission: Geography Essentials",
  "Daily Mission: Sports Legends",
  "Daily Mission: Movies & TV",
  "Daily Mission: Technology Milestones",
  "Daily Mission: Music Through the Decades",
  "Daily Mission: History Turning Points",
  "Daily Mission: Mythology & Folklore",
  "Daily Mission: Animals & Nature",
  "Daily Mission: Business & Brands",
  "Daily Mission: World Cuisines",
  "Daily Mission: Black History",
];

const RESERVED_USERNAME_WORDS = new Set<string>([
  "admin",
  "administrator",
  "mod",
  "moderator",
  "support",
  "staff",
  "system",
  "official",
  "triviagoat",
  "trivia_goat",
  "goat",
  "gt",
  "developer",
  "dev",
  "owner",
  "founder",
  "firebase",
  "google",
  "openai",
]);

const BANNED_USERNAME_FRAGMENTS: string[] = [
  "fuck",
  "fuk",
  "shit",
  "bitch",
  "asshole",
  "bastard",
  "slut",
  "whore",
  "dick",
  "cunt",
  "nigger",
  "nigga",
  "faggot",
  "retard",
  "rape",
  "rapist",
  "nazi",
  "hitler",
  "kkk",
  "pedo",
  "porn",
  "sex",
  "suicide",
  "kill",
  "murder",
];

const BLOCKED_COMMENT_FRAGMENTS: string[] = [
  "fuck", "fucking", "fucker", "fuk", "shite", "bitch", "cunt", "pussy", "dick", "cock",
  "bastard", "twat", "wanker", "clit", "ejaculate", "cum", "ass", "asshole",
  "nigger", "nigga", "nigg@", "faggot", "fag", "retard", "kike", "tranny", "chink", "wetback",
  "nazi", "hitler", "holocaust", "kkk",
  "idiot", "moron", "dumbass", "you suck", "loser", "trash", "garbage", "worthless",
  "pathetic", "failure", "kiss my ass", "eat shit",
  "kill yourself", "kys", "suicide", "cutting", "hang yourself", "shoot yourself",
  "drink bleach", "go die", "get cancer", "murder", "terrorism", "bomb",
  "porn", "xxx", "sex", "rape", "rapist", "pedophile", "pedo", "molest", "bestiality",
  "deepfake", "naked", "nudes", "incest", "hardcore",
  "f.u.c.k", "f_u_c_k", "f*ck", "sh1t", "b1tch", "a$$", "p0rn", "ree-tard", "n1gga", "4ss",
];

const ALLOWED_MODELS = new Set<string>([
  "gemini-3-flash-preview",
  "gemini-3.1-pro-preview",
  "gemini-3.1-flash-lite-preview",
]);

/* -------------------------------------------------------------------------- */
/* TYPES                                                                      */
/* -------------------------------------------------------------------------- */

type UserDoc = {
  displayName?: string;
  displayNameKey?: string;
  email?: string | null;
  fcmToken?: string;
  iq?: number | FieldValue;
  gold?: number | FieldValue;
  xp?: number | FieldValue;
  matchesWon?: number | FieldValue;
  role?: string;
  accountType?: string;
  isPublic?: boolean;
  createdAt?: FieldValue;
  updatedAt?: FieldValue;
};

type LeaderboardGlobalDoc = {
  topUid?: string;
  topName?: string;
};

type TriviaQuestionDTO = {
  prompt: string;
  choices: [string, string, string, string];
  correctIndex: 0 | 1 | 2 | 3;
};

type GeminiQuestionWire = {
  prompt?: unknown;
  choices?: unknown;
  correctIndex?: unknown;
};

type DailyMissionPackDoc = {
  dayKey: string;
  topic: string;
  questions: TriviaQuestionDTO[];
  generatedAt: string;
  model: string;
  status?: "generating" | "ready";
  lockedTopic?: string;
};

type UsernameRateLimitDoc = {
  windowStartMs?: number;
  attemptCount?: number;
  lastAttemptMs?: number;
};

type GenericRateLimitDoc = {
  windowStartMs?: number;
  attemptCount?: number;
  updatedAt?: FieldValue;
};

type PlatformPostDoc = {
  content?: string;
  authorUID?: string;
  authorName?: string;
  status?: string;
  isAI?: boolean;
  commentsCount?: number;
  aiReplyGenerated?: boolean;
  aiReplyGeneratedAt?: FieldValue | string;
  aiReplyMode?: string;
  aiReplyTopic?: string;
  aiReplyModel?: string;
};

type PlatformCommentDoc = {
  postID?: string;
  parentCommentID?: string;
  content?: string;
  authorUID?: string;
  authorName?: string;
  status?: string;
  isAI?: boolean;
  seededByAdmin?: boolean;
  source?: string;
  moderationSource?: string;
  moderationReason?: string;
  moderationModel?: string;
};

type AiReplyMeta = {
  reply: string;
  replyMode: string;
  replyTopic: string;
  model: string;
};

type AiFeaturedPostMeta = {
  content: string;
  contentType: string;
  topic: string;
  model: string;
};

type SeedCommunityLaunchResult = {
  aiPostId?: string;
  communityPostId?: string;
  skippedAI: boolean;
  skippedCommunity: boolean;
};

type CommentModerationMeta = {
  verdict: "approved" | "rejected" | "pending";
  reason: string;
  model: string;
};

type PostModerationMeta = {
  verdict: "approved" | "rejected" | "pending";
  reason: string;
  model: string;
};

type PublicStatsDoc = {
  totalBattlesPlayed: number;
  totalUsers: number;
  totalPosts: number;
  totalEvents: number;
  totalApprovedPosts: number;
  updatedAt?: FieldValue;
};

type PublicLeaderboardSnapshotDoc = {
  uid: string;
  displayName: string;
  username: string;
  score: number;
  wins: number;
  streak: number;
  rank: number;
  updatedAt?: FieldValue;
};

type UserLeaderboardSourceDoc = {
  displayName?: string;
  displayNameKey?: string;
  xp?: number;
  matchesWon?: number;
  globalRank?: number;
};

type PlatformEventDoc = {
  title?: string;
  slug?: string;
  heroLine?: string;
  summary?: string;
  status?: "draft" | "scheduled" | "live" | "ended" | "cancelled";
  visibility?: "public" | "invite_only";
  category?: "launch" | "tournament" | "university" | "sponsored" | "community";
  locationType?: "virtual" | "hybrid" | "in_person";
  startsAt?: FieldValue | string;
  endsAt?: FieldValue | string;
  rsvpOpensAt?: FieldValue | string;
  rsvpClosesAt?: FieldValue | string;
  waitlistOpensAt?: FieldValue | string;
  waitlistClosesAt?: FieldValue | string;
  capacity?: number;
  waitlistEnabled?: boolean;
  inviteOnly?: boolean;
  published?: boolean;
  featured?: boolean;
  launchWaveLabel?: string;
  createdBy?: string;
  updatedBy?: string;
  createdAt?: FieldValue;
  updatedAt?: FieldValue;
};

type PlatformEventInviteDoc = {
  uid: string;
  email: string;
  displayName: string;
  status: "invited" | "accepted" | "declined" | "approved";
  inviteSource: "admin" | "request_access" | "waitlist_promotion" | "event_crm";
  eventId: string;
  invitedBy: string;
  invitedAt?: FieldValue;
  respondedAt?: FieldValue | null;
  updatedAt?: FieldValue;
};


type PlatformEventGuestDoc = {
  eventId: string;
  name: string;
  email: string;
  role: string;
  organization?: string;
  notes?: string;
  isVIP?: boolean;
  invitationStatus: "staged" | "invited" | "accepted" | "declined" | "checked_in";
  invitationTokenHash?: string | null;
  invitationTokenCreatedAt?: string | null;
  invitationExpiresAt?: string | null;
  invitedAt?: FieldValue | null;
  acceptedAt?: FieldValue | null;
  declinedAt?: FieldValue | null;
  source?: "contacts" | "manual" | "import";
  invitedBy?: string;
  createdAt?: FieldValue;
  updatedAt?: FieldValue;
};


type PlatformEventAccessRequestDoc = {
  uid: string;
  email: string;
  displayName: string;
  eventId: string;
  status: "requested" | "approved" | "rejected";
  note?: string;
  createdAt?: FieldValue;
  updatedAt?: FieldValue;
  reviewedAt?: FieldValue | null;
  reviewedBy?: string | null;
};

type PlatformEventAccessLeadDoc = {
  email?: string;
  displayName?: string;
  note?: string;
  eventId?: string;
  status?: "pending_verification" | "verified" | "approved" | "rejected" | "waitlisted";
  verificationMethod?: "email_link";
  verificationTokenHash?: string | null;
  verificationTokenCreatedAt?: string | null;
  verificationExpiresAt?: string | null;
  verificationSentAt?: FieldValue | null;
  verifiedAt?: FieldValue | null;
  requestedAt?: FieldValue;
  invitedAt?: FieldValue | null;
  approvedAt?: FieldValue | null;
  updatedAt?: FieldValue;
  source?: "public_request_access";
  sourceCampaign?: string;
  linkedUid?: string | null;
    referralSource?: string;
    referralMedium?: string;
    referralCampaign?: string;
    referralContent?: string;
    landingURL?: string;

    attribution?: EventAttribution;
  };

type PlatformEventWaitlistDoc = {
  uid: string;
  email: string;
  displayName: string;
  status: "waiting" | "promoted" | "removed";
  eventId: string;
  createdAt?: FieldValue;
  updatedAt?: FieldValue;
  promotedAt?: FieldValue | null;
  promotedBy?: string | null;
};

type SubmitPostResult = {
  success: true;
  postId: string;
  status: "pending" | "approved";
};

type SubmitCommentResult = {
  success: true;
  commentId: string;
  postId: string;
  status: "pending" | "approved";
};

type PlatformConfigDoc = {
  featureFlags?: Record<string, boolean>;
  updatedAt?: FieldValue;
  updatedBy?: string;
  version?: number | FieldValue;
};

type AdminAuditLogDoc = {
  action: string;
  actorUid: string;
  actorRole: string;
  targetType: string;
  targetId: string;
  note?: string;
  before?: Record<string, unknown>;
  after?: Record<string, unknown>;
  createdAt?: FieldValue;
};

type AdminActor = {
  uid: string;
  role: string;
};

/* -------------------------------------------------------------------------- */
/* SHARED HELPERS                                                             */
/* -------------------------------------------------------------------------- */

/**
 * Moderates a community post.
 * Uses deterministic blocking first, then AI JSON moderation.
 * AI uncertainty falls back to pending review, never approval.
 * @param {string} authorName - Author name.
 * @param {string} content - Post content.
 * @return {Promise<PostModerationMeta>} Moderation result.
 */
async function moderatePostContent(
  authorName: string,
  content: string
): Promise<PostModerationMeta> {
  const trimmed = content.trim();
  const modelName = getFastModel();

  if (containsBlockedContent(trimmed)) {
    return {
      verdict: "rejected",
      reason: "policy_blocked_content",
      model: modelName,
    };
  }

  const model = createGemini(GEMINI_API_KEY.value(), modelName);
  const prompt =
    "Return ONLY valid JSON. No markdown. No extra text.\n\n" +
    "{\"verdict\":\"APPROVED\"} OR {\"verdict\":\"REJECTED\",\"reason\":\"toxicity\"}\n\n" +
    "Reasons: toxicity, hate, harassment, sexual, violence, self_harm, spam, scam, other.\n\n" +
    "Reject posts that contain hate speech, harassment, sexual content, " +
    "violence, self-harm encouragement, threats, scams, spam, doxxing, " +
    "illegal guidance, or graphic abuse.\n\n" +
    "Approve posts that are safe, relevant, and appropriate for a public trivia community.\n\n" +
    `Author: ${authorName}\n` +
    `Post:\n${trimmed}`;

  try {
    const result = await model.generateContent({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0,
        maxOutputTokens: 40,
        responseMimeType: "application/json",
      },
    });

    const raw = String(result.response.text() ?? "").trim();

    let parsed: { verdict?: string; reason?: string } | null = null;

    try {
      const temp = safeJsonParse(raw) as unknown;
      if (isRecord(temp)) {
        parsed = {
          verdict: typeof temp.verdict === "string" ? temp.verdict : undefined,
          reason: typeof temp.reason === "string" ? temp.reason : undefined,
        };
      }
    } catch {
      return {
        verdict: "pending",
        reason: "ai_parse_fallback",
        model: modelName,
      };
    }

    if (parsed?.verdict === "APPROVED") {
      return {
        verdict: "approved",
        reason: "safe",
        model: modelName,
      };
    }

    if (parsed?.verdict === "REJECTED") {
      return {
        verdict: "rejected",
        reason: parsed.reason ?? "policy_ai",
        model: modelName,
      };
    }

    return {
      verdict: "pending",
      reason: "ai_uncertain",
      model: modelName,
    };
  } catch (error) {
    logger.warn("moderatePostContent AI fallback", {
      error: String(error),
      authorName,
    });

    return {
      verdict: "pending",
      reason: "ai_unavailable",
      model: modelName,
    };
  }
}

/**
 * Enforces a generic per-key rate limit inside a rolling fixed window.
 * @param {string} key - Unique rate-limit key.
 * @param {number} maxAttempts - Maximum attempts allowed in the window.
 * @param {number} windowMs - Window size in milliseconds.
 * @param {string} message - User-facing limit message.
 * @return {Promise<void>} Completion promise.
 */
async function enforceRateLimit(
  key: string,
  maxAttempts: number,
  windowMs: number,
  message: string
): Promise<void> {
  const ref = db.collection("rateLimits").doc(key);
  const nowMs = Date.now();

  await db.runTransaction(async (tx: Transaction) => {
    const snap = await tx.get(ref);
    const data = (snap.data() ?? {}) as GenericRateLimitDoc;

    const windowStartMs =
      typeof data.windowStartMs === "number" ? data.windowStartMs : nowMs;
    const attemptCount =
      typeof data.attemptCount === "number" ? data.attemptCount : 0;

    const windowAge = nowMs - windowStartMs;

    if (windowAge >= windowMs) {
      tx.set(
        ref,
        {
          windowStartMs: nowMs,
          attemptCount: 1,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    if (attemptCount >= maxAttempts) {
      throw new HttpsError("resource-exhausted", message);
    }

    tx.set(
      ref,
      {
        windowStartMs,
        attemptCount: attemptCount + 1,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

/**
 * Safely converts unknown input to a trimmed string.
 * @param {unknown} value - Raw value.
 * @return {string} Trimmed string.
 */
function asTrimmedString(value: unknown): string {
  return String(value ?? "").trim();
}

/**
 * Validates basic email format.
 * @param {string} value - Email string.
 * @return {boolean} True if valid.
 */
function isValidEmail(value: string): boolean {
  const email = value.trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/**
 * Converts unknown input to integer.
 * @param {unknown} value - Input value.
 * @return {number} Parsed integer or NaN.
 */
function toInt(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  const parsed = parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) ? parsed : NaN;
}

/**
 * Clamps trivia question count.
 * @param {unknown} value - Raw value.
 * @return {number} Clamped count.
 */
function clampCount(value: unknown): number {
  const parsed = toInt(value);
  const raw = Number.isFinite(parsed) ? parsed : 20;
  return Math.max(10, Math.min(50, raw));
}

/**
 * Cleans display name.
 * @param {unknown} value - Raw name.
 * @return {string} Cleaned name.
 */
function cleanDisplayName(value: unknown): string {
  const cleaned = String(value ?? "").trim();
  return cleaned || "Player";
}

/**
 * Escapes raw text for safe HTML interpolation.
 * @param {unknown} value - Raw value.
 * @return {string} Escaped string.
 */
function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Returns true when value is a non-null record.
 * @param {unknown} value - Raw value.
 * @return {boolean} True when record.
 */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

/**
 * Creates verification token.
 * @return {string} Token.
 */
function createVerificationToken(): string {
  return randomBytes(24).toString("hex");
}

/**
 * Hashes token.
 * @param {string} token - Raw token.
 * @return {string} Hash.
 */
function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/**
 * Builds future ISO timestamp.
 * @param {number} hours - Hours ahead.
 * @return {string} ISO string.
 */
function buildFutureIso(hours: number): string {
  return new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
}

/**
 * Returns true when an ISO timestamp is missing or expired.
 * @param {string | null | undefined} value - ISO timestamp.
 * @return {boolean} True when expired.
 */
function isExpiredIso(value: string | null | undefined): boolean {
  if (!value) return true;

  const ts = Date.parse(value);
  if (!Number.isFinite(ts)) return true;

  return ts <= Date.now();
}

/**
 * Builds a fallback display name for public event leads.
 * @param {string} displayName - Raw display name.
 * @param {string} email - Lead email.
 * @return {string} Safe display name.
 */
function normalizeEventLeadDisplayName(displayName: string, email: string): string {
  const cleaned = asTrimmedString(displayName).slice(0, 120);
  if (cleaned) return cleaned;

  const local = email.split("@")[0]?.trim();
  if (local) return local.slice(0, 120);

  return "Player";
}

/**
 * Returns fast model name.
 * @return {string} Model name.
 */
function getFastModel(): string {
  return "gemini-3-flash-preview";
}

/**
 * Returns deep model name.
 * @return {string} Model name.
 */
function getDeepModel(): string {
  return "gemini-3.1-pro-preview";
}

/**
 * Creates Gemini client.
 * @param {string} apiKey - API key.
 * @param {string} model - Model name.
 * @return {GenerativeModel} Model instance.
 */
function createGemini(apiKey: string, model: string): GenerativeModel {
  if (!ALLOWED_MODELS.has(model)) {
    throw new HttpsError("failed-precondition", "Invalid AI model.");
  }

  const gen = new GoogleGenerativeAI(apiKey);
  return gen.getGenerativeModel({ model });
}

/**
 * Cleans model output.
 * @param {string} text - Raw text.
 * @return {string} Clean text.
 */
function sanitizeModelText(text: string): string {
  return String(text ?? "")
    .replace(/^```[\s\S]*?\n?/i, "")
    .replace(/```$/i, "")
    .trim();
}

/**
 * Safely parses JSON, removing markdown fences if present.
 * @param {string} text - Raw model text.
 * @return {unknown} Parsed value.
 */
function safeJsonParse(text: string): unknown {
  const trimmed = String(text ?? "").trim();
  const unfenced = trimmed
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  return JSON.parse(unfenced);
}

/**
 * Validates and maps Gemini trivia response.
 * @param {unknown} parsed - Parsed JSON.
 * @param {number} count - Desired count.
 * @return {TriviaQuestionDTO[]} Questions.
 */
function validateAndMapQuestions(parsed: unknown, count: number): TriviaQuestionDTO[] {
  if (!isRecord(parsed) || !Array.isArray(parsed.questions)) {
    throw new HttpsError("internal", "Invalid response shape from AI.");
  }

  return parsed.questions.slice(0, count).map((question: unknown, index: number) => {
    const wire = isRecord(question) ? question as GeminiQuestionWire : {};
    const prompt = asTrimmedString(wire.prompt);
    const choicesRaw = Array.isArray(wire.choices) ? wire.choices.map(String) : [];
    const correctIndex = toInt(wire.correctIndex);

    if (!prompt || choicesRaw.length !== 4 || ![0, 1, 2, 3].includes(correctIndex)) {
      throw new HttpsError("internal", `Question error at index ${index}.`);
    }

    const c0 = asTrimmedString(choicesRaw[0]);
    const c1 = asTrimmedString(choicesRaw[1]);
    const c2 = asTrimmedString(choicesRaw[2]);
    const c3 = asTrimmedString(choicesRaw[3]);

    if (!c0 || !c1 || !c2 || !c3) {
      throw new HttpsError("internal", `Empty choice at index ${index}.`);
    }

    return {
      prompt,
      choices: [c0, c1, c2, c3],
      correctIndex: correctIndex as 0 | 1 | 2 | 3,
    };
  });
}

/**
 * Removes duplicate questions.
 * @param {TriviaQuestionDTO[]} questions - Raw questions.
 * @return {TriviaQuestionDTO[]} Deduped questions.
 */
function dedupeQuestions(questions: TriviaQuestionDTO[]): TriviaQuestionDTO[] {
  const seen = new Set<string>();
  const output: TriviaQuestionDTO[] = [];

  for (const question of questions) {
    const key =
      question.prompt.trim().toLowerCase() +
      "|" +
      question.choices.map((choice) => choice.trim().toLowerCase()).join("|") +
      "|" +
      question.correctIndex;

    if (seen.has(key)) continue;
    seen.add(key);
    output.push(question);
  }

  return output;
}

/**
 * Stable FNV-1a hash used for deterministic topic selection.
 * @param {string} value - Input string.
 * @return {number} Hash.
 */
function stableHash32(value: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

/**
 * Picks the daily mission topic from dayKey.
 * @param {string} dayKey - Day key.
 * @return {string} Topic.
 */
function pickDailyMissionTopic(dayKey: string): string {
  const index = stableHash32(dayKey) % DAILY_MISSION_TOPICS.length;
  return DAILY_MISSION_TOPICS[index];
}

/**
 * Normalizes YYYY-M-D day key.
 * @param {string} dayKey - Raw day key.
 * @return {string} Normalized day key.
 */
function normalizeDayKey(dayKey: string): string {
  const trimmed = asTrimmedString(dayKey);
  const match = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(trimmed);

  if (!match) {
    throw new HttpsError("invalid-argument", "Missing or invalid dayKey.");
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);

  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
    throw new HttpsError("invalid-argument", "Missing or invalid dayKey.");
  }

  if (month < 1 || month > 12 || day < 1 || day > 31) {
    throw new HttpsError("invalid-argument", "Missing or invalid dayKey.");
  }

  return `${year}-${month}-${day}`;
}

/**
 * Throws a structured username error.
 * @param {"invalid-argument" | "already-exists" | "resource-exhausted"} code - Error code.
 * @param {string} message - User-facing message.
 * @param {string} reason - Machine-readable reason.
  */
function usernameError(
  code: "invalid-argument" | "already-exists" | "resource-exhausted",
  message: string,
  reason: string
): never {
  throw new HttpsError(code, message, { reason });
}

    /**
     * Normalizes username.
     * @param {unknown} input - Raw username.
     * @return {{display: string, key: string, compact: string, moderationKey: string}} Normalized username object.
     */
    function normalizeUsername(input: unknown): {
  display: string;
  key: string;
  compact: string;
  moderationKey: string;
} {
  const raw = asTrimmedString(input);
  const cleaned = raw.replace(/\s+/g, "");

  if (cleaned.length < 3 || cleaned.length > 16) {
    usernameError("invalid-argument", "Codename must be 3–16 characters.", "length");
  }

  if (!/^[a-zA-Z0-9_]+$/.test(cleaned)) {
    usernameError(
      "invalid-argument",
      "Use only letters, numbers, and underscores.",
      "charset"
    );
  }

  if (/^_+|_+$/.test(cleaned)) {
    usernameError(
      "invalid-argument",
      "Codename cannot start or end with underscores.",
      "edge_underscore"
    );
  }

  if (/__/.test(cleaned)) {
    usernameError(
      "invalid-argument",
      "Codename cannot contain repeated underscores.",
      "double_underscore"
    );
  }

  const key = cleaned.toLowerCase();
  const compact = key.replace(/_/g, "");
  const moderationKey = compact
    .replace(/0/g, "o")
    .replace(/1/g, "i")
    .replace(/3/g, "e")
    .replace(/4/g, "a")
    .replace(/5/g, "s")
    .replace(/7/g, "t")
    .replace(/8/g, "b");

  return { display: cleaned, key, compact, moderationKey };
}

/**
 * Validates normalized username against policy.
 * @param {string} display - Display form.
 * @param {string} key - Lowercase key.
 * @param {string} compact - Underscore-stripped key.
 * @param {string} moderationKey - Moderation key.
 * @return {void}
 */
function validateUsernamePolicy(
  display: string,
  key: string,
  compact: string,
  moderationKey: string
): void {
  if (
    RESERVED_USERNAME_WORDS.has(key) ||
    RESERVED_USERNAME_WORDS.has(compact) ||
    RESERVED_USERNAME_WORDS.has(moderationKey)
  ) {
    usernameError("invalid-argument", "That codename is reserved. Try another.", "reserved");
  }

  for (const fragment of BANNED_USERNAME_FRAGMENTS) {
    if (
      key.includes(fragment) ||
      compact.includes(fragment) ||
      moderationKey.includes(fragment)
    ) {
      usernameError(
        "invalid-argument",
        "That codename is not allowed. Try another.",
        "restricted_word"
      );
    }
  }

  if (/(.)\1\1+/i.test(display)) {
    usernameError(
      "invalid-argument",
      "That codename looks too spammy. Try another.",
      "repeated_chars"
    );
  }

  const numericChars = display.replace(/[^0-9]/g, "").length;
  if (numericChars >= Math.ceil(display.length * 0.7)) {
    usernameError(
      "invalid-argument",
      "Use a more distinctive codename.",
      "too_numeric"
    );
  }

  const lower = display.toLowerCase();
  const obviousPatterns = ["1234", "12345", "123456", "abcd", "qwer", "asdf", "zxcv"];
  if (obviousPatterns.some((pattern) => lower.includes(pattern))) {
    usernameError(
      "invalid-argument",
      "That codename looks too generic. Try another.",
      "pattern"
    );
  }
}

/**
 * Enforces username claim rate limit.
 * @param {string} uid - User ID.
 * @return {Promise<void>} Completion promise.
 */
async function enforceUsernameClaimRateLimit(uid: string): Promise<void> {
  const rateRef = db.collection("usernameClaimRateLimits").doc(uid);
  const nowMs = Date.now();

  await db.runTransaction(async (tx: Transaction) => {
    const snap = await tx.get(rateRef);
    const data = (snap.data() ?? {}) as UsernameRateLimitDoc;

    const windowStartMs =
      typeof data.windowStartMs === "number" ? data.windowStartMs : nowMs;
    const lastAttemptMs =
      typeof data.lastAttemptMs === "number" ? data.lastAttemptMs : 0;
    const attemptCount =
      typeof data.attemptCount === "number" ? data.attemptCount : 0;

    if (nowMs - lastAttemptMs < 8_000) {
      usernameError(
        "resource-exhausted",
        "You’re trying too quickly. Wait a moment and try again.",
        "cooldown"
      );
    }

    const windowAge = nowMs - windowStartMs;
    const nextWindowStartMs = windowAge > 60 * 60 * 1000 ? nowMs : windowStartMs;
    const nextAttemptCount = windowAge > 60 * 60 * 1000 ? 1 : attemptCount + 1;

    if (nextAttemptCount > 8) {
      usernameError(
        "resource-exhausted",
        "Too many codename attempts. Please try again later.",
        "hourly_limit"
      );
    }

    tx.set(
      rateRef,
      {
        windowStartMs: nextWindowStartMs,
        attemptCount: nextAttemptCount,
        lastAttemptMs: nowMs,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

/**
 * Builds trivia prompt.
 * @param {string} topic - Topic.
 * @param {number} count - Count.
 * @return {string} Prompt.
 */
function buildTriviaPrompt(topic: string, count: number): string {
  return (
    "Return ONLY valid JSON.\n" +
    `Generate EXACTLY ${count} high-quality trivia questions about "${topic}".
` +
    "Schema:\n" +
    "{\n" +
    "  \"questions\": [\n" +
    "    {\n" +
    "      \"prompt\": \"...\",\n" +
    "      \"choices\": [\"A\", \"B\", \"C\", \"D\"],\n" +
    "      \"correctIndex\": 0\n" +
    "    }\n" +
    "  ]\n" +
    "}\n" +
    "Rules:\n" +
    "- Return exactly the requested number of questions\n" +
    "- choices must be exactly 4 strings\n" +
    "- correctIndex must be 0, 1, 2, or 3\n" +
    "- prompt must be non-empty\n" +
    "- no duplicate prompts\n" +
    "- no repeated choice sets\n" +
    "- keep questions clear, answerable, and varied in difficulty\n"
  );
}

/**
 * Returns the event verification base URL.
 * @return {string} Base URL.
 */
function getEventVerificationBaseUrl(): string {
  return "https://triviagoat.ca";
}

/**
 * Builds the public verification URL for an event access lead.
 * @param {string} eventId - Event ID.
 * @param {string} email - Lead email.
 * @param {string} token - Raw verification token.
 * @return {string} Absolute verification URL.
 */
function buildVerificationUrl(eventId: string, email: string, token: string): string {
  return (
    `${getEventVerificationBaseUrl()}/events/verify` +
    `?eventId=${encodeURIComponent(eventId)}` +
    `&email=${encodeURIComponent(email.trim().toLowerCase())}` +
    `&token=${encodeURIComponent(token)}`
  );
}

/**
 * Builds event verification email HTML.
 * @param {string} displayName - Recipient display name.
 * @param {string} eventTitle - Event title.
 * @param {string} verificationUrl - Verification URL.
 * @return {string} HTML body.
 */
function buildEventAccessVerificationEmailHtml(
  displayName: string,
  eventTitle: string,
  verificationUrl: string
): string {
  const safeName = escapeHtml(displayName || "there");
  const safeEventTitle = escapeHtml(eventTitle);
  const safeVerificationUrl = escapeHtml(verificationUrl);

  return `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #111827; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #000000; font-size: 24px; font-weight: 800; margin-bottom: 16px;">
        Confirm your Trivia GOAT launch access
      </h2>

      <p>Hi ${safeName},</p>

      <p>You requested early access for <strong>${safeEventTitle}</strong>.</p>

      <p>Please confirm your email to secure your place in the founding-player launch queue.</p>

      <div style="margin: 32px 0;">
        <a
          href="${safeVerificationUrl}"
          style="display: inline-block; padding: 14px 28px; background-color: #f97316; color: #000000; text-decoration: none; border-radius: 12px; font-weight: 800; font-size: 14px; text-transform: uppercase; letter-spacing: 0.05em;"
        >
          Verify Email
        </a>
      </div>

      <p style="font-size: 13px; color: #6b7280;">
        If the button doesn't work, copy and paste this link into your browser:
      </p>

      <p style="font-size: 13px; word-break: break-all; color: #f97316;">
        ${safeVerificationUrl}
      </p>

      <hr style="border: 0; border-top: 1px solid #e5e7eb; margin: 32px 0;" />

      <p style="font-size: 12px; color: #9ca3af;">
        This secure link expires in 24 hours. If you did not request this, you can safely ignore this email.
      </p>
    </div>
  `.trim();
}

/**
 * Sends a verification email for a public event access lead.
 * @param {string} toEmail - Recipient email.
 * @param {string} displayName - Recipient display name.
 * @param {string} eventTitle - Event title.
 * @param {string} verificationUrl - Verification link.
 * @return {Promise<void>} Completion promise.
 */
      async function sendEventLeadVerificationEmail(
        toEmail: string,
        displayName: string,
        eventTitle: string,
        verificationUrl: string
      ): Promise<void> {
        const resend = new Resend(RESEND_API_KEY.value());

        try {
          await resend.emails.send({
            from: RESEND_FROM_EMAIL.value(),
            to: [toEmail],
            subject: `Verify your access request for ${eventTitle}`,
            html: buildEventAccessVerificationEmailHtml(displayName, eventTitle, verificationUrl),
            text:
              "Confirm your Trivia GOAT launch access request.\n\n" +
              `You requested early access for ${eventTitle}.\n\n` +
              `Verify your email using this link:\n${verificationUrl}\n\n` +
              "This link expires in 24 hours.",
          });
        } catch (error) {
          logger.error("Email send failed", { error: String(error), toEmail, eventTitle });
          throw new HttpsError("internal", "Failed to send verification email.");
        }
      }

/**
 * Builds the event invitation response URL.
 * @param {string} eventId - Event ID.
 * @param {string} guestId - Guest document ID.
 * @param {string} email - Guest email.
 * @param {string} token - Raw invite token.
 * @return {string} Absolute invitation URL.
 */
function buildEventInvitationUrl(
  eventId: string,
  guestId: string,
  email: string,
  token: string
): string {
  return (
    `${getEventVerificationBaseUrl()}/events/invite` +
    `?eventId=${encodeURIComponent(eventId)}` +
    `&guestId=${encodeURIComponent(guestId)}` +
    `&email=${encodeURIComponent(email.trim().toLowerCase())}` +
    `&token=${encodeURIComponent(token)}`
  );
}

/**
 * Normalizes an event person role.
 * @param {unknown} value - Raw role.
 * @return {string} Safe role.
 */
function normalizeEventPersonRole(value: unknown): string {
  const cleaned = asTrimmedString(value).slice(0, 48);
  return cleaned || "Attendee";
}

/**
 * Builds event invitation email HTML.
 * @param {string} displayName - Recipient display name.
 * @param {string} eventTitle - Event title.
 * @param {string} role - Event role.
 * @param {string} organization - Organization.
 * @param {string} inviteUrl - Invite URL.
 * @return {string} HTML body.
 */
function buildEventInvitationEmailHtml(
  displayName: string,
  eventTitle: string,
  role: string,
  organization: string,
  inviteUrl: string
): string {
  const safeName = escapeHtml(displayName || "there");
  const safeEventTitle = escapeHtml(eventTitle);
  const safeRole = escapeHtml(role || "Guest");
  const safeOrganization = escapeHtml(organization);
  const safeInviteUrl = escapeHtml(inviteUrl);
  const organizationLine = safeOrganization ?
    `<p><strong>Organization:</strong> ${safeOrganization}</p>` :
    "";

  return `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #111827; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #000000; font-size: 24px; font-weight: 800; margin-bottom: 16px;">
        You're invited to ${safeEventTitle}
      </h2>

      <p>Hi ${safeName},</p>
      <p>You have been invited to <strong>${safeEventTitle}</strong>.</p>
      <p><strong>Role:</strong> ${safeRole}</p>
      ${organizationLine}

      <div style="margin: 32px 0;">
        <a
          href="${safeInviteUrl}"
          style="display: inline-block; padding: 14px 28px; background-color: #f97316; color: #000000; text-decoration: none; border-radius: 12px; font-weight: 800; font-size: 14px; text-transform: uppercase; letter-spacing: 0.05em;"
        >
          Respond to Invite
        </a>
      </div>

      <p style="font-size: 13px; color: #6b7280;">
        If the button doesn't work, copy and paste this link into your browser:
      </p>

      <p style="font-size: 13px; word-break: break-all; color: #f97316;">
        ${safeInviteUrl}
      </p>

      <hr style="border: 0; border-top: 1px solid #e5e7eb; margin: 32px 0;" />

      <p style="font-size: 12px; color: #9ca3af;">
        This secure invitation link expires in 14 days.
      </p>
    </div>
  `.trim();
}

/**
 * Sends an event invitation email.
 * @param {string} toEmail - Recipient email.
 * @param {string} displayName - Recipient display name.
 * @param {string} eventTitle - Event title.
 * @param {string} role - Event role.
 * @param {string} organization - Organization.
 * @param {string} inviteUrl - Invite URL.
 * @return {Promise<void>} Completion promise.
 */
async function sendEventInvitationEmail(
  toEmail: string,
  displayName: string,
  eventTitle: string,
  role: string,
  organization: string,
  inviteUrl: string
): Promise<void> {
  const resend = new Resend(RESEND_API_KEY.value());

  try {
      const emailResult = await resend.emails.send({
      from: RESEND_FROM_EMAIL.value(),
      to: [toEmail],
      subject: `You're invited to ${eventTitle}`,
      html: buildEventInvitationEmailHtml(
        displayName,
        eventTitle,
        role,
        organization,
        inviteUrl
      ),
      text:
        `You're invited to ${eventTitle}.\n\n` +
        `Role: ${role}\n` +
        (organization ? `Organization: ${organization}\n` : "") +
        `\nRespond to your invitation here:\n${inviteUrl}\n\n` +
        "This secure invitation link expires in 14 days.",
    });
logger.info("Event invitation email accepted by Resend", {
  toEmail,
  eventTitle,
  resendResult: emailResult,
});
  } catch (error) {
    logger.error("Event invitation email failed", {
      error: String(error),
      toEmail,
      eventTitle,
    });
    throw new HttpsError("internal", "Failed to send event invitation email.");
  }
}

/**
 * Builds deterministic event guest document ID from email.
 * @param {string} email - Email.
 * @return {string} Guest document ID.
 */
function makeEventGuestId(email: string): string {
  return `guest_${hashToken(email.trim().toLowerCase()).slice(0, 32)}`;
}

/**
 * Cleans public username fallback.
 * @param {unknown} value - Existing username-ish value.
 * @param {string} fallbackDisplayName - Fallback display name.
 * @param {string} uid - User ID.
 * @return {string} Safe username.
 */
function cleanUsername(value: unknown, fallbackDisplayName: string, uid: string): string {
  const raw = asTrimmedString(value).toLowerCase();
  if (raw) return raw;

  const fallback = fallbackDisplayName
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, "")
    .replace(/^_+|_+$/g, "")
    .slice(0, 16);

  if (fallback) return fallback;
  return `player_${uid.slice(0, 6)}`;
}

/**
 * Builds AI reply prompt.
 * @param {string} authorName - Author name.
 * @param {string} content - Post content.
 * @return {string} Prompt text.
 */
function buildAiReplyPrompt(authorName: string, content: string): string {
  return (
    "You are Trivia GOAT AI, the official AI voice inside a competitive knowledge platform.\n" +
    "You are sharp, engaging, confident, and slightly playful.\n\n" +
    "Write a strong follow-up comment to this user post.\n\n" +
    "Rules:\n" +
    "- 2 to 5 sentences\n" +
    "- Add insight, not fluff\n" +
    "- Push the idea forward\n" +
    "- Optional: end with a strong question\n" +
    "- No generic praise\n\n" +
    `Author: ${authorName}\n` +
    `Post:\n${content}\n\n` +
    "Reply:"
  );
}

/**
 * Derives AI reply topic.
 * @param {string} content - Source content.
 * @return {string} Topic label.
 */
function deriveAiReplyTopic(content: string): string {
  const lower = content.toLowerCase();
  if (lower.includes("rank")) return "rankings";
  if (lower.includes("learn")) return "learning";
  if (lower.includes("speed")) return "performance";
  return "general";
}

/**
 * Derives AI reply mode.
 * @param {string} content - Generated reply.
 * @return {string} Mode label.
 */
function deriveAiReplyMode(content: string): string {
  const lower = content.toLowerCase();
  if (lower.includes("?")) return "engagement_question";
  if (lower.includes("better") || lower.includes("harder")) return "competitive_frame";
  return "insight";
}

/**
 * Generates AI reply.
 * @param {string} authorName - Author name.
 * @param {string} content - Post content.
 * @return {Promise<AiReplyMeta>} Reply metadata.
 */
    async function generateAiReply(authorName: string, content: string): Promise<AiReplyMeta> {
      let model: GenerativeModel;
      let modelName = getDeepModel();

      try {
        model = createGemini(GEMINI_API_KEY.value(), modelName);
      } catch {
        modelName = getFastModel();
        model = createGemini(GEMINI_API_KEY.value(), modelName);
      }

      const result = await model.generateContent({
        contents: [{ role: "user", parts: [{ text: buildAiReplyPrompt(authorName, content) }] }],
        generationConfig: {
          temperature: 0.9,
          maxOutputTokens: 220,
        },
      });

      const reply = sanitizeModelText(result.response.text());
      if (!reply || reply.length < 40) {
        throw new HttpsError("internal", "AI reply too weak.");
      }

      return {
        reply,
        replyMode: deriveAiReplyMode(reply),
        replyTopic: deriveAiReplyTopic(content),
        model: modelName,
      };
    }

/**
 * Builds featured AI post prompt.
 * @param {string} topic - Topic.
 * @return {string} Prompt text.
 */
function buildFeaturedAiPostPrompt(topic: string): string {
  return (
    "Write a high-quality community post for a competitive trivia app.\n\n" +
    "Rules:\n" +
    "- 3 to 6 short paragraphs\n" +
    "- Strong hook\n" +
    "- Insightful + engaging\n" +
    "- Encourage discussion\n\n" +
    `Topic: ${topic}\n\n` +
    "Post:"
  );
}

/**
 * Generates featured AI post.
 * @param {string} topic - Topic.
 * @return {Promise<AiFeaturedPostMeta>} Post metadata.
 */
    async function generateFeaturedAiPost(topic: string): Promise<AiFeaturedPostMeta> {
      let model: GenerativeModel;
      let modelName = getDeepModel();

      try {
        model = createGemini(GEMINI_API_KEY.value(), modelName);
      } catch {
        modelName = getFastModel();
        model = createGemini(GEMINI_API_KEY.value(), modelName);
      }

      const result = await model.generateContent({
        contents: [{ role: "user", parts: [{ text: buildFeaturedAiPostPrompt(topic) }] }],
        generationConfig: {
          temperature: 0.95,
          maxOutputTokens: 700,
        },
      });

      const content = sanitizeModelText(result.response.text());
      if (!content || content.length < 120) {
        throw new HttpsError("internal", "AI post too weak.");
      }

      return {
        content,
        contentType: "featured_editorial",
        topic,
        model: modelName,
      };
    }

/**
 * Returns true when a launch post already exists.
 * @param {string} launchKind - Launch kind marker.
 * @return {Promise<boolean>} True when existing.
 */
async function hasExistingLaunchPost(launchKind: string): Promise<boolean> {
  const snap = await db
    .collection("posts")
    .where("launchKind", "==", launchKind)
    .where("status", "==", "approved")
    .limit(1)
    .get();

  return !snap.empty;
}

/**
 * Builds seeded community post content.
 * @return {string} Post content.
 */
function buildSeedCommunityPostContent(): string {
  return (
    "What actually separates a strong trivia player from everyone else?\n\n" +
    "Most people say knowledge. That matters, but under pressure it’s rarely the full story. " +
    "Pattern recognition, composure, timing, and the ability to stay clean under a ticking clock usually matter just as much.\n\n" +
    "Some players know a lot. Fewer can convert that into consistent wins.\n\n" +
    "What do you think matters most: raw knowledge, speed, focus, or clutch decision-making?"
  );
}

    /**
     * Checks blocked comment fragments.
     * @param {string} text - Input text.
     * @return {boolean} True when blocked.
     */
    function containsBlockedContent(text: string): boolean {
      if (!text) return false;
      const lower = text.toLowerCase();
      return BLOCKED_COMMENT_FRAGMENTS.some((fragment) => lower.includes(fragment));
    }

    /**
     * Returns true when a comment was created by a trusted seed/admin/system flow.
     * @param {PlatformCommentDoc} data - Comment document data.
     * @return {boolean} True when moderation can be bypassed.
     */
    function isTrustedSeedComment(data: PlatformCommentDoc): boolean {
      const moderationSource = asTrimmedString(data.moderationSource).toLowerCase();
      const source = asTrimmedString(data.source).toLowerCase();
      const authorUID = asTrimmedString(data.authorUID).toLowerCase();

      return (
        data.isAI === true ||
        data.seededByAdmin === true ||
        moderationSource === "admin_seed_launch" ||
        moderationSource === "system_seed" ||
        moderationSource === "seed_comment" ||
        source === "admin_seed_launch" ||
        source === "system_seed" ||
        source === "seed_comment" ||
        authorUID.startsWith("seed_user_") ||
        authorUID.startsWith("system_seed_")
      );
    }
        /**
         * Returns true when a comment is obviously safe and does not need AI parsing.
         * @param {string} content - Comment content.
         * @return {boolean} True when comment can be safely approved by heuristic.
         */
        function isSimpleSafeComment(content: string): boolean {
          const trimmed = content.trim();

          if (trimmed.length < 2 || trimmed.length > 160) return false;
          if (/https?:\/\//i.test(trimmed)) return false;
          if (/@everyone|@here/i.test(trimmed)) return false;
          if (/(.)\1{8,}/i.test(trimmed)) return false;

          return /^[a-zA-Z0-9\s?.!,'"-]+$/.test(trimmed);
        }

        /**
         * Returns true when AI GOAT should reply to this approved comment.
         * Uses deterministic hashing so retries make the same decision.
         * @param {string} postId - Parent post ID.
         * @param {string} commentId - Comment ID.
         * @param {number} ratePercent - Reply rate from 0 to 100.
         * @return {boolean} True when AI GOAT should reply.
         */
        function shouldAiGoatReply(
          postId: string,
          commentId: string,
          ratePercent = 70
        ): boolean {
          const clampedRate = Math.max(0, Math.min(100, ratePercent));
          const bucket = stableHash32(`ai-goat-reply:${postId}:${commentId}`) % 100;

          return bucket < clampedRate;
        }

        /**
         * Generates an AI Goat reply for an approved user comment.
         * @param {string} content - Original comment content.
         * @return {Promise<string>} AI-generated reply.
         */
        async function generateAiGoatReply(content: string): Promise<string> {
          const trimmed = content.trim();

          if (!trimmed) {
            return "The AI GOAT needs a little more to work with on that one 🧠";
          }

          try {
            const model = createGemini(GEMINI_API_KEY.value(), getFastModel());

            const prompt =
              "You are AI GOAT, the official voice inside a competitive trivia app.\n\n" +
              "Reply to the user comment in 1–2 short sentences.\n" +
              "Be smart, playful, positive, and conversational.\n" +
              "Do not mention moderation, policies, safety, or backend systems.\n" +
              "Do not be toxic. Do not roast the user.\n\n" +
              `User comment:\n${trimmed}\n\n` +
              "AI GOAT reply:";

            const result = await model.generateContent({
              contents: [{ role: "user", parts: [{ text: prompt }] }],
              generationConfig: {
                temperature: 0.75,
                maxOutputTokens: 90,
              },
            });

            const reply = sanitizeModelText(result.response.text()).slice(0, 500);

            if (!reply || reply.length < 2) {
              return "Interesting take — the AI GOAT is still thinking on that one 🧠";
            }

            return reply;
          } catch (error) {
            logger.warn("generateAiGoatReply fallback", {
              error: String(error),
            });

            return "Hmm… the AI GOAT needs a moment to think about that 🤔";
          }
        }

    /**
     * Moderates a community comment.
     * Uses deterministic blocking first, then AI JSON moderation.
     * AI uncertainty falls back to pending review, never rejection.
     * @param {string} authorName - Author name.
     * @param {string} content - Comment content.
     * @return {Promise<CommentModerationMeta>} Moderation result.
     */
    async function moderateCommunityComment(
      authorName: string,
      content: string
    ): Promise<CommentModerationMeta> {
      const trimmedContent = content.trim();
      const modelName = getFastModel();

      const looksHostile =
        /(you|u)\s+(are|r)?\s*(stupid|dumb|trash|garbage|pathetic|idiot|moron|worthless)/i.test(trimmedContent) ||
        /(you|u)\s+suck/i.test(trimmedContent) ||
        /kiss\s+my\s+ass/i.test(trimmedContent) ||
        /shut\s+up/i.test(trimmedContent);


        if (containsBlockedContent(trimmedContent) || looksHostile) {
        return {
          verdict: "rejected",
          reason: "policy_deterministic",
          model: modelName,
        };
      }

        if (isSimpleSafeComment(trimmedContent)) {
          return {
            verdict: "approved",
            reason: "safe_heuristic",
            model: "heuristic",
          };
        }
        const model = createGemini(GEMINI_API_KEY.value(), modelName);
        const prompt =
        "Return ONLY valid JSON. No markdown. No extra text.\n\n" +
        "{\"verdict\":\"APPROVED\"} OR {\"verdict\":\"REJECTED\",\"reason\":\"toxicity\"}\n\n" +
        "Reasons: toxicity, hate, sexual, violence, spam, other.\n\n" +
        "Reject comments that contain harassment, hate, sexual content, " +
        "self-harm encouragement, violent threats, doxxing, spam, scams, " +
        "illegal guidance, or graphic abuse.\n\n" +
        "Approve comments that are safe, respectful, and appropriate for a public trivia community.\n\n" +
        `Author: ${authorName}\n` +
        `Comment: ${trimmedContent}`;

      try {
        const result = await model.generateContent({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0,
            maxOutputTokens: 40,
            responseMimeType: "application/json",
          },
        });

        const raw = String(result.response.text() ?? "").trim();

        let parsed: { verdict?: string; reason?: string } | null = null;

        try {
          const temp = safeJsonParse(raw) as unknown;
          if (isRecord(temp)) {
            parsed = {
              verdict: typeof temp.verdict === "string" ? temp.verdict : undefined,
              reason: typeof temp.reason === "string" ? temp.reason : undefined,
            };
          }
        } catch {
          return {
            verdict: "pending",
            reason: "ai_parse_fallback",
            model: modelName,
          };
        }

        if (parsed?.verdict === "APPROVED") {
          return {
            verdict: "approved",
            reason: "safe",
            model: modelName,
          };
        }

        if (parsed?.verdict === "REJECTED") {
          return {
            verdict: "rejected",
            reason: parsed.reason ?? "policy_ai",
            model: modelName,
          };
        }

        return {
          verdict: "pending",
          reason: "ai_uncertain",
          model: modelName,
        };
      } catch (error) {
        logger.warn("moderateCommunityComment AI fallback", {
          error: String(error),
          authorName,
        });

        return {
          verdict: "pending",
          reason: "ai_unavailable",
          model: modelName,
        };
      }
    }
/**
 * Seeds launch-ready community content if needed.
 * @return {Promise<SeedCommunityLaunchResult>} Seed result.
 */
async function seedCommunityLaunchPosts(): Promise<SeedCommunityLaunchResult> {
  const result: SeedCommunityLaunchResult = {
    skippedAI: false,
    skippedCommunity: false,
  };

  const now = new Date();

  if (await hasExistingLaunchPost("community_launch_ai")) {
    result.skippedAI = true;
  } else {
    const generated = await generateFeaturedAiPost("competition");
    const aiRef = db.collection("posts").doc();

    await aiRef.set({
      content: generated.content,
      contentType: generated.contentType,
      topic: generated.topic,
      authorUID: "system_ai",
      authorName: "Trivia GOAT AI",
      status: "approved",
      createdAt: now,
      approvedAt: now,
      likesCount: 0,
      commentsCount: 0,
      isAI: true,
      model: generated.model,
      aiPostKind: "featured",
      launchKind: "community_launch_ai",
    });

    result.aiPostId = aiRef.id;
  }

  if (await hasExistingLaunchPost("community_launch_player")) {
    result.skippedCommunity = true;
  } else {
    const communityRef = db.collection("posts").doc();
    await communityRef.set({
      content: buildSeedCommunityPostContent(),
      contentType: "discussion_seed",
      topic: "competition",
      authorUID: "system_seed_player",
      authorName: "Arena Control",
      status: "approved",
      createdAt: now,
      approvedAt: now,
      likesCount: 0,
      commentsCount: 0,
      isAI: false,
      launchKind: "community_launch_player",
    });

    result.communityPostId = communityRef.id;
  }

  return result;
}

/**
 * Reads basic user identity fields.
 * @param {string} uid - User ID.
  */
async function readUserIdentity(uid: string): Promise<{ email: string; displayName: string }> {
  const userSnap = await db.collection("users").doc(uid).get();
  const data = userSnap.exists ? (userSnap.data() as UserDoc | undefined) : undefined;

  return {
    email: asTrimmedString(data?.email),
    displayName: cleanDisplayName(data?.displayName),
  };
}

/**
 * Ensures request is from owner.
 * @param {CallableRequest} request - Callable request.
 * @return {void}
 */
function assertOwner(request: CallableRequest): void {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Auth required.");
  }

  if (request.auth.uid !== OWNER_UID) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
}

    /**
     * Returns true when the role should be treated as admin-capable.
     * @param {string} value - Raw role value.
     * @return {boolean} True when elevated.
     */
    function isAdminLikeRole(value: string): boolean {
      const normalized = value.trim().toLowerCase();
      return normalized === "admin" || normalized === "owner" || normalized === "super_admin";
    }

    /**
     * Requires the caller to be owner or admin.
     * @param {CallableRequest} request - Callable request.
     * @return {Promise<AdminActor>} Actor identity.
     */
    async function assertAdminOrOwner(request: CallableRequest): Promise<AdminActor> {
      const uid = request.auth?.uid;
      if (!uid) {
        throw new HttpsError("unauthenticated", "Auth required.");
      }

      if (uid === OWNER_UID) {
        return { uid, role: "owner" };
      }

      const userSnap = await db.collection("users").doc(uid).get();
      const userData = userSnap.exists ? (userSnap.data() as UserDoc | undefined) : undefined;

      const role = asTrimmedString(userData?.role);
      const accountType = asTrimmedString(userData?.accountType);

      if (isAdminLikeRole(role) || isAdminLikeRole(accountType)) {
        return { uid, role: role || accountType || "admin" };
      }

      throw new HttpsError("permission-denied", "Admin access required.");
    }

    /**
     * Normalizes a feature-flag key.
     * @param {unknown} value - Raw key.
     * @return {string} Normalized key.
     */
    function normalizeFeatureFlagKey(value: unknown): string {
      const key = asTrimmedString(value).toLowerCase();

      if (!key) {
        throw new HttpsError("invalid-argument", "Feature flag key is required.");
      }

      if (!/^[a-z0-9_]+$/.test(key)) {
        throw new HttpsError("invalid-argument", `Invalid feature flag key: ${key}`);
      }

      return key;
    }

    /**
     * Requires a strict boolean.
     * @param {unknown} value - Raw value.
     * @param {string} fieldName - Field name.
     * @return {boolean} Parsed boolean.
     */
    function requireBoolean(value: unknown, fieldName: string): boolean {
      if (typeof value !== "boolean") {
        throw new HttpsError("invalid-argument", `${fieldName} must be a boolean.`);
      }
      return value;
    }

    /**
     * Reads platform config, falling back to defaults.
     * @return {Promise<PlatformConfigDoc>} Config doc.
     */
    async function readPlatformConfig(): Promise<PlatformConfigDoc> {
      const ref = db.collection(ADMIN_CONFIG_COLLECTION).doc(PLATFORM_CONFIG_DOC);
      const snap = await ref.get();

      if (!snap.exists) {
        return {
          featureFlags: { ...DEFAULT_FEATURE_FLAGS },
          version: 1,
        };
      }

      const data = snap.data() as PlatformConfigDoc | undefined;

      return {
        featureFlags: {
          ...DEFAULT_FEATURE_FLAGS,
          ...(data?.featureFlags ?? {}),
        },
        updatedAt: data?.updatedAt,
        updatedBy: data?.updatedBy,
        version: typeof data?.version === "number" ? data.version : 1,
      };
    }

    /**
     * Writes an admin audit log.
     * @param {AdminAuditLogDoc} payload - Audit payload.
     * @return {Promise<void>} Completion promise.
     */
    async function writeAdminAuditLog(payload: AdminAuditLogDoc): Promise<void> {
      await db.collection(ADMIN_AUDIT_LOGS_COLLECTION).add({
        ...payload,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

/**
 * Rebuilds public platform stats.
 * @return {Promise<void>} Completion promise.
 */
async function rebuildPublicPlatformStats(): Promise<void> {
    const [usersSnap, postsSnap, approvedPostsSnap, eventsSnap, globalBattlesSnap] =
      await Promise.all([
        db.collection("users").get(),
        db.collection("posts").get(),
        db.collection("posts").where("status", "==", "approved").get(),
        db.collection("events").get(),
        db.collection("globalBattles").get(),
      ]);

  const stats: PublicStatsDoc = {
    totalUsers: usersSnap.size,
    totalPosts: postsSnap.size,
    totalApprovedPosts: approvedPostsSnap.size,
    totalEvents: eventsSnap.size,
    totalBattlesPlayed: globalBattlesSnap.size,
    updatedAt: FieldValue.serverTimestamp(),
  };

  await db.collection("stats").doc("platform").set(stats, { merge: true });
}

/**
 * Rebuilds public leaderboard snapshots.
 * @param {number} limitCount - Limit count.
 * @return {Promise<void>} Completion promise.
 */
async function rebuildPublicLeaderboardSnapshots(limitCount = 100): Promise<void> {
  const usersSnap = await db
    .collection("users")
    .orderBy("xp", "desc")
    .limit(limitCount)
    .get();

  const batch = db.batch();
  const existingSnap = await WEBSITE_LEADERBOARD_SNAPSHOTS_COLLECTION.get();
  existingSnap.docs.forEach((docSnap) => {
    batch.delete(docSnap.ref);
  });

  let rank = 1;

  usersSnap.docs.forEach((docSnap) => {
    const data = docSnap.data() as UserLeaderboardSourceDoc;
    const uid = docSnap.id;
    const displayName = cleanDisplayName(data.displayName);
    const username = cleanUsername(data.displayNameKey, displayName, uid);
    const score = typeof data.xp === "number" ? data.xp : 0;
    const wins = typeof data.matchesWon === "number" ? data.matchesWon : 0;

    const row: PublicLeaderboardSnapshotDoc = {
      uid,
      displayName,
      username,
      score,
      wins,
      streak: 0,
      rank,
      updatedAt: FieldValue.serverTimestamp(),
    };

    batch.set(WEBSITE_LEADERBOARD_SNAPSHOTS_COLLECTION.doc(uid), row, { merge: true });
    rank += 1;
  });

  await batch.commit();
}

/**
 * Backfills legacy user fields.
 * @return {Promise<object>} Result summary.
 */
async function backfillLegacyUsers(): Promise<object> {
  const usersSnap = await db.collection("users").get();

  let batch = db.batch();
  let batchOps = 0;
  let updated = 0;

  for (const docSnap of usersSnap.docs) {
    const data = (docSnap.data() ?? {}) as Record<string, unknown>;
    const patch: Record<string, unknown> = {};

    const displayName = asTrimmedString(data.displayName);
    const displayNameKey = asTrimmedString(data.displayNameKey).toLowerCase();
    const username = asTrimmedString(data.username).toLowerCase();
    const role = asTrimmedString(data.role);
    const accountType = asTrimmedString(data.accountType);
    const hasCreatedAt = "createdAt" in data;
    const hasIsPublic = typeof data.isPublic === "boolean";

    if (!hasCreatedAt) patch.createdAt = FieldValue.serverTimestamp();
    if (!hasIsPublic) patch.isPublic = true;
    if (!role) patch.role = "user";
    if (!accountType) patch.accountType = "user";
    if (!username && displayNameKey) patch.username = displayNameKey;
    if (!displayName && displayNameKey) patch.displayName = displayNameKey;

    if (Object.keys(patch).length === 0) continue;

    patch.updatedAt = FieldValue.serverTimestamp();
    batch.set(docSnap.ref, patch, { merge: true });
    batchOps += 1;
    updated += 1;

    if (batchOps >= 400) {
      await batch.commit();
      batch = db.batch();
      batchOps = 0;
    }
  }

  if (batchOps > 0) {
    await batch.commit();
  }

  return {
    scanned: usersSnap.size,
    updated,
  };
}

/**
 * Parses boolean-like input.
 * @param {unknown} value - Raw value.
 * @return {boolean | undefined} Parsed boolean or undefined.
 */
function parseOptionalBoolean(value: unknown): boolean | undefined {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (normalized === "true") return true;
    if (normalized === "false") return false;
  }
  return undefined;
}

/**
 * Slugifies value.
 * @param {string} value - Raw value.
 * @return {string} Slug.
 */
function slugify(value: string): string {
  return value
    .toLowerCase()
    .trim()
    .replace(/['"]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

/**
 * Requires ISO date string.
 * @param {unknown} value - Raw input.
 * @param {string} fieldName - Field name.
 * @return {string} ISO string.
 */
function requireIsoDateString(value: unknown, fieldName: string): string {
  const raw = asTrimmedString(value);
  if (!raw) {
    throw new HttpsError("invalid-argument", `Missing ${fieldName}.`);
  }

  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError("invalid-argument", `Invalid ${fieldName}.`);
  }

  return parsed.toISOString();
}

/**
 * Requires event title.
 * @param {unknown} value - Raw title.
 * @return {string} Clean title.
 */
function requireEventTitle(value: unknown): string {
  const title = asTrimmedString(value);
  if (!title) {
    throw new HttpsError("invalid-argument", "Missing event title.");
  }
  if (title.length > 120) {
    throw new HttpsError("invalid-argument", "Event title is too long.");
  }
  return title;
}

/**
 * Requires event summary.
 * @param {unknown} value - Raw summary.
 * @return {string} Clean summary.
 */
function requireEventSummary(value: unknown): string {
  const summary = asTrimmedString(value);
  if (!summary) {
    throw new HttpsError("invalid-argument", "Missing event summary.");
  }
  if (summary.length > 1000) {
    throw new HttpsError("invalid-argument", "Event summary is too long.");
  }
  return summary;
}

/**
 * Requires event hero line.
 * @param {unknown} value - Raw hero line.
 * @return {string} Clean hero line.
 */
function requireEventHeroLine(value: unknown): string {
  const heroLine = asTrimmedString(value);
  if (!heroLine) {
    throw new HttpsError("invalid-argument", "Missing event hero line.");
  }
  if (heroLine.length > 180) {
    throw new HttpsError("invalid-argument", "Event hero line is too long.");
  }
  return heroLine;
}

/**
 * Parses event capacity.
 * @param {unknown} value - Raw capacity.
 * @return {number} Capacity.
 */
function parseEventCapacity(value: unknown): number {
  const parsed = toInt(value);
  if (!Number.isFinite(parsed) || parsed < 1) {
    throw new HttpsError("invalid-argument", "Invalid event capacity.");
  }
  return Math.min(50000, parsed);
}

/**
 * Parses event status.
 * @param {unknown} value - Raw status.
 * @return {"draft" | "scheduled" | "live" | "ended" | "cancelled"} Status.
 */
function parseEventStatus(
  value: unknown
): "draft" | "scheduled" | "live" | "ended" | "cancelled" {
  const normalized = asTrimmedString(value).toLowerCase();
  if (
    normalized === "draft" ||
    normalized === "scheduled" ||
    normalized === "live" ||
    normalized === "ended" ||
    normalized === "cancelled"
  ) {
    return normalized;
  }
  throw new HttpsError("invalid-argument", "Invalid event status.");
}
      /**
       * Parses and validates an event approval status value.
       * @param {unknown} value - Raw approval status value.
       * @return {string} Valid event approval status.
       */
      function parseEventApprovalStatus(value: unknown): string {
        const approvalStatus = asTrimmedString(value);

        switch (approvalStatus) {
          case "draft":
          case "submitted":
          case "approved":
          case "rejected":
          case "archived":
            return approvalStatus;
          default:
            throw new HttpsError(
              "invalid-argument",
              "Invalid event approval status."
            );
        }
      }
      /**
 * Parses event visibility.
 * @param {unknown} value - Raw visibility.
 * @return {"public" | "invite_only"} Visibility.
 */
    function parseEventVisibility(value: unknown): "public" | "invite_only" {
      const normalized = asTrimmedString(value).toLowerCase();

      if (normalized === "public") {
        return "public";
      }

      if (
        normalized === "invite_only" ||
        normalized === "invite-only" ||
        normalized === "inviteonly" ||
        normalized === "private"
      ) {
        return "invite_only";
      }

      throw new HttpsError(
        "invalid-argument",
        `Invalid event visibility: ${String(value)}`
      );
    }
/**
 * Parses event category.
 * @param {unknown} value - Raw category.
 * @return {"launch" | "tournament" | "university" | "sponsored" | "community"} Category.
 */
function parseEventCategory(
  value: unknown
): "launch" | "tournament" | "university" | "sponsored" | "community" {
  const normalized = asTrimmedString(value).toLowerCase();
  if (
    normalized === "launch" ||
    normalized === "tournament" ||
    normalized === "university" ||
    normalized === "sponsored" ||
    normalized === "community"
  ) {
    return normalized;
  }
  throw new HttpsError("invalid-argument", "Invalid event category.");
}

/**
 * Parses event location type.
 * @param {unknown} value - Raw location type.
 * @return {"virtual" | "hybrid" | "in_person"} Location type.
 */
function parseEventLocationType(
  value: unknown
): "virtual" | "hybrid" | "in_person" {
  const normalized = asTrimmedString(value).toLowerCase();
  if (
    normalized === "virtual" ||
    normalized === "hybrid" ||
    normalized === "in_person"
  ) {
    return normalized;
  }
  throw new HttpsError("invalid-argument", "Invalid event locationType.");
}

/* -------------------------------------------------------------------------- */
/* TRIVIA / GAMEPLAY                                                          */
/* -------------------------------------------------------------------------- */

/**
 * Generates a trivia pack.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Generation result.
 */
export const generateTriviaPack = onCall(
  { secrets: [GEMINI_API_KEY], timeoutSeconds: 60, memory: "256MiB" },
  async (request: CallableRequest): Promise<object> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }

    await enforceRateLimit(
      `generateTriviaPack:${uid}`,
      12,
      60 * 1000,
      "Too many trivia generation requests. Please wait a moment and try again."
    );

    const data = (request.data ?? {}) as Record<string, unknown>;
    const topic = asTrimmedString(data.topic) || "General Knowledge";
    const count = clampCount(data.count);

    const model = createGemini(GEMINI_API_KEY.value(), getFastModel());
    const result = await model.generateContent({
      contents: [{ role: "user", parts: [{ text: buildTriviaPrompt(topic, count) }] }],
      generationConfig: { responseMimeType: "application/json" },
    });

      const modelName = getFastModel();

      let parsed: unknown;

      try {
        parsed = safeJsonParse(result.response.text());
      } catch {
        logger.error("Trivia JSON parse failed", {
          raw: result.response.text(),
        });

        throw new HttpsError("internal", "Trivia generation failed. Please retry.");
      }
      const questions = dedupeQuestions(
        validateAndMapQuestions(parsed, count)
      );

      return {
        questions,
        topic,
        generatedAt: new Date().toISOString(),
        model: modelName,
      };
  }
);

/**
 * Processes a trivia answer and awards rewards for correct answers.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Success payload.
 */
export const submitAnswer = onCall(
  async (request: CallableRequest): Promise<object> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const isCorrect = Boolean(data.isCorrect);

    if (isCorrect) {
      await db.collection("users").doc(uid).set(
        {
          iq: FieldValue.increment(10),
          gold: FieldValue.increment(5),
          updatedAt: FieldValue.serverTimestamp(),
        } as UserDoc,
        { merge: true }
      );
    }

    return { success: true };
  }
);
        /**
         * Shared Daily Mission pack generation result payload.
         */
        type DailyMissionPackResult = {
          questions: unknown[];
          topic: string;
          dayKey: string;
          generatedAt: string;
          cached: boolean;
          model: string;
        };

        /**
         * Ensures the shared Daily Mission pack exists and is ready.
         * Reuses an existing ready pack, waits briefly for active generation,
         * or generates a new pack when needed.
         * @param {string} dayKey - Normalized mission day key.
         * @return {Promise<DailyMissionPackResult>} Ready mission pack payload.
         */
        async function ensureDailyMissionPackReady(
          dayKey: string
        ): Promise<DailyMissionPackResult> {
          const count = 15;
          const minimumAcceptableCount = 10;
          const modelName = getFastModel();
          const docRef = db.collection("dailyMissionPacks").doc(dayKey);

          const existingSnap = await docRef.get();

          if (existingSnap.exists) {
            const existing = existingSnap.data() as DailyMissionPackDoc;

            if (
              existing.status === "ready" &&
              Array.isArray(existing.questions) &&
              existing.questions.length >= minimumAcceptableCount
            ) {
              return {
                questions: existing.questions,
                topic:
                  existing.topic ||
                  existing.lockedTopic ||
                  pickDailyMissionTopic(dayKey),
                dayKey: existing.dayKey || dayKey,
                generatedAt: existing.generatedAt || new Date().toISOString(),
                cached: true,
                model: existing.model || modelName,
              };
            }
          }

          const lockedTopic = pickDailyMissionTopic(dayKey);

          const lockResult = await db.runTransaction(async (tx: Transaction) => {
            const snap = await tx.get(docRef);

            if (snap.exists) {
              const existing = snap.data() as DailyMissionPackDoc;

              if (
                existing.status === "ready" &&
                Array.isArray(existing.questions) &&
                existing.questions.length >= minimumAcceptableCount
              ) {
                return { mode: "ready" as const, data: existing };
              }

              if (existing.status === "generating") {
                return { mode: "wait" as const };
              }
            }

            tx.set(
              docRef,
              {
                status: "generating",
                dayKey,
                topic: lockedTopic,
                lockedTopic,
                questions: [],
                generatedAt: "",
                model: "",
                createdAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true }
            );

            return { mode: "generate" as const };
          });

          if (lockResult.mode === "ready") {
            const existing = lockResult.data;

            return {
              questions: existing.questions,
              topic: existing.topic || existing.lockedTopic || lockedTopic,
              dayKey: existing.dayKey || dayKey,
              generatedAt: existing.generatedAt || new Date().toISOString(),
              cached: true,
              model: existing.model || modelName,
            };
          }

          if (lockResult.mode === "wait") {
            for (let i = 0; i < 10; i++) {
              await new Promise((resolve) => setTimeout(resolve, 350));

              const waitSnap = await docRef.get();

              if (!waitSnap.exists) continue;

              const waiting = waitSnap.data() as DailyMissionPackDoc;

              if (
                waiting.status === "ready" &&
                Array.isArray(waiting.questions) &&
                waiting.questions.length >= minimumAcceptableCount
              ) {
                return {
                  questions: waiting.questions,
                  topic: waiting.topic || waiting.lockedTopic || lockedTopic,
                  dayKey: waiting.dayKey || dayKey,
                  generatedAt: waiting.generatedAt || new Date().toISOString(),
                  cached: true,
                  model: waiting.model || modelName,
                };
              }
            }

            throw new HttpsError(
              "resource-exhausted",
              "Daily mission pack is generating. Try again."
            );
          }

          try {
            const model = createGemini(GEMINI_API_KEY.value(), modelName);

            const result = await model.generateContent({
              contents: [
                {
                  role: "user",
                  parts: [{ text: buildTriviaPrompt(lockedTopic, count) }],
                },
              ],
              generationConfig: {
                responseMimeType: "application/json",
              },
            });

            const parsed = safeJsonParse(result.response.text());
            const questions = dedupeQuestions(validateAndMapQuestions(parsed, count));

            if (questions.length < minimumAcceptableCount) {
              throw new HttpsError(
                "resource-exhausted",
                `Insufficient daily mission trivia generated for "${lockedTopic}".`
              );
            }

            const generatedAt = new Date().toISOString();

            await docRef.set(
              {
                status: "ready",
                dayKey,
                topic: lockedTopic,
                lockedTopic,
                questions,
                generatedAt,
                model: modelName,
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true }
            );

            return {
              questions,
              topic: lockedTopic,
              dayKey,
              generatedAt,
              cached: false,
              model: modelName,
            };
          } catch (error) {
            await docRef.set(
              {
                status: "failed",
                questions: [],
                topic: lockedTopic,
                lockedTopic,
                error: error instanceof Error ?
                  error.message :
                  "Unknown daily mission generation failure.",
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true }
            );

            if (error instanceof HttpsError) {
              throw error;
            }

            throw new HttpsError("internal", "Failed to generate daily mission pack.");
          }
        }

        /**
         * Returns the shared Daily Mission pack for the requested day key.
         * @param {CallableRequest} request - Callable request.
         * @return {Promise<object>} Mission pack payload.
         */
        export const generateDailyMissionPack = onCall(
          {
            secrets: [GEMINI_API_KEY],
            timeoutSeconds: 60,
            memory: "256MiB",
          },
          async (request: CallableRequest): Promise<object> => {
            const uid = request.auth?.uid;

            if (!uid) {
              throw new HttpsError("unauthenticated", "Auth required.");
            }

            await enforceRateLimit(
              `generateDailyMissionPack:${uid}`,
              20,
              60 * 1000,
              "Too many daily mission requests. Please wait a moment and try again."
            );

            const data = (request.data ?? {}) as Record<string, unknown>;
            const dayKey = normalizeDayKey(asTrimmedString(data.dayKey));

            return ensureDailyMissionPackReady(dayKey);
          }
        );

        /**
         * Warms the Daily Mission pack shortly after midnight so users
         * receive an instant cached pack instead of triggering cold generation.
         * @return {Promise<void>} Completion promise.
         */
        export const scheduledDailyMissionPackWarm = onSchedule(
          {
            schedule: "1 0 * * *",
            timeZone: "America/Toronto",
            secrets: [GEMINI_API_KEY],
            timeoutSeconds: 60,
            memory: "256MiB",
          },
          async (): Promise<void> => {
            const now = new Date();

            const formatter = new Intl.DateTimeFormat("en-CA", {
              timeZone: "America/Toronto",
              year: "numeric",
              month: "2-digit",
              day: "2-digit",
            });

            const parts = formatter.formatToParts(now);

            const year = parts.find((part) => part.type === "year")?.value;
            const month = parts.find((part) => part.type === "month")?.value;
            const day = parts.find((part) => part.type === "day")?.value;

            if (!year || !month || !day) {
              throw new Error("Could not resolve scheduled daily mission day key.");
            }

            const dayKey = `${year}-${month}-${day}`;

            const result = await ensureDailyMissionPackReady(dayKey);

            console.log("✅ Scheduled daily mission pack warm complete", {
              dayKey,
              topic: result.topic,
              cached: result.cached,
              count: result.questions.length,
              model: result.model,
            });
          }
        );

            /**
             * Claims a unique codename for the authenticated user.
             * @param {CallableRequest} req - Callable request.
             * @return {Promise<object>} Claim result.
             */
        export const claimUsername = onCall(
          async (req: CallableRequest): Promise<object> => {
            const uid = req.auth?.uid;
            if (!uid) {
              throw new HttpsError("unauthenticated", "Auth required.");
            }

            await enforceRateLimit(
              `claimUsername:${uid}`,
              6,
              60 * 60 * 1000,
              "Too many codename attempts. Please try again later."
            );

            const data = (req.data ?? {}) as Record<string, unknown>;
            const normalized = normalizeUsername(data.username);
            const display = normalized.display;
            const key = normalized.key;
            const compact = normalized.compact;
            const moderationKey = normalized.moderationKey;

            validateUsernamePolicy(display, key, compact, moderationKey);
            await enforceUsernameClaimRateLimit(uid);

            const usernameRef = db.collection("usernames").doc(key);
            const userRef = db.collection("users").doc(uid);

            const isPlaceholderCodename = (value: string): boolean => {
              const cleaned = value.trim().toLowerCase().replace(/\s+/g, "");
              return (
                cleaned === "" ||
                cleaned === "pilot" ||
                cleaned === "player" ||
                cleaned === "newpilot" ||
                /^newpilot\d{0,8}$/.test(cleaned)
              );
            };

            const claimed = await db.runTransaction(async (tx: Transaction) => {
              const usernameSnap = await tx.get(usernameRef);
              const userSnap = await tx.get(userRef);

              const usernameData = usernameSnap.data() as
                | { ownerId?: string; displayName?: string }
                | undefined;

              const userData = userSnap.data() as UserDoc | undefined;

              const currentUserKey = asTrimmedString(userData?.displayNameKey).toLowerCase();
              const currentDisplayName = asTrimmedString(userData?.displayName);

              const hasRealExistingCodename =
                !!currentUserKey &&
                currentUserKey !== key &&
                !isPlaceholderCodename(currentUserKey) &&
                !isPlaceholderCodename(currentDisplayName);

              if (
                usernameSnap.exists &&
                usernameData?.ownerId &&
                usernameData.ownerId !== uid
              ) {
                usernameError("already-exists", "That codename is already taken.", "taken");
              }

              if (hasRealExistingCodename) {
                usernameError(
                  "invalid-argument",
                  "Codename changes are not allowed.",
                  "rename_blocked"
                );
              }

              const usernamePatch: Record<string, unknown> = {
                ownerId: uid,
                displayName: display,
                displayNameKey: key,
                updatedAt: FieldValue.serverTimestamp(),
              };

              if (!usernameSnap.exists) {
                usernamePatch.createdAt = FieldValue.serverTimestamp();
              }

              tx.set(usernameRef, usernamePatch, { merge: true });

              tx.set(
                userRef,
                {
                  displayName: display,
                  displayNameKey: key,
                  updatedAt: FieldValue.serverTimestamp(),
                } as UserDoc,
                { merge: true }
              );

              return {
                username: display,
                key,
                moderation: {
                  accepted: true,
                  reason: "ok",
                },
              };
            });

            return claimed;
          }
        );

/**
 * Registers an FCM token for the authenticated user.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Success payload.
 */
export const registerFcmToken = onCall(
  async (request: CallableRequest): Promise<object> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const token = asTrimmedString(data.token);

    if (!token) {
      throw new HttpsError("invalid-argument", "Missing token.");
    }

    await db.collection("users").doc(uid).set(
      {
        fcmToken: token,
        updatedAt: FieldValue.serverTimestamp(),
      } as UserDoc,
      { merge: true }
    );

    return { success: true };
  }
);

/* -------------------------------------------------------------------------- */
/* COMMUNITY / SOCIAL                                                         */
/* -------------------------------------------------------------------------- */

      /**
       * Creates a community post for the authenticated user.
       * Server-side validation + rate limiting + moderation-safe intake.
       * @param {CallableRequest} request - Callable request.
       * @return {Promise<SubmitPostResult>} Post creation result.
       */
      export const submitPost = onCall(
        { secrets: [GEMINI_API_KEY] },
        async (request: CallableRequest): Promise<SubmitPostResult> => {
          const uid = request.auth?.uid;
          if (!uid) {
            throw new HttpsError("unauthenticated", "Auth required.");
          }

          await enforceRateLimit(
            `submitPost:${uid}`,
            1,
            10 * 1000,
            "Please wait a few seconds before submitting another post."
          );

          const data = (request.data ?? {}) as Record<string, unknown>;
          const rawContent = asTrimmedString(data.content);
          const authorName = asTrimmedString(data.authorName) || "Player";

          const content = rawContent
            .replace(new RegExp("\\0", "g"), "")
            .replace(/[^\x20-\x7E\n\r]/g, "")
            .replace(/\s+/g, " ")
            .trim()
            .slice(0, 500);

          if (!content) {
            throw new HttpsError("invalid-argument", "Missing content.");
          }

          if (content.length < 8) {
            throw new HttpsError(
              "invalid-argument",
              "Post must be at least 8 characters."
            );
          }

          if (content.length > 500) {
            throw new HttpsError(
              "invalid-argument",
              "Posts must be 500 characters or less."
            );
          }

          if (containsBlockedContent(content)) {
            throw new HttpsError(
              "invalid-argument",
              "This post contains blocked language and cannot be submitted."
            );
          }

            const moderation = await moderatePostContent(authorName, content);
            const approved = moderation.verdict === "approved";
            const rejected = moderation.verdict === "rejected";
            const nextStatus = approved ? "approved" : rejected ? "rejected" : "pending";

            const postRef = db.collection("posts").doc();

            await postRef.set({
              content,
              authorUID: uid,
              authorName,
              status: nextStatus,
              moderationStatus: nextStatus,
              moderationSource: rejected ? "ai" : approved ? "ai" : "ai_fallback",
              moderationReason: moderation.reason,
              moderationModel: moderation.model,
              moderatedAt: FieldValue.serverTimestamp(),
              approvedAt: approved ? FieldValue.serverTimestamp() : null,
              isAI: false,
              commentsCount: 0,
              aiReplyGenerated: false,
              createdAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            } as PlatformPostDoc & {
              moderationStatus: string;
              moderationSource: string;
              moderationReason: string;
              moderationModel: string;
              moderatedAt: FieldValue;
              approvedAt: FieldValue | null;
            });

            return {
              success: true,
              postId: postRef.id,
              status: approved ? "approved" : "pending",
            };
        }
      );

      /**
       * Creates a community comment for an existing post.
       * Server-side validation + rate limiting + moderation-safe intake.
       * @param {CallableRequest} request - Callable request.
       * @return {Promise<SubmitCommentResult>} Comment creation result.
       */
      export const submitComment = onCall(
        async (request: CallableRequest): Promise<SubmitCommentResult> => {
          const uid = request.auth?.uid;
          if (!uid) {
            throw new HttpsError("unauthenticated", "Auth required.");
          }

          await enforceRateLimit(
            `submitComment:${uid}`,
            2,
            10 * 1000,
            "Please wait a few seconds before submitting another comment."
          );

          const data = (request.data ?? {}) as Record<string, unknown>;
          const postId = asTrimmedString(data.postId);
          const rawContent = asTrimmedString(data.content);
          const authorName = asTrimmedString(data.authorName) || "Player";

          if (!postId) {
            throw new HttpsError("invalid-argument", "Missing postId.");
          }

          const content = rawContent
            .replace(new RegExp("\\0", "g"), "")
            .replace(/[^\x20-\x7E\n\r]/g, "")
            .replace(/\s+/g, " ")
            .trim()
            .slice(0, 500);

          if (!content) {
            throw new HttpsError("invalid-argument", "Missing content.");
          }

          if (content.length < 2) {
            throw new HttpsError(
              "invalid-argument",
              "Comment must be at least 2 characters."
            );
          }

          if (content.length > 500) {
            throw new HttpsError(
              "invalid-argument",
              "Comments must be 500 characters or less."
            );
          }

          if (containsBlockedContent(content)) {
            throw new HttpsError(
              "invalid-argument",
              "This comment contains blocked language and cannot be submitted."
            );
          }

          const postRef = db.collection("posts").doc(postId);
          const commentRef = postRef.collection("comments").doc();

          await db.runTransaction(async (tx: Transaction) => {
            const postSnap = await tx.get(postRef);
            if (!postSnap.exists) {
              throw new HttpsError("not-found", "Post not found.");
            }

            const postData = postSnap.data() as PlatformPostDoc | undefined;
            const postStatus = asTrimmedString(postData?.status).toLowerCase();

            if (postStatus !== "approved") {
              throw new HttpsError(
                "failed-precondition",
                "Comments can only be added to approved posts."
              );
            }

            tx.set(commentRef, {
              postID: postId,
              content,
              authorUID: uid,
              authorName,
              isAI: false,
              status: "pending",
              moderationStatus: "pending",
              moderationSource: "callable_intake",
              createdAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            });

            tx.set(
              postRef,
              {
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
          });

          return {
            success: true,
            commentId: commentRef.id,
            postId,
            status: "pending",
          };
        }
      );

      /**
       * Moderates newly created player posts.
       * @param {FirestoreEvent<DocumentSnapshot | undefined>} event - Firestore create event.
       * @return {Promise<void>} Completion promise.
       */
      export const moderatePostOnCreate = onDocumentCreated(
        {
          document: "posts/{postId}",
          secrets: [GEMINI_API_KEY],
        },
        async (event: FirestoreEvent<DocumentSnapshot | undefined>): Promise<void> => {
          const snapshot = event.data;
          if (!snapshot?.exists) return;

          const data = snapshot.data() as PlatformPostDoc | undefined;
          if (!data) return;

          const postId = String(event.params.postId || "");
          if (!postId) return;

          if (data.isAI === true) return;

          const status = String(data.status || "").toLowerCase();
          if (status !== "pending") return;

          const content = String(data.content || "").trim();
          const authorName = String(data.authorName || "Player");

          if (!content) {
            await snapshot.ref.set(
              {
                status: "rejected",
                moderationStatus: "rejected",
                moderationReason: "empty",
                moderationSource: "ai",
                moderatedAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
            return;
          }

          try {
            const moderation = await moderatePostContent(authorName, content);

            if (moderation.verdict === "pending") {
              await snapshot.ref.set(
                {
                  status: "pending",
                  moderationStatus: "pending",
                  moderationSource: "ai_fallback",
                  moderationReason: moderation.reason,
                  moderationModel: moderation.model,
                  moderatedAt: FieldValue.serverTimestamp(),
                  updatedAt: FieldValue.serverTimestamp(),
                },
                { merge: true }
              );
              return;
            }

            await snapshot.ref.set(
              {
                status: "rejected",
                moderationStatus: "rejected",
                moderationSource: "ai",
                moderationReason: moderation.reason,
                moderationModel: moderation.model,
                moderatedAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
          } catch (error) {
            logger.error("moderatePostOnCreate failed", {
              error: String(error),
            });
          }
        }
      );

/**
 * Publishes a featured AI post.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Publish result.
 */
export const publishFeaturedAiPost = onCall(
  { secrets: [GEMINI_API_KEY], timeoutSeconds: 60 },
  async (request: CallableRequest): Promise<object> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const topic = asTrimmedString(data.topic) || "competition";
    const generated = await generateFeaturedAiPost(topic);
    const ref = db.collection("posts").doc();
    const now = new Date();

    await ref.set({
      content: generated.content,
      contentType: generated.contentType,
      topic: generated.topic,
      authorUID: "system_ai",
      authorName: "Trivia GOAT AI",
      status: "approved",
      createdAt: now,
      approvedAt: now,
      likesCount: 0,
      commentsCount: 0,
      isAI: true,
      model: generated.model,
      aiPostKind: "featured",
    });

    return {
      success: true,
      postId: ref.id,
      topic: generated.topic,
      contentType: generated.contentType,
      model: generated.model,
    };
  }
);

/**
 * Returns a short mascot-style response for iOS assistant moments.
 * @param {CallableRequest} req - Callable request.
 * @return {Promise<object>} Mascot response.
 */
export const getMascotResponse = onCall(
  { secrets: [GEMINI_API_KEY] },
  async (req: CallableRequest): Promise<object> => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }

    const data = (req.data ?? {}) as Record<string, unknown>;
    const input = asTrimmedString(data.input).slice(0, 500);

    if (!input) {
      throw new HttpsError("invalid-argument", "Missing input.");
    }

    const model = createGemini(GEMINI_API_KEY.value(), getFastModel());

    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [
            {
              text:
                "You are the Trivia GOAT mascot. Respond briefly, confidently, and playfully.\n\n" +
                input,
            },
          ],
        },
      ],
    });

    return {
      reply: sanitizeModelText(result.response.text()),
    };
  }
);

/**
 * Seeds launch-ready community content.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Seed result.
 */
export const seedCommunityLaunchContent = onCall(
  { secrets: [GEMINI_API_KEY], timeoutSeconds: 60 },
  async (request: CallableRequest): Promise<object> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }

    const seeded = await seedCommunityLaunchPosts();
    return {
      success: true,
      ...seeded,
    };
  }
);

/**
 * Seeds launch-ready AI community content once.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Seed result.
 */
export const seedCommunity = onCall(
  { secrets: [GEMINI_API_KEY] },
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);

    const exists = await hasExistingLaunchPost("launch_seed_featured");
    if (exists) {
      return { success: true, skipped: true };
    }

    const content = await generateFeaturedAiPost("competition");
    await db.collection("posts").add({
      content: content.content,
      authorUID: "system_ai",
      authorName: "Trivia GOAT AI",
      status: "approved",
      launchKind: "launch_seed_featured",
      createdAt: FieldValue.serverTimestamp(),
    });

    return { success: true, skipped: false };
  }
);
            /**
             * Moderates newly created player comments.
             * @param {FirestoreEvent<DocumentSnapshot | undefined>} event - Firestore create event.
             * @return {Promise<void>} Completion promise.
             */
            export const moderateCommentOnCreate = onDocumentCreated(
              {
                document: "posts/{postId}/comments/{commentId}",
                secrets: [GEMINI_API_KEY],
              },
              async (event: FirestoreEvent<DocumentSnapshot | undefined>): Promise<void> => {
                const snapshot = event.data;
                if (!snapshot?.exists) return;

                const data = snapshot.data() as PlatformCommentDoc | undefined;
                if (!data) return;

                const postId = asTrimmedString(event.params.postId);
                const commentId = asTrimmedString(event.params.commentId);

                if (!postId || !commentId) return;

                if (isTrustedSeedComment(data)) {
                  await snapshot.ref.set(
                    {
                      status: "approved",
                      approvedAt: FieldValue.serverTimestamp(),
                      moderatedAt: FieldValue.serverTimestamp(),
                      moderationStatus: "approved",
                      moderationSource: data.moderationSource ?? "trusted_seed",
                      moderationReason: "trusted_seed_content",
                      updatedAt: FieldValue.serverTimestamp(),
                    },
                    { merge: true }
                  );
                  return;
                }

                if (asTrimmedString(data.status).toLowerCase() !== "pending") return;

                const content = asTrimmedString(data.content);
                const authorName = asTrimmedString(data.authorName) || "Player";
                const commentRef = db
                  .collection("posts")
                  .doc(postId)
                  .collection("comments")
                  .doc(commentId);

                if (!content) {
                  await commentRef.set(
                    {
                      status: "rejected",
                      moderatedAt: FieldValue.serverTimestamp(),
                      moderationStatus: "rejected",
                      moderationSource: "ai",
                      moderationReason: "empty",
                      updatedAt: FieldValue.serverTimestamp(),
                    },
                    { merge: true }
                  );
                  return;
                }

                try {
                  const moderation = await moderateCommunityComment(authorName, content);

                  if (moderation.verdict === "approved") {
                    await commentRef.set(
                      {
                        status: "approved",
                        approvedAt: FieldValue.serverTimestamp(),
                        moderatedAt: FieldValue.serverTimestamp(),
                        moderationStatus: "approved",
                        moderationSource: "ai",
                        moderationReason: moderation.reason,
                        moderationModel: moderation.model,
                        updatedAt: FieldValue.serverTimestamp(),
                      },
                      { merge: true }
                    );

                    try {
                      const latestData = snapshot.data() as PlatformCommentDoc | undefined;

                      if (latestData) {
                        const isTrusted = isTrustedSeedComment(latestData);
                        const isAiAuthor = asTrimmedString(latestData.authorUID).toLowerCase() === "ai_goat";
                        const commentContent = asTrimmedString(latestData.content);

                        if (!isTrusted && !isAiAuthor && commentContent && shouldAiGoatReply(postId, commentId)) {
                          const existingReplySnap = await commentRef
                            .collection("replies")
                            .where("authorUID", "==", "ai_goat")
                            .limit(1)
                            .get();

                          if (existingReplySnap.empty) {
                            const reply = await generateAiGoatReply(commentContent);

                            await commentRef.collection("replies").add({
                              content: reply,
                              authorName: "AI GOAT",
                              authorUID: "ai_goat",
                              createdAt: FieldValue.serverTimestamp(),
                              updatedAt: FieldValue.serverTimestamp(),
                              status: "approved",
                              moderationStatus: "approved",
                              moderationSource: "system_ai_goat_reply",
                              moderationReason: "auto_reply_to_approved_comment",
                              isAI: true,
                              source: "ai_goat_auto_reply",
                            });
                          }
                        }
                      }
                    } catch (error) {
                      logger.warn("AI Goat reply write skipped", {
                        error: String(error),
                        postId,
                        commentId,
                      });
                    }

                    return;
                  }

                  await commentRef.set(
                    {
                      status: "pending",
                      moderatedAt: FieldValue.serverTimestamp(),
                      moderationStatus: "pending",
                      moderationSource: "ai_fallback",
                      moderationReason: moderation.reason,
                      moderationModel: moderation.model,
                      updatedAt: FieldValue.serverTimestamp(),
                    },
                    { merge: true }
                  );
                } catch (error) {
                  logger.error("moderateCommentOnCreate failed", {
                    error: String(error),
                  });

                  await commentRef.set(
                    {
                      status: "pending",
                      moderatedAt: FieldValue.serverTimestamp(),
                      moderationStatus: "pending",
                      moderationSource: "ai_error",
                      moderationReason: "ai_unavailable",
                      updatedAt: FieldValue.serverTimestamp(),
                    },
                    { merge: true }
                  );
                }
              }
            );
/**
 * Automatically generates one AI reply when a post becomes approved.
 * @param {FirestoreEvent<Change<DocumentSnapshot> | undefined>} event - Firestore update event.
 * @return {Promise<void>} Completion promise.
 */
export const autoAIReplyOnApprovedPost = onDocumentUpdated(
  {
    document: "posts/{postId}",
    secrets: [GEMINI_API_KEY],
  },
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined>): Promise<void> => {
    const before = event.data?.before?.data() as PlatformPostDoc | undefined;
    const after = event.data?.after?.data() as PlatformPostDoc | undefined;

    if (!after) return;

    const justApproved = after.status === "approved" && (!before || before.status !== "approved");
    if (!justApproved) return;
    if (after.isAI === true) return;
    if (after.aiReplyGenerated === true) return;

    const postId = asTrimmedString(event.params.postId);
    if (!postId) return;

    const content = asTrimmedString(after.content);
    const authorName = asTrimmedString(after.authorName) || "Player";
    if (!content) return;

    const ai = await generateAiReply(authorName, content);
    const postRef = db.collection("posts").doc(postId);

    await postRef.collection("comments").add({
      postID: postId,
      content: ai.reply,
      authorUID: "system_ai",
      authorName: "Trivia GOAT AI",
      isAI: true,
      status: "approved",
      createdAt: FieldValue.serverTimestamp(),
      approvedAt: FieldValue.serverTimestamp(),
      replyMode: ai.replyMode,
      replyTopic: ai.replyTopic,
      model: ai.model,
    });

    await postRef.set(
      {
        commentsCount: FieldValue.increment(1),
        aiReplyGenerated: true,
        aiReplyGeneratedAt: FieldValue.serverTimestamp(),
        aiReplyMode: ai.replyMode,
        aiReplyTopic: ai.replyTopic,
        aiReplyModel: ai.model,
      },
      { merge: true }
    );
  }
);

/**
 * Keeps post comment counts aligned with moderation status transitions.
 * @param {FirestoreEvent<Change<DocumentSnapshot> | undefined>} event - Firestore update event.
 * @return {Promise<void>} Completion promise.
 */
      export const syncPostCommentCountOnCommentStatusUpdate = onDocumentUpdated(
  "posts/{postId}/comments/{commentId}",
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined>): Promise<void> => {
    const before = event.data?.before?.data() as PlatformCommentDoc | undefined;
    const after = event.data?.after?.data() as PlatformCommentDoc | undefined;

    if (!before || !after) return;

    const postId = asTrimmedString(event.params.postId);
    if (!postId) return;

    const beforeStatus = asTrimmedString(before.status).toLowerCase();
    const afterStatus = asTrimmedString(after.status).toLowerCase();

    if (!beforeStatus || !afterStatus) return;
    if (beforeStatus === afterStatus) return;

    const ref = db.collection("posts").doc(postId);

    if (beforeStatus === "pending" && afterStatus === "approved") {
      await ref.set({ commentsCount: FieldValue.increment(1) }, { merge: true });
      return;
    }

    if (beforeStatus === "approved" && afterStatus === "rejected") {
      await ref.set({ commentsCount: FieldValue.increment(-1) }, { merge: true });
    }
  }
);

/* -------------------------------------------------------------------------- */
/* EVENTS                                                                     */
/* -------------------------------------------------------------------------- */

/**
 * Creates a launch event draft.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Creation result.
 */
export const createLaunchEventDraft = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const title = requireEventTitle(
      data.title ?? "Trivia GOAT Launch Night — App + Platform Debut"
    );
    const heroLine = asTrimmedString(data.heroLine) || "The official debut of Trivia GOAT.";
    const summary = requireEventSummary(
      data.summary ??
        "Join the first live reveal of the Trivia GOAT platform and mobile app. " +
          "We’ll open the first public wave, introduce the competitive roadmap, " +
          "spotlight community features, and invite founding players into the launch cohort."
    );
    const startsAt = requireIsoDateString(data.startsAt, "startsAt");
    const endsAt = requireIsoDateString(data.endsAt, "endsAt");
    const rsvpOpensAt = asTrimmedString(data.rsvpOpensAt) ?
      requireIsoDateString(data.rsvpOpensAt, "rsvpOpensAt") :
      startsAt;
    const rsvpClosesAt = asTrimmedString(data.rsvpClosesAt) ?
      requireIsoDateString(data.rsvpClosesAt, "rsvpClosesAt") :
      startsAt;
    const capacity = parseEventCapacity(data.capacity ?? 500);
    const slug = slugify(asTrimmedString(data.slug) || title);
    const uid = String(request.auth?.uid ?? OWNER_UID);

    const eventRef = db.collection("events").doc();
    await eventRef.set({
      title,
      slug,
      heroLine,
      summary,
      status: "draft",
      approvalStatus: "draft",
      visibility: "invite_only",
      category: "launch",
      locationType: "hybrid",
      startsAt,
      endsAt,
      rsvpOpensAt,
      rsvpClosesAt,
      waitlistOpensAt: rsvpOpensAt,
      waitlistClosesAt: endsAt,
      capacity,
      waitlistEnabled: true,
      inviteOnly: true,
      published: false,
      featured: true,
      launchWaveLabel: "Founding Players",
      createdBy: uid,
      updatedBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    } as PlatformEventDoc);

    return {
      success: true,
      eventId: eventRef.id,
      slug,
      status: "draft",
    };
  }
);

/**
 * Creates a general event draft.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Creation result.
 */
export const createEventDraft = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const uid = String(request.auth?.uid ?? OWNER_UID);

    const title = requireEventTitle(data.title);
    const heroLine = requireEventHeroLine(data.heroLine);
    const summary = requireEventSummary(data.summary);
    const startsAt = requireIsoDateString(data.startsAt, "startsAt");
    const endsAt = requireIsoDateString(data.endsAt, "endsAt");
    const rsvpOpensAt = asTrimmedString(data.rsvpOpensAt) ?
      requireIsoDateString(data.rsvpOpensAt, "rsvpOpensAt") :
      startsAt;
    const rsvpClosesAt = asTrimmedString(data.rsvpClosesAt) ?
      requireIsoDateString(data.rsvpClosesAt, "rsvpClosesAt") :
      endsAt;
    const waitlistOpensAt = asTrimmedString(data.waitlistOpensAt) ?
      requireIsoDateString(data.waitlistOpensAt, "waitlistOpensAt") :
      rsvpOpensAt;
    const waitlistClosesAt = asTrimmedString(data.waitlistClosesAt) ?
      requireIsoDateString(data.waitlistClosesAt, "waitlistClosesAt") :
      endsAt;
    const category = parseEventCategory(data.category ?? "community");
    const locationType = parseEventLocationType(data.locationType ?? "virtual");
    const visibility = parseEventVisibility(data.visibility ?? "public");
    const capacity = parseEventCapacity(data.capacity ?? 100);
    const waitlistEnabled = parseOptionalBoolean(data.waitlistEnabled) ?? true;
            const inviteOnly =
              parseOptionalBoolean(data.inviteOnly) ??
              visibility === "invite_only";
    const published = false;
    const featured = parseOptionalBoolean(data.featured) ?? false;
    const slug = slugify(asTrimmedString(data.slug) || title);
    const eventRef = db.collection("events").doc();
    await eventRef.set({
      title,
      slug,
      heroLine,
      summary,
        status: "draft",
        approvalStatus: "draft",
        visibility,
      category,
      locationType,
      startsAt,
      endsAt,
      rsvpOpensAt,
      rsvpClosesAt,
      waitlistOpensAt,
      waitlistClosesAt,
      capacity,
      waitlistEnabled,
      inviteOnly,
      published,
      featured,
      launchWaveLabel: asTrimmedString(data.launchWaveLabel).slice(0, 80),
      createdBy: uid,
      updatedBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    } as PlatformEventDoc);

    return {
      success: true,
      eventId: eventRef.id,
      slug,
      status: "draft",
    };
  }
);

/**
 * Updates event schedule.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Update result.
 */
export const updateEventSchedule = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);
            const data = (request.data ?? {}) as Record<string, unknown>;
            const eventId = asTrimmedString(data.eventId);

            if (!eventId) {
              throw new HttpsError("invalid-argument", "Missing eventId.");
            }

            const patch: Record<string, unknown> = {
              updatedAt: FieldValue.serverTimestamp(),
              updatedBy: request.auth?.uid ?? OWNER_UID,
            };

    if ("startsAt" in data) patch.startsAt = requireIsoDateString(data.startsAt, "startsAt");
    if ("endsAt" in data) patch.endsAt = requireIsoDateString(data.endsAt, "endsAt");
    if ("rsvpOpensAt" in data) patch.rsvpOpensAt = requireIsoDateString(data.rsvpOpensAt, "rsvpOpensAt");
    if ("rsvpClosesAt" in data) patch.rsvpClosesAt = requireIsoDateString(data.rsvpClosesAt, "rsvpClosesAt");
    if ("waitlistOpensAt" in data) patch.waitlistOpensAt = requireIsoDateString(data.waitlistOpensAt, "waitlistOpensAt");
    if ("waitlistClosesAt" in data) patch.waitlistClosesAt = requireIsoDateString(data.waitlistClosesAt, "waitlistClosesAt");
    if ("capacity" in data) patch.capacity = parseEventCapacity(data.capacity);

    await db.collection("events").doc(eventId).set(patch, { merge: true });
    return { success: true, eventId };
  }
);

/**
 * Updates event details.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Update result.
 */
export const updateEventDetails = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);
    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }

    const eventRef = db.collection("events").doc(eventId);
    const eventSnap = await eventRef.get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found.");
    }

    const patch: Record<string, unknown> = {
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: request.auth?.uid ?? OWNER_UID,
    };

    if ("title" in data) {
      const title = requireEventTitle(data.title);
      patch.title = title;
      if (!("slug" in data)) patch.slug = slugify(title);
    }
    if ("slug" in data) patch.slug = slugify(asTrimmedString(data.slug) || asTrimmedString(data.title));
    if ("heroLine" in data) patch.heroLine = requireEventHeroLine(data.heroLine);
    if ("summary" in data) patch.summary = requireEventSummary(data.summary);
            if ("status" in data) {
              patch.status = parseEventStatus(data.status);
            }

            if ("approvalStatus" in data) {
              patch.approvalStatus = parseEventApprovalStatus(data.approvalStatus);
            }

            if ("visibility" in data) {
              patch.visibility = parseEventVisibility(data.visibility);
            }
    if ("category" in data) patch.category = parseEventCategory(data.category);
    if ("locationType" in data) patch.locationType = parseEventLocationType(data.locationType);
    if ("startsAt" in data) patch.startsAt = requireIsoDateString(data.startsAt, "startsAt");
    if ("endsAt" in data) patch.endsAt = requireIsoDateString(data.endsAt, "endsAt");
    if ("rsvpOpensAt" in data) patch.rsvpOpensAt = requireIsoDateString(data.rsvpOpensAt, "rsvpOpensAt");
    if ("rsvpClosesAt" in data) patch.rsvpClosesAt = requireIsoDateString(data.rsvpClosesAt, "rsvpClosesAt");
    if ("waitlistOpensAt" in data) patch.waitlistOpensAt = requireIsoDateString(data.waitlistOpensAt, "waitlistOpensAt");
    if ("waitlistClosesAt" in data) patch.waitlistClosesAt = requireIsoDateString(data.waitlistClosesAt, "waitlistClosesAt");
    if ("capacity" in data) patch.capacity = parseEventCapacity(data.capacity);
    if ("waitlistEnabled" in data) {
      const parsed = parseOptionalBoolean(data.waitlistEnabled);
      if (typeof parsed !== "boolean") {
        throw new HttpsError("invalid-argument", "Invalid waitlistEnabled.");
      }
      patch.waitlistEnabled = parsed;
    }
    if ("inviteOnly" in data) {
      const parsed = parseOptionalBoolean(data.inviteOnly);
      if (typeof parsed !== "boolean") {
        throw new HttpsError("invalid-argument", "Invalid inviteOnly.");
      }
      patch.inviteOnly = parsed;
    }
    if ("published" in data) {
      const parsed = parseOptionalBoolean(data.published);
      if (typeof parsed !== "boolean") {
        throw new HttpsError("invalid-argument", "Invalid published.");
      }
      patch.published = parsed;
    }
    if ("featured" in data) {
      const parsed = parseOptionalBoolean(data.featured);
      if (typeof parsed !== "boolean") {
        throw new HttpsError("invalid-argument", "Invalid featured.");
      }
      patch.featured = parsed;
    }
    if ("launchWaveLabel" in data) patch.launchWaveLabel = asTrimmedString(data.launchWaveLabel).slice(0, 80);

    await eventRef.set(patch, { merge: true });
    return { success: true, eventId };
  }
);

/**
 * Toggles event live state.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Toggle result.
 */
export const toggleEventLive = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);
    const makeLive = Boolean(data.live);

    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }

    await db.collection("events").doc(eventId).set(
      {
        status: makeLive ? "live" : "scheduled",
        published: true,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: request.auth?.uid ?? OWNER_UID,
      },
      { merge: true }
    );

    return { success: true, eventId, live: makeLive };
  }
);

/**
 * Deletes an event when safe.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Delete result.
 */
export const deleteEvent = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);

    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }

    const eventRef = db.collection("events").doc(eventId);
    const eventSnap = await eventRef.get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found.");
    }

    const [accessRequestsSnap, waitlistSnap, invitesSnap, accessLeadsSnap] = await Promise.all([
      eventRef.collection("accessRequests").limit(1).get(),
      eventRef.collection("waitlist").limit(1).get(),
      eventRef.collection("invites").limit(1).get(),
      eventRef.collection("accessLeads").limit(1).get(),
    ]);

    const hasChildren =
      !accessRequestsSnap.empty ||
      !waitlistSnap.empty ||
      !invitesSnap.empty ||
      !accessLeadsSnap.empty;

    if (hasChildren) {
      throw new HttpsError(
        "failed-precondition",
        "Event cannot be deleted while it still has leads, requests, waitlist entries, or invites."
      );
    }

    await eventRef.delete();
    return { success: true, eventId, deleted: true };
  }
);

/**
 * Requests access to an event.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Request result.
 */
export const requestEventAccess = onCall(
  async (request: CallableRequest): Promise<object> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);
    const note = asTrimmedString(data.note).slice(0, 240);

    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }

    const identity = await readUserIdentity(uid);
    const requestRef = db.collection("events").doc(eventId).collection("accessRequests").doc(uid);
    const inviteRef = db.collection("events").doc(eventId).collection("invites").doc(uid);

    const [requestSnap, inviteSnap] = await Promise.all([requestRef.get(), inviteRef.get()]);

    if (inviteSnap.exists) {
      return { success: true, eventId, status: "already_invited" };
    }

    if (requestSnap.exists) {
      return { success: true, eventId, status: "already_requested" };
    }

    await requestRef.set(
      {
        uid,
        email: identity.email,
        displayName: identity.displayName,
        eventId,
        status: "requested",
        note,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        reviewedAt: null,
        reviewedBy: null,
      } as PlatformEventAccessRequestDoc,
      { merge: true }
    );

    return { success: true, eventId, status: "requested" };
  }
);

/**
 * Joins an event waitlist.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Waitlist result.
 */
            export const joinEventWaitlist = onCall(
              async (request: CallableRequest): Promise<object> => {
                const uid = request.auth?.uid;
                if (!uid) {
                  throw new HttpsError("unauthenticated", "Auth required.");
                }

                const data = (request.data ?? {}) as Record<string, unknown>;
                const eventId = asTrimmedString(data.eventId);
                if (!eventId) {
                  throw new HttpsError("invalid-argument", "Missing eventId.");
                }

                logger.info("joinEventWaitlist debug", {
                  eventId,
                  databaseId: "b4-v2-default-clone",
                  uid,
                });

                const identity = await readUserIdentity(uid);

                const eventRef = db.collection("events").doc(eventId);
                const waitlistRef = eventRef.collection("waitlist").doc(uid);
                const inviteRef = eventRef.collection("invites").doc(uid);
                const rsvpRef = eventRef.collection("rsvps").doc(uid);

                return db.runTransaction(async (tx: Transaction) => {
                  const [eventSnap, waitlistSnap, inviteSnap, rsvpSnap] = await Promise.all([
                    tx.get(eventRef),
                    tx.get(waitlistRef),
                    tx.get(inviteRef),
                    tx.get(rsvpRef),
                  ]);

                  if (!eventSnap.exists) {
                    throw new HttpsError("not-found", "Event not found.");
                  }

                  if (rsvpSnap.exists) {
                    throw new HttpsError("already-exists", "You are already registered for this event.");
                  }

                  if (inviteSnap.exists) {
                    throw new HttpsError("already-exists", "You already have an invite record for this event.");
                  }

                  if (waitlistSnap.exists) {
                    return { success: true, eventId, status: "already_waitlisted" };
                  }

                  const eventData = eventSnap.data() as PlatformEventDoc;
                  const status = asTrimmedString(eventData.status).toLowerCase();

                  if (status === "live") {
                    throw new HttpsError("failed-precondition", "Event is already live.");
                  }

                  if (status === "ended" || status === "cancelled") {
                    throw new HttpsError("failed-precondition", "Event is no longer accepting waitlist entries.");
                  }

                  if (!eventData.waitlistEnabled) {
                    throw new HttpsError("failed-precondition", "Waitlist is not enabled for this event.");
                  }

                  tx.set(
                    waitlistRef,
                    {
                      uid,
                      email: identity.email,
                      displayName: identity.displayName,
                      status: "waiting",
                      eventId,
                      createdAt: FieldValue.serverTimestamp(),
                      updatedAt: FieldValue.serverTimestamp(),
                      promotedAt: null,
                      promotedBy: null,
                    } as PlatformEventWaitlistDoc,
                    { merge: true }
                  );

                  tx.update(eventRef, {
                    waitlistCount: FieldValue.increment(1),
                    updatedAt: FieldValue.serverTimestamp(),
                  });

                  return { success: true, eventId, status: "waiting" };
                });
              }
            );

            export const submitEventRSVP = onCall(
              async (request: CallableRequest): Promise<object> => {
                const uid = request.auth?.uid;
                if (!uid) {
                  throw new HttpsError("unauthenticated", "Auth required.");
                }

                const data = (request.data ?? {}) as Record<string, unknown>;
                const eventId = asTrimmedString(data.eventId);

                if (!eventId) {
                  throw new HttpsError("invalid-argument", "Missing eventId.");
                }

                logger.info("submitEventRSVP debug", {
                  eventId,
                  databaseId: "b4-v2-default-clone",
                  uid,
                });

                const identity = await readUserIdentity(uid);

                const eventRef = db.collection("events").doc(eventId);
                const rsvpRef = eventRef.collection("rsvps").doc(uid);
                const waitlistRef = eventRef.collection("waitlist").doc(uid);
                const inviteRef = eventRef.collection("invites").doc(uid);

                return db.runTransaction(async (tx: Transaction) => {
                  const [eventSnap, rsvpSnap, waitlistSnap, inviteSnap] = await Promise.all([
                    tx.get(eventRef),
                    tx.get(rsvpRef),
                    tx.get(waitlistRef),
                    tx.get(inviteRef),
                  ]);

                  if (!eventSnap.exists) {
                    logger.warn("submitEventRSVP event missing", {
                      eventId,
                      databaseId: "b4-v2-default-clone",
                      eventPath: eventRef.path,
                      uid,
                    });

                    throw new HttpsError("not-found", "Event not found.");
                  }

                  if (rsvpSnap.exists) {
                    return {
                      success: true,
                      eventId,
                      status: "already_confirmed",
                    };
                  }

                  const eventData = eventSnap.data() as PlatformEventDoc;
                  const status = asTrimmedString(eventData.status).toLowerCase();

                  if (status === "live") {
                    throw new HttpsError("failed-precondition", "Event is already live.");
                  }

                  if (status === "ended" || status === "cancelled") {
                    throw new HttpsError(
                      "failed-precondition",
                      "Event is no longer accepting RSVPs."
                    );
                  }

                  const capacity =
                    typeof eventData.capacity === "number" ? eventData.capacity : 0;

                  const eventRecord = eventData as Record<string, unknown>;

                  const attendeeCount = typeof eventRecord.attendeeCount === "number" ?
                    eventRecord.attendeeCount :
                    0;

                  const isFull = capacity > 0 && attendeeCount >= capacity;

                  if (isFull) {
                    if (!eventData.waitlistEnabled) {
                      throw new HttpsError("resource-exhausted", "Event is full.");
                    }

                    if (!waitlistSnap.exists) {
                      tx.set(
                        waitlistRef,
                        {
                          uid,
                          email: identity.email,
                          displayName: identity.displayName,
                          status: "waiting",
                          eventId,
                          createdAt: FieldValue.serverTimestamp(),
                          updatedAt: FieldValue.serverTimestamp(),
                          promotedAt: null,
                          promotedBy: null,
                        } as PlatformEventWaitlistDoc,
                        { merge: true }
                      );
                    }

                    return {
                      success: true,
                      eventId,
                      status: "waitlisted",
                    };
                  }

                  tx.set(
                    rsvpRef,
                    {
                      uid,
                      email: identity.email,
                      displayName: identity.displayName,
                      status: "confirmed",
                      eventId,
                      createdAt: FieldValue.serverTimestamp(),
                      updatedAt: FieldValue.serverTimestamp(),
                    },
                    { merge: true }
                  );

                  if (inviteSnap.exists) {
                    tx.set(
                      inviteRef,
                      {
                        status: "accepted",
                        respondedAt: FieldValue.serverTimestamp(),
                        updatedAt: FieldValue.serverTimestamp(),
                      },
                      { merge: true }
                    );
                  }

                  tx.update(eventRef, {
                    attendeeCount: FieldValue.increment(1),
                    rsvpCount: FieldValue.increment(1),
                    updatedAt: FieldValue.serverTimestamp(),
                  });

                  return {
                    success: true,
                    eventId,
                    status: "confirmed",
                  };
                });
              }
            );


/**
 * Sends staged event invitations and creates Event CRM guest records.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Send result.
 */
export const sendEventInvitations = onCall(
  { secrets: [RESEND_API_KEY, RESEND_FROM_EMAIL] },
  async (request: CallableRequest): Promise<object> => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);
    const inviteesRaw = data.invitees;

    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }

    if (!Array.isArray(inviteesRaw) || inviteesRaw.length === 0) {
      throw new HttpsError("invalid-argument", "Missing invitees.");
    }

    if (inviteesRaw.length > 100) {
      throw new HttpsError("invalid-argument", "Invite batch limit is 100.");
    }

    const eventRef = db.collection("events").doc(eventId);
    const eventSnap = await eventRef.get();

    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found.");
    }

      const eventData = eventSnap.data() as PlatformEventDoc | undefined;
      const eventTitle = asTrimmedString(eventData?.title) || "Trivia GOAT Event";
      const invitedBy = request.auth?.uid ?? "";

      if (!invitedBy) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const rawEventData = eventSnap.data() ?? {};
      const requesterEmail = asTrimmedString(request.auth?.token?.email).toLowerCase();

      const createdBy = asTrimmedString(rawEventData.createdBy);
      const organizerUID = asTrimmedString(rawEventData.organizerUID);
      const organizerUid = asTrimmedString(rawEventData.organizerUid);
      const submittedByUID = asTrimmedString(rawEventData.submittedByUID);
      const submittedByUid = asTrimmedString(rawEventData.submittedByUid);
      const updatedBy = asTrimmedString(rawEventData.updatedBy);

      const canManageInviteFlow =
        invitedBy === OWNER_UID ||
        requesterEmail === "bravatech4226@gmail.com" ||
        invitedBy === createdBy ||
        invitedBy === organizerUID ||
        invitedBy === organizerUid ||
        invitedBy === submittedByUID ||
        invitedBy === submittedByUid ||
        invitedBy === updatedBy;

      if (!canManageInviteFlow) {
        logger.warn("sendEventInvitations denied", {
          eventId,
          invitedBy,
          requesterEmail,
          createdBy,
          organizerUID,
          submittedByUID,
          updatedBy,
          databaseId: "b4-v2-default-clone",
        });

        throw new HttpsError("permission-denied", "Event manager access required.");
      }

    const normalizedInvitees = inviteesRaw
      .filter(isRecord)
      .map((invitee: Record<string, unknown>) => {
        const sourceRaw = asTrimmedString(invitee.source).toLowerCase();
        const source = sourceRaw === "contacts" || sourceRaw === "import" ? sourceRaw : "manual";
        const email = asTrimmedString(invitee.email).toLowerCase();
        const name = cleanDisplayName(invitee.name || email.split("@")[0]);

        return {
          name,
          email,
          role: normalizeEventPersonRole(invitee.role),
          organization: asTrimmedString(invitee.organization).slice(0, 120),
          notes: asTrimmedString(invitee.notes).slice(0, 500),
          isVIP: parseOptionalBoolean(invitee.isVIP) ?? false,
          source,
        };
      })
      .filter((invitee) => invitee.email && isValidEmail(invitee.email));

    const uniqueInvitees = Array.from(
      new Map(normalizedInvitees.map((invitee) => [invitee.email, invitee])).values()
    );

    if (uniqueInvitees.length === 0) {
      throw new HttpsError("invalid-argument", "No valid invitee emails were provided.");
    }

    const emailsSent: string[] = [];
    const batch = db.batch();

    for (const invitee of uniqueInvitees) {
      const guestId = makeEventGuestId(invitee.email);
      const syntheticUid = `guest_${hashToken(`${eventId}:${invitee.email}`).slice(0, 32)}`;
      const token = createVerificationToken();
      const tokenHash = hashToken(token);
      const inviteUrl = buildEventInvitationUrl(eventId, guestId, invitee.email, token);
      const guestRef = eventRef.collection("guests").doc(guestId);
      const inviteRef = eventRef.collection("invites").doc(syntheticUid);

      batch.set(
        guestRef,
        {
          eventId,
          name: invitee.name,
          email: invitee.email,
          role: invitee.role,
          organization: invitee.organization,
          notes: invitee.notes,
          isVIP: invitee.isVIP,
          invitationStatus: "invited",
          invitationTokenHash: tokenHash,
          invitationTokenCreatedAt: new Date().toISOString(),
          invitationExpiresAt: buildFutureIso(24 * 14),
          invitedAt: FieldValue.serverTimestamp(),
          acceptedAt: null,
          declinedAt: null,
          source: invitee.source,
          invitedBy,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        } as PlatformEventGuestDoc,
        { merge: true }
      );

      batch.set(
        inviteRef,
        {
          uid: syntheticUid,
          email: invitee.email,
          displayName: invitee.name,
          status: "invited",
          inviteSource: "event_crm",
          eventId,
          invitedBy,
          invitedAt: FieldValue.serverTimestamp(),
          respondedAt: null,
          updatedAt: FieldValue.serverTimestamp(),
        } as PlatformEventInviteDoc,
        { merge: true }
      );

      await sendEventInvitationEmail(
        invitee.email,
        invitee.name,
        eventTitle,
        invitee.role,
        invitee.organization,
        inviteUrl
      );

      emailsSent.push(invitee.email);
    }

    await batch.commit();

    logger.info("sendEventInvitations complete", {
      eventId,
      databaseId: "b4-v2-default-clone",
      count: emailsSent.length,
    });

    return {
      success: true,
      eventId,
      status: "sent",
      sentCount: emailsSent.length,
      emails: emailsSent,
    };
  }
);

/**
 * Accepts or declines an Event CRM invitation using a secure token.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Response result.
 */
export const respondToEventInvitation = onCall(
  async (request: CallableRequest): Promise<object> => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);
    const guestId = asTrimmedString(data.guestId);
    const token = asTrimmedString(data.token);
    const response = asTrimmedString(data.response).toLowerCase();

    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }
    if (!guestId) {
      throw new HttpsError("invalid-argument", "Missing guestId.");
    }
    if (!token) {
      throw new HttpsError("invalid-argument", "Missing token.");
    }
    if (response !== "accepted" && response !== "declined") {
      throw new HttpsError("invalid-argument", "Invalid invitation response.");
    }

    const eventRef = db.collection("events").doc(eventId);
    const guestRef = eventRef.collection("guests").doc(guestId);
    const guestSnap = await guestRef.get();

    if (!guestSnap.exists) {
      throw new HttpsError("not-found", "Invitation not found.");
    }

    const guestData = guestSnap.data() as PlatformEventGuestDoc | undefined;
    const expiresAt = asTrimmedString(guestData?.invitationExpiresAt);

    if (!guestData?.invitationTokenHash) {
      throw new HttpsError("failed-precondition", "Invitation token is no longer active.");
    }

    if (expiresAt && new Date(expiresAt).getTime() < Date.now()) {
      throw new HttpsError("deadline-exceeded", "Invitation has expired.");
    }

    if (hashToken(token) !== guestData.invitationTokenHash) {
      throw new HttpsError("permission-denied", "Invalid invitation token.");
    }

    const syntheticUid = `guest_${hashToken(`${eventId}:${guestData.email}`).slice(0, 32)}`;
    const inviteRef = eventRef.collection("invites").doc(syntheticUid);
    const statusPatch = response === "accepted" ?
      { invitationStatus: "accepted", acceptedAt: FieldValue.serverTimestamp() } :
      { invitationStatus: "declined", declinedAt: FieldValue.serverTimestamp() };

    await Promise.all([
      guestRef.set(
        {
          ...statusPatch,
          invitationTokenHash: null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      ),
      inviteRef.set(
        {
          status: response,
          respondedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      ),
    ]);

    return { success: true, eventId, guestId, status: response };
  }
);

/**
 * Invites a user directly to an event.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Invite result.
 */
export const inviteUserToEvent = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);
    const uid = asTrimmedString(data.uid);

    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }
    if (!uid) {
      throw new HttpsError("invalid-argument", "Missing uid.");
    }

    const identity = await readUserIdentity(uid);
    const inviteRef = db.collection("events").doc(eventId).collection("invites").doc(uid);

    await inviteRef.set(
      {
        uid,
        email: identity.email,
        displayName: identity.displayName,
        status: "invited",
        inviteSource: "admin",
        eventId,
        invitedBy: request.auth?.uid ?? OWNER_UID,
        invitedAt: FieldValue.serverTimestamp(),
        respondedAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      } as PlatformEventInviteDoc,
      { merge: true }
    );

    return { success: true, eventId, uid, status: "invited" };
  }
);

/**
 * Approves an event access request.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Approval result.
 */
export const approveEventAccessRequest = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);
    const uid = asTrimmedString(data.uid);

    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }
    if (!uid) {
      throw new HttpsError("invalid-argument", "Missing uid.");
    }

    const eventRef = db.collection("events").doc(eventId);
    const requestRef = eventRef.collection("accessRequests").doc(uid);
    const inviteRef = eventRef.collection("invites").doc(uid);
    const requestSnap = await requestRef.get();

    if (!requestSnap.exists) {
      throw new HttpsError("not-found", "Access request not found.");
    }

    const requestData = requestSnap.data() as PlatformEventAccessRequestDoc;
    const reviewedBy = request.auth?.uid ?? OWNER_UID;
    const batch = db.batch();

    batch.set(
      inviteRef,
      {
        uid,
        email: requestData.email,
        displayName: requestData.displayName,
        status: "approved",
        inviteSource: "request_access",
        eventId,
        invitedBy: reviewedBy,
        invitedAt: FieldValue.serverTimestamp(),
        respondedAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      } as PlatformEventInviteDoc,
      { merge: true }
    );

    batch.set(
      requestRef,
      {
        status: "approved",
        reviewedAt: FieldValue.serverTimestamp(),
        reviewedBy,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    await batch.commit();
    return { success: true, eventId, uid, status: "approved" };
  }
);

/**
 * Rejects an event access request.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Rejection result.
 */
export const rejectEventAccessRequest = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);
    const uid = asTrimmedString(data.uid);

    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }
    if (!uid) {
      throw new HttpsError("invalid-argument", "Missing uid.");
    }

    const requestRef = db.collection("events").doc(eventId).collection("accessRequests").doc(uid);
    const requestSnap = await requestRef.get();
    if (!requestSnap.exists) {
      throw new HttpsError("not-found", "Access request not found.");
    }

    await requestRef.set(
      {
        status: "rejected",
        reviewedAt: FieldValue.serverTimestamp(),
        reviewedBy: request.auth?.uid ?? OWNER_UID,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { success: true, eventId, uid, status: "rejected" };
  }
);

/**
 * Promotes a waitlisted user.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Promotion result.
 */
export const promoteFromWaitlist = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const eventId = asTrimmedString(data.eventId);
    const uid = asTrimmedString(data.uid);

    if (!eventId) {
      throw new HttpsError("invalid-argument", "Missing eventId.");
    }
    if (!uid) {
      throw new HttpsError("invalid-argument", "Missing uid.");
    }

    const eventRef = db.collection("events").doc(eventId);
    const waitlistRef = eventRef.collection("waitlist").doc(uid);
    const inviteRef = eventRef.collection("invites").doc(uid);
    const waitlistSnap = await waitlistRef.get();
    if (!waitlistSnap.exists) {
      throw new HttpsError("not-found", "Waitlist entry not found.");
    }

    const waitlistData = waitlistSnap.data() as PlatformEventWaitlistDoc;
    const promotedBy = request.auth?.uid ?? OWNER_UID;
    const batch = db.batch();

    batch.set(
      inviteRef,
      {
        uid,
        email: waitlistData.email,
        displayName: waitlistData.displayName,
        status: "approved",
        inviteSource: "waitlist_promotion",
        eventId,
        invitedBy: promotedBy,
        invitedAt: FieldValue.serverTimestamp(),
        respondedAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      } as PlatformEventInviteDoc,
      { merge: true }
    );

    batch.set(
      waitlistRef,
      {
        status: "promoted",
        promotedAt: FieldValue.serverTimestamp(),
        promotedBy,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    await batch.commit();
    return { success: true, eventId, uid, status: "approved" };
  }
);
            type EventAttribution = {
              ref?: string;
              utm_source?: string;
              utm_medium?: string;
              utm_campaign?: string;
              utm_content?: string;
              landingURL?: string;
            };

            type SubmitEventAccessLeadData = {
              eventId?: string;
              email?: string;
              displayName?: string;
              note?: string;
              attribution?: EventAttribution;
            };

            /**
             * Captures a public event access lead and sends a verification email.
             * @param {CallableRequest} request - Callable request.
             * @return {Promise<object>} Submission result.
             */
            export const submitEventAccessLead = onCall(
        { secrets: [RESEND_API_KEY, RESEND_FROM_EMAIL] },
            async (
              request: CallableRequest<SubmitEventAccessLeadData>
            ): Promise<object> => {
            const data = (request.data ?? {}) as Record<string, unknown>;
            const attribution: EventAttribution = data.attribution ?? {};
            const referralSource = String(
              attribution.ref ||
                attribution.utm_source ||
                "direct"
            ).trim();
            const referralMedium = String(
              attribution.utm_medium || "unknown"
            ).trim();
            const referralCampaign = String(
              attribution.utm_campaign || ""
            ).trim();
            const referralContent = String(
              attribution.utm_content || ""
            ).trim();
            const landingURL = String(
              attribution.landingURL || ""
            ).trim();
            const eventId = asTrimmedString(data.eventId);
          const email = asTrimmedString(data.email).toLowerCase();
          const rawDisplayName = asTrimmedString(data.displayName);
          const displayName = normalizeEventLeadDisplayName(rawDisplayName, email);
          const note = asTrimmedString(data.note).slice(0, 240);
            if (!eventId) {
            throw new HttpsError("invalid-argument", "Missing eventId.");
          }

          if (!email || !isValidEmail(email)) {
            throw new HttpsError("invalid-argument", "Invalid email.");
          }

          await enforceRateLimit(
            `submitEventAccessLead:${eventId}:${email}`,
            3,
            15 * 60 * 1000,
            "Too many access requests for this email. Please wait before trying again."
          );

          const eventRef = db.collection("events").doc(eventId);
          const leadRef = eventRef.collection("accessLeads").doc(email);

          const [eventSnap, leadSnap] = await Promise.all([eventRef.get(), leadRef.get()]);
          if (!eventSnap.exists) {
            throw new HttpsError("not-found", "Event not found.");
          }

          const eventData = eventSnap.data() as PlatformEventDoc | undefined;
          const eventTitle = asTrimmedString(eventData?.title) || "Trivia GOAT Event";

          if (!eventData?.published) {
            throw new HttpsError("failed-precondition", "Event is not publicly available.");
          }

          if (eventData.status === "ended" || eventData.status === "cancelled") {
            throw new HttpsError(
              "failed-precondition",
              "Event is no longer accepting access requests."
            );
          }

          if (leadSnap.exists) {
            const existingLead = leadSnap.data() as PlatformEventAccessLeadDoc | undefined;
            const existingStatus = asTrimmedString(existingLead?.status).toLowerCase();

            if (
              existingStatus === "approved" ||
              existingStatus === "waitlisted" ||
              existingStatus === "verified"
            ) {
              return {
                success: true,
                eventId,
                status: existingStatus,
              };
            }

            if (
              existingStatus === "pending_verification" &&
              !isExpiredIso(existingLead?.verificationExpiresAt ?? null)
            ) {
              return {
                success: true,
                eventId,
                status: "verification_pending",
              };
            }
          }

          const verificationToken = createVerificationToken();
          const verificationTokenHash = hashToken(verificationToken);
          const verificationExpiresAt = buildFutureIso(24);
          const verificationUrl = buildVerificationUrl(eventId, email, verificationToken);

          await leadRef.set(
            {
              email,
              displayName,
              note,
              eventId,

              status: "pending_verification",
              verificationMethod: "email_link",
              verificationTokenHash,
              verificationTokenCreatedAt: new Date().toISOString(),
              verificationExpiresAt,
              verificationSentAt: null,
              verifiedAt: null,

              requestedAt: FieldValue.serverTimestamp(),

              attribution,
              referralSource,
              referralMedium,
              referralCampaign,
              referralContent,
              landingURL,

              invitedAt: null,
              approvedAt: null,

              updatedAt: FieldValue.serverTimestamp(),

              source: "public_request_access",
              sourceCampaign: "toronto_tech_week_launch",

              linkedUid: null,
            } as PlatformEventAccessLeadDoc,
            { merge: true }
          );

          await sendEventLeadVerificationEmail(email, displayName, eventTitle, verificationUrl);

          await leadRef.set(
            {
              verificationSentAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

          return {
            success: true,
            eventId,
            status: leadSnap.exists ? "verification_resent" : "submitted",
          };
        }
      );

/**
 * Routes a verified lead into invite or waitlist using transaction-safe capacity checks.
 * @param {string} eventId - Event ID.
 * @param {string} email - Lead email.
 * @return {Promise<string>} Final status.
 */
async function processVerifiedLead(eventId: string, email: string): Promise<string> {
  const eventRef = db.collection("events").doc(eventId);
  const leadRef = eventRef.collection("accessLeads").doc(email);

  return db.runTransaction(async (tx: Transaction) => {
    const [eventSnap, leadSnap] = await Promise.all([tx.get(eventRef), tx.get(leadRef)]);

    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found.");
    }
    if (!leadSnap.exists) {
      throw new HttpsError("not-found", "Lead not found.");
    }

    const eventData = eventSnap.data() as PlatformEventDoc | undefined;
    const leadData = leadSnap.data() as PlatformEventAccessLeadDoc | undefined;

    const capacity = typeof eventData?.capacity === "number" ? eventData.capacity : 0;
    const displayName = cleanDisplayName(leadData?.displayName);
    const syntheticUid = `lead_${email.replace(/[^a-z0-9]/g, "")}`;

            const syntheticInviteRef = eventRef.collection("invites").doc(syntheticUid);
            const syntheticWaitlistRef = eventRef.collection("waitlist").doc(syntheticUid);

            const [invitesSnap, existingInviteSnap, existingWaitlistSnap] = await Promise.all([
              tx.get(
                eventRef.collection("invites").where("status", "in", ["invited", "approved", "accepted"])
              ),
              tx.get(syntheticInviteRef),
              tx.get(syntheticWaitlistRef),
            ]);

            if (existingInviteSnap.exists) {
              return "approved";
            }

            if (existingWaitlistSnap.exists) {
              return "waitlisted";
            }

            const approvedCount = invitesSnap.size;

            if (approvedCount < capacity) {
            tx.set(
              syntheticInviteRef,
        {
          uid: syntheticUid,
          email,
          displayName,
          status: "approved",
          inviteSource: "request_access",
          eventId,
          invitedBy: "system_auto",
          invitedAt: FieldValue.serverTimestamp(),
          respondedAt: null,
          updatedAt: FieldValue.serverTimestamp(),
        } as PlatformEventInviteDoc,
        { merge: true }
      );

      tx.set(
        leadRef,
        {
          status: "approved",
          approvedAt: FieldValue.serverTimestamp(),
          invitedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return "approved";
    }

            tx.set(
              syntheticWaitlistRef,
      {
        uid: syntheticUid,
        email,
        displayName,
        status: "waiting",
        eventId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        promotedAt: null,
        promotedBy: null,
      } as PlatformEventWaitlistDoc,
      { merge: true }
    );

    tx.set(
      leadRef,
      {
        status: "waitlisted",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return "waitlisted";
  });
}

/**
 * Verifies a public event access lead using the emailed token.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Verification result.
 */
      export const verifyEventAccessLead = onCall(
        async (request: CallableRequest): Promise<object> => {
          const data = (request.data ?? {}) as Record<string, unknown>;
          const eventId = asTrimmedString(data.eventId);
          const email = asTrimmedString(data.email).toLowerCase();
          const token = asTrimmedString(data.token);

          if (!eventId) {
            throw new HttpsError("invalid-argument", "Missing eventId.");
          }
          if (!email || !isValidEmail(email)) {
            throw new HttpsError("invalid-argument", "Missing or invalid email.");
          }
          if (!token) {
            throw new HttpsError("invalid-argument", "Missing token.");
          }

          await enforceRateLimit(
            `verifyEventAccessLead:${eventId}:${email}`,
            8,
            15 * 60 * 1000,
            "Too many verification attempts. Please wait before trying again."
          );

          const leadRef = db.collection("events").doc(eventId).collection("accessLeads").doc(email);
          const snap = await leadRef.get();

          if (!snap.exists) {
            return {
              success: false,
              eventId,
              email,
              status: "not_found",
            };
          }

          const leadData = snap.data() as PlatformEventAccessLeadDoc | undefined;
          if (!leadData) {
            return {
              success: false,
              eventId,
              email,
              status: "not_found",
            };
          }

          if (leadData.status === "approved" || leadData.status === "waitlisted") {
            return {
              success: true,
              eventId,
              email,
              status: leadData.status,
            };
          }

          if (leadData.status === "verified") {
            const finalStatus = await processVerifiedLead(eventId, email);
            return {
              success: true,
              eventId,
              email,
              status: finalStatus,
            };
          }

          if (!leadData.verificationTokenHash || !leadData.verificationExpiresAt) {
            return {
              success: false,
              eventId,
              email,
              status: "verification_unavailable",
            };
          }

          if (isExpiredIso(leadData.verificationExpiresAt)) {
            return {
              success: false,
              eventId,
              email,
              status: "expired",
            };
          }

            const submittedHash = hashToken(token);

            logger.info("VERIFY TOKEN DEBUG", {
              eventId,
              email,
              incomingTokenLength: token.length,
              incomingTokenHash: submittedHash,
              storedTokenHash: leadData.verificationTokenHash,
              hashesMatch: submittedHash === leadData.verificationTokenHash,
            });

            if (submittedHash !== leadData.verificationTokenHash) {
            return {
              success: false,
              eventId,
              email,
              status: "invalid_token",
            };
          }

          await leadRef.set(
            {
              status: "verified",
              verifiedAt: FieldValue.serverTimestamp(),
              verificationTokenHash: null,
              verificationTokenCreatedAt: null,
              verificationExpiresAt: null,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

          const finalStatus = await processVerifiedLead(eventId, email);

          return {
            success: true,
            eventId,
            email,
            status: finalStatus,
          };
        }
      );

      /* -------------------------------------------------------------------------- */
      /* SETTINGS / PLATFORM CONFIG                                                 */
      /* -------------------------------------------------------------------------- */

      /**
       * Returns the current platform config for admin surfaces.
       * @param {CallableRequest} request - Callable request.
       * @return {Promise<object>} Platform config payload.
       */
      export const getPlatformConfig = onCall(
        async (request: CallableRequest): Promise<object> => {
          await assertAdminOrOwner(request);

          const config = await readPlatformConfig();

          return {
            success: true,
            featureFlags: config.featureFlags ?? { ...DEFAULT_FEATURE_FLAGS },
            version: config.version ?? 1,
            updatedBy: config.updatedBy ?? null,
            updatedAt: config.updatedAt ?? null,
          };
        }
      );

      /**
       * Updates one or more feature flags and records an audit entry.
       * @param {CallableRequest} request - Callable request.
       * @return {Promise<object>} Update result.
       */
      export const updateFeatureFlags = onCall(
        async (request: CallableRequest): Promise<object> => {
          const actor = await assertAdminOrOwner(request);

          const data = (request.data ?? {}) as Record<string, unknown>;
          const rawUpdates = data.updates;
          const note = asTrimmedString(data.note).slice(0, 240);

          if (!isRecord(rawUpdates)) {
            throw new HttpsError("invalid-argument", "updates must be an object.");
          }

          const entries = Object.entries(rawUpdates);
          if (entries.length === 0) {
            throw new HttpsError("invalid-argument", "At least one feature flag update is required.");
          }

          if (entries.length > 50) {
            throw new HttpsError("invalid-argument", "Too many feature flag updates in one request.");
          }

          const normalizedUpdates: Record<string, boolean> = {};

          for (const [rawKey, rawValue] of entries) {
            const key = normalizeFeatureFlagKey(rawKey);
            const value = requireBoolean(rawValue, `updates.${key}`);
            normalizedUpdates[key] = value;
          }

          const ref = db.collection(ADMIN_CONFIG_COLLECTION).doc(PLATFORM_CONFIG_DOC);

          const result = await db.runTransaction(async (tx: Transaction) => {
            const snap = await tx.get(ref);
            const existing = snap.exists ? (snap.data() as PlatformConfigDoc | undefined) : undefined;

            const currentFlags: Record<string, boolean> = {
              ...DEFAULT_FEATURE_FLAGS,
              ...(existing?.featureFlags ?? {}),
            };

            const before: Record<string, unknown> = {};
            const after: Record<string, unknown> = {};

            for (const [key, value] of Object.entries(normalizedUpdates)) {
              before[key] = currentFlags[key];
              after[key] = value;
              currentFlags[key] = value;
            }

            tx.set(
              ref,
              {
                featureFlags: currentFlags,
                updatedBy: actor.uid,
                updatedAt: FieldValue.serverTimestamp(),
                version: FieldValue.increment(1),
              } as PlatformConfigDoc,
              { merge: true }
            );

            return {
              before,
              after,
              featureFlags: currentFlags,
              changedKeys: Object.keys(normalizedUpdates),
            };
          });

          await writeAdminAuditLog({
            action: "update_feature_flags",
            actorUid: actor.uid,
            actorRole: actor.role,
            targetType: "platform_config",
            targetId: PLATFORM_CONFIG_DOC,
            note,
            before: result.before,
            after: result.after,
          });

          return {
            success: true,
            changedKeys: result.changedKeys,
            featureFlags: result.featureFlags,
          };
        }
      );

/* -------------------------------------------------------------------------- */
/* PUSH / ADMIN / WEBSITE                                                     */
/* -------------------------------------------------------------------------- */

        /**
         * Sends a test push notification to a provided token or the user's saved token.
         * @param {CallableRequest} req - Callable request.
         * @return {Promise<object>} Result payload.
         */
        export const sendTestPush = onCall(
          async (req: CallableRequest): Promise<object> => {
            const uid = req.auth?.uid;
            if (!uid) {
              throw new HttpsError("unauthenticated", "Auth required.");
            }

            const data = (req.data ?? {}) as Record<string, unknown>;
            let token = asTrimmedString(data.token);

            if (!token) {
              const userSnap = await db.collection("users").doc(uid).get();
              const userData = userSnap.data() as UserDoc | undefined;
              token = asTrimmedString(userData?.fcmToken);
            }

            if (!token) {
              throw new HttpsError("invalid-argument", "Missing token.");
            }

            await messaging.send({
              token,
              notification: {
                title: "Trivia GOAT",
                body: "Test push",
              },
            });

            return { success: true };
          }
        );

/**
 * Notifies previous leader when they are overtaken.
 * @param {FirestoreEvent<Change<DocumentSnapshot> | undefined>} event - Firestore update event.
 * @return {Promise<void>} Completion promise.
 */
export const notifyLeaderboardFlip = onDocumentUpdated(
  "leaderboards/global",
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined>): Promise<void> => {
    const before = event.data?.before?.data() as LeaderboardGlobalDoc | undefined;
    const after = event.data?.after?.data() as LeaderboardGlobalDoc | undefined;

    if (!before || !after) return;

    const prevTopUid = before.topUid;
    const newTopUid = after.topUid;

    if (!prevTopUid || !newTopUid || prevTopUid === newTopUid) return;

    const prevUserSnap = await db.collection("users").doc(prevTopUid).get();
    const prevUser = prevUserSnap.exists ? (prevUserSnap.data() as UserDoc) : undefined;
    const token = asTrimmedString(prevUser?.fcmToken);
    if (!token) return;

    await messaging.send({
      token,
      notification: {
        title: "You just got passed ⚡️",
        body: `${after.topName ?? "A new pilot"} took #1. Jump back in and reclaim it.`,
      },
      data: {
        type: "leaderboard_flip",
        newTopUid: String(newTopUid),
      },
    });
  }
);

/**
 * Rebuilds leaderboard snapshots for admin use.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Result payload.
 */
export const rebuildLeaderboardAdmin = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);
    await rebuildPublicLeaderboardSnapshots(100);
    return { success: true };
  }
);

/**
 * Rebuilds website platform stats.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Result payload.
 */
export const rebuildWebsiteStats = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);
    await rebuildPublicPlatformStats();
    return { success: true, target: "stats/platform" };
  }
);

/**
 * Rebuilds website leaderboard snapshots.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Result payload.
 */
export const rebuildWebsiteLeaderboard = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const rawLimit = toInt(data.limit);
    const limitCount = Number.isFinite(rawLimit) ? Math.max(10, Math.min(250, rawLimit)) : 100;
    await rebuildPublicLeaderboardSnapshots(limitCount);
    return {
      success: true,
      target: "website/website/leaderboard/snapshots/snapshots",
      limit: limitCount,
    };
  }
);

/**
 * Rebuilds all public website data.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Result payload.
 */
export const rebuildWebsitePublicData = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const rawLimit = toInt(data.limit);
    const limitCount = Number.isFinite(rawLimit) ? Math.max(10, Math.min(250, rawLimit)) : 100;

    await rebuildPublicPlatformStats();
    await rebuildPublicLeaderboardSnapshots(limitCount);

    return {
      success: true,
      statsTarget: "stats/platform",
      leaderboardTarget: "website/website/leaderboard/snapshots/snapshots",
      limit: limitCount,
    };
  }
);

/**
 * Backfills legacy user fields.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Backfill summary.
 */
export const backfillLegacyUserFields = onCall(
  async (request: CallableRequest): Promise<object> => {
    assertOwner(request);
    const result = await backfillLegacyUsers();
    return {
      success: true,
      ...result,
    };
  }
);

/**
 * Rebuilds stats when user created.
 * @return {Promise<void>} Completion promise.
 */
export const rebuildStatsOnUserCreate = onDocumentCreated(
  "users/{uid}",
  async (): Promise<void> => {
    await rebuildPublicPlatformStats();
  }
);

/**
 * Rebuilds stats when post created.
 * @return {Promise<void>} Completion promise.
 */
export const rebuildStatsOnPostCreate = onDocumentCreated(
  "posts/{postId}",
  async (): Promise<void> => {
    await rebuildPublicPlatformStats();
  }
);

/**
 * Rebuilds stats when post updated.
 * @return {Promise<void>} Completion promise.
 */
export const rebuildStatsOnPostUpdate = onDocumentUpdated(
  "posts/{postId}",
  async (): Promise<void> => {
    await rebuildPublicPlatformStats();
  }
);

/**
 * Rebuilds stats when event created.
 * @return {Promise<void>} Completion promise.
 */
export const rebuildStatsOnEventCreate = onDocumentCreated(
  "events/{eventId}",
  async (): Promise<void> => {
    await rebuildPublicPlatformStats();
  }
);

/**
 * Rebuilds stats when global battle created.
 * @return {Promise<void>} Completion promise.
 */
export const rebuildStatsOnGlobalBattleCreate = onDocumentCreated(
  "globalBattles/{lobbyId}",
  async (): Promise<void> => {
    await rebuildPublicPlatformStats();
  }
);

/**
 * Rebuilds leaderboard when user created.
 * @return {Promise<void>} Completion promise.
 */
export const rebuildLeaderboardOnUserCreate = onDocumentCreated(
  "users/{uid}",
  async (): Promise<void> => {
    await rebuildPublicLeaderboardSnapshots(100);
  }
);

/**
 * Rebuilds leaderboard when user updated.
 * @return {Promise<void>} Completion promise.
 */
export const rebuildLeaderboardOnUserUpdate = onDocumentUpdated(
  "users/{uid}",
  async (): Promise<void> => {
    await rebuildPublicLeaderboardSnapshots(100);
  }
);
      /* -------------------------------------------------------------------------- */
      /* DAILY AI POST TEMPLATE TYPE                                                */
      /* -------------------------------------------------------------------------- */
      /**
       * Curated Daily AI post template used by scheduled feed publishing.
       * Defines the structure for templated daily feed posts.
       */
      type DailyAiPostTemplate = {
        type:
          | "featured_editorial"
          | "full_breakdown"
          | "challenge"
          | "debate"
          | "event_angle"
          | "insight"
          | "culture"
          | "global_battle"
          | "learning_prompt";
        topic:
          | "performance"
          | "rankings"
          | "science"
          | "competition"
          | "events"
          | "learning"
          | "culture"
          | "global_battle"
          | "memory"
          | "strategy";
        content: string;
      };

      /* -------------------------------------------------------------------------- */
      /* DAILY AI POST TEMPLATES                                                    */
      /* -------------------------------------------------------------------------- */
      /**
       * Returns curated Daily AI post templates.
       * @return {DailyAiPostTemplate[]} Available templates.
       */
      function getDailyAiPostTemplates(): DailyAiPostTemplate[] {
        return [
          {
            type: "featured_editorial",
            topic: "performance",
            content: `GOAT Editorial 🧠

      A lot of players think the best competitor is simply the person who knows the most.

      That sounds right — until live play exposes the gap between stored knowledge and usable knowledge.

      The real separator is often retrieval under pressure.

      Not just what you know, but how quickly you trust it, deliver it, and recover if you miss.

      That is why competition feels different from casual trivia.

      It forces knowledge to become performance.`,
          },
          {
            type: "debate",
            topic: "competition",
            content: `Debate 🔥

      When two players know roughly the same amount, what matters more:
      speed or accuracy?

      Speed can steal a round.

      Accuracy can protect a streak.

      So the better question might be:

      Which one should a serious competitive platform reward more heavily?`,
          },
          {
            type: "global_battle",
            topic: "global_battle",
            content: `Global Battle Note 🌍⚡

      A close match changes everything.

      The early questions test knowledge.

      The late questions test nerve.

      When the score is tight and the clock starts shrinking, even an easy answer can feel heavier.

      That is the real arena.

      Not just knowing the answer — staying clean when the room gets loud.`,
          },
          {
            type: "learning_prompt",
            topic: "memory",
            content: `Learning Prompt 🧠

      Memory is not just storage.

      It is access.

      A fact you cannot retrieve under pressure is not fully yours yet.

      That is why short, repeated competition can train recall differently than passive studying.

      Question for the room:

      Do you remember more when you study quietly, or when you have to prove it live?`,
          },
          {
            type: "culture",
            topic: "culture",
            content: `GOAT Culture 🐐

      The best trivia rooms have edge without becoming toxic.

      People can compete hard, disagree strongly, and still keep the game sharp.

      That is the sweet spot:

      pressure without disrespect,
      confidence without arrogance,
      challenge without chaos.

      That is the kind of arena worth building.`,
          },
        ];
      }

      /* -------------------------------------------------------------------------- */
      /* DAILY AI TEMPLATE PICKER                                                   */
      /* -------------------------------------------------------------------------- */
      /**
       * Picks a deterministic Daily AI post template for a given day key.
       * @param {string} dayKey - YYYY-MM-DD day key.
       * @return {DailyAiPostTemplate} Selected template.
       */
      /**
       * Picks a deterministic Daily AI post template for a given day key and slot.
       * @param {string} dayKey - YYYY-MM-DD day key.
       * @param {string} slot - Publishing slot.
       * @return {DailyAiPostTemplate} Selected template.
       */
      function pickDailyAiPostTemplate(
        dayKey: string,
        slot: string
      ): DailyAiPostTemplate {
        const templates = getDailyAiPostTemplates();
        const index = stableHash32(`daily-ai:${dayKey}:${slot}`) % templates.length;
        return templates[index];
      }
      /* -------------------------------------------------------------------------- */
      /* DAILY AI POST PUBLISHER                                                    */
      /* -------------------------------------------------------------------------- */
        /**
         * Publishes one Daily AI post for the provided day key.
         * Idempotent per dayKey to prevent duplicate posts.
         * @param {string} dayKey - YYYY-MM-DD day key.
         * @return {Promise<object>} Publish result.
         */
      /**
       * Publishes one Daily AI post for the provided day key and slot.
       * Idempotent per dayKey + slot to prevent duplicate posts.
       * @param {string} dayKey - YYYY-MM-DD day key.
       * @param {string} slot - Publishing slot.
       * @return {Promise<object>} Publish result.
       */
      async function publishDailyAiPostForDay(
        dayKey: string,
        slot: string
      ): Promise<{
        created: boolean;
        postId: string;
        contentType?: string;
        topic?: string;
        slot?: string;
      }> {
        const postId = `featured_ai_${dayKey}_${slot}`;
        const ref = db.collection("posts").doc(postId);
        const snap = await ref.get();

        if (snap.exists) {
          return { created: false, postId };
        }

        const selection = pickDailyAiPostTemplate(dayKey, slot);

        await ref.set({
          content: selection.content,
          contentType: selection.type,
          topic: selection.topic,
          authorUID: "system_ai_featured",
          authorName: "Trivia GOAT AI",
          status: "approved",
          createdAt: FieldValue.serverTimestamp(),
          approvedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          likesCount: 0,
          commentsCount: 0,
          isAI: true,
          dayKey,
          dailySlot: slot,
          aiPostKind: "daily_featured",
          source: `scheduled_daily_ai_${slot}`,
        });

        return {
          created: true,
          postId,
          contentType: selection.type,
          topic: selection.topic,
          slot,
        };
      }

/* -------------------------------------------------------------------------- */
/* SCHEDULERS / HEALTH                                                        */
/* -------------------------------------------------------------------------- */

/**
 * Publishes one approved morning Daily AI post into the public feed.
 * Idempotent by dayKey + slot, so retries cannot create duplicates.
 * @return {Promise<void>} Completion promise.
 */
export const scheduledDailyAiPostPublish = onSchedule(
  {
    schedule: "every day 09:00",
    timeZone: "America/Toronto",
    region: "us-central1",
  },
  async (): Promise<void> => {
    const dayKey = new Date().toISOString().slice(0, 10);
    const result = await publishDailyAiPostForDay(dayKey, "morning");

    logger.info("scheduledDailyAiPostPublish complete", result);
  }
);

/**
 * Publishes one approved afternoon Daily AI post into the public feed.
 * Idempotent by dayKey + slot, so retries cannot create duplicates.
 * @return {Promise<void>} Completion promise.
 */
export const scheduledAfternoonAiPostPublish = onSchedule(
  {
    schedule: "every day 14:00",
    timeZone: "America/Toronto",
    region: "us-central1",
  },
  async (): Promise<void> => {
    const dayKey = new Date().toISOString().slice(0, 10);
    const result = await publishDailyAiPostForDay(dayKey, "afternoon");

    logger.info("scheduledAfternoonAiPostPublish complete", result);
  }
);

/**
 * Publishes one approved evening Daily AI post into the public feed.
 * Idempotent by dayKey + slot, so retries cannot create duplicates.
 * @return {Promise<void>} Completion promise.
 */
export const scheduledEveningAiPostPublish = onSchedule(
  {
    schedule: "every day 19:00",
    timeZone: "America/Toronto",
    region: "us-central1",
  },
  async (): Promise<void> => {
    const dayKey = new Date().toISOString().slice(0, 10);
    const result = await publishDailyAiPostForDay(dayKey, "evening");

    logger.info("scheduledEveningAiPostPublish complete", result);
  }
);

/**
 * Scheduled stats rebuild.
 * @return {Promise<void>} Completion promise.
 */
export const scheduledStatsRebuild = onSchedule(
  { schedule: "every 10 minutes", region: "us-central1" },
  async (): Promise<void> => {
    await rebuildPublicPlatformStats();
  }
);

/**
 * Scheduled leaderboard rebuild.
 * @return {Promise<void>} Completion promise.
 */
export const scheduledLeaderboardRebuild = onSchedule(
  { schedule: "every 30 minutes", region: "us-central1" },
  async (): Promise<void> => {
    await rebuildPublicLeaderboardSnapshots(100);
  }
);

/**
 * Returns backend health status for authenticated clients.
 * @param {CallableRequest} request - Callable request.
 * @return {Promise<object>} Health payload.
 */
export const healthCheck = onCall(
  async (request: CallableRequest): Promise<object> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }

    return {
      ok: true,
      ts: new Date().toISOString(),
      region: "us-central1",
    };
  }
);
