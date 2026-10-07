#!/usr/bin/env python3
"""查看并清理团队的 Apple 签名证书（App Store Connect API）。

背景：CI 的归档步骤用 `-allowProvisioningUpdates` 让 Xcode 现场向 Apple 申请
签名证书（日志里的 "Apple Development: Created via API"）。这类证书会一直占用
团队证书配额，配额满后 Xcode 会直接报错：
    Choose a certificate to revoke. Your account has reached the maximum number of certificates.

用法（在归档前、构建结束后各调用一次）：
    python3 ci/asc_certificates.py preflight <state-file>   # 记录证书 id 快照
    python3 ci/asc_certificates.py cleanup   <state-file>   # 撤销本次新建的证书

需要环境变量：
    APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_KEY_PATH

仓库与 Actions 日志都是公开的，因此脚本只输出数量，不打印证书名称、序列号、到期时间等明细。
清理只撤销「不在快照里」且「刚签发」的证书，因此不会影响开发者账号里已有的证书。
如果快照文件缺失或候选证书数量异常，脚本会放弃撤销（宁可漏清，不可误删）。
"""

from __future__ import annotations

import base64
import calendar
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

DEFAULT_API_BASE = "https://api.appstoreconnect.apple.com"
CERTIFICATE_FIELDS = "certificateType,expirationDate"

# 只清理开发/分发型证书，其它类型（Apple Pay、Pass Type ID 等）一律不碰
REVOKABLE_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT", "DISTRIBUTION", "IOS_DISTRIBUTION"}
# 一次构建最多只会新建个位数的证书，超过则说明判断有误，放弃撤销
MAX_REVOCATIONS_PER_RUN = 4
# 新签发证书的有效期约一年，用它作为"刚签发"的第二重保险
FRESH_CERTIFICATE_MIN_DAYS = 300
TOKEN_TTL_SECONDS = 1200


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def read_der_length(der: bytes, index: int) -> tuple[int, int]:
    first = der[index]
    if first < 0x80:
        return first, index + 1
    count = first & 0x7F
    return int.from_bytes(der[index + 1:index + 1 + count], "big"), index + 1 + count


def der_signature_to_raw(der: bytes) -> bytes:
    """ECDSA DER SEQUENCE{r,s} -> raw R||S，JWT ES256 要求定长 32+32 字节。"""
    if der[0] != 0x30:
        raise ValueError("unexpected ECDSA signature encoding")
    _, index = read_der_length(der, 1)
    parts = []
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("unexpected ECDSA signature encoding")
        length, index = read_der_length(der, index + 1)
        parts.append(der[index:index + length].lstrip(b"\x00").rjust(32, b"\x00"))
        index += length
    return b"".join(parts)


def encode_segment(obj: dict) -> str:
    return b64url(json.dumps(obj, separators=(",", ":")).encode("utf-8"))


def build_token(key_path: str, key_id: str, issuer_id: str) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + TOKEN_TTL_SECONDS, "aud": "appstoreconnect-v1"}
    signing_input = f"{encode_segment(header)}.{encode_segment(payload)}"
    completed = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode("ascii"),
        capture_output=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"openssl 签名失败：{completed.stderr.decode('utf-8', 'replace').strip()}")
    return f"{signing_input}.{b64url(der_signature_to_raw(completed.stdout))}"


class AppStoreConnect:
    def __init__(self, token: str, base_url: str) -> None:
        self._token = token
        self._base_url = base_url.rstrip("/")

    def request(self, method: str, path_or_url: str) -> dict | None:
        url = path_or_url if path_or_url.startswith("http") else f"{self._base_url}{path_or_url}"
        request = urllib.request.Request(url, method=method)
        request.add_header("Authorization", f"Bearer {self._token}")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")
            raise RuntimeError(f"{method} {url} failed with HTTP {error.code}: {detail}") from error
        return json.loads(body) if body else None

    def list_certificates(self) -> list[dict]:
        url = f"/v1/certificates?limit=200&fields[certificates]={CERTIFICATE_FIELDS}"
        certificates: list[dict] = []
        while url:
            document = self.request("GET", url) or {}
            certificates.extend(document.get("data", []))
            url = (document.get("links") or {}).get("next")
        return certificates


