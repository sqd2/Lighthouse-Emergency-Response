const {onRequest, onCall} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {defineString} = require("firebase-functions/params");
const admin = require("firebase-admin");
const cors = require("cors")({origin: true});
const {AccessToken} = require("livekit-server-sdk");
const nodemailer = require("nodemailer");
const {Resend} = require("resend");

// Import modularized helper functions
const {getEmergencyContact, notifyEmergencyContact} = require("./src/helpers/emergency-contact");
const {getUserName, formatUserDisplay} = require("./src/helpers/user-helpers");
const {sendNotificationToUser} = require("./src/helpers/notification-helpers");
const {calculateDistance, toRadians} = require("./src/helpers/distance-helpers");

// Define environment parameters
const resendApiKey = defineString("RESEND_API_KEY");
const twilioAccountSid = defineString("TWILIO_ACCOUNT_SID");
const twilioAuthToken = defineString("TWILIO_AUTH_TOKEN");
const twilioPhoneNumber = defineString("TWILIO_PHONE_NUMBER");

// Initialize Firebase Admin SDK
admin.initializeApp();

const GOOGLE_API_KEY = "AIzaSyCvvz3UmQXQR9PzRUeYlNu2wJqpxG8FvuQ";

// LiveKit WebRTC configuration
const LIVEKIT_URL = "wss://lighthouse-webrtc-a5tfjg76.livekit.cloud";
const LIVEKIT_API_KEY = "APIyPzoZFJ78KTh";
const LIVEKIT_API_SECRET = "EyUTouWgpzAEO6WF3NrHiwBsSQ9mRQ6eoyyyf920LGA";


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
          title: "[TEST] Test Notification",
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
 * Notify active dispatchers when a new SOS alert is created.
 * Calculates proximity and sends notifications to all active dispatchers.
 */
