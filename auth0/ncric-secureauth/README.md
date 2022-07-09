NCRIC SecureAuth IdP
--------------------

NCRIC uses SecureAuth as its identity provider to authenticate users
against its internal Active Directory. It has configured SecureAuth
so that AstroMetrics users will enter through its own login page at
https://ncric.identity.secureauth.com/SecureAuth5/ (`SecureAuth5` is
bound to AstroMetrics). SecureAuth then performs a SAML POST request
to our Auth0 domain, where an Auth0 OAuth token will be issued and the
authenticated user redirected into the AstroMetrics app, bypassing our
login screen altogether.
