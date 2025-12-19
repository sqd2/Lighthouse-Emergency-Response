const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const cors = require("cors")({origin: true});

// Initialize Firebase Admin SDK
admin.initializeApp();

const GOOGLE_API_KEY = "AIzaSyCvvz3UmQXQR9PzRUeYlNu2wJqpxG8FvuQ";

/**
 * Cloud Function to proxy Google Places API requests
 * This avoids CORS issues when calling from web browsers
 */
exports.searchNearbyPlaces = onRequest((request, response) => {
  cors(request, response, async () => {
    try {
      // Only allow POST requests
      if (request.method !== "POST") {
        response.status(405).send("Method Not Allowed");
        return;
      }

      const {latitude, longitude, radius, type} = request.body;

      // Validate input
      if (!latitude || !longitude || !radius || !type) {
        response.status(400).json({
          error: "Missing required parameters: latitude, longitude, radius, type",
        });
        return;
      }

      // Build Google Places API URL
      const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${latitude},${longitude}&radius=${radius}&type=${type}&key=${GOOGLE_API_KEY}`;

      // Fetch from Google Places API
      const apiResponse = await fetch(url);
      const data = await apiResponse.json();

      if (data.status === "REQUEST_DENIED") {
        response.status(403).json({
          error: "API Key Error",
          message: data.error_message,
        });
        return;
      }

      // Return the results
      response.status(200).json({
        status: data.status,
        results: data.results || [],
      });
    } catch (error) {
      console.error("Error fetching places:", error);
      response.status(500).json({
        error: "Internal Server Error",
        message: error.message,
      });
    }
  });
});

/**
 * Cloud Function to proxy Google Directions API requests
 * This avoids CORS issues when calling from web browsers
 */
exports.getDirections = onRequest((request, response) => {
  cors(request, response, async () => {
    try {
      // Only allow POST requests
      if (request.method !== "POST") {
        response.status(405).send("Method Not Allowed");
        return;
      }

      const {originLat, originLng, destLat, destLng} = request.body;

      // Validate input
      if (!originLat || !originLng || !destLat || !destLng) {
        response.status(400).json({
          error: "Missing required parameters",
        });
        return;
      }

      // Build Google Directions API URL
      const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${originLat},${originLng}&destination=${destLat},${destLng}&key=${GOOGLE_API_KEY}`;

      // Fetch from Google Directions API
      const apiResponse = await fetch(url);
      const data = await apiResponse.json();

      if (data.status === "REQUEST_DENIED") {
        response.status(403).json({
          error: "API Key Error",
          message: data.error_message,
        });
        return;
      }

      // Return the results
      response.status(200).json(data);
    } catch (error) {
      console.error("Error fetching directions:", error);
      response.status(500).json({
        error: "Internal Server Error",
        message: error.message,
      });
    }
  });
});

/**
 * Test function to send a notification to a user by email
 * Call this via HTTP to test if notifications work
 */
exports.testNotification = onRequest(async (request, response) => {
  cors(request, response, async () => {
    try {
      const {userEmail} = request.body;

      if (!userEmail) {
        response.status(400).json({error: "userEmail required"});
        return;
      }

      // Find user by email
      const usersSnapshot = await admin.firestore()
          .collection("users")
          .where("email", "==", userEmail)
          .limit(1)
          .get();

      if (usersSnapshot.empty) {
        response.status(404).json({error: `User ${userEmail} not found`});
        return;
      }

      const userDoc = usersSnapshot.docs[0];
      const fcmToken = userDoc.data().fcmToken;

      if (!fcmToken) {
        response.status(400).json({
          error: `User ${userEmail} has no FCM token`,
          userId: userDoc.id,
        });
        return;
      }

      // Send test notification (data-only)
      const message = {
        data: {
          type: "test",
          title: "🧪 Test Notification",
          body: "This is a test notification from Firebase Functions!",
        },
        token: fcmToken,
      };

      const result = await admin.messaging().send(message);

      response.status(200).json({
        success: true,
        message: `Test notification sent to ${userEmail}`,
        messageId: result,
        userId: userDoc.id,
        fcmToken: fcmToken,
      });
    } catch (error) {
      console.error("Error sending test notification:", error);
      response.status(500).json({
        error: error.message,
        code: error.code,
      });
    }
  });
});

/**
 * Sends a notification to a specific user (all their devices)
 */
