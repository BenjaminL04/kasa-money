from flask import Flask, request, jsonify
import mysql.connector
import requests
import time
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

def get_btc_to_zar_conversion_rate():
    binance_api_url = "https://api.binance.com/api/v3/ticker/price?symbol=BTCZAR"
    try:
        response = requests.get(binance_api_url)
        response_data = response.json()
        if response.status_code == 200 and 'price' in response_data:
            return float(response_data['price'])
        else:
            return None
    except requests.RequestException as e:
        print(f"Error making Binance API request: {e}")
        return None

def get_read_key_for_phone(phone_number):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        query = "SELECT read_key FROM creds WHERE phone_number = %s"
        cursor.execute(query, (phone_number,))
        result = cursor.fetchone()
        if result:
            read_key = result[0]
            api_url = "API_BASE_URL/api/v1/payments/decode"
            headers = {"X-API-KEY": read_key}
            data = {
                "data": request.json["bolt11"]
            }
            response = requests.post(api_url, headers=headers, json=data)
            response_data = response.json()
            amount_msat = response_data.get("amount_msat")
            expiry = response_data.get("expiry")
            date_from_api = response_data.get("date")
            if amount_msat is not None:
                sat = round(amount_msat / 1000)
                btc = sat / 100000000
                conversion_rate = get_btc_to_zar_conversion_rate()
                if conversion_rate is not None:
                    zar = round(btc * conversion_rate, 2)

                    expiry_date = expiry + date_from_api

                    # Updated check for expiry_date being smaller than date
                    if expiry_date < get_unix_time():
                        return {"status": "expired"}

                    return {
                        "ZAR": zar,
                        "sat": sat,
                        "expiry": expiry,
                        "date": get_unix_time(),
                        "post_date": date_from_api,
                        "expiry_date": expiry_date
                    }
                else:
                    return {"error": "Failed to calculate ZAR value due to missing conversion rate."}
            else:
                return {"error": "Failed to extract amount_msat from the API response."}
        else:
            return {"error": "Phone number not found."}
    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}
    finally:
        if connection.is_connected():
            cursor.close()
            connection.close()

def check_creds_for_phone(phone_number):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        query = "SELECT * FROM creds WHERE phone_number = %s"
        cursor.execute(query, (phone_number,))
        if cursor.fetchone():
            return get_read_key_for_phone(phone_number)
        else:
            return {"error": "Phone number not found."}
    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}
    finally:
        if connection.is_connected():
            cursor.close()
            connection.close()

def get_phone_number_for_user(email):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        query = "SELECT phone_number FROM users WHERE email = %s"
        cursor.execute(query, (email,))
        result = cursor.fetchone()
        if result:
            phone_number = result[0]
            return check_creds_for_phone(phone_number)
        else:
            return {"error": "User not found."}
    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}
    finally:
        if connection.is_connected():
            cursor.close()
            connection.close()

def get_email_for_token(token):
    db_config = {
        'host': os.getenv('DB_HOST'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME')
    }
    try:
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor()
        query = "SELECT email FROM tokens WHERE token = %s"
        cursor.execute(query, (token,))
        result = cursor.fetchone()
        if result:
            email = result[0]
            return get_phone_number_for_user(email)
        else:
            return {"error": "Token not found."}
    except mysql.connector.Error as err:
        return {"error": f"Error: {err}"}
    finally:
        if connection.is_connected():
            cursor.close()
            connection.close()

def get_unix_time():
    return int(time.time())

@app.route('/decodeinvoice', methods=['POST'])
def decode_invoice():
    bolt11 = request.json.get('bolt11')
    token = request.json.get('token')
    if bolt11 and token:
        response_data = get_email_for_token(token)
        response_data["date"] = get_unix_time()
        return jsonify(response_data)
    else:
        return jsonify({"error": "Missing bolt11 or token parameter."})

if __name__ == '__main__':
    app.run(port=5018)
