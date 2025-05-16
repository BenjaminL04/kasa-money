from flask import Flask, request, jsonify
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

# SMTP Configuration
SMTP_EMAIL = os.getenv("SMTP_EMAIL")
SMTP_SERVER = os.getenv("SMTP_SERVER")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
SMTP_PORT = int(os.getenv("SMTP_PORT", 587))

@app.route('/otp', methods=['POST'])
def send_otp_email():
    try:
        # Retrieve data from the POST request
        data = request.get_json()
        recipient_email = data.get('recipient_email')
        otp = data.get('otp')

        # Email content
        subject = "Kasa Wallet OTP Code"
        
        # HTML Email Body
        body = f"""
        <html>
        <body>
            <div style='text-align: center;'>
                <img src='cid:logo' style='width: 150px;'><br>
                <h2>Your OTP Code</h2>
                <p style='font-size: 20px;'><strong>{otp}</strong></p>
                <p>Please enter this OTP to complete your request. This code expires soon.</p>
            </div>
        </body>
        </html>
        """

        # Setup the MIME
        message = MIMEMultipart()
        message["From"] = SMTP_EMAIL
        message["To"] = recipient_email
        message["Subject"] = subject
        message.attach(MIMEText(body, "html"))

        # Attach the business logo as an inline image
        with open("images/logo.png", "rb") as image_file:
            image_data = image_file.read()
            image = MIMEImage(image_data, name="logo.png")
            image.add_header("Content-ID", "<logo>")
            message.attach(image)

        # Connect to the SMTP server and send email
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_EMAIL, SMTP_PASSWORD)
            server.sendmail(SMTP_EMAIL, recipient_email, message.as_string())

        return jsonify({'status': 'success', 'message': 'Email sent successfully'})
    
    except Exception as e:
        return jsonify({'status': 'error', 'message': f'Error: {e}'})

if __name__ == '__main__':
    app.run(port=5003)