async function sendNotificationToUser(userId, title, body, data = {}) {
  try {
    console.log(`📤 Attempting to send notification to user ${userId}`);
    console.log(`📋 Title: ${title}`);
    console.log(`📋 Body: ${body}`);

    // Get user's FCM tokens
    const userDoc = await admin.firestore().collection("users").doc(userId).get();

    if (!userDoc.exists) {
      console.log(`❌ User ${userId} not found in Firestore`);
      return;
    }

    const userData = userDoc.data();
    console.log(`✅ User found: ${userData.email || userId}`);
    console.log(`📱 Role: ${userData.role}`);

    // Get all tokens (new array format)
    const fcmTokens = userData.fcmTokens || [];
    const legacyToken = userData.fcmToken; // Fallback for old single-token format

    console.log(`🔔 Has ${fcmTokens.length} device token(s)`);
    console.log(`🔔 Has legacy token: ${!!legacyToken}`);

    // Combine tokens: new array format + legacy single token (if exists and not in array)
    const allTokens = [...fcmTokens];
    if (legacyToken && !fcmTokens.some((t) => t.token === legacyToken)) {
      allTokens.push({token: legacyToken, platform: "unknown"});
    }

    if (allTokens.length === 0) {
      console.log(`❌ User ${userId} (${userData.email}) has no FCM tokens`);
      return;
    }

    // Send to all devices
    console.log(`🚀 Sending to ${allTokens.length} device(s)...`);
    const invalidTokens = [];

    for (let i = 0; i < allTokens.length; i++) {
      const tokenData = allTokens[i];
      const token = tokenData.token;
      const platform = tokenData.platform || "unknown";

      console.log(`  📲 Device ${i + 1}/${allTokens.length} (${platform}): ${token.substring(0, 20)}...`);

      try {
        // Send data-only message (no notification field)
        // This prevents Firebase from auto-showing notifications
        // Our custom handlers will display them instead
        const message = {
          data: {
            ...data,
            title: title,
            body: body,
          },
          token: token,
        };

        const response = await admin.messaging().send(message);
        console.log(`  ✅ Sent to device ${i + 1} (${platform}), Message ID: ${response}`);
      } catch (error) {
        console.error(`  ❌ Failed to send to device ${i + 1} (${platform}):`, error.code);

        // Track invalid tokens for cleanup
        if (error.code === "messaging/invalid-registration-token" ||
            error.code === "messaging/registration-token-not-registered") {
          console.log(`  🗑️ Marking token for removal: ${token.substring(0, 20)}...`);
          invalidTokens.push(token);
        }
      }
    }

    // Clean up invalid tokens
    if (invalidTokens.length > 0) {
      console.log(`🧹 Removing ${invalidTokens.length} invalid token(s)...`);
      const validTokens = fcmTokens.filter((t) => !invalidTokens.includes(t.token));
      await userDoc.ref.update({
        fcmTokens: validTokens,
      });
      console.log(`✅ Cleaned up invalid tokens. Remaining: ${validTokens.length}`);
    }

    console.log(`✅ Finished sending notifications to ${userData.email || userId}`);
  } catch (error) {
    console.error(`❌ Error sending notification to ${userId}:`, error.code, error.message);
  }
}

/**
 * Cloud Function: Notify active dispatchers when a new SOS is created
 */
exports.onSOSCreated = onDocumentCreated("emergency_alerts/{alertId}", async (event) => {
  const alertData = event.data.data();
  const alertId = event.params.alertId;

  console.log(`🚨 New SOS created: ${alertId} from ${alertData.userEmail}`);

  try {
    // Get all active dispatchers
    console.log("🔍 Searching for active dispatchers...");
    const dispatchersSnapshot = await admin.firestore()
        .collection("users")
        .where("role", "==", "dispatcher")
        .where("isActive", "==", true)
        .get();

    console.log(`📊 Found ${dispatchersSnapshot.size} active dispatcher(s)`);

    if (dispatchersSnapshot.empty) {
      console.log("❌ No active dispatchers found");
      return;
    }

    // Log each dispatcher
    dispatchersSnapshot.docs.forEach((doc) => {
      const data = doc.data();
      console.log(`👤 Dispatcher: ${data.email}, ID: ${doc.id}, Active: ${data.isActive}, Has token: ${!!data.fcmToken}`);
    });

    // Send notification to each active dispatcher
    const notificationPromises = dispatchersSnapshot.docs.map((doc) => {
      return sendNotificationToUser(
          doc.id,
          "🚨 New Emergency Alert",
          `Emergency SOS from ${alertData.userEmail}`,
          {
            type: "new_sos",
            alertId: alertId,
          },
      );
    });

    await Promise.all(notificationPromises);
    console.log(`✅ Notified ${dispatchersSnapshot.size} active dispatcher(s)`);
  } catch (error) {
    console.error("❌ Error in onSOSCreated:", error);
  }
});

