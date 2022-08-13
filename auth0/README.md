# Auth0 Account

## Applications

### `ALPRS dev M2M` — Machine-to-Machine Application

* Description: AstroMetrics (ALPRS) DEV platform
* Auth0 Management API: `https://maiveric.us.auth0.com/api/v2/`
* API Grant Permission Scopes: `read:users` and `read:users_app_metadata` only
* Token Endpoint Authentication Method: `Post`
* Application Logo: `https://dev.astrometrics.us/maiveric-mark.png`
* Application Login URI: _{empty}_
* Allowed Callback URLs: _{empty}_
* Allowed Logout URLs: _{empty}_
* Allowed Web Origins: _{empty}_
* Allowed Origins (CORS): _{empty}_
* All settings under Refresh Token Rotation and Refresh Token Expiration sections turned off
* Advanced settings > OAuth: JWT Signature Algorithm = `RS256`
* Advanced settings > OAuth: disable OIDC Conformant
* Advanced settings > Grant Types: Client Credentials only

### `ALPRS dev SPA` — Single Page Application

* Description: AstroMetrics (ALPRS) DEV platform
* Connections: disable all social (google-oauth2)
* Application Logo: `https://dev.astrometrics.us/maiveric-mark.png`
* Application Login URI: _{empty}_
* Allowed Callback URLs: `https://dev.astrometrics.us/, http://localhost:9001/` _(`localhost:9001` is used by lattice-org via tunnel)_
* Allowed Logout URLs: _{empty}_
* Allowed Web Origins: `https://dev.astrometrics.us, http://localhost:9001` _(`localhost:9001` is used by lattice-org via tunnel)_
* Allowed Origins (CORS): _{empty}_
* All settings under Refresh Token Rotation and Refresh Token Expiration sections turned off
* Advanced settings > OAuth: JWT Signature Algorithm = `RS256`
* Advanced settings > OAuth: disable OIDC Conformant
* Advanced settings > Grant Types: Implicit, Authorization Code, and Password

## Authentication

* Database > Password Policy: for testing on DEV, may reduce password strength

## Auth Flow Actions

1. From the Auth0 dashboard, go to **Actions > Library > Custom**.
2. For each action below, click on **Build Custom**, enter the name, select the event, paste the code, and click **Deploy**.
    **`addAuthenticatedUserRoleToUser`** ("Pre User Registration" action)
    ```js
    /**
    * Handler that will be called during the execution of a PreUserRegistration flow.
    *
    * @param {Event} event                - Details about the context and user that is attempting to register.
    * @param {PreUserRegistrationAPI} api - Interface whose methods can be used to change the behavior of the signup.
    *
    * https://auth0.com/docs/actions/triggers/pre-user-registration/event-object
    * https://auth0.com/docs/actions/triggers/pre-user-registration/api-object
    */
    exports.onExecutePreUserRegistration = async (event, api) => {
      const metadata = event.user.app_metadata || {};
      const roles    = metadata.roles || [];

      if (roles.indexOf('AuthenticatedUser') === -1) {
        roles.push('AuthenticatedUser');
        api.user.setAppMetadata('roles', roles);
      }
    };
    ```
    **`onLoginAddAuthenticatedUserRoleToUser`** ("Login / Post Login" action)
    ```js
    /**
    * Handler that will be called during the execution of a PostLogin flow.
    *
    * @param {Event} event      - Details about the user and the context in which they are logging in.
    * @param {PostLoginAPI} api - Interface whose methods can be used to change the behavior of the login.
    *
    * https://auth0.com/docs/actions/triggers/post-login/event-object
    * https://auth0.com/docs/actions/triggers/post-login/api-object
    */
    exports.onExecutePostLogin = async (event, api) => {
      const metadata = event.user.app_metadata || {};
      const roles    = metadata.roles || [];

      if (roles.indexOf('AuthenticatedUser') === -1) {
        roles.push('AuthenticatedUser');
        api.user.setAppMetadata('roles', roles);
      }
    };
    ```
3. From the Auth0 dashboard, go to **Actions > Flows > Login**.
4. Select custom action `onLoginAddAuthenticatedUserRoleToUser` from right and drag onto the canvas, then click **Apply**.
5. Back to the flow menu and select "Pre User Registration".
6. Select custom action `addAuthenticatedUserRoleToUser` from right and drag onto the canvas, then click **Apply**.
7. From the Auth0 dashboard, go to **User Management > Users**.
8. Select a previously created user to designate as an "**admin**" user to allow calling the **`AdminApi`** (not accessible from the UI).
9. Scroll down the user details page to the **`app_metadata`** section, and paste in the following JSON.
    ```json
    {
      "roles": [
        "AuthenticatedUser",
        "admin"
      ]
    }
    ```
    The "`admin`" role in the `app_metadata` is only required in order to allow
    the user to call certain admin APIs, like `GET /datastore/search/edm/index`.

## NCRIC SAML SSO

* New **SAML Enterprise Connection** named `NCRIC`.
* Sign In URL: `https://ncric.identity.secureauth.com/SecureAuth5/`
* X509 Signing Certificate: _"`ncric-secureauth/signing-cert.pem`"_
* Enable Sign Out: off
* User ID Attribute: `email`
* Debug Mode: on
* Sign Request: on
* Sign Request Algorithm: `RSA-SHA256`
* Sign Request Algorithm Digest: `SHA256`
* Protocol Binding: `HTTP-POST`
* Request Template (optional): _(default)_
  ```xml
  <samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
  @@AssertServiceURLAndDestination@@
      ID="@@ID@@"
      IssueInstant="@@IssueInstant@@"
      ProtocolBinding="@@ProtocolBinding@@" Version="2.0">
      <saml:Issuer xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion">@@Issuer@@</saml:Issuer>
  </samlp:AuthnRequest>
  ```
* Sync user profile attributes at each login: on

### Mappings

  ```json
  {
    "email": "Email"
  }
  ```

### IdP-Initiated SSO

* Check "Accept Requests"
* Default Application: ALPRS prod SPA
* Response Protocol : `OpenID Connect`
* Query String: `redirect_uri=https://astrometrics.us/&scope=openid email user_id user_metadata app_metadata nickname roles&response_type=token`

### Login Experience

* Identity Provider domains: `ncric.ca.gov`
* Display connection as a button: unchecked

### Applications

* Enable only "ALPRS dev SPA" and "ALPRS prod SPA".

## User Management

* Create test user(s) with desired e-mail and password