exports.onSOSCreated = onDocumentCreated("emergency_alerts/{alertId}", async (event) => {
  const alertData = event.data.data();
  const alertId = event.params.alertId;

  console.log(`[ALERT] New SOS created: ${alertId} from ${alertData.userEmail}`);

  // Get citizen's name for notifications
  const citizenName = await getUserName(alertData.userId);
  const citizenDisplay = formatUserDisplay(citizenName, alertData.userEmail);

  // Extract lat/lon from GeoPoint or separate fields (backward compatibility)
  let alertLat, alertLon;
  if (alertData.location) {
    // New format: GeoPoint in location field
    alertLat = alertData.location.latitude;
    alertLon = alertData.location.longitude;
  } else if (alertData.lat && alertData.lon) {
    // Old format: separate lat/lon fields
    alertLat = alertData.lat;
    alertLon = alertData.lon;
  }

  console.log(`[LOCATION] Alert location: ${alertLat}, ${alertLon}`);

  // Validate alert location data
  if (!alertLat || !alertLon || isNaN(alertLat) || isNaN(alertLon)) {
    console.error(`[ERROR] Invalid alert location data: lat=${alertLat}, lon=${alertLon}`);
    return;
  }

  try {
    // Get all active dispatchers
    console.log("[SEARCH] Searching for active dispatchers...");
    const dispatchersSnapshot = await admin.firestore()
        .collection("users")
        .where("role", "==", "dispatcher")
        .where("isActive", "==", true)
        .get();

    console.log(`[DATA] Found ${dispatchersSnapshot.size} active dispatcher(s)`);

    if (dispatchersSnapshot.empty) {
      console.log("[ERROR] No active dispatchers found");
      return;
    }

    // Calculate distance for each dispatcher
    const dispatchersWithDistance = [];

    dispatchersSnapshot.docs.forEach((doc) => {
      const data = doc.data();
      const dispatcherId = doc.id;

      // Check if dispatcher has location data
      if (data.lastKnownLocation) {
        const dispatcherLat = data.lastKnownLocation.latitude;
        const dispatcherLon = data.lastKnownLocation.longitude;

        // Validate dispatcher location
        if (isNaN(dispatcherLat) || isNaN(dispatcherLon)) {
          console.log(`[WARN] Dispatcher ${data.email} has invalid location: lat=${dispatcherLat}, lon=${dispatcherLon} - skipping`);
          return;
        }

        // Calculate distance from dispatcher to alert
        const distance = calculateDistance(
            dispatcherLat,
            dispatcherLon,
            alertLat,
            alertLon,
        );

        // Validate calculated distance
        if (isNaN(distance)) {
          console.error(`[ERROR] Distance calculation returned NaN for dispatcher ${data.email}`);
          console.error(`   Dispatcher: lat=${dispatcherLat}, lon=${dispatcherLon}`);
          console.error(`   Alert: lat=${alertLat}, lon=${alertLon}`);
          return;
        }

        dispatchersWithDistance.push({
          id: dispatcherId,
          email: data.email,
          distance: distance,
          hasToken: !!(data.fcmToken || (data.fcmTokens && data.fcmTokens.length > 0)),
        });

        console.log(`[USER] Dispatcher: ${data.email}, Distance: ${distance.toFixed(2)} km`);
      } else {
        console.log(`[WARN] Dispatcher ${data.email} has no location data - skipping`);
      }
    });

    if (dispatchersWithDistance.length === 0) {
      console.log("[ERROR] No dispatchers with location data found");
      return;
    }

    // Sort by distance (nearest first) - for logging purposes
    dispatchersWithDistance.sort((a, b) => a.distance - b.distance);

    // Notify ALL dispatchers (no distance limitation)
    console.log(`[LOCATION] Notifying ALL ${dispatchersWithDistance.length} active dispatcher(s):`);
    dispatchersWithDistance.forEach((d, index) => {
      console.log(`  ${index + 1}. ${d.email} - ${d.distance.toFixed(2)} km away`);
    });

    // Send notification to ALL active dispatchers
    const notificationPromises = dispatchersWithDistance.map((dispatcher) => {
      const distanceText = dispatcher.distance < 1 ?
        `${(dispatcher.distance * 1000).toFixed(0)} m` :
        `${dispatcher.distance.toFixed(1)} km`;

      return sendNotificationToUser(
          dispatcher.id,
          "[ALERT] New Emergency Alert",
          `Emergency SOS from ${citizenDisplay} - ${distanceText} away`,
          {
            type: "new_sos",
            alertId: alertId,
            distance: String(dispatcher.distance.toFixed(2)),
            distanceText: distanceText,
          },
      );
    });

    await Promise.all(notificationPromises);
    console.log(`[SUCCESS] Notified ${dispatchersWithDistance.length} dispatcher(s) - ALL active dispatchers notified`);

    // Notify emergency contact
    console.log("[EMERGENCY_CONTACT] Attempting to notify emergency contact for user:", alertData.userId);
    try {
      const locationUrl = `https://www.google.com/maps?q=${alertLat},${alertLon}`;
      const emergencyMessage = `EMERGENCY ALERT: ${citizenName || alertData.userEmail} has initiated an SOS.\n\nDescription: ${alertData.description || "No description provided"}\n\nLocation: ${locationUrl}\n\nStatus: Emergency services have been notified.`;

      await notifyEmergencyContact(
          alertData.userId,
          citizenName,
          alertData.userEmail,
          emergencyMessage,
          "[URGENT] Emergency SOS Initiated",
      );
      console.log("[EMERGENCY_CONTACT] Emergency contact notification process completed");
    } catch (emergencyContactError) {
      console.error("[EMERGENCY_CONTACT] Failed to notify emergency contact:", emergencyContactError);
    }
  } catch (error) {
    console.error("[ERROR] Error in onSOSCreated:", error);
  }
});

/**
 * Cloud Function: Notify citizen when dispatcher accepts their SOS
 */
