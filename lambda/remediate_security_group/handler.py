import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SENSITIVE_PORTS = {22, 3306, 8200}


def lambda_handler(event, context):
    detail = event.get("detail", {})
    config_rule = detail.get("configRuleName", "unknown")
    group_id = detail.get("resourceId", "")
    region = event.get("region") or detail.get("awsRegion", "eu-west-1")

    logger.info(f"Config NON_COMPLIANT | rule={config_rule} | sg={group_id} | region={region}")

    if group_id:
        ec2 = boto3.client("ec2", region_name=region)

        try:
            response = ec2.describe_security_groups(GroupIds=[group_id])
            sgs = response.get("SecurityGroups", [])
            if not sgs:
                logger.warning(f"Security group {group_id} not found")
                return {"status": "skipped"}
            sg = sgs[0]
        except Exception as e:
            logger.error(f"Failed to describe security group {group_id}: {str(e)}")
            raise

        offending_rules = []
        for rule in sg.get("IpPermissions", []):
            if is_open_to_internet(rule) and targets_sensitive_port(rule):
                isolated = isolate_internet_ranges(rule)
                if isolated:
                    offending_rules.append(isolated)

        if offending_rules:
            try:
                ec2.revoke_security_group_ingress(
                    GroupId=group_id,
                    IpPermissions=offending_rules
                )
                logger.info(
                    f"Revoked internet access from {len(offending_rules)} rule(s) on "
                    f"{group_id} | rule={config_rule}"
                )
                return {"status": "success", "rules_revoked": len(offending_rules)}
            except Exception as e:
                logger.error(f"Failed to revoke rules from {group_id}: {str(e)}")
                raise

        logger.info(f"No offending rules found in {group_id}")
        return {"status": "skipped"}

    return {"status": "skipped"}


def is_open_to_internet(rule):
    ipv4_open = any(r.get("CidrIp") == "0.0.0.0/0" for r in rule.get("IpRanges", []))
    ipv6_open = any(r.get("CidrIpv6") == "::/0" for r in rule.get("Ipv6Ranges", []))
    return ipv4_open or ipv6_open


def targets_sensitive_port(rule):
    protocol = rule.get("IpProtocol", "")

    if protocol == "-1":
        return True

    from_port = rule.get("FromPort")
    to_port = rule.get("ToPort")

    if from_port is None or to_port is None:
        return False

    return any(from_port <= port <= to_port for port in SENSITIVE_PORTS)


def isolate_internet_ranges(rule):
    protocol = rule.get("IpProtocol", "")
    isolated = {"IpProtocol": protocol}

    if protocol != "-1":
        isolated["FromPort"] = rule.get("FromPort")
        isolated["ToPort"] = rule.get("ToPort")

    ipv4_offending = [
        {"CidrIp": r["CidrIp"]}
        for r in rule.get("IpRanges", [])
        if r.get("CidrIp") == "0.0.0.0/0"
    ]
    ipv6_offending = [
        {"CidrIpv6": r["CidrIpv6"]}
        for r in rule.get("Ipv6Ranges", [])
        if r.get("CidrIpv6") == "::/0"
    ]

    if not ipv4_offending and not ipv6_offending:
        return None

    if ipv4_offending:
        isolated["IpRanges"] = ipv4_offending
    if ipv6_offending:
        isolated["Ipv6Ranges"] = ipv6_offending

    return isolated