/**
 * Cloud Function: Notify citizen when dispatcher accepts their SOS
 */
exports.onSOSAccepted = onDocumentUpdated("emergency_alerts/{alertId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const alertId = event.params.alertId;

  // Check if status changed from 'active' to 'accepted'
  const wasActive = beforeData.status === "active";
  const nowAccepted = afterData.status === "accepted";
  const hasDispatcher = afterData.acceptedBy && !beforeData.acceptedBy;

  if (wasActive && nowAccepted && hasDispatcher) {
    console.log(`SOS ${alertId} accepted by ${afterData.acceptedByEmail}`);

    try {
      const citizenId = afterData.userId;

      await sendNotificationToUser(
          citizenId,
          "✅ Help is on the way!",
          `Dispatcher ${afterData.acceptedByEmail} has accepted your emergency request`,
          {
            type: "sos_accepted",
            alertId: alertId,
            dispatcherEmail: afterData.acceptedByEmail,
          },
      );

      console.log(`Notified citizen ${citizenId} of SOS acceptance`);
    } catch (error) {
      console.error("Error in onSOSAccepted:", error);
    }
  }
});

/**
 * Cloud Function: Notify other party when a new message is sent
 */
exports.onMessageSent = onDocumentCreated("emergency_alerts/{alertId}/messages/{messageId}", async (event) => {
  const messageData = event.data.data();
  const alertId = event.params.alertId;

  console.log(`💬 New message in alert ${alertId} from ${messageData.senderEmail} (role: ${messageData.senderRole})`);

  try {
    // Get alert data to find the other party
    const alertDoc = await admin.firestore()
        .collection("emergency_alerts")
        .doc(alertId)
        .get();

    if (!alertDoc.exists) {
      console.log(`❌ Alert ${alertId} not found`);
      return;
    }

    const alertData = alertDoc.data();
    console.log(`📋 Alert status: ${alertData.status}`);
    console.log(`👤 Citizen: ${alertData.userEmail} (ID: ${alertData.userId})`);
    console.log(`👮 Dispatcher: ${alertData.acceptedByEmail || 'none'} (ID: ${alertData.acceptedBy || 'none'})`);

    // Determine recipient based on sender role
    let recipientId;
    let recipientName;

    if (messageData.senderRole === "citizen") {
      // Send to dispatcher
      recipientId = alertData.acceptedBy;
      recipientName = alertData.acceptedByEmail;
      console.log(`📤 Sender is citizen, sending to dispatcher: ${recipientName}`);
    } else {
      // Send to citizen
      recipientId = alertData.userId;
      recipientName = alertData.userEmail;
      console.log(`📤 Sender is dispatcher, sending to citizen: ${recipientName}`);
    }

    if (!recipientId) {
      console.log("❌ No recipient found for message notification");
      return;
    }

    console.log(`🎯 Recipient ID: ${recipientId}`);

    // Prepare notification content
    let title = `💬 Message from ${messageData.senderEmail}`;
    let body;

    switch (messageData.messageType) {
      case "image":
        body = "📷 Sent an image";
        break;
      case "voice":
        body = "🎤 Sent a voice message";
        break;
      default:
        body = messageData.message || "Sent a message";
        // Truncate long messages
        if (body.length > 50) {
          body = body.substring(0, 50) + "...";
        }
    }

    console.log(`📬 Notification title: ${title}`);
    console.log(`📬 Notification body: ${body}`);

    await sendNotificationToUser(
        recipientId,
        title,
        body,
        {
          type: "new_message",
          alertId: alertId,
          messageId: event.params.messageId,
        },
    );

    console.log(`✅ Notified ${recipientName} of new message`);
  } catch (error) {
    console.error("❌ Error in onMessageSent:", error);
  }
});
