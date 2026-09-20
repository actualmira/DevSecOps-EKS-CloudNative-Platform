import json
import boto3
import urllib.request
import urllib.error
import os


def lambda_handler(event, context):
    """
    Triggered by EventBridge when SSM patch compliance
    finds NON COMPLIANT EKS nodes.

    """
    detail = event.get("detail", {})
    instance_id = detail.get("resource-id", "unknown")
    compliance_status = detail.get("compliance-status", "unknown")
    severity = detail.get("severity", "unknown")

    print(f"Instance {instance_id} is {compliance_status} - severity: {severity}")

    secret_arn = os.environ["GITHUB_SECRET_ARN"]
    region = os.environ["AWS_REGION_NAME"]
    github_org = os.environ["GITHUB_ORG"]
    github_repo = os.environ["GITHUB_REPO"]

    client = boto3.client("secretsmanager", region_name=region)

    try:
        response = client.get_secret_value(SecretId=secret_arn)
        secret = json.loads(response["SecretString"])
        github_token = secret["token"]
    except Exception as e:
        print(f"Failed to retrieve GitHub PAT: {e}")
        raise

    url = f"https://api.github.com/repos/{github_org}/{github_repo}/dispatches"

    payload = json.dumps({
        "event_type": "ssm-patch-noncompliant",
        "client_payload": {
            "instance_id": instance_id,
            "compliance_status": compliance_status,
            "severity": severity
        }
    }).encode("utf-8")

    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json",
        "X-GitHub-Api-Version": "2022-11-28"
    }

    req = urllib.request.Request(
        url, data=payload, headers=headers, method="POST"
    )

    try:
        with urllib.request.urlopen(req) as response:
            print(f"GitHub dispatch successful: {response.status}")
            return {
                "statusCode": 200,
                "body": "Rolling update triggered successfully"
            }
    except urllib.error.HTTPError as e:
        print(f"Response body: {e.read().decode()}")
        raise
