# `Gamend.Payments.Providers.Apple.JWS`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/providers/apple.ex#L319)

Verifies App Store JWS payloads (StoreKit signed transactions and App Store
Server Notifications V2).

The signing key comes from the leaf certificate in the JWS `x5c` header, but
only after the full certificate chain is validated against the pinned Apple
Root CA - G3 trust anchor. A self-signed or otherwise unchained certificate is
rejected, so a payload cannot be forged by placing an attacker-controlled key
in the header. If the pinned root is not installed, verification fails closed.

The pinned root lives at `priv/certs/apple_root_ca_g3.pem` — obtain it from
https://www.apple.com/certificateauthority/AppleRootCA-G3.cer.

# `verify_and_decode`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
