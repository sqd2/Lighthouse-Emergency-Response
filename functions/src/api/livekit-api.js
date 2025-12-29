/**
 * LiveKit API Module
 *
 * I handle LiveKit WebRTC token generation for video calls.
 * I verify user authorization before generating access tokens for call rooms.
 *
 * Functions:
 * - generateLiveKitToken: Generates and returns LiveKit access tokens for authorized users
 */

const {onCall} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {AccessToken} = require("livekit-server-sdk");

// LiveKit WebRTC configuration - loaded from environment variables
const LIVEKIT_URL = process.env.LIVEKIT_URL || "wss://lighthouse-webrtc-a5tfjg76.livekit.cloud";
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;

// Validate environment variables are set
if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
  console.error("[ERROR] LiveKit credentials not found in environment variables!");
  console.error("Please set LIVEKIT_API_KEY and LIVEKIT_API_SECRET in functions/.env");
}

/**
 * Cloud Function: Generate LiveKit access token for WebRTC calls
 * Callable function that verifies user authorization and generates token
 */
exports.generateLiveKitToken = onCall(async (request) => {
  try {
    // Get authenticated user
    const userId = request.auth?.uid;
    if (!userId) {
      throw new Error("User must be authenticated");
    }

    console.log(`[VIDEO] Generating LiveKit token for user ${userId}`);

    const {alertId, callId, roomName} = request.data;

    // Validate input
    if (!alertId || !callId || !roomName) {
      throw new Error("Missing required parameters: alertId, callId, roomName");
    }

    console.log(`[INFO] Alert ID: ${alertId}, Call ID: ${callId}, Room: ${roomName}`);

    // Verify user is authorized (part of the alert)
    const alertDoc = await admin.firestore()
        .collection("emergency_alerts")
        .doc(alertId)
        .get();

    if (!alertDoc.exists) {
      throw new Error("Alert not found");
    }

    const alertData = alertDoc.data();
    const isAuthorized =
      userId === alertData.userId || // Citizen
      userId === alertData.acceptedBy; // Dispatcher

    if (!isAuthorized) {
      console.error(`[ERROR] User ${userId} not authorized for alert ${alertId}`);
      throw new Error("User not authorized for this alert");
    }

    // Get call data to verify
    const callDoc = await admin.firestore()
        .collection("emergency_alerts")
        .doc(alertId)
        .collection("calls")
        .doc(callId)
        .get();

    if (!callDoc.exists) {
      throw new Error("Call not found");
    }

    const callData = callDoc.data();

    // Verify user is participant in the call
    if (userId !== callData.callerId && userId !== callData.receiverId) {
      console.error(`[ERROR] User ${userId} not participant in call ${callId}`);
      throw new Error("User not a participant in this call");
    }

    console.log(`[SUCCESS] User authorized for call`);

    // Generate LiveKit access token
    const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
      identity: userId,
      ttl: "2h", // Token valid for 2 hours
    });

    // Grant permissions
    at.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });

    const token = await at.toJwt();

    console.log(`[SUCCESS] Generated token for ${userId} in room ${roomName}`);

    return {
      token: token,
      serverUrl: LIVEKIT_URL,
    };
  } catch (error) {
    console.error("[ERROR] Error generating LiveKit token:", error);
    throw new Error(`Failed to generate token: ${error.message}`);
  }
});