exports.onSOSAccepted = onDocumentUpdated("emergency_alerts/{alertId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const alertId = event.params.alertId;

  // Check if dispatcher just accepted (status: pending → active)
  const wasPending = beforeData.status === "pending";
  const nowActive = afterData.status === "active";
  const hasDispatcher = afterData.acceptedBy && !beforeData.acceptedBy;

  if (wasPending && nowActive && hasDispatcher) {
    console.log(`[SUCCESS] SOS ${alertId} accepted by ${afterData.acceptedByEmail}`);

    try {
      const citizenId = afterData.userId;

      // Get dispatcher's name for notification
      const dispatcherName = await getUserName(afterData.acceptedBy);
      const dispatcherDisplay = formatUserDisplay(dispatcherName, afterData.acceptedByEmail);

      await sendNotificationToUser(
          citizenId,
          "[SUCCESS] Help is on the way!",
          `Dispatcher ${dispatcherDisplay} has accepted your emergency request`,
          {
            type: "sos_accepted",
            alertId: alertId,
            dispatcherEmail: afterData.acceptedByEmail,
          },
      );

      console.log(`[DEVICE] Notified citizen ${citizenId} of SOS acceptance`);

      // Notify emergency contact
      const citizenName = await getUserName(afterData.userId);
      const updateMessage = `SOS UPDATE: A dispatcher (${dispatcherDisplay}) has accepted the emergency alert from ${citizenName || afterData.userEmail}.\n\nStatus: Help is on the way!\n\nAlert ID: ${alertId}`;

      await notifyEmergencyContact(
          afterData.userId,
          citizenName,
          afterData.userEmail,
          updateMessage,
          "[UPDATE] Emergency Help Accepted",
      );
    } catch (error) {
      console.error("[ERROR] Error in onSOSAccepted:", error);
    }
  }
});

/**
 * Cloud Function: Notify citizen when dispatcher arrives at scene
 */
exports.onDispatcherArrived = onDocumentUpdated("emergency_alerts/{alertId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const alertId = event.params.alertId;

  // Check if status changed to 'arrived'
  const statusChanged = beforeData.status === "active" && afterData.status === "arrived";

  if (statusChanged) {
    console.log(`[TARGET] Dispatcher arrived at alert ${alertId}`);

    try {
      const citizenId = afterData.userId;
      const dispatcherEmail = afterData.acceptedByEmail || "Dispatcher";

      // Get dispatcher's name for notification
      const dispatcherName = afterData.acceptedBy ? await getUserName(afterData.acceptedBy) : dispatcherEmail;
      const dispatcherDisplay = formatUserDisplay(dispatcherName, dispatcherEmail);

      await sendNotificationToUser(
          citizenId,
          "[ALERT] Dispatcher Arrived",
          `${dispatcherDisplay} has arrived at your location`,
          {
            type: "dispatcher_arrived",
            alertId: alertId,
            dispatcherEmail: dispatcherEmail,
          },
      );

      console.log(`[DEVICE] Notified citizen ${citizenId} of dispatcher arrival`);

      // Notify emergency contact
      const citizenName = await getUserName(afterData.userId);
      const updateMessage = `SOS UPDATE: Dispatcher (${dispatcherDisplay}) has arrived at the emergency location for ${citizenName || afterData.userEmail}.\n\nStatus: Help has arrived!\n\nAlert ID: ${alertId}`;

      await notifyEmergencyContact(
          afterData.userId,
          citizenName,
          afterData.userEmail,
          updateMessage,
          "[UPDATE] Emergency Help Arrived",
      );
    } catch (error) {
      console.error("[ERROR] Error in onDispatcherArrived:", error);
    }
  }
});

/**
 * Cloud Function: Notify dispatcher when citizen cancels SOS
 */
