# https://security.stackexchange.com/questions/146132/self-signed-certificate-for-a-idp-initiated-saml-sso

openssl genrsa -out certificate.pem 1024
openssl req -new -key certificate.pem -out certificate.csr
openssl x509 -req -days 365 -in certificate.csr -signkey certificate.pem -out certificate.crt