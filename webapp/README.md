## Debugging & Rebuilding

To debug the frontend app, SSH into the Bastion host and do the following:

```bash
# it's a good idea to make a backup of the originally
# deployed code with patches applied by /bootstrap.sh
$ cp -a ~/astrometrics ~/astrometrics.backup

# note that you'll have to git stash uncommitted code
# if you want to git pull or check out another branch
$ cd ~/astrometrics
~/astrometrics$ git st
On branch develop

Changes not staged for commit:
    modified:   config/auth/auth0.config.js
    modified:   config/webpack/webpack.config.base.js
    modified:   package-lock.json
    modified:   src/components/maintenance/UnderMaintenance.js
    modified:   src/containers/app/AppContainer.js
    modified:   src/containers/app/AppHeaderContainer.js
    modified:   src/containers/app/AppNavigationContainer.js
    modified:   src/containers/explore/ExploreNavigationContainer.js
    modified:   src/containers/parameters/SearchParameters.js
    modified:   src/containers/quality/QualityDashboard.js
    modified:   src/index.html
    modified:   src/index.js
    modified:   src/utils/constants/Constants.js
```

To build and deploy the webapp after making modifications, run the following:

```bash
(
cd ~/astrometrics
eval $(egrep "(ENV|MB_TOKEN)=\"" /bootstrap.sh | awk '{print $2}')
npm run build:$ENV -- --env.mapboxToken=$MB_TOKEN
rm -f build/favicon_v2.png
aws s3 sync build s3://$WEBAPP_BUCKET --no-progress
)
```

_**NOTE:** If you have redeployed multiple times within a short
period of time (a few minutes) and you don't see your changes,  
it's likely that CloudFront is still caching the previous build.
You may want to explicitly trigger a cache invalidation operation  
on the CloudFront distribution for the prefix "`/*`", wait until
it completes, and then reload your browser._
