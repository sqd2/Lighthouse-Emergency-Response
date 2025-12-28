/**
 * Emergency Contact Helper Functions
 *
 * This module provides functionality for retrieving and notifying emergency contacts
 * from encrypted medical information. I implement secure decryption of user medical
 * data and multi-channel notification delivery (SMS and email).
 */

const admin = require("firebase-admin");
const {defineString} = require("firebase-functions/params");

// Define Twilio and Resend API credentials as secret parameters
const twilioAccountSid = defineString("TWILIO_ACCOUNT_SID");
const twilioAuthToken = defineString("TWILIO_AUTH_TOKEN");
const twilioPhoneNumber = defineString("TWILIO_PHONE_NUMBER");
const resendApiKey = defineString("RESEND_API_KEY");

/**
 * Retrieves emergency contact information from user's encrypted medical records.
 *
 * This function queries the user's medical information from Firestore, decrypts it
 * using an encryption key derived from the user's UID via SHA-256 hashing, and
 * extracts the emergency contact details. I ensure that the decryption process
 * matches the client-side encryption implementation for consistency.
 *
 * The medical information is stored in the following Firestore path:
 * users/{userId}/medical_info/data
 *
 * @param {string} userId - The Firebase Auth UID of the user
 * @returns {Promise<Object|null>} Emergency contact object with name, phone, email, and relationship,
 *                                 or null if no emergency contact is configured or decryption fails
 */
async function getEmergencyContact(userId) {
  console.log(`[EMERGENCY_CONTACT] ===== START getEmergencyContact for user: ${userId} =====`);

  try {
    const medicalInfoSnapshot = await admin.firestore()
        .collection("users")
        .doc(userId)
        .collection("medical_info")
        .doc("data")
        .get();

    console.log(`[EMERGENCY_CONTACT] Medical info snapshot exists: ${medicalInfoSnapshot.exists}`);

    if (!medicalInfoSnapshot.exists) {
      console.log(`[EMERGENCY_CONTACT] No medical info document found for user ${userId}`);
      return null;
    }

    const medicalData = medicalInfoSnapshot.data();
    console.log(`[EMERGENCY_CONTACT] Medical data keys: ${Object.keys(medicalData).join(", ")}`);
    console.log(`[EMERGENCY_CONTACT] Has encryptedData: ${!!medicalData.encryptedData}`);
    console.log(`[EMERGENCY_CONTACT] Has IV: ${!!medicalData.iv}`);

    // Medical information is encrypted using AES-256-CBC. I decrypt it here.
    if (medicalData.encryptedData && medicalData.iv) {
      try {
        console.log(`[EMERGENCY_CONTACT] Starting decryption process...`);
        const crypto = require("crypto");

        // Extract the encrypted data and initialization vector
        const encryptedData = medicalData.encryptedData;
        const iv = Buffer.from(medicalData.iv, "base64");
        console.log(`[EMERGENCY_CONTACT] IV length: ${iv.length} bytes`);

        // Derive encryption key from user UID using SHA-256 (matching Flutter app implementation)
        const keyHash = crypto.createHash("sha256").update(userId).digest();
        const encryptionKey = Buffer.from(keyHash);
        console.log(`[EMERGENCY_CONTACT] Encryption key derived, length: ${encryptionKey.length} bytes`);

        // Perform AES-256-CBC decryption
        const decipher = crypto.createDecipheriv("aes-256-cbc", encryptionKey, iv);
        let decrypted = decipher.update(encryptedData, "base64", "utf8");
        decrypted += decipher.final("utf8");
        console.log(`[EMERGENCY_CONTACT] Decryption successful, decrypted length: ${decrypted.length} chars`);

        // Parse the decrypted JSON
        const medicalInfo = JSON.parse(decrypted);
        console.log(`[EMERGENCY_CONTACT] Parsed JSON successfully`);
        console.log(`[EMERGENCY_CONTACT] Medical info keys: ${Object.keys(medicalInfo).join(", ")}`);
        console.log(`[EMERGENCY_CONTACT] Has emergencyContact field: ${!!medicalInfo.emergencyContact}`);

        if (medicalInfo.emergencyContact) {
          const ec = medicalInfo.emergencyContact;
          console.log(`[EMERGENCY_CONTACT] Emergency contact details - name: ${!!ec.name}, phone: ${!!ec.phone}, email: ${!!ec.email}`);
          console.log(`[EMERGENCY_CONTACT] Found emergency contact for user ${userId}: ${ec.name || "no name"}`);
          return medicalInfo.emergencyContact;
        } else {
          console.log(`[EMERGENCY_CONTACT] No emergencyContact field in medical info`);
        }
      } catch (decryptError) {
        console.error("[EMERGENCY_CONTACT] Error decrypting medical info:", decryptError);
        console.error("[EMERGENCY_CONTACT] Decryption error stack:", decryptError.stack);
        // I return null if decryption fails rather than throwing, to gracefully handle errors
      }
    } else {
      console.log(`[EMERGENCY_CONTACT] Medical data missing encryption fields - encryptedData: ${!!medicalData.encryptedData}, iv: ${!!medicalData.iv}`);
    }

    console.log(`[EMERGENCY_CONTACT] Returning null - no emergency contact found`);
    return null;
  } catch (error) {
    console.error("[EMERGENCY_CONTACT] Error getting emergency contact:", error);
    console.error("[EMERGENCY_CONTACT] Error stack:", error.stack);
    return null;
  } finally {
    console.log(`[EMERGENCY_CONTACT] ===== END getEmergencyContact for user: ${userId} =====`);
  }
}

