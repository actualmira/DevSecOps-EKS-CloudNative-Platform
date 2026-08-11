import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TRAIL_NAME = os.environ["CLOUDTRAIL_TRAIL_NAME"]


def lambda_handler(event, context):
    detail = event.get("detail", {})
    config_rule = detail.get("configRuleName", "unknown")
    resource_id = detail.get("resourceId", "unknown")
    region = event.get("region") or detail.get("awsRegion", "eu-west-1")

    logger.info(f"Config NON_COMPLIANT | rule={config_rule} | resource={resource_id} | region={region}")

    cloudtrail = boto3.client("cloudtrail", region_name=region)

    try:
        status = cloudtrail.get_trail_status(Name=TRAIL_NAME)

        if status["IsLogging"]:
            logger.info(f"Trail {TRAIL_NAME} is already logging")
            return {"status": "skipped"}

        cloudtrail.start_logging(Name=TRAIL_NAME)
        logger.info(f"Trail {TRAIL_NAME} re-enabled | rule={config_rule}")
        return {"status": "success"}

    except Exception as e:
        logger.error(f"Failed to re-enable trail {TRAIL_NAME}: {str(e)}")
        raise
