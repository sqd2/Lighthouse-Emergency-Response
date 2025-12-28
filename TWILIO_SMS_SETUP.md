# Twilio SMS Setup Guide

## SMS Notification Feature

The system now has a Cloud Function (`sendEmergencyContactSMS`) that automatically sends SMS notifications to emergency contacts when a user triggers an SOS alert.

**Status:** ✅ Cloud Function deployed and ready
**What's needed:** Twilio account configuration

---

## Step 1: Sign Up for Twilio

1. Go to https://www.twilio.com/try-twilio
2. Sign up for a free trial account
3. Verify your email and phone number
4. You'll get **$15 free credit** (~2000 SMS messages)

---

## Step 2: Get Your Twilio Credentials

After signing up, you'll need three pieces of information:

### A. Account SID and Auth Token
1. Go to your Twilio Console: https://console.twilio.com/
2. On the dashboard, you'll see:
   - **Account SID** (starts with "AC...")
   - **Auth Token** (click to reveal)

### B. Phone Number
1. In the Twilio Console, go to **Phone Numbers** > **Manage** > **Buy a number**
2. For trial accounts:
   - Select your country (Malaysia)
   - Search for available numbers
   - Choose one with **SMS capability**
   - Click "Buy" (free during trial)
3. Your phone number will be in E.164 format: `+60123456789`

**Note:** During trial, you can only send SMS to verified phone numbers. Add your emergency contacts as verified numbers:
- Go to **Phone Numbers** > **Verified Caller IDs**
- Click "Add a new Caller ID"
- Enter the emergency contact's phone number
- They'll receive a verification code

---

## Step 3: Configure Firebase Functions

Run these commands in your terminal (replace with your actual credentials):

```bash
# Set Twilio Account SID
firebase functions:config:set twilio.account_sid="AC1d77ad930ee907077141f8c8d60fd522"

# Set Twilio Auth Token
firebase functions:config:set twilio.auth_token="ef036cc3d6302b1c2aedb24f3194058d"

# Set Twilio Phone Number (in E.164 format)
firebase functions:config:set twilio.phone_number="+13208550575"
```

**Example:**
```bash
firebase functions:config:set twilio.account_sid="AC1234567890abcdef1234567890abcd"
firebase functions:config:set twilio.auth_token="1234567890abcdef1234567890abcd"
firebase functions:config:set twilio.phone_number="+60123456789"
```

---

## Step 4: Redeploy Cloud Functions

After setting the config, redeploy the functfirebase deploy --only functions
ions:

```bash
```

This will make the Twilio credentials available to the `sendEmergencyContactSMS` function.

---

## Step 5: Add Emergency Contact Phone to Medical Info

The Cloud Function expects a field called `emergencyContactPhone` in the medical info document.

### Current Medical Info Structure:
```
users/{userId}/medical_info/data
  └── medicalInfo: (encrypted data)
  └── emergencyContactPhone: "+60123456789"  ← ADD THIS
```

### How to Add:

**Option A: Via Firestore Console (Quick Test)**
1. Go to Firebase Console: https://console.firebase.google.com/
2. Navigate to **Firestore Database**
3. Find a user: `users/{userId}/medical_info/data`
4. Click **Edit**
5. Add new field:
   - Field name: `emergencyContactPhone`
   - Type: `string`
   - Value: `+60123456789` (in E.164 format)
6. Click **Update**

**Option B: Update Flutter Code (Proper Solution)**

You'll need to update the medical info service to save the emergency contact phone separately when saving medical info. This will be done in the next task.

---

## Step 6: Test SMS Notifications

1. Make sure a user has `emergencyContactPhone` set in their medical info
2. Trigger an SOS alert from the app
3. Check if SMS is received by the emergency contact
4. Check Cloud Function logs:
   ```bash
   firebase functions:log
   ```
   Look for messages like:
   - `📱 [SMS] New SOS alert created`
   - `✅ [SMS] Sent successfully! SID: SMxxxx`

---

## SMS Message Format

When an SOS alert is triggered, the emergency contact receives:

```
🚨 EMERGENCY ALERT
user@example.com has triggered an SOS alert!

Location: https://maps.google.com/?q=3.1390,101.6869

This is an automated message from Lighthouse Emergency Response System.
```

The message includes:
- User's email
- Google Maps link to their location
- Clear indication it's an emergency

---

## Troubleshooting

### SMS not sending?

1. **Check Firebase logs:**
   ```bash
   firebase functions:log --only sendEmergencyContactSMS
   ```

2. **Common issues:**
   - ⚠️ Twilio not configured → Set config variables (Step 3)
   - ⚠️ No emergency contact phone → Add to medical info (Step 5)
   - ❌ Invalid phone number → Must be E.164 format (+60123456789)
   - ❌ Twilio trial restrictions → Verify recipient phone in Twilio Console

3. **Check Twilio logs:**
   - Go to https://console.twilio.com/
   - Navigate to **Monitor** > **Logs** > **Messaging Logs**
   - Check for failed messages and error codes

### Phone Number Format

Always use E.164 format:
- ✅ Correct: `+60123456789` (Malaysia)
- ✅ Correct: `+12065551234` (US)
- ❌ Wrong: `0123456789` (missing country code)
- ❌ Wrong: `60123456789` (missing +)
- ❌ Wrong: `+60 12 345 6789` (has spaces)

---

## Cost Information

### Twilio Pricing (Malaysia)
- **SMS:** ~$0.0075 per message
- **Free trial:** $15 credit = ~2000 SMS messages

### Example Costs:
- 1 emergency contact per user = 1 SMS per SOS = $0.0075
- 3 emergency contacts per user = 3 SMS per SOS = $0.0225
- 100 SOS alerts/month (1 contact) = $0.75/month
- 1000 SOS alerts/month (1 contact) = $7.50/month

### For Demo/Testing:
The free $15 credit is more than enough for testing and demonstration purposes.

---

## Security Notes

1. **Credentials are secure:**
   - Stored in Firebase config (server-side only)
   - Never exposed to client apps
   - Not visible in source code

2. **Phone numbers:**
   - Currently stored unencrypted for Cloud Function access
   - Medical data itself remains encrypted
   - Consider encryption at rest for production

3. **Rate limiting:**
   - Cloud Functions have automatic rate limiting
   - Consider adding custom limits to prevent abuse

---

## Next Steps

After completing Twilio setup:
1. Update medical info service to save `emergencyContactPhone` field
2. Test SMS notifications with real SOS alerts
3. Add UI for users to manage emergency contacts
4. Consider supporting multiple emergency contacts (send to all)

---

## Support

- **Twilio Documentation:** https://www.twilio.com/docs/sms
- **Firebase Functions Config:** https://firebase.google.com/docs/functions/config-env
- **Project Console:** https://console.firebase.google.com/project/lighthouse-2498c/overview