exports.onSOSCancelled = onDocumentUpdated("emergency_alerts/{alertId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const alertId = event.params.alertId;

  // Check if status changed to 'cancelled'
  const wasCancelled = afterData.status === "cancelled" && beforeData.status !== "cancelled";

  if (wasCancelled) {
    console.log(`[ERROR] SOS ${alertId} cancelled by citizen`);

    try {
      const dispatcherId = afterData.acceptedBy;
      const citizenEmail = afterData.userEmail || "Citizen";
      const cancellationReason = afterData.cancellationReason || "No reason provided";

      // Only notify if a dispatcher had accepted
      if (dispatcherId) {
        // Get citizen's name for notification
        const citizenName = await getUserName(afterData.userId);
        const citizenDisplay = formatUserDisplay(citizenName, citizenEmail);

        await sendNotificationToUser(
            dispatcherId,
            "[WARN] Alert Cancelled",
            `${citizenDisplay} cancelled their emergency alert. Reason: ${cancellationReason}`,
            {
              type: "sos_cancelled",
              alertId: alertId,
              citizenEmail: citizenEmail,
              reason: cancellationReason,
            },
        );

        console.log(`[DEVICE] Notified dispatcher ${dispatcherId} of cancellation`);
      }

      // Notify emergency contact
      const citizenName = await getUserName(afterData.userId);
      const updateMessage = `SOS UPDATE: The emergency alert from ${citizenName || citizenEmail} has been CANCELLED.\n\nReason: ${cancellationReason}\n\nStatus: Alert resolved - No longer active.\n\nAlert ID: ${alertId}`;

      await notifyEmergencyContact(
          afterData.userId,
          citizenName,
          citizenEmail,
          updateMessage,
          "[RESOLVED] Emergency Cancelled",
      );
    } catch (error) {
      console.error("[ERROR] Error in onSOSCancelled:", error);
    }
  }
});

/**
 * Cloud Function: Notify citizen when dispatcher resolves SOS
 */
exports.onSOSResolved = onDocumentUpdated("emergency_alerts/{alertId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const alertId = event.params.alertId;

  // Check if status changed to 'resolved'
  const wasResolved = afterData.status === "resolved" && beforeData.status !== "resolved";

  if (wasResolved) {
    console.log(`[SUCCESS] SOS ${alertId} marked as resolved`);

    try {
      const citizenId = afterData.userId;
      const dispatcherEmail = afterData.acceptedByEmail || "Dispatcher";

      // Get dispatcher's name for notification
      const dispatcherName = afterData.acceptedBy ? await getUserName(afterData.acceptedBy) : dispatcherEmail;
      const dispatcherDisplay = formatUserDisplay(dispatcherName, dispatcherEmail);

      await sendNotificationToUser(
          citizenId,
          "[SUCCESS] Emergency Resolved",
          `${dispatcherDisplay} has marked your emergency as resolved`,
          {
            type: "sos_resolved",
            alertId: alertId,
            dispatcherEmail: dispatcherEmail,
          },
      );

      console.log(`[DEVICE] Notified citizen ${citizenId} of resolution`);

      // Notify emergency contact
      const citizenName = await getUserName(afterData.userId);
      const updateMessage = `SOS UPDATE: The emergency alert from ${citizenName || afterData.userEmail} has been RESOLVED.\n\nDispatcher: ${dispatcherDisplay}\n\nStatus: Emergency successfully handled - All clear!\n\nAlert ID: ${alertId}`;

      await notifyEmergencyContact(
          afterData.userId,
          citizenName,
          afterData.userEmail,
          updateMessage,
          "[RESOLVED] Emergency Completed",
      );
    } catch (error) {
      console.error("[ERROR] Error in onSOSResolved:", error);
    }
  }
});

/**
 * Cloud Function: Notify other party when a new message is sent
 */
