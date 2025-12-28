/**
 * Notification Helper Functions
 *
 * This module provides functionality for sending push notifications to users via
 * Firebase Cloud Messaging (FCM). I implement multi-device support, allowing users
 * to receive notifications on all their registered devices, and automatic cleanup
 * of invalid or expired FCM tokens.
 */

const admin = require("firebase-admin");

/**
 * Sends push notification to all registered devices for a specific user.
 *
 * I handle both the new multi-device token format (fcmTokens array) and the legacy
 * single-token format (fcmToken string) for backward compatibility. When sending
 * notifications, I track invalid tokens and automatically remove them from the user's
 * profile to maintain database hygiene and reduce failed send attempts.
 *
 * The notification is sent as a data-only message (no notification field) to prevent
 * Firebase from automatically displaying system notifications. This allows our custom
 * Flutter handlers to control the notification display and behavior.
 *
 * @param {string} userId - The Firebase Auth UID of the target user
 * @param {string} title - Notification title text
 * @param {string} body - Notification body text
 * @param {Object} data - Additional custom data to include in the notification payload
 * @returns {Promise<void>}
 */
async function sendNotificationToUser(userId, title, body, data = {}) {
  try {
    console.log(`[SEND] Attempting to send notification to user ${userId}`);
    console.log(`[INFO] Title: ${title}`);
    console.log(`[INFO] Body: ${body}`);

    // Get user's FCM tokens
    const userDoc = await admin.firestore().collection("users").doc(userId).get();

    if (!userDoc.exists) {
      console.log(`[ERROR] User ${userId} not found in Firestore`);
      return;
    }

    const userData = userDoc.data();
    console.log(`[SUCCESS] User found: ${userData.email || userId}`);
    console.log(`[SMS] Role: ${userData.role}`);

    // Get all tokens (new array format)
    const fcmTokens = userData.fcmTokens || [];
    const legacyToken = userData.fcmToken; // Fallback for old single-token format

    console.log(`[NOTIF] Has ${fcmTokens.length} device token(s)`);
    console.log(`[NOTIF] Has legacy token: ${!!legacyToken}`);

    // Combine tokens: new array format + legacy single token (if exists and not in array)
    const allTokens = [...fcmTokens];
    if (legacyToken && !fcmTokens.some((t) => t.token === legacyToken)) {
      allTokens.push({token: legacyToken, platform: "unknown"});
    }

    if (allTokens.length === 0) {
      console.log(`[ERROR] User ${userId} (${userData.email}) has no FCM tokens`);
      return;
    }

    // Send to all devices
    console.log(`[DEPLOY] Sending to ${allTokens.length} device(s)...`);
    const invalidTokens = [];

    for (let i = 0; i < allTokens.length; i++) {
      const tokenData = allTokens[i];
      const token = tokenData.token;
      const platform = tokenData.platform || "unknown";

      console.log(`  [DEVICE] Device ${i + 1}/${allTokens.length} (${platform}): ${token.substring(0, 20)}...`);

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
        console.log(`  [SUCCESS] Sent to device ${i + 1} (${platform}), Message ID: ${response}`);
      } catch (error) {
        console.error(`  [ERROR] Failed to send to device ${i + 1} (${platform}):`, error.code);

        // Track invalid tokens for cleanup
        if (error.code === "messaging/invalid-registration-token" ||
            error.code === "messaging/registration-token-not-registered") {
          console.log(`  [REMOVE] Marking token for removal: ${token.substring(0, 20)}...`);
          invalidTokens.push(token);
        }
      }
    }

    // Clean up invalid tokens
    if (invalidTokens.length > 0) {
      console.log(`[CLEANUP] Removing ${invalidTokens.length} invalid token(s)...`);
      const validTokens = fcmTokens.filter((t) => !invalidTokens.includes(t.token));
      await userDoc.ref.update({
        fcmTokens: validTokens,
      });
      console.log(`[SUCCESS] Cleaned up invalid tokens. Remaining: ${validTokens.length}`);
    }

    console.log(`[SUCCESS] Finished sending notifications to ${userData.email || userId}`);
  } catch (error) {
    console.error(`[ERROR] Error sending notification to ${userId}:`, error.code, error.message);
  }
}

module.exports = {
  sendNotificationToUser,
};
