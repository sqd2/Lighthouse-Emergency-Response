/**
 * Communication Trigger Functions
 *
 * This module contains Firestore-triggered Cloud Functions that handle real-time
 * communication notifications within emergency alerts. I implement notification
 * delivery for chat messages and incoming calls, ensuring that both citizens and
 * dispatchers stay informed during active emergency situations.
 */

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const {formatUserDisplay} = require("../helpers/user-helpers");
const {sendNotificationToUser} = require("../helpers/notification-helpers");

/**
 * Triggered when a new chat message is sent within an emergency alert.
 *
 * This function implements bidirectional messaging notifications between citizens
 * and dispatchers. I determine the message recipient based on the sender's role,
 * then send a push notification containing the message content or a description
 * for media messages (images, voice recordings).
 *
 * Message flow:
 * - Citizen sends message → Notify assigned dispatcher
 * - Dispatcher sends message → Notify citizen
 *
 * I truncate long text messages to 50 characters in notifications to prevent
 * excessive notification text while still providing context.
 *
 * Notification Recipients:
 * - The other party in the emergency alert conversation
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
 * Triggered when a new WebRTC call is initiated within an emergency alert.
 *
 * This function sends incoming call notifications to the call receiver when a
 * voice or video call is initiated. I only send notifications when the call
 * status is "ringing" to avoid duplicate notifications for calls in other states
 * (answered, ended, missed).
 *
 * The notification includes the caller's information and call type (voice/video),
 * along with the LiveKit room name needed to join the call. This allows the
 * receiver's client to display an incoming call screen with the option to
 * answer or decline.
 *
 * Notification Recipients:
 * - The user being called (receiverId field in call document)
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
