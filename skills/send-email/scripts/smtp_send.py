#!/usr/bin/env python3
"""Send one plain-text message through an authenticated SMTP service."""

from __future__ import annotations

import argparse
import os
import smtplib
import ssl
import subprocess
import sys
from dataclasses import dataclass
from email.message import EmailMessage
from email.policy import SMTP
from email.utils import formatdate, make_msgid
from pathlib import Path


EXIT_USAGE = 64
EXIT_UNAVAILABLE = 69
EXIT_TEMPFAIL = 75
EXIT_AUTH = 77
SECURITY_MODES = {"ssl", "starttls"}


@dataclass(frozen=True)
class SmtpConfig:
    host: str
    port: int
    security: str
    username: str
    password: str
    from_address: str
    timeout: float
    password_source: str


def require_env(name: str) -> str:
    value = (os.environ.get(name) or "").strip()
    if not value:
        raise ValueError(f"{name} is required")
    return value


def parse_port(raw: str, label: str) -> int:
    try:
        port = int(raw)
    except ValueError as exc:
        raise ValueError(f"{label} must be an integer") from exc
    if not 1 <= port <= 65535:
        raise ValueError(f"{label} must be between 1 and 65535")
    return port


def parse_timeout(raw: str) -> float:
    try:
        timeout = float(raw)
    except ValueError as exc:
        raise ValueError("SEND_EMAIL_SMTP_TIMEOUT must be a number") from exc
    if timeout <= 0:
        raise ValueError("SEND_EMAIL_SMTP_TIMEOUT must be greater than zero")
    return timeout


def password_from_keychain(service: str, account: str) -> str:
    security_bin = os.environ.get("SEND_EMAIL_SECURITY_BIN", "/usr/bin/security")
    try:
        completed = subprocess.run(
            [
                security_bin,
                "find-generic-password",
                "-w",
                "-s",
                service,
                "-a",
                account,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError(
            f"No readable Keychain password for service {service!r} and account {account!r}"
        ) from exc
    password = completed.stdout.rstrip("\r\n")
    if not password:
        raise ValueError("The Keychain password is empty")
    return password


def load_config() -> SmtpConfig:
    host = require_env("SEND_EMAIL_SMTP_HOST")
    security = (os.environ.get("SEND_EMAIL_SMTP_SECURITY") or "starttls").strip().lower()
    if security not in SECURITY_MODES:
        raise ValueError("SEND_EMAIL_SMTP_SECURITY must be ssl or starttls")
    default_port = "465" if security == "ssl" else "587"
    port = parse_port(os.environ.get("SEND_EMAIL_SMTP_PORT") or default_port, "SEND_EMAIL_SMTP_PORT")
    username = require_env("SEND_EMAIL_SMTP_USERNAME")
    from_address = (os.environ.get("SEND_EMAIL_SMTP_FROM") or username).strip()
    if not from_address:
        raise ValueError("SEND_EMAIL_SMTP_FROM cannot be empty")

    password = os.environ.get("SEND_EMAIL_SMTP_PASSWORD") or ""
    keychain_service = (os.environ.get("SEND_EMAIL_SMTP_KEYCHAIN_SERVICE") or "").strip()
    if password and keychain_service:
        raise ValueError(
            "Set only one of SEND_EMAIL_SMTP_PASSWORD or SEND_EMAIL_SMTP_KEYCHAIN_SERVICE"
        )
    password_source = "environment"
    if not password:
        if not keychain_service:
            raise ValueError(
                "Set SEND_EMAIL_SMTP_PASSWORD or SEND_EMAIL_SMTP_KEYCHAIN_SERVICE"
            )
        keychain_account = (
            os.environ.get("SEND_EMAIL_SMTP_KEYCHAIN_ACCOUNT") or username
        ).strip()
        password = password_from_keychain(keychain_service, keychain_account)
        password_source = "keychain"

    return SmtpConfig(
        host=host,
        port=port,
        security=security,
        username=username,
        password=password,
        from_address=from_address,
        timeout=parse_timeout(os.environ.get("SEND_EMAIL_SMTP_TIMEOUT") or "20"),
        password_source=password_source,
    )


def build_message(*, config: SmtpConfig, recipient: str, subject: str, body: str) -> EmailMessage:
    message = EmailMessage(policy=SMTP)
    message["From"] = config.from_address
    message["To"] = recipient
    message["Subject"] = subject
    message["Date"] = formatdate(localtime=True)
    message["Message-ID"] = make_msgid()
    message.set_content(body, subtype="plain", charset="utf-8")
    return message


def decode_smtp_error(error: bytes | str) -> str:
    if isinstance(error, bytes):
        return error.decode("utf-8", errors="replace").replace("\r", " ").replace("\n", " ")
    return str(error).replace("\r", " ").replace("\n", " ")


def send_message(config: SmtpConfig, message: EmailMessage, recipient: str) -> None:
    context = ssl.create_default_context()
    if config.security == "ssl":
        client_factory = smtplib.SMTP_SSL
        client_args = (config.host, config.port)
        client_kwargs = {"timeout": config.timeout, "context": context}
    else:
        client_factory = smtplib.SMTP
        client_args = (config.host, config.port)
        client_kwargs = {"timeout": config.timeout}

    with client_factory(*client_args, **client_kwargs) as client:
        client.ehlo()
        if config.security == "starttls":
            client.starttls(context=context)
            client.ehlo()
        client.login(config.username, config.password)
        print("SMTP_AUTHENTICATED")
        refused = client.send_message(
            message,
            from_addr=config.from_address,
            to_addrs=[recipient],
        )
        if refused:
            raise smtplib.SMTPRecipientsRefused(refused)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--to", required=True)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--body-file", required=True)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    body_path = Path(args.body_file)
    try:
        config = load_config()
        if not body_path.is_file():
            raise ValueError(f"Body file is not a regular file: {body_path}")
        body = body_path.read_text(encoding="utf-8")
        if not body:
            raise ValueError("Message body cannot be empty")
        message = build_message(
            config=config,
            recipient=args.to,
            subject=args.subject,
            body=body,
        )
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"SMTP_CONFIG_INVALID error={exc}", file=sys.stderr)
        return EXIT_USAGE

    print(
        f"SMTP_CONFIG_READY security={config.security} host={config.host} port={config.port} "
        f"password_source={config.password_source}"
    )
    print("MESSAGE_READY encoding=mime")
    if args.dry_run:
        print(f"DRY_RUN_OK to={args.to} body_bytes={len(body.encode('utf-8'))}")
        return 0

    try:
        send_message(config, message, args.to)
    except smtplib.SMTPAuthenticationError as exc:
        print(
            f"SMTP_AUTH_FAILED code={exc.smtp_code} error={decode_smtp_error(exc.smtp_error)}",
            file=sys.stderr,
        )
        return EXIT_AUTH
    except smtplib.SMTPRecipientsRefused:
        print(f"REMOTE_SMTP_REJECTED to={args.to}", file=sys.stderr)
        return EXIT_TEMPFAIL
    except smtplib.SMTPResponseException as exc:
        print(
            f"SMTP_SEND_FAILED code={exc.smtp_code} error={decode_smtp_error(exc.smtp_error)}",
            file=sys.stderr,
        )
        return EXIT_TEMPFAIL
    except (OSError, smtplib.SMTPException) as exc:
        print(f"SMTP_SEND_FAILED type={type(exc).__name__} error={exc}", file=sys.stderr)
        return EXIT_UNAVAILABLE

    print(f"REMOTE_SMTP_ACCEPTED to={args.to} transport=smtp message_id={message['Message-ID']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
