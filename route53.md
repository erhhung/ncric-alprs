## Route 53 Configuration

The ALPRS commercial account is used to manage the astrometrics.us domain and its subdomain dev.astrometrics.us (two distinct hosted zones).  
dev.astrometrics.us is used to serve the DEV deployment (includes api.dev.astrometrics.us) while the primary domain is for PROD.  
These two hosted zones were created manually outside of Terraform, but all DNS records within the zones are managed by Terraform.

Instructions for creating a subdomain:
https://aws.amazon.com/premiumsupport/knowledge-center/create-subdomain-route-53/
