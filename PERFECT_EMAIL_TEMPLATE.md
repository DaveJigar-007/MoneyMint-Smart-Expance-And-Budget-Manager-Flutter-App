# Perfect Email Template with MoneyMint Logo

## Enhanced HTML Template for Firebase Console

Copy this HTML code and paste it in Firebase Console → Authentication → Templates → Password reset → Edit email body:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reset Your MoneyMint Password</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 0; background-color: #f8f9fa;">
    
    <!-- Preheader to avoid M avatar -->
    <div style="display: none; font-size: 1px; color: #fefefe; line-height: 1px; font-family: Arial, sans-serif; max-height: 0px; max-width: 0px; opacity: 0; overflow: hidden;">
        Reset your MoneyMint password with our secure link
    </div>
    
    <!-- Main Container -->
    <div style="background-color: white; max-width: 600px; margin: 20px auto; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); overflow: hidden;">
        
        <!-- Header with Logo -->
        <div style="background: linear-gradient(135deg, #274647 0%, #2a5a5c 100%); padding: 40px 30px; text-align: center;">
            <!-- Logo with fallback -->
            <div style="background-color: white; border-radius: 50%; width: 80px; height: 80px; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center; box-shadow: 0 4px 15px rgba(0,0,0,0.2);">
                <img src="https://money--mint.firebaseapp.com/assets/images/mm.png" 
                     alt="MoneyMint Logo" 
                     style="width: 60px; height: 60px; display: block;"
                     onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                <div style="display: none; font-size: 32px; font-weight: bold; color: #274647;">MM</div>
            </div>
            <h1 style="color: white; margin: 0; font-size: 32px; font-weight: 700; letter-spacing: -0.5px;">MoneyMint</h1>
            <p style="color: rgba(255,255,255,0.9); margin: 8px 0 0 0; font-size: 16px;">Your Personal Finance Manager</p>
        </div>
        
        <!-- Content Section -->
        <div style="padding: 40px 30px;">
            
            <!-- Greeting -->
            <h2 style="color: #274647; margin: 0 0 20px 0; font-size: 24px; font-weight: 600;">Password Reset Request</h2>
            
            <p style="color: #555; font-size: 16px; line-height: 1.6; margin: 0 0 25px 0;">
                Hello {{user.email}},
            </p>
            
            <p style="color: #555; font-size: 16px; line-height: 1.6; margin: 0 0 30px 0;">
                We received a request to reset your password for your MoneyMint account. Click the button below to securely reset your password:
            </p>
            
            <!-- Primary CTA Button -->
            <div style="text-align: center; margin: 35px 0;">
                <a href="{{% action_url %}}" 
                   style="background: linear-gradient(135deg, #274647 0%, #2a5a5c 100%); color: white; padding: 18px 40px; text-decoration: none; border-radius: 50px; display: inline-block; font-weight: 600; font-size: 16px; box-shadow: 0 6px 20px rgba(39, 70, 71, 0.3); transition: all 0.3s ease;">
                    🔄 Reset Password
                </a>
            </div>
            
            <!-- Fallback Link -->
            <div style="background-color: #f8f9fa; padding: 20px; border-radius: 8px; margin: 30px 0; border-left: 4px solid #274647;">
                <p style="font-size: 14px; color: #666; margin: 0 0 10px 0; text-align: center;">
                    <strong>Can't click the button?</strong> Copy and paste this link into your browser:
                </p>
                <a href="{{% action_url %}}" style="color: #274647; word-break: break-all; text-decoration: underline; font-size: 13px;">{{% action_url %}}</a>
            </div>
            
            <!-- Security Notice -->
            <div style="background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%); padding: 25px; border-radius: 12px; margin: 35px 0; border: 1px solid #dee2e6;">
                <h3 style="color: #274647; margin: 0 0 15px 0; font-size: 16px; display: flex; align-items: center;">
                    🔒 Security Notice
                </h3>
                <ul style="color: #555; font-size: 14px; padding-left: 20px; margin: 0; line-height: 1.6;">
                    <li style="margin-bottom: 8px;">This password reset link expires in <strong>24 hours</strong></li>
                    <li style="margin-bottom: 8px;">If you didn't request this, please ignore this email</li>
                    <li style="margin-bottom: 8px;">Never share this reset link with anyone</li>
                    <li>MoneyMint will never ask for your password via email</li>
                </ul>
            </div>
        </div>
        
        <!-- Footer -->
        <div style="background-color: #f8f9fa; padding: 30px; text-align: center; border-top: 1px solid #dee2e6;">
            <div style="margin-bottom: 20px;">
                <p style="color: #666; margin: 0 0 10px 0; font-size: 14px;"><strong>Need Help?</strong></p>
                <p style="color: #888; margin: 0; font-size: 13px;">Contact our support team if you have questions</p>
            </div>
            
            <div style="margin-top: 25px; padding-top: 20px; border-top: 1px solid #dee2e6;">
                <p style="color: #888; margin: 0 0 8px 0; font-size: 13px;">
                    Best regards,<br>
                    <strong style="color: #274647;">The MoneyMint Team</strong>
                </p>
            </div>
            
            <div style="margin-top: 20px; font-size: 11px; color: #aaa;">
                <p style="margin: 0;">© 2024 MoneyMint. All rights reserved.</p>
                <p style="margin: 5px 0 0 0;">This is an automated message. Please do not reply.</p>
            </div>
        </div>
    </div>
</body>
</html>
```

## Email Subject
```
Subject: Reset Your MoneyMint Password - Action Required
```

## Additional Firebase Settings

### 1. Update Sender Information
In Firebase Console → Authentication → Templates → Password reset:
- **From name**: MoneyMint
- **Reply-to**: noreply@money--mint.firebaseapp.com

### 2. Configure Email Headers (if available)
Add these custom headers in Firebase Console settings:
```
X-Priority: 1
X-Mailer: MoneyMint App
Organization: MoneyMint
```

## Why This Template Works Better

1. **Preheader text** prevents generic avatar generation
2. **Embedded logo with fallback** ensures your logo always shows
3. **Professional gradient design** looks more legitimate
4. **Security-focused content** reduces spam filtering
5. **Mobile-optimized** for all devices

## Steps to Apply

1. **Firebase Console** → Authentication → Templates → Password reset
2. **Edit email body** and replace with HTML above
3. **Update subject** to: "Reset Your MoneyMint Password - Action Required"
4. **Set sender name** to: "MoneyMint"
5. **Save** the template

## Expected Result
- Your MoneyMint logo (`mm.png`) will display instead of "M"
- Professional appearance that reaches primary inbox
- Better brand recognition and trust
