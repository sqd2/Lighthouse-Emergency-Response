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
 * Sends a notification to a specific user
 */
async function sendNotificationToUser(userId, title, body, data = {}) {
  try {
    // Get user's FCM token
    const userDoc = await admin.firestore().collection("users").doc(userId).get();

    if (!userDoc.exists) {
      console.log(`User ${userId} not found`);
      return;
    }

    const fcmToken = userDoc.data().fcmToken;

    if (!fcmToken) {
      console.log(`User ${userId} has no FCM token`);
      return;
    }

    // Send notification
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: data,
      token: fcmToken,
    };

    const response = await admin.messaging().send(message);
    console.log(`Notification sent to ${userId}:`, response);
  } catch (error) {
    console.error(`Error sending notification to ${userId}:`, error);
  }
}

/**
 * Cloud Function: Notify active dispatchers when a new SOS is created
 */
exports.onSOSCreated = onDocumentCreated("emergency_alerts/{alertId}", async (event) => {
  const alertData = event.data.data();
  const alertId = event.params.alertId;

  console.log(`New SOS created: ${alertId}`);

  try {
    // Get all active dispatchers
    const dispatchersSnapshot = await admin.firestore()
        .collection("users")
        .where("role", "==", "dispatcher")
        .where("isActive", "==", true)
        .get();

    if (dispatchersSnapshot.empty) {
      console.log("No active dispatchers found");
      return;
    }

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
    console.log(`Notified ${dispatchersSnapshot.size} active dispatchers`);
  } catch (error) {
    console.error("Error in onSOSCreated:", error);
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

  console.log(`New message in alert ${alertId} from ${messageData.senderEmail}`);

  try {
    // Get alert data to find the other party
    const alertDoc = await admin.firestore()
        .collection("emergency_alerts")
        .doc(alertId)
        .get();

    if (!alertDoc.exists) {
      console.log(`Alert ${alertId} not found`);
      return;
    }

    const alertData = alertDoc.data();

    // Determine recipient based on sender role
    let recipientId;
    let recipientName;

    if (messageData.senderRole === "citizen") {
      // Send to dispatcher
      recipientId = alertData.acceptedBy;
      recipientName = alertData.acceptedByEmail;
    } else {
      // Send to citizen
      recipientId = alertData.userId;
      recipientName = alertData.userEmail;
    }

    if (!recipientId) {
      console.log("No recipient found for message notification");
      return;
    }

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

    console.log(`Notified ${recipientName} of new message`);
  } catch (error) {
    console.error("Error in onMessageSent:", error);
  }
});
