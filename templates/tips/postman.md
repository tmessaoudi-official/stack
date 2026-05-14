# Postman

**When Postman beats curl**: Complex API workflows with chained requests (use the response from request A as input to request B), OAuth flows that require browser redirects, APIs with interactive authentication (MFA, SSO), and collaborative API documentation where multiple people share and iterate on a collection. Postman's visual environment builder and test assertion runner also beat curl for anything beyond a single one-off request.

**When curl beats Postman**: Scripted automation, CI pipelines, quick one-liners, or any context where you don't want a GUI dependency. `curl` with `jq` handles 90% of API testing without a desktop app.

## Install

Download the latest release from the official page (don't pin to a specific version — Postman releases frequently):
https://www.postman.com/downloads/

For Linux, Postman ships as an AppImage or tarball. The AppImage is the easiest:

```bash
# Download, mark executable, run
chmod +x Postman-linux-x86_64.AppImage
./Postman-linux-x86_64.AppImage
```

**Note**: The version number previously tracked here (`10.13.4`) is stale — always download from the official page rather than hardcoding a version.
