from flask import Flask, request, jsonify
import mysql.connector
import requests
import base64
import hashlib
from ecdsa import VerifyingKey, NIST256p
from ecdsa.util import string_to_number
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def verify_signature(token, nonce, signature_base64, x_base64, y_base64):
    try:
        x_bytes = base64.b64decode(x_base64)
        y_bytes = base64.b64decode(y_base64)
        public_key_bytes = x_bytes + y_bytes
        verifying_key = VerifyingKey.from_string(public_key_bytes, curve=NIST256p)
        message_with_nonce = f"{token}:{nonce}"
        message_hash = hashlib.sha256(message_with_nonce.encode()).digest()
        signature_bytes = base64.b64decode(signature_base64)
        return verifying_key.verify(signature_bytes, message_hash, hashfunc=hashlib.sha256)
    except Exception as e:
        return False

def get_db_connection():
    return mysql.connector.connect(
        host=os.getenv('DB_HOST'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD'),
        database=os.getenv('DB_NAME')
    )

def verify_price(price):
    try:
        response = requests.get('https://api.binance.com/api/v3/ticker/price?symbol=BTCZAR')
        current_price = float(response.json()['price'])
        user_price = float(price)
        lower_bound = current_price * 0.9
        upper_bound = current_price * 1.1
        return lower_bound <= user_price <= upper_bound
    except Exception:
        return False

@app.route('/swap_tokens', methods=['POST'])
def swap_tokens():
    data = request.get_json()
    required_fields = ['token', 'nonce', 'signature', 'price', 'type', 'zarp_amount', 'btc_amount']
    
    if not all(field in data for field in required_fields):
        return jsonify({"error": "Missing required fields"}), 400

    token = data['token']
    nonce = data['nonce']
    signature = data['signature']
    price = data['price']
    swap_type = data['type']
    try:
        zarp_amount = float(data['zarp_amount'])
    except ValueError:
        return jsonify({"error": "Invalid zarp_amount format"}), 400
    try:
        btc_amount = int(data['btc_amount'])
    except ValueError:
        return jsonify({"error": "Invalid btc_amount format"}), 400

    if swap_type not in ['btc_to_zarp', 'zarp_to_btc']:
        return jsonify({"error": "Invalid swap type"}), 400

    if not verify_price(price):
        return jsonify({"error": "Price is not within 10% of current market price"}), 400

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT email, x, y FROM tokens WHERE token = %s", (token,))
        result = cursor.fetchone()
        if not result:
            return jsonify({"error": "Token not found"}), 404
        email, x_base64, y_base64 = result

        cursor.execute("SELECT signature FROM used_signatures WHERE email = %s AND signature = %s", 
                      (email, signature))
        if cursor.fetchone():
            return jsonify({"error": "Signature already used"}), 400

        if not verify_signature(token, nonce, signature, x_base64, y_base64):
            return jsonify({"error": "Signature verification failed"}), 401

        cursor.execute("SELECT phone_number, first_name FROM users WHERE email = %s", (email,))
        user_result = cursor.fetchone()
        if not user_result:
            return jsonify({"error": "User not found"}), 404
        phone_number, first_name = user_result

        cursor.execute("SELECT read_key, admin_key FROM creds WHERE phone_number = %s", (phone_number,))
        keys = cursor.fetchone()
        if not keys:
            return jsonify({"error": "Credentials not found"}), 404
        read_key, admin_key = keys

        url = "API_BASE_URL/api/v1/payments/lnurl"
        payload = {}

        if swap_type == 'btc_to_zarp':
            response = requests.get('API_BASE_URL/api/v1/wallet', 
                                 headers={'X-API-KEY': read_key})
            balance = response.json().get('balance', 0)
            if balance < btc_amount:
                return jsonify({"error": "Insufficient BTC balance"}), 400

            headers = {'X-API-KEY': admin_key}
            adjusted_btc_amount = int(str(btc_amount) + "000")
            payload = {
                "description_hash": "38aca5cfd3ebe3fea5c914be95819a3d64e22a78be72d83eef3c1cfd7a4af318",
                "callback": "API_BASE_URL/lnurlp/api/v1/lnurl/cb/RNjc5z",
                "amount": adjusted_btc_amount,
                "comment": "swap",
                "description": "BTC withdrawal for ZARP swap"
            }

        elif swap_type == 'zarp_to_btc':
            cursor.execute("SELECT balance FROM zarp_balances WHERE phone_number = %s", (phone_number,))
            balance_result = cursor.fetchone()
            current_balance = balance_result[0] if balance_result else 0
            if current_balance < zarp_amount:
                return jsonify({"error": "Insufficient ZARP balance"}), 400

            lnurl = f"{phone_number}@bitcoinkhaya.com"
            api_url = f'API_BASE_URL/api/v1/lnurlscan/{lnurl}?code={lnurl}'
            response = requests.get(api_url, headers={'X-API-KEY': read_key})
            lnurl_data = response.json()

            headers = {'X-API-KEY': '10dc878e229c45b79535538d4bd63a19'}
            adjusted_btc_amount = int(str(btc_amount) + "000")
            payload = {
                "description_hash": lnurl_data["description_hash"],
                "callback": lnurl_data["callback"],
                "amount": adjusted_btc_amount,
                "comment": "swap",
                "description": "BTC deposit from ZARP swap"
            }

        response = requests.post(url, json=payload, headers=headers)
        resp_data = response.json()

        if 'payment_hash' not in resp_data:
            return jsonify({"error": "Payment failed", "details": resp_data}), 500

        if swap_type == 'btc_to_zarp':
            cursor.execute("""
                INSERT INTO zarp_transactions 
                (sender_phone_number, receiver_phone_number, amount, type, signature)
                VALUES (%s, %s, %s, %s, %s)
            """, ('27000000000', phone_number, zarp_amount, 'swap', signature))

            cursor.execute("""
                UPDATE zarp_balances 
                SET balance = balance + %s 
                WHERE phone_number = %s
            """, (zarp_amount, phone_number))
            if cursor.rowcount == 0:
                cursor.execute("""
                    INSERT INTO zarp_balances (phone_number, balance)
                    VALUES (%s, %s)
                """, (phone_number, zarp_amount))

        elif swap_type == 'zarp_to_btc':
            cursor.execute("""
                INSERT INTO zarp_transactions 
                (sender_phone_number, receiver_phone_number, amount, type, signature)
                VALUES (%s, %s, %s, %s, %s)
            """, (phone_number, '27000000000', zarp_amount, 'swap', signature))

            cursor.execute("""
                UPDATE zarp_balances 
                SET balance = balance - %s 
                WHERE phone_number = %s
            """, (zarp_amount, phone_number))

        cursor.execute("INSERT INTO used_signatures (email, signature) VALUES (%s, %s)", 
                      (email, signature))
        
        conn.commit()
        return jsonify({"message": "Swap completed successfully"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'conn' in locals():
            conn.close()

if __name__ == '__main__':
    app.run(port=5037)
