/**
 * Communications API Module
 *
 * I handle email and SMS communication endpoints using Resend and Twilio.
 *
 * Functions:
 * - sendEmail: Sends emails using Resend API
 * - sendSMS: Sends SMS messages using Twilio API
 */

const {onCall} = require("firebase-functions/v2/https");
const {defineString} = require("firebase-functions/params");
const {Resend} = require("resend");

// Define environment parameters
const resendApiKey = defineString("RESEND_API_KEY");
const twilioAccountSid = defineString("TWILIO_ACCOUNT_SID");
const twilioAuthToken = defineString("TWILIO_AUTH_TOKEN");
const twilioPhoneNumber = defineString("TWILIO_PHONE_NUMBER");

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
