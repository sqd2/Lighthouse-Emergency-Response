# SMS Notification System for Emergency Contacts

## Overview
Send SMS notifications to emergency contacts when a user triggers an SOS alert.

## Architecture

### 1. SMS Service Options

#### Option A: Twilio (Recommended)
- **Pros:**
  - Easy to use, well-documented
  - Pay-as-you-go pricing (~$0.0075 per SMS in Malaysia)
  - Free trial with $15 credit
  - Reliable delivery
- **Cons:**
  - Requires account setup
  - Costs money per SMS
- **Setup:**
  ```bash
  npm install twilio --save
  ```

#### Option B: AWS SNS
- **Pros:**
  - AWS integration
  - Cheap ($0.00645 per SMS)
- **Cons:**
  - More complex setup
  - Requires AWS account

#### Option C: Firebase Extensions - Twilio
- **Pros:**
  - Easy Firebase integration
  - No code needed for basic setup
- **Cons:**
  - Still requires Twilio account
  - Less flexible

## Implementation Plan

### Step 1: Update Medical Info Model
Already supports emergency contacts, but we need to ensure phone numbers are stored:

```dart
// lib/models/medical_info.dart
class EmergencyContact {
  final String name;
  final String relationship;
  final String phoneNumber; // Format: +60123456789
}
```

### Step 2: Create Cloud Function

```javascript
// functions/index.js

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const twilio = require('twilio');

// Twilio credentials (store in Firebase config)
const accountSid = functions.config().twilio.account_sid;
const authToken = functions.config().twilio.auth_token;
const twilioPhoneNumber = functions.config().twilio.phone_number;

const twilioClient = twilio(accountSid, authToken);

exports.sendEmergencyContactSMS = functions.firestore
  .document('emergency_alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const alertData = snap.data();
    const userId = alertData.userId;
    const userEmail = alertData.userEmail;

    try {
      // Get user's medical info with emergency contacts
      const medicalInfoDoc = await admin.firestore()
        .collection('users')
        .doc(userId)
        .collection('medical_info')
        .doc('data')
        .get();

      if (!medicalInfoDoc.exists) {
        console.log('No medical info found for user:', userId);
        return null;
      }

      const medicalInfo = medicalInfoDoc.data();
      const emergencyContacts = medicalInfo.emergencyContacts || [];

      if (emergencyContacts.length === 0) {
        console.log('No emergency contacts found for user:', userId);
        return null;
      }

      // Get user's location (approximate address)
      const location = alertData.location;
      const lat = location.latitude;
      const lng = location.longitude;
      const googleMapsLink = `https://maps.google.com/?q=${lat},${lng}`;

      // Compose SMS message
      const message = `🚨 EMERGENCY ALERT
${userEmail} has triggered an SOS alert!

Location: ${googleMapsLink}

This is an automated message from Lighthouse Emergency Response System.`;

      // Send SMS to all emergency contacts
      const smsPromises = emergencyContacts.map(async (contact) => {
        if (!contact.phoneNumber) {
          console.log('No phone number for contact:', contact.name);
          return null;
        }

        try {
          const result = await twilioClient.messages.create({
            body: message,
            from: twilioPhoneNumber,
            to: contact.phoneNumber // Must be in E.164 format: +60123456789
          });

          console.log(`SMS sent to ${contact.name} (${contact.phoneNumber}):`, result.sid);
          return result;
        } catch (error) {
          console.error(`Failed to send SMS to ${contact.name}:`, error);
          return null;
        }
      });

      await Promise.all(smsPromises);
      console.log('All SMS notifications sent');

      return null;
    } catch (error) {
      console.error('Error sending emergency contact SMS:', error);
      return null;
    }
  });
```

### Step 3: Configure Twilio Credentials

```bash
# Set Firebase config
firebase functions:config:set twilio.account_sid="YOUR_ACCOUNT_SID"
firebase functions:config:set twilio.auth_token="YOUR_AUTH_TOKEN"
firebase functions:config:set twilio.phone_number="+1234567890"

# Deploy functions
firebase deploy --only functions
```

### Step 4: Update package.json

```json
{
  "dependencies": {
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^5.0.0",
    "twilio": "^4.20.0"
  }
}
```

### Step 5: Test

1. Add emergency contacts with phone numbers to medical info
2. Trigger SOS alert
3. Verify SMS received

## Cost Estimation

### Twilio Pricing (Malaysia)
- **SMS:** ~$0.0075 per message
- **Example:**
  - 3 emergency contacts = 3 SMS = $0.0225 per SOS
  - 100 SOS alerts/month = $2.25/month
  - 1000 SOS alerts/month = $22.50/month

### Free Tier
- Twilio gives $15 free credit = ~2000 SMS messages

## Security Considerations

1. **Rate Limiting:** Prevent spam by limiting SMS per user per hour
2. **Phone Number Validation:** Ensure proper E.164 format
3. **Credentials:** Store Twilio credentials in Firebase config (NOT in code)
4. **Privacy:** Only send location, not medical details

## Alternative: Email Notifications (Free)

If SMS is too expensive, we can send emails instead:

```javascript
const nodemailer = require('nodemailer');

// Much cheaper - can use Gmail SMTP for free
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: functions.config().email.user,
    pass: functions.config().email.password
  }
});

// Send email to emergency contacts
await transporter.sendMail({
  from: '"Lighthouse Emergency" <noreply@lighthouse.com>',
  to: contact.email,
  subject: '🚨 EMERGENCY ALERT',
  html: `<h1>Emergency Alert</h1>
         <p>${userEmail} has triggered an SOS alert!</p>
         <p><a href="${googleMapsLink}">View Location on Map</a></p>`
});
```

## Recommendation

**For final year project demo:**
- Use Twilio with free $15 credit
- Implement both SMS and email notifications
- Let users choose notification preference per contact

**For production:**
- Use SMS for critical contacts
- Use email as backup/additional notification
- Implement rate limiting to control costs
