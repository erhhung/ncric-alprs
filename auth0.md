# Auth0 Account

## Applications

### `ALPRS dev M2M` — Machine-to-Machine Application

* Description: AstroMetrics (ALPRS) DEV platform
* Auth0 Management API: `https://maiveric.us.auth0.com/api/v2/`
* API Grant Permission Scopes: `read:users` and `read:users_app_metadata` only
* Token Endpoint Authentication Method: Post
* Application Logo: `https://dev.astrometrics.us/maiveric-logo.png`
* Application Login URI: _{empty}_
* Allowed Callback URLs: _{empty}_
* Allowed Logout URLs: _{empty}_
* Allowed Web Origins: _{empty}_
* Allowed Origins (CORS): _{empty}_
* All settings under Refresh Token Rotation and Refresh Token Expiration sections turned off
* Advanced settings > OAuth: disable OIDC Conformant
* Advanced settings > Grant Types: Client Credentials only

### `ALPRS dev SPA` — Single Page Application

* Description: AstroMetrics (ALPRS) DEV platform
* Connections: disable all social (google-oauth2)
* Application Logo: `https://dev.astrometrics.us/maiveric-logo.png`
* Application Login URI: _{empty}_
* Allowed Callback URLs: `https://dev.astrometrics.us/`
* Allowed Logout URLs: _{empty}_
* Allowed Web Origins: `https://dev.astrometrics.us`
* Allowed Origins (CORS): _{empty}_
* All settings under Refresh Token Rotation and Refresh Token Expiration sections turned off
* Advanced settings > OAuth: disable OIDC Conformant
* Advanced settings > Grant Types: Implicit, Authorization Code, and Password

## Authentication

* Database > Password Policy: for testing on DEV, may reduce password strength

## User Management

* Create test user(s) with desired e-mail and password
