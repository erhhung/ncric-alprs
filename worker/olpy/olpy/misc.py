from auth0.v3.authentication import GetToken
from auth0.v3.exceptions import RateLimitError
import openlattice
import requests
import json
import os
import sys
import time
import random


def post_jira(username, password, summary, description="", project=None, assignee=None,
              issuetype="Task", points=1):
    """
    Posts a task to jira.
    """

    if assignee is None:
        assignee = username
    headers = {'Content-Type': 'application/json'}
    url = "https://jira.openlattice.com/rest/api/2/issue"
    data = {
        "fields": {
            "assignee": {
                "name": assignee
            },
            "project": {
                "key": "INTEGRATE"
            },
            "summary": summary,
            "description": description,
            "customfield_10119": points,  # storypoints
            "issuetype": {
                "name": issuetype
            }
        }
    }
    if not project is None:
        data['fields']['components'] = [{"name": project}]
    response = requests.post(url, headers=headers, data=json.dumps(data), auth=(username, password))
    return response


def get_jwt(username=None, password=None, client_id=None, base_url='http://datastore:8080'):
    """
    Gets the jwt token for a given usr/pw from a given url.
    """

    domain = 'maiveric.us.auth0.com'
    realm = 'Username-Password-Authentication'
    scope = 'openid email nickname roles user_id organizations'

    envvars = {
        'rundeck': {
            'user': os.environ.get("RD_OPTION_OL_USER"),
            "password": os.environ.get("RD_OPTION_OL_PASS"),
            "client_id": os.environ.get("RD_OPTION_CLIENT_ID")
        },
        'local_to_local': {
            'user': os.environ.get("ol_user"),
            "password": os.environ.get("ol_password"),
            "client_id": os.environ.get("ol_client_id_local")
        },
        'local_to_prod': {
            'user': os.environ.get("ol_user"),
            "password": os.environ.get("ol_password"),
            "client_id":  os.environ.get('ol_client_id')
        }
    }

    environment = os.environ
    if 'RD_JOB_ID' in environment:
        env = 'rundeck'
    else:
        env = 'local_to_prod' if 'astrometrics' in base_url else 'local_to_local'
    env = envvars[env]

    if username:
        env['user'] = username
    if password:
        env['password'] = password
    if client_id:
        env['client_id'] = client_id
    if 'datastore' in base_url or 'astrometrics' in base_url:
        base_url = f'https://{domain}/userinfo'

    if not (env['user'] and env['password'] and env['client_id']):
        raise ValueError("Not all necessary variables for authentication are present!")

    get_token = GetToken(domain)
    # Allow retries with exponential backoff (5, 10, 20,
    # 40 +/- 2 seconds) to accommodate rate limit errors
    tries = 0
    delay = 0
    token = None
    while not token:
        try:
            token = get_token.login(
                client_id=env['client_id'],
                client_secret="",
                username=env['user'],
                password=env['password'],
                scope=scope,
                realm=realm,
                audience=base_url,
                grant_type='http://auth0.com/oauth/grant-type/password-realm')

        except RateLimitError as e:
            tries += 1
            if tries == 10:
                msg = 'Giving up retrying Auth0 authentication!'
                print(msg, file=sys.stderr)
                raise e
            msg = f'{e.status_code} Auth0 {type(e).__name__}: {e.message}'
            print(msg, file=sys.stderr)
            # get next base backoff delay
            for backoff in 5, 10, 20, 40:
                if delay < backoff:
                    delay = backoff
                    break
            # prevent surge by adding +/- 2 seconds
            sleep = delay + random.randrange(-2, 3)
            msg = f'Retrying Auth0 authentication after {sleep} seconds...'
            print(msg, file=sys.stderr)
            time.sleep(sleep)
    return token['id_token']


def get_config(jwt=None, base_url='http://datastore:8080'):
    if not jwt:
        jwt = get_jwt(base_url=base_url)
    configuration = openlattice.Configuration()
    configuration.host = base_url
    configuration.access_token = jwt
    return configuration


def get_fqn_string(fullQualifiedName):
    return f'{fullQualifiedName.namespace}.{fullQualifiedName.name}'