exports.onMessageSent = onDocumentCreated("emergency_alerts/{alertId}/messages/{messageId}", async (event) => {
  const messageData = event.data.data();
  const alertId = event.params.alertId;

  console.log(`[MSG] New message in alert ${alertId} from ${messageData.senderEmail} (role: ${messageData.senderRole})`);

  try {
    // Get alert data to find the other party
    const alertDoc = await admin.firestore()
        .collection("emergency_alerts")
        .doc(alertId)
        .get();

    if (!alertDoc.exists) {
      console.log(`[ERROR] Alert ${alertId} not found`);
      return;
    }

    const alertData = alertDoc.data();
    console.log(`[INFO] Alert status: ${alertData.status}`);
    console.log(`[USER] Citizen: ${alertData.userEmail} (ID: ${alertData.userId})`);
    console.log(`[DISPATCHER] Dispatcher: ${alertData.acceptedByEmail || 'none'} (ID: ${alertData.acceptedBy || 'none'})`);

    // Determine recipient based on sender role
    let recipientId;
    let recipientName;

    if (messageData.senderRole === "citizen") {
      // Send to dispatcher
      recipientId = alertData.acceptedBy;
      recipientName = alertData.acceptedByEmail;
      console.log(`[SEND] Sender is citizen, sending to dispatcher: ${recipientName}`);
    } else {
      // Send to citizen
      recipientId = alertData.userId;
      recipientName = alertData.userEmail;
      console.log(`[SEND] Sender is dispatcher, sending to citizen: ${recipientName}`);
    }

    if (!recipientId) {
      console.log("[ERROR] No recipient found for message notification");
      return;
    }

    console.log(`[TARGET] Recipient ID: ${recipientId}`);

    // Prepare notification content
    let title = `[MSG] Message from ${messageData.senderEmail}`;
    let body;

    switch (messageData.messageType) {
      case "image":
        body = "[IMAGE] Sent an image";
        break;
      case "voice":
        body = "[AUDIO] Sent a voice message";
        break;
      default:
        body = messageData.message || "Sent a message";
        // Truncate long messages
        if (body.length > 50) {
          body = body.substring(0, 50) + "...";
        }
    }

    console.log(`[NOTIFICATION] Notification title: ${title}`);
    console.log(`[NOTIFICATION] Notification body: ${body}`);

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

    console.log(`[SUCCESS] Notified ${recipientName} of new message`);
  } catch (error) {
    console.error("[ERROR] Error in onMessageSent:", error);
  }
});

/**
 * Cloud Function: Notify receiver when incoming call is created
 */
exports.onCallCreated = onDocumentCreated("emergency_alerts/{alertId}/calls/{callId}", async (event) => {
  const callData = event.data.data();
  const alertId = event.params.alertId;
  const callId = event.params.callId;

  console.log(`[CALL] New call created: ${callId} in alert ${alertId}`);
  console.log(`[INFO] Status: ${callData.status}, Type: ${callData.type}`);

  // Only send notification if call is ringing
  if (callData.status !== "ringing") {
    console.log(`[INFO] Call not ringing (status: ${callData.status}), skipping notification`);
    return;
  }

  try {
    const receiverId = callData.receiverId;
    const callerName = callData.callerName || "Unknown";
    const callerEmail = callData.callerEmail || "";
    const callType = callData.type === "video" ? "Video" : "Voice";
    const callerRole = callData.callerRole === "dispatcher" ? "Dispatcher" : "Citizen";

    // Format caller display as "Name (email)"
    const callerDisplay = formatUserDisplay(callerName, callerEmail);

    console.log(`[DEVICE] Sending incoming call notification to ${receiverId}`);
    console.log(`[CALL] ${callType} call from ${callerDisplay}`);

    await sendNotificationToUser(
        receiverId,
        `[CALL] Incoming ${callType} Call`,
        `Incoming call from ${callerDisplay}`,
        {
          type: "incoming_call",
          alertId: alertId,
          callId: callId,
          callerId: callData.callerId,
          callerName: callerName,
          callerRole: callData.callerRole,
          callType: callData.type,
          roomName: callData.roomName,
        },
    );

    console.log(`[SUCCESS] Sent incoming call notification to ${receiverId}`);
  } catch (error) {
    console.error("[ERROR] Error in onCallCreated:", error);
  }
});

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
      serverUrl: "wss://lighthouse-webrtc-a5tfjg76.livekit.cloud",
    };
  } catch (error) {
    console.error("[ERROR] Error generating LiveKit token:", error);
    throw new Error(`Failed to generate token: ${error.message}`);
  }
});

