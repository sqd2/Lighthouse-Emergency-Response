/**
 * Notifications API Module
 *
 * I handle notification-related endpoints for testing and emergency contacts.
 *
 * Functions:
 * - testNotification: Sends a test FCM notification to a user
 * - sendEmergencyContactSMS: Firestore trigger to send SMS to emergency contacts when SOS is created
 */

const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const cors = require("cors")({origin: true});

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