def connect() -> AppStoreConnect:
    missing = [
        name
        for name in ("APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_KEY_PATH")
        if not os.environ.get(name)
    ]
    if missing:
        raise RuntimeError(f"missing environment variables: {', '.join(missing)}")
    token = build_token(
        os.environ["APP_STORE_CONNECT_KEY_PATH"],
        os.environ["APP_STORE_CONNECT_KEY_ID"],
        os.environ["APP_STORE_CONNECT_ISSUER_ID"],
    )
    return AppStoreConnect(token, os.environ.get("ASC_API_BASE_URL", DEFAULT_API_BASE))


def to_summary(certificate: dict) -> dict:
    attributes = certificate.get("attributes") or {}
    return {
        "id": certificate["id"],
        "certificateType": attributes.get("certificateType", "UNKNOWN"),
        "expirationDate": attributes.get("expirationDate", ""),
    }


def parse_expiration(summary: dict) -> time.struct_time | None:
    expiration = summary["expirationDate"]
    if not expiration:
        return None
    try:
        return time.strptime(expiration[:19], "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None


def days_until_expiration(summary: dict) -> float | None:
    expires_at = parse_expiration(summary)
    return None if expires_at is None else (calendar.timegm(expires_at) - time.time()) / 86400


def cmd_preflight(state_path: str) -> int:
    certificate_ids = sorted({certificate["id"] for certificate in connect().list_certificates()})
    with open(state_path, "w", encoding="utf-8") as state_file:
        json.dump({"snapshot_at": int(time.time()), "certificate_ids": certificate_ids}, state_file, indent=2)
    # 仓库是公开的，Actions 日志同样公开：这里只报数量，不打印任何证书明细
    print(f"已记录 {len(certificate_ids)} 张证书的快照到 {state_path}")
    return 0


def load_snapshot_ids(state_path: str) -> set[str]:
    with open(state_path, encoding="utf-8") as state_file:
        return set(json.load(state_file).get("certificate_ids", []))


def cmd_cleanup(state_path: str) -> int:
    if not os.path.exists(state_path):
        print(f"::warning::缺少证书快照 {state_path}，跳过清理（不撤销任何证书）")
        return 0
    snapshot_ids = load_snapshot_ids(state_path)
    if not snapshot_ids:
        print(f"::warning::证书快照 {state_path} 为空，跳过清理（不撤销任何证书）")
        return 0

    client = connect()
    current = [to_summary(certificate) for certificate in client.list_certificates()]
    candidates = [summary for summary in current if summary["id"] not in snapshot_ids]
    revokable = [
        summary
        for summary in candidates
        if summary["certificateType"] in REVOKABLE_TYPES
        and (days_until_expiration(summary) or 0) >= FRESH_CERTIFICATE_MIN_DAYS
    ]
    print(f"本次构建新增证书 {len(candidates)} 张，其中可清理 {len(revokable)} 张")

    if not revokable:
        print("没有需要撤销的证书（Xcode 可能复用了已有证书）。")
        return 0
    if len(revokable) > MAX_REVOCATIONS_PER_RUN:
        print(f"::warning::新增证书数量异常（{len(revokable)} 张，上限 {MAX_REVOCATIONS_PER_RUN}），已放弃撤销以免误删")
        return 0

    failures = 0
    for summary in revokable:
        try:
            client.request("DELETE", f"/v1/certificates/{summary['id']}")
        except RuntimeError as error:
            failures += 1
            print(f"::warning::撤销 {summary['certificateType']} 证书失败：{error}")
        else:
            print(f"已撤销证书：{summary['certificateType']}")
    print(f"清理完成：成功 {len(revokable) - failures} 张，失败 {failures} 张")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in {"preflight", "cleanup"}:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    command, state_path = argv[1], argv[2]
    try:
        return cmd_preflight(state_path) if command == "preflight" else cmd_cleanup(state_path)
    except Exception as error:  # 辅助步骤绝不能把发布任务判为失败
        print(f"::warning::{command} 失败：{type(error).__name__}: {error}")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