/**
 * Send SMS notification to emergency contact when SOS alert is created.
 * Requires Twilio configuration via Firebase environment variables.
 *
 * Configuration:
 *   firebase functions:config:set twilio.account_sid="YOUR_SID"
 *   firebase functions:config:set twilio.auth_token="YOUR_TOKEN"
 *   firebase functions:config:set twilio.phone_number="+1234567890"
 */
exports.sendEmergencyContactSMS = onDocumentCreated(
    "emergency_alerts/{alertId}",
    async (event) => {
      const alertData = event.data.data();
      const alertId = event.params.alertId;
      const userId = alertData.userId;
      const userEmail = alertData.userEmail;

      console.log(`[SMS] [SMS] New SOS alert created: ${alertId} by ${userEmail}`);

      try {
        // Check if Twilio is configured
        const functions = require("firebase-functions");
        const twilioConfig = functions.config().twilio;

        if (!twilioConfig || !twilioConfig.account_sid || !twilioConfig.auth_token || !twilioConfig.phone_number) {
          console.warn("[WARN] [SMS] Twilio not configured. Skipping SMS notification.");
          console.warn("[WARN] [SMS] To enable SMS, run:");
          console.warn('[WARN] [SMS]   firebase functions:config:set twilio.account_sid="YOUR_SID"');
          console.warn('[WARN] [SMS]   firebase functions:config:set twilio.auth_token="YOUR_TOKEN"');
          console.warn('[WARN] [SMS]   firebase functions:config:set twilio.phone_number="+1234567890"');
          return null;
        }

        const accountSid = twilioConfig.account_sid;
        const authToken = twilioConfig.auth_token;
        const fromPhoneNumber = twilioConfig.phone_number;

        // Initialize Twilio client
        const twilio = require("twilio");
        const twilioClient = twilio(accountSid, authToken);

        // Get user's medical info with emergency contact
        const medicalInfoDoc = await admin.firestore()
            .collection("users")
            .doc(userId)
            .collection("medical_info")
            .doc("data")
            .get();

        if (!medicalInfoDoc.exists) {
          console.log(`[INFO] [SMS] No medical info found for user: ${userId}`);
          return null;
        }

        const medicalInfoData = medicalInfoDoc.data();
        const emergencyContactPhone = medicalInfoData.emergencyContactPhone;

        if (!emergencyContactPhone || emergencyContactPhone === "") {
          console.log(`[INFO] [SMS] No emergency contact phone for user: ${userId}`);
          return null;
        }

        // Get alert location
        const location = alertData.location;
        const lat = location.latitude;
        const lng = location.longitude;
        const googleMapsLink = `https://maps.google.com/?q=${lat},${lng}`;

        // Compose SMS message
        const message = `[ALERT] EMERGENCY ALERT
${userEmail} has triggered an SOS alert!

Location: ${googleMapsLink}

This is an automated message from Lighthouse Emergency Response System.`;

        console.log(`[SMS] [SMS] Sending to: ${emergencyContactPhone}`);

        // Send SMS
        try {
          const result = await twilioClient.messages.create({
            body: message,
            from: fromPhoneNumber,
            to: emergencyContactPhone, // Must be in E.164 format: +60123456789
          });

          console.log(`[SUCCESS] [SMS] Sent successfully! SID: ${result.sid}`);
          return {success: true, sid: result.sid};
        } catch (smsError) {
          console.error(`[ERROR] [SMS] Failed to send:`, smsError);

          // Log specific Twilio errors
          if (smsError.code) {
            console.error(`[ERROR] [SMS] Twilio error code: ${smsError.code}`);
          }
          if (smsError.message) {
            console.error(`[ERROR] [SMS] Error message: ${smsError.message}`);
          }

          return {success: false, error: smsError.message};
        }
      } catch (error) {
        console.error("[ERROR] [SMS] Error processing emergency contact SMS:", error);
        return {success: false, error: error.message};
      }
    },
);

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

