from flask import Flask, request, jsonify
import hashlib
import mysql.connector
import base64
import ecdsa
from dotenv import load_dotenv
import os
import random
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

# Database configuration
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

# SMTP configuration
SMTP_EMAIL = os.getenv("SMTP_EMAIL")
SMTP_SERVER = os.getenv("SMTP_SERVER")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
SMTP_PORT = int(os.getenv("SMTP_PORT", 587))


# Function to hash a password using SHA-256
def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()

# Function to generate an ECDSA signature
def generate_signature(private_key_b64, nonce):
    private_key_bytes = base64.b64decode(private_key_b64)
    sk = ecdsa.SigningKey.from_string(private_key_bytes, curve=ecdsa.NIST256p)
    signature = sk.sign(nonce.encode())
    return base64.b64encode(signature).decode('utf-8')

# Function to generate a random 6-digit OTP
def generate_otp():
    return str(random.randint(100000, 999999))

# Function to send an OTP email
def send_otp_email(to_email, otp):
    try:
        msg = MIMEMultipart()
        msg['From'] = SMTP_EMAIL
        msg['To'] = to_email
        msg['Subject'] = "Your Kasa OTP Code"

        # Email content
        html = f"""
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
        
        msg.attach(MIMEText(html, 'html'))

        # Attach logo
        with open("images/logo.png", 'rb') as img:
            logo = MIMEImage(img.read())
            logo.add_header('Content-ID', '<logo>')
            msg.attach(logo)
        
        # Send email
        server = smtplib.SMTP(SMTP_SERVER, SMTP_PORT)
        server.starttls()
        server.login(SMTP_EMAIL, SMTP_PASSWORD)
        server.sendmail(SMTP_EMAIL, to_email, msg.as_string())
        server.quit()
        print("OTP email sent successfully.")
    except Exception as e:
        print(f"Error sending email: {e}")

# Endpoint to generate password OTP
@app.route('/password_otp', methods=['POST'])
def password_otp():
    try:
        data = request.get_json()
        email = data.get('email')

        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()

        # Check if the user exists
        cursor.execute("SELECT id FROM users WHERE email = %s", (email,))
        user = cursor.fetchone()
        if not user:
            return jsonify({'message': 'User does not exist'}), 404

        # Retrieve private key
        cursor.execute("SELECT private_key FROM login_keys LIMIT 1")
        key_result = cursor.fetchone()
        if not key_result:
            return jsonify({'message': 'No private key found'}), 500
        
        private_key_b64 = key_result[0]
        nonce = base64.b64encode(os.urandom(16)).decode('utf-8')
        signature = generate_signature(private_key_b64, nonce)
        
        # Generate OTP
        otp = generate_otp()
        otp_hashed = hash_password(otp)
        
        # Insert into otp_passwords table
        insert_query = """
        INSERT INTO otp_passwords (email, signature, otp, used, attempts)
        VALUES (%s, %s, %s, %s, %s)
        """
        cursor.execute(insert_query, (email, signature, otp_hashed, 0, 0))
        connection.commit()
        
        # Send OTP email
        send_otp_email(email, otp)

        cursor.close()
        connection.close()

        return jsonify({'message': 'OTP sent successfully', 'signature': signature}), 200

    except Exception as e:
        print(f"Error: {e}")
        return jsonify({'message': 'Error processing the request'}), 500

if __name__ == '__main__':
    app.run(port=5033)
