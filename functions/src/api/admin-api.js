/**
 * Admin API Module
 *
 * I provide administrative utility endpoints for database management.
 *
 * Functions:
 * - deleteAllFacilities: Deletes all facilities from the database
 */

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const cors = require("cors")({origin: true});

/**
 * HTTP Function to delete all facilities
 * Call with: https://us-central1-lighthouse-2498c.cloudfunctions.net/deleteAllFacilities
 */
exports.deleteAllFacilities = onRequest(async (request, response) => {
  cors(request, response, async () => {
    try {
      console.log("[DELETE_FACILITIES] Starting to delete all facilities...");

      const snapshot = await admin.firestore().collection("facilities").get();

      if (snapshot.empty) {
        console.log("[DELETE_FACILITIES] No facilities found");
        response.json({success: true, deleted: 0, message: "No facilities to delete"});
        return;
      }

      const batch = admin.firestore().batch();
      snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });

      await batch.commit();

      console.log(`[DELETE_FACILITIES] Successfully deleted ${snapshot.docs.length} facilities`);
      response.json({
        success: true,
        deleted: snapshot.docs.length,
        message: `Successfully deleted ${snapshot.docs.length} facilities`,
      });
    } catch (error) {
      console.error("[DELETE_FACILITIES] Error:", error);
      response.status(500).json({success: false, error: error.message});
    }
  });
});