/**
 * Callable Function to send email using Resend
 * Supports both plain text and HTML emails
 *
 * Setup instructions:
 * 1. Sign up at https://resend.com and get API key
 * 2. Set environment variable: firebase functions:config:set resend.api_key="re_xxxxx"
 * 3. Verify your domain in Resend dashboard (or use onboarding@resend.dev for testing)
 * 4. Deploy: firebase deploy --only functions
 */
exports.sendEmail = onCall(async (request) => {
  try {
    const {to, subject, text, html} = request.data;

    console.log("[SEND_EMAIL] Sending email to:", to);

    // Get Resend API key from Firebase parameters
    const apiKey = resendApiKey.value();

    if (!apiKey) {
      console.error("[SEND_EMAIL] Resend API key not configured");
      throw new Error(
          "Email service not configured. Please set RESEND_API_KEY parameter.",
      );
    }

    // Initialize Resend client
    const resend = new Resend(apiKey);

    // Send email using Resend with verified domain
    const result = await resend.emails.send({
      from: "Lighthouse Emergency <noreply@info.lighthouseapp.tech>",
      to: to,
      subject: subject,
      text: text,
      html: html || text,
    });

    console.log("[SEND_EMAIL] Email sent successfully:", result.data?.id);
    return {success: true, messageId: result.data?.id};
  } catch (error) {
    console.error("[SEND_EMAIL] Error sending email:", error);
    throw new Error(`Failed to send email: ${error.message}`);
  }
});

/**
 * Alternative: Gmail-based email function (kept for reference)
 * To use Gmail instead, uncomment this and comment out the Resend version above
 */
// exports.sendEmailGmail = onCall(async (request) => {
//   try {
//     const {to, subject, text, html} = request.data;
//     const emailUser = process.env.EMAIL_USER;
//     const emailPassword = process.env.EMAIL_PASSWORD;
//
//     if (!emailUser || !emailPassword) {
//       throw new Error("Gmail credentials not configured");
//     }
//
//     const transporter = nodemailer.createTransport({
//       service: "gmail",
//       auth: {user: emailUser, pass: emailPassword},
//     });
//
//     const result = await transporter.sendMail({
//       from: `"Lighthouse Emergency" <${emailUser}>`,
//       to: to,
//       subject: subject,
//       text: text,
//       html: html || text,
//     });
//
//     return {success: true, messageId: result.messageId};
//   } catch (error) {
//     throw new Error(`Failed to send email: ${error.message}`);
//   }
// });

/**
 * Callable Function to send SMS
 * Uses Twilio for SMS delivery
 */
exports.sendSMS = onCall(async (request) => {
  try {
    const {to, message} = request.data;

    console.log("[SEND_SMS] Sending SMS to:", to);

    // Get Twilio credentials from Firebase parameters
    const accountSid = twilioAccountSid.value();
    const authToken = twilioAuthToken.value();
    const twilioNumber = twilioPhoneNumber.value();

    if (!accountSid || !authToken || !twilioNumber) {
      console.error("[SEND_SMS] Twilio credentials not configured");
      throw new Error("Twilio credentials not configured. Please set TWILIO_* parameters.");
    }

    const twilio = require("twilio");
    const twilioClient = twilio(accountSid, authToken);

    const result = await twilioClient.messages.create({
      body: message,
      from: twilioNumber,
      to: to,
    });

    console.log("[SEND_SMS] SMS sent successfully:", result.sid);
    return {success: true, messageSid: result.sid};
  } catch (error) {
    console.error("[SEND_SMS] Error sending SMS:", error);
    throw new Error(`Failed to send SMS: ${error.message}`);
  }
});