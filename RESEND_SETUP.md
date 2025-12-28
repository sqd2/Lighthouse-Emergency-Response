# Resend Email Setup Guide (Free 3,000 emails/month)

## Why Resend?

- **Free Tier**: 3,000 emails/month (vs Gmail's 500/day)
- **Better Deliverability**: Professional email infrastructure
- **No 2FA/App Passwords**: Simple API key setup
- **Production Ready**: Built for transactional emails
- **Analytics**: Track email delivery and opens

## Step-by-Step Setup

### 1. Create Resend Account

1. Go to **https://resend.com/signup**
2. Sign up with your email
3. Verify your email address (check inbox/spam)

### 2. Get Your API Key

1. Once logged in, go to **https://resend.com/api-keys**
2. Click **"Create API Key"**
3. Name it: `Lighthouse Emergency`
4. Permission: **"Sending access"** (default)
5. Click **"Add"**
6. **COPY THE API KEY** (starts with `re_`) - you won't see it again!
   - Example: `re_123abc456def789ghi012jkl345mno678`

### 3. Configure Firebase Functions

Open your terminal and run:

```bash
firebase functions:config:set resend.api_key="re_CpTG8uQJ_LB41RXdUucJkuwqcqr88Xrdd"
```

Replace `re_YOUR_API_KEY_HERE` with your actual API key.

### 4. Deploy Functions

```bash
firebase deploy --only functions
```

### 5. Test Email Sending

**For Testing (uses Resend's test domain)**:
- The current setup uses `onboarding@resend.dev` as the sender
- This works immediately without domain verification
- **Limitation**: Can only send to your Resend account email

**For Production (use your own domain)**:
1. Add and verify your domain in Resend dashboard
2. Update `functions/index.js` line 1053:
   ```javascript
   from: "Lighthouse Emergency <noreply@yourdomain.com>",
   ```

## Verify Domain (Optional - For Production)

### If you have a custom domain:

1. Go to **https://resend.com/domains**
2. Click **"Add Domain"**
3. Enter your domain (e.g., `lighthouse-emergency.com`)
4. Add the DNS records Resend provides:
   - **SPF** record (TXT)
   - **DKIM** records (TXT)
   - **DMARC** record (TXT) - optional but recommended
5. Click **"Verify"** after DNS propagates (can take 5-60 minutes)

### If you DON'T have a custom domain:

You can use Resend's test domain (`onboarding@resend.dev`):
- **Works immediately** - no verification needed
- **Limitation**: Can only send to the email address registered with your Resend account
- **Perfect for**: Development and testing

To send to ANY email address, you need either:
- A verified custom domain, OR
- Upgrade to Resend's paid plan ($20/month for 50k emails)

## Free Tier Limits

| Feature | Free Tier |
|---------|-----------|
| **Emails/month** | 3,000 |
| **Emails/day** | 100 |
| **Recipients/email** | Unlimited |
| **API Keys** | Unlimited |
| **Domains** | 1 |
| **Team Members** | 1 |

## Testing Your Setup

### Method 1: Register a New User

1. Go to your app's registration page
2. Register with an email address
3. Check your inbox for verification email from Lighthouse Emergency

### Method 2: Test Forgot Password

1. Go to login page
2. Click "Forgot Password"
3. Enter your email
4. Check inbox for password reset email

### Method 3: Test 2FA

1. Login to your app
2. Go to Settings → Two-Factor Authentication
3. Enable 2FA with email method
4. You should receive a 6-digit code

## Troubleshooting

### "Email service not configured" error

```bash
# Check current config
firebase functions:config:get

# Set the API key again
firebase functions:config:set resend.api_key="re_YOUR_KEY"

# Deploy functions
firebase deploy --only functions
```

### Emails not arriving

1. **Check Resend Dashboard**: https://resend.com/emails
   - See delivery status of all sent emails
   - Check for errors or bounces

2. **Using test domain?** (`onboarding@resend.dev`)
   - Can only send to your Resend account email
   - Solution: Verify a custom domain OR upgrade

3. **Check spam folder**
   - Resend has good deliverability, but check spam just in case

4. **Verify API key is set**:
   ```bash
   firebase functions:config:get resend.api_key
   ```

### Need to switch to Gmail instead?

If you prefer Gmail, uncomment the Gmail function in `functions/index.js` (line 1072-1099) and comment out the Resend version. Then follow the Gmail setup in EMAIL_SETUP.md.

## Upgrading to Custom Domain

When you're ready to use your own domain:

1. **Purchase a domain** (if you don't have one):
   - Namecheap: ~$10/year
   - Google Domains: ~$12/year
   - Cloudflare: ~$9/year

2. **Add to Resend** and verify DNS records

3. **Update code** in `functions/index.js`:
   ```javascript
   from: "Lighthouse Emergency <noreply@yourdomain.com>",
   ```

4. **Deploy**:
   ```bash
   firebase deploy --only functions
   ```

## Cost Comparison

| Service | Free Tier | After Free Tier |
|---------|-----------|-----------------|
| **Resend** | 3,000/month | $20/mo for 50k |
| **Gmail** | 500/day | Not for commercial use |
| **SendGrid** | 100/day | $20/mo for 50k |
| **Mailgun** | 5,000/month | $35/mo for 50k |

## Next Steps

1. ✅ Set up Resend API key
2. ✅ Deploy functions
3. ✅ Test with registration
4. ⏳ (Optional) Verify custom domain for production
5. ⏳ Monitor usage in Resend dashboard

**Need help?** Check the Resend docs: https://resend.com/docs
