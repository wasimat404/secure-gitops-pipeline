"""
Minimal Flask app demonstrating zero-hardcoded-secrets.

DB credentials come from environment variables, which are populated by
Kubernetes from a Secret that External Secrets Operator syncs from Vault.
The app itself has no idea Vault exists — it just reads env vars.
"""
import os
import logging

from flask import Flask, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)


def _required_env(key: str) -> str:
    val = os.environ.get(key)
    if not val:
        raise RuntimeError(f"Missing required env var: {key}")
    return val


@app.route("/healthz")
def healthz():
    return jsonify(status="ok"), 200


@app.route("/readyz")
def readyz():
    # In a real app, ping the DB here. We just verify creds were injected.
    try:
        _required_env("DB_USERNAME")
        _required_env("DB_PASSWORD")
    except RuntimeError as e:
        log.warning("not ready: %s", e)
        return jsonify(status="not-ready", reason=str(e)), 503
    return jsonify(status="ready"), 200


@app.route("/")
def index():
    # Don't ever log or return the password. This just proves it was injected.
    return jsonify(
        app="secure-gitops-demo",
        db_user=os.environ.get("DB_USERNAME", "<unset>"),
        db_password_set=bool(os.environ.get("DB_PASSWORD")),
        version=os.environ.get("APP_VERSION", "dev"),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
