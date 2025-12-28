# Email Setup Guide for Lighthouse Emergency

## Quick Start with Gmail (Free)

### Step 1: Create Gmail App Password

1. Go to https://myaccount.google.com/security
2. Enable "2-Step Verification" if not already enabled
3. Go to https://myaccount.google.com/apppasswords
4. Select "Mail" and "Other (Custom name)"
5. Name it "Lighthouse Emergency"
6. Copy the 16-character password (remove spaces)

### Step 2: Configure Firebase Functions

Open terminal and run:

```bash
firebase functions:config:set email.user="your-gmail@gmail.com"
firebase functions:config:set email.password="your-16-char-app-password"
```

### Step 3: Update functions/index.js

Replace the sendEmail function's transporter with:

```javascript
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: functions.config().email?.user || process.env.EMAIL_USER,
    pass: functions.config().email?.password || process.env.EMAIL_PASSWORD,
  },
});

const mailOptions = {
  from: `"Lighthouse Emergency" <${functions.config().email?.user || process.env.EMAIL_USER}>`,
  to: to,
  subject: subject,
  text: text,
  html: html || text,
};
```

### Step 4: Deploy

```bash
firebase deploy --only functions
```

### Step 5: Test

After deployment, try:
- Registering a new account (should send verification email)
- Using "Forgot Password" (should send reset email)
- Enabling 2FA with email method (should send verification code)

## Limits

- **Gmail Free**: 500 emails/day
- If you need more, consider:
  - **Resend**: 3,000 emails/month (free)
  - **SendGrid**: 100 emails/day (free)
  - **Mailgun**: 5,000 emails/month (free, requires credit card)

## Troubleshooting

### "Less secure app access" error
- Make sure you're using an App Password, not your regular Gmail password
- 2-Step Verification must be enabled first

### Emails going to spam
- Add SPF/DKIM records if using custom domain
- For Gmail, this usually isn't an issue

### Rate limit exceeded
- Gmail: 500/day limit
- Consider upgrading to a dedicated email service

## Production Recommendations

For production use, consider using Resend or SendGrid instead of Gmail:
- Better deliverability
- Higher limits
- Professional appearance
- Email analytics
- Webhook support for delivery tracking
