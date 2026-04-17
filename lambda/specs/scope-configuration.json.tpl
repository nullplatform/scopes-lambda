{
    "name": "AWS Lambda",
    "description": "Configuration for AWS Lambda (state backend, placeholder image, and agent layer)",
    "category": "scope-configurations",
    "icon": "np:aws-lambda",
    "visible_to": [
        "organization=1255165411"
    ],
    "allow_dimensions": false,
    "schema": {
        "type": "object",
        "required": [
            "state"
        ],
        "properties": {
            "agent": {
                "type": "object",
                "order": 3,
                "title": "Null Agent",
                "properties": {
                    "null_agent_layer_arn": {
                        "type": "string",
                        "title": "Lambda Layer ARN",
                        "description": "ARN of the nullplatform agent Lambda layer (required when USE_NULL_AGENT=true)"
                    }
                }
            },
            "state": {
                "type": "object",
                "order": 1,
                "title": "IaC State (OpenTofu)",
                "required": [
                    "tofu_state_bucket"
                ],
                "properties": {
                    "tofu_state_bucket": {
                        "type": "string",
                        "title": "State Bucket",
                        "description": "S3 bucket name used to store OpenTofu/Terraform state"
                    }
                }
            },
            "deployment": {
                "type": "object",
                "order": 2,
                "title": "Deployment",
                "properties": {
                    "placeholder_image_uri": {
                        "type": "string",
                        "title": "Placeholder Image URI",
                        "description": "ECR image URI used as the Lambda placeholder container during scope creation (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/my-repo/placeholder:latest)"
                    }
                }
            }
        }
    }
}