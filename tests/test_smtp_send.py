from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import smtplib
import sys
import tempfile
import unittest
from email.header import decode_header, make_header
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "skills" / "send-email" / "scripts" / "smtp_send.py"
SPEC = importlib.util.spec_from_file_location("smtp_send", MODULE_PATH)
assert SPEC and SPEC.loader
smtp_send = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = smtp_send
SPEC.loader.exec_module(smtp_send)


class FakeSmtp:
    def __init__(self, *args, refused=None, login_error=None, **kwargs):
        self.args = args
        self.kwargs = kwargs
        self.refused = refused or {}
        self.login_error = login_error
        self.ehlo_count = 0
        self.starttls_called = False
        self.login_args = None
        self.message = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False

    def ehlo(self):
        self.ehlo_count += 1

    def starttls(self, *, context):
        self.starttls_called = True

    def login(self, username, password):
        if self.login_error:
            raise self.login_error
        self.login_args = (username, password)

    def send_message(self, message, *, from_addr, to_addrs):
        self.message = message
        self.from_addr = from_addr
        self.to_addrs = to_addrs
        return self.refused


def config(**overrides):
    values = {
        "host": "smtp.example.com",
        "port": 465,
        "security": "ssl",
        "username": "sender@example.com",
        "password": "not-a-real-secret",
        "from_address": "sender@example.com",
        "timeout": 20.0,
        "password_source": "environment",
    }
    values.update(overrides)
    return smtp_send.SmtpConfig(**values)


class SmtpSendTests(unittest.TestCase):
    def test_non_ascii_subject_serializes_as_mime_header(self):
        message = smtp_send.build_message(
            config=config(),
            recipient="person@example.com",
            subject="认证 SMTP 测试",
            body="测试正文",
        )

        header_bytes = message.as_bytes().split(b"\r\n\r\n", 1)[0]
        self.assertNotIn("认证 SMTP 测试".encode(), header_bytes)
        self.assertEqual(
            str(make_header(decode_header(message["Subject"]))),
            "认证 SMTP 测试",
        )

    def test_ssl_transport_logs_in_and_sends(self):
        fake = FakeSmtp()
        message = smtp_send.build_message(
            config=config(),
            recipient="person@example.com",
            subject="Subject",
            body="Body",
        )

        with mock.patch.object(smtp_send.smtplib, "SMTP_SSL", return_value=fake):
            smtp_send.send_message(config(), message, "person@example.com")

        self.assertEqual(fake.login_args, ("sender@example.com", "not-a-real-secret"))
        self.assertEqual(fake.to_addrs, ["person@example.com"])
        self.assertFalse(fake.starttls_called)

    def test_starttls_transport_upgrades_before_login(self):
        fake = FakeSmtp()
        starttls_config = config(security="starttls", port=587)
        message = smtp_send.build_message(
            config=starttls_config,
            recipient="person@example.com",
            subject="Subject",
            body="Body",
        )

        with mock.patch.object(smtp_send.smtplib, "SMTP", return_value=fake):
            smtp_send.send_message(starttls_config, message, "person@example.com")

        self.assertTrue(fake.starttls_called)
        self.assertEqual(fake.ehlo_count, 2)

    def test_keychain_password_is_loaded_without_printing_it(self):
        environment = {
            "SEND_EMAIL_SMTP_HOST": "smtp.example.com",
            "SEND_EMAIL_SMTP_USERNAME": "sender@example.com",
            "SEND_EMAIL_SMTP_KEYCHAIN_SERVICE": "send-email-smtp",
        }
        completed = mock.Mock(stdout="keychain-secret\n")

        with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(
            smtp_send.subprocess, "run", return_value=completed
        ) as run:
            loaded = smtp_send.load_config()

        self.assertEqual(loaded.password, "keychain-secret")
        self.assertEqual(loaded.password_source, "keychain")
        self.assertNotIn("keychain-secret", " ".join(run.call_args.args[0]))

    def test_multiple_password_sources_are_rejected(self):
        environment = {
            "SEND_EMAIL_SMTP_HOST": "smtp.example.com",
            "SEND_EMAIL_SMTP_USERNAME": "sender@example.com",
            "SEND_EMAIL_SMTP_PASSWORD": "not-a-real-secret",
            "SEND_EMAIL_SMTP_KEYCHAIN_SERVICE": "send-email-smtp",
        }

        with mock.patch.dict(os.environ, environment, clear=True):
            with self.assertRaisesRegex(ValueError, "Set only one"):
                smtp_send.load_config()

    def test_authentication_failure_returns_77_without_password_leak(self):
        fake = FakeSmtp(login_error=smtplib.SMTPAuthenticationError(535, b"denied"))
        environment = {
            "SEND_EMAIL_SMTP_HOST": "smtp.example.com",
            "SEND_EMAIL_SMTP_PORT": "465",
            "SEND_EMAIL_SMTP_SECURITY": "ssl",
            "SEND_EMAIL_SMTP_USERNAME": "sender@example.com",
            "SEND_EMAIL_SMTP_PASSWORD": "not-a-real-secret",
        }

        with tempfile.NamedTemporaryFile("w", encoding="utf-8") as body:
            body.write("Body")
            body.flush()
            argv = [
                "smtp_send.py",
                "--to",
                "person@example.com",
                "--subject",
                "Subject",
                "--body-file",
                body.name,
            ]
            stderr = io.StringIO()
            with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(
                smtp_send.smtplib, "SMTP_SSL", return_value=fake
            ), mock.patch.object(sys, "argv", argv), contextlib.redirect_stderr(stderr):
                status = smtp_send.main()

        self.assertEqual(status, smtp_send.EXIT_AUTH)
        self.assertIn("SMTP_AUTH_FAILED", stderr.getvalue())
        self.assertNotIn("not-a-real-secret", stderr.getvalue())

    def test_recipient_refusal_returns_75(self):
        fake = FakeSmtp(refused={"person@example.com": (550, b"blocked")})
        environment = {
            "SEND_EMAIL_SMTP_HOST": "smtp.example.com",
            "SEND_EMAIL_SMTP_PORT": "465",
            "SEND_EMAIL_SMTP_SECURITY": "ssl",
            "SEND_EMAIL_SMTP_USERNAME": "sender@example.com",
            "SEND_EMAIL_SMTP_PASSWORD": "not-a-real-secret",
        }

        with tempfile.NamedTemporaryFile("w", encoding="utf-8") as body:
            body.write("Body")
            body.flush()
            argv = [
                "smtp_send.py",
                "--to",
                "person@example.com",
                "--subject",
                "Subject",
                "--body-file",
                body.name,
            ]
            stderr = io.StringIO()
            with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(
                smtp_send.smtplib, "SMTP_SSL", return_value=fake
            ), mock.patch.object(sys, "argv", argv), contextlib.redirect_stderr(stderr):
                status = smtp_send.main()

        self.assertEqual(status, smtp_send.EXIT_TEMPFAIL)
        self.assertIn("REMOTE_SMTP_REJECTED", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
