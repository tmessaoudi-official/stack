# Generate a Self-Signed Certificate for SAML Testing

**What it solves**: Local SAML Identity Provider (IdP) simulation or Service Provider (SP) configuration testing. SAML exchanges require X.509 certificates for signing assertions — self-signed certs are fine for development and local testing.

## Generate the certificate

```bash
# Generate RSA private key
openssl genrsa -out certificate.pem 2048

# Generate certificate signing request (CSR)
openssl req -new -key certificate.pem -out certificate.csr

# Self-sign the certificate (valid for 365 days)
openssl x509 -req -days 365 -in certificate.csr -signkey certificate.pem -out certificate.crt
```

**Note on key size**: The original example used 1024-bit RSA, which is now considered weak. Use 2048 bits minimum; 4096 for long-lived certs.

## What each flag does

- `genrsa -out certificate.pem 2048` — generates a 2048-bit RSA private key, stored in PEM format
- `req -new -key certificate.pem -out certificate.csr` — creates a certificate signing request using your private key; prompts for subject info (CN, organization, etc.)
- `x509 -req -days 365 -in certificate.csr -signkey certificate.pem -out certificate.crt` — self-signs the CSR using the same private key (self-signed = no separate CA)

## Using the cert in a SAML SP config

Most SAML libraries (SimpleSAMLphp, python3-saml, OneLogin) expect:
- **Private key**: `certificate.pem` — keep this secret, used by the SP to sign requests
- **Public certificate**: `certificate.crt` — share this with the IdP so it can verify your signatures

Typical config:
```
sp.privateKey = contents of certificate.pem (base64, no headers)
sp.x509cert   = contents of certificate.crt (base64, no headers)
```

Strip the `-----BEGIN...-----` / `-----END...-----` headers and all newlines when pasting into JSON/YAML config.

## Gotcha: PEM format required

SAML libraries expect **PEM format** (base64-encoded, ASCII headers). If you accidentally generate a DER binary (`.der` extension), convert it:
```bash
openssl x509 -inform DER -in certificate.der -out certificate.crt
```

Reference: https://security.stackexchange.com/questions/146132/self-signed-certificate-for-a-idp-initiated-saml-sso
