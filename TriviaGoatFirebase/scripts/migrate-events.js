const admin = require("firebase-admin");

const serviceAccount = require("../serviceAccountKey.json");

const DATABASE_ID = "b4-v2-default-clone";
const DRY_RUN = false;

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore(admin.app(), DATABASE_ID);

console.log("Firebase project:", serviceAccount.project_id);
console.log("Firestore database:", DATABASE_ID);
console.log("Dry run:", DRY_RUN);

async function migrateEvents() {
  const snapshot = await db.collection("events").get();

  console.log(`Found ${snapshot.size} events`);

  for (const doc of snapshot.docs) {
    const data = doc.data();

    const title =
      data.title ||
      data.name ||
      "Untitled Event";

      const fullDescription =
        data.summary ||
        data.description ||
        data.heroLine ||
        "";

      const heroLine =
        data.heroLine && data.heroLine.length <= 90
          ? data.heroLine
          : "The official debut of Trivia GOAT.";

    const category =
      data.category ||
      data.type ||
      "community";

    const published =
      data.published ??
      data.isPublic ??
      false;

    let approvalStatus = data.approvalStatus;

    if (!approvalStatus) {
      approvalStatus = published ? "approved" : "draft";
    }

    const update = {
      title,
        heroLine,
        summary: fullDescription,

      category,
      visibility: published ? "public" : "private",

      approvalStatus,
      published,

      locationType: data.locationType || "hybrid",

      featured: data.featured ?? false,
      featuredPriority: data.featuredPriority ?? 0,

      capacity: data.capacity ?? 100,
      attendeeCount: data.attendeeCount ?? 0,
      waitlistEnabled: data.waitlistEnabled ?? true,

      status:
        data.status === "cancelled" || data.status === "canceled"
          ? "scheduled"
          : (data.status || "scheduled"),

      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };

    if (DRY_RUN) {
      console.log("DRY RUN:", doc.id, update);
    } else {
      await doc.ref.set(update, { merge: true });
      console.log(`Migrated: ${doc.id}`);
    }
  }

  console.log(DRY_RUN ? "Dry run complete" : "Migration complete");
}

migrateEvents().catch((error) => {
  console.error("Migration failed:", error);
  process.exit(1);
});
