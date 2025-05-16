import solana.rpc.api
from solders.pubkey import Pubkey
from solders.signature import Signature
import mysql.connector
from mysql.connector import Error
import traceback
from httpx import HTTPStatusError
import json
from dotenv import load_dotenv
import os

load_dotenv()

# Config
RPC_ENDPOINT = os.getenv("RPC_ENDPOINT")
TOKEN_CONTRACT_ADDRESS = "8v8aBHR7EXFZDwaqaRjAStEcmCj6VZi5iGq1YDtyTok6"
LIMIT = 10
DB_CONFIG = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

def get_pubkey_phone_map():
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        cursor.execute("SELECT phone_number, pubkey FROM solana_addresses")
        data = {row[1]: row[0] for row in cursor.fetchall()}
        cursor.close()
        conn.close()
        return data
    except Error as e:
        return {}

def transaction_already_recorded(txid):
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor(buffered=True)
        cursor.execute("""
            SELECT 1 FROM zarp_deposits WHERE transaction_id = %s
            UNION
            SELECT 1 FROM zarp_transactions WHERE signature = %s
        """, (txid, txid))
        exists = cursor.fetchone() is not None
        cursor.close()
        conn.close()
        return exists
    except Error as e:
        return False

def insert_deposit(phone, pubkey, txid, amount):
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor(buffered=True)

        # Insert into zarp_deposits
        cursor.execute("""
            INSERT INTO zarp_deposits (phone_number, pubkey, transaction_id, amount)
            VALUES (%s, %s, %s, %s)
        """, (phone, pubkey, txid, amount))

        # Insert into zarp_transactions
        cursor.execute("""
            INSERT INTO zarp_transactions (sender_phone_number, receiver_phone_number, amount, type, signature)
            VALUES (%s, %s, %s, %s, %s)
        """, ("27000000000", phone, round(amount, 2), "onchain_deposit", txid))

        # ✅ Update existing balance only
        cursor.execute("SELECT balance FROM zarp_balances WHERE phone_number = %s", (phone,))
        result = cursor.fetchone()

        if result:
            old_balance = float(result[0])
            new_balance = round(old_balance + amount, 2)
            cursor.execute("UPDATE zarp_balances SET balance = %s WHERE phone_number = %s", (new_balance, phone))

        conn.commit()
        cursor.close()
        conn.close()

    except Error as e:
        traceback.print_exc()

def fetch_transaction(client, txid_str):
    signature = Signature.from_string(txid_str)
    return client.get_transaction(signature, max_supported_transaction_version=0)

def extract_zarp_transfers(tx_dict, token_address, pubkey_set):
    transfers = []
    try:
        meta = tx_dict.get("meta", {})
        inner = meta.get("innerInstructions", [])

        # Method 1: parsed SPL transfers
        for ins in inner:
            for ix in ins.get("instructions", []):
                if isinstance(ix, dict) and "parsed" in ix:
                    parsed = ix["parsed"]
                    if parsed.get("type") == "transfer":
                        info = parsed.get("info", {})
                        mint = info.get("mint")
                        dest = info.get("destination")
                        amt = float(info.get("amount", 0)) / 1_000_000
                        if mint == str(token_address) and dest in pubkey_set:
                            transfers.append((dest, amt))

        # Method 2: fallback using balance delta
        pre = {b["accountIndex"]: b for b in meta.get("preTokenBalances", [])}
        post = {b["accountIndex"]: b for b in meta.get("postTokenBalances", [])}

        for index, p in post.items():
            if p["mint"] != str(token_address):
                continue

            owner = p.get("owner")
            post_amt = float(p["uiTokenAmount"]["amount"])

            if index in pre:
                pre_amt = float(pre[index]["uiTokenAmount"]["amount"])
                delta = post_amt - pre_amt
            else:
                delta = post_amt

            if delta > 0 and owner in pubkey_set:
                transfers.append((owner, delta / 1_000_000))

    except Exception as e:
        traceback.print_exc()

    return transfers

def main():
    client = solana.rpc.api.Client(RPC_ENDPOINT)
    token_pubkey = Pubkey.from_string(TOKEN_CONTRACT_ADDRESS)
    pubkey_to_phone = get_pubkey_phone_map()

    if not pubkey_to_phone:
        return

    try:
        sigs = client.get_signatures_for_address(token_pubkey, limit=LIMIT).value

        for i, sig_info in enumerate(sigs, 1):
            txid = str(sig_info.signature)

            if transaction_already_recorded(txid):
                continue

            try:
                tx_resp = fetch_transaction(client, txid)
                raw = tx_resp.to_json()

                tx_data = json.loads(raw)["result"]
                transfers = extract_zarp_transfers(tx_data, token_pubkey, pubkey_to_phone.keys())

                for to_pubkey, amount in transfers:
                    phone = pubkey_to_phone.get(to_pubkey)
                    if phone:
                        insert_deposit(phone, to_pubkey, txid, amount)

            except Exception as tx_error:
                traceback.print_exc()

    except Exception as e:
        traceback.print_exc()

API_BASE_URL = os.getenv("API_BASE_URL")
if __name__ == "__main__":
    main()