/**
 * Sends notification to the user's emergency contact via SMS or email.
 *
 * I implement a multi-channel notification strategy with SMS as the primary method
 * and email as the fallback. This function first attempts to send an SMS notification
 * using Twilio. If SMS fails or no phone number is available, I fall back to sending
 * an email notification via Resend.
 *
 * The function handles the following scenarios:
 * - SMS success: Returns immediately after successful SMS delivery
 * - SMS failure: Logs the error and attempts email delivery
 * - No phone: Skips SMS and attempts email delivery
 * - No email: Logs that no contact method is available
 *
 * @param {string} userId - The Firebase Auth UID of the user
 * @param {string} userName - Display name of the user (for message context)
 * @param {string} userEmail - Email address of the user (for message context)
 * @param {string} message - Message body to send
 * @param {string} [subject="Emergency Alert"] - Email subject line
 * @returns {Promise<void>}
 */
async function notifyEmergencyContact(userId, userName, userEmail, message, subject = "Emergency Alert") {
  console.log(`[EMERGENCY_CONTACT] ===== START notifyEmergencyContact =====`);
  console.log(`[EMERGENCY_CONTACT] userId: ${userId}, userName: ${userName}, userEmail: ${userEmail}`);
  console.log(`[EMERGENCY_CONTACT] subject: ${subject}`);
  console.log(`[EMERGENCY_CONTACT] message preview: ${message.substring(0, 100)}...`);

  try {
    const emergencyContact = await getEmergencyContact(userId);

    if (!emergencyContact) {
      console.log(`[EMERGENCY_CONTACT] No emergency contact configured for user ${userId}`);
      console.log(`[EMERGENCY_CONTACT] ===== END notifyEmergencyContact (no contact) =====`);
      return;
    }

    const {name, phone, email} = emergencyContact;
    console.log(`[EMERGENCY_CONTACT] Retrieved contact - name: ${name}, hasPhone: ${!!phone}, hasEmail: ${!!email}`);

    // Validate that we have at least one contact method
    if (!name || (!phone && !email)) {
      console.log(`[EMERGENCY_CONTACT] Emergency contact incomplete: name=${name}, phone=${phone}, email=${email}`);
      console.log(`[EMERGENCY_CONTACT] ===== END notifyEmergencyContact (incomplete) =====`);
      return;
    }

    // Primary notification method: SMS via Twilio
    if (phone && phone.trim() !== "") {
      try {
        console.log(`[EMERGENCY_CONTACT] Attempting SMS to ${name} at ${phone}`);

        const twilio = require("twilio");
        const accountSid = twilioAccountSid.value();
        const authToken = twilioAuthToken.value();
        const twilioNumber = twilioPhoneNumber.value();

        console.log(`[EMERGENCY_CONTACT] Twilio credentials loaded, from: ${twilioNumber}`);
        const twilioClient = twilio(accountSid, authToken);

        const smsResult = await twilioClient.messages.create({
          body: message,
          from: twilioNumber,
          to: phone,
        });

        console.log(`[EMERGENCY_CONTACT] SMS sent successfully to ${name}, SID: ${smsResult.sid}`);
        console.log(`[EMERGENCY_CONTACT] ===== END notifyEmergencyContact (SMS success) =====`);
        return; // Successfully sent via SMS, I skip email notification
      } catch (smsError) {
        console.error("[EMERGENCY_CONTACT] Failed to send SMS:", smsError);
        console.error("[EMERGENCY_CONTACT] SMS error details:", smsError.message);
        // I continue to try email if SMS fails
      }
    } else {
      console.log(`[EMERGENCY_CONTACT] No phone number available, skipping SMS`);
    }

    // Fallback notification method: Email via Resend
    if (email && email.trim() !== "") {
      try {
        console.log(`[EMERGENCY_CONTACT] Attempting email to ${name} at ${email}`);

        const {Resend} = require("resend");
        const apiKey = resendApiKey.value();
        const resend = new Resend(apiKey);

        console.log(`[EMERGENCY_CONTACT] Resend client initialized`);

        const emailResult = await resend.emails.send({
          from: "Lighthouse Emergency <noreply@info.lighthouseapp.tech>",
          to: email,
          subject: subject,
          text: message,
          html: `<p>${message.replace(/\n/g, "<br>")}</p>`,
        });

        console.log(`[EMERGENCY_CONTACT] Email sent successfully to ${name}, ID: ${emailResult.id}`);
        console.log(`[EMERGENCY_CONTACT] ===== END notifyEmergencyContact (email success) =====`);
      } catch (emailError) {
        console.error("[EMERGENCY_CONTACT] Failed to send email:", emailError);
        console.error("[EMERGENCY_CONTACT] Email error details:", emailError.message);
        console.log(`[EMERGENCY_CONTACT] ===== END notifyEmergencyContact (email failed) =====`);
      }
    } else {
      console.log(`[EMERGENCY_CONTACT] No email available, skipping email`);
      console.log(`[EMERGENCY_CONTACT] ===== END notifyEmergencyContact (no contact method) =====`);
    }
  } catch (error) {
    console.error("[EMERGENCY_CONTACT] Error in notifyEmergencyContact:", error);
    console.error("[EMERGENCY_CONTACT] Error stack:", error.stack);
    console.log(`[EMERGENCY_CONTACT] ===== END notifyEmergencyContact (error) =====`);
  }
}

module.exports = {
  getEmergencyContact,
  notifyEmergencyContact,
};
