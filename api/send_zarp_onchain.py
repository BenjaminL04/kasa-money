import asyncio
import mysql.connector
from flask import Flask, request, jsonify
from typing import List
from solana.rpc.async_api import AsyncClient
from solana.rpc.commitment import Confirmed
from solders.transaction import VersionedTransaction
from solders.message import MessageV0, MessageHeader
from solders.hash import Hash
from solders.instruction import Instruction as TransactionInstruction, AccountMeta, CompiledInstruction
from solders.pubkey import Pubkey
from solders.keypair import Keypair
from spl.token.constants import ASSOCIATED_TOKEN_PROGRAM_ID, TOKEN_PROGRAM_ID
from spl.token.instructions import transfer_checked, TransferCheckedParams
import base64
import hashlib
from ecdsa import VerifyingKey, NIST256p
from ecdsa.util import string_to_number
from dotenv import load_dotenv
import os

load_dotenv()

API_BASE_URL = os.getenv("API_BASE_URL")
app = Flask(__name__)

SYS_PROGRAM_ID = Pubkey.from_string("11111111111111111111111111111111")

# Database config
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

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
    except Exception:
        return False

def get_db_connection():
    return mysql.connector.connect(**db_config)

def fetch_private_key_from_db(chain_name: str) -> List[int]:
    connection = get_db_connection()
    cursor = connection.cursor()
    query = "SELECT private_key FROM hotwallet WHERE chain = %s LIMIT 1"
    cursor.execute(query, (chain_name,))
    result = cursor.fetchone()
    cursor.close()
    connection.close()
    if result:
        private_key_str = result[0]
        private_key = [int(x.strip()) for x in private_key_str.strip("[]").split(",")]
        return private_key
    else:
        raise ValueError("No private key found for specified chain.")

PRIVATE_KEY = fetch_private_key_from_db('solana')
SENDER_KEYPAIR = Keypair.from_bytes(bytes(PRIVATE_KEY))
SENDER_PUBKEY = SENDER_KEYPAIR.pubkey()

MINT_PUBKEY = Pubkey.from_string("8v8aBHR7EXFZDwaqaRjAStEcmCj6VZi5iGq1YDtyTok6")
TOKEN_2022_PROGRAM_ID = Pubkey.from_string("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb")
DECIMALS = 6

def get_associated_token_address(owner: Pubkey, mint: Pubkey, token_program_id: Pubkey) -> Pubkey:
    seeds = [bytes(owner), bytes(token_program_id), bytes(mint)]
    ata, _ = Pubkey.find_program_address(seeds, ASSOCIATED_TOKEN_PROGRAM_ID)
    return ata

def compile_instruction(ix: TransactionInstruction, account_keys: List[Pubkey]) -> CompiledInstruction:
    account_indices = [account_keys.index(meta.pubkey) for meta in ix.accounts]
    program_id_index = account_keys.index(ix.program_id)
    return CompiledInstruction(program_id_index, ix.data, bytes(account_indices))

