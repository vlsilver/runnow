// One-off uploader: reads the *_route.json files produced by
// build_routes.py (or the legacy hand-authored ones) and writes them to
// Firestore as journeyRoutes/{id} (summary) + journeyRoutes/{id}/detail/data
// (points + milestones) — see firestore.rules and MemberRepository in
// lib/src/repository.dart for how the app reads these back.
//
// Requires: `npm install firebase-admin` in this directory first, and
// `gcloud auth application-default login` (or GOOGLE_APPLICATION_CREDENTIALS)
// for a principal with Firestore write access to the target project.
// Re-running is safe/idempotent — it always overwrites by route id.
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import admin from "firebase-admin";

const PROJECT_ID = "run-now-79767";
const ASSETS_DIR = path.resolve(import.meta.dirname, "../../assets/journey");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: PROJECT_ID,
});

const db = admin.firestore();

async function main() {
  const files = (await readdir(ASSETS_DIR)).filter((f) => f.endsWith("_route.json"));
  console.log(`Found ${files.length} route files.`);

  for (const file of files) {
    const raw = await readFile(path.join(ASSETS_DIR, file), "utf8");
    const data = JSON.parse(raw);
    const { id, name, tagline, totalLengthMeters, points, milestones } = data;
    if (!id) throw new Error(`Missing id in ${file}`);

    // Firestore rejects nested arrays (array of [lat, lon] pairs), so store
    // points as an array of {lat, lon} maps instead.
    const pointMaps = points.map(([lat, lon]) => ({ lat, lon }));

    const routeRef = db.collection("journeyRoutes").doc(id);
    await routeRef.set({ id, name, tagline, totalLengthMeters });
    await routeRef.collection("detail").doc("data").set({ points: pointMaps, milestones });

    console.log(`Wrote journeyRoutes/${id} (+ detail/data): ${points.length} points, ${milestones.length} milestones, ${(totalLengthMeters / 1000).toFixed(1)} km`);
  }

  console.log("Done.");
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
