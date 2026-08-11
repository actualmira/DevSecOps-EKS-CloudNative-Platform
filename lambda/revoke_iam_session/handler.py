import boto3
import json
import logging
from datetime import datetime, timezone, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    finding = event.get("detail", {})
    finding_id = finding.get("id", "unknown")

    logger.info(f"Processing finding {finding_id}")

    access_key_details = finding.get("resource", {}).get("accessKeyDetails", {})
    principal_name = access_key_details.get("userName", "")
    principal_id = access_key_details.get("principalId", "")
    user_type = access_key_details.get("userType", "")
    access_key_id = access_key_details.get("accessKeyId", "")

    created_at = finding.get("createdAt", "")
    try:
        finding_time = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
        revocation_time = (finding_time - timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (ValueError, AttributeError):
        revocation_time = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    iam = boto3.client("iam")

    if user_type == "AssumedRole":
        try:
            iam.put_role_policy(
                RoleName=principal_name,
                PolicyName="RevokeCompromisedSessions",
                PolicyDocument=json.dumps({
                    "Version": "2012-10-17",
                    "Statement": [{
                        "Sid": "RevokeCompromisedSessions",
                        "Effect": "Deny",
                        "Action": "*",
                        "Resource": "*",
                        "Condition": {
                            "DateLessThan": {
                                "aws:TokenIssueTime": revocation_time
                            }
                        }
                    }]
                })
            )
            logger.info(f"Role sessions revoked for {principal_name} | tokens before {revocation_time} denied | finding={finding_id}")
            return {"status": "success"}
        except Exception as e:
            logger.error(f"Failed to revoke role sessions for {principal_name}: {str(e)}")
            raise

    if user_type == "IAMUser" and access_key_id:
        try:
            iam.update_access_key(
                UserName=principal_name,
                AccessKeyId=access_key_id,
                Status="Inactive"
            )
            logger.info(f"Access key {access_key_id} disabled for IAM user {principal_name} | finding={finding_id}")
            return {"status": "success"}
        except Exception as e:
            logger.error(f"Failed to disable access key for {principal_name}: {str(e)}")
            raise

    return {"status": "skipped", "reason": "no_actionable_principal", "finding_id": finding_id}