async def send_zarp(recipient_pubkey: str, amount: float):
    recipient_pubkey_obj = Pubkey.from_string(recipient_pubkey)
    AMOUNT = int(amount * (10 ** DECIMALS))

    client = AsyncClient("https://api.mainnet-beta.solana.com", commitment=Confirmed)

    sender_token_account = get_associated_token_address(SENDER_PUBKEY, MINT_PUBKEY, TOKEN_2022_PROGRAM_ID)
    recipient_token_account = get_associated_token_address(recipient_pubkey_obj, MINT_PUBKEY, TOKEN_2022_PROGRAM_ID)

    recipient_info = await client.get_account_info(recipient_token_account)
    recipient_exists = recipient_info.value is not None

    instructions = []

    if not recipient_exists:
        ata_ix = TransactionInstruction(
            program_id=ASSOCIATED_TOKEN_PROGRAM_ID,
            accounts=[
                AccountMeta(SENDER_PUBKEY, is_signer=True, is_writable=True),
                AccountMeta(recipient_token_account, is_signer=False, is_writable=True),
                AccountMeta(recipient_pubkey_obj, is_signer=False, is_writable=False),
                AccountMeta(MINT_PUBKEY, is_signer=False, is_writable=False),
                AccountMeta(SYS_PROGRAM_ID, is_signer=False, is_writable=False),
                AccountMeta(TOKEN_2022_PROGRAM_ID, is_signer=False, is_writable=False),
                AccountMeta(TOKEN_PROGRAM_ID, is_signer=False, is_writable=False),
            ],
            data=bytes()
        )
        instructions.append(ata_ix)

    transfer_ix = transfer_checked(
        TransferCheckedParams(
            program_id=TOKEN_2022_PROGRAM_ID,
            source=sender_token_account,
            mint=MINT_PUBKEY,
            dest=recipient_token_account,
            owner=SENDER_PUBKEY,
            amount=AMOUNT,
            decimals=DECIMALS,
            signers=[]
        )
    )
    instructions.append(transfer_ix)

    blockhash = (await client.get_latest_blockhash()).value.blockhash
    hash_obj = Hash.from_string(str(blockhash))

    all_keys = []
    for ix in instructions:
        for meta in ix.accounts:
            if meta.pubkey not in all_keys:
                all_keys.append(meta.pubkey)
        if ix.program_id not in all_keys:
            all_keys.append(ix.program_id)
    account_keys = all_keys

    if SENDER_PUBKEY in account_keys:
        account_keys.remove(SENDER_PUBKEY)
        account_keys.insert(0, SENDER_PUBKEY)

    compiled_instructions = [compile_instruction(ix, account_keys) for ix in instructions]

    header = MessageHeader(
        num_required_signatures=1,
        num_readonly_signed_accounts=0,
        num_readonly_unsigned_accounts=0
    )

    msg = MessageV0(
        header,
        account_keys,
        hash_obj,
        compiled_instructions,
        []
    )

    tx = VersionedTransaction(msg, [SENDER_KEYPAIR])

    sim = await client.simulate_transaction(tx)
    if sim.value.err:
        await client.close()
        return {"success": False, "error": sim.value.logs}

    sent = await client.send_raw_transaction(bytes(tx))
    await client.close()

    tx_url = f"https://explorer.solana.com/tx/{sent.value}?cluster=mainnet"
    return {"success": True, "tx_url": tx_url}

@app.route('/send_zarp_onchain', methods=['POST'])
def send_zarp_onchain():
    data = request.get_json()
    required_fields = ['token', 'nonce', 'signature', 'recipient_pubkey', 'amount']
    
    if not all(field in data for field in required_fields):
        return jsonify({"success": False, "error": "Missing required fields"}), 400

    token = data['token']
    nonce = data['nonce']
    signature = data['signature']
    recipient_pubkey = data['recipient_pubkey']
    try:
        amount = float(data['amount'])
    except ValueError:
        return jsonify({"success": False, "error": "Invalid amount format"}), 400

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT email, x, y FROM tokens WHERE token = %s", (token,))
        result = cursor.fetchone()
        if not result:
            return jsonify({"success": False, "error": "Token not found"}), 404
        email, x_base64, y_base64 = result

        cursor.execute("SELECT signature FROM used_signatures WHERE email = %s AND signature = %s", 
                      (email, signature))
        if cursor.fetchone():
            return jsonify({"success": False, "error": "Signature already used"}), 400

        if not verify_signature(token, nonce, signature, x_base64, y_base64):
            return jsonify({"success": False, "error": "Signature verification failed"}), 401

        cursor.execute("SELECT phone_number FROM users WHERE email = %s", (email,))
        user_result = cursor.fetchone()
        if not user_result:
            return jsonify({"success": False, "error": "User not found"}), 404
        phone_number = user_result[0]

        cursor.execute("SELECT balance FROM zarp_balances WHERE phone_number = %s", (phone_number,))
        balance_result = cursor.fetchone()
        current_balance = balance_result[0] if balance_result else 0
        if current_balance < amount:
            return jsonify({"success": False, "error": "Insufficient ZARP balance"}), 400

        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        result = loop.run_until_complete(send_zarp(recipient_pubkey, amount))

        if result["success"]:
            cursor.execute("""
                INSERT INTO zarp_transactions 
                (sender_phone_number, receiver_phone_number, amount, type, signature, sender_reference, receiver_reference)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (phone_number, '27000000000', amount, 'onchain_withdrawal', signature, '', None))

            cursor.execute("""
                UPDATE zarp_balances 
                SET balance = balance - %s 
                WHERE phone_number = %s
            """, (amount, phone_number))

            cursor.execute("INSERT INTO used_signatures (email, signature) VALUES (%s, %s)", 
                          (email, signature))
            
            conn.commit()
            return jsonify(result), 200
        else:
            return jsonify(result), 500

    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500
    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    app.run(port=5038)
