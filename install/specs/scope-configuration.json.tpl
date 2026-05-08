{
  "name": "AWS Lambda",
  "description": "Scope-wide configuration for AWS Lambda scopes (placeholder image URI, OpenTofu state bucket, optional agent layer)",
  "category": "scope-configurations",
  "icon": "mdi:lambda",
  "visible_to": [
    "{{ env.Getenv "NRN" }}"
  ],
  "allow_dimensions": true,
  "schema": {
    "type": "object",
    "required": ["state", "deployment"],
    "properties": {
      "state": {
        "type": "object",
        "title": "OpenTofu state",
        "description": "Backend used by the create/delete workflows to persist per-scope OpenTofu state.",
        "required": ["tofu_state_bucket"],
        "properties": {
          "tofu_state_bucket": {
            "type": "string",
            "title": "OpenTofu state bucket",
            "description": "S3 bucket where per-scope OpenTofu state files are stored by the create/delete workflows. Can be shared across scope types — each scope writes under its own key prefix."
          }
        }
      },
      "deployment": {
        "type": "object",
        "title": "Deployment",
        "description": "Default Lambda image deployed when a scope is created. Replaced by the real application image on the first deployment.",
        "required": ["placeholder_image_uri"],
        "properties": {
          "placeholder_image_uri": {
            "type": "string",
            "title": "Placeholder image URI",
            "description": "ECR repository URI for the Lambda placeholder image (without arch suffix). The agent's resolve_placeholder_image script appends -arm64 / -amd64 based on scope.attributes.architecture."
          }
        }
      },
      "agent": {
        "type": "object",
        "title": "Nullplatform agent (optional)",
        "description": "Lambda layer ARN for the nullplatform agent runtime. Only needed when scope sets USE_NULL_AGENT=true.",
        "properties": {
          "null_agent_layer_arn": {
            "type": "string",
            "title": "Nullplatform agent Lambda layer ARN",
            "description": "Optional ARN of the nullplatform agent Lambda layer (e.g. arn:aws:lambda:us-east-1:123456789012:layer:nullplatform-agent:1)."
          }
        }
      }
    },
    "uiSchema": {
      "type": "VerticalLayout",
      "elements": [
        {
          "type": "Categorization",
          "elements": [
            {
              "type": "Category",
              "label": "State",
              "elements": [
                {
                  "type": "Label",
                  "text": "> **ℹ️ Agent IAM (IRSA)**\n\nThe nullplatform agent must run with an IAM role attached to its Kubernetes service account. The role needs `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, and `s3:ListBucket` on the state bucket below (and any per-scope key prefixes the workflow writes).",
                  "options": { "format": "markdown" }
                },
                {
                  "type": "Control",
                  "scope": "#/properties/state/properties/tofu_state_bucket"
                }
              ]
            },
            {
              "type": "Category",
              "label": "Deployment",
              "elements": [
                {
                  "type": "Label",
                  "text": "> **ℹ️ Placeholder image**\n\nThe placeholder image is the container the agent deploys as the initial Lambda when a scope is created; it's replaced with the real application image on the first deployment. Lambda doesn't support multi-arch manifest lists — push two images with `-arm64` / `-amd64` suffixes on top of the same base tag, and the agent picks the suffix based on `scope.attributes.architecture` (default `arm64`).\n\nSee `install/prerequisites.md` for the buildx push commands.",
                  "options": { "format": "markdown" }
                },
                {
                  "type": "Control",
                  "scope": "#/properties/deployment/properties/placeholder_image_uri"
                }
              ]
            },
            {
              "type": "Category",
              "label": "Agent (optional)",
              "elements": [
                {
                  "type": "Label",
                  "text": "Optional. Set this only if your Lambda functions opt into the nullplatform agent runtime (scope or app sets `USE_NULL_AGENT=true`). Leave empty otherwise.",
                  "options": { "format": "markdown" }
                },
                {
                  "type": "Control",
                  "scope": "#/properties/agent/properties/null_agent_layer_arn"
                }
              ]
            }
          ]
        }
      ]
    }
  }
}
