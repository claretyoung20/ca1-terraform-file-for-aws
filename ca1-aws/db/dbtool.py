#!/usr/bin/env python3
"""CA1 database helper - run on the load-generator EC2.

  python3 dbtool.py init     # create schema + 10 coupons (once)
  python3 dbtool.py reset    # truncate product table and re-seed 200 rows (before EVERY run)
  python3 dbtool.py status   # row counts, max_connections, current connections

Reads host/user/password from SSM Parameter Store (/ca1/db/*), so no secrets on disk.
Needs:  pip3 install --user pymysql cryptography
"""
import os
import ssl
import subprocess
import sys
from pathlib import Path

import pymysql

REGION = os.environ.get("REGION", "eu-west-1")
HERE = Path(__file__).resolve().parent


def param(name):
    return subprocess.check_output(
        ["aws", "ssm", "get-parameter", "--region", REGION, "--name", name,
         "--with-decryption", "--query", "Parameter.Value", "--output", "text"],
        text=True).strip()


def connect():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False          # lab shortcut: encrypt but don't verify the RDS cert
    ctx.verify_mode = ssl.CERT_NONE
    return pymysql.connect(host=param("/ca1/db/host"), user=param("/ca1/db/username"),
                           password=param("/ca1/db/password"), ssl=ctx, autocommit=True)


def statements(sql_text):
    # Drop comment lines FIRST (a comment may contain ';'), then split into statements.
    code = "\n".join(l for l in sql_text.splitlines() if not l.strip().startswith("--"))
    for chunk in code.split(";"):
        if chunk.strip():
            yield chunk.strip()


def run_file(conn, name):
    print(f"-- {name}")
    with conn.cursor() as cur:
        for stmt in statements((HERE / name).read_text()):
            cur.execute(stmt)
            if cur.description:
                cols = [d[0] for d in cur.description]
                for row in cur.fetchall():
                    print("   ", dict(zip(cols, row)))


def query(conn, sql):
    with conn.cursor() as cur:
        cur.execute(sql)
        return cur.fetchall()


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    conn = connect()
    if cmd == "init":
        run_file(conn, "schema.sql")
        run_file(conn, "seed-coupons.sql")
    elif cmd == "reset":
        run_file(conn, "reset-products.sql")
    elif cmd == "status":
        conn.select_db("servicedb")
        print("products        :", query(conn, "SELECT COUNT(*) FROM product")[0][0])
        print("coupons         :", query(conn, "SELECT COUNT(*) FROM coupon")[0][0])
        print("max_connections :", query(conn, "SHOW VARIABLES LIKE 'max_connections'")[0][1])
        print("connected now   :", query(conn, "SHOW STATUS LIKE 'Threads_connected'")[0][1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
